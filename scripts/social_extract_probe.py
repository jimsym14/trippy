#!/usr/bin/env python3
"""Run the share-to-map pipeline on real TikTok posts and print Mio-style cards.

    .venv/bin/python scripts/social_extract_probe.py [--no-gemini] [--audio auto|always|never] URL...

Gemini uses GEMINI_API_KEY from the environment or project .env. Google Places matching
uses the deployed bridge (TRIPPY_BRIDGE_TOKEN + TRIPPY_BRIDGE_URL) when available.
Outputs go to .local/social-probe/<post id>.json (evidence text and results, no media).
"""
import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from trippy_config import read_environment  # noqa: E402
from trippy.social import tiktok  # noqa: E402
from trippy.social.extract import enrich, extract, refine  # noqa: E402
from trippy.social.gemini import GeminiPool  # noqa: E402

OUT = ROOT / ".local/social-probe"


def bridge_search(env):
    token, base = env.get("TRIPPY_BRIDGE_TOKEN", "").strip(), env.get("TRIPPY_BRIDGE_URL", "https://trippy-research-89fm.onrender.com").rstrip("/")
    if not token:
        return None, None

    def search(query):
        url = base + "/api/places/search?" + urllib.parse.urlencode({"q": query, "lang": "en"})
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read()).get("places", [])

    def details(place_id):
        url = base + "/api/places/details?" + urllib.parse.urlencode({"place_id": place_id})
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read())
    return search, details


def card(place):
    lines = [f"  ● {place['name']}" + (f" ({place['name_latin']})" if place.get("name_latin") and place["name_latin"] != place["name"] else "")
             + f"  [{place['category']}]  {' · '.join(place['vibe_tags'])}  conf={place.get('confidence')}"]
    lines.append(f"    TLDR; {place['tldr']}")
    for title, key in (("Pro tips", "pro_tips"), ("Good to know", "good_to_know"), ("Must try", "must_try"), ("Why go", "why_go")):
        if place.get(key):
            lines.append(f"    {title}: " + " | ".join(place[key]))
    where = ", ".join(filter(None, [place.get("address_hint"), place.get("neighborhood"), place.get("city"), place.get("country_code")]))
    lines.append(f"    Where: {where}   query: {place.get('search_query')}   evidence: {', '.join(place.get('evidence', []))}")
    if place.get("google"):
        g = place["google"]
        lines.append(f"    📍 Google: {g['name']} — {g['address']} ({g['latitude']:.5f},{g['longitude']:.5f})  ★{g.get('rating')} ({g.get('reviewCount')})")
    if place.get("from_reviews"):
        lines.append(f"    + from reviews: " + " | ".join(place["from_reviews"]))
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("urls", nargs="+")
    parser.add_argument("--no-gemini", action="store_true")
    parser.add_argument("--audio", choices=["auto", "always", "never"], default="auto")
    parser.add_argument("--models", default="")
    args = parser.parse_args()
    env = read_environment(ROOT / ".env")
    OUT.mkdir(parents=True, exist_ok=True)
    pool = None if args.no_gemini else GeminiPool(env.get("GEMINI_API_KEY", "").strip(), args.models.split(",") if args.models else None)
    search, details = bridge_search(env)
    print('Google matching:', 'on (via bridge)' if search else 'off (no TRIPPY_BRIDGE_TOKEN in .env)')
    if pool:
        print("Gemini models:", ", ".join(pool.models()))
    for url in args.urls:
        started = time.time()
        reader = tiktok.Reader()
        post = reader.read(url)
        audio = None
        wants_audio = args.audio == "always" or (args.audio == "auto" and not post["slideshow"] and not post["transcript"] and (post["duration"] or 0) > 0)
        if wants_audio and args.audio != "never":
            audio = reader.audio()
        print(f"\n===== {post['author']} · {post['id']} · {'slideshow' if post['slideshow'] else 'video'} {post['duration']}s")
        print(f"  caption: {post['caption'][:160]!r}")
        print(f"  slideshow title: {post['slideshow_title']!r}   slides: {len(post['slides'])}   on-screen text: {len(post['on_screen_text'])}"
              f"   transcript: {(post['transcript_language'] or '—')} {len(post['transcript'] or '')} chars   audio: {len(audio[1]) // 1024 if audio else 0} KB")
        record = {k: v for k, v in post.items() if k != "slides"}
        record["fetch_seconds"] = round(time.time() - started, 1)
        if pool:
            source = {"url": post["url"], "author": post["author"], "evidence": tiktok.evidence(post), "images": post["slides"], "audio": audio}
            t = time.time()
            result = extract(pool, source)
            if search:
                enrich(result, search)
                try:
                    refine(pool, result, details)
                except Exception as error:  # noqa: BLE001
                    print("  refine failed:", str(error)[:300])
                print("  models:", pool.status())
            record.update(result=result, extract_seconds=round(time.time() - t, 1))
            print(f"  → {result['model']} in {record['extract_seconds']}s · {result['post_title']!r} · {result['city']}, {result['country']} · {len(result['places'])} places")
            print(f"  summary: {result['post_summary']}")
            if result.get("transcript"):
                print(f"  heard: {result['transcript'][:220]!r}")
            for place in result["places"]:
                print(card(place))
            if result.get("unresolved"):
                print("  unresolved:", result["unresolved"])
        (OUT / f"{post['id']}.json").write_text(json.dumps(record, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
