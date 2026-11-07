import unittest

from trippy import capacity
from trippy.usage import Controls


class CapacityTests(unittest.TestCase):
    def test_text_search_metrics_share_one_free_allowance(self):
        rows = [('2026-11-02', 'google:text_search', 'a', 600, 0), ('2026-11-03', 'google:social_search', 'b', 500, 0),
                ('2026-10-30', 'google:app_search', 'a', 999, 0)]  # last month: not counted
        result = capacity.build(rows, dict(Controls.DEFAULTS), today='2026-11-07')
        sku = next(s for s in result['skus'] if s['id'] == 'text_search_enterprise')
        self.assertEqual((sku['used'], sku['free']), (1100, 1000))
        self.assertAlmostEqual(sku['overage_usd'], 3.5)

    def test_scenarios_and_free_capacity(self):
        result = capacity.build([], dict(Controls.DEFAULTS), today='2026-11-07')
        one, hundred, thousand = result['scenarios']
        self.assertEqual(one['google_usd'], 0)  # one user stays inside the free calls
        self.assertGreater(hundred['google_usd'], 0)
        self.assertGreater(thousand['total_usd'], hundred['total_usd'] * 5)
        self.assertEqual(result['free_capacity']['tightest'], 'Text Search (Enterprise)')
        self.assertTrue(all(b['severity'] in {'now', 'soon', 'scale'} for b in result['bottlenecks']))

    def test_no_global_cap_means_no_exposure_figure(self):
        controls = dict(Controls.DEFAULTS, global_google_cap=None)
        self.assertIsNone(capacity.build([], controls, today='2026-11-07')['exposure'])


if __name__ == '__main__':
    unittest.main()
