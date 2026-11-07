import io
import json
import unittest
from urllib.error import HTTPError

from trippy.accounts import AccountError, Accounts

VALUES = {'SUPABASE_URL': 'https://example.supabase.co', 'SUPABASE_PUBLISHABLE_KEY': 'pub', 'SUPABASE_SECRET_KEY': 'sec',
          'TRIPPY_ADMIN_EMAILS': 'Boss@Example.com, other@example.com'}


class FakeSupabase:
    def __init__(self):
        self.calls = []

    def __call__(self, request, timeout=0):
        self.calls.append((request.get_method(), request.full_url, dict(request.header_items())))
        path = request.full_url.split('.co', 1)[1]
        if path == '/auth/v1/verify':
            body = json.loads(request.data)
            if body['token'] != '123456': raise HTTPError(request.full_url, 403, 'bad', {}, io.BytesIO(b'{}'))
            return self.reply({'access_token': 'acc', 'refresh_token': 'ref', 'expires_in': 3600,
                               'user': {'id': 'u1', 'email': 'boss@example.com', 'phone': '+30...'}})
        if path == '/auth/v1/user':
            token = request.headers.get('Authorization')
            if token != 'Bearer acc': raise HTTPError(request.full_url, 401, 'no', {}, io.BytesIO(b'{}'))
            return self.reply({'id': 'u1', 'email': 'boss@example.com'})
        return self.reply({})

    @staticmethod
    def reply(payload):
        class R(io.BytesIO):
            def __enter__(self): return self
            def __exit__(self, *a): return False
        return R(json.dumps(payload).encode())


class AccountTests(unittest.TestCase):
    def test_email_code_returns_only_the_session_and_the_server_decides_admin(self):
        fake = FakeSupabase(); accounts = Accounts(VALUES, opener=fake)
        session = accounts.email_verify('boss@example.com', '123 456')
        self.assertEqual(session['user'], {'id': 'u1', 'email': 'boss@example.com'})   # no phone or extra fields
        person = accounts.person('acc')
        self.assertTrue(person.admin)
        accounts.person('acc')
        self.assertEqual(sum(1 for c in fake.calls if c[1].endswith('/auth/v1/user')), 1)  # cached
        self.assertIsNone(accounts.person('forged'))

    def test_wrong_code_and_bad_email_are_refused(self):
        accounts = Accounts(VALUES, opener=FakeSupabase())
        with self.assertRaises(AccountError) as wrong: accounts.email_verify('boss@example.com', '000000')
        self.assertEqual(wrong.exception.code, 'invalid_code')
        with self.assertRaises(AccountError): accounts.email_start('not-an-email')

    def test_not_configured_and_rate_limited(self):
        with self.assertRaises(AccountError) as off: Accounts({}).email_start('a@b.co')
        self.assertEqual(off.exception.code, 'accounts_not_configured')
        accounts = Accounts(VALUES, opener=FakeSupabase(), clock=lambda: 100.0)
        self.assertTrue(all(accounts.allow('1.2.3.4', 'start', 3) for _ in range(3)))
        self.assertFalse(accounts.allow('1.2.3.4', 'start', 3))
        self.assertTrue(accounts.allow('5.6.7.8', 'start', 3))

    def test_the_secret_key_is_only_used_to_delete(self):
        fake = FakeSupabase(); accounts = Accounts(VALUES, opener=fake)
        accounts.email_start('boss@example.com')
        self.assertEqual(fake.calls[-1][2].get('Apikey'), 'pub')
        accounts.delete(accounts.person('acc'))
        self.assertEqual(fake.calls[-1][0], 'DELETE'); self.assertEqual(fake.calls[-1][2].get('Apikey'), 'sec')


if __name__ == '__main__':
    unittest.main()


class GoogleAndCreditsTests(unittest.TestCase):
    def test_google_url_uses_pkce_and_only_our_callback(self):
        accounts = Accounts(VALUES, opener=FakeSupabase())
        url = accounts.google_url('a' * 43, 'trippy://auth-callback')['url']
        self.assertTrue(url.startswith('https://example.supabase.co/auth/v1/authorize?provider=google'))
        self.assertIn('code_challenge_method=s256', url)
        with self.assertRaises(AccountError): accounts.google_url('a' * 43, 'https://evil.example/cb')
        with self.assertRaises(AccountError): accounts.google_url('short', 'trippy://auth-callback')

    def test_monthly_credits_count_per_account(self):
        import tempfile
        from pathlib import Path
        from trippy.usage import Controls, Usage, credit_left, credits
        user = '33333333-3333-4333-8333-333333333333'
        with tempfile.TemporaryDirectory() as folder:
            usage = Usage(Path(folder) / 'u.json', None, flush_seconds=0)
            controls = Controls(usage)
            controls.update({'free_plans_per_month': 2})
            usage.hit('credit:plan', user); usage.hit('credit:plan', user)
            summary = credits(usage, controls, user)
            self.assertEqual(next(i for i in summary['items'] if i['id'] == 'plans')['used'], 2)
            self.assertFalse(credit_left(summary, 'plans'))
            self.assertTrue(credit_left(summary, 'videos'))
            self.assertTrue(credit_left(credits(usage, controls, user, admin=True), 'plans'))


class UserDataTests(unittest.TestCase):
    def test_snapshot_round_trip_cap_and_delete(self):
        import tempfile
        from pathlib import Path
        from trippy.usage import Usage
        from trippy.user_data import UserData, UserDataError
        user = '44444444-4444-4444-8444-444444444444'
        with tempfile.TemporaryDirectory() as folder:
            store = UserData(Usage(Path(folder) / 'u.json', None, flush_seconds=0), Path(folder) / 'data')
            self.assertIsNone(store.load(user)['payload'])
            store.save(user, {'trips': [1, 2]})
            self.assertEqual(store.load(user)['payload'], {'trips': [1, 2]})
            with self.assertRaises(UserDataError): store.save(user, {'x': 'a' * 8_100_000})
            store.delete(user)
            self.assertIsNone(store.load(user)['payload'])
            with self.assertRaises(ValueError): store.load('../../etc/passwd')
