"""Turn a shared post's evidence into Mio-style place cards, then pin them via Google Places.

Evidence: caption, on-screen text stickers, TikTok auto-captions, slide images and, for videos, a
shrunken copy of the video itself (frames + speech; audio-only when the video could not be prepared).
Gemini sees all of it in one request.
"""
from __future__ import annotations

import json
import threading
import time
import uuid
from pathlib import Path

from .gemini import GeminiPool, GeminiUnavailable, inline

CATEGORIES = ["Sights", "Food", "Coffee", "Brunch", "Bars", "Groceries", "Metro", "Other", "Street food",
              "Burger", "Seafood", "Vegan", "Shopping", "Local shops", "Parks", "Clubs"]

SYSTEM = """You turn a travel/food social post into place cards for a personal travel map.
Work only from the evidence given (caption, on-screen text, transcript, slide images, video, audio).
Every place the post recommends or names as a venue gets its own card, in the order it appears
(slideshows usually show one place per slide; the place name is often drawn on the image or
pinned with 📍; in videos, read the text drawn over the frames as carefully as you listen to the speech).
Do not invent places, dishes, prices or facts that the evidence does not support.
Some posts are not about venues at all but give travel tips (packing, scams, transport, etiquette, money,
booking hacks); keep those as tips. A post can have both.
Write card text in English, short and concrete, like a friend's notes. Keep proper names in their
original spelling; add the Latin-script name if the original is Greek or another script."""

PROMPT = """Return JSON for this post.

For each place:
- name: venue name as written; name_latin if the original is non-Latin.
- category: one of {categories}.
- neighborhood, city, country, country_code (ISO 3166-1 alpha-2): from the evidence; city/country can
  be inferred from the post as a whole (e.g. "#athensspots").
- address_hint: street address if shown or said.
- search_query: the best Google Maps text query to find exactly this venue ("<name>, <neighborhood>, <city>").
- vibe_tags: exactly 3 one-or-two-word adjectives (e.g. "Cozy", "Trendy", "Rooftop").
- tldr: one sentence, max 14 words, why this place is worth saving.
- pro_tips: practical advice (when to go, booking, what to order first, how to get in).
- good_to_know: caveats and facts (smoking, cash only, queues, closed days, price level).
- must_try: specific dishes/drinks named or shown.
- why_go: the reasons the creator gives.
- price_hint: e.g. "€10–15" only if stated.
- evidence: which inputs support this card, e.g. ["slide 3", "caption", "transcript", "on-screen text", "video 0:12", "audio"]
  (for text read off a video frame, give its timestamp as "video m:ss").
- moments: the timeline of this place in the post, in order: each {{at, text}} where "at" is "m:ss" for video
  (or "slide N" for slideshows, "caption" for the caption) and text is what was said or shown about the place
  at that moment (short, in English; quote the creator when it is punchy). Empty if there is no timing.
- confidence: 0–1 that this is a real, findable venue.
Also classify the post: post_kind = "places" (recommends venues), "tips" (general travel advice, no venue is
the point), or "mixed". For tips, return tips: each {{title, detail, at}} — a short headline, one or two
sentences of advice, and where it appears ("0:24", "slide 3", "caption").

relevant: true when the post helps someone plan or enjoy a trip or a day out (places, food, routes, tips,
costs, views). False for anything else (dance, fashion, news, ads unrelated to a place) — then leave every
list empty. Judge from everything given, never from the caption alone: many slideshows have an empty caption.
guide_types: every kind of guide this post is, from {guide_types}:
  venue = about one shop/restaurant/sight and what it has; area_guide = several places in one neighbourhood;
  city_guide = places across one city; themed_list = places that share a theme (cheap eats, date night,
  rooftops, smash burgers); route = a ready tour, trip, hike or itinerary that links places in order;
  hidden_spots = lesser-known places or views; must_see = places not to miss; tips = practical advice;
  foods = dishes or drinks to try.
theme: the theme in 2–4 words when it is a themed_list or route ("cheap eats", "date night", "Interrail"), else "".
scope: how wide the post is. level = place, neighbourhood, city, region, country, multi_country or continent;
  name = that place, neighbourhood, city, region, country or continent as written in English; region = the widest
  named area it belongs to when there is one ("Alps", "Balkans", "Amalfi Coast", "Europe"), else "";
  countries = ISO 3166-1 alpha-2 codes of every country it covers.
stated_count: how many places the post itself says it covers ("8 stops", "10 spots", "top 5"), else 0.
  Count every numbered stop or card you can see; if you find fewer than stated, look again at every frame.
foods: dishes or drinks the post says to try, each {{name, detail, where}} (where = the venue or city, if said).
route: only for a route — mode (walk, hike, train, car, bus, ferry, mixed), days (number, 0 if not said),
  cost_hint (as stated, else ""), and stops in order, each {{name, city, country_code, nights}} (nights 0 if not said).
Leave a list empty rather than guessing. Also return post_title (short), post_summary (one sentence),
transcript (verbatim speech in its original language if audio or video was provided, else ""), and
unresolved: names mentioned that you could not confirm as venues.

Post URL: {url}
Author: {author}
{evidence}"""

_LIST = {"type": "ARRAY", "items": {"type": "STRING"}}
_MOMENTS = {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {"at": {"type": "STRING"}, "text": {"type": "STRING"}},
                                       "required": ["at", "text"]}}
_TIPS = {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
    "title": {"type": "STRING"}, "detail": {"type": "STRING"}, "at": {"type": "STRING"}}, "required": ["title", "detail"]}}
POST_KINDS = ["places", "tips", "mixed"]
GUIDE_TYPES = ["venue", "area_guide", "city_guide", "themed_list", "route", "hidden_spots", "must_see", "tips", "foods"]
SCOPE_LEVELS = ["place", "neighbourhood", "city", "region", "country", "multi_country", "continent"]
ROUTE_MODES = ["walk", "hike", "train", "car", "bus", "ferry", "mixed"]
SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "post_title": {"type": "STRING"},
        "post_summary": {"type": "STRING"},
        "transcript": {"type": "STRING"},
        "city": {"type": "STRING"},
        "country": {"type": "STRING"},
        "country_code": {"type": "STRING"},
        "post_kind": {"type": "STRING", "enum": POST_KINDS},
        "relevant": {"type": "BOOLEAN"},
        "stated_count": {"type": "NUMBER"},
        "guide_types": {"type": "ARRAY", "items": {"type": "STRING", "enum": GUIDE_TYPES}},
        "theme": {"type": "STRING"},
        "scope": {"type": "OBJECT", "properties": {"level": {"type": "STRING", "enum": SCOPE_LEVELS}, "name": {"type": "STRING"},
                                                   "region": {"type": "STRING"}, "countries": _LIST}, "required": ["level", "name"]},
        "foods": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {"name": {"type": "STRING"}, "detail": {"type": "STRING"},
                                                                             "where": {"type": "STRING"}}, "required": ["name"]}},
        "route": {"type": "OBJECT", "properties": {
            "mode": {"type": "STRING", "enum": ROUTE_MODES}, "days": {"type": "NUMBER"}, "cost_hint": {"type": "STRING"},
            "stops": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
                "name": {"type": "STRING"}, "city": {"type": "STRING"}, "country_code": {"type": "STRING"}, "nights": {"type": "NUMBER"}},
                "required": ["name"]}}}},
        "tips": _TIPS,
        "places": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
            "name": {"type": "STRING"}, "name_latin": {"type": "STRING"},
            "category": {"type": "STRING", "enum": CATEGORIES},
            "neighborhood": {"type": "STRING"}, "city": {"type": "STRING"}, "country": {"type": "STRING"},
            "country_code": {"type": "STRING"}, "address_hint": {"type": "STRING"}, "search_query": {"type": "STRING"},
            "vibe_tags": _LIST, "tldr": {"type": "STRING"}, "pro_tips": _LIST, "good_to_know": _LIST,
            "must_try": _LIST, "why_go": _LIST, "price_hint": {"type": "STRING"}, "evidence": _LIST,
            "moments": _MOMENTS, "confidence": {"type": "NUMBER"}},
            "required": ["name", "category", "search_query", "vibe_tags", "tldr", "pro_tips", "good_to_know",
                         "must_try", "why_go", "evidence", "confidence"]}},
        "unresolved": _LIST,
    },
    "required": ["post_title", "post_summary", "transcript", "city", "country", "post_kind", "relevant", "guide_types", "scope",
                 "tips", "places", "unresolved"],
}


def build_parts(source):
    """source: {url, author, evidence:[{origin,text}], images:[bytes jpeg], video:(mime, bytes)|None, audio:(mime, bytes)|None}"""
    lines = []
    for block in source.get("evidence", []):
        text = (block.get("text") or "").strip()
        if text:
            label = {"post_caption": "Caption", "on_screen_text": "On-screen text", "auto_caption": "Transcript (TikTok auto-captions)",
                     "frame_text": "Text the phone read on the frames, by time (may have small misreadings; the frames are the truth)",
                     "slide_ocr": "Slide text (OCR)", "shared_text": "Shared text"}.get(block.get("origin"), block.get("origin", "Text"))
            lines.append(f"\n[{label}]\n{text[:20000]}")
    if source.get("sound") == "music":
        lines.append("\n[Sound: music only, nobody speaks. Ignore any lyrics; the places are in the text and frames.]")
    elif source.get("sound") == "mixed":
        lines.append("\n[Sound: someone speaks over music. Use what is said; ignore song lyrics.]")
    images = source.get("images") or []
    frame_times = source.get("frame_times") or []
    if images and frame_times:
        lines.append(f"\n[{len(images)} frames from the video follow, in order, each labelled with its time — read every place"
                     " name, number, 📍 pin or address drawn on them]")
    elif images:
        lines.append(f"\n[{len(images)} slide images follow, in order: slide 1 … slide {len(images)}]")
    if source.get("video"):
        lines.append("\n[Video follows (1 frame per second, with sound) — read every place name, 📍 pin, address or price"
                     " drawn on the frames, and transcribe and use what is said]")
    elif source.get("audio"):
        lines.append("\n[Audio track follows — transcribe it and use what is said]")
    parts = [{"text": PROMPT.format(categories=", ".join(CATEGORIES), guide_types=", ".join(GUIDE_TYPES), url=source.get("url") or "unknown",
                                    author=source.get("author") or "unknown", evidence="".join(lines) or "(no text)")}]
    def clock(seconds):
        return f"{int(seconds) // 60}:{int(seconds) % 60:02d}"
    for index, image in enumerate(images[:35], 1):
        label = f"video {clock(frame_times[index - 1])}" if index - 1 < len(frame_times) else f"slide {index}"
        parts += [{"text": label}, inline(image[0], image[1]) if isinstance(image, tuple) else inline("image/jpeg", image)]
    if source.get("video"):
        mime, data = source["video"]
        parts.append(inline(mime, data))
    elif source.get("audio"):
        mime, data = source["audio"]
        parts.append(inline(mime, data))
    return parts


def clean(result):
    """Drop empty/low-confidence cards and normalise lists so the app can trust the shape."""
    places, seen = [], set()
    for place in result.get("places") or []:
        name = (place.get("name") or "").strip()
        key = name.casefold()
        if not name or key in seen or float(place.get("confidence") or 0) < 0.35:
            continue
        seen.add(key)
        for field in ("vibe_tags", "pro_tips", "good_to_know", "must_try", "why_go", "evidence"):
            place[field] = [str(x).strip() for x in place.get(field) or [] if str(x).strip()][:8]
        place["vibe_tags"] = place["vibe_tags"][:3]
        place["moments"] = [{"at": str(m.get("at") or "").strip()[:20], "text": str(m.get("text") or "").strip()[:300]}
                            for m in place.get("moments") or [] if isinstance(m, dict) and str(m.get("text") or "").strip()][:12]
        if place.get("category") not in CATEGORIES:
            place["category"] = "Other"
        place["city"] = place.get("city") or result.get("city") or ""
        place["country"] = place.get("country") or result.get("country") or ""
        place["country_code"] = (place.get("country_code") or result.get("country_code") or "").upper()[:2]
        places.append(place)
    result["places"] = places
    result["tips"] = [{"title": str(t.get("title") or "").strip()[:120], "detail": str(t.get("detail") or "").strip()[:500],
                       "at": str(t.get("at") or "").strip()[:20]}
                      for t in result.get("tips") or [] if isinstance(t, dict) and str(t.get("title") or "").strip()][:20]
    kind = result.get("post_kind")
    if kind not in POST_KINDS:
        kind = "mixed" if places and result["tips"] else "tips" if result["tips"] else "places"
    if kind == "tips" and places:
        kind = "mixed"
    result["post_kind"] = kind
    try: stated = max(0, int(result.get("stated_count") or 0))
    except (TypeError, ValueError): stated = 0
    result["stated_count"] = stated
    # "8 stops" in the post and fewer found: say so, so the read can be repeated with more to look at.
    result["incomplete"] = bool(stated and len(places) < stated)
    # Off-topic posts keep nothing, so nothing gets pinned or written into notes.
    result["relevant"] = result.get("relevant") is not False
    if not result["relevant"]:
        result.update(places=[], tips=[], foods=[], route=None, guide_types=[])
    types = [t for t in dict.fromkeys(result.get("guide_types") or []) if t in GUIDE_TYPES]
    if result["relevant"]:
        # What the content shows wins over a missing label.
        if result["tips"] and "tips" not in types: types.append("tips")
        if len(places) == 1 and not types: types.append("venue")
    result["guide_types"] = types
    result["theme"] = str(result.get("theme") or "").strip()[:60]
    scope = result.get("scope") if isinstance(result.get("scope"), dict) else {}
    level = scope.get("level") if scope.get("level") in SCOPE_LEVELS else ("city" if result.get("city") else "place")
    countries = [str(c).strip().upper()[:2] for c in scope.get("countries") or [] if len(str(c).strip()) == 2]
    if not countries and result.get("country_code"):
        countries = [str(result["country_code"]).upper()[:2]]
    if not countries:   # the places know their country even when the post-level answer left it out
        countries = [p["country_code"] for p in places if p.get("country_code")]
    # A region is a short proper name ("Alps", "Amalfi Coast"); anything that reads like a sentence is dropped.
    region = str(scope.get("region") or "").strip()
    if len(region.split()) > 4 or any(ch in region for ch in ",;:()") or "-level" in region or "scope" in region.lower():
        region = ""
    result["scope"] = {"level": level, "name": str(scope.get("name") or result.get("city") or result.get("country") or "").strip()[:80],
                       "region": region[:60], "countries": list(dict.fromkeys(countries))[:20]}
    result["foods"] = [{"name": str(f.get("name") or "").strip()[:80], "detail": str(f.get("detail") or "").strip()[:240],
                        "where": str(f.get("where") or "").strip()[:80]}
                       for f in result.get("foods") or [] if isinstance(f, dict) and str(f.get("name") or "").strip()][:20]
    route = result.get("route") if isinstance(result.get("route"), dict) else None
    stops = [{"name": str(s.get("name") or "").strip()[:80], "city": str(s.get("city") or "").strip()[:60],
              "country_code": str(s.get("country_code") or "").strip().upper()[:2], "nights": int(s.get("nights") or 0)}
             for s in (route or {}).get("stops") or [] if isinstance(s, dict) and str(s.get("name") or "").strip()][:30]
    result["route"] = ({"mode": route.get("mode") if route.get("mode") in ROUTE_MODES else "mixed", "days": int(route.get("days") or 0),
                        "cost_hint": str(route.get("cost_hint") or "").strip()[:80], "stops": stops}
                       if route and stops and "route" in types else None)
    return result


# ----------------------------------------------------- What the read saw ---
# A video read from its caption alone misses everything drawn on the frames (a walking route's eight numbered
# stops, say). Each read records what it was given, and a thin one is never final: the next save that brings the
# video, or frames, or a "read again", replaces it.

MEDIA_RANK = {"none": 0, "audio": 1, "frames": 2, "images": 2, "video": 3}


def media_of(source):
    """What visual or sound evidence a read had: video, frames, slide images, audio or none."""
    if source.get("video"): kind = "video"
    elif source.get("frame_times") and source.get("images"): kind = "frames"
    elif source.get("images"): kind = "images"
    elif source.get("audio"): kind = "audio"
    else: kind = "none"
    return {"kind": kind, "count": len(source.get("images") or []), "note": str(source.get("media_note") or "")[:120],
            "sound": str(source.get("sound") or "")[:10],
            "expects_video": bool(source.get("expects_video"))}


def is_thin(result):
    """A read that can't be trusted to be complete: a video read without its frames or sound, or one that
    found fewer places than the post itself says it has. Reads stored before this was recorded are judged by
    their places: one place or none, known only from the caption or speech."""
    if not result or result.get("relevant") is False:
        return False
    media = result.get("media")
    if media:
        return (media.get("expects_video") and media.get("kind") in ("none", "audio")) or bool(result.get("incomplete"))
    places = result.get("places") or []
    textual = {"caption", "transcript", "on-screen text", "audio"}
    return len(places) <= 1 and not result.get("tips") and all(set(p.get("evidence") or []) <= textual for p in places)


def richer(source, result):
    """Would reading this upload see more than the stored read did?"""
    old = (result or {}).get("media") or {"kind": "none"}
    new = media_of(source)
    return MEDIA_RANK[new["kind"]] > MEDIA_RANK.get(old.get("kind"), 0) or (new["kind"] == old.get("kind") and new["count"] > old.get("count", 0))


def server_video(url, reader_factory=None):
    """Last try when the phone could send nothing to look at: fetch and shrink the video here (needs ffmpeg)."""
    import shutil
    if not url or not shutil.which("ffmpeg"):
        return None
    try:
        from .tiktok import Reader
        reader = (reader_factory or Reader)()
        reader.read(url, max_slides=0)
        return reader.video()
    except Exception:  # noqa: BLE001 - best effort; the caption read still happens and is marked thin
        return None


# ----------------------------------------------------------- Is it travel? ---
# A shared post is read only when it helps a trip. The caption alone can't say (slideshows often have none), so
# the free text the phone already has (caption, stickers, slide OCR, captions) is checked first; only when that
# text can't tell either way does a tiny text-and-cover call decide, before the full read of the video.

_TRAVEL = ["📍", "🗺", "✈", "🍝", "🍕", "🍷", "☕", "🏛", "🏖", "travel", "trip", "itinerary", "guide", "spots", "places", "visit", "hidden",
           "must see", "must-see", "don't miss", "dont miss", "eat", "food", "restaurant", "cafe", "café", "bar", "brunch", "bakery",
           "hike", "beach", "view", "sunset", "museum", "tour", "interrail", "train", "flight", "hotel", "airbnb", "budget", "cheap",
           "tips", "where to", "things to do", "date night", "rooftop", "taverna", "trattoria", "ταξίδ", "ταξιδ", "φαγητ", "μαγαζ",
           "εστιατ", "καφε", "καφέ", "μπαρ", "θέα", "θεα", "βόλτα", "βολτα", "παραλ", "πεζοπορ", "αξιοθέατ", "αξιοθεατ", "εκδρομ",
           "viaggio", "ristorante", "viaje", "restaurante", "voyage", "reise"]
_OFF = ["grwm", "get ready with me", "outfit", "makeup", "skincare", "dance challenge", "#dance", "lip sync", "lipsync",
        "gameplay", "fortnite", "minecraft", "crypto", "stock tips", "workout", "gym", "unboxing", "asmr", "prank", "meme"]


def looks_like_travel(texts, *, place_names=()):
    """"yes", "no" or "unsure" from free text alone. "no" needs real text that is clearly about something else."""
    text = " ".join(t for t in texts if t).casefold()
    words = len(text.split())
    hits = sum(word in text for word in _TRAVEL) + sum(1 for name in place_names if name and name.casefold() in text)
    off = sum(word in text for word in _OFF)
    if hits >= 2 or (hits >= 1 and not off):
        return "yes"
    if off and not hits and words >= 4:
        return "no"
    return "unsure"


TRIAGE_SCHEMA = {"type": "OBJECT", "properties": {"relevant": {"type": "BOOLEAN"}, "why": {"type": "STRING"}}, "required": ["relevant"]}


def triage(pool, source):
    """True/False from a tiny call: the text plus at most two images (the cover and first slide). About a
    hundredth of a full video read. Any failure says True, so a post is never lost to the gate."""
    texts = [b.get("text") or "" for b in source.get("evidence") or []]
    verdict = looks_like_travel(texts)
    if verdict != "unsure":
        return verdict == "yes", "text"
    parts = [{"text": "Is this social post useful for planning a trip or a day out (places, food, routes, travel tips, costs, views)? "
                      "Judge from the text and images together.\n\n" + "\n".join(t[:2000] for t in texts if t.strip())[:6000]}]
    for image in (source.get("images") or [])[:2]:
        parts.append(inline(image[0], image[1]) if isinstance(image, tuple) else inline("image/jpeg", image))
    try:
        answer, _ = pool.generate(parts, schema=TRIAGE_SCHEMA, system="Answer briefly.", thinking_budget=0)
        return answer.get("relevant") is not False, "model"
    except Exception:  # noqa: BLE001 - when in doubt, read it
        return True, "error"


def extract(pool: GeminiPool, source):
    result, model = pool.generate(build_parts(source), schema=SCHEMA, system=SYSTEM)
    result = clean(result)
    result["model"] = model
    return result


def enrich(result, search):
    """search(query) -> list of Google Places hits ({placeID,name,address,latitude,longitude,primaryType,city,countryCode,rating?})."""
    for place in result.get("places", []):
        queries = [place.get("search_query"), ", ".join(filter(None, [place.get("name_latin") or place.get("name"), place.get("neighborhood"), place.get("city")]))]
        for query in dict.fromkeys(q for q in queries if q):
            try:
                hits = search(query)
            except Exception as error:  # noqa: BLE001 - enrichment is best effort
                place["match_error"] = type(error).__name__
                continue
            if hits:
                hit = hits[0]
                if place.get("country_code") and hit.get("countryCode") and hit["countryCode"].upper() != place["country_code"]:
                    continue
                place["google"] = {k: hit.get(k) for k in ("placeID", "name", "address", "latitude", "longitude", "primaryType", "city", "countryCode")}
                break
    return result


REFINE_SYSTEM = """You polish place cards for a personal travel map using two sources: what a social post said,
and Google Maps data with recent reviews for the matched venue. The post is the primary source.
Reviews add practical knowledge (booking, queues, smoking, cash, noise, best dishes, best time).
Only add facts that are specific and supported by at least one review; never add generic praise."""

REFINE_PROMPT = """For each card below, return an improved version.
- neighborhood: from the Google address if the card lacks one.
- tldr: one plain sentence (max 14 words) a friend would say; combine the post's angle with what the place is.
- vibe_tags: exactly 3 adjectives the post and reviews agree on.
- pro_tips, good_to_know, must_try, why_go: keep every item from the post, then add at most 3 new items per list
  from the reviews (short, concrete, e.g. "Book ahead on weekends", "People smoke inside", "Try the pistachio pasta").
- from_reviews: copy exactly the items you added from reviews.
Return {{"places": [...]}} with one entry per card, same order, each with "index".

{cards}"""

_REFINED = {"type": "OBJECT", "properties": {"places": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
    "index": {"type": "INTEGER"}, "neighborhood": {"type": "STRING"}, "tldr": {"type": "STRING"}, "vibe_tags": _LIST,
    "pro_tips": _LIST, "good_to_know": _LIST, "must_try": _LIST, "why_go": _LIST, "from_reviews": _LIST},
    "required": ["index", "tldr", "vibe_tags", "pro_tips", "good_to_know", "must_try", "why_go", "from_reviews"]}}},
    "required": ["places"]}


def refine(pool, result, details):
    """details(place_id) -> {summary, rating, reviewCount, primaryType, address, openingHours, reviews:[{rating,text}]}"""
    cards = []
    for index, place in enumerate(result.get("places", [])):
        google = place.get("google") or {}
        if not google.get("placeID"):
            continue
        try:
            facts = details(google["placeID"]) or {}
        except Exception as error:  # noqa: BLE001 - best effort
            place["details_error"] = type(error).__name__
            continue
        place["google"].update({k: facts.get(k) for k in ("rating", "reviewCount", "primaryType", "address", "openingHours") if facts.get(k)})
        reviews = [f"({r.get('rating')}★) {r.get('text', '')[:700]}" for r in facts.get("reviews") or [] if r.get("text")]
        card = {k: place.get(k) for k in ("name", "category", "neighborhood", "city", "tldr", "vibe_tags", "pro_tips", "good_to_know", "must_try", "why_go")}
        cards.append((index, f"### Card {index}\nPost card: {json.dumps(card, ensure_ascii=False)}\nGoogle: {facts.get('primaryType', '')}, "
                             f"{facts.get('address', '')}, rating {facts.get('rating')} ({facts.get('reviewCount')} reviews). "
                             f"Summary: {facts.get('summary', '')}\nReviews:\n" + "\n".join(reviews[:5])))
    if not cards:
        return result
    improved, model = pool.generate([{"text": REFINE_PROMPT.format(cards="\n\n".join(text for _, text in cards))}],
                                    schema=_REFINED, system=REFINE_SYSTEM)
    for update in improved.get("places") or []:
        index = update.get("index")
        if not isinstance(index, int) or not 0 <= index < len(result["places"]):
            continue
        place = result["places"][index]
        if update.get("neighborhood") and not place.get("neighborhood"):
            place["neighborhood"] = update["neighborhood"]
        if update.get("tldr"):
            place["tldr"] = update["tldr"].strip()
        if len(update.get("vibe_tags") or []) >= 3:
            place["vibe_tags"] = [t.strip() for t in update["vibe_tags"][:3]]
        for field in ("pro_tips", "good_to_know", "must_try", "why_go"):
            merged = list(dict.fromkeys([*(place.get(field) or []), *[str(x).strip() for x in update.get(field) or [] if str(x).strip()]]))
            place[field] = merged[:10]
        place["from_reviews"] = [x for x in update.get("from_reviews") or [] if x]
        if place["from_reviews"] and "Google reviews" not in place["evidence"]:
            place["evidence"].append("Google reviews")
    result["refine_model"] = model
    return result


class ExtractionQueue:
    """One worker thread; jobs persist as JSON so a restart can report them (not re-run them)."""

    def __init__(self, pool_factory, search=None, directory=None, clock=time.time, details=None, index=None, takes=None):
        self._pool_factory = pool_factory
        self._pool = None
        self._search = search
        self._details = details
        self._index = index  # VideoIndex: one Gemini read per post, shared by every saver
        self._takes = takes  # PlaceTakes: which places each post covers, for the community view
        self._aliases = {}   # source_id -> job_id of the first saver of the same post while it is being read
        self._jobs = {}
        self._order = []
        self._lock = threading.Condition()
        self._dir = Path(directory) if directory else None
        self._clock = clock
        if self._dir:
            self._dir.mkdir(parents=True, exist_ok=True)
        threading.Thread(target=self._run, daemon=True, name="social-extract").start()

    def cached(self, video_key):
        return self._index.get(video_key) if self._index and video_key else None

    def final(self, video_key):
        """The stored read, when it is good enough to hand out without reading again."""
        hit = self.cached(video_key)
        return hit if hit is not None and not is_thin(hit) else None

    def submit(self, source_id, source, video_key="", reread=False):
        with self._lock:
            hit = self.cached(video_key)
            # A thin stored read (or a "read again") is replaced when this upload can see more than it did.
            if hit is not None and source is not None and (is_thin(hit) or reread) and richer(source, hit):
                hit = None
            if hit is not None:
                # Already read for someone: hand over the same result, no Gemini call, no Places call.
                self._index.count_reader(video_key)
                job = {"job_id": source_id, "status": "ready", "result": hit, "cached": True,
                       "submitted_at": self._clock(), "finished_at": self._clock(), "video_key": video_key}
                self._jobs[source_id] = job
                return self.public(job)
            if video_key:
                for other in self._jobs.values():
                    if other.get("video_key") == video_key and other["status"] in ("queued", "running") and other["job_id"] != source_id:
                        self._aliases[source_id] = other["job_id"]
                        view = self.public(other)
                        view["job_id"] = source_id
                        return view
            existing = self._jobs.get(source_id)
            if existing and existing["status"] in ("queued", "running", "ready"):
                return self.public(existing)
            job = {"job_id": source_id, "status": "queued", "submitted_at": self._clock(), "source": source, "video_key": video_key}
            self._jobs[source_id] = job
            self._order.append(source_id)
            self._lock.notify()
            return self.public(job)

    def get(self, job_id):
        with self._lock:
            alias = self._aliases.get(job_id)
            if alias and alias in self._jobs:
                view = self.public(self._jobs[alias])
                view["job_id"] = job_id
                if view["status"] == "ready":
                    view["cached"] = True
                return view
            job = self._jobs.get(job_id)
            if job:
                return self.public(job)
        if self._dir and (self._dir / f"{job_id}.json").is_file():
            return json.loads((self._dir / f"{job_id}.json").read_text())
        return None

    def public(self, job):
        view = {k: v for k, v in job.items() if k != "source"}
        if job["status"] == "queued":
            view["position"] = self._order.index(job["job_id"]) + 1 if job["job_id"] in self._order else 0
        return view

    def _run(self):
        while True:
            with self._lock:
                while not self._order:
                    self._lock.wait()
                job = self._jobs[self._order[0]]
                job["status"] = "running"
            try:
                if self._pool is None:
                    self._pool = self._pool_factory()
                source = job["source"]
                if source.get("expects_video") and media_of(source)["kind"] in ("none", "audio"):
                    fetched = server_video(source.get("url"))
                    if fetched:
                        source["video"] = fetched
                        source["media_note"] = (source.get("media_note") or "") + " · fetched by the server"
                relevant, judged_by = triage(self._pool, job["source"])
                if not relevant:
                    # Not travel: no full read, no place lookups, and the verdict is kept for the next saver.
                    result = clean({"post_title": "Not a travel post", "post_summary": "", "transcript": "", "city": "", "country": "",
                                    "post_kind": "places", "relevant": False, "guide_types": [], "scope": {}, "tips": [], "places": [],
                                    "unresolved": []})
                    result["triaged_by"] = judged_by
                else:
                    result = extract(self._pool, job["source"])
                if self._search and result.get("places"):
                    enrich(result, self._search)
                    if self._details:
                        try:
                            refine(self._pool, result, self._details)
                        except GeminiUnavailable as error:
                            result["refine_error"] = str(error)[:200]  # the post-only cards are still good
                source = job.get("source") or {}
                result["source"] = {"url": source.get("url") or "", "author": source.get("author") or ""}
                result["media"] = media_of(source)
                result["thin"] = is_thin(result)
                job.update(status="ready", result=result, finished_at=self._clock())
                if self._index and job.get("video_key"):
                    self._index.put(job["video_key"], result)
                    if self._takes:
                        self._takes.add_video(job["video_key"], result.get("places"))
            except GeminiUnavailable as error:
                if error.retry_at and error.retry_at - self._clock() < 6 * 3600:
                    # Every free model is parked: wait for the first to free up, keep the job queued.
                    job.update(status="queued", waiting_until=error.retry_at, note="Waiting for free Gemini quota")
                    with self._lock:
                        self._lock.wait(timeout=max(5, error.retry_at - self._clock()))
                    continue
                job.update(status="failed", error=str(error)[:400])
            except Exception as error:  # noqa: BLE001
                job.update(status="failed", error=f"{type(error).__name__}: {str(error)[:300]}")
            with self._lock:
                if self._order and self._order[0] == job["job_id"]:
                    self._order.pop(0)
                job.pop("source", None)
            if self._dir:
                (self._dir / f"{job['job_id']}.json").write_text(json.dumps(self.public(job), ensure_ascii=False))
