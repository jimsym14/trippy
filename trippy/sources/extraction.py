"""Evidence-validated, checkpointed two-pass research drafts. No publication.

Prepare local structured requests; a provider callable or separately supplied
responses can execute extraction. This module never silently calls paid models.
"""
import argparse
from contextlib import closing
from collections import Counter
from hashlib import sha256
import json
import math
from pathlib import Path
from uuid import uuid4
import re
import sqlite3
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field
from trippy.catalog.normalize import normalize_text
from .planner import canonical_video

ROOT = Path(__file__).resolve().parents[2]
PROMPT_VERSION = 2
PROMPT = ROOT / 'configs/source_research/extraction-prompt-v2.md'


def prompt_for_version(version):
    if type(version) is not int or version not in (1,2):raise ValueError('Unsupported extraction prompt version')
    return ROOT / f'configs/source_research/extraction-prompt-v{version}.md'
Category = Literal['food', 'coffee', 'bars', 'clubs', 'sights', 'museums', 'outdoors',
    'day_trips', 'shopping', 'events', 'transport', 'tickets', 'stay',
    'budget_practical', 'family_accessibility', 'dietary', 'other']
Dimension = Literal['cuisine', 'dishes', 'dietary', 'allergies', 'vibe', 'music',
    'audience', 'neighborhood', 'address', 'city', 'branch', 'website', 'price',
    'currency', 'budget', 'booking', 'queue', 'opening_hours', 'duration', 'season',
    'date', 'accessibility', 'family', 'transport', 'tickets', 'safety', 'shopping',
    'accommodation', 'subcategory', 'recommendation', 'sponsorship', 'other']


class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)


class Citation(Strict):
    segment_id: str
    start_seconds: float
    end_seconds: float
    quote: str = Field(min_length=1, max_length=2000)


class Claim(Strict):
    dimension: Dimension
    value: str = Field(min_length=1, max_length=2000)
    basis: Literal['source_fact', 'creator_opinion', 'inferred_fit']
    observed_at: str | None
    citations: list[Citation] = Field(min_length=1, max_length=12)


class Rating(Strict):
    value: float = Field(ge=0, le=5)
    scale: Literal[5]
    platform: str = Field(min_length=1, max_length=100)
    citations: list[Citation] = Field(min_length=1, max_length=12)


class Mention(Strict):
    name: str = Field(min_length=1, max_length=500)
    aliases: list[str] = Field(max_length=20)
    kind: Literal['venue', 'chain', 'district', 'city', 'dish', 'event', 'route', 'transport_product', 'ticket', 'advice']
    categories: list[Category] = Field(min_length=1, max_length=17)
    stance: Literal['recommended', 'negative', 'passing', 'mixed', 'sponsored']
    identity_uncertain: bool
    identity_uncertainty_reason: str | None
    experience: Literal['first_hand_visit', 'reported_by_others', 'unknown']
    branch: str | None
    claims: list[Claim] = Field(max_length=100)
    rating: Rating | None
    citations: list[Citation] = Field(min_length=1, max_length=12)


class Extraction(Strict):
    mentions: list[Mention] = Field(max_length=120)


def fingerprint(value):
    return sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def greek_search_variant(value):
    """Phonetic lookup hint only; never a factual/canonical name correction."""
    text=normalize_text(value)
    for original,replacement in [('ου','u'),('αι','e'),('ει','i'),('οι','i'),('γκ','g'),('ντ','d'),('μπ','b')]:
        text=text.replace(original,replacement)
    mapping=dict(zip('αβγδεζηθικλμνξοπρσςτυφχψω',
        ['a','v','g','d','e','z','i','th','i','k','l','m','n','x','o','p','r','s','s','t','y','f','ch','ps','o']))
    return ''.join(mapping.get(c,c) for c in text)


def quality_flags(evidence):
    segments = evidence.get('segments', [])
    flags = []
    if not segments: return ['empty']
    if evidence.get('language') not in {'el', 'en', 'es', 'ca'}:
        flags.append('unsupported_or_misdetected_language')
    texts = [' '.join(s.get('text', '').split()) for s in segments]
    speech = [t for t in texts if re.search(r'[^\W\d_]', t, re.UNICODE) and not
              re.fullmatch(r'[\[(].*[\])]', t)]
    if sum(len(t) for t in speech) < 120: flags.append('insufficient_speech')
    if len(texts) >= 20 and Counter(texts).most_common(1)[0][1] / len(texts) > .30:
        flags.append('excessive_repetition')
    if len(speech) / len(texts) < .20: flags.append('mostly_music_or_annotations')
    outside=sum(c.get('reason')=='beyond_audio_duration' for c in evidence.get('excluded_cues', []))
    if outside / (len(segments)+outside) > .10: flags.append('excessive_out_of_audio_cues')
    return flags


def chunk_evidence(evidence, metadata=None, *, max_chars=12000, overlap=2, prompt_version=PROMPT_VERSION):
    if not 1000 <= max_chars <= 30000 or not 0 <= overlap <= 5:
        raise ValueError('Invalid chunk bounds')
    source = evidence['source']
    prompt=prompt_for_version(prompt_version).read_text()
    if canonical_video(source['url'])['external_id'] != source['external_id']:
        raise ValueError('Source identity mismatch')
    flags = quality_flags(evidence)
    if flags: return [], flags
    numbered, previous = [], -1
    for i, s in enumerate(evidence['segments']):
        start, end = s['start_seconds'], s['end_seconds']
        if any(type(v) not in (float, int) or not math.isfinite(v) for v in (start, end)) or not 0 <= start < end or start < previous:
            raise ValueError('Invalid transcript timestamp')
        if len(s['text']) > max_chars: raise ValueError('Oversized segment requires manual segmentation')
        previous = start
        numbered.append({**s, 'segment_id': f"{source['external_id']}:{i:06d}"})
    chunks, pos = [], 0
    while pos < len(numbered):
        stop, size = pos, 0
        while stop < len(numbered) and size + len(numbered[stop]['text']) <= max_chars:
            size += len(numbered[stop]['text']); stop += 1
        payload = {'source': source, 'source_evidence_sha256': fingerprint(evidence),
            'transcript_sha256': evidence.get('transcript_sha256', evidence.get('content_sha256')),
            'metadata': metadata or {}, 'segments': numbered[pos:stop]}
        key = fingerprint({'prompt': prompt, 'schema': Extraction.model_json_schema(), 'payload': payload})
        chunks.append({'id': key, 'prompt_version': prompt_version, 'system_prompt': prompt,
            'response_schema': Extraction.model_json_schema(), 'payload': payload,
            'status': 'prepared_not_executed'})
        if stop == len(numbered): break
        pos = max(pos + 1, stop - overlap)
    return chunks, []


def validate_result(chunk, raw):
    parsed = Extraction.model_validate(raw)
    segments = {s['segment_id']: s for s in chunk['payload']['segments']}
    def check(citation):
        s = segments.get(citation.segment_id)
        if not s or citation.quote not in s['text'] or (citation.start_seconds, citation.end_seconds) != (s['start_seconds'], s['end_seconds']):
            raise ValueError('Citation quote, segment or timestamps do not match evidence')
    for mention in parsed.mentions:
        for citation in mention.citations: check(citation)
        if mention.kind not in {'advice', 'route'}:
            quoted = normalize_text(' '.join(c.quote for c in mention.citations))
            if not any(normalize_text(n) in quoted for n in [mention.name, *mention.aliases] if normalize_text(n)):
                raise ValueError('Entity name or original alias must occur in cited speech')
        for claim in mention.claims:
            for citation in claim.citations: check(citation)
        if mention.rating:
            for citation in mention.rating.citations: check(citation)
            text = ' '.join(c.quote for c in mention.rating.citations).casefold()
            number = re.escape(format(mention.rating.value, 'g'))
            if mention.rating.platform.casefold() not in text or not re.search(
                    number + r'\s*(?:/\s*5|out of\s*5|στα\s*5|από\s*5)', text):
                raise ValueError('Rating needs explicit platform and five-point value in quote')
    return parsed.model_dump()


def identity_candidates(mention, catalog, *, limit=8):
    """Read the full inventory; never equate a name match with resolved identity."""
    if mention['kind'] != 'venue' or not catalog: return []
    names = [normalize_text(mention['name']), *(normalize_text(n) for n in mention['aliases'])]
    names += [greek_search_variant(n) for n in [mention['name'],*mention['aliases']]]
    names = list(dict.fromkeys(n for n in names if len(n) >= 3))[:10]
    if not names: return []
    with closing(sqlite3.connect(Path(catalog).resolve().as_uri() + '?mode=ro', uri=True)) as db:
        db.row_factory = sqlite3.Row
        rows = db.execute('SELECT DISTINCT entity_id,name,address,locality,latitude,longitude,external_id,source_category,family,website_url,operating_status '
            'FROM catalog_snapshots WHERE ' + ' OR '.join('search_text LIKE ? ESCAPE \'\\\'' for _ in names) + ' LIMIT ?',
            [*['%' + n.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%' for n in names], 200]).fetchall()
    category_family={'bars':'nightlife','clubs':'nightlife','museums':'sights','day_trips':'outdoors'}
    families={category_family.get(c,c) for c in mention['categories']}
    rows=sorted(rows,key=lambda r:(normalize_text(r['name']) not in names,r['family'] not in families,r['entity_id']))[:limit]
    return [{**dict(r), 'decision': 'identity_candidate_needs_review',
             'basis': 'normalized_name_alias_or_phonetic_lookup_only; verify_branch_address_city'} for r in rows]


def aggregate(results, catalog=None):
    drafts, seen = [], set()
    for chunk, raw in results:
        parsed = validate_result(chunk, raw)
        source = chunk['payload']['source']
        metadata = chunk['payload']['metadata']
        for mention in parsed['mentions']:
            # Drop only exact replays from overlap; different claims, branches,
            # citations and publishers remain separate, preserving disagreement.
            key = fingerprint({'source': source['external_id'], 'mention': mention})
            if key in seen: continue
            seen.add(key)
            # Consolidate an overlap occurrence only when its same-source
            # identity AND at least one exact cited quote agree. Do not merge
            # two distant occurrences based on a name alone.
            same = next((d for d in drafts if d['source']['external_id'] == source['external_id'] and
                (normalize_text(d['name']), d['kind'], d['branch']) == (normalize_text(mention['name']), mention['kind'], mention['branch']) and
                {fingerprint(c) for c in d['citations']} & {fingerprint(c) for c in mention['citations']} and
                d['stance'] == mention['stance'] and d['rating'] == mention['rating'] and
                d['experience'] == mention['experience']), None)
            if same:
                if same['name']!=mention['name'] and mention['name'] not in same['aliases']:
                    same['aliases'].append(mention['name'])
                if same['identity_uncertain'] or mention['identity_uncertain']:
                    reasons=list(dict.fromkeys(r for r in (same['identity_uncertainty_reason'],mention['identity_uncertainty_reason']) if r))
                    same['identity_uncertain']=True
                    same['identity_uncertainty_reason']='; '.join(reasons) or 'Merged occurrences require identity review'
                for field in ('claims', 'citations', 'categories', 'aliases'):
                    known = {fingerprint(v) for v in same[field]}
                    same[field].extend(v for v in mention[field] if fingerprint(v) not in known)
                continue
            drafts.append({'id': key, **mention, 'source': source,
                'source_evidence_sha256': chunk['payload']['source_evidence_sha256'],
                'publisher_group': metadata.get('publisher_group') or metadata.get('channel_id') or 'unknown_publisher',
                'source_content_note': metadata.get('content_note'),
                'published_at': metadata.get('published_at'), 'identity_candidates': identity_candidates(mention, catalog),
                'status': 'evidence_validated_not_fact_checked', 'requires_current_check': True})
    groups = {}
    for draft in drafts:
        key = (normalize_text(draft['name']), draft['kind'], normalize_text(draft['branch'] or ''))
        groups.setdefault(key, []).append(draft)
    review = [{'name': key[0], 'kind': key[1], 'branch': key[2], 'draft_ids': [d['id'] for d in group],
               'independent_publisher_count': len({d['publisher_group'] for d in group} - {'unknown_publisher'}),
               'unknown_publisher_mention_count': sum(d['publisher_group']=='unknown_publisher' for d in group),
               'decision': 'possible_duplicates_not_merged; confirm_identity_and_copy_relationships'}
              for key, group in groups.items()]
    linked={}
    for draft in drafts:
        for candidate in draft['identity_candidates']:
            linked.setdefault(candidate['entity_id'],set()).add(draft['id'])
    identity_links=[{'candidate_entity_id':entity,'draft_ids':sorted(ids),
        'decision':'shared_candidate_not_merged; verify_multilingual_names_and_branch'}
        for entity,ids in linked.items() if len(ids)>1]
    return {'version': 1, 'status': 'private_draft_needs_identity_and_fact_review',
            'drafts': drafts, 'review_queue': review, 'identity_link_review_queue':identity_links,'catalog_writes': 0}


def execute_chunks(chunks, provider, cache_dir, *, max_attempts=2):
    """Provider injection supports bounded approved runners and offline evals.

    Invalid/refused responses never enter drafts. A checkpoint caches ONLY
    validated results and exact request fingerprints; failures allow partial use.
    """
    if not 1 <= max_attempts <= 3: raise ValueError('Invalid retry cap')
    directory = Path(cache_dir); directory.mkdir(parents=True, exist_ok=True)
    results, errors = [], []
    for chunk_index,chunk in enumerate(chunks):
        path = directory / (chunk['id'] + '.json')
        if path.exists():
            cached = json.loads(path.read_text())
            if cached.get('request_sha256') != fingerprint(chunk):
                raise ValueError('Cache request mismatch')
            results.append((chunk, validate_result(chunk, cached['result'])))
            if cached.get('quarantine'):
                errors.append({'chunk_id':chunk['id'],'error_type':'PartialEvidenceValidation',
                    'quarantine':cached['quarantine'],'accepted_mentions':len(cached['result']['mentions'])})
            continue
        feedback=None
        for attempt in range(max_attempts):
            candidate=None
            try:
                request={**chunk,'validation_feedback':feedback} if feedback else chunk
                candidate=provider(request)
                from .review import partition_mentions
                parsed,rejected,repairs = partition_mentions(chunk,candidate)
                if rejected and not parsed['mentions']:
                    raise ValueError('No evidence-valid mentions: '+rejected[0]['reason'])
                parsed=validate_result(chunk,parsed)
                with path.open('x') as stream:
                    json.dump({'request_sha256': fingerprint(chunk), 'result': parsed,
                        'quarantine':rejected,'citation_repairs':repairs}, stream, ensure_ascii=False)
                if rejected:
                    errors.append({'chunk_id':chunk['id'],'error_type':'PartialEvidenceValidation',
                        'quarantine':rejected,'accepted_mentions':len(parsed['mentions'])})
                results.append((chunk, parsed)); break
            except Exception as exc:
                diagnostic={'chunk_id':chunk['id'],'attempt_in_run':attempt+1,'error_type':type(exc).__name__,
                    'candidate_status':'unvalidated_not_publishable','candidate':candidate}
                if type(exc) is ValueError or type(exc).__name__ in {'BudgetError','ProviderConfigurationError'}:
                    diagnostic['reason']=str(exc)
                else:diagnostic['reason']='Structured schema validation failed'
                diagnostics=directory/'diagnostics';diagnostics.mkdir(mode=0o700,exist_ok=True)
                with (diagnostics/(chunk['id']+'.'+uuid4().hex+'.json')).open('x') as stream:
                    json.dump(diagnostic,stream,ensure_ascii=False)
                feedback={'error':diagnostic['reason'],'untrusted_previous_candidate':candidate,
                    'instruction':'Re-extract from the original segments. Preserve exact quotes and original ASR name aliases; unsupported information stays unknown.'}
                if type(exc).__name__=='ProviderConfigurationError':
                    errors.append({'chunk_id':chunk['id'],'error_type':'ProviderConfigurationError','reason':str(exc)})
                    errors.extend({'chunk_id':remaining['id'],'error_type':'NotAttemptedProviderConfiguration'}
                        for remaining in chunks[chunk_index+1:])
                    return results,errors
                # Budget exhaustion is terminal for a chunk: retrying cannot
                # repair it and must never produce another provider call.
                if type(exc).__name__ == 'BudgetError':
                    errors.append({'chunk_id': chunk['id'], 'error_type': 'BudgetError','reason':str(exc)})
                    break
                if attempt == max_attempts - 1:
                    error={'chunk_id': chunk['id'], 'error_type': type(exc).__name__}
                    if type(exc) is ValueError:error['reason']=str(exc)
                    errors.append(error)
    return results, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--sources', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--responses-dir', type=Path, help='Reviewed provider JSON outputs named by chunk ID')
    parser.add_argument('--catalog', type=Path)
    parser.add_argument('--execute-luna', action='store_true')
    parser.add_argument('--env-file', type=Path, default=Path('.env'))
    parser.add_argument('--cache-dir', type=Path, default=Path('.local/stage3/extraction-cache'))
    parser.add_argument('--budget-ledger', type=Path, default=Path('.local/stage3/extraction-budget.sqlite'))
    parser.add_argument('--quality-report',type=Path,help='Passed reviewed quality gate required for more than six chunks')
    args = parser.parse_args()
    if args.execute_luna and args.responses_dir: parser.error('Choose Luna execution or supplied responses')
    # Reserve the destination before any provider execution, avoiding paid calls
    # followed by an existing-output failure. Keep a recoverable running report.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump({'version': 1, 'status': 'preparing', 'catalog_writes': 0}, stream)
    metadata = {}
    if args.sources:
        metadata = {s['external_id']: s for s in json.loads(args.sources.read_text())['sources']}
    chunks, excluded = [], []
    for file in sorted(args.evidence_dir.rglob('*.evidence.json')):
        evidence = json.loads(file.read_text())
        try:
            prepared, flags = chunk_evidence(evidence, metadata.get(evidence['source']['external_id']))
            chunks.extend(prepared)
        except ValueError as exc:
            flags = [str(exc)]
        if flags: excluded.append({'file': str(file), 'reasons': flags})
    output = {'version': 1, 'status': 'extraction_prepared_not_executed', 'chunks': chunks,
              'excluded': excluded, 'paid_calls': 0, 'catalog_writes': 0}
    if args.responses_dir:
        results, missing = [], []
        for chunk in chunks:
            path = args.responses_dir / (chunk['id'] + '.json')
            if path.exists(): results.append((chunk, json.loads(path.read_text())))
            else: missing.append(chunk['id'])
        output = {**aggregate(results, args.catalog), 'missing_chunk_ids': missing, 'excluded': excluded}
    if args.execute_luna:
        from .quality import require_scale_approval
        require_scale_approval(chunks,json.loads(args.quality_report.read_text()) if args.quality_report else None)
        from trippy_config import read_environment
        from .luna import make_provider
        args.budget_ledger.parent.mkdir(parents=True, exist_ok=True)
        provider = make_provider(read_environment(args.env_file), args.budget_ledger)
        results, errors = execute_chunks(chunks, provider, args.cache_dir)
        output = {**aggregate(results, args.catalog), 'failed_chunks': errors, 'excluded': excluded,
                  'provider': 'azure_configured_luna_only', 'execution_status': 'partial' if errors else 'complete'}
    temporary=args.output.with_name(args.output.name+'.tmp')
    temporary.write_text(json.dumps(output, ensure_ascii=False, indent=2));temporary.replace(args.output)
    print(json.dumps({'status': output['status'], 'chunks': len(chunks), 'excluded': len(excluded), 'catalog_writes': 0}))


if __name__ == '__main__': main()
