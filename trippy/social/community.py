"""The community's video knowledge: one organised record per indexed video, and what trip plans may use of it.

Two inputs, one shape:
* TikTok posts read once by the share pipeline (VideoIndex), plus everyone's quick takes (PlaceTakes).
* YouTube creator videos from the active Barcelona source dataset (timestamped, paraphrased creator claims).

What is published is derived information only: place names, categories, the creator's stance, our short
paraphrased claims with their timestamps, tips, and a link to the original. Transcripts and verbatim quotes are
never returned.
"""
from __future__ import annotations

import html
import json
import re
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path

ACTIVE_DATASET = ".local/stage3/planner-release-v1/active-dataset.json"
SOURCES_DIR = ".local/stage3/sources"

# One vocabulary for both platforms (the iOS app maps these to colours and symbols).
CATEGORY_TITLES = {
    "sights": "Sights", "food": "Food", "coffee": "Coffee", "bars": "Bars", "clubs": "Nightlife", "museums": "Museums",
    "outdoors": "Outdoors", "shopping": "Shopping", "stay": "Where to stay", "day_trips": "Day trips",
    "transport": "Getting around", "tickets": "Tickets", "budget_practical": "Money & practical",
    "events": "Events", "family_accessibility": "Family & access", "other": "Other",
}
TIKTOK_CATEGORY = {
    "Sights": "sights", "Food": "food", "Coffee": "coffee", "Brunch": "food", "Bars": "bars", "Groceries": "shopping",
    "Metro": "transport", "Other": "other", "Street food": "food", "Burger": "food", "Seafood": "food", "Vegan": "food",
    "Shopping": "shopping", "Local shops": "shopping", "Parks": "outdoors", "Clubs": "clubs",
}
# Planner categories (research_pipeline.canonical_category) per community category.
PLAN_CATEGORY = {
    "sights": "attraction", "museums": "museum", "food": "food", "coffee": "coffee", "bars": "nightlife",
    "clubs": "nightlife", "outdoors": "nature", "shopping": "shopping",
}
PLACE_KINDS = {"venue", "district", "dish", "route", "event", "chain"}
TIP_KINDS = {"advice", "transport_product", "ticket"}
TIP_DIMENSIONS = {"safety", "price", "budget", "booking", "queue", "tickets", "transport", "currency", "season",
                  "opening_hours", "accessibility", "duration"}
STANCES = {"recommended": "recommended", "mixed": "mixed", "negative": "avoid", "passing": "mentioned"}


def clock(seconds) -> str:
    seconds = int(float(seconds or 0))
    return f"{seconds // 3600}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}" if seconds >= 3600 else f"{seconds // 60}:{seconds % 60:02d}"


def _read(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def _slug(text):
    return re.sub(r"[^a-z0-9]+", "-", (text or "").casefold()).strip("-")


# ---------------------------------------------------------------- YouTube ---

def _youtube_metadata(root):
    """Title, channel, date and language per YouTube id, from the discovery files."""
    found = {}

    def walk(node):
        if isinstance(node, dict):
            if node.get("provider") == "youtube" and node.get("external_id") and node.get("title"):
                found.setdefault(node["external_id"], {
                    "title": html.unescape(node["title"]), "author": node.get("channel_title"), "published_at": node.get("published_at"),
                    "language": node.get("language_hint")})
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
    for path in sorted(Path(root, SOURCES_DIR).glob("*.json")):
        walk(_read(path))
    return found


def _first_second(record):
    times = [c.get("start_seconds") for claim in record.get("claims", []) for c in claim.get("citations", [])]
    times += [c.get("start_seconds") for c in record.get("citations", [])]
    times = [t for t in times if isinstance(t, (int, float))]
    return min(times) if times else None


def _moments(record, limit=6):
    """Each claim once, at its first citation time, as our paraphrase (never the transcript quote)."""
    out = []
    for claim in record.get("claims", []):
        starts = [c.get("start_seconds") for c in claim.get("citations", []) if isinstance(c.get("start_seconds"), (int, float))]
        if claim.get("value"):
            out.append((min(starts) if starts else 10**9, claim["value"].strip()))
    out.sort()
    return [{"at": clock(t) if t < 10**9 else "", "seconds": t if t < 10**9 else None, "text": text[:300]} for t, text in out[:limit]]


def youtube_videos(root, city="Barcelona", source="published"):
    """YouTube videos from the published copy (with map positions); source="dataset" rebuilds from the build dataset."""
    if source == "published":
        published = _read(Path(root) / PUBLISHED_YOUTUBE)
        if published:
            return [v for v in published.get("videos", []) if not city or v.get("city") == city]
    active = _read(Path(root) / ACTIVE_DATASET) or {}
    normalized = _read(Path(root) / active["normalized"]) if active.get("normalized") else None
    drafts = (normalized or {}).get("drafts", [])
    if not drafts:
        return []
    meta = _youtube_metadata(root)
    by_video = defaultdict(list)
    for record in drafts:
        source = record.get("source") or {}
        if source.get("provider") == "youtube" and source.get("external_id"):
            by_video[source["external_id"]].append(record)
    videos = []
    for video_id, records in by_video.items():
        info = meta.get(video_id, {})
        url = f"https://www.youtube.com/watch?v={video_id}"
        places, tips = [], []
        for record in sorted(records, key=lambda r: (_first_second(r) is None, _first_second(r) or 0)):
            categories = [c for c in record.get("categories", []) if c in CATEGORY_TITLES] or ["other"]
            stance = STANCES.get(record.get("stance"), "mentioned")
            moments = _moments(record)
            if record.get("kind") in PLACE_KINDS:
                opinion = next((c["value"] for c in record.get("claims", []) if c.get("basis") == "creator_opinion" and c.get("value")), None)
                places.append({
                    "id": record["id"][:24], "name": record["name"], "kind": record["kind"], "category": categories[0],
                    "categories": categories, "stance": stance, "first_hand": record.get("experience") == "first_hand_visit",
                    "summary": (opinion or (moments[0]["text"] if moments else ""))[:300], "moments": moments,
                    "at": moments[0]["at"] if moments else "", "seconds": moments[0]["seconds"] if moments else None,
                    "needs_check": bool(record.get("requires_current_check"))})
            if record.get("kind") in TIP_KINDS:
                for m in moments[:3]:
                    tips.append({"title": record["name"], "detail": m["text"], "at": m["at"], "seconds": m["seconds"], "category": categories[0]})
            elif record.get("kind") in {"city", "district"}:
                for claim in record.get("claims", []):
                    if claim.get("dimension") in TIP_DIMENSIONS and claim.get("value"):
                        start = min((c.get("start_seconds") for c in claim.get("citations", []) if isinstance(c.get("start_seconds"), (int, float))), default=None)
                        tips.append({"title": f"{record['name']}: {claim['dimension'].replace('_', ' ')}", "detail": claim["value"][:300],
                                     "at": clock(start) if start is not None else "", "seconds": start, "category": categories[0]})
        tips.sort(key=lambda t: (t["seconds"] is None, t["seconds"] or 0))
        videos.append(_finish({
            "key": f"youtube:{video_id}", "platform": "youtube", "url": url, "title": info.get("title") or "YouTube video",
            "author": info.get("author"), "published_at": info.get("published_at") or records[0].get("published_at"),
            "language": info.get("language"), "city": city, "country_code": "ES", "summary": None,
            "places": places, "tips": tips[:30]}))
    return videos


# ----------------------------------------------------------------- TikTok ---

def tiktok_videos(index_path, takes=None):
    if hasattr(index_path, "rows"):   # a VideoIndex, which may live in Postgres
        rows = index_path.rows()
    else:
        path = Path(index_path)
        if not path.is_file():
            return []
        with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
            rows = db.execute("SELECT key, result, indexed_at, readers FROM videos").fetchall()
    videos = []
    for key, raw, indexed_at, readers in rows:
        result = json.loads(raw)
        if result.get("relevant") is False:
            continue   # read once, found not to be about travel: kept only so nobody pays to read it again
        post_id = key.split(":", 1)[1] if key.startswith("tiktok:") else ""
        author = (result.get("source") or {}).get("author") or ""
        url = (result.get("source") or {}).get("url") or (f"https://www.tiktok.com/@{author}/video/{post_id}" if author and post_id
                                                         else f"https://m.tiktok.com/v/{post_id}.html" if post_id else "")
        places = []
        for index, place in enumerate(result.get("places") or []):
            google = place.get("google") or {}
            category = TIKTOK_CATEGORY.get(place.get("category"), "other")
            moments = [{"at": m.get("at", ""), "seconds": _seconds(m.get("at")), "text": m.get("text", "")} for m in place.get("moments") or []]
            places.append({
                "id": google.get("placeID") or f"{index}-{_slug(place.get('name'))}", "name": google.get("name") or place.get("name"),
                "kind": "venue", "category": category, "categories": [category], "stance": "recommended", "first_hand": True,
                "summary": place.get("tldr") or "", "moments": moments, "at": moments[0]["at"] if moments else "",
                "seconds": moments[0]["seconds"] if moments else None, "neighborhood": place.get("neighborhood"),
                "google_place_id": google.get("placeID"), "latitude": google.get("latitude"), "longitude": google.get("longitude"),
                "address": google.get("address"), "must_try": place.get("must_try") or [], "tips": (place.get("pro_tips") or [])[:4],
                "good_to_know": (place.get("good_to_know") or [])[:4], "price": place.get("price_hint"), "vibe": place.get("vibe_tags") or [],
                "when": place.get("when")})
        tips = [{"title": t.get("title", ""), "detail": t.get("detail", ""), "at": t.get("at", ""), "seconds": _seconds(t.get("at")),
                 "category": "budget_practical", "where": t.get("where") or "", "topics": t.get("topics") or [],
                 "when": t.get("when"), "audience": t.get("audience") or [], "cost": t.get("cost") or []}
                for t in result.get("tips") or []]
        video = _finish({"key": key, "platform": "tiktok", "url": url, "title": result.get("post_title") or "TikTok",
                         "author": author or None, "published_at": None, "language": None, "city": result.get("city") or "",
                         "country_code": result.get("country_code"), "summary": result.get("post_summary"),
                         "places": places, "tips": tips, "savers": readers, "indexed_at": indexed_at,
                         # What kind of guide it is and how wide (trippy/social/guides.py files it by these).
                         "relevant": result.get("relevant", True), "guide_types": result.get("guide_types") or [],
                         "theme": result.get("theme") or "", "scope": result.get("scope") or {},
                         "foods": result.get("foods") or [], "route": result.get("route")})
        if takes is not None:
            ids = [p["google_place_id"] for p in places if p.get("google_place_id")]
            summary = takes.summary(ids) if ids else {}
            for p in places:
                community = summary.get(p.get("google_place_id"))
                if community and community["voters"]:
                    p["takes"] = {k: community[k] for k in ("voters", "been", "got_in", "tags")}
        videos.append(video)
    return videos


def _fold(text):
    import unicodedata
    text = "".join(c for c in unicodedata.normalize("NFD", (text or "").casefold()) if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^\w]+", " ", text).split())


def _seconds(at):
    match = re.fullmatch(r"(?:(\d+):)?(\d+):(\d{2})", (at or "").strip())
    if not match:
        return None
    hours, minutes, seconds = match.groups()
    return int(hours or 0) * 3600 + int(minutes) * 60 + int(seconds)


def _finish(video):
    from .tip_index import annotate
    annotate(video)   # also sets video["when"] and each place's when   # topics, scope and stance on every tip (no model; see tip_index.py)
    counts = Counter(p["category"] for p in video["places"])
    counts.update(t["category"] for t in video["tips"])
    video["categories"] = [{"id": c, "title": CATEGORY_TITLES.get(c, c.title()), "count": n} for c, n in counts.most_common()]
    recommended = sum(p["stance"] == "recommended" for p in video["places"])
    video["counts"] = {"places": len(video["places"]), "recommended": recommended, "tips": len(video["tips"]),
                       "avoid": sum(p["stance"] == "avoid" for p in video["places"])}
    video["kind"] = "tips" if video["tips"] and not video["places"] else "mixed" if video["tips"] else "places"
    if not video.get("summary"):
        parts = [f"{len(video['places'])} places" if video["places"] else None, f"{len(video['tips'])} tips" if video["tips"] else None]
        top = ", ".join(c["title"].lower() for c in video["categories"][:3])
        video["summary"] = " · ".join(p for p in parts if p) + (f" — {top}" if top else "")
    return video


# ------------------------------------------------------------ The library ---

class CommunityVideos:
    """All indexed videos, cached until an input file changes."""

    def __init__(self, root, index_path, takes=None):
        # index_path: a VideoIndex (shared with the share pipeline) or the path of its SQLite file.
        self.root, self.index_path, self.takes = Path(root), index_path if hasattr(index_path, "rows") else Path(index_path), takes
        self._cache = (None, [])

    def _stamp(self):
        files = [self.root / ACTIVE_DATASET, self.root / PUBLISHED_YOUTUBE, *sorted((self.root / SOURCES_DIR).glob("*.json"))]
        stamp = tuple((str(f), f.stat().st_mtime_ns) for f in files if f.exists())
        index = self.index_path
        if hasattr(index, "version"):   # a VideoIndex (Postgres or SQLite): its own change marker
            return stamp + (("index", index.version()),)
        return stamp + tuple((str(index), index.stat().st_mtime_ns) for index in [Path(index)] if index.exists())

    def all(self):
        stamp = self._stamp()
        if self._cache[0] != stamp:
            videos = youtube_videos(self.root) + tiktok_videos(self.index_path, self.takes)
            videos.sort(key=lambda v: (-(v["counts"]["places"] + v["counts"]["tips"]), v["title"]))
            self._cache = (stamp, videos)
        return self._cache[1]

    def get(self, key):
        return next((v for v in self.all() if v["key"] == key), None)

    def for_place(self, google_id="", name="", city=""):
        """Every video that covers this shop: same Google place, or the same name in the same city."""
        wanted = _fold(name)
        out = []
        for v in self.all():
            for p in v["places"]:
                same_id = google_id and p.get("google_place_id") == google_id
                same_name = wanted and len(wanted) >= 3 and _fold(p["name"]) == wanted and (not city or v["city"].casefold() == city.casefold())
                if same_id or same_name:
                    out.append({k: v[k] for k in ("key", "platform", "url", "title", "author", "published_at", "city")}
                               | {"place": {k: p.get(k) for k in ("name", "stance", "summary", "moments", "at", "seconds", "must_try", "tips")}})
                    break
        out.sort(key=lambda item: (item["platform"] != "tiktok", item["title"]))
        return {"videos": out[:30]}

    def browse(self, city="", platform="", category="", query="", place="", area="", only="", sort="", bbox=None):
        """Search every video. query: title, creator, place names, tips. place: a shop/sight name. area: neighbourhood.
        only: "recommended" (has places the creator recommends) or "tips". sort: popular | newest | places | tips.
        bbox: (south, west, north, east) — videos with a mapped place inside it."""
        query, place_q, area_q = _fold(query), _fold(place), _fold(area)
        out = []
        for v in self.all():
            if city and v["city"].casefold() != city.casefold():
                continue
            if platform and v["platform"] != platform:
                continue
            if category and category not in {c["id"] for c in v["categories"]}:
                continue
            if only == "recommended" and not v["counts"]["recommended"]:
                continue
            if only == "tips" and not v["counts"]["tips"]:
                continue
            matched = []
            if place_q:
                matched = [p["name"] for p in v["places"] if place_q in _fold(p["name"])]
                if not matched:
                    continue
            if area_q and not any(area_q in _fold(p.get("neighborhood") or "") or area_q in _fold(p.get("address") or "")
                                  for p in v["places"]):
                continue
            if bbox and not any(_inside(p, bbox) for p in v["places"]):
                continue
            if query:
                text = " ".join([v["title"], v.get("author") or "", v.get("summary") or "", *(p["name"] for p in v["places"]),
                                 *(p.get("neighborhood") or "" for p in v["places"]), *(t["title"] for t in v["tips"])])
                if query not in _fold(text):
                    continue
                matched = matched or [p["name"] for p in v["places"] if query in _fold(p["name"])]
            out.append({k: v[k] for k in ("key", "platform", "url", "title", "author", "published_at", "city", "country_code",
                                          "summary", "kind", "categories", "counts")}
                       | {"top_places": list(dict.fromkeys(p["name"] for p in v["places"] if p["stance"] == "recommended"))[:4],
                          "matched_places": list(dict.fromkeys(matched))[:4], "savers": v.get("savers") or 0})
        order = {"newest": lambda x: (x["published_at"] or "") , "places": lambda x: x["counts"]["places"],
                 "tips": lambda x: x["counts"]["tips"]}.get(sort, lambda x: (x["savers"], x["counts"]["places"] + x["counts"]["tips"]))
        out.sort(key=order, reverse=True)
        all_videos = self.all()
        areas = Counter(p["neighborhood"] for v in all_videos if not city or v["city"].casefold() == city.casefold()
                        for p in v["places"] if p.get("neighborhood"))
        per_city = Counter(v["city"] for v in all_videos if v["city"])
        codes = {v["city"]: v.get("country_code") for v in all_videos if v["city"] and v.get("country_code")}
        return {"videos": out, "cities": sorted(per_city),
                # City cards: most-covered first, with a flag and a count.
                "city_stats": [{"name": c, "country_code": codes.get(c), "videos": n} for c, n in per_city.most_common()],
                "areas": [a for a, _ in areas.most_common(20)],
                "categories": [{"id": c, "title": t} for c, t in CATEGORY_TITLES.items()
                               if any(c in {x["id"] for x in v["categories"]} for v in all_videos)]}

    def map_places(self, city="", platform="", category="", bbox=None, limit=400):
        """One pin per place across every video (positions: the share pipeline or OpenStreetMap), with its videos."""
        pins = {}
        for v in self.all():
            if city and v["city"].casefold() != city.casefold():
                continue
            if platform and v["platform"] != platform:
                continue
            for p in v["places"]:
                if p.get("latitude") is None or p.get("longitude") is None:
                    continue
                if category and category not in (p.get("categories") or [p["category"]]):
                    continue
                if bbox and not _inside(p, bbox):
                    continue
                key = p.get("google_place_id") or f"{_fold(p['name'])}|{v['city'].casefold()}"
                pin = pins.setdefault(key, {"id": key[:80], "name": p["name"], "category": p["category"], "latitude": p["latitude"],
                                            "longitude": p["longitude"], "city": v["city"], "recommended": 0, "avoid": 0,
                                            "platforms": [], "videos": []})
                pin["recommended"] += p["stance"] == "recommended"
                pin["avoid"] += p["stance"] == "avoid"
                if v["platform"] not in pin["platforms"]:
                    pin["platforms"].append(v["platform"])
                if len(pin["videos"]) < 12:
                    pin["videos"].append({"key": v["key"], "platform": v["platform"], "title": v["title"], "author": v.get("author"),
                                          "summary": (p.get("summary") or "")[:200], "at": p.get("at") or "", "stance": p["stance"]})
        out = sorted(pins.values(), key=lambda pin: -len(pin["videos"]))[:limit]
        return {"places": out, "attribution": "Positions © OpenStreetMap contributors"
                if any(v["platform"] == "youtube" for v in self.all()) else ""}


def _inside(place, bbox):
    lat, lng = place.get("latitude"), place.get("longitude")
    if lat is None or lng is None:
        return False
    south, west, north, east = bbox
    return south <= lat <= north and west <= lng <= east


# ------------------------------------------------------ For trip planning ---

def place_verdict(takes_summary, min_voters=3):
    """'skip' when the community clearly says so; 'boost' when it clearly likes it; else None."""
    if not takes_summary or takes_summary.get("voters", 0) < min_voters:
        return None
    voters, tags, got_in = takes_summary["voters"], takes_summary.get("tags", {}), takes_summary.get("got_in", {})
    entries = sum(got_in.values())
    if entries >= min_voters and got_in.get("turned_away", 0) / entries > 0.5:
        return "skip"
    negative = tags.get("overhyped", 0) + tags.get("nothing_special", 0) + tags.get("mid", 0)
    if negative / voters > 0.5:
        return "skip"
    if tags.get("value_for_money", 0) / voters >= 0.4:
        return "boost"
    return None


def wanted_by_brief(place, takes_summary, preference_tags):
    """The user's own input decides what community knowledge is usable for this trip."""
    tags = set(t.casefold() for t in preference_tags or [])
    counts = (takes_summary or {}).get("tags", {})
    voters = max(1, (takes_summary or {}).get("voters", 0))
    if tags & {"budget", "cheap", "budget_practical", "low_budget"} and counts.get("expensive", 0) / voters > 0.5:
        return False
    if tags & {"traditional", "local", "authentic"} and counts.get("modern", 0) / voters > 0.6:
        return False
    if tags & {"modern", "trendy"} and counts.get("traditional", 0) / voters > 0.6:
        return False
    return True


def community_choice(brief):
    """('auto' | 'off' | 'picked', the ticked video keys): the traveller's choice of community knowledge for this trip."""
    choice = brief.get("community") or {}
    return choice.get("use", "auto"), set(choice.get("videos") or [])


def plan_sources(city, *, videos, limit=60):
    """The videos that could feed a plan for this city, for the app's "Use these videos" list.

    Nothing here costs a call: it counts what is already indexed. `usable` is the number of places a plan could
    actually use (real coordinates, and the creator recommended them or was mixed)."""
    wanted = (city or "").split(",")[0].strip().casefold()
    out, seen = [], {}
    for video in videos:
        if not wanted or video["city"].casefold() != wanted:
            continue
        usable = [p for p in video["places"] if p.get("latitude") is not None and p["stance"] in ("recommended", "mixed")
                  and PLAN_CATEGORY.get(p["category"])]
        if not usable:
            continue
        categories = Counter(PLAN_CATEGORY[p["category"]] for p in usable)
        for p in usable:
            seen[p.get("google_place_id") or _fold(p["name"])] = True
        out.append({"key": video["key"], "platform": video["platform"], "title": video["title"], "author": video.get("author"),
                    "url": video["url"], "usable": len(usable), "categories": dict(categories.most_common()),
                    "top_places": list(dict.fromkeys(p["name"] for p in usable))[:4], "savers": video.get("savers") or 0})
    out.sort(key=lambda v: (-v["usable"], v["title"]))
    return {"city": city, "videos": out[:limit], "places": len(seen)}


def plan_nodes(brief, *, videos, takes=None, plan_categories=(), limit=40):
    """Community library nodes for one trip (place_graph.library_graph's community_nodes).

    Only places with real coordinates, in a category the trip asked for, that the creator recommended, that the
    community has not clearly rejected, and that fit the user's preferences. Weight stays far below the user's
    own pins/saves (place_graph.WEIGHTS['community']).
    """
    city = (brief.get("destination") or "").split(",")[0].strip().casefold()
    wanted = set(plan_categories)
    excluded = set(brief.get("excluded_place_ids") or [])
    preference = brief.get("preference_tags") or []
    use, picked = community_choice(brief)
    if use == "off":
        return []
    from research_pipeline import trip_dates
    from .tags import when_matches
    try: dates = trip_dates(brief)
    except ValueError: dates = []
    nodes = []
    for video in videos:
        if video["city"].casefold() != city or (use == "picked" and video["key"] not in picked):
            continue
        ids = [p["google_place_id"] for p in video["places"] if p.get("google_place_id")]
        summaries = takes.summary(ids) if takes is not None and ids else {}
        chosen = []
        for p in video["places"]:
            if p.get("latitude") is None or p["stance"] not in ("recommended", "mixed"):
                continue
            # The time half of the scope: a Christmas market is not a stop on a July trip.
            if when_matches(p.get("when") or video.get("when"), dates) is False:
                continue
            # Only real venues can be a stop: a neighbourhood, a dish or a walking route is context, not a place to go.
            if p.get("kind") not in (None, "venue"):
                continue
            # A video the traveller ticked counts for everything it recommends, not only the trip's categories.
            category = PLAN_CATEGORY.get(p["category"])
            if category is None or (use != "picked" and category not in wanted) or p["id"] in excluded:
                continue
            community = summaries.get(p.get("google_place_id"))
            if place_verdict(community) == "skip" or not wanted_by_brief(p, community, preference):
                continue
            chosen.append({"id": p["id"][:200], "name": p["name"][:200], "address": (p.get("address") or None),
                           "category": PLAN_CATEGORY[p["category"]], "latitude": p["latitude"], "longitude": p["longitude"],
                           "provider_id": p.get("google_place_id"), "selected": True})
        if chosen:
            text = "\n".join(filter(None, [video["title"], video.get("summary"),
                                           *(f"{p['name']}: {p['summary']}" for p in video["places"] if p["name"] in {c['name'] for c in chosen})]))
            nodes.append({"id": "community:" + video["key"], "kind": "community", "published": True, "city": brief.get("destination", ""),
                          "url": video["url"] if video["url"].startswith("https://") else None, "text": text[:8000], "places": chosen,
                          "picked": use == "picked"})
        if sum(len(n["places"]) for n in nodes) >= limit:
            break
    return _one_place_once(nodes)


def _one_place_once(nodes):
    """The same sight named by five videos ("Casa Milà", "La Pedrera", "Κάζα Μιλά") is one place with five videos
    behind it. Places of one category within 120 m, or with the same name within 400 m, take one id, name and
    position: the commonest name, in Latin script when there is one."""
    groups = []
    for node in nodes:
        for place in node["places"]:
            spot = (place["latitude"], place["longitude"])
            for group in groups:
                if group["category"] != place["category"]:
                    continue
                apart = _km(group["spot"], spot) * 1000
                if apart <= 120 or (apart <= 400 and _fold(place["name"]) in group["names"]):
                    break
            else:
                group = {"category": place["category"], "spot": spot, "names": set(), "members": []}
                groups.append(group)
            group["names"].add(_fold(place["name"])); group["members"].append(place)
    for group in groups:
        counts = Counter(m["name"] for m in group["members"])
        name = max(counts, key=lambda n: (bool(re.search("[A-Za-z]", n)), counts[n], len(n), n))
        lead = next(m for m in group["members"] if m["name"] == name)
        for member in group["members"]:
            member.update(id=lead["id"], name=name, latitude=lead["latitude"], longitude=lead["longitude"],
                          address=lead.get("address"), provider_id=lead.get("provider_id"))
    for node in nodes:   # a video that named the place twice still counts once
        seen, kept = set(), []
        for place in node["places"]:
            if place["id"] not in seen:
                seen.add(place["id"]); kept.append(place)
        node["places"] = kept
    return nodes


def endorsed_nodes(root, brief, plan_categories=()):
    """YouTube creator venues already linked to catalog identities (planner/endorsements.py) as community nodes,
    so live providers get the same creator knowledge the local catalog provider already ranks with."""
    from trippy.planner.endorsements import load
    # The creators' combined picks are an "auto" source: off, or a hand-picked list, leaves them out.
    if community_choice(brief)[0] != "auto":
        return []
    city = (brief.get("destination") or "").split(",")[0].strip()
    try:
        data = load(root, city)
    except Exception:  # noqa: BLE001 - optional knowledge
        return []
    family_category = {"food": "food", "cafe": "coffee", "coffee": "coffee", "bar": "nightlife", "nightlife": "nightlife",
                       "museum": "museum", "attraction": "attraction", "landmark": "attraction", "sights": "attraction", "park": "nature",
                       "nature": "nature", "outdoors": "nature",
                       "shop": "shopping", "shopping": "shopping"}
    places = []
    for entity in data.get("entities", {}).values():
        category = family_category.get(entity.get("family"))
        if not category or category not in set(plan_categories) or entity.get("score", 0) <= 0:
            continue
        places.append({"id": entity["entity_id"][:200], "name": entity["catalog_name"][:200], "address": None, "category": category,
                       "latitude": entity["latitude"], "longitude": entity["longitude"], "selected": True})
    if not places:
        return []
    return [{"id": "community:youtube-creators", "kind": "community", "published": True, "city": brief.get("destination", ""),
             "url": None, "text": "Recommended by YouTube travel creators.", "places": places[:60]}]


# ------------------------------------------------- Published YouTube copy ---
# The YouTube dataset lives on the build machine (.local/stage3). The server reads this published copy instead:
# derived, paraphrased notes with timestamps and links only (no transcripts), plus OpenStreetMap positions.
PUBLISHED_YOUTUBE = "data/community/youtube.json"
CITY_CENTRES = {"Barcelona": (41.3874, 2.1686)}


def _km(a, b):
    import math
    dlat, dlng = math.radians(b[0] - a[0]), math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.sin(dlng / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def export_youtube(root, *, resolve=None, log=print):
    """Write the published YouTube copy, with OpenStreetMap coordinates for each venue when found."""
    videos = youtube_videos(root, source="dataset")
    if resolve is None:
        from trippy.planner.gemini_blend import osm_resolver
        resolve = osm_resolver(user_agent="Trippy/1.0 (community index build)")
    cache = {}
    for video in videos:
        for place in video["places"]:
            if place["kind"] not in {"venue", "district"}:
                continue
            key = _fold(place["name"])
            if key not in cache:
                try:
                    found = resolve(place["name"], video["city"] or "Barcelona", (41.3874, 2.1686))
                except Exception:  # noqa: BLE001 - a lookup failure just leaves the place off the map
                    found = None
                # A match far from the city centre is almost always a different place with the same name.
                near = found and _km((found["latitude"], found["longitude"]), CITY_CENTRES.get(video["city"] or "Barcelona", (41.3874, 2.1686))) <= 12
                cache[key] = (round(found["latitude"], 6), round(found["longitude"], 6)) if near else None
                log(f"{'✓' if cache[key] else '·'} {place['name']}")
            if cache[key]:
                place["latitude"], place["longitude"] = cache[key]
                place["position_source"] = "openstreetmap"
    target = Path(root) / PUBLISHED_YOUTUBE
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({"note": "Derived notes from public YouTube videos: paraphrased, timestamped, linked. "
                                          "Positions © OpenStreetMap contributors (ODbL).", "videos": videos},
                                 ensure_ascii=False, indent=0) + "\n")
    return videos


if __name__ == "__main__":
    import sys
    if "--export-youtube" in sys.argv:
        out = export_youtube(Path(__file__).resolve().parents[2])
        placed = sum(1 for v in out for p in v["places"] if p.get("latitude"))
        print(f"wrote {len(out)} videos, {placed} places with positions")
