"""One tagging system for everything the community index retrieves: tips, guides and place facts.

A scope has two parts: where (city, neighbourhood, country, region; see tip_index.tip_scope) and when (an optional
time window). Alongside it, every item carries facets: topics (tip_index.TOPICS), when, audience and cost.

New reads name these inside the one extraction call that already happens (extract.SCHEMA); older stored reads get
the same shape from the keyword fallback here. Nothing in this module calls a model. Adding a facet means adding
it to FACETS: a vocabulary or parser, a normaliser for what the read says, and a fallback from free text.

when = {"label": "Christmas", "months": [12, 1], "start": "12-01", "end": "01-06", "movable": "", "weekdays": [],
        "times": []}. start/end are month-day bounds (they may wrap the year). movable names a feast whose date
changes yearly ("easter"). months alone is a looser window (a season). weekdays/times only narrow the day.
"""
from __future__ import annotations

import re
from datetime import date, timedelta

from .guides import fold

# ------------------------------------------------------------------ when ---
# label, keywords, fixed window (MM-DD, MM-DD) or movable feast, months
HOLIDAYS = [
    ("Christmas", "christmas* xmas natale navidad nadal noel weihnacht* advent christmas_market* χριστουγενν* kerst*",
     ("12-01", "01-06"), ""),
    ("New Year", "new_year* nye capodanno nochevieja reveillon silvester πρωτοχρονι* ρεβεγιον", ("12-28", "01-02"), ""),
    ("Easter", "easter pasqua semana_santa holy_week pascua ostern πασχα", None, "easter"),
    ("Carnival", "carnival* carnevale carnaval fasching αποκρι* καρναβαλ*", None, "carnival"),
    ("Halloween", "halloween", ("10-25", "11-01"), ""),
    ("Ferragosto", "ferragosto", ("08-10", "08-20"), ""),
]
SEASONS = {"Summer": ([6, 7, 8], "summer* καλοκαιρ* estate verano"), "Winter": ([12, 1, 2], "winter* χειμων* inverno invierno"),
           "Spring": ([3, 4, 5], "spring* ανοιξ* primavera"), "Autumn": ([9, 10, 11], "autumn* foliage φθινοπωρ* autunno otono")}
MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
GREEK_MONTHS = ["ιανουαρ", "φεβρουαρ", "μαρτ", "απριλ", "μαι", "ιουν", "ιουλ", "αυγουστ", "σεπτεμβρ", "οκτωβρ", "νοεμβρ", "δεκεμβρ"]
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
TIMES = {"morning": "morning* sunrise early_morning breakfast πρωι*", "afternoon": "afternoon* midday lunchtime siesta μεσημερ* απογευμα*",
         "evening": "evening* sunset dusk golden_hour dinner_time ηλιοβασιλεμα* βραδ*",
         "night": "night* late_night nightlife after_midnight νυχτ*"}
# Southern-hemisphere countries: "summer" there is December to February.
SOUTH = {"AU", "NZ", "AR", "CL", "ZA", "UY", "PY", "BO", "NA", "BW", "LS", "SZ", "MZ", "MG"}
TIME_OF_DAY = list(TIMES)


def _alternatives(words):
    parts = []
    for word in _phrases(words):
        parts.append(re.escape(word[:-1]) + r"\w*" if word.endswith("*") else re.escape(word) + r"(?:s|es)?\b")
    return re.compile(r"\b(?:" + "|".join(parts) + ")")


def _phrases(words):
    """Keywords; a phrase is written with underscores ("step_free") so it is matched whole."""
    return [w.replace("_", " ") for w in words.split()]


_HOLIDAYS = [(label, _alternatives(words), window, movable) for label, words, window, movable in HOLIDAYS]
_SEASONS = {label: (months, _alternatives(words)) for label, (months, words) in SEASONS.items()}
_MONTHS = re.compile(r"\b(?:" + "|".join(m for m in MONTHS if m != "may") + r"|in may|may to|may and|μαι[οου]\w*|"
                     + "|".join(g + r"\w*" for g in GREEK_MONTHS if g != "μαι") + r")\b")
_WEEKDAYS = re.compile(r"\b(" + "|".join(WEEKDAYS) + r")s?\b|\b(weekends?)\b")
_TIMES = {label: _alternatives(words) for label, words in TIMES.items()}


def _month_of(token):
    token = token.replace("in may", "may").replace("may to", "may").replace("may and", "may")
    for index, name in enumerate(MONTHS, 1):
        if token.startswith(name):
            return index
    for index, stem in enumerate(GREEK_MONTHS, 1):
        if token.startswith(stem):
            return index
    return None


def when_of(text, country=""):
    """A time window from free text, or None. A holiday wins over a season, a season over loose month names."""
    folded = fold(text)
    if not folded:
        return None
    when = None
    for label, pattern, window, movable in _HOLIDAYS:
        if pattern.search(folded):
            when = _empty(label)
            if window:
                when.update(start=window[0], end=window[1], months=_window_months(*window))
            else:
                when.update(movable=movable, months=[2, 3] if movable == "carnival" else [3, 4])
            break
    if when is None:
        for label, (months, pattern) in _SEASONS.items():
            if pattern.search(folded):
                when = _empty(label)
                when["months"] = [(m + 5) % 12 + 1 for m in months] if country.upper() in SOUTH else list(months)
                break
    if when is None:
        months = sorted({m for m in (_month_of(x.group(0)) for x in _MONTHS.finditer(folded)) if m})
        if months:
            when = _empty(" & ".join(MONTHS[m - 1].title() for m in months[:3]))
            when["months"] = months
    weekdays = sorted({WEEKDAYS.index(m.group(1)) for m in _WEEKDAYS.finditer(folded) if m.group(1)}
                      | ({5, 6} if any(m.group(2) for m in _WEEKDAYS.finditer(folded)) else set()))
    times = [label for label, pattern in _TIMES.items() if pattern.search(folded)]
    if weekdays or times:
        when = when or _empty("")
        when["weekdays"], when["times"] = weekdays, times
        if not when["label"]:
            when["label"] = (", ".join(WEEKDAYS[d].title() + "s" for d in weekdays[:2]) if weekdays else times[0].title())
    return when


def _empty(label):
    return {"label": label, "months": [], "start": "", "end": "", "movable": "", "weekdays": [], "times": []}


def _window_months(start, end):
    a, b = int(start[:2]), int(end[:2])
    return list(range(a, b + 1)) if a <= b else list(range(a, 13)) + list(range(1, b + 1))


_MD = re.compile(r"^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$")


def clean_when(raw):
    """What a read said about time, made safe: known fields only, valid months and dates, else None."""
    if not isinstance(raw, dict):
        return None
    when = _empty(str(raw.get("label") or "").strip()[:40])
    try:
        when["months"] = sorted({int(m) for m in raw.get("months") or [] if 1 <= int(m) <= 12})
    except (TypeError, ValueError):
        when["months"] = []
    start, end = str(raw.get("start") or "").strip(), str(raw.get("end") or "").strip()
    if _MD.match(start) and _MD.match(end):
        when.update(start=start, end=end)
        when["months"] = when["months"] or _window_months(start, end)
    when["movable"] = raw.get("movable") if raw.get("movable") in ("easter", "carnival") else ""
    when["weekdays"] = sorted({d for d in raw.get("weekdays") or [] if isinstance(d, int) and 0 <= d <= 6}
                              | {WEEKDAYS.index(d.casefold()) for d in raw.get("weekdays") or [] if isinstance(d, str) and d.casefold() in WEEKDAYS})
    when["times"] = [t for t in dict.fromkeys(raw.get("times") or []) if t in TIMES]
    if not (when["months"] or when["start"] or when["movable"] or when["weekdays"] or when["times"]):
        # A label with no dates ("Christmas") is still a time: read it like free text.
        return when_of(when["label"]) if when["label"] else None
    if not when["label"]:
        when["label"] = (when_of(" ".join(MONTHS[m - 1] for m in when["months"])) or {}).get("label", "")
    return when


def easter(year):
    """Western Easter Sunday (anonymous Gregorian algorithm)."""
    a, b, c = year % 19, year // 100, year % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = (h + l - 7 * m + 114) % 31 + 1
    return date(year, month, day)


def _in_window(day, start, end, margin=3):
    for year in (day.year - 1, day.year, day.year + 1):
        try:
            a = date(year, int(start[:2]), int(start[3:]))
            b = date(year + (1 if end < start else 0), int(end[:2]), int(end[3:]))
        except ValueError:   # 02-29 in a short year
            continue
        if a - timedelta(days=margin) <= day <= b + timedelta(days=margin):
            return True
    return False


def when_matches(when, dates):
    """Does a time window apply to these trip dates (ISO strings)? None when there is no window or no dates to judge
    by; True/False otherwise. Time of day never rules a trip out."""
    if not when or not any(when.get(k) for k in ("months", "start", "movable", "weekdays")):
        return None
    days = []
    for d in dates or []:
        try: days.append(date.fromisoformat(d))
        except (TypeError, ValueError): pass   # a malformed date from a query string judges nothing
    if not days:
        return None
    def fits(day):
        if when.get("start") and when.get("end"):
            ok = _in_window(day, when["start"], when["end"])
        elif when.get("movable"):
            feast = easter(day.year)
            if when["movable"] == "carnival":
                feast -= timedelta(days=47)
                ok = feast - timedelta(days=12) <= day <= feast + timedelta(days=1)
            else:
                ok = feast - timedelta(days=8) <= day <= feast + timedelta(days=2)
        elif when.get("months"):
            ok = day.month in when["months"]
        else:
            ok = True
        return ok and (not when.get("weekdays") or day.weekday() in when["weekdays"])
    return any(fits(day) for day in days)


# ------------------------------------------------------- audience, cost ---
AUDIENCE = {"families": "family families kids children child toddler* stroller* pram* παιδι* οικογεν*",
            "couples": "couple* romantic* date_night honeymoon* ζευγαρ* ρομαντικ*",
            "solo": "solo alone on_your_own",
            "friends": "friends group* bachelor* hen_party stag_party παρεα*",
            "accessible": "wheelchair* accessible accessibility step_free lift elevator* mobility"}
COST = {"free": "free_entry no_cost for_free free_of_charge δωρεαν*", "budget": "cheap* budget* under_€* affordable bargain* φθην*",
        "splurge": "splurge* luxury luxurious fine_dining michelin expensive* pricey ακριβ*"}
_AUDIENCE = {k: _alternatives(v) for k, v in AUDIENCE.items()}
_COST = {k: _alternatives(v) for k, v in COST.items()}


def vocabulary_of(text, patterns):
    folded = fold(text)
    return [label for label, pattern in patterns.items() if pattern.search(folded)] if folded else []


# ------------------------------------------------------------- facets ---
# name -> (vocabulary or None, fallback from text). Topics live in tip_index (they also drive stop matching).
FACETS = {
    "when": (None, lambda text, country="": when_of(text, country)),
    "audience": (list(AUDIENCE), lambda text, country="": vocabulary_of(text, _AUDIENCE)),
    "cost": (list(COST), lambda text, country="": vocabulary_of(text, _COST)),
}


def clean_facets(raw):
    """Facets a read named, made safe (unknown values dropped)."""
    raw = raw if isinstance(raw, dict) else {}
    out = {"when": clean_when(raw.get("when"))}
    for name, (vocabulary, _) in FACETS.items():
        if vocabulary is not None:
            out[name] = [v for v in dict.fromkeys(raw.get(name) or []) if v in vocabulary][:4]
    return out


def facets(item, text, *, country="", inherit=None):
    """Every facet for one item: what the read said, else the free-text fallback, else what it inherits (its video's
    when, say). `inherit` is a dict of facets from the wider item."""
    said = clean_facets(item)
    inherit = inherit or {}
    out = {}
    for name, (_, fallback) in FACETS.items():
        value = said.get(name) or fallback(text, country) or inherit.get(name)
        out[name] = value if value else (None if name == "when" else [])
    # "Go at night" inside a Christmas video is a Christmas night: a time of day narrows the inherited period.
    wider = inherit.get("when")
    if out["when"] and wider and out["when"] is not wider and not dated(out["when"]) and dated(wider):
        out["when"] = {**wider, "weekdays": out["when"]["weekdays"] or wider["weekdays"],
                       "times": list(dict.fromkeys(wider["times"] + out["when"]["times"]))}
    return out


def dated(when):
    """Does the window name a part of the year (not only a weekday or time of day)?"""
    return bool(when and (when.get("months") or when.get("start") or when.get("movable")))
