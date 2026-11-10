"""Packs Natural Earth 1:50m country polygons (public domain) into the compact file the iOS globe reads.

    python3 -I scripts/build_globe_borders.py <ne_50m_admin_0_countries.geojson> ios/Trippy/Resources/globe-borders.bin

Layout (little endian): "TGB1", uint16 countries; per country: 2 ASCII bytes ISO code ("--" when none),
uint8 continent index, uint8 name length + UTF-8 name, uint16 rings; per ring: uint16 points, then
int16 longitude*100, int16 latitude*100 for each point.
"""
import json, struct, sys

CONTINENTS = ["Africa", "Antarctica", "Asia", "Europe", "North America", "Oceania", "South America", "Seven seas (open ocean)"]

def rings_of(geometry):
    polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
    for polygon in polygons:
        for ring in polygon:
            points = []
            for lon, lat in ring:
                q = (max(-18000, min(18000, round(lon * 100))), max(-9000, min(9000, round(lat * 100))))
                if not points or points[-1] != q:
                    points.append(q)
            if len(points) < 4:
                continue
            xs = [p[0] for p in points]; ys = [p[1] for p in points]
            if max(xs) - min(xs) < 3 and max(ys) - min(ys) < 3:
                continue
            yield points

def main(source, target):
    features = json.load(open(source, encoding="utf-8"))["features"]
    out = bytearray(b"TGB1") + struct.pack("<H", len(features))
    total = 0
    for feature in features:
        p = feature["properties"]
        code = p.get("ISO_A2_EH") or p.get("ISO_A2") or "--"
        if len(code) != 2 or not code.isalpha():
            code = "--"
        name = (p.get("NAME_LONG") or p.get("NAME") or "").encode("utf-8")[:255]
        continent = CONTINENTS.index(p["CONTINENT"]) if p.get("CONTINENT") in CONTINENTS else 255
        rings = list(rings_of(feature["geometry"]))
        out += code.encode("ascii") + struct.pack("<BB", continent, len(name)) + name + struct.pack("<H", len(rings))
        for ring in rings:
            out += struct.pack("<H", len(ring))
            for lon, lat in ring:
                out += struct.pack("<hh", lon, lat)
            total += len(ring)
    open(target, "wb").write(out)
    print(f"{len(features)} countries, {total} points, {len(out)} bytes")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
