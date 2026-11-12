"""Community tips that reach a trip plan: what each tip is about, where it applies, and which stops it touches.

Every tip from an indexed video (TikTok reads, YouTube creator notes) gets:
* topics  – what it is about (beach, nightlife, transport, safety, prices, queues, ...). New TikTok reads name them
            inside the one extraction call that already happens; older reads and YouTube notes fall back to the
            keyword map below. No model call, ever.
* scope   – where it applies: the video's own scope (a city, a country, a region) unless the tip narrows it
            ("Barceloneta: safety" is about Barceloneta, not all of Barcelona).
* stance  – "warning" when it tells people to avoid, skip or watch out, else "tip".

`plan_tips` then matches a finished plan (its city, the traveller's picks and the scheduled stops) against that
index: a Barcelona plan with beaches gets the creator who says to skip the city beaches, next to the beach stop or,
when no beach made it into the days, at the top of the plan. Everything here is string work over what is indexed.
"""
from __future__ import annotations

import re
import zlib
from collections import defaultdict

from .guides import CONTINENT_OF, country_name, fold
from .tags import clean_when, dated, facets, when_matches, when_of

# id -> (title, keywords). A keyword ending in * matches any word starting with it; others match the word and its
# plural. Matching runs on folded text (lower case, no accents), so Greek keywords are written without tonos.
TOPICS = {
    "beach": ("Beaches", "beach* platja platges playa* seaside coastal swim* sunbath* παραλ* θαλασσ* κολυμπ*"),
    "nightlife": ("Nightlife", "nightlife club* clubbing bar pub disco* party parties cocktail* late night going out ποτο* μπαρ"),
    "food": ("Food", "food* restaurant* eat eating dinner* lunch* tapas paella dish* menu* breakfast meal* φαγητ* εστιατ* ταβερν*"),
    "coffee": ("Coffee", "coffee cafe brunch bakery bakeries καφε*"),
    "transport": ("Getting around", "metro bus buses train* taxi* uber cab tram* transport* airport cable car funicular bike* "
                                    "bicycle* cycling scooter* t casual travel card on foot μετρο λεωφορ* ταξι"),
    "safety": ("Safety", "safe safety pickpocket* thief thieves theft steal* stolen rob robbed robber* scam* mugg* "
                         "κλεφτ* κλεψ* ασφαλ* πορτοφολ*"),
    "prices": ("Money", "price* cost* cheap* expensive* budget* money cash euro* pay paying for free tax* overpriced afford* "
                        "tipping τιμ* ακριβ* φθην*"),
    "queues": ("Queues & crowds", "queue* long line* in line crowd* waiting wait time busy peak hour* rush hour* go early ουρα* κοσμο*"),
    "tickets": ("Tickets & booking", "ticket* booking book ahead book online reservation* reserve* in advance skip the line sold out "
                                     "εισιτηρ* κρατησ*"),
    "season": ("Weather & season", "season* summer winter spring autumn weather rain* heat hot temperature* july august sunscreen "
                                   "καλοκαιρ* χειμων* καιρ*"),
    "sights": ("Sights", "sight* sightseeing monument* landmark* cathedral* church* basilica* architect* palace* old town "
                         "αξιοθεατ* μνημει* εκκλησ*"),
    "museums": ("Museums", "museum* galler* exhibition* μουσει*"),
    "outdoors": ("Parks & views", "park* hike* hiking hill* garden* viewpoint* view* panoram* sunset* nature mountain* πεζοπορ* θεα"),
    "shopping": ("Shopping", "shop* market* souvenir* mall* boutique* αγορ*"),
    "day_trips": ("Day trips", "day trip* excursion* out of town outside the city εκδρομ*"),
    "etiquette": ("Local customs", "etiquette dress code custom* siesta greet* polite rude locals tipping"),
}
TOPIC_TITLES = {topic: title for topic, (title, _) in TOPICS.items()}
# Useful for any trip in the city, whatever its days hold.
PRACTICAL = {"safety", "transport", "prices", "queues", "tickets", "season", "etiquette"}
# Too wide to pin to one stop on their own (every plan has sights and food); they match at trip level, or a stop by name.
BROAD = {"sights", "food", "coffee", "outdoors", "museums", "shopping"}

# Community categories (community.CATEGORY_TITLES) and planner categories (research_pipeline.canonical_category).
CATEGORY_TOPICS = {"sights": "sights", "attraction": "sights", "museums": "museums", "museum": "museums", "food": "food",
                   "coffee": "coffee", "bars": "nightlife", "bar": "nightlife", "clubs": "nightlife", "club": "nightlife",
                   "nightlife": "nightlife", "outdoors": "outdoors", "nature": "outdoors", "shopping": "shopping",
                   "transport": "transport", "tickets": "tickets", "day_trips": "day_trips", "excursion": "day_trips"}
# The "<place>: <dimension>" titles YouTube city/district notes carry (community.TIP_DIMENSIONS).
DIMENSION_TOPICS = {"safety": "safety", "price": "prices", "budget": "prices", "currency": "prices", "booking": "tickets",
                    "tickets": "tickets", "queue": "queues", "transport": "transport", "season": "season",
                    "opening hours": "tickets", "accessibility": None, "duration": None}
_REGION_WORDS = {"costa", "coast", "island", "islands", "isla", "illes", "valley", "mountains", "region", "province", "riviera", "peninsula"}
_WARNING = re.compile(r"\b((?<!to )avoid\w*|skip\w*|don ?t|do not|dont|never|not worth\w*|overrated|over ?priced|tourist trap\w*|beware|"
                      r"watch out|careful|instead|rather than|better than|nicer than|than spend\w*|not for|not recommend\w*|waste of|dirty|"
                      r"pickpocket\w*|scam\w*|thie\w+|αποφυγ\w*|προσοχ\w*|μην)\b")


def _keywords():
    # Each keyword is its own alternative; phrases ("cable car", "day trip*") are kept whole.
    compiled = {}
    for topic, (_, words) in TOPICS.items():
        alternatives = []
        for chunk in _split(words):
            alternatives.append(re.escape(chunk[:-1]) + r"\w*" if chunk.endswith("*") else re.escape(chunk) + r"(?:s|es)?\b")
        compiled[topic] = re.compile(r"\b(?:" + "|".join(alternatives) + ")")
    return compiled


_PHRASES = {"cable car", "t casual", "travel card", "on foot", "for free", "long line*", "in line", "wait time", "peak hour*",
            "rush hour*", "go early", "book ahead", "book online", "in advance", "skip the line", "sold out", "old town",
            "day trip*", "out of town", "outside the city", "dress code", "late night", "going out"}


def _split(words):
    """Keywords in order, with the known phrases kept whole."""
    out, tokens, i = [], words.split(), 0
    while i < len(tokens):
        for size in (3, 2):
            phrase = " ".join(tokens[i:i + size])
            if phrase in _PHRASES:
                out.append(phrase); i += size; break
        else:
            out.append(tokens[i]); i += 1
    return out


_KEYWORDS = _keywords()


def topics_of(text):
    """Topics a piece of free text is about, from the keyword map (the fallback for reads without topics)."""
    folded = fold(text)
    return [topic for topic, pattern in _KEYWORDS.items() if pattern.search(folded)] if folded else []


def stance_of(text):
    return "warning" if _WARNING.search(fold(text)) else "tip"


def _dimension(title):
    """('Gothic Quarter', 'tickets') for a YouTube "<place>: <dimension>" title, else (None, None)."""
    head, sep, tail = (title or "").rpartition(":")
    tail = tail.strip().casefold()
    if sep and head.strip() and tail in DIMENSION_TOPICS:
        return head.strip(), tail
    return None, None


def tip_topics(tip):
    """Topics named by the read itself, then the YouTube dimension or category, then keywords."""
    found = [t for t in tip.get("topics") or [] if t in TOPICS]
    place, dimension = _dimension(tip.get("title"))
    if dimension:
        if DIMENSION_TOPICS.get(dimension): found.append(DIMENSION_TOPICS[dimension])
    elif CATEGORY_TOPICS.get(tip.get("category")):
        found.append(CATEGORY_TOPICS[tip["category"]])
    found += topics_of(f"{tip.get('title') or ''}. {tip.get('detail') or ''}")
    return list(dict.fromkeys(found))


def main_topics(tip):
    """What the tip is mainly about: topics the read named, its title's, or its YouTube dimension — not a word in passing."""
    found = [t for t in tip.get("topics") or [] if t in TOPICS] if tip.get("main_topics") is None else list(tip["main_topics"])
    found += topics_of(tip.get("title"))
    dimension = _dimension(tip.get("title"))[1]
    if DIMENSION_TOPICS.get(dimension): found.append(DIMENSION_TOPICS[dimension])
    return list(dict.fromkeys(found))


def video_scope(video):
    """The video's own scope, filled in for creator videos and older reads that never had one."""
    scope = dict(video.get("scope") or {})
    city = video.get("city") or ""
    countries = [c for c in scope.get("countries") or [] if c] or ([video["country_code"].upper()] if video.get("country_code") else [])
    level = scope.get("level") or ("city" if city else "country" if countries else "place")
    name = scope.get("name") or city or (country_name(countries[0]) if countries else "")
    return {"level": level, "name": name, "region": scope.get("region") or "", "countries": countries, "city": city}


def tip_scope(tip, video):
    """Where a tip applies: what it narrows itself to ("where", or the place in a "<place>: <dimension>" title),
    else the whole video's scope."""
    base = video_scope(video)
    where = (tip.get("where") or "").strip() or (_dimension(tip.get("title"))[0] or "")
    if not where or fold(where) in (fold(base["name"]), fold(base["city"])):
        return base
    city = base["city"] if base["level"] in ("place", "neighbourhood", "city") else ""
    words = set(fold(where).split())
    if base["city"] and fold(where) == fold(base["city"]):
        level = "city"
    elif words & _REGION_WORDS:
        level = "region"
    else:
        level = "neighbourhood" if city else base["level"]
    return {**base, "level": level, "name": where[:80], "city": city}


def scope_label(scope):
    name, city = scope.get("name") or "", scope.get("city") or ""
    if scope.get("level") in ("place", "neighbourhood") and city and fold(city) != fold(name):
        return f"{name}, {city}"
    if scope.get("level") == "continent" or (not name and scope.get("countries")):
        return name or CONTINENT_OF.get(scope["countries"][0], "")
    return name


def annotate(video):
    """Tag every tip and place of a community video (community._finish calls this): topics, scope (where + when),
    stance, audience and cost. What the read named wins; older reads use the keyword fallback (tags.py)."""
    country = (video_scope(video)["countries"] or [""])[0]
    said = clean_when((video.get("scope") or {}).get("when"))
    video["when"] = said or when_of(f"{video.get('title') or ''}. {video.get('summary') or ''}. {video.get('theme') or ''}", country)
    for place in video.get("places") or []:
        place["when"] = (clean_when(place.get("when")) or when_of(" ".join([place.get("name") or "", place.get("summary") or "",
                                                                          *(place.get("tips") or [])]), country) or video["when"])
    for tip in video.get("tips") or []:
        tip.update(facets(tip, f"{tip.get('title') or ''}. {tip.get('detail') or ''}", country=country, inherit={"when": video["when"]}))
        tip["main_topics"] = main_topics(tip)
        tip["topics"] = tip_topics(tip)
        tip["scope"] = tip_scope(tip, video)
        tip["scope"]["label"] = scope_label(tip["scope"])
        tip["scope"]["when"] = tip["when"]
        tip["stance"] = tip.get("stance") if tip.get("stance") in ("warning", "tip") else stance_of(f"{tip.get('title')}. {tip.get('detail')}")
    return video


def source_link(video, tip):
    """The video, at the tip's moment when the platform supports a start time."""
    url = video.get("url") or ""
    seconds = tip.get("seconds")
    if url and seconds and video.get("platform") == "youtube":
        return f"{url}{'&' if '?' in url else '?'}t={int(seconds)}s"
    return url or None


# ---------------------------------------------------------------- The plan ---

def _stops(result):
    """(day number, date, place) for every scheduled stop, in plan order."""
    places = {p.get("id"): p for p in result.get("places") or []}
    out = []
    for number, day in enumerate((result.get("itinerary") or {}).get("days") or [], 1):
        for stop in day.get("stops") or []:
            place = places.get(stop.get("place_id"))
            if place:
                out.append((number, day.get("date") or "", place))
    return out


def _area_names(result):
    """place id -> names of the areas it was grouped into (reverse-geocoded neighbourhoods)."""
    names = defaultdict(list)
    for area in result.get("areas") or []:
        for place_id in area.get("place_ids") or []:
            if area.get("name"): names[place_id].append(area["name"])
    return names


def _names_in(text, name):
    """Does folded text name this place? Whole name, or its part before a dash or bracket (≥5 letters)."""
    candidates = {fold(name), fold(re.split(r"\s[-–(]|,", name or "")[0])}
    return any(len(c) >= 5 and re.search(r"\b" + re.escape(c) + r"\b", text) for c in candidates)


def _headline(text):
    text = (text or "").strip()
    return text[:1].upper() + text[1:]


def _brief_dates(brief):
    from research_pipeline import trip_dates
    try:
        return trip_dates(brief)
    except (ValueError, TypeError):
        return []


def plan_tips(result, brief, videos, *, limit=12, per_stop=2, trip_limit=6):
    """Community tips that apply to this plan, each with why it matched and the stops (if any) it sits next to.

    result: the composed plan (places, itinerary.days, areas). brief: the normalised trip brief.
    videos: CommunityVideos.all() (tips already annotated). Returns {"city", "tips": [...]}.
    """
    from trippy.social.community import community_choice
    use, picked = community_choice(brief)
    city = (brief.get("destination") or "").split(",")[0].strip()
    if use == "off" or not city:
        return {"city": city, "tips": []}
    wanted = fold(city)
    countries = {c for v in videos if fold(v.get("city")) == wanted for c in video_scope(v)["countries"]}

    # What the traveller asked for: their own words map to topics ("beaches" -> beach).
    asked = {}
    for label in [*(brief.get("interests") or []), *(brief.get("preference_tags") or []), *(brief.get("vibes") or [])]:
        for topic in [*topics_of(label.replace("_", " ")), CATEGORY_TOPICS.get(label)]:
            if topic and topic not in asked: asked[topic] = label.replace("_", " ")
    stops = _stops(result)
    areas = _area_names(result)
    # The time half of the scope: the plan's own days, else the brief's dates.
    dates = [d for _, d, _ in stops if d] or _brief_dates(brief)
    wants = {fold(x) for x in [*(brief.get("preference_tags") or []), *(brief.get("vibes") or []), *(brief.get("interests") or [])]}
    party = {"families": {"family", "families", "kids", "children"}, "couples": {"couple", "couples", "romantic", "date night"},
             "friends": {"friends", "group"}, "solo": {"solo"}, "accessible": {"accessible", "wheelchair", "mobility"}}
    budget = {"free": {"budget", "cheap", "low budget", "free"}, "budget": {"budget", "cheap", "low budget"},
              "splurge": {"luxury", "splurge", "fine dining"}}
    stop_topics = []
    for number, date, place in stops:
        found = set(topics_of(f"{place.get('name') or ''} {' '.join(t for t in place.get('tags') or [] if ':' not in t)}"))
        if CATEGORY_TOPICS.get(place.get("category")): found.add(CATEGORY_TOPICS[place["category"]])
        stop_topics.append(found)
    # Every plan has sights and meals (planning_contract.categories always keeps them).
    in_plan = set().union({"sights", "food"}, *stop_topics)

    candidates, seen = [], set()
    for video in videos:
        if video.get("relevant", True) is False or (use == "picked" and video["key"] not in picked):
            continue
        for tip in video.get("tips") or []:
            scope = tip.get("scope") or tip_scope(tip, video)
            topics = tip.get("topics") or tip_topics(tip)
            main = set(tip["main_topics"] if tip.get("main_topics") is not None else main_topics(tip))
            same_city = fold(scope.get("city")) == wanted or fold(scope.get("name")) == wanted
            if same_city:
                level_score = 2 if scope["level"] in ("city", "neighbourhood", "place") else 1
            elif scope.get("level") in ("country", "region", "multi_country") and countries & set(scope.get("countries") or []):
                level_score = 0
            else:
                continue
            key = fold(f"{tip.get('title')} {tip.get('detail')}")[:90]
            if not key or key in seen:
                continue
            text = fold(f"{tip.get('title')} {tip.get('detail')}")
            when = tip.get("when") if "when" in tip else facets(tip, text, inherit={"when": video.get("when")})["when"]
            in_time = when_matches(when, dates)
            if in_time is False:
                continue   # Christmas advice on a July trip, summer beach crowds on a December one
            narrowed = scope["level"] in ("neighbourhood", "place") and fold(scope["name"]) != fold(scope.get("city"))
            attach, why = [], ""
            title = fold(tip.get("title"))
            for (number, date, place), found in zip(stops, stop_topics):
                # A name in the title is what the tip is about; one in passing ("the metro from Sagrada Familia")
                # counts only when the tip is about more than practicalities.
                by_name = _names_in(title, place.get("name")) or (_names_in(text, place.get("name")) and not set(topics) <= PRACTICAL)
                by_area = narrowed and any(fold(scope["name"]) in fold(n) or fold(n) in fold(scope["name"])
                                           for n in [*areas.get(place.get("id"), []), place.get("address") or ""] if len(fold(n)) >= 4)
                by_topic = (found & set(topics)) - PRACTICAL - BROAD
                if by_name or by_area or by_topic:
                    attach.append((number, date, place, bool(by_name and _names_in(title, place.get("name")) or by_area or by_topic & main),
                                   f"Mentions {place['name']}" if by_name
                                   else f"About {scope['name']}, where {place['name']} is" if by_area else f"Day {number} has {place['name']}"))
            matched_asked = [t for t in topics if t in asked]
            specific = set(topics) - PRACTICAL - BROAD
            # A holiday or event window the trip falls in (Christmas, Easter) is reason enough on its own.
            occasion = bool(in_time and when and (when.get("start") or when.get("movable")))
            if not attach and specific and not occasion and not specific & (in_plan | set(asked)):
                continue   # a beach tip that mentions the train is still about beaches, which this trip skips
            if not attach and matched_asked:
                why = f"You picked {asked[matched_asked[0]]}"
            elif not attach and set(topics) & PRACTICAL:
                why = "Good to know in " + (scope_label(scope) or city)
            elif not attach and occasion:
                why = ""
            elif not attach and set(topics) & in_plan & BROAD:
                why = f"Your plan has {TOPIC_TITLES[next(t for t in topics if t in in_plan & BROAD)].lower()}"
            elif not attach:
                continue
            if narrowed and not attach and not matched_asked and not occasion:
                continue   # about a part of town the plan never goes to
            seen.add(key)
            stance = tip.get("stance") or stance_of(text)
            fits = [a for a in tip.get("audience") or [] if party.get(a, set()) & wants] + \
                   [c for c in tip.get("cost") or [] if budget.get(c, set()) & wants]
            if in_time and dated(when):
                why = f"{when['label']}, your dates" + (f" · {why}" if why else "")
            # A tip that is about the stop (its headline names it, or its topic) beats one that mentions it in passing.
            score = (2 if in_time and dated(when) else 0) + (1 if fits else 0) - (1 if in_time is None and dated(when) else 0) \
                + (4 if attach else 0) + (2 if any(a[3] for a in attach) else 0) + (1 if set(matched_asked) & main else 0) \
                + (3 if matched_asked else 0) + level_score + (1 if stance == "warning" else 0) \
                + (1 if set(topics) - PRACTICAL else 0)
            candidates.append((score, len(candidates), {
                "id": f"{video['key']}#{zlib.crc32(key.encode()):08x}", "title": _headline(tip.get("title"))[:120], "detail": (tip.get("detail") or "")[:500],
                "at": tip.get("at") or "", "seconds": tip.get("seconds"), "stance": stance,
                "topics": topics, "topic_titles": [TOPIC_TITLES[t] for t in topics if t in TOPIC_TITLES],
                "scope": {**{k: scope.get(k) for k in ("level", "name", "region", "countries", "city")}, "label": scope_label(scope),
                          "when": when},
                "_season": f"{when['label']}, your dates" if in_time and dated(when) else "", "when_label": (when or {}).get("label") or "", "in_season": bool(in_time and dated(when)),
                "audience": tip.get("audience") or [], "cost": tip.get("cost") or [],
                "why": why, "attach": attach[:3],
                "source": {"key": video["key"], "platform": video.get("platform"), "title": video.get("title"),
                           "author": video.get("author"), "url": video.get("url"), "link": source_link(video, tip)}}))
    candidates.sort(key=lambda item: (-item[0], item[1]))
    chosen, per_place, at_trip = [], defaultdict(int), 0
    for _, _, tip in candidates:
        attach = tip.pop("attach")
        if attach:
            # Each stop shows its best few; a tip whose stops are all full is not moved to the top of the plan.
            attach = [a for a in attach if per_place[a[2]["id"]] < per_stop]
            if not attach:
                continue
            for a in attach: per_place[a[2]["id"]] += 1
            tip["why"] = " · ".join(x for x in (tip["_season"], attach[0][4]) if x)
        tip.pop("_season", None)
        tip.update(place_ids=[a[2]["id"] for a in attach], dates=list(dict.fromkeys(a[1] for a in attach)),
                   days=list(dict.fromkeys(a[0] for a in attach)))
        if not attach:
            if at_trip >= trip_limit: continue
            at_trip += 1
        chosen.append(tip)
        if len(chosen) >= limit: break
    return {"city": city, "tips": chosen}
