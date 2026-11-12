import base64
import io
import json
import time
import unittest
import uuid
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import urlsplit

import bridge_server as bridge
from trippy.social import extract as ex
from trippy.social.gemini import GeminiPool, GeminiUnavailable
from trippy.social.tiktok import vtt_text


class FakeResponse(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *a): return False


def reply(payload):
    return FakeResponse(json.dumps({"candidates": [{"content": {"parts": [{"text": json.dumps(payload)}]}}]}).encode())


def rate_limited(daily=False):
    detail = {"error": {"code": 429, "message": "Quota exceeded", "details": [
        {"@type": "type.googleapis.com/google.rpc.QuotaFailure", "violations": [{"quotaId": "GenerateRequestsPerDayPerProjectPerModel-FreeTier" if daily else "GenerateRequestsPerMinutePerProjectPerModel-FreeTier"}]},
        {"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "30s"}]}}
    return HTTPError("u", 429, "Too Many", {}, io.BytesIO(json.dumps(detail).encode()))


RESULT = {"post_title": "Cozy", "post_summary": "s", "transcript": "", "city": "Athens", "country": "Greece", "country_code": "GR",
          "unresolved": [], "places": [
              {"name": "Easy Peasy", "category": "Coffee", "search_query": "Easy Peasy, Peristeri, Athens", "vibe_tags": ["Cozy", "Summer", "Rooftop", "Extra"],
               "tldr": "t", "pro_tips": [" a ", ""], "good_to_know": [], "must_try": [], "why_go": ["w"], "evidence": ["slide 6"], "confidence": 0.9},
              {"name": "easy peasy", "category": "Coffee", "search_query": "x", "vibe_tags": [], "tldr": "", "pro_tips": [], "good_to_know": [],
               "must_try": [], "why_go": [], "evidence": [], "confidence": 0.9},
              {"name": "Maybe", "category": "Nope", "search_query": "x", "vibe_tags": [], "tldr": "", "pro_tips": [], "good_to_know": [],
               "must_try": [], "why_go": [], "evidence": [], "confidence": 0.1}]}


class GeminiPoolTests(unittest.TestCase):
    def test_falls_through_and_parks_rate_limited_model(self):
        calls = []
        def opener(request, timeout=0):
            calls.append(request.full_url)
            if "model-a" in request.full_url: raise rate_limited()
            return reply({"ok": True})
        now = [1000.0]
        pool = GeminiPool("k", ["model-a", "model-b"], opener=opener, clock=lambda: now[0])
        self.assertEqual(pool.generate([{"text": "x"}]), ({"ok": True}, "model-b"))
        pool.generate([{"text": "x"}])
        self.assertEqual(sum("model-a" in c for c in calls), 1, "parked model is skipped until its retry delay")
        now[0] += 40
        pool.generate([{"text": "x"}])
        self.assertEqual(sum("model-a" in c for c in calls), 2)

    def test_daily_quota_parks_until_pacific_midnight(self):
        pool = GeminiPool("k", ["model-a"], opener=lambda r, timeout=0: (_ for _ in ()).throw(rate_limited(daily=True)))
        with self.assertRaises(GeminiUnavailable) as raised:
            pool.generate([{"text": "x"}])
        self.assertGreater(raised.exception.retry_at - time.time(), 60)

    def test_discovery_prefers_new_flash_then_lite(self):
        models = {"models": [{"name": f"models/{n}", "supportedGenerationMethods": ["generateContent"]} for n in
                  ["gemini-3.1-flash-lite", "gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite", "gemini-3.8-flash-tts", "gemini-4-argon"]]}
        pool = GeminiPool("k", opener=lambda r, timeout=0: FakeResponse(json.dumps(models).encode()))
        self.assertEqual(pool.models(), ["gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite"])


class ExtractTests(unittest.TestCase):
    def test_clean_dedupes_and_normalises(self):
        result = ex.clean(json.loads(json.dumps(RESULT)))
        self.assertEqual([p["name"] for p in result["places"]], ["Easy Peasy"])
        place = result["places"][0]
        self.assertEqual(place["vibe_tags"], ["Cozy", "Summer", "Rooftop"])
        self.assertEqual(place["pro_tips"], ["a"])
        self.assertEqual((place["city"], place["country_code"]), ("Athens", "GR"))

    def test_parts_include_slides_and_audio(self):
        parts = ex.build_parts({"url": "u", "evidence": [{"origin": "post_caption", "text": "cap"}],
                                "images": [("image/jpeg", b"1"), ("image/webp", b"2")], "audio": ("audio/mp4", b"a")})
        self.assertIn("[Caption]", parts[0]["text"])
        self.assertEqual([p["inline_data"]["mime_type"] for p in parts if "inline_data" in p], ["image/jpeg", "image/webp", "audio/mp4"])

    def test_video_replaces_audio_and_asks_for_frame_text(self):
        parts = ex.build_parts({"url": "u", "evidence": [], "images": [], "video": ("video/mp4", b"v"), "audio": ("audio/mp4", b"a")})
        self.assertIn("drawn on the frames", parts[0]["text"])
        self.assertEqual([p["inline_data"]["mime_type"] for p in parts if "inline_data" in p], ["video/mp4"])

    def test_enrich_rejects_wrong_country(self):
        result = ex.clean(json.loads(json.dumps(RESULT)))
        ex.enrich(result, lambda q: [{"placeID": "x", "name": "Easy Peasy NYC", "countryCode": "US", "latitude": 1, "longitude": 2}])
        self.assertNotIn("google", result["places"][0])
        ex.enrich(result, lambda q: [{"placeID": "p", "name": "Easy Peasy", "address": "Peristeri", "countryCode": "GR", "latitude": 38.0, "longitude": 23.7}])
        self.assertEqual(result["places"][0]["google"]["placeID"], "p")

    def test_queue_runs_job_and_is_idempotent(self):
        class Pool:
            calls = 0
            def generate(self, parts, **kw):
                Pool.calls += 1
                return json.loads(json.dumps(RESULT)), "fake-model"
        queue = ex.ExtractionQueue(lambda: Pool(), search=None)
        job_id = str(uuid.uuid4())
        queue.submit(job_id, {"evidence": [{"origin": "post_caption", "text": "📍 Cozy cafés in Athens"}]})
        for _ in range(100):
            if queue.get(job_id)["status"] == "ready": break
            time.sleep(0.02)
        job = queue.get(job_id)
        self.assertEqual(job["status"], "ready")
        self.assertEqual(job["result"]["model"], "fake-model")
        self.assertNotIn("source", job)
        queue.submit(job_id, {"evidence": [{"origin": "post_caption", "text": "📍 Cozy cafés in Athens"}]})
        self.assertEqual(Pool.calls, 1)   # clear travel text: no gate call, one read

    def test_gate_reads_free_text_first_and_never_trusts_the_caption_alone(self):
        self.assertEqual(ex.looks_like_travel(["8 spots to eat under 10€ in Rome"]), "yes")
        self.assertEqual(ex.looks_like_travel(["Θέλουμε να φάμε στο Παγκράτι, date night"]), "yes")
        self.assertEqual(ex.looks_like_travel(["GRWM for my first day at the gym, outfit and makeup"]), "no")
        # The Interrail slideshow has an empty caption; the slides carry everything. Unsure means: look.
        self.assertEqual(ex.looks_like_travel(["", ""]), "unsure")
        self.assertEqual(ex.looks_like_travel(["", "φθηνά ταξίδια με interrail, πόλεις και κόστος"]), "yes")

        class Pool:
            def __init__(self, answer): self.answer, self.calls = answer, 0
            def generate(self, parts, **kw):
                self.calls += 1
                if self.answer is None: raise RuntimeError("down")
                return {"relevant": self.answer}, "lite"
        empty = {"evidence": [{"origin": "post_caption", "text": ""}], "images": [b"jpeg"] * 9}
        no = Pool(False)
        self.assertEqual(ex.triage(no, empty), (False, "model"))
        self.assertEqual(no.calls, 1)
        self.assertEqual(ex.triage(Pool(None), empty), (True, "error"))   # a failing gate never drops a post
        clear = Pool(False)
        self.assertEqual(ex.triage(clear, {"evidence": [{"origin": "post_caption", "text": "Your guide for Rome #mustsee #traveltips"}]}), (True, "text"))
        self.assertEqual(clear.calls, 0)

    def test_off_topic_posts_keep_nothing_and_guides_are_normalised(self):
        off = ex.clean({**json.loads(json.dumps(RESULT)), "relevant": False})
        self.assertEqual((off["places"], off["tips"], off["guide_types"]), ([], [], []))
        route = ex.clean({**json.loads(json.dumps(RESULT)), "relevant": True, "guide_types": ["route", "tips", "bogus", "route"],
                          "theme": "Interrail on a budget",
                          "scope": {"level": "multi_country", "name": "Central Europe", "region": "Europe", "countries": ["cz", "AT", "hun"]},
                          "route": {"mode": "train", "days": 10, "cost_hint": "€350", "stops": [{"name": "Prague", "country_code": "cz", "nights": 3},
                                                                                              {"name": "Vienna", "country_code": "AT"}, {"name": ""}]},
                          "foods": [{"name": "Trdelník", "where": "Prague"}, {"detail": "no name"}]})
        self.assertEqual(route["guide_types"], ["route", "tips"])
        self.assertEqual(route["scope"], {"level": "multi_country", "name": "Central Europe", "region": "Europe", "countries": ["CZ", "AT"]})
        self.assertEqual([s["name"] for s in route["route"]["stops"]], ["Prague", "Vienna"])
        self.assertEqual(route["route"]["stops"][0]["country_code"], "CZ")
        self.assertEqual([f["name"] for f in route["foods"]], ["Trdelník"])
        # A route label with no stops is not a route.
        self.assertIsNone(ex.clean({**json.loads(json.dumps(RESULT)), "guide_types": ["route"], "route": {"stops": []}})["route"])

    def test_vtt_to_text(self):
        self.assertEqual(vtt_text("WEBVTT\n\n1\n00:00.0 --> 00:01.0\nHello\n\n00:01.0 --> 00:02.0\nHello\nworld"), "Hello world")


class EndpointTests(unittest.TestCase):
    def handler(self, path, body=None):
        handler = object.__new__(bridge.RequestHandler)
        handler.path = path; handler.replies = []
        raw = json.dumps(body).encode() if body is not None else b""
        handler.headers = {"Content-Length": str(len(raw))}; handler.rfile = io.BytesIO(raw)
        handler.send_json = lambda status, payload: handler.replies.append((status, payload))
        return handler

    def test_requires_token(self):
        handler = self.handler("/api/social/extract", {"source_id": str(uuid.uuid4())})
        with patch.object(bridge, "places_access_allowed", return_value=False):
            handler.do_POST()
        self.assertEqual(handler.replies[0][0], 401)

    def test_submit_and_poll(self):
        class Queue:
            def __init__(self): self.jobs = {}; self.keys = {}
            def cached(self, key): return {"places": [], "media": {"kind": "video"}} if key == "tiktok:999999999" else None
            def final(self, key): return self.cached(key)
            def submit(self, job_id, source, key="", reread=False):
                self.keys[job_id] = key
                if source is None: return {"job_id": job_id, "status": "ready", "cached": True}
                self.jobs[job_id] = source; return {"job_id": job_id, "status": "queued"}
            def get(self, job_id): return {"job_id": job_id, "status": "ready"} if job_id in self.jobs else None
        queue, source_id = Queue(), str(uuid.uuid4())
        body = {"source_id": source_id, "url": "https://www.tiktok.com/@a/video/1", "evidence": [{"origin": "post_caption", "text": "hi"}],
                "images": [{"mime": "image/jpeg", "data": base64.b64encode(b"img").decode()}]}
        with patch.object(bridge, "places_access_allowed", return_value=True), patch.object(bridge, "social_queue", return_value=queue):
            handler = self.handler("/api/social/extract", body); handler.do_POST()
            self.assertEqual(handler.replies[0], (202, {"job_id": source_id, "status": "queued"}))
            self.assertEqual(queue.jobs[source_id]["images"], [("image/jpeg", b"img")])
            # An already-indexed post: the probe gets the stored read back, nothing is queued.
            again = str(uuid.uuid4())
            handler = self.handler("/api/social/extract", {"source_id": again, "url": "https://www.tiktok.com/@a/video/999999999", "probe": True})
            handler.do_POST()
            self.assertEqual(handler.replies[0], (200, {"job_id": again, "status": "ready", "cached": True}))
            self.assertNotIn(again, queue.jobs)
            fresh = str(uuid.uuid4())
            handler = self.handler("/api/social/extract", {"source_id": fresh, "url": "https://www.tiktok.com/@a/video/123456789", "probe": True})
            handler.do_POST()
            self.assertEqual(handler.replies[0], (200, {"job_id": fresh, "status": "unindexed"}))
            handler = self.handler(f"/api/social/extract?job_id={source_id}"); handler.do_GET()
            self.assertEqual(handler.replies[0][1]["status"], "ready")
            handler = self.handler("/api/social/extract", {"source_id": "nope"}); handler.do_POST()
            self.assertEqual(handler.replies[0][0], 422)


class ThinReadTests(unittest.TestCase):
    """A walking-route video whose eight stops are drawn on the frames, read once from its caption alone."""
    CAPTION_ONLY = {"post_title": "Christmas in Rome", "relevant": True, "post_kind": "places", "tips": [],
                    "places": [{"name": "Piazza Navona", "evidence": ["caption"]}]}

    def test_a_caption_only_read_of_a_video_is_thin_and_a_richer_upload_replaces_it(self):
        legacy = json.loads(json.dumps(self.CAPTION_ONLY))                      # stored before media was recorded
        self.assertTrue(ex.is_thin(legacy))
        recorded = {**legacy, "media": {"kind": "none", "count": 0, "expects_video": True}}
        self.assertTrue(ex.is_thin(recorded))
        self.assertFalse(ex.is_thin({**legacy, "media": {"kind": "video", "count": 0, "expects_video": True}}))
        self.assertTrue(ex.richer({"video": ("video/mp4", b"x")}, recorded))
        self.assertTrue(ex.richer({"images": [b"a"] * 12, "frame_times": list(range(0, 24, 2))}, recorded))
        self.assertFalse(ex.richer({"evidence": [{"origin": "post_caption", "text": "x"}]}, recorded))
        # A full read that found fewer places than the post says it has is thin too.
        self.assertTrue(ex.is_thin({**legacy, "media": {"kind": "video", "expects_video": True}, "incomplete": True}))

    def test_stated_count_flags_an_incomplete_read(self):
        result = ex.clean({**json.loads(json.dumps(RESULT)), "relevant": True, "stated_count": 8})
        self.assertEqual(result["stated_count"], 8)
        self.assertTrue(result["incomplete"])
        self.assertFalse(ex.clean({**json.loads(json.dumps(RESULT)), "relevant": True, "stated_count": 0})["incomplete"])

    def test_frames_are_labelled_with_their_time(self):
        parts = ex.build_parts({"url": "u", "evidence": [{"origin": "post_caption", "text": "8 stops"}],
                                "images": [("image/jpeg", b"a"), ("image/jpeg", b"b")], "frame_times": [0, 3]})
        labels = [p["text"] for p in parts if "text" in p][1:]
        self.assertEqual(labels, ["video 0:00", "video 0:03"])
        self.assertIn("frames from the video", parts[0]["text"])

    def test_the_queue_hands_out_a_good_read_but_rereads_a_thin_one_when_frames_arrive(self):
        class Index:
            def __init__(self, stored): self.stored = stored; self.counted = 0
            def get(self, key): return self.stored
            def put(self, key, result): self.stored = result
            def count_reader(self, key): self.counted += 1
        class Pool:
            calls = 0
            def generate(self, parts, **kw):
                Pool.calls += 1
                return json.loads(json.dumps(RESULT)), "fake-model"
        index = Index({**json.loads(json.dumps(self.CAPTION_ONLY))})
        queue = ex.ExtractionQueue(lambda: Pool(), search=None, index=index)
        self.assertIsNone(queue.final("tiktok:1"))                             # thin: not final
        caption_only = {"evidence": [{"origin": "post_caption", "text": "📍 8 stops in Rome"}], "expects_video": True}
        self.assertEqual(queue.submit("a", caption_only, "tiktok:1")["status"], "ready")   # nothing new: the stored read stands
        self.assertEqual(Pool.calls, 0)
        frames = {**caption_only, "images": [b"jpeg"] * 10, "frame_times": list(range(0, 30, 3))}
        job = queue.submit(str(uuid.uuid4()), frames, "tiktok:1")
        for _ in range(100):
            if queue.get(job["job_id"])["status"] == "ready": break
            time.sleep(0.02)
        self.assertEqual(Pool.calls, 1)
        self.assertEqual(index.stored["media"]["kind"], "frames")


class ScopeCleanupTests(unittest.TestCase):
    def test_sentences_are_not_regions_and_countries_come_from_places(self):
        result = ex.clean({**json.loads(json.dumps(RESULT)), "relevant": True, "country_code": "",
                           "scope": {"level": "city", "name": "Rome", "region": "Lazio, Italy-level city scope covered in walking route forma", "countries": []}})
        self.assertEqual(result["scope"]["region"], "")
        self.assertEqual(result["scope"]["countries"], [p["country_code"] for p in result["places"] if p["country_code"]][:1])
        named = ex.clean({**json.loads(json.dumps(RESULT)), "relevant": True, "scope": {"level": "region", "name": "Dolomites", "region": "Alps"}})
        self.assertEqual(named["scope"]["region"], "Alps")


class SoundAndFrameTextTests(unittest.TestCase):
    def test_music_only_posts_tell_the_model_to_ignore_lyrics_and_frame_text_is_labelled(self):
        parts = ex.build_parts({"url": "u", "sound": "music", "evidence": [{"origin": "frame_text", "text": "[0:07] Piazza del Popolo"}],
                                "images": [("image/jpeg", b"a")], "frame_times": [7.2]})
        prompt = parts[0]["text"]
        self.assertIn("music only", prompt)
        self.assertIn("Text the phone read on the frames", prompt)
        self.assertIn("video 0:07", [p["text"] for p in parts if "text" in p])
        self.assertIn("speaks over music", ex.build_parts({"url": "u", "sound": "mixed", "evidence": [{"origin": "post_caption", "text": "x"}]})[0]["text"])
        self.assertEqual(ex.media_of({"images": [b"a"], "frame_times": [1.0], "sound": "music"})["sound"], "music")

    def test_the_server_drops_song_captions_when_the_phone_heard_only_music(self):
        captured = {}
        class Queue:
            def cached(self, key): return None
            def final(self, key): return None
            def submit(self, job_id, source, key="", reread=False):
                captured.update(source); return {"job_id": job_id, "status": "queued"}
        body = {"source_id": str(uuid.uuid4()), "url": "https://www.tiktok.com/@a/video/5", "sound": "music",
                "evidence": [{"origin": "post_caption", "text": "8 stops"}, {"origin": "auto_caption", "text": "It's beginning to look a lot like Christmas"}],
                "images": [{"mime": "image/jpeg", "data": base64.b64encode(b"img").decode()}], "frame_times": [7.2]}
        handler = EndpointTests.handler(self, "/api/social/extract", body)
        with patch.object(bridge, "places_access_allowed", return_value=True), patch.object(bridge, "social_queue", return_value=Queue()):
            handler.do_POST()
        self.assertEqual([b["origin"] for b in captured["evidence"]], ["post_caption"])
        self.assertEqual((captured["sound"], captured["frame_times"]), ("music", [7.2]))
