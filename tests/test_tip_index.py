"""Community tips carry a scope and topics, and reach the plan stops they are about — with no model call."""
import json

from trippy.social import extract as ex
from trippy.social import guides
from trippy.social.community import CommunityVideos, tiktok_videos
from trippy.social.index import VideoIndex
from trippy.social.tip_index import annotate, plan_tips, scope_label, stance_of, tip_scope, tip_topics, topics_of


def _tiktok(key, *, city="Barcelona", country="ES", level="city", tips=(), author="creator"):
    return {"post_title": f"{city} tips", "city": city, "country_code": country, "relevant": True, "guide_types": ["tips"],
            "scope": {"level": level, "name": city if level == "city" else "Spain", "region": "", "countries": [country]},
            "source": {"url": f"https://www.tiktok.com/@{author}/video/{key}", "author": author},
            "places": [], "tips": list(tips)}


def _library(tmp_path, reads):
    index = VideoIndex(tmp_path / "videos.sqlite")
    for key, read in reads.items():
        index.put(f"tiktok:{key}", read)
    return CommunityVideos(tmp_path, index).all()


BEACHES = {"title": "Skip the city beaches", "detail": "Barceloneta is crowded and dirty; take the train to Sitges instead.", "at": "0:14"}
METRO = {"title": "Get a T-casual", "detail": "Ten metro and bus rides for one price.", "at": "0:40"}
MUSEUM = {"title": "Picasso Museum is free on Thursday evenings", "detail": "Book the free slot online.", "at": "1:02"}
SPAIN = {"title": "Dinner is late", "detail": "Restaurants open for dinner around 20:30.", "at": "0:05"}


def _plan(*stops, areas=(), month=6):
    """stops: (day, place_id, name, category)."""
    days = {}
    for day, place_id, _, _ in stops:
        days.setdefault(day, []).append({"place_id": place_id})
    return {"places": [{"id": p, "name": n, "category": c} for _, p, n, c in stops],
            "itinerary": {"days": [{"date": f"2026-{month:02d}-2{d}", "stops": days[d]} for d in sorted(days)]}, "areas": list(areas)}


def test_topics_fall_back_to_keywords_and_never_match_inside_words():
    assert topics_of("Avoid the city beaches, take the train to Sitges") == ["beach", "transport"]
    assert "nightlife" not in topics_of("Barcelona in a day")              # "bar" is a word, not a prefix
    assert "nightlife" in topics_of("Cocktail bars in El Born")
    assert topics_of("Μπαρτσελονέτα: κλέφτες παντού") == ["safety"]          # Greek, accents folded
    assert stance_of(BEACHES["detail"]) == "warning" and stance_of(METRO["detail"]) == "tip"
    assert stance_of("Take the funicular to avoid walking up") == "tip"      # a purpose, not a warning


def test_a_tip_inherits_the_video_scope_unless_it_narrows_it():
    video = {"city": "Barcelona", "country_code": "ES", "scope": {"level": "city", "name": "Barcelona", "countries": ["ES"]}}
    assert tip_scope({"title": "x"}, video) == {"level": "city", "name": "Barcelona", "region": "", "countries": ["ES"], "city": "Barcelona"}
    narrowed = tip_scope({"title": "x", "where": "Barceloneta"}, video)
    assert narrowed["level"] == "neighbourhood" and scope_label(narrowed) == "Barceloneta, Barcelona"
    # YouTube "<place>: <dimension>" notes: the place is the scope, the dimension the topic.
    youtube = {"city": "Barcelona", "country_code": "ES"}
    assert tip_scope({"title": "Gothic Quarter: tickets"}, youtube)["name"] == "Gothic Quarter"
    assert tip_scope({"title": "Costa Brava: transport"}, youtube)["level"] == "region"
    assert tip_scope({"title": "Barcelona: season"}, youtube)["level"] == "city"
    assert tip_scope({"title": "visitor advice: carry water"}, youtube)["level"] == "city"
    assert tip_topics({"title": "Gothic Quarter: tickets", "detail": "", "category": "sights"}) == ["tickets"]
    assert tip_topics({"title": "x", "detail": "y", "topics": ["beach", "bogus"]}) == ["beach"]


def test_new_reads_name_topics_and_where_and_old_reads_still_work():
    assert "topics" in json.dumps(ex.SCHEMA["properties"]["tips"]) and "{tip_topics}" in ex.PROMPT
    cleaned = ex.clean({"places": [], "tips": [{"title": "Skip it", "detail": "d", "topics": ["beach", "nope"], "where": "Barceloneta"},
                                                {"title": "Old shape", "detail": "d"}], "city": "Barcelona", "relevant": True})
    assert cleaned["tips"][0]["topics"] == ["beach"] and cleaned["tips"][0]["where"] == "Barceloneta"
    assert cleaned["tips"][1]["topics"] == [] and cleaned["tips"][1]["where"] == ""
    video = annotate({"city": "Barcelona", "country_code": "ES", "url": "u", "platform": "tiktok",
                      "tips": [{"title": "Old shape", "detail": "Pickpockets on the metro"}]})
    assert set(video["tips"][0]["topics"]) == {"safety", "transport"} and video["tips"][0]["stance"] == "warning"
    assert video["tips"][0]["scope"]["label"] == "Barcelona"


def test_community_records_and_tips_api_carry_scope(tmp_path):
    reads = {"1": _tiktok("1", tips=[{**BEACHES, "topics": ["beach", "day_trips"], "where": ""}, METRO]),
             "2": _tiktok("2", city="", level="country", tips=[SPAIN])}
    videos = tiktok_videos(_library_index(tmp_path, reads))
    tip = next(v for v in videos if v["key"] == "tiktok:1")["tips"][0]
    assert tip["topics"][:2] == ["beach", "day_trips"] and {"transport", "queues"} <= set(tip["topics"]) and tip["scope"]["name"] == "Barcelona" and tip["stance"] == "warning"
    found = guides.tips_for(videos, city="Barcelona", country="ES")
    city, country = found["groups"]
    assert city["tips"][0]["scope"]["label"] == "Barcelona" and city["tips"][0]["from"]["link"].startswith("https://www.tiktok.com/")
    assert country["tips"][0]["scope"]["level"] == "country"
    assert [t["title"] for g in guides.tips_for(videos, city="Barcelona", country="ES", topic="beach")["groups"] for t in g["tips"]] \
        == ["Skip the city beaches"]


def _library_index(tmp_path, reads):
    index = VideoIndex(tmp_path / "videos.sqlite")
    for key, read in reads.items():
        index.put(f"tiktok:{key}", read)
    return index


def test_a_beach_warning_sits_next_to_the_beach_stop(tmp_path):
    videos = _library(tmp_path, {"1": _tiktok("1", tips=[BEACHES, METRO, MUSEUM]), "2": _tiktok("2", level="country", city="", tips=[SPAIN])})
    plan = _plan((1, "sagrada", "Sagrada Família", "attraction"), (2, "beach", "Platja de la Barceloneta", "nature"),
                 (2, "bar", "El Xampanyet", "bar"))
    out = plan_tips(plan, {"destination": "Barcelona, Spain", "interests": ["beaches"]}, videos)
    by_title = {t["title"]: t for t in out["tips"]}
    beach = by_title["Skip the city beaches"]
    assert beach["place_ids"] == ["beach"] and beach["days"] == [2] and beach["dates"] == ["2026-06-22"]
    assert beach["stance"] == "warning" and beach["scope"]["label"] == "Barcelona" and beach["why"] == "Day 2 has Platja de la Barceloneta"
    assert beach["source"] == {"key": "tiktok:1", "platform": "tiktok", "title": "Barcelona tips", "author": "creator",
                               "url": "https://www.tiktok.com/@creator/video/1", "link": "https://www.tiktok.com/@creator/video/1"}
    assert out["tips"][0] is beach                                           # matched a stop, so it leads
    assert by_title["Get a T-casual"]["place_ids"] == [] and by_title["Get a T-casual"]["why"].startswith("Good to know")
    assert by_title["Dinner is late"]["scope"]["level"] == "country"         # Spain's tips reach a Barcelona plan
    assert "Picasso Museum is free on Thursday evenings" not in by_title     # no museum in the plan, none asked for


def test_a_picked_interest_without_a_stop_still_gets_its_tip(tmp_path):
    videos = _library(tmp_path, {"1": _tiktok("1", tips=[BEACHES])})
    plan = _plan((1, "sagrada", "Sagrada Família", "attraction"))
    [tip] = plan_tips(plan, {"destination": "Barcelona", "interests": ["beaches"]}, videos)["tips"]
    assert tip["place_ids"] == [] and tip["why"] == "You picked beaches"
    assert plan_tips(plan, {"destination": "Barcelona", "interests": ["museums"]}, videos)["tips"] == []


def test_neighbourhood_tips_follow_the_plan_there_and_other_cities_stay_out(tmp_path):
    raval = {"title": "Watch your bag", "detail": "Pickpockets work the side streets at night.", "where": "El Raval"}
    videos = _library(tmp_path, {"1": _tiktok("1", tips=[raval]), "9": _tiktok("9", city="Lisbon", country="PT", tips=[BEACHES])})
    near = _plan((1, "macba", "MACBA", "museum"), areas=[{"name": "El Raval", "place_ids": ["macba"]}])
    [tip] = plan_tips(near, {"destination": "Barcelona"}, videos)["tips"]
    assert tip["place_ids"] == ["macba"] and tip["scope"]["label"] == "El Raval, Barcelona" and tip["why"].startswith("About El Raval")
    far = _plan((1, "park", "Park Güell", "attraction"))
    assert plan_tips(far, {"destination": "Barcelona"}, videos)["tips"] == []


def test_the_travellers_community_choice_is_respected_and_stops_are_capped(tmp_path):
    many = [{"title": f"Beach tip {i}", "detail": f"Beach advice number {i}."} for i in range(5)]
    videos = _library(tmp_path, {"1": _tiktok("1", tips=many)})
    plan = _plan((1, "beach", "Bogatell Beach", "nature"))
    assert len(plan_tips(plan, {"destination": "Barcelona"}, videos)["tips"]) == 2      # two per stop
    assert plan_tips(plan, {"destination": "Barcelona", "community": {"use": "off"}}, videos)["tips"] == []
    assert plan_tips(plan, {"destination": "Barcelona", "community": {"use": "picked", "videos": ["tiktok:2"]}}, videos)["tips"] == []


def test_youtube_links_open_at_the_tip():
    video = annotate({"key": "youtube:abc", "platform": "youtube", "url": "https://www.youtube.com/watch?v=abc", "title": "Barcelona",
                      "author": "Creator", "city": "Barcelona", "country_code": "ES",
                      "tips": [{"title": "beach", "detail": "Not worth a beach day in winter.", "at": "1:37", "seconds": 97}]})
    june = _plan((1, "beach", "Barceloneta Beach", "nature"))
    assert plan_tips(june, {"destination": "Barcelona"}, [video])["tips"] == []      # a winter tip, a June trip
    december = _plan((1, "beach", "Barceloneta Beach", "nature"), month=12)
    [tip] = plan_tips(december, {"destination": "Barcelona"}, [video])["tips"]
    assert tip["source"]["link"] == "https://www.youtube.com/watch?v=abc&t=97s" and tip["stance"] == "warning"
    assert tip["when_label"] == "Winter" and tip["in_season"] and tip["why"].startswith("Winter, your dates")


# ------------------------------------------------- The time half of a scope ---

from trippy.social.tags import clean_when, easter, facets, when_matches, when_of  # noqa: E402


def test_time_windows_from_text_and_from_the_read():
    assert when_of("Christmas in Rome Festive Walking Route")["start"] == "12-01"
    assert when_of("Barceloneta in summer is packed")["months"] == [6, 7, 8]
    assert when_of("Summer in Sydney", "AU")["months"] == [12, 1, 2]              # southern hemisphere
    assert when_of("Πάσχα στην Κέρκυρα")["movable"] == "easter"
    assert when_of("Free entry on Sundays")["weekdays"] == [6]
    assert when_of("Visit in May") ["months"] == [5] and when_of("You may want cash") is None
    assert when_of("Don't fall for the scams") is None
    assert clean_when({"label": "Christmas"})["end"] == "01-06"                   # a label alone is still a time
    assert clean_when({"months": [6, 13], "start": "6-1", "weekdays": ["sunday", 9]}) == {
        "label": "June", "months": [6], "start": "", "end": "", "movable": "", "weekdays": [6], "times": []}
    assert clean_when({}) is None and clean_when("summer") is None


def test_trip_dates_against_time_windows():
    christmas = when_of("christmas markets")
    assert when_matches(christmas, ["2026-12-27", "2026-12-28"]) is True
    assert when_matches(christmas, ["2027-01-05"]) is True                        # the window wraps the new year
    assert when_matches(christmas, ["2026-07-10"]) is False
    assert when_matches(christmas, []) is None and when_matches(None, ["2026-07-10"]) is None
    assert easter(2027).isoformat() == "2027-03-28" and when_matches(when_of("Easter"), ["2027-03-26"]) is True
    assert when_matches(when_of("Easter"), ["2027-04-20"]) is False
    assert when_matches(when_of("go at sunset"), ["2026-07-10"]) is None          # a time of day never rules a trip out


def test_a_time_of_day_narrows_the_videos_period_and_other_facets_are_tagged():
    christmas = when_of("Christmas")
    tagged = facets({"title": "x"}, "Go at night when the lights are on, great for kids, free entry", inherit={"when": christmas})
    assert tagged["when"]["label"] == "Christmas" and tagged["when"]["times"] == ["night"]
    assert tagged["audience"] == ["families"] and tagged["cost"] == ["free"]
    said = facets({"when": {"label": "Summer", "months": [6, 7, 8]}, "audience": ["couples", "aliens"]}, "", inherit={"when": christmas})
    assert said["when"]["label"] == "Summer" and said["audience"] == ["couples"]


def test_reads_carry_when_on_the_post_tips_and_places():
    assert "_WHEN" not in ex.PROMPT and "when" in ex.SCHEMA["properties"]["scope"]["properties"]
    assert {"when", "audience", "cost"} <= set(ex.SCHEMA["properties"]["tips"]["items"]["properties"])
    cleaned = ex.clean({"city": "Rome", "relevant": True, "scope": {"level": "city", "name": "Rome", "when": {"label": "Christmas"}},
                        "places": [{"name": "Piazza Navona market", "category": "Sights", "confidence": 0.9, "when": {"months": [12]}}],
                        "tips": [{"title": "Go at dusk", "detail": "Lights", "when": {"times": ["evening"]}, "cost": ["free", "x"]}]})
    assert cleaned["scope"]["when"]["start"] == "12-01" and cleaned["places"][0]["when"]["months"] == [12]
    assert cleaned["tips"][0]["when"]["times"] == ["evening"] and cleaned["tips"][0]["cost"] == ["free"]


ROME_CHRISTMAS = {"post_title": "Christmas in Rome Festive Walking Route", "post_summary": "A festive walk past the lights and markets.",
                  "city": "Rome", "country_code": "IT", "relevant": True, "guide_types": ["route", "tips"],
                  "scope": {"level": "city", "name": "Rome", "countries": ["IT"]},
                  "source": {"url": "https://www.tiktok.com/@romewalks/video/7705794775592586548", "author": "romewalks"},
                  "places": [{"name": "Piazza Navona", "category": "Sights", "tldr": "The Christmas market",
                              "google": {"placeID": "ChIJnavona", "latitude": 41.899, "longitude": 12.473}}],
                  "tips": [{"title": "Go after dark", "detail": "The lights on Via del Corso switch on at dusk.", "at": "0:21"}]}
ROME_ALL_YEAR = {**ROME_CHRISTMAS, "post_title": "Rome tips", "post_summary": "", "places": [],
                 "tips": [{"title": "Validate your bus ticket", "detail": "Fines are steep.", "at": "0:05"}]}


def _rome_plan(month, day):
    return {"places": [{"id": "pantheon", "name": "Pantheon", "category": "attraction"}],
            "itinerary": {"days": [{"date": f"2026-{month:02d}-{day:02d}", "stops": [{"place_id": "pantheon"}]}]}}


def test_a_christmas_video_reaches_rome_trips_around_christmas_only(tmp_path):
    videos = _library(tmp_path, {"7705794775592586548": ROME_CHRISTMAS, "2": ROME_ALL_YEAR})
    video = next(v for v in videos if v["key"] == "tiktok:7705794775592586548")
    assert video["when"]["label"] == "Christmas" and video["places"][0]["when"]["label"] == "Christmas"
    assert video["tips"][0]["when"]["times"] == ["evening"] and video["tips"][0]["scope"]["when"]["label"] == "Christmas"
    december = plan_tips(_rome_plan(12, 22), {"destination": "Rome"}, videos)["tips"]
    lights = next(t for t in december if t["title"] == "Go after dark")
    assert lights["in_season"] and lights["when_label"] == "Christmas" and lights["why"].startswith("Christmas, your dates")
    assert december[0] is lights                                                    # in season ranks first
    july = [t["title"] for t in plan_tips(_rome_plan(7, 10), {"destination": "Rome"}, videos)["tips"]]
    assert july == ["Validate your bus ticket"]


def test_a_christmas_market_is_not_a_stop_on_a_summer_trip(tmp_path):
    from trippy.social.community import plan_nodes
    videos = _library(tmp_path, {"1": ROME_CHRISTMAS})
    brief = lambda arrival, departure: {"destination": "Rome", "date_range": {"arrival": arrival, "departure": departure}}
    assert plan_nodes(brief("2026-12-20", "2026-12-23"), videos=videos, plan_categories=["attraction"])[0]["places"][0]["name"] == "Piazza Navona"
    assert plan_nodes(brief("2026-07-01", "2026-07-04"), videos=videos, plan_categories=["attraction"]) == []
    assert plan_nodes({"destination": "Rome"}, videos=videos, plan_categories=["attraction"])   # no dates: nothing ruled out


def test_summer_beach_warning_reaches_summer_barcelona_trips_only(tmp_path):
    crowded = {"title": "Avoid the city beaches", "detail": "In summer Barceloneta is packed; go to Sitges.", "topics": ["beach"]}
    videos = _library(tmp_path, {"1": _tiktok("1", tips=[crowded])})
    summer = plan_tips(_plan((1, "beach", "Platja de la Barceloneta", "nature"), month=7), {"destination": "Barcelona"}, videos)["tips"]
    assert [t["title"] for t in summer] == ["Avoid the city beaches"] and summer[0]["place_ids"] == ["beach"]
    assert summer[0]["why"] == "Summer, your dates · Day 1 has Platja de la Barceloneta"
    winter = plan_tips(_plan((1, "beach", "Platja de la Barceloneta", "nature"), month=1), {"destination": "Barcelona"}, videos)["tips"]
    assert winter == []
