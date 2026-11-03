"""Import supplied, permitted transcripts as timestamped local evidence.

No video download, paid ASR, model extraction, or shared catalog publication.
"""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re

from .planner import canonical_video


TIMING = re.compile(r"^((?:\d{2,}:)?\d{2}:\d{2}[.,]\d{3})\s+-->\s+((?:\d{2,}:)?\d{2}:\d{2}[.,]\d{3})(?:\s.*)?$")


def seconds(value):
    parts = value.replace(",", ".").split(":")
    if len(parts) == 2:
        parts.insert(0, "0")
    hour, minute, second = int(parts[0]), int(parts[1]), float(parts[2])
    if minute >= 60 or second >= 60:
        raise ValueError("Invalid subtitle timestamp")
    return round(hour*3600 + minute*60 + second, 3)


def parse_transcript(text, kind):
    if len(text.encode()) > 5_000_000:
        raise ValueError("Transcript exceeds local byte cap")
    if kind == "txt":
        if not text.strip():
            raise ValueError("Empty transcript")
        return [{"start_seconds": None, "end_seconds": None, "text": text.strip()}]
    if kind not in {"srt", "vtt"}:
        raise ValueError("Use srt, vtt or txt")
    blocks = re.split(r"\n\s*\n", text.replace("\r\n", "\n").lstrip("\ufeff").strip())
    segments = []
    for block in blocks:
        lines = block.splitlines()
        if not lines or lines[0].startswith(("WEBVTT", "NOTE", "STYLE", "REGION")):
            continue
        index = next((i for i,line in enumerate(lines) if "-->" in line), None)
        if index is None:
            raise ValueError("Invalid subtitle block")
        match = TIMING.fullmatch(lines[index].strip())
        if not match:
            raise ValueError("Invalid subtitle timing")
        start, end = (seconds(x) for x in match.groups())
        body = "\n".join(lines[index+1:]).strip()
        if end <= start or not body or (segments and start < segments[-1]["start_seconds"]):
            raise ValueError("Invalid subtitle order, duration or empty text")
        segments.append({"start_seconds":start,"end_seconds":end,"text":body})
    if not segments:
        raise ValueError("No subtitle segments found")
    return segments


def evidence_document(url, text, kind, *, language, content_basis):
    if content_basis not in {"owned", "licensed", "creator_provided"}:
        raise ValueError("A permitted content basis is required")
    if not re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z]{2,4})?", language):
        raise ValueError("Invalid transcript language")
    return {"version":1, "source":canonical_video(url), "scope":"private_local_evidence",
            "language":language,"content_basis_declared":content_basis,
            "content_sha256":sha256(text.encode()).hexdigest(),"segments":parse_transcript(text,kind),
            "status":"evidence_imported_not_fact_checked", "catalog_writes":0,"model_calls":0,
            "retrieval_time_status":"unknown_unless_supplied_separately",
            "transcription_accuracy":"unverified_names_need_identity_review"}


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-url",required=True)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--format",choices=("srt","vtt","txt"),required=True)
    parser.add_argument("--language",required=True)
    parser.add_argument("--content-basis",choices=("owned","licensed","creator_provided"),required=True)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args(argv)
    if args.input.stat().st_size>5_000_000:parser.error("Transcript exceeds local byte cap")
    result=evidence_document(args.source_url,args.input.read_text(),args.format,
                             language=args.language,content_basis=args.content_basis)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open("x") as stream:json.dump(result,stream,ensure_ascii=False,indent=2)
    print(json.dumps({"status":result["status"],"segments":len(result["segments"]),"model_calls":0}))


if __name__=="__main__":main()
