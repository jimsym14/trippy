import unittest

from trippy.social.community import CommunityVideos, _finish
from trippy.social.index import VideoIndex


def video(key, platform, title, city, places, tips=(), published=None, savers=0):
    return _finish({"key": key, "platform": platform, "url": "https://example.com/" + key, "title": title, "author": "creator",
                    "published_at": published, "language": None, "city": city, "country_code": None, "summary": None,
                    "places": [dict({"id": n, "name": n, "kind": "venue", "category": c, "categories": [c], "stance": s,
                                     "summary": n + " is great", "moments": [], "at": "1:02", "seconds": 62}, **extra)
                               for n, c, s, extra in places],
                    "tips": [{"title": t, "detail": t, "at": "", "seconds": None, "category": "budget_practical"} for t in tips],
                    "savers": savers})


class Library(CommunityVideos):
    def __init__(self, videos):
        self.videos = videos

    def all(self):
        return self.videos


VIDEOS = [
    video("tiktok:1", "tiktok", "Best bakeries in Gràcia", "Barcelona",
          [("Forn Baluard", "food", "recommended", {"neighborhood": "Gràcia", "latitude": 41.40, "longitude": 2.16})], savers=5),
    video("youtube:a", "youtube", "Barcelona in 3 days", "Barcelona",
          [("Sagrada Família", "sights", "recommended", {"latitude": 41.4036, "longitude": 2.1744}),
           ("Las Ramblas cafés", "food", "avoid", {})], tips=["Buy the T-casual card"], published="2026-05-01"),
    video("tiktok:2", "tiktok", "Rome trattorias", "Rome", [("Da Enzo", "food", "recommended", {"latitude": 41.888, "longitude": 12.4778})]),
]


class CommunitySearchTests(unittest.TestCase):
    def setUp(self):
        self.lib = Library(VIDEOS)

    def keys(self, **kw):
        return [v["key"] for v in self.lib.browse(**kw)["videos"]]

    def test_filters_combine(self):
        self.assertEqual(self.keys(city="Barcelona", platform="youtube"), ["youtube:a"])
        self.assertEqual(self.keys(place="baluard"), ["tiktok:1"])
        self.assertEqual(self.keys(area="gracia"), ["tiktok:1"])            # accents don't matter
        self.assertEqual(self.keys(only="tips"), ["youtube:a"])
        self.assertEqual(self.keys(query="t-casual"), ["youtube:a"])        # tips are searchable
        self.assertEqual(self.keys(bbox=(41.8, 12.4, 41.95, 12.6)), ["tiktok:2"])
        self.assertEqual(self.keys(sort="newest")[0], "youtube:a")
        self.assertEqual(self.keys()[0], "tiktok:1")                        # most saved first by default
        result = self.lib.browse(place="enzo")
        self.assertEqual(result["videos"][0]["matched_places"], ["Da Enzo"])
        self.assertIn("Gràcia", self.lib.browse(city="Barcelona")["areas"])

    def test_map_pins_only_placed_places_and_group_videos(self):
        pins = self.lib.map_places(city="Barcelona")["places"]
        self.assertEqual(sorted(p["name"] for p in pins), ["Forn Baluard", "Sagrada Família"])   # no position, no pin
        sagrada = next(p for p in pins if p["name"] == "Sagrada Família")
        self.assertEqual(sagrada["videos"][0]["key"], "youtube:a")
        self.assertEqual(self.lib.map_places(category="food", city="Rome")["places"][0]["name"], "Da Enzo")


class VideoIndexTests(unittest.TestCase):
    def test_rows_and_version_change_when_a_post_is_added(self):
        index = VideoIndex(":memory:", clock=lambda: 100.0)
        before = index.version()
        index.put("tiktok:9", {"places": []})
        self.assertNotEqual(index.version(), before)
        self.assertEqual(index.rows()[0][0], "tiktok:9")


if __name__ == "__main__":
    unittest.main()
