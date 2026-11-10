import json

from trippy.planner.place_graph import library_graph
from trippy.social.community import CommunityVideos, clock, place_verdict, plan_nodes, tiktok_videos, wanted_by_brief, youtube_videos
from trippy.social.index import PlaceTakes, VideoIndex


def _youtube_root(tmp_path):
    drafts = [
        {"id": "a" * 64, "name": "Bar Lobo", "kind": "venue", "categories": ["food"], "stance": "recommended",
         "experience": "first_hand_visit", "source": {"provider": "youtube", "external_id": "vid1"},
         "claims": [{"value": "Great tapas at the bar.", "basis": "creator_opinion",
                     "citations": [{"start_seconds": 75.2, "quote": "VERBATIM QUOTE"}]}]},
        {"id": "b" * 64, "name": "Tourist trap", "kind": "venue", "categories": ["food"], "stance": "negative",
         "source": {"provider": "youtube", "external_id": "vid1"},
         "claims": [{"value": "Overpriced paella.", "basis": "creator_opinion", "citations": [{"start_seconds": 10}]}]},
        {"id": "c" * 64, "name": "T10 ticket", "kind": "ticket", "categories": ["transport"], "stance": "recommended",
         "source": {"provider": "youtube", "external_id": "vid1"},
         "claims": [{"value": "Cheaper than singles.", "basis": "creator_opinion", "citations": [{"start_seconds": 3700}]}]},
    ]
    stage = tmp_path / ".local/stage3/planner-release-v1"
    stage.mkdir(parents=True)
    (stage / "normalized.json").write_text(json.dumps({"drafts": drafts}))
    (stage / "active-dataset.json").write_text(json.dumps({"normalized": ".local/stage3/planner-release-v1/normalized.json"}))
    sources = tmp_path / ".local/stage3/sources"
    sources.mkdir(parents=True)
    (sources / "meta.json").write_text(json.dumps({"items": [{"provider": "youtube", "external_id": "vid1", "title": "Barcelona food",
                                                               "channel_title": "Creator"}]}))
    return tmp_path


def test_youtube_video_is_organised_without_quotes(tmp_path):
    [video] = youtube_videos(_youtube_root(tmp_path))
    assert video["key"] == "youtube:vid1" and video["title"] == "Barcelona food" and video["author"] == "Creator"
    assert [p["name"] for p in video["places"]] == ["Tourist trap", "Bar Lobo"]  # in timeline order
    assert video["places"][0]["stance"] == "avoid" and video["places"][1]["at"] == "1:15"
    assert video["tips"][0] == {"title": "T10 ticket", "detail": "Cheaper than singles.", "at": "1:01:40", "seconds": 3700, "category": "transport"}
    assert "VERBATIM" not in json.dumps(video)
    assert video["counts"] == {"places": 2, "recommended": 1, "tips": 1, "avoid": 1}
    assert clock(59) == "0:59"


def test_tiktok_videos_and_browse(tmp_path):
    index = VideoIndex(tmp_path / "videos.sqlite")
    index.put("tiktok:42", {"post_title": "Athens cafés", "city": "Athens", "source": {"url": "https://www.tiktok.com/@a/video/42", "author": "a"},
                            "places": [{"name": "Minu", "category": "Coffee", "tldr": "Plants", "moments": [{"at": "0:12", "text": "Go early"}],
                                        "google": {"placeID": "ChIJm", "latitude": 37.9, "longitude": 23.7}}],
                            "tips": [{"title": "Cash", "detail": "Bring some", "at": "0:30"}]})
    takes = PlaceTakes(tmp_path / "takes.sqlite")
    takes.vote("ChIJm", "u1", been=True, tags=["value_for_money"])
    [video] = tiktok_videos(tmp_path / "videos.sqlite", takes)
    assert video["places"][0]["category"] == "coffee" and video["places"][0]["seconds"] == 12
    assert video["places"][0]["takes"]["tags"] == {"value_for_money": 1}
    assert video["kind"] == "mixed"
    library = CommunityVideos(_youtube_root(tmp_path), tmp_path / "videos.sqlite", takes)
    assert {v["platform"] for v in library.browse()["videos"]} == {"youtube", "tiktok"}
    assert [v["key"] for v in library.browse(city="athens")["videos"]] == ["tiktok:42"]
    assert [v["key"] for v in library.browse(category="transport")["videos"]] == ["youtube:vid1"]
    assert library.browse(query="minu")["videos"][0]["top_places"] == ["Minu"]
    assert [v["key"] for v in library.for_place(google_id="ChIJm")["videos"]] == ["tiktok:42"]
    assert [v["key"] for v in library.for_place(name="BAR LOBO", city="Barcelona")["videos"]] == ["youtube:vid1"]
    assert library.for_place(name="Bar Lobo", city="Athens")["videos"] == []


def test_community_verdicts_and_user_input():
    assert place_verdict({"voters": 2, "tags": {"overhyped": 2}}) is None  # too few to judge
    assert place_verdict({"voters": 4, "tags": {"overhyped": 2, "mid": 1}, "got_in": {}}) == "skip"
    assert place_verdict({"voters": 4, "tags": {}, "got_in": {"turned_away": 3, "walked_in": 1}}) == "skip"
    assert place_verdict({"voters": 5, "tags": {"value_for_money": 2}, "got_in": {}}) == "boost"
    assert not wanted_by_brief({}, {"voters": 3, "tags": {"expensive": 2}}, ["budget"])
    assert wanted_by_brief({}, {"voters": 3, "tags": {"expensive": 2}}, ["nightlife"])


def test_plan_nodes_respect_categories_and_community(tmp_path):
    takes = PlaceTakes(":memory:")
    for voter in ("1", "2", "3"):
        takes.vote("ChIJbad", voter, been=True, tags=["overhyped"])
    place = lambda pid, cat: {"id": pid, "name": pid, "category": cat, "stance": "recommended", "latitude": 41.38, "longitude": 2.17,
                              "google_place_id": pid, "summary": "", "address": None}
    video = {"key": "tiktok:1", "url": "https://www.tiktok.com/@a/video/1", "title": "T", "summary": "S", "city": "Barcelona",
             "places": [place("ChIJgood", "food"), place("ChIJbad", "food"), place("ChIJbar", "bars"),
                        {**place("ChIJfar", "food"), "latitude": None}]}
    brief = {"destination": "Barcelona", "preference_tags": [], "excluded_place_ids": []}
    [node] = plan_nodes(brief, videos=[video], takes=takes, plan_categories=["attraction", "food"])
    assert [p["name"] for p in node["places"]] == ["ChIJgood"]  # bad = rejected by community, bar = not asked, far = no coordinates
    graph = library_graph({"destination": "Barcelona", "library_nodes": []}, [node])
    assert graph["places"][0]["priority"] == 10 and graph["nodes"][0]["kind"] == "community"
