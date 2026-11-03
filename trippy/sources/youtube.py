"""Official YouTube search, explicit execution, durable local quota reservation.

Does not download audiovisual content, captions, or scrape YouTube pages.
"""

from datetime import datetime, timezone
from contextlib import closing
from hashlib import sha256
import json
from pathlib import Path
import sqlite3
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener
from zoneinfo import ZoneInfo

from .planner import canonical_video


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def reserve_search(path, api_key, *, daily_limit=100, now=None):
    if type(daily_limit) is not int or not 1 <= daily_limit <= 100:
        raise ValueError("Daily search limit must be between 1 and 100")
    day = (now or datetime.now(timezone.utc)).astimezone(ZoneInfo("America/Los_Angeles")).date().isoformat()
    # No raw key is stored. This is a local per-key ceiling, not Google's project-wide usage meter.
    fingerprint = sha256(api_key.encode()).hexdigest()
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(path, timeout=10)) as db, db:
        db.execute("CREATE TABLE IF NOT EXISTS search_quota (key_hash TEXT, day TEXT, used INTEGER NOT NULL, PRIMARY KEY(key_hash,day))")
        db.execute("BEGIN IMMEDIATE")
        db.execute("INSERT OR IGNORE INTO search_quota VALUES (?,?,0)", (fingerprint,day))
        used = db.execute("SELECT used FROM search_quota WHERE key_hash=? AND day=?", (fingerprint,day)).fetchone()[0]
        if used >= daily_limit:
            raise ValueError("Local daily YouTube search ceiling reached")
        db.execute("UPDATE search_quota SET used=used+1 WHERE key_hash=? AND day=?", (fingerprint,day))
    # Retain reservation on failure: invalid requests can still consume provider quota.


def search(query, api_key, *, max_results):
    params = {"part": "snippet", "type": "video", "q": query["query"], "maxResults": max_results,
              "relevanceLanguage": query["language_hint"], "order": "relevance", "key": api_key}
    if query.get("region_hint"):
        params["regionCode"] = query["region_hint"]
    request = Request("https://www.googleapis.com/youtube/v3/search?" + urlencode(params))
    try:
        with build_opener(NoRedirect()).open(request, timeout=20) as response:
            raw = response.read(2_000_001)
        if len(raw) > 2_000_000:
            raise ValueError("YouTube response exceeds local byte cap")
        document = json.loads(raw)
        if not isinstance(document.get("items"), list) or len(document["items"]) > max_results:
            raise ValueError("Invalid YouTube response")
        return document["items"]
    except (HTTPError, URLError):
        # Never propagate provider URLs/exceptions containing the API key.
        raise ValueError("YouTube request failed; check credentials or provider quota") from None


def discover(plan, api_key, ledger, *, requester=search):
    if not isinstance(api_key, str) or not api_key.strip():
        raise ValueError("YOUTUBE_API_KEY is required for official discovery")
    if len(plan["queries"]) > 100:
        raise ValueError("YouTube search request cap exceeded")
    sources, by_id, completed = [], {}, []
    result = {**plan, "sources": sources, "completed_query_ids": completed,
              "status": "discovery_running", "catalog_writes": 0}
    for query in plan["queries"]:
        if len(sources) >= plan["limits"]["max_video_candidates"]:
            result["status"] = "candidate_cap_reached"
            break
        try:
            reserve_search(ledger, api_key)
            items = requester(query, api_key, max_results=plan["limits"]["results_per_query"])
        except ValueError as exc:
            result["status"] = "discovery_incomplete"
            result["error"] = str(exc)
            break
        fetched = datetime.now(timezone.utc).isoformat()
        completed.append(query["id"])
        for item in items:
            identifier = item.get("id", {}).get("videoId", "")
            try:
                video = canonical_video("https://www.youtube.com/watch?v=" + identifier)
            except ValueError:
                continue
            if identifier in by_id:
                by_id[identifier]["discovered_by_query_ids"].append(query["id"])
                continue
            if len(sources) >= plan["limits"]["max_video_candidates"]:
                continue
            snippet = item.get("snippet", {})
            source = {**video, "title": snippet.get("title"), "channel_id": snippet.get("channelId"),
                      "channel_title": snippet.get("channelTitle"), "published_at": snippet.get("publishedAt"),
                      "fetched_at": fetched, "discovered_by_query_ids": [query["id"]],
                      "language_status": "unverified_search_hint_only", "origin": "official_youtube_search",
                      "scope": "local_review", "status": "candidate_needs_review",
                      "transcript_status": "not_acquired", "metadata_refresh_or_delete_days": 30}
            sources.append(source)
            by_id[identifier] = source
    else:
        result["status"] = "discovery_complete_not_content_processed"
    result["not_executed_query_ids"] = [q["id"] for q in plan["queries"] if q["id"] not in completed]
    return result
