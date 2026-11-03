"""Versioned, editable search profiles and deterministic breadth-first queries."""

from hashlib import sha256
import json
import re
from urllib.parse import parse_qs, urlparse


def validate_profile(profile):
    if profile.get("version") != 1:
        raise ValueError("Unsupported profile version")
    languages = profile.get("languages", [])
    if not languages or len(languages) != len(set(languages)) or len(languages) > 8:
        raise ValueError("Choose one to eight distinct source languages")
    if any(not re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z]{2,4})?", x) for x in languages):
        raise ValueError("Invalid language code")
    names = profile.get("destination_names", {})
    if any(not isinstance(names.get(x), str) or not names[x].strip() or len(names[x]) > 100 for x in languages):
        raise ValueError("Every source language needs a destination name")
    topics = profile.get("topics", [])
    ids = [x.get("id") for x in topics]
    if not topics or len(topics) > 64 or len(ids) != len(set(ids)):
        raise ValueError("Choose distinct coverage topics")
    for topic in topics:
        if not isinstance(topic.get("id"), str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", topic["id"]):
            raise ValueError("Invalid topic ID")
        for lang in languages:
            templates = topic.get("queries", {}).get(lang, [])
            if not templates or len(templates) > 8:
                raise ValueError("Every active topic needs queries in each selected language")
            for template in templates:
                if not isinstance(template, str) or not 1 <= len(template) <= 300:
                    raise ValueError("Invalid query template")
                # Only destination substitution is allowed; unknown placeholders stay explicit errors.
                if re.search(r"[{}]", template.replace("{city}", "")):
                    raise ValueError("Unknown query placeholder")
    limits = profile.get("limits", {})
    for key, ceiling in (("max_queries", 100), ("results_per_query", 50), ("max_video_candidates", 500)):
        if type(limits.get(key)) is not int or not 1 <= limits[key] <= ceiling:
            raise ValueError("Invalid bounded limit: " + key)
    region = profile.get("region_code")
    if region is not None and (not isinstance(region, str) or not re.fullmatch(r"[A-Z]{2}", region)):
        raise ValueError("Invalid region hint")
    return profile


def plan_queries(profile, *, covered_topics=()):
    """Search each topic/language before expanding synonyms. Never invent city styles."""
    validate_profile(profile)
    covered = set(covered_topics)
    if not covered.issubset({x["id"] for x in profile["topics"]}):
        raise ValueError("Unknown covered topic")
    topics = sorted(profile["topics"], key=lambda x: x["id"] in covered)
    queries, seen = [], set()
    cap = profile["limits"]["max_queries"]
    depth = max(len(x["queries"][lang]) for x in topics for lang in profile["languages"])
    for index in range(depth):
        for topic in topics:
            for lang in profile["languages"]:
                templates = topic["queries"][lang]
                if index >= len(templates):
                    continue
                query = templates[index].replace("{city}", profile["destination_names"][lang]).strip()
                key = (lang, " ".join(query.casefold().split()))
                if key in seen:
                    continue
                seen.add(key)
                identifier = sha256((lang + "\n" + query).encode()).hexdigest()[:20]
                queries.append({"id": identifier, "topic": topic["id"], "language_hint": lang,
                                "query": query, "phase": "overview" if topic["id"] == "overview" else "targeted",
                                "region_hint": profile.get("region_code")})
    selected = queries[:cap]
    represented = {(x["topic"], x["language_hint"]) for x in selected}
    return {"version": 1, "destination": profile["destination_names"], "source_languages": profile["languages"],
            "profile_sha256": sha256(json.dumps(profile, sort_keys=True, ensure_ascii=False).encode()).hexdigest(),
            "queries": selected, "unexecuted_query_count": max(0, len(queries)-cap),
            "missing_topic_languages": [{"topic": t["id"], "language": lang} for t in topics
                for lang in profile["languages"] if (t["id"], lang) not in represented],
            "limits": profile["limits"], "scope": "local_source_discovery", "paid_provider_calls": 0,
            "status": "planned_not_executed"}


def canonical_video(url):
    """Validate identifiers without fetching URLs or accepting arbitrary hosts."""
    if not isinstance(url, str) or len(url) > 2048:
        raise ValueError("Invalid video URL")
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError("Use an HTTPS video link")
    host = (parsed.hostname or "").lower()
    if host == "youtu.be":
        identifier = parsed.path.strip("/")
    elif host in {"youtube.com", "www.youtube.com", "m.youtube.com"}:
        if parsed.path == "/watch":
            values = parse_qs(parsed.query).get("v", [])
            identifier = values[0] if len(values) == 1 else ""
        else:
            match = re.fullmatch(r"/(?:shorts|embed|live)/([\w-]{11})/?", parsed.path)
            identifier = match.group(1) if match else ""
    else:
        raise ValueError("This connector currently accepts YouTube links only")
    if not re.fullmatch(r"[A-Za-z0-9_-]{11}", identifier):
        raise ValueError("Invalid YouTube video identifier")
    return {"provider": "youtube", "external_id": identifier,
            "url": "https://www.youtube.com/watch?v=" + identifier}


def manual_sources(urls):
    seen, sources = set(), []
    for url in urls:
        video = canonical_video(url)
        if video["external_id"] not in seen:
            seen.add(video["external_id"])
            sources.append({**video, "origin": "manual_link", "status": "needs_metadata_and_content_access",
                            "scope": "private", "transcript_status": "not_acquired"})
    if len(sources) > 500:
        raise ValueError("Source candidate limit exceeded")
    return sources
