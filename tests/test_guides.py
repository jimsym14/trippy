from trippy.social import guides


def _video(key, *, city="", country="", level="city", region="", countries=None, types=(), tips=(), foods=(), title=None, savers=0):
    return {"key": key, "platform": "tiktok", "url": "https://www.tiktok.com/@a/video/" + key, "title": title or key, "author": "a",
            "city": city, "country_code": country, "summary": "", "places": [], "savers": savers,
            "tips": [{"title": t, "detail": t + " detail"} for t in tips], "foods": [{"name": f, "where": city} for f in foods],
            "guide_types": list(types), "scope": {"level": level, "name": city or region or country, "region": region,
                                                  "countries": countries or ([country] if country else [])}}


VIDEOS = [
    _video("rome-food", city="Rome", country="IT", types=["themed_list", "foods"], foods=["Supplì", "Maritozzo"], savers=4, title="8 spots under 10€"),
    _video("rome-coperto", city="Rome", country="IT", types=["tips"], tips=["Coperto is illegal in Rome"]),
    _video("italy-tips", country="IT", level="country", types=["tips"], tips=["Validate train tickets", "Coperto is illegal in Rome"]),
    _video("interrail", level="multi_country", region="Europe", countries=["CZ", "AT", "HU"], types=["route", "tips"], tips=["Book seat reservations early"]),
    _video("alps-hike", level="region", region="Alps", countries=["AT", "CH", "IT"], types=["route", "hidden_spots"]),
    _video("athens-date", city="Athens", country="GR", level="neighbourhood", types=["area_guide", "themed_list"]),
    {**_video("dance", city="Rome", country="IT", types=[]), "relevant": False},
]


def test_a_guide_is_listed_at_its_level_and_every_level_above_it():
    keys = lambda **kw: [g["key"] for g in guides.browse(VIDEOS, **kw)["guides"]]
    assert set(keys(country="IT")) == {"rome-food", "rome-coperto", "italy-tips", "alps-hike"}
    assert "alps-hike" in keys(country="AT") and "interrail" in keys(country="AT")
    assert set(keys(city="Rome", country="IT")) == {"rome-food", "rome-coperto", "italy-tips", "alps-hike"}
    assert keys(region="Alps") == ["alps-hike"]
    assert "dance" not in keys()                                  # off-topic posts never show
    europe = guides.browse(VIDEOS, continent="Europe")
    assert {b["name"] for b in europe["below"]} >= {"IT", "AT", "CZ", "GR"} and {"name": "Alps", "count": 1} in europe["regions"]


def test_closest_guides_come_first_and_types_filter():
    rome = guides.browse(VIDEOS, city="Rome", country="IT")
    assert rome["guides"][0]["key"] == "rome-food" and rome["guides"][-1]["level"] in ("country", "region")
    assert [g["key"] for g in guides.browse(VIDEOS, country="IT", kind="foods")["guides"]] == ["rome-food"]
    assert {t["id"] for t in rome["types"]} >= {"tips", "foods", "route"}


def test_tips_pool_from_city_to_country_to_continent_said_once():
    found = guides.tips_for(VIDEOS, city="Rome", country="IT")
    levels = {g["level"]: [t["title"] for t in g["tips"]] for g in found["groups"]}
    assert levels["city"] == ["Coperto is illegal in Rome"]
    assert levels["country"] == ["Validate train tickets"]          # the repeat is not said twice
    assert levels["continent"] == ["Book seat reservations early"]
    assert guides.foods_for(VIDEOS, city="Rome")[0]["name"] == "Supplì"
