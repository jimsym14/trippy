"""Offline whisper.cpp transcription of a completed local audio batch.

No paid API, video download or catalog publishing. Content rights and transcript
accuracy remain separate review states; processing does not establish permission.
"""

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
import math
from pathlib import Path
import shutil
import subprocess

from .transcripts import parse_transcript, TIMING, seconds
import re
from .planner import canonical_video
from .extraction import quality_flags


ROOT=Path(__file__).resolve().parents[2]
DEFAULT_ENGINE=ROOT/'.local/asr/build-v1.9.5-relocated/bin/whisper-cli'
DEFAULT_MODEL=ROOT/'.local/asr/ggml-small.bin'
MODEL_SHA256='1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b'


def digest_file(path):
    digest=sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    return digest.hexdigest()


def probe_duration(path):
    result=subprocess.run(['ffprobe','-v','error','-protocol_whitelist','file,pipe','-show_entries',
        'format=duration','-of','json',str(path)],stdin=subprocess.DEVNULL,capture_output=True,timeout=30,check=True)
    seconds=float(json.loads(result.stdout)['format']['duration'])
    if not math.isfinite(seconds) or not 0<seconds<=7200:
        raise ValueError('Local audio must have a finite duration no longer than two hours')
    return seconds


def parse_whisper_vtt(text):
    """Retain raw output; exclude only zero-duration cues, never invent times.

    Other malformed timing still fails the strict parser. Exclusions are returned
    for review so a structurally usable transcript isn't presented as complete.
    """
    blocks=re.split(r'\n\s*\n',text.replace('\r\n','\n').strip())
    retained,excluded=[],[]
    for block in blocks:
        timing=next((line for line in block.splitlines() if '-->' in line),None)
        match=TIMING.fullmatch(timing.strip()) if timing else None
        if match and seconds(match.group(1))==seconds(match.group(2)):
            excluded.append({'reason':'zero_duration_asr_cue','raw_block':block})
        else:retained.append(block)
    return parse_transcript('\n\n'.join(retained),'vtt'),excluded


def transcribe_file(source, output, *, base_dir=None, engine=DEFAULT_ENGINE, model=DEFAULT_MODEL, language='auto', cpu_only=False):
    if canonical_video(source['url'])['external_id']!=source['external_id']:
        raise ValueError('Source identity mismatch')
    audio=Path(source['input'])
    if not audio.is_absolute() and base_dir is not None:audio=Path(base_dir)/audio
    audio=audio.resolve()
    if not audio.is_file() or audio.stat().st_size>250_000_000:
        raise ValueError('Missing audio or file byte cap exceeded')
    if digest_file(audio)!=source['sha256']:
        raise ValueError('Downloaded audio changed since its receipt')
    duration=probe_duration(audio)
    required_bytes=int(duration*32000)+100_000_000
    if shutil.disk_usage(output).free<required_bytes+1_000_000_000:
        raise ValueError('Insufficient space for PCM conversion and storage reserve')
    stem=output/source['external_id']
    wav=stem.with_suffix('.wav')
    log=stem.with_suffix('.log')
    with log.open('x') as stream:
        subprocess.run(['ffmpeg','-n','-nostdin','-hide_banner','-loglevel','error','-protocol_whitelist','file,pipe',
            '-i',str(audio),'-map','0:a:0','-vn','-ac','1','-ar','16000','-c:a','pcm_s16le',str(wav)],
            stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=stream,timeout=120,check=True)
        command=[str(engine),'-m',str(model),'-f',str(wav),'-l',language,'-t','4','-ovtt','-oj','-of',str(stem),'-np']
        if cpu_only:command.append('-ng')
        subprocess.run(command,stdin=subprocess.DEVNULL,stdout=stream,stderr=stream,
                       timeout=min(7200,max(300,int(duration*2))),check=True)
    return emit_evidence(source,stem,duration,model_sha256=digest_file(model),language=language)


def emit_evidence(source,stem,duration,*,model_sha256,language,recovered=False):
    """Validate completed raw ASR artifacts; writes private evidence only.

    The caller provides the verified model receipt for its own completed job.
    Recovery retains the original raw VTT and explicitly audits excluded cues.
    """
    vtt=stem.with_suffix('.vtt').read_text()
    detail=json.loads(stem.with_suffix('.json').read_text())
    segments,excluded_cues=parse_whisper_vtt(vtt)
    outside=[s for s in segments if s['end_seconds']>duration+2]
    excluded_cues.extend({'reason':'beyond_audio_duration','original_segment':s} for s in outside)
    segments=[s for s in segments if s['end_seconds']<=duration+2]
    if not segments:raise ValueError('No valid transcript cues within audio duration')
    evidence={'version':1,'source':{'provider':source['provider'],'external_id':source['external_id'],'url':source['url']},
        'scope':'private_local_evidence','content_rights':source.get('content_rights','unverified'),
        'transcription_backend':'local_whisper_cpp','model_sha256':model_sha256,
        'language':detail.get('result',{}).get('language'), 'language_selection':language,
        'audio_sha256':source['sha256'],'transcript_sha256':sha256(vtt.encode()).hexdigest(),
        'audio_duration_seconds':duration,
        'excluded_cues':excluded_cues,
        'coverage_status':'partial_invalid_cues_excluded' if excluded_cues else 'structurally_complete',
        'recovered_completed_raw_output':recovered,
        'transcribed_at':datetime.now(timezone.utc).isoformat(),'source_observed_time_status':'unknown',
        'segments':segments,'status':'transcribed_not_fact_checked','model_api_calls':0,'catalog_writes':0}
    with stem.with_suffix('.evidence.json').open('x') as stream:json.dump(evidence,stream,ensure_ascii=False,indent=2)
    return {'status':'transcribed_not_fact_checked','evidence_file':str(stem.with_suffix('.evidence.json')),
            'language':evidence['language'],'segments':len(segments),'duration_seconds':duration,
            'quality_flags':quality_flags(evidence)}


def evidence_matches_vtt(evidence,vtt,*,duration=None):
    try:
        segments,_=parse_whisper_vtt(vtt.read_text())
        if duration is not None:segments=[s for s in segments if s['end_seconds']<=duration+2]
        else:
            excluded=[c['original_segment'] for c in evidence.get('excluded_cues',[]) if c.get('reason')=='beyond_audio_duration']
            segments=[s for s in segments if s not in excluded]
        return segments==evidence.get('segments')
    except ValueError:return False


def source_language(source, requested='auto'):
    if requested!='auto':return requested
    declared=source.get('transcription_language') or source.get('declared_audio_language') or 'auto'
    language=declared.split('-')[0]
    return language if language in {'el','en','es','ca'} else 'auto'


def reusable_evidence(source, directories):
    for directory in directories:
        for file in Path(directory).rglob(source['external_id'] + '.evidence.json'):
            try:
                evidence=json.loads(file.read_text())
                vtt=file.with_name(file.name.replace('.evidence.json','.vtt'))
                if (evidence['source']['external_id']==source['external_id'] and
                    evidence['audio_sha256']==source['sha256'] and evidence['model_sha256']==MODEL_SHA256 and
                    vtt.is_file() and digest_file(vtt)==evidence.get('transcript_sha256') and
                    evidence_matches_vtt(evidence,vtt,duration=source.get('audio_duration_seconds')) and
                    not quality_flags(evidence)):
                    return {'status':'transcribed_not_fact_checked','evidence_file':str(file.resolve()),
                            'language':evidence['language'],'segments':len(evidence['segments']),
                            'reused':True,'quality_flags':[]}
            except (ValueError,KeyError):
                continue
    return None


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--batch',type=Path,required=True,help='Completed download progress.json')
    parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--language',choices=('auto','el','en','es','ca'),default='auto')
    parser.add_argument('--limit',type=int,default=20)
    parser.add_argument('--cpu-only',action='store_true')
    parser.add_argument('--resume',action='store_true')
    parser.add_argument('--reuse-dir',type=Path,action='append',default=[])
    args=parser.parse_args(argv)
    if not 1<=args.limit<=100:parser.error('Choose 1–100 audio files per batch')
    if args.batch.stat().st_size>2_000_000:parser.error('Batch manifest exceeds size cap')
    batch=json.loads(args.batch.read_text())
    if batch.get('version')!=1:parser.error('Unsupported batch version')
    sources=[s for s in batch['sources'] if s['status']=='downloaded_not_transcribed'][:args.limit]
    if not sources:parser.error('No downloaded audio in this batch')
    if not DEFAULT_ENGINE.is_file() or not DEFAULT_MODEL.is_file():parser.error('Local Whisper installation missing')
    if digest_file(DEFAULT_MODEL)!=MODEL_SHA256:parser.error('Local transcription model hash mismatch')
    output=args.output_dir.resolve();output.parent.mkdir(parents=True,exist_ok=True);output.mkdir(mode=0o700,exist_ok=args.resume)
    report={'version':1,'status':'transcribing','sources':[],'paid_calls':0,'catalog_writes':0}
    def checkpoint():
        tmp=output/'progress.json.tmp';tmp.write_text(json.dumps(report,ensure_ascii=False,indent=2));tmp.replace(output/'progress.json')
    checkpoint()
    for source in sources:
        entry={'external_id':source['external_id'],'status':'transcribing'};report['sources'].append(entry);checkpoint()
        try:
            audio=Path(source['input'])
            if not audio.is_absolute():audio=args.batch.resolve().parent/audio
            if digest_file(audio)!=source['sha256']:raise ValueError('Audio receipt hash mismatch')
            source={**source,'audio_duration_seconds':probe_duration(audio)}
            reused=reusable_evidence(source,[output,*args.reuse_dir])
            if reused:entry.update(reused)
            else:
                attempt=output/source['external_id'];attempt.mkdir(exist_ok=True)
                run=attempt/('attempt-'+str(len(list(attempt.iterdir()))+1));run.mkdir()
                language=source_language(source,args.language)
                entry.update(transcribe_file(source,run,base_dir=args.batch.resolve().parent,language=language,cpu_only=args.cpu_only))
        except Exception as exc:
            entry.update(status='transcription_failed',error_type=type(exc).__name__)
            if isinstance(exc,ValueError):entry['error_reason']=str(exc)
        checkpoint();print(json.dumps(entry),flush=True)
    report['status']='transcription_complete' if all(s['status']=='transcribed_not_fact_checked' for s in report['sources']) else 'transcription_incomplete'
    checkpoint()


if __name__=='__main__':main()
