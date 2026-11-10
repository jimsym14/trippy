import threading
import time

from trippy.social import extract
from trippy.social.extract import ExtractionQueue, clean
from trippy.social.index import PlaceTakes, VideoIndex, video_key


def test_video_key_prefers_tiktok_id():
    assert video_key("https://www.tiktok.com/@a/video/7312345678901234567?is_from_webapp=1") == "tiktok:7312345678901234567"
    assert video_key("https://www.tiktok.com/@a/photo/7312345678901234567") == "tiktok:7312345678901234567"
    assert video_key("", "7312345678901234567") == "tiktok:7312345678901234567"
    short = video_key("https://vm.tiktok.com/ZMabc/?x=1")
    assert short.startswith("url:") and short == video_key("https://VM.tiktok.com/ZMabc")
    assert video_key("") == ""


def test_clean_classifies_tips_and_keeps_moments():
    result = clean({"places": [], "tips": [{"title": "Carry cash", "detail": "Many kiosks are cash only.", "at": "0:12"}],
                    "post_kind": "places"})
    assert result["post_kind"] == "places"  # model said places; kept (tips list just rides along)
    result = clean({"places": [], "tips": [{"title": "Carry cash", "detail": "x"}]})
    assert result["post_kind"] == "tips"
    place = {"name": "Kiki", "category": "Food", "confidence": 0.9,
             "moments": [{"at": "0:03", "text": "best pasta"}, {"at": "0:09", "text": ""}, "bad"]}
    result = clean({"places": [place], "tips": [{"title": "Book", "detail": "y"}], "post_kind": "tips"})
    assert result["post_kind"] == "mixed"
    assert result["places"][0]["moments"] == [{"at": "0:03", "text": "best pasta"}]


def test_takes_count_once_per_voter_and_never_expose_voters():
    takes = PlaceTakes(":memory:")
    takes.vote("ChIJabc", "user:1", been=True, got_in="waited", tags=["overhyped", "expensive", "bogus"])
    takes.vote("ChIJabc", "user:1", been=True, got_in="walked_in", tags=["value_for_money"])  # replaces
    takes.vote("ChIJabc", "install:x", been=False, tags=["overhyped"])
    summary = takes.summary(["ChIJabc"], voter="user:1")["ChIJabc"]
    assert summary["voters"] == 2 and summary["been"] == 1
    assert summary["got_in"] == {"walked_in": 1}
    assert summary["tags"] == {"value_for_money": 1, "overhyped": 1}
    assert summary["mine"] == {"been": True, "got_in": "walked_in", "tags": ["value_for_money"]}
    assert "user:1" not in str(takes.summary(["ChIJabc"]))
    takes.vote("ChIJabc", "install:x")  # empty answer withdraws
    assert takes.summary(["ChIJabc"])["ChIJabc"]["voters"] == 1


def test_takes_collect_video_tips_across_posts():
    takes = PlaceTakes(":memory:")
    place = {"google": {"placeID": "ChIJabc"}, "pro_tips": ["Book ahead"], "good_to_know": ["Cash only"]}
    takes.add_video("tiktok:1", [place])
    takes.add_video("tiktok:2", [{"google": {"placeID": "ChIJabc"}, "pro_tips": ["book ahead"], "good_to_know": []}])
    takes.add_video("tiktok:2", [{"google": {"placeID": "ChIJabc"}, "pro_tips": ["book ahead"], "good_to_know": []}])  # idempotent
    summary = takes.summary(["ChIJabc"])["ChIJabc"]
    assert summary["videos"] == 2 and summary["tips"][0] == "Book ahead"


def test_queue_reads_each_post_once(monkeypatch, tmp_path):
    calls = []

    def fake_extract(pool, source):
        calls.append(source["url"])
        time.sleep(0.05)
        return {"post_title": "t", "places": [{"name": "Kiki", "google": {"placeID": "ChIJk"}, "pro_tips": ["Go early"]}]}

    monkeypatch.setattr(extract, "extract", fake_extract)
    index, takes = VideoIndex(tmp_path / "v.sqlite"), PlaceTakes(tmp_path / "t.sqlite")
    queue = ExtractionQueue(lambda: object(), index=index, takes=takes)
    key = "tiktok:42"
    first = queue.submit("00000000-0000-0000-0000-000000000001", {"url": "u"}, key)
    second = queue.submit("00000000-0000-0000-0000-000000000002", {"url": "u"}, key)  # same post while reading
    assert first["status"] in ("queued", "running") and second["job_id"].endswith("2")
    deadline = time.time() + 3
    while queue.get(first["job_id"])["status"] != "ready" and time.time() < deadline:
        time.sleep(0.02)
    assert queue.get(second["job_id"])["status"] == "ready"
    third = queue.submit("00000000-0000-0000-0000-000000000003", None, key)  # later saver
    assert third["status"] == "ready" and third["cached"] and third["result"]["places"][0]["name"] == "Kiki"
    assert calls == ["u"]
    assert takes.summary(["ChIJk"])["ChIJk"]["videos"] == 1
    assert index.stats()["reads_saved"] == 1
