import tempfile
import unittest
from pathlib import Path
from urllib.error import HTTPError

from trippy import call_log
from trippy.call_log import CallLog

A = '11111111-1111-4111-8111-111111111111'


class CallLogTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / 'calls.jsonl'
        self.log = CallLog(self.path, None, flush_seconds=0)

    def tearDown(self):
        self.dir.cleanup()

    def test_records_success_with_tokens_and_split_into_kind_and_provider(self):
        with self.log.track('ai:gemini', model='gemini-x', client=A) as call:
            call.tokens(100, 20)
        with self.log.track('google:details', client=A) as call:
            call.nbytes = 2048
        with self.log.track('free:nominatim'):
            pass
        rows = {r['provider']: r for r in self.log.rows()}
        self.assertEqual((rows['gemini']['kind'], rows['gemini']['tokens_in'], rows['gemini']['model']), ('ai', 100, 'gemini-x'))
        self.assertEqual((rows['google']['kind'], rows['google']['operation'], rows['google']['nbytes']), ('api', 'details', 2048))
        self.assertEqual(rows['nominatim']['status'], 'ok')
        self.assertEqual(rows['gemini']['client'], A)

    def test_errors_are_recorded_and_reraised_without_the_message(self):
        with self.assertRaises(HTTPError):
            with self.log.track('ai:gemini', model='m'):
                raise HTTPError('https://x/?key=SECRET', 429, 'secret words', {}, None)
        with self.assertRaises(TimeoutError):
            with self.log.track('free:overpass'):
                raise TimeoutError('slow')
        statuses = {r['provider']: r for r in self.log.rows()}
        self.assertEqual((statuses['gemini']['status'], statuses['gemini']['http_status']), ('rate_limited', 429))
        self.assertEqual(statuses['overpass']['status'], 'timeout')
        self.assertNotIn('SECRET', str(self.log.rows()))
        self.assertNotIn('secret words', str(self.log.rows()))

    def test_plan_is_attached_from_the_worker_thread(self):
        call_log.set_plan('job-7')
        try:
            with self.log.track('google:photo'): pass
        finally:
            call_log.set_plan(None)
        self.assertEqual(self.log.rows()[0]['plan'], 'job-7')

    def test_filters_and_stats(self):
        for ms_error in (False, True):
            try:
                with self.log.track('ai:azure', model='luna'):
                    if ms_error: raise ValueError('x')
            except ValueError: pass
        with self.log.track('google:photo'): pass
        everything = self.log.query()
        self.assertEqual(everything['total'], 3)
        self.assertEqual(everything['stats']['errors'], 1)
        self.assertEqual(dict(everything['facets']['kind']), {'ai': 2, 'api': 1})
        self.assertEqual(self.log.query(kind='ai', status='error')['total'], 1)
        self.assertEqual(self.log.query(provider='google')['total'], 1)
        self.assertEqual(self.log.query(client='nobody')['total'], 0)
        self.assertEqual(self.log.query(min_ms=10**6)['total'], 0)
        self.assertEqual(self.log.query(limit=1)['rows'][0]['provider'], 'google')   # newest first

    def test_survives_a_restart_and_keeps_ids_increasing(self):
        with self.log.track('ai:gemini'): pass
        self.log.flush()
        again = CallLog(self.path, None, flush_seconds=0)
        self.assertEqual(len(again.rows()), 1)
        with again.track('ai:gemini'): pass
        ids = [r['id'] for r in again.rows()]
        self.assertEqual(len(set(ids)), 2)

    def test_tracking_before_install_is_a_noop(self):
        call_log.install(None)
        with call_log.track('ai:gemini') as call:
            call.tokens(1, 2)


if __name__ == '__main__':
    unittest.main()
