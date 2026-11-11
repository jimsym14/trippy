"""Gemini free-tier pool: try models in preference order, park a model when it hits
its rate limit (until the retry delay, or until the daily reset at midnight Pacific),
and fall through to the next one. Uses the REST API directly (no SDK dependency).
"""
from __future__ import annotations

import base64
import json
import re
import threading
import time
from datetime import datetime, timedelta
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

API = "https://generativelanguage.googleapis.com/v1beta"
PACIFIC = ZoneInfo("America/Los_Angeles")


class GeminiUnavailable(RuntimeError):
    """Every model is parked or failing; `retry_at` says when one frees up."""

    def __init__(self, message, retry_at=None):
        super().__init__(message)
        self.retry_at = retry_at


def next_pacific_midnight(now=None):
    now = (now or datetime.now(PACIFIC)).astimezone(PACIFIC)
    tomorrow = (now + timedelta(days=1)).replace(hour=0, minute=0, second=5, microsecond=0)
    return tomorrow.timestamp()


def _flash_rank(name):
    """Prefer newer Flash, then newer Flash-Lite. Pro is not on the free tier."""
    match = re.search(r"gemini-(\d+(?:\.\d+)?)-(flash(?:-lite)?)", name)
    if not match:
        return None
    version, family = float(match.group(1)), match.group(2)
    if version < 3 or any(tag in name for tag in ("tts", "image", "live", "embedding", "audio", "thinking-exp")):
        return None
    return (0 if family == "flash" else 1, -version, "preview" in name or "exp" in name, name)


class GeminiPool:
    def __init__(self, api_key, models=None, *, opener=urlopen, clock=time.time, timeout=60):
        if not api_key:
            raise ValueError("GEMINI_API_KEY is not configured")
        self.api_key = api_key
        self._models = [m.strip() for m in (models or []) if m.strip()]
        self._parked = {}
        self._lock = threading.Lock()
        self._open = opener
        self._clock = clock
        self.timeout = timeout

    # -- model discovery -------------------------------------------------
    def models(self):
        if not self._models:
            self._models = self.discover()
        return list(self._models)

    def discover(self):
        request = Request(f"{API}/models?pageSize=200", headers={"x-goog-api-key": self.api_key})
        with self._open(request, timeout=20) as response:
            payload = json.loads(response.read())
        ranked = []
        for model in payload.get("models", []):
            name = model.get("name", "").removeprefix("models/")
            if "generateContent" not in model.get("supportedGenerationMethods", []):
                continue
            rank = _flash_rank(name)
            if rank:
                ranked.append(rank)
        ranked.sort()
        return [rank[-1] for rank in ranked][:6]

    def status(self):
        now = self._clock()
        return [{"model": m, "parked_for_seconds": max(0, int(self._parked.get(m, 0) - now))} for m in self.models()]

    # -- generation ------------------------------------------------------
    def generate(self, parts, *, schema=None, system=None, temperature=0.2, thinking_budget=None):
        body = {"contents": [{"role": "user", "parts": parts}],
                "generationConfig": {"temperature": temperature, "responseMimeType": "application/json"}}
        if schema:
            body["generationConfig"]["responseSchema"] = schema
        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}
        if thinking_budget is not None:
            # Writing tasks need no reasoning; 0 saves the thought tokens that count against free TPM.
            body["generationConfig"]["thinkingConfig"] = {"thinkingBudget": thinking_budget}
        errors, soonest = [], None
        for model in self.models():
            with self._lock:
                parked = self._parked.get(model, 0)
            if parked > self._clock():
                soonest = parked if soonest is None else min(soonest, parked)
                continue
            try:
                return self._call(model, body), model
            except HTTPError as error:
                detail = self._error_detail(error)
                if error.code == 429:
                    until = self._park_until(detail)
                    with self._lock:
                        self._parked[model] = until
                    soonest = until if soonest is None else min(soonest, until)
                    errors.append(f"{model}: rate limited")
                    continue
                message = detail.get("message", "").lower()
                if error.code == 400 and "thinking" in message and "thinkingConfig" in body["generationConfig"]:
                    body["generationConfig"].pop("thinkingConfig")  # model without the knob: retry plainly
                    try:
                        return self._call(model, body), model
                    except HTTPError:
                        pass
                if error.code == 404 or (error.code == 400 and ("not found" in message or "no longer available" in message)):
                    self._rest(model, 24 * 3600)  # retired or not enabled for this key
                    errors.append(f"{model}: unavailable")
                    continue
                if error.code >= 500:
                    self._rest(model, 300)  # overloaded: try the next model, come back in 5 minutes
                    errors.append(f"{model}: HTTP {error.code}")
                    continue
                raise GeminiUnavailable(f"{model}: {detail.get('message', 'request rejected')}"[:400])
            except (URLError, TimeoutError, OSError) as error:
                self._rest(model, 1800)  # a model that times out tends to keep doing so; skip it for 30 min
                errors.append(f"{model}: {type(error).__name__}")
                continue
        raise GeminiUnavailable("; ".join(errors) or "no Gemini model available", soonest)

    def _rest(self, model, seconds):
        with self._lock:
            self._parked[model] = max(self._parked.get(model, 0), self._clock() + seconds)

    def _call(self, model, body):
        from trippy import usage
        usage.hit('ai:gemini')
        request = Request(f"{API}/models/{model}:generateContent", data=json.dumps(body).encode(),
                          headers={"x-goog-api-key": self.api_key, "Content-Type": "application/json"}, method="POST")
        from trippy import call_log
        with call_log.track('ai:gemini', model=model) as call:
            with self._open(request, timeout=self.timeout) as response:
                payload = json.loads(response.read())
            meta = payload.get('usageMetadata') or {}
            call.tokens(meta.get('promptTokenCount'), meta.get('candidatesTokenCount'))
        candidates = payload.get("candidates") or []
        if not candidates:
            raise GeminiUnavailable(f"{model}: empty response ({payload.get('promptFeedback', {}).get('blockReason', 'no candidates')})")
        text = "".join(part.get("text", "") for part in candidates[0].get("content", {}).get("parts", []))
        return json.loads(text)

    @staticmethod
    def _error_detail(error):
        try:
            payload = json.loads(error.read(65536) or b"{}")
            return payload.get("error", {}) if isinstance(payload, dict) else {}
        except (ValueError, TypeError):
            return {}

    def _park_until(self, detail):
        now = self._clock()
        text = json.dumps(detail)
        if "PerDay" in text or "per day" in text.lower():
            return next_pacific_midnight()
        for item in detail.get("details", []):
            delay = item.get("retryDelay")
            if isinstance(delay, str) and delay.endswith("s"):
                try:
                    return now + float(delay[:-1]) + 1
                except ValueError:
                    pass
        return now + 60


def inline(mime, data: bytes):
    return {"inline_data": {"mime_type": mime, "data": base64.b64encode(data).decode()}}
