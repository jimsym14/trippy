"""OpenStreetMap `opening_hours` → the planner's weekly hours tag (free data instead of Google hours).

Handles the common forms: "24/7", "Mo-Fr 08:00-20:00; Sa,Su 09:00-14:00", "Tu-Su 10:00-14:00,18:00-23:00",
"Mo off", times past midnight ("18:00-02:00"). Anything else (public holidays, months, weeks, "sunrise")
returns None, so a wrong guess never reaches a plan.
"""
import re

from .travel_provider import HOURS_PREFIX

DAYS = {'Su': 0, 'Mo': 1, 'Tu': 2, 'We': 3, 'Th': 4, 'Fr': 5, 'Sa': 6}
ORDER = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
TIME = re.compile(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})\+?$')


def _days(spec):
    out = []
    for part in spec.split(','):
        part = part.strip()
        if '-' in part:
            a, b = part.split('-', 1)
            if a not in DAYS or b not in DAYS: return None
            i, j = ORDER.index(a), ORDER.index(b)
            span = ORDER[i:j + 1] if i <= j else ORDER[i:] + ORDER[:j + 1]
            out += span
        elif part in DAYS: out.append(part)
        else: return None
    return out


def periods(text):
    """[(open_day, hh, mm, close_day, hh, mm)] in Google's day numbering (0 = Sunday), or None."""
    if not isinstance(text, str) or not text.strip(): return None
    text = text.strip()
    if text == '24/7': return 'always'
    week = {d: [] for d in ORDER}
    for rule in [r.strip() for r in text.split(';') if r.strip()]:
        tokens = rule.split(' ', 1)
        if tokens[0].startswith(('PH', 'SH')): continue   # public/school holiday rules: the holiday check covers those
        if re.match(r'^(\d{1,2}:\d{2}|off|closed)', tokens[0]):
            days, rest = list(ORDER), rule
        else:
            days = _days(tokens[0])
            if days is None or len(tokens) < 2: return None
            rest = tokens[1].strip()
        if rest in ('off', 'closed'):
            for d in days: week[d] = []
            continue
        ranges = []
        for chunk in rest.split(','):
            m = TIME.match(chunk.strip())
            if not m: return None
            ranges.append(tuple(int(x) for x in m.groups()))
        for d in days: week[d] = ranges   # later rules override earlier ones, as in OSM
    out = []
    for d, ranges in week.items():
        for oh, om, ch, cm in ranges:
            if oh > 24 or ch > 48 or om > 59 or cm > 59: return None
            close_day = DAYS[d]
            if (ch, cm) <= (oh, om) or ch >= 24:   # closes after midnight
                close_day = (DAYS[d] + 1) % 7; ch = ch % 24
            out.append((DAYS[d], oh % 24, om, close_day, ch, cm))
    return out


def hours_tag(text):
    """The planner's hours tag for an OSM opening_hours string, or None."""
    result = periods(text)
    if result is None: return None
    if result == 'always': return f'{HOURS_PREFIX}:always'
    if not result: return None
    return f'{HOURS_PREFIX}:' + ','.join('%d%02d%02d-%d%02d%02d' % p for p in sorted(result)[:21])
