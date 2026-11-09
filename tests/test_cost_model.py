import unittest

from trippy import cost_model


class CostModelTests(unittest.TestCase):
    def test_bundled_copy_in_the_app_is_current(self):
        # The app ships this file for offline use; refresh with `python3 -m trippy.cost_model --write`.
        self.assertEqual(cost_model.BUNDLED.read_text(), cost_model.bundled_text())

    def test_net_price_takes_out_vat_and_apples_cut(self):
        self.assertAlmostEqual(cost_model.net_usd(2.99), 2.2546, places=3)
        self.assertAlmostEqual(cost_model.net_usd(19.99), 15.07, places=2)

    def test_free_ui_kit_loads_cover_small_user_counts(self):
        small = cost_model.compute(100, pipeline='open_data')
        self.assertEqual(small['costs']['google_ui_kit'], 0)
        big = cost_model.compute(10_000, pipeline='open_data')
        self.assertAlmostEqual(big['costs']['google_ui_kit'], (10_000 * 25 - 10_000) * 0.001, places=2)

    def test_reuse_lowers_video_cost_and_stages_follow_users(self):
        fresh = cost_model.compute(10_000, reuse=0)
        reused = cost_model.compute(10_000, reuse=0.5)
        self.assertAlmostEqual(reused['costs']['gemini_video'], fresh['costs']['gemini_video'] / 2, places=1)
        self.assertEqual(cost_model.compute(500)['fixed_stage'], 'launch')
        self.assertEqual(cost_model.compute(50_000)['fixed_stage'], 'scale')

    def test_live_counters_only_this_month(self):
        rows = [('2026-11-02', 'google:ui_kit', 'a', 40, 0), ('2026-10-30', 'google:ui_kit', 'a', 99, 0)]
        live = {row['metric']: row['month'] for row in cost_model.snapshot(rows, today='2026-11-08')['live']}
        self.assertEqual(live['google:ui_kit'], 40)


if __name__ == '__main__':
    unittest.main()
