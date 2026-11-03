"""Explicit user-requested audio batch, with bounded local storage and no login.

Downloading is not a content-reuse license. Rights stay unverified. No inference,
transcription, shared catalog publishing or browser cookies are used here.
"""

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import shutil
import time

from .planner import canonical_video


MAX_FILE_BYTES = 250_000_000
MIN_FREE_BYTES = 1_000_000_000


class QuietLog:
    def debug(self, message): pass
    def warning(self, message): pass
    def error(self, message): pass


def validated_sources(batch):
    if batch.get("version") != 1 or not isinstance(batch.get("sources"), list) or not 1 <= len(batch["sources"]) <= 100:
        raise ValueError("Expected a version-1 batch of 1–100 sources")
    sources, seen = [], set()
    for source in batch["sources"]:
        video = canonical_video(source["url"])
        if source.get("external_id") != video["external_id"]:
            raise ValueError("Source URL and ID mismatch")
        if video["external_id"] in seen:
            raise ValueError("Duplicate source ID in batch")
        seen.add(video["external_id"])
        sources.append({**video,"content_rights":"unverified",**{k:source[k] for k in
            ('language_hint','declared_audio_language','transcription_language','channel_id','channel_title','title','published_at','publisher_group') if k in source}})
    return sources


def file_hash(path):
    digest=sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b""):digest.update(chunk)
    return digest.hexdigest()


def download_one(source, directory, *, factory=None):
    if factory is None:
        from yt_dlp import YoutubeDL
        factory=YoutubeDL
    start=time.monotonic()

    def bounded_progress(state):
        if state.get("downloaded_bytes",0)>MAX_FILE_BYTES or time.monotonic()-start>900:
            raise ValueError("Audio byte/time cap reached")
        if shutil.disk_usage(directory).free<MIN_FREE_BYTES:
            raise ValueError("Storage reserve reached")

    def eligibility(info, *, incomplete=False):
        if info.get("is_live") or info.get("live_status") in {"is_live","is_upcoming"}:
            return "Live/upcoming streams are outside the finite audio batch"
        if info.get("has_drm"):
            return "DRM-protected content is unsupported"
        if info.get("filesize") and info["filesize"]>MAX_FILE_BYTES:
            return "Audio filesize cap exceeded"
        return None

    options={"format":"bestaudio[ext=m4a]/bestaudio", "noplaylist":True,
        "outtmpl":str(directory/(source["external_id"]+".%(ext)s")),
        "quiet":True,"no_warnings":True,"logger":QuietLog(),"overwrites":False,
        "retries":2,"fragment_retries":2,"extractor_retries":1,"socket_timeout":20,
        "max_filesize":MAX_FILE_BYTES,"progress_hooks":[bounded_progress],"match_filter":eligibility,
        "geo_bypass":False,"allow_unplayable_formats":False,"js_runtimes":{"node":{}},
        "remote_components":set(),"cachedir":False,"skip_download":False}
    with factory(options) as downloader:
        info=downloader.extract_info(source["url"],download=True)
    if not isinstance(info,dict) or info.get("id")!=source["external_id"]:
        raise ValueError("No matching downloadable audio")
    downloads=info.get("requested_downloads") or []
    if len(downloads)!=1:
        raise ValueError("Expected one audio-only output")
    output=Path(downloads[0].get("filepath", "")).resolve()
    if output.parent!=directory.resolve() or not output.is_file() or not 0<output.stat().st_size<=MAX_FILE_BYTES:
        raise ValueError("Audio output validation failed")
    if downloads[0].get("vcodec") not in (None,"none"):
        raise ValueError("Expected audio-only media")
    return {"status":"downloaded_not_transcribed","input":output.name,"bytes":output.stat().st_size,
            "sha256":file_hash(output),"duration_seconds":info.get("duration"),
            "acquired_at":datetime.now(timezone.utc).isoformat(),"content_rights":"unverified"}


def run_batch(batch, output_dir, *, downloader=download_one):
    sources=validated_sources(batch)
    output_dir=Path(output_dir).resolve()
    ancestor=output_dir
    while not ancestor.exists():ancestor=ancestor.parent
    if shutil.disk_usage(ancestor).free<MIN_FREE_BYTES+MAX_FILE_BYTES:
        raise ValueError("At least 1.25 GB free is required for the bounded audio batch")
    output_dir.parent.mkdir(parents=True,exist_ok=True)
    output_dir.mkdir(mode=0o700,exist_ok=False)
    report={"version":1,"status":"downloading","source_batch_sha256":sha256(json.dumps(batch,sort_keys=True).encode()).hexdigest(),
            "sources":[],"paid_calls":0,"model_calls":0,"catalog_writes":0,
            "content_rights":"unverified","max_file_bytes":MAX_FILE_BYTES,"min_storage_reserve_bytes":MIN_FREE_BYTES}
    def checkpoint():
        temporary=output_dir/"progress.json.tmp"
        temporary.write_text(json.dumps(report,ensure_ascii=False,indent=2))
        temporary.replace(output_dir/"progress.json")
    checkpoint()
    for source in sources:
        entry={**source,"status":"queued"}
        report["sources"].append(entry)
        checkpoint()
        if shutil.disk_usage(output_dir).free<MIN_FREE_BYTES+MAX_FILE_BYTES:
            entry["status"]="storage_limit_reached"
            report["status"]="incomplete_storage_limit"
            checkpoint()
            break
        try:entry.update(downloader(source,output_dir))
        except Exception as exc:
            entry.update(status="download_failed",error_type=type(exc).__name__)
        checkpoint()
        print(json.dumps({"source_id":source["external_id"],"status":entry["status"]}),flush=True)
    else:
        report["status"]="download_complete" if all(s["status"]=="downloaded_not_transcribed" for s in report["sources"]) else "download_incomplete"
    report["downloaded_count"]=sum(s["status"]=="downloaded_not_transcribed" for s in report["sources"])
    report["not_attempted_source_ids"]=[s["external_id"] for s in sources if s["external_id"] not in {r["external_id"] for r in report["sources"]}]
    checkpoint()
    return report


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch",type=Path,required=True)
    parser.add_argument("--output-dir",type=Path,required=True)
    args=parser.parse_args(argv)
    if args.batch.stat().st_size>1_000_000:parser.error("Batch manifest exceeds byte limit")
    report=run_batch(json.loads(args.batch.read_text()),args.output_dir)
    print(json.dumps({"status":report["status"],"downloaded":report["downloaded_count"]}))


if __name__=="__main__":main()
