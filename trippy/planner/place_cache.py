"""What a plan already paid for (in money or seconds) is kept and reused by every later plan.

Two things are cached, both exact, so a reused answer is the same answer the call would give:

ideas   — the idea model's reply for one prompt. The prompt already carries the city, the base, the pills, the
          request and the category, so only an identical request reuses it. A re-plan, a retry or a second
          traveller with the same choices costs no model call.
checks  — an OpenStreetMap lookup for "name, city" (found or not found). The public server allows one request a
          second, so a plan with 60 ideas spent a minute here; a city that has been planned before spends none.

Only our own model output and OpenStreetMap data (ODbL, credited on the place) are stored. Google answers are
never cached here: Google's terms let us keep a place_id and nothing else.

On the server the rows live in Postgres next to the video index (Render's disk is wiped on restart).
"""
import hashlib
import json
import time

from trippy.social.index import _Store

DAY = 86400
IDEAS_DAYS, FOUND_DAYS, MISSING_DAYS = 14, 30, 7


class PlaceCache(_Store):
    def __init__(self, path, clock=time.time, database_url=None):
        super().__init__(path, database_url)
        self._clock = clock
        self.hits = {'ideas': 0, 'checks': 0}
        self.misses = {'ideas': 0, 'checks': 0}
        self._run("""CREATE TABLE IF NOT EXISTS planner_cache (kind TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL,
                     stored_at DOUBLE PRECISION NOT NULL, PRIMARY KEY (kind, key))""")

    @staticmethod
    def key(*parts):
        return hashlib.sha256(json.dumps(parts, ensure_ascii=False, sort_keys=True, default=str).encode()).hexdigest()

    def get(self, kind, key, days):
        """(True, value) when a fresh row exists, else (False, None). A stored None is a real answer ("not found")."""
        try:
            rows = self._run("SELECT value, stored_at FROM planner_cache WHERE kind=? AND key=?", (kind, key))
        except Exception:  # noqa: BLE001 - the cache is an optimisation; a broken one must never fail a plan
            return False, None
        if not rows:
            return False, None
        value = json.loads(rows[0][0])
        age = self._clock() - rows[0][1]
        limit = days(value) if callable(days) else days
        return (True, value) if age <= limit * DAY else (False, None)

    def put(self, kind, key, value):
        try:
            self._run("INSERT INTO planner_cache(kind,key,value,stored_at) VALUES(?,?,?,?) "
                      "ON CONFLICT(kind,key) DO UPDATE SET value=excluded.value, stored_at=excluded.stored_at",
                      (kind, key, json.dumps(value, ensure_ascii=False), self._clock()))
        except Exception:  # noqa: BLE001
            pass

    def stats(self):
        return {'hits': dict(self.hits), 'misses': dict(self.misses)}


def cached_generate(generate, cache, model):
    """generate(prompt, system, schema) with replies kept per exact prompt. Empty or failed replies are not kept."""
    def run(prompt, system, schema):
        key = cache.key(model, system, prompt, schema)
        found, value = cache.get('ideas', key, IDEAS_DAYS)
        if found:
            cache.hits['ideas'] += 1
            return value
        cache.misses['ideas'] += 1
        value = generate(prompt, system, schema)
        if value and value.get('places'):
            cache.put('ideas', key, value)
        return value
    return run


def cached_resolver(resolver, cache):
    """An OpenStreetMap resolver with its answers kept. Must not wrap a Google resolver (see the module note)."""
    label = getattr(resolver, 'label', 'check')
    if label != 'openstreetmap':
        raise ValueError('Only OpenStreetMap answers may be cached')

    takes_kinds = getattr(resolver, 'takes_kinds', False)

    def resolve(query, destination, near, kinds=None):
        # The lookup box is ±0.25° around the base, so bases a few km apart share an answer; the distance to the
        # real base is still checked by the caller.
        where = [round(near[0], 1), round(near[1], 1)] if near else None
        key = cache.key(query.casefold(), destination.casefold(), where, sorted(kinds) if kinds else None)
        found, value = cache.get('checks', key, lambda v: FOUND_DAYS if v else MISSING_DAYS)
        if found:
            cache.hits['checks'] += 1
            return value
        cache.misses['checks'] += 1
        value = resolver(query, destination, near, kinds) if takes_kinds else resolver(query, destination, near)
        cache.put('checks', key, value)
        return value
    resolve.label = label
    resolve.takes_kinds = takes_kinds
    return resolve
