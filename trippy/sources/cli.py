"""Local profile preview / manual links / explicit official discovery."""

import argparse
import json
from pathlib import Path

from trippy_config import read_environment

from .planner import manual_sources, plan_queries
from .youtube import discover
from .creators import discover_creators, load_creators


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--links", type=Path, help="Local text file, one YouTube URL per line")
    parser.add_argument("--env-file", type=Path, default=Path(".env"), help="Safe dotenv reading; shell values take precedence")
    parser.add_argument("--execute-youtube", action="store_true", help="Use the official API quota; no captions/media downloads")
    parser.add_argument("--ledger", type=Path, default=Path(".local/stage3/sources/youtube-quota.sqlite"))
    args = parser.parse_args(argv)
    if args.links and args.execute_youtube:
        parser.error("Manual import and automated discovery are separate batch operations")
    if args.output.exists():
        parser.error("Output already exists; choose a new batch path")
    profile = json.loads(args.profile.read_text())
    result = plan_queries(profile)
    if profile.get('creator_defaults'):
        result['creator_seed_preview'] = load_creators(args.profile.parent / profile['creator_defaults'], profile['languages'])
    if args.links:
        if args.links.stat().st_size > 1_000_000:
            parser.error("Manual link list exceeds local byte cap")
        urls = [x.strip() for x in args.links.read_text().splitlines() if x.strip() and not x.lstrip().startswith("#")]
        result["sources"] = manual_sources(urls)
        result["status"] = "manual_links_registered_not_content_processed"
    api_key = read_environment(args.env_file).get("YOUTUBE_API_KEY", "")
    if args.execute_youtube and not api_key.strip():
        parser.error("Set YOUTUBE_API_KEY in the local env file or shell environment before discovery")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Reserve the output before any network work; don't charge quota then overwrite a prior batch.
    with args.output.open("x") as stream:
        if args.execute_youtube:
            result = discover(result, api_key, args.ledger)
            if profile.get('creator_defaults'):
                creators = load_creators(args.profile.parent / profile['creator_defaults'], profile['languages'])
                seeded = discover_creators(creators, list(profile['destination_names'].values()), api_key, args.ledger)
                # Seeds supplement topical breadth; don't truncate later creators
                # simply because a broad query filled its separate candidate cap.
                by_id = {s['external_id']: s for s in result['sources']}
                for source in seeded['sources']:
                    if source['external_id'] in by_id:
                        by_id[source['external_id']].update(source)
                    else:
                        result['sources'].append(source)
                result['creator_coverage'] = seeded['coverage']
                result['creator_discovery_status'] = seeded['status']
                result['candidate_limits_basis'] = 'topical_cap_plus_bounded_default_creator_seeds'
        json.dump(result, stream, ensure_ascii=False, indent=2)
    print(json.dumps({"status": result["status"], "queries": len(result["queries"]),
                      "sources": len(result.get("sources", [])), "missing_topic_languages": result["missing_topic_languages"]}))


if __name__ == "__main__":
    main()
