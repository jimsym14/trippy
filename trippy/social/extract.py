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
- confidence: 0–1 that this is a real, findable venue.
Leave a list empty rather than guessing. Also return post_title (short), post_summary (one sentence),
transcript (verbatim speech in its original language if audio or video was provided, else ""), and
unresolved: names mentioned that you could not confirm as venues.

Post URL: {url}
Author: {author}
{evidence}"""

_LIST = {"type": "ARRAY", "items": {"type": "STRING"}}
SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "post_title": {"type": "STRING"},
        "post_summary": {"type": "STRING"},
        "transcript": {"type": "STRING"},
        "city": {"type": "STRING"},
        "country": {"type": "STRING"},
        "country_code": {"type": "STRING"},
        "places": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
            "name": {"type": "STRING"}, "name_latin": {"type": "STRING"},
            "category": {"type": "STRING", "enum": CATEGORIES},
            "neighborhood": {"type": "STRING"}, "city": {"type": "STRING"}, "country": {"type": "STRING"},
            "country_code": {"type": "STRING"}, "address_hint": {"type": "STRING"}, "search_query": {"type": "STRING"},
            "vibe_tags": _LIST, "tldr": {"type": "STRING"}, "pro_tips": _LIST, "good_to_know": _LIST,
            "must_try": _LIST, "why_go": _LIST, "price_hint": {"type": "STRING"}, "evidence": _LIST,
            "confidence": {"type": "NUMBER"}},
            "required": ["name", "category", "search_query", "vibe_tags", "tldr", "pro_tips", "good_to_know",
                         "must_try", "why_go", "evidence", "confidence"]}},
        "unresolved": _LIST,
    },
    "required": ["post_title", "post_summary", "transcript", "city", "country", "places", "unresolved"],
}


def build_parts(source):
    """source: {url, author, evidence:[{origin,text}], images:[bytes jpeg], video:(mime, bytes)|None, audio:(mime, bytes)|None}"""
    lines = []
    for block in source.get("evidence", []):
        text = (block.get("text") or "").strip()
        if text:
            label = {"post_caption": "Caption", "on_screen_text": "On-screen text", "auto_caption": "Transcript (TikTok auto-captions)",
                     "slide_ocr": "Slide text (OCR)", "shared_text": "Shared text"}.get(block.get("origin"), block.get("origin", "Text"))
            lines.append(f"\n[{label}]\n{text[:20000]}")
    images = source.get("images") or []
    if images:
        lines.append(f"\n[{len(images)} slide images follow, in order: slide 1 … slide {len(images)}]")
    if source.get("video"):
        lines.append("\n[Video follows (1 frame per second, with sound) — read every place name, 📍 pin, address or price"
                     " drawn on the frames, and transcribe and use what is said]")
    elif source.get("audio"):
        lines.append("\n[Audio track follows — transcribe it and use what is said]")
    parts = [{"text": PROMPT.format(categories=", ".join(CATEGORIES), url=source.get("url") or "unknown",
                                    author=source.get("author") or "unknown", evidence="".join(lines) or "(no text)")}]
    for index, image in enumerate(images[:35], 1):
        parts += [{"text": f"slide {index}"}, inline(image[0], image[1]) if isinstance(image, tuple) else inline("image/jpeg", image)]
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
        if place.get("category") not in CATEGORIES:
            place["category"] = "Other"
        place["city"] = place.get("city") or result.get("city") or ""
        place["country"] = place.get("country") or result.get("country") or ""
        place["country_code"] = (place.get("country_code") or result.get("country_code") or "").upper()[:2]
        places.append(place)
    result["places"] = places
    return result


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

    def __init__(self, pool_factory, search=None, directory=None, clock=time.time, details=None):
        self._pool_factory = pool_factory
        self._pool = None
        self._search = search
        self._details = details
        self._jobs = {}
        self._order = []
        self._lock = threading.Condition()
        self._dir = Path(directory) if directory else None
        self._clock = clock
        if self._dir:
            self._dir.mkdir(parents=True, exist_ok=True)
        threading.Thread(target=self._run, daemon=True, name="social-extract").start()

    def submit(self, source_id, source):
        with self._lock:
            existing = self._jobs.get(source_id)
            if existing and existing["status"] in ("queued", "running", "ready"):
                return self.public(existing)
            job = {"job_id": source_id, "status": "queued", "submitted_at": self._clock(), "source": source}
            self._jobs[source_id] = job
            self._order.append(source_id)
            self._lock.notify()
            return self.public(job)

    def get(self, job_id):
        with self._lock:
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
                result = extract(self._pool, job["source"])
                if self._search:
                    enrich(result, self._search)
                    if self._details:
                        try:
                            refine(self._pool, result, self._details)
                        except GeminiUnavailable as error:
                            result["refine_error"] = str(error)[:200]  # the post-only cards are still good
                job.update(status="ready", result=result, finished_at=self._clock())
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
