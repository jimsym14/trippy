import unittest

from trippy.planner import planner_config as pc
from trippy.usage import Controls


class PlannerConfigTests(unittest.TestCase):
    def test_only_listed_choices_are_accepted(self):
        self.assertEqual(pc.clean({'place_finder': 'gemini_blend'})['idea_model'], pc.DEFAULT['idea_model'])
        for bad in ({'place_finder': 'something_else'}, {'idea_model': 'gpt-99'}, {'unknown': 'x'}, 'gemini_blend'):
            with self.assertRaises(ValueError): pc.clean(bad)

    def test_estimate_breaks_down_each_step(self):
        today = pc.estimate({}, days=2, categories=5)
        self.assertEqual([l['step'] for l in today['lines']],
                         ['Reading the request', 'Finding places', 'Famous sights', 'Plan notes and day themes'])
        self.assertAlmostEqual(today['lines'][1]['usd'], 5 * 0.035, places=4)
        self.assertTrue(any('EEA' in w for w in today['warnings']))
        blend = pc.estimate({'place_finder': 'gemini_blend', 'place_check': 'osm', 'request_reader': 'keywords'}, days=2)
        self.assertEqual(blend['total_usd'], 0)          # free tier + free check
        self.assertGreater(blend['paid_total_usd'], 0)   # what it costs off the free tier
        google = pc.estimate({'place_finder': 'gemini_blend', 'place_check': 'google'}, days=2)
        self.assertGreater(google['total_usd'], pc.estimate({'place_finder': 'gemini_blend'}, days=2)['total_usd'])

    def test_controls_store_a_clean_planner_and_refuse_bad_values(self):
        controls = Controls.__new__(Controls)
        import threading
        controls.lock = threading.Lock(); controls.values = dict(Controls.DEFAULTS)
        controls.usage = type('U', (), {'database_url': None, 'path': None})()
        saved = controls.update({'planner': {'place_finder': 'gemini_blend', 'idea_model': 'gemini-3.5-flash-lite'}})
        self.assertEqual(saved['planner']['idea_model'], 'gemini-3.5-flash-lite')
        self.assertEqual(saved['planner']['place_check'], pc.DEFAULT['place_check'])
        with self.assertRaises(ValueError): controls.update({'planner': {'idea_model': 'anything'}})


if __name__ == '__main__':
    unittest.main()
