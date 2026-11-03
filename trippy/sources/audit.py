"""Consolidate creator transcript receipts into a curated extraction input batch."""
import argparse
from collections import Counter
import json
from pathlib import Path
import shutil

from .asr import MODEL_SHA256, digest_file, evidence_matches_vtt, probe_duration
from .extraction import quality_flags
from .planner import canonical_video


def audit_sources(sources, download_manifests, evidence_directories):
    receipts = {};durations={}
    for manifest in download_manifests:
        path = Path(manifest).resolve()
        for receipt in json.loads(path.read_text())['sources']:
            if receipt.get('sha256'):
                audio = Path(receipt['input'])
                if not audio.is_absolute(): audio = path.parent / audio
                if audio.is_file() and digest_file(audio) == receipt['sha256']:
                    receipts.setdefault(receipt['external_id'], set()).add(receipt['sha256'])
                    durations[receipt['sha256']]=probe_duration(audio)
    entries = []
    for source in sources:
        identifier = canonical_video(source['url'])['external_id']
        if identifier != source['external_id']: raise ValueError('Source identity mismatch')
        entry = {'external_id': identifier, 'title': source.get('title'),
                 'creator': source.get('channel_title'), 'status': 'missing_or_failed', 'attempts': []}
        for directory in evidence_directories:
            for file in sorted(Path(directory).rglob(identifier+'.evidence.json')):
                try:
                    evidence = json.loads(file.read_text())
                    vtt = file.with_name(file.name.replace('.evidence.json', '.vtt'))
                    flags = quality_flags(evidence)
                    if (evidence['source']['external_id'] != identifier or
                        evidence.get('audio_sha256') not in receipts.get(identifier, set()) or
                        evidence.get('model_sha256') != MODEL_SHA256 or not vtt.is_file() or
                        digest_file(vtt) != evidence.get('transcript_sha256')):
                        flags.append('receipt_or_source_hash_mismatch')
                    elif not evidence_matches_vtt(evidence,vtt,duration=durations.get(evidence['audio_sha256'])):
                        flags.append('evidence_segments_differ_from_original_vtt')
                    entry['attempts'].append({'file': str(file.resolve()), 'quality_flags': flags})
                    if not flags and entry['status'] != 'transcribed_needs_identity_and_fact_review':
                        entry.update(status='transcribed_needs_identity_and_fact_review',
                            evidence_file=str(file.resolve()), vtt_file=str(vtt.resolve()),
                            segments=len(evidence['segments']), language=evidence['language'],
                            excluded_cue_count=len(evidence.get('excluded_cues', [])),
                            recovered_raw_output=evidence.get('recovered_completed_raw_output', False))
                    elif flags and entry['status'] == 'missing_or_failed':
                        entry['status'] = 'excluded_low_quality_or_bad_receipt'
                except (ValueError, KeyError):
                    entry['attempts'].append({'file': str(file.resolve()), 'quality_flags': ['invalid_evidence']})
        entries.append(entry)
    return {'version': 1, 'status': 'transcript_receipt_audit_complete', 'sources': entries,
            'counts': dict(Counter(e['status'] for e in entries)), 'catalog_writes': 0, 'paid_calls': 0}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sources', type=Path, required=True)
    p.add_argument('--downloads', type=Path, action='append', required=True)
    p.add_argument('--transcripts', type=Path, action='append', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--curated-dir', type=Path)
    args = p.parse_args()
    if args.output.exists() or (args.curated_dir and args.curated_dir.exists()):
        p.error('Choose new audit and curated output paths')
    sources = json.loads(args.sources.read_text())['sources']
    report = audit_sources(sources, args.downloads, args.transcripts)
    if args.curated_dir:
        args.curated_dir.mkdir(parents=True, mode=0o700)
        for entry in report['sources']:
            if entry['status'] != 'transcribed_needs_identity_and_fact_review': continue
            for key in ('evidence_file', 'vtt_file'):
                source = Path(entry[key]); shutil.copyfile(source, args.curated_dir/source.name)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream: json.dump(report, stream, ensure_ascii=False, indent=2)
    print(json.dumps({'status': report['status'], 'counts': report['counts']}))


if __name__ == '__main__': main()
