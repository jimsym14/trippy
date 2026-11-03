"""Evidence-preserving source normalization. No AI classification or facts."""

from collections import Counter, defaultdict
from math import asin, cos, floor, isfinite, radians, sin, sqrt
import re
import unicodedata
from urllib.parse import urlparse
from uuid import UUID, uuid5

NAMESPACE = UUID("260bd14e-6ce5-4d73-9d21-61d99eb15f77")
QUOTAS = {"food": 170, "coffee": 90, "sights": 100, "outdoors": 65, "nightlife": 45, "shopping": 30}


def stable(key):
    return str(uuid5(NAMESPACE, key))


def normalize_text(text):
    decomposed = unicodedata.normalize("NFKD", text.casefold())
    plain = "".join(v for v in decomposed if not unicodedata.combining(v))
    return " ".join(re.findall(r"\w+", plain, re.UNICODE))


def family_for(category, hierarchy=()):
    """Reviewed deterministic taxonomy mapping; source category stays intact."""
    tokens = set(re.split(r"[^a-z0-9]+", " ".join([category, *hierarchy]).lower()))
    primary = set(re.split(r"[^a-z0-9]+",category.lower()))
    if primary & {"automotive","hardware","pharmacy","medical","wholesale","furniture","appliance","plumbing"}:
        return "other"
    if primary & {"store","shop","shopping","supermarket","grocery","market"} and not primary & {"restaurant","cafe","coffee","bakery"}:
        return "shopping"
    if tokens & {"cafe", "coffee", "tea", "bakery", "bakeries", "brunch"}:
        return "coffee"
    if tokens & {"nightclub", "nightclubs", "bar", "bars", "pub", "pubs", "nightlife", "cocktail"}:
        return "nightlife"
    if tokens & {"restaurant", "restaurants", "food", "dining", "pizza", "tapas", "seafood"}:
        return "food"
    if tokens & {"museum", "museums", "monument", "landmark", "landmarks", "attraction", "attractions",
                 "historic", "historical", "architecture", "art", "gallery", "galleries", "cathedral",
                 "castle", "palace", "theatre", "theater", "aquarium", "zoo", "cultural", "church", "basilica"}:
        return "sights"
    if tokens & {"park", "parks", "beach", "beaches", "garden", "gardens", "trail", "viewpoint", "nature", "hiking"}:
        return "outdoors"
    if tokens & {"hotel", "hotels", "hostel", "hostels", "lodging", "accommodation"}:
        return "stay"
    if tokens & {"shopping", "retail", "market", "markets", "store", "shops", "shop", "bookstore", "boutique"}:
        return "shopping"
    if tokens & {"airport", "station", "transit", "transportation", "transport"}:
        return "transport"
    return "other"


def safe_website(values):
    for value in values or []:
        if not isinstance(value, str) or len(value) > 2048:
            continue
        parsed = urlparse(value)
        if parsed.scheme in {"http", "https"} and parsed.hostname and not parsed.username and not parsed.password:
            return value
    return None


def normalize_feature(feature, bbox):
    if not isinstance(feature, dict) or feature.get("type") != "Feature":
        raise ValueError("invalid_feature")
    geometry = feature.get("geometry") or {}
    coordinates = geometry.get("coordinates", [])
    if geometry.get("type") != "Point" or len(coordinates) != 2:
        raise ValueError("not_a_point")
    x, y = coordinates
    if any(type(v) not in (int, float) or not isfinite(v) for v in (x, y)) or not (-180 <= x <= 180 and -90 <= y <= 90):
        raise ValueError("invalid_coordinates")
    if not (bbox[0] <= x <= bbox[2] and bbox[1] <= y <= bbox[3]):
        raise ValueError("outside_scope")
    properties = feature.get("properties") or {}
    external = properties.get("id")
    name = (properties.get("names") or {}).get("primary")
    if not isinstance(external, str) or not external.strip() or len(external) > 160:
        raise ValueError("missing_identity")
    if not isinstance(name, str) or not name.strip() or len(name) > 500:
        raise ValueError("missing_name")
    taxonomy = properties.get("taxonomy") or properties.get("categories") or {}
    category = taxonomy.get("primary") or properties.get("basic_category") or "unknown"
    if not isinstance(category, str) or len(category) > 200:
        raise ValueError("invalid_category")
    hierarchy = taxonomy.get("hierarchy") or []
    if not isinstance(hierarchy, list) or any(not isinstance(v, str) for v in hierarchy):
        raise ValueError("unsupported_taxonomy")
    source_datasets = {v.get("dataset") for v in (properties.get("sources") or []) if isinstance(v, dict)}
    # An explicit whitelist from the reviewed Places license guide. New source
    # names need review rather than silently inheriting another source's terms.
    permitted = {"meta", "Microsoft", "BrightQuery", "Foursquare", "AllThePlaces", "Krick", "DAC",
                 "PinMeTo", "Uberall", "Birdeye", "OpenTravel", "RenderSEO", "Overture"}
    if not source_datasets or not source_datasets.issubset(permitted):
        raise ValueError("source_policy_review_needed")
    if any(v.get("license") not in {None,"CDLA-Permissive-2.0","Apache-2.0","CC0-1.0"}
           for v in properties.get("sources") or [] if isinstance(v,dict)):
        raise ValueError("source_license_review_needed")
    confidence = properties.get("confidence")
    if confidence is not None and (type(confidence) not in (int, float) or not isfinite(confidence) or not 0 <= confidence <= 1):
        raise ValueError("invalid_confidence")
    addresses = properties.get("addresses") or []
    first_address = next((v for v in addresses if isinstance(v, dict)), {})
    country = first_address.get("country")
    if country and country != "ES":
        raise ValueError("wrong_country")
    address = first_address.get("freeform")
    locality = first_address.get("locality")
    address = address if isinstance(address, str) and len(address) <= 1500 else None
    locality = locality if isinstance(locality, str) and len(locality) <= 200 else None
    area_x = min(3, max(0, int((x - bbox[0]) / (bbox[2] - bbox[0]) * 4)))
    area_y = min(2, max(0, int((y - bbox[1]) / (bbox[3] - bbox[1]) * 3)))
    # These are pilot grid groups, never invented administrative neighborhoods.
    area_key = f"pilot_grid:{area_x}:{area_y}"
    names = properties.get("names") or {}
    aliases = list((names.get("common") or {}).values()) if isinstance(names.get("common"), dict) else []
    aliases = [v for v in aliases if isinstance(v, str) and len(v) <= 500]
    operating_status = properties.get("operating_status")
    if operating_status not in {None, "open", "temporarily_closed", "permanently_closed"}:
        raise ValueError("unknown_operating_status")
    return {"entity_id": stable("overture:" + external), "external_id": external,
        "name": name.strip(), "search_text": normalize_text(" ".join([name, *aliases])),
        "source_category": category, "family": family_for(category, hierarchy), "area_key": area_key,
        "latitude": y, "longitude": x, "address": address, "locality": locality,
        "website_url": safe_website(properties.get("websites")), "confidence": confidence,
        "operating_status": operating_status, "identity_status": "source_identity", "shortlist_rank": None,
        "source_properties": {"names": names, "taxonomy": taxonomy, "basic_category": properties.get("basic_category"),
            "sources": properties.get("sources"), "addresses": addresses, "websites": properties.get("websites"),
            "feature_version": properties.get("version")}}


def distance_m(first, second):
    p1, p2 = radians(float(first["latitude"])), radians(float(second["latitude"]))
    delta_lat = p2-p1
    delta_lon = radians(float(second["longitude"])-float(first["longitude"]))
    return 12742000 * asin(min(1, sqrt(sin(delta_lat/2)**2+cos(p1)*cos(p2)*sin(delta_lon/2)**2)))


def flag_duplicates(records, *, limit=2000):
    buckets, conflicts = defaultdict(list), []
    capped = False
    for record in sorted(records, key=lambda v: v["entity_id"]):
        name = normalize_text(record["name"])
        bx, by = floor(record["longitude"]/.0003), floor(record["latitude"]/.0003)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for previous in buckets[(name, bx+dx, by+dy)]:
                    metres = distance_m(record, previous)
                    if metres <= 20:
                        record["identity_status"] = previous["identity_status"] = "review_needed"
                        if len(conflicts) < limit:
                            pair = sorted([record["entity_id"], previous["entity_id"]])
                            conflicts.append({"first_entity_id": pair[0], "second_entity_id": pair[1],
                                "evidence": {"normalized_name_equal": True, "distance_m": round(metres, 2),
                                    "decision": "separate_source_ids_not_merged"}})
                        else:
                            capped = True
        buckets[(name, bx, by)].append(record)
    return conflicts, capped


def shortlist(records, *, target=500):
    """Diverse provisional candidates; no claim of AI enrichment/fit quality."""
    eligible = [v for v in records if v["family"] in QUOTAS and v["identity_status"] == "source_identity"
                and v["operating_status"] != "permanently_closed" and v["confidence"] != 0]
    grouped = defaultdict(list)
    for record in eligible:
        grouped[(record["family"], record["area_key"])].append(record)
    for values in grouped.values():
        values.sort(key=lambda v: (-(normalize_text(v.get("locality") or "") == "barcelona"),
            -(v["confidence"] if v["confidence"] is not None else -1), -bool(v["website_url"]), v["entity_id"]))
    selected, chosen = [], set()
    for family, quota in QUOTAS.items():
        areas = sorted(k for k in grouped if k[0] == family)
        count = 0
        while areas and count < quota and len(selected) < target:
            remaining = []
            for key in areas:
                if count >= quota or len(selected) >= target:
                    break
                if grouped[key]:
                    value = grouped[key].pop(0)
                    selected.append(value)
                    chosen.add(value["entity_id"])
                    count += 1
                if grouped[key]:
                    remaining.append(key)
            areas = remaining
    # Fill deficits with real remaining travel candidates, round-robin groups.
    groups = sorted(grouped)
    while groups and len(selected) < target:
        remaining = []
        for key in groups:
            if len(selected) >= target:
                break
            if grouped[key]:
                value = grouped[key].pop(0)
                if value["entity_id"] not in chosen:
                    selected.append(value)
                    chosen.add(value["entity_id"])
            if grouped[key]:
                remaining.append(key)
        groups = remaining
    for rank, record in enumerate(selected, 1):
        record["shortlist_rank"] = rank
    return {"target": target, "actual": len(selected), "by_family": dict(Counter(v["family"] for v in selected)),
            "quota_deficits": {k: max(0, q-sum(v["family"] == k for v in selected)) for k, q in QUOTAS.items()},
            "basis": "deterministic preliminary shortlist; no Luna calls or verified operational facts"}
