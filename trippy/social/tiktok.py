"""Python twin of the iOS TikTokPageReader, used by the test harness (and as a server fallback).

Reads a public post page the way Safari loads it: no login, anonymous cookies only.
"""
from __future__ import annotations

import http.cookiejar
import json
import re
import subprocess
import tempfile
import urllib.request
from pathlib import Path

UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
_BLOB = re.compile(r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>', re.S)


class Reader:
    def __init__(self, timeout=20):
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))
        self.timeout = timeout
        self.video_url = None

    def _get(self, url, accept="text/html", referer=None):
        headers = {"User-Agent": UA, "Accept": accept, "Accept-Language": "en-US,en;q=0.9"}
        if referer:
            headers["Referer"] = referer
        with self.opener.open(urllib.request.Request(url, headers=headers), timeout=self.timeout) as response:
            return response.geturl(), response.headers.get_content_type(), response.read(80_000_000)

    def _item(self, url):
        final, _, body = self._get(url)
        match = _BLOB.search(body.decode("utf-8", "replace"))
        if not match:
            return None, final
        scope = json.loads(match.group(1)).get("__DEFAULT_SCOPE__", {})
        detail = scope.get("webapp.video-detail") or scope.get("webapp.reflow.video.detail") or {}
        item = (detail.get("itemInfo") or {}).get("itemStruct") or {}
        return (item if item.get("id") else None), final

    def read(self, url, max_slides=35):
        item, final = self._item(url)
        if item is None:
            for a, b in (("/video/", "/photo/"), ("/photo/", "/video/")):
                if a in final:
                    self.jar.clear()  # TikTok refuses the retry when the first visit's cookies are sent
                    item, final = self._item(final.replace(a, b))
                    break
        if item is None:
            raise LookupError("post unavailable")
        video = item.get("video") or {}
        image_post = item.get("imagePost") or {}
        images = image_post.get("images") or []
        self.video_url = video.get("playAddr") or None
        transcript = language = None
        for track in video.get("subtitleInfos") or []:
            if (track.get("Format") or "").lower() == "webvtt" and track.get("Url"):
                _, _, vtt = self._get(track["Url"], "*/*")
                transcript, language = vtt_text(vtt.decode("utf-8", "replace")), track.get("LanguageCodeName")
                break
        slides = []
        for image in images[:max_slides]:
            links = (image.get("imageURL") or {}).get("urlList") or []
            if links:
                _, mime, data = self._get(links[0], "image/*")
                slides.append((mime if mime.startswith("image/") else "image/jpeg", data))
        stats = item.get("stats") or {}
        extras = item.get("textExtra") or []
        return {
            "id": item["id"], "url": final, "slideshow": bool(images),
            "author": (item.get("author") or {}).get("uniqueId"),
            "caption": (item.get("desc") or "").strip(), "slideshow_title": image_post.get("title"),
            "on_screen_text": [t.strip() for s in item.get("stickersOnItem") or [] for t in s.get("stickerText") or [] if t.strip()],
            "transcript": transcript, "transcript_language": language,
            "duration": video.get("duration"), "region": item.get("locationCreated"),
            "labels": item.get("diversificationLabels") or [],
            "mentions": [e.get("userUniqueId") for e in extras if e.get("userUniqueId")],
            "likes": stats.get("diggCount"), "saves": stats.get("collectCount"), "slides": slides,
        }

    def video(self, max_bytes=9_000_000, max_seconds=300):
        """Download the video and shrink it for Gemini: 1 fps (Gemini samples at 1 fps anyway), 540 px wide,
        mono 32k audio. On-screen place names survive; a 60 s post comes out around 1 MB."""
        if not self.video_url:
            return None
        _, _, data = self._get(self.video_url, "*/*", referer="https://www.tiktok.com/")
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder, "v.mp4"), Path(folder, "small.mp4")
            source.write_bytes(data)
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(source), "-t", str(max_seconds),
                            "-vf", "fps=1,scale='min(540,iw)':-2", "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
                            "-pix_fmt", "yuv420p", "-c:a", "aac", "-ac", "1", "-ar", "16000", "-b:a", "32k",
                            "-movflags", "+faststart", str(target)], check=True)
            small = target.read_bytes()
            return ("video/mp4", small) if len(small) <= max_bytes else None

    def audio(self, bitrate="32k"):
        """Download the video with this session's cookies and keep only a small mono AAC track."""
        if not self.video_url:
            return None
        _, _, data = self._get(self.video_url, "*/*", referer="https://www.tiktok.com/")
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder, "v.mp4"), Path(folder, "a.m4a")
            source.write_bytes(data)
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(source), "-vn", "-ac", "1", "-ar", "16000", "-b:a", bitrate, str(target)], check=True)
            return "audio/mp4", target.read_bytes()


def vtt_text(vtt):
    lines = []
    for raw in vtt.splitlines():
        line = raw.strip()
        if not line or line == "WEBVTT" or "-->" in line or line.isdigit():
            continue
        if not lines or lines[-1] != line:
            lines.append(line)
    return " ".join(lines)


def evidence(post):
    blocks = []
    if post["caption"]:
        blocks.append({"origin": "post_caption", "text": post["caption"]})
    if post.get("slideshow_title"):
        blocks.append({"origin": "post_caption", "text": post["slideshow_title"]})
    if post["on_screen_text"]:
        blocks.append({"origin": "on_screen_text", "text": "\n".join(post["on_screen_text"])})
    if post["transcript"]:
        blocks.append({"origin": "auto_caption", "text": post["transcript"]})
    return blocks
