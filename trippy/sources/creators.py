"""Editable channel-identity seeds, bounded companion discovery and stats snapshots.

API metadata is a discovery signal, never permission or evidence of venue quality.
Search cannot guarantee every episode is indexed; coverage gaps are explicit.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
from urllib.parse import urlencode
from urllib.request import Request, build_opener

from trippy_config import read_environment
from trippy.catalog.normalize import normalize_text
from .youtube import NoRedirect, reserve_search
from .planner import canonical_video


def api(resource, params, key):
    try:
        with build_opener(NoRedirect()).open(Request(
                'https://www.googleapis.com/youtube/v3/' + resource + '?' +
                urlencode({**params, 'key': key})), timeout=30) as response:
            raw = response.read(5_000_001)
        if len(raw) > 5_000_000:
            raise ValueError('Metadata byte cap exceeded')
        return json.loads(raw)
    except Exception:
        raise ValueError('Official YouTube metadata request failed (credentials redacted)') from None


def load_creators(path, languages):
    document = json.loads(Path(path).read_text())
    if document.get('version') != 1:
        raise ValueError('Unsupported creator defaults')
    selected = [c for c in document['creators'] if c.get('enabled') and c['language'] in languages]
    if len(selected) > 20 or len({c['channel_id'] for c in selected}) != len(selected):
        raise ValueError('Creator count or duplicate channel identity')
    for c in selected:
        if not re.fullmatch(r'UC[A-Za-z0-9_-]{22}', c['channel_id']):
            raise ValueError('Verified channel ID required')
    return selected


def city_relevant(title, names):
    # Title anchoring deliberately excludes broad Spain/Madrid videos mentioning
    # Barcelona only incidentally in a description. Such videos need manual input.
    tokens = set(normalize_text(title).split())
    return any(set(normalize_text(name).split()).issubset(tokens) for name in names)


def duration_seconds(value):
    match = re.fullmatch(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?', value or '')
    return sum(int(x or 0) * n for x, n in zip(match.groups(), (3600, 60, 1))) if match else None


def discover_creators(creators, names, key, ledger, *, requester=api, pages=2, per_creator=6):
    if not key or not 1 <= pages <= 3 or not 1 <= per_creator <= 20:
        raise ValueError('Key and bounded discovery limits required')
    now = datetime.now(timezone.utc).isoformat()
    result = {'version': 1, 'status': 'creator_discovery_running', 'sources': [], 'candidates': [], 'coverage': [],
              'fetched_at': now, 'catalog_writes': 0, 'paid_calls': 0,
              'metadata_refresh_or_delete_days': 30}
    for creator in creators:
        candidates, errors, capped = {}, [], False
        # Every configured destination spelling is searched, both ranking modes.
        for name in dict.fromkeys(names):
            for order in ('relevance', 'date'):
                token = None
                for page in range(pages):
                    try:
                        reserve_search(ledger, key)
                        params = dict(part='snippet', type='video', channelId=creator['channel_id'],
                                      q=name, maxResults=50, order=order)
                        if token: params['pageToken'] = token
                        document = requester('search', params, key)
                    except ValueError as exc:
                        errors.append(str(exc)); break
                    for item in document.get('items', []):
                        snippet = item.get('snippet', {})
                        identifier = item.get('id', {}).get('videoId', '')
                        if snippet.get('channelId') != creator['channel_id']:
                            continue
                        if not city_relevant(snippet.get('title', ''), names):
                            continue
                        try: video = canonical_video('https://www.youtube.com/watch?v=' + identifier)
                        except ValueError: continue
                        candidates[identifier] = {**video, 'title': snippet['title'],
                            'channel_id': creator['channel_id'], 'channel_title': creator['name'],
                            'creator_id': creator['id'], 'publisher_group': creator['channel_id'],
                            'language_hint': creator['language'], 'published_at': snippet.get('publishedAt'),
                            'origin': 'default_creator_channel_search', 'fetched_at': now,
                            'scope': 'local_review', 'status': 'candidate_needs_review',
                            'transcript_status': 'not_acquired', 'metadata_refresh_or_delete_days': 30}
                    token = document.get('nextPageToken')
                    if not token: break
                    if page == pages - 1: capped = True
        ids = list(candidates)
        for offset in range(0, len(ids), 50):
            try:
                details = requester('videos', dict(part='snippet,statistics,contentDetails,status',
                                    id=','.join(ids[offset:offset+50])), key)
            except ValueError as exc:
                errors.append(str(exc)); continue
            for item in details.get('items', []):
                if item['id'] not in candidates: continue
                source = candidates[item['id']]
                if item.get('snippet', {}).get('channelId') != creator['channel_id']:
                    del candidates[item['id']]; continue
                source['statistics_snapshot'] = item.get('statistics', {})
                source['duration_seconds'] = duration_seconds(item.get('contentDetails', {}).get('duration'))
                source['description'] = item.get('snippet', {}).get('description', '')
                source['declared_audio_language'] = item.get('snippet', {}).get('defaultAudioLanguage')
                source['availability'] = item.get('status', {}).get('privacyStatus')
        result['candidates'].extend(candidates.values())
        eligible = [s for s in candidates.values() if s.get('duration_seconds') and
                    30 <= s['duration_seconds'] <= 7200 and s.get('availability') == 'public']
        # Full episodes/parts get first priority; metrics are a tie breaker,
        # not a star rating or an assertion of trustworthy recommendations.
        def rank(s):
            part = bool(re.search(r'(?:part|episode|μέρος|μερος|επεισόδιο|επεισοδιο|[ΑΒΓ]΄)', s['title'], re.I))
            return (-part, -int(s.get('statistics_snapshot', {}).get('viewCount', 0)), s['external_id'])
        eligible.sort(key=rank)
        # Greek television episodes are retained together up to the explicit cap.
        cap = 20 if creator['language'] == 'el' else per_creator
        selected = eligible[:cap]
        result['sources'].extend(selected)
        result['coverage'].append({'creator': creator['name'], 'channel_id': creator['channel_id'],
            'candidates': len(candidates), 'eligible': len(eligible), 'selected': len(selected),
            'deferred_video_ids': [s['external_id'] for s in eligible[cap:]],
            'search_page_cap_reached': capped, 'errors': errors,
            'companion_check': 'all_title_relevant_results_retained_as_candidates; completeness_unverified',
            'status': 'found' if selected else 'missing_or_unavailable'})
    result['status'] = 'creator_discovery_incomplete' if any(c['errors'] for c in result['coverage']) else 'creator_discovery_complete_needs_review'
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--per-creator', type=int, default=6)
    args = p.parse_args()
    profile = json.loads(args.profile.read_text())
    creators = load_creators(args.profile.parent / profile['creator_defaults'], profile['languages'])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        result = discover_creators(creators, list(profile['destination_names'].values()),
            read_environment(Path('.env')).get('YOUTUBE_API_KEY', ''),
            '.local/stage3/sources/youtube-quota.sqlite', per_creator=args.per_creator)
        json.dump(result, stream, ensure_ascii=False, indent=2)
    print(json.dumps({'status': result['status'], 'sources': len(result['sources']), 'coverage': result['coverage']}, ensure_ascii=False))


if __name__ == '__main__': main()
