"""Guides and tips, filed where they belong, so each one is found from every level it applies to.

Every read post (TikTok shares, creator YouTube videos) is one guide. Its scope says how wide it is (a venue, a
neighbourhood, a city, a named region like the Alps, a country, several countries, a continent) and which
countries it covers. A guide is listed at its own level and under every level above it: a Rome food list shows
under Rome, Italy and Europe; an Interrail route through Prague and Vienna shows under both countries and Europe.

Tips are pooled the same way: the tips for Rome are Rome's own, then Italy's, then Europe's, each said once.
Nothing here calls a model or a paid service; it reads what the video index already holds.
"""
from collections import Counter, defaultdict
import re
import unicodedata

CONTINENTS = {
    "Europe": "AD AL AT AX BA BE BG BY CH CY CZ DE DK EE ES FI FO FR GB GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK MT NL NO PL PT RO RS RU SE SI SK SM UA VA XK",
    "Asia": "AE AF AM AZ BD BH BN BT CN GE HK ID IL IN IQ IR JO JP KG KH KP KR KW KZ LA LB LK MM MN MO MV MY NP OM PH PK PS QA SA SG SY TH TJ TM TR TW UZ VN YE",
    "Africa": "AO BF BI BJ BW CD CF CG CI CM CV DJ DZ EG ER ET GA GH GM GN GQ GW KE KM LR LS LY MA MG ML MR MU MW MZ NA NE NG RW SC SD SL SN SO SS ST SZ TD TG TN TZ UG ZA ZM ZW",
    "North America": "AG AI AW BB BL BM BQ BS BZ CA CR CU CW DM DO GD GL GP GT HN HT JM KN KY LC MF MQ MS MX NI PA PM PR SV SX TC TT US VC VG VI",
    "South America": "AR BO BR CL CO EC FK GF GY PE PY SR UY VE",
    "Oceania": "AS AU CK FJ FM GU KI MH MP NC NF NR NU NZ PF PG PW SB TK TL TO TV VU WF WS",
}
CONTINENT_OF = {code: name for name, codes in CONTINENTS.items() for code in codes.split()}
TYPE_TITLES = {"must_see": "Not to miss", "hidden_spots": "Hidden spots", "foods": "Food to try", "route": "Routes and trips",
               "themed_list": "Lists", "city_guide": "City guides", "area_guide": "Neighbourhoods", "venue": "Single places", "tips": "Tips"}
LEVELS = ["place", "neighbourhood", "city", "region", "country", "multi_country", "continent"]


def fold(text):
    text = "".join(c for c in unicodedata.normalize("NFD", (text or "").casefold()) if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^\w]+", " ", text).split())


def country_name(code):
    try:
        import pycountry  # optional
        return pycountry.countries.get(alpha_2=code).name
    except Exception:  # noqa: BLE001
        return code


def guide_of(video):
    """One guide card from a community video (see community.tiktok_videos / youtube_videos)."""
    scope = video.get("scope") or {}
    countries = [c for c in scope.get("countries") or [] if c] or ([video["country_code"].upper()] if video.get("country_code") else [])
    types = list(video.get("guide_types") or [])
    if not types:   # creator videos and posts read before guide types existed
        if video.get("places"): types.append("city_guide" if len({p.get("neighborhood") for p in video["places"]}) > 1 else "area_guide")
        if video.get("tips"): types.append("tips")
    level = scope.get("level") or ("city" if video.get("city") else "country" if countries else "place")
    continents = sorted({CONTINENT_OF.get(c, "Other") for c in countries})
    return {"key": video["key"], "platform": video["platform"], "url": video["url"], "title": video["title"], "author": video.get("author"),
            "summary": video.get("summary") or "", "types": types, "theme": video.get("theme") or "",
            "level": level, "scope_name": scope.get("name") or video.get("city") or "", "region": scope.get("region") or "",
            # The time half of the scope (tags.py): "Christmas", "Summer", or None when it holds all year.
            "when": video.get("when") or scope.get("when"),
            "city": video.get("city") or "", "countries": countries, "continents": continents,
            "places": len(video.get("places") or []), "tips": len(video.get("tips") or []), "foods": len(video.get("foods") or []),
            "route_stops": len((video.get("route") or {}).get("stops") or []), "savers": video.get("savers") or 0}


def matches(guide, *, continent="", country="", region="", city=""):
    """Is the guide listed at this level? A wider guide is listed under every narrower level it covers."""
    if continent and continent not in guide["continents"]: return False
    if country and country.upper() not in guide["countries"]: return False
    if region and fold(region) not in (fold(guide["region"]), fold(guide["scope_name"])): return False
    if guide["region"] in CONTINENTS and guide["region"] not in guide["continents"]: guide["continents"].append(guide["region"])
    if city:
        # A city page lists the city's own guides and anything wider that covers its country.
        own = fold(guide["city"]) == fold(city) or fold(guide["scope_name"]) == fold(city)
        wider = LEVELS.index(guide["level"]) >= LEVELS.index("region") if guide["level"] in LEVELS else False
        if not (own or wider): return False
    return True


def browse(videos, *, continent="", country="", region="", city="", kind="", query=""):
    """Guides for one level, with the levels below it and the types present, for the Guides page."""
    guides = [guide_of(v) for v in videos if v.get("relevant", True) is not False]
    here = [g for g in guides if matches(g, continent=continent, country=country, region=region, city=city)]
    if query:
        q = fold(query)
        here = [g for g in here if q in fold(" ".join([g["title"], g["summary"], g["theme"], g["city"], g["scope_name"], g["region"], g["author"] or ""]))]
    types = Counter(t for g in here for t in g["types"])
    shown = [g for g in here if not kind or kind in g["types"]]
    # Closest first: a city's own guides before its country's, then the most saved.
    depth = {"place": 0, "neighbourhood": 1, "city": 2, "region": 3, "country": 4, "multi_country": 5, "continent": 6}
    shown.sort(key=lambda g: (depth.get(g["level"], 9) if city or country else 0, -g["savers"], -(g["places"] + g["tips"] + g["foods"]), g["title"]))
    below = Counter()
    for g in here:
        if not continent: below.update(g["continents"])
        elif not country: below.update(g["countries"])
        elif not city and g["city"]: below[g["city"]] += 1
    # Named regions (the Alps, the Balkans), not a continent repeated as a region.
    regions = Counter(g["region"] for g in here if g["region"] and not region and g["region"] not in CONTINENTS)
    return {"level": {"continent": continent, "country": country, "region": region, "city": city},
            "guides": shown[:80], "count": len(shown),
            "types": [{"id": t, "title": TYPE_TITLES.get(t, t), "count": n} for t, n in types.most_common()],
            "below": [{"name": name, "count": n} for name, n in below.most_common(30)],
            "regions": [{"name": name, "count": n} for name, n in regions.most_common(10)]}


def tips_for(videos, *, city="", country="", limit=40, topic="", dates=()):
    """Every tip that applies to a city: its own first, then its country's, then its continent's. Said once each.
    Each tip carries its scope (where and when it applies), topics and stance (tip_index.annotate); topic= keeps one
    topic, dates= (ISO days of a trip) drops tips for another time of year."""
    from .tags import when_matches
    from .tip_index import source_link, tip_scope, tip_topics, scope_label, stance_of
    country = country.upper()
    groups, seen = defaultdict(list), set()
    for video in videos:
        if video.get("relevant", True) is False: continue
        g = guide_of(video)
        if city and (fold(g["city"]) == fold(city) or fold(g["scope_name"]) == fold(city)): level = "city"
        elif country and country in g["countries"] and g["level"] in ("country", "region", "multi_country"): level = "country"
        elif country and CONTINENT_OF.get(country) in g["continents"] and g["level"] in ("multi_country", "continent"): level = "continent"
        else: continue
        for tip in video.get("tips") or []:
            key = fold(tip.get("title"))[:60]
            if not key or key in seen: continue
            topics = tip.get("topics") or tip_topics(tip)
            if topic and topic not in topics: continue
            if when_matches(tip.get("when"), dates) is False: continue
            seen.add(key)
            scope = tip.get("scope") or {**tip_scope(tip, video)}
            scope.setdefault("label", scope_label(scope))
            groups[level].append({"title": tip.get("title"), "detail": tip.get("detail"), "at": tip.get("at"),
                                  "topics": topics, "scope": scope, "when": tip.get("when"),
                                  "audience": tip.get("audience") or [], "cost": tip.get("cost") or [],
                                  "stance": tip.get("stance") or stance_of(f"{tip.get('title')}. {tip.get('detail')}"),
                                  "from": {"key": g["key"], "title": g["title"], "author": g["author"], "url": g["url"],
                                           "platform": g["platform"], "link": source_link(video, tip)}})
    titles = {"city": city or "This city", "country": country_name(country) if country else "This country",
              "continent": CONTINENT_OF.get(country, "")}
    return {"groups": [{"level": level, "title": titles[level], "tips": groups[level][:limit]} for level in ("city", "country", "continent") if groups[level]]}


def foods_for(videos, *, city="", country=""):
    """Dishes to try in a city or country, most mentioned first, with where people said to have them."""
    counts, details = Counter(), {}
    for video in videos:
        g = guide_of(video)
        if not ((city and fold(g["city"]) == fold(city)) or (country and country.upper() in g["countries"] and not city)): continue
        for food in video.get("foods") or []:
            key = fold(food.get("name"))
            if not key: continue
            counts[key] += 1
            details.setdefault(key, {"name": food["name"], "detail": food.get("detail") or "", "where": [], "from": []})
            if food.get("where") and food["where"] not in details[key]["where"]: details[key]["where"].append(food["where"])
            details[key]["from"].append(g["key"])
    return [{**details[k], "mentions": n} for k, n in counts.most_common(30)]
