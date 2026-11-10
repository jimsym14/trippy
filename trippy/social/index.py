"""Shared indexes behind TikTok saves.

VideoIndex   — every public post is read by Gemini once. The result is stored under the post's stable key
               (``tiktok:<id>``) and handed to every later saver, whoever they are.
PlaceTakes   — the quick "your take" answers (been? got in? overhyped, value for money, ...) every user gives a
               place, keyed by Google place_id (the one Google field we may keep indefinitely). Only counts are
               ever returned; who voted stays private. Video-derived tips are public post content, so the most
               repeated ones are returned as the place's collected knowledge.
"""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import threading
import time
from pathlib import Path

# The answers the quick-take card offers. "been"/"got_in" are single choices; the rest are tags.
TAGS = ("overhyped", "value_for_money", "expensive", "cheap", "modern", "traditional", "mid", "nothing_special")
GOT_IN = ("walked_in", "waited", "booked", "turned_away")
_TIKTOK_ID = re.compile(r"/(?:video|photo)/(\d{8,25})")


def video_key(url: str = "", post_id: str = "") -> str:
    """Stable key for a post: the TikTok id when known, else a hash of the normalised URL."""
    post_id = (post_id or "").strip()
    if post_id.isdigit():
        return f"tiktok:{post_id}"
    match = _TIKTOK_ID.search(url or "")
    if match:
        return f"tiktok:{match.group(1)}"
    clean = (url or "").split("?", 1)[0].split("#", 1)[0].rstrip("/").lower()
    return "url:" + hashlib.sha256(clean.encode()).hexdigest()[:32] if clean else ""


class _Store:
    """SQLite file (development, tests) or Postgres (the server: Render's disk is wiped on every restart).

    The SQL is written once in the shared dialect; `?` placeholders become `%s` for Postgres, and the
    tables live in schema `trippy_social`.
    """
    def __init__(self, path, database_url=None):
        self._lock = threading.Lock()
        self._url = (database_url or "").strip() or None
        if self._url:
            self._db = None
            with self._pg() as db:
                db.execute("CREATE SCHEMA IF NOT EXISTS trippy_social")
            return
        self._path = str(path)
        if self._path != ":memory:":
            Path(self._path).parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(self._path, check_same_thread=False)
        self._db.execute("PRAGMA journal_mode=WAL") if self._path != ":memory:" else None

    def _pg(self):
        import psycopg
        connection = psycopg.connect(self._url, connect_timeout=8, autocommit=True)
        connection.execute("SET search_path TO trippy_social")
        return connection

    def _run(self, sql, args=()):
        if self._url:
            with self._lock, self._pg() as db:
                cursor = db.execute(sql.replace("?", "%s"), args)
                return cursor.fetchall() if cursor.description else []
        with self._lock, self._db:
            return self._db.execute(sql, args).fetchall()


class VideoIndex(_Store):
    def __init__(self, path, clock=time.time, database_url=None):
        super().__init__(path, database_url)
        self._clock = clock
        self._run("""CREATE TABLE IF NOT EXISTS videos (key TEXT PRIMARY KEY, result TEXT NOT NULL,
                     indexed_at DOUBLE PRECISION NOT NULL, readers INTEGER NOT NULL DEFAULT 1)""")

    def get(self, key):
        if not key:
            return None
        rows = self._run("SELECT result FROM videos WHERE key=?", (key,))
        return json.loads(rows[0][0]) if rows else None

    def put(self, key, result):
        if not key or not result:
            return
        self._run("INSERT INTO videos(key,result,indexed_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET result=excluded.result",
                  (key, json.dumps(result, ensure_ascii=False), self._clock()))

    def rows(self):
        """Every indexed post: (key, result json, indexed_at, readers)."""
        return self._run("SELECT key, result, indexed_at, readers FROM videos")

    def version(self):
        """Changes whenever a post is added, re-read or saved again (for the community cache)."""
        return tuple(self._run("SELECT COUNT(*), COALESCE(MAX(indexed_at),0), COALESCE(SUM(readers),0) FROM videos")[0])

    def count_reader(self, key):
        self._run("UPDATE videos SET readers=readers+1 WHERE key=?", (key,))

    def stats(self):
        rows = self._run("SELECT COUNT(*), COALESCE(SUM(readers),0) FROM videos")
        videos, readers = rows[0]
        return {"videos": videos, "saves": readers, "reads_saved": max(0, readers - videos)}


class PlaceTakes(_Store):
    def __init__(self, path, clock=time.time, database_url=None):
        super().__init__(path, database_url)
        self._clock = clock
        self._run("""CREATE TABLE IF NOT EXISTS takes (place_id TEXT NOT NULL, voter TEXT NOT NULL, been INTEGER,
                     got_in TEXT, tags TEXT NOT NULL DEFAULT '[]', updated_at DOUBLE PRECISION NOT NULL, PRIMARY KEY(place_id, voter))""")
        self._run("""CREATE TABLE IF NOT EXISTS video_places (place_id TEXT NOT NULL, video_key TEXT NOT NULL,
                     tips TEXT NOT NULL DEFAULT '[]', PRIMARY KEY(place_id, video_key))""")

    @staticmethod
    def _valid_place(place_id):
        return isinstance(place_id, str) and 3 <= len(place_id) <= 300 and not any(c.isspace() for c in place_id)

    def vote(self, place_id, voter, been=None, got_in=None, tags=()):
        """One answer per (place, voter); a later answer replaces the earlier one. Empty answers withdraw it."""
        if not self._valid_place(place_id) or not voter:
            raise ValueError("invalid_place")
        tags = sorted({t for t in tags or () if t in TAGS})
        got_in = got_in if got_in in GOT_IN else None
        been = None if been is None else bool(been)
        if been is None and not got_in and not tags:
            self._run("DELETE FROM takes WHERE place_id=? AND voter=?", (place_id, voter))
            return
        self._run("""INSERT INTO takes(place_id,voter,been,got_in,tags,updated_at) VALUES(?,?,?,?,?,?)
                     ON CONFLICT(place_id,voter) DO UPDATE SET been=excluded.been, got_in=excluded.got_in,
                     tags=excluded.tags, updated_at=excluded.updated_at""",
                  (place_id, voter, None if been is None else int(been), got_in, json.dumps(tags), self._clock()))

    def add_video(self, video_key_, places):
        """Record which places a post covers (and its public tips), once per post."""
        for place in places or []:
            place_id = ((place.get("google") or {}).get("placeID") or "")
            if not self._valid_place(place_id):
                continue
            tips = [t for t in [*(place.get("pro_tips") or []), *(place.get("good_to_know") or [])] if isinstance(t, str)][:8]
            self._run("""INSERT INTO video_places(place_id,video_key,tips) VALUES(?,?,?)
                         ON CONFLICT(place_id,video_key) DO UPDATE SET tips=excluded.tips""",
                      (place_id, video_key_, json.dumps(tips, ensure_ascii=False)))

    def summary(self, place_ids, voter=None):
        out = {}
        for place_id in dict.fromkeys(p for p in place_ids if self._valid_place(p)):
            rows = self._run("SELECT voter, been, got_in, tags FROM takes WHERE place_id=?", (place_id,))
            tags = {t: 0 for t in TAGS}
            got_in = {g: 0 for g in GOT_IN}
            been = 0
            mine = None
            for who, was, entry, tag_json in rows:
                been += 1 if was else 0
                if entry:
                    got_in[entry] += 1
                for tag in json.loads(tag_json):
                    if tag in tags:
                        tags[tag] += 1
                if voter and who == voter:
                    mine = {"been": None if was is None else bool(was), "got_in": entry, "tags": json.loads(tag_json)}
            videos = self._run("SELECT tips FROM video_places WHERE place_id=?", (place_id,))
            counted = {}
            for (tip_json,) in videos:
                for tip in json.loads(tip_json):
                    key = tip.strip().casefold()
                    if key:
                        entry = counted.setdefault(key, [tip.strip(), 0])
                        entry[1] += 1
            tips = [text for text, _ in sorted(counted.values(), key=lambda item: -item[1])][:6]
            out[place_id] = {"voters": len(rows), "been": been, "got_in": {k: v for k, v in got_in.items() if v},
                             "tags": {k: v for k, v in tags.items() if v}, "videos": len(videos), "tips": tips, "mine": mine}
        return out
