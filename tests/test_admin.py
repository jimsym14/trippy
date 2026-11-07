import tempfile
import unittest
from pathlib import Path

from trippy.admin_summary import build
from trippy.usage import Controls, Usage, clean_client

A = '11111111-1111-4111-8111-111111111111'
B = '22222222-2222-4222-8222-222222222222'


class UsageTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.usage = Usage(Path(self.dir.name) / 'usage.json', None, flush_seconds=0)

    def tearDown(self):
        self.dir.cleanup()

    def test_counts_survive_a_restart_in_file_mode(self):
        self.usage.hit('google:details', A); self.usage.hit('api:/api/places/details', A, 1, 2000)
        self.usage.report(A, {'trips': 3, 'saved_places': 12, 'storage_mb': 8.5, 'app_version': '1.0', 'name': 'ignored'})
        self.usage.flush()
        again = Usage(Path(self.dir.name) / 'usage.json', None, flush_seconds=0)
        self.assertEqual(again.count_today('google', A), 1)
        self.assertEqual(again.client_reports()[A]['report']['trips'], 3)
        self.assertNotIn('name', again.client_reports()[A]['report'])

    def test_controls_block_and_limit(self):
        controls = Controls(self.usage)
        controls.update({'blocked': [A], 'client_caps': {B: 2}, 'global_google_cap': 5})
        self.assertEqual(controls.refusal(A), 'install_blocked')
        self.assertIsNone(controls.refusal(B, google=True))
        self.usage.hit('google:photo', B); self.usage.hit('google:photo', B)
        self.assertEqual(controls.refusal(B, google=True), 'daily_limit_reached')
        controls.update({'paid_research': False})
        self.assertEqual(controls.refusal(B, paid=True), 'paid_research_paused')
        with self.assertRaises(ValueError): controls.update({'secret': 'x'})
        with self.assertRaises(ValueError): controls.update({'global_google_cap': -1})

    def test_summary_has_per_install_averages_and_no_secrets(self):
        for _ in range(4): self.usage.hit('api:/api/places/search', A, 1, 1000)
        self.usage.hit('google:app_search', A); self.usage.hit('plan:started', A); self.usage.hit('plan:ready', A)
        self.usage.report(A, {'trips': 2, 'storage_mb': 10})
        self.usage.report(B, {'trips': 4, 'storage_mb': 20})
        summary = build(self.usage.rows(), self.usage.client_reports(), values={'GOOGLE_PLACES_API_KEY': 'secret-value-123'})
        self.assertEqual(summary['totals']['installs'], 2)
        self.assertEqual(summary['totals']['avg_trips'], 3)
        self.assertEqual(summary['totals']['avg_storage_mb'], 15)
        a = next(i for i in summary['installs'] if i['client'] == A)
        self.assertEqual((a['requests'], a['google'], a['plans'], a['plans_ready']), (4, 1, 1, 1))
        self.assertNotIn('secret-value-123', str(summary))
        self.assertTrue(next(s for s in summary['settings'] if s['key'] == 'GOOGLE_PLACES_API_KEY')['set'])

    def test_install_ids_must_be_uuids(self):
        self.assertEqual(clean_client('robert; drop table'), 'unknown')
        self.assertEqual(clean_client(A.upper()), A)


if __name__ == '__main__':
    unittest.main()
