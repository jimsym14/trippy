"""Trippy accounts through Supabase Auth, called only from this server.

The app never holds a Supabase key: it asks this server to send an email code,
verify it, or exchange an Apple identity token, and gets back a session. Every
later request carries the session's access token (`X-Trippy-Session`); the server
checks it with Supabase (cached for a minute) and decides admin rights itself from
TRIPPY_ADMIN_EMAILS, so no client can make itself an admin.

Settings (Render Environment): SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY (auth calls),
SUPABASE_SECRET_KEY (only for deleting an account), TRIPPY_ADMIN_EMAILS.
"""
from __future__ import annotations

import hashlib
import json
import re
import threading
import time
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

EMAIL = re.compile(r'^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s]{2,24}$')


class AccountError(Exception):
    def __init__(self, status, code):
        super().__init__(code)
        self.status, self.code = status, code


@dataclass(frozen=True)
class Person:
    user_id: str
    email: str | None
    admin: bool


class Accounts:
    def __init__(self, values, *, opener=urlopen, clock=time.time):
        self.url = (values.get('SUPABASE_URL') or '').strip().rstrip('/')
        self.public_key = (values.get('SUPABASE_PUBLISHABLE_KEY') or '').strip()
        self.secret_key = (values.get('SUPABASE_SECRET_KEY') or '').strip()
        self.admins = {e.strip().lower() for e in (values.get('TRIPPY_ADMIN_EMAILS') or '').split(',') if e.strip()}
        self.opener, self.clock = opener, clock
        self.lock = threading.Lock()
        self.cache = {}          # sha256(token) -> (checked_at, Person)
        self.attempts = {}       # (address, kind) -> [times]

    @property
    def configured(self):
        return self.url.startswith('https://') and bool(self.public_key)

    # -- rate limits -------------------------------------------------------------
    def allow(self, address, kind, limit=8, window=600):
        now = self.clock()
        with self.lock:
            recent = [t for t in self.attempts.get((address, kind), []) if now - t < window]
            if len(recent) >= limit:
                self.attempts[(address, kind)] = recent
                return False
            self.attempts[(address, kind)] = recent + [now]
            return True

    # -- Supabase calls ------------------------------------------------------------
    def _call(self, method, path, body=None, *, token=None, secret=False):
        if not self.configured: raise AccountError(503, 'accounts_not_configured')
        key = self.secret_key if secret else self.public_key
        if secret and not key: raise AccountError(503, 'account_deletion_not_configured')
        headers = {'apikey': key, 'Content-Type': 'application/json', 'Accept': 'application/json',
                   'Authorization': 'Bearer ' + (token or key)}
        data = json.dumps(body).encode() if body is not None else None
        request = Request(self.url + path, data=data, headers=headers, method=method)
        try:
            with self.opener(request, timeout=15) as response:
                raw = response.read(200_000)
            return json.loads(raw) if raw else {}
        except HTTPError as error:
            status = error.code
            code = {400: 'invalid_code', 401: 'session_expired', 403: 'invalid_code', 404: 'not_found',
                    422: 'invalid_code', 429: 'too_many_requests'}.get(status, 'auth_unavailable')
            raise AccountError(429 if status == 429 else 401 if status in (401, 403) else 400 if status in (400, 422) else 502, code)
        except (URLError, TimeoutError, OSError):
            raise AccountError(502, 'auth_unavailable')

    @staticmethod
    def _session(payload):
        """Only what the app needs: tokens, expiry and who it is."""
        user = payload.get('user') or {}
        if not payload.get('access_token') or not user.get('id'): raise AccountError(502, 'auth_unavailable')
        return {'access_token': payload['access_token'], 'refresh_token': payload.get('refresh_token'),
                'expires_in': payload.get('expires_in', 3600), 'user': {'id': user['id'], 'email': user.get('email')}}

    def email_start(self, email):
        email = (email or '').strip().lower()
        if not EMAIL.match(email): raise AccountError(422, 'invalid_email')
        self._call('POST', '/auth/v1/otp', {'email': email, 'create_user': True})
        return {'sent': True}

    def email_verify(self, email, code):
        email, code = (email or '').strip().lower(), re.sub(r'\D', '', str(code or ''))
        if not EMAIL.match(email) or len(code) != 6: raise AccountError(422, 'invalid_code')
        return self._session(self._call('POST', '/auth/v1/verify', {'type': 'email', 'email': email, 'token': code}))

    def apple(self, id_token, nonce):
        if not isinstance(id_token, str) or not 20 < len(id_token) < 8000 or not isinstance(nonce, str) or len(nonce) > 200:
            raise AccountError(422, 'invalid_apple_token')
        return self._session(self._call('POST', '/auth/v1/token?grant_type=id_token',
                                        {'provider': 'apple', 'id_token': id_token, 'nonce': nonce}))

    def refresh(self, refresh_token):
        if not isinstance(refresh_token, str) or not 8 < len(refresh_token) < 4000: raise AccountError(422, 'invalid_session')
        return self._session(self._call('POST', '/auth/v1/token?grant_type=refresh_token', {'refresh_token': refresh_token}))

    def person(self, access_token):
        """Who a session belongs to, checked with Supabase at most once a minute per token."""
        if not access_token or len(access_token) > 8000: return None
        digest = hashlib.sha256(access_token.encode()).hexdigest()
        now = self.clock()
        with self.lock:
            hit = self.cache.get(digest)
            if hit and now - hit[0] < 60: return hit[1]
        try:
            user = self._call('GET', '/auth/v1/user', token=access_token)
        except AccountError as error:
            if error.status == 401:
                with self.lock: self.cache.pop(digest, None)
            return None
        email = (user.get('email') or '').lower() or None
        found = Person(user_id=user['id'], email=email, admin=bool(email and email in self.admins)) if user.get('id') else None
        with self.lock:
            if len(self.cache) > 5000: self.cache.clear()
            self.cache[digest] = (now, found)
        return found

    def delete(self, person):
        self._call('DELETE', '/auth/v1/admin/users/' + quote(person.user_id, safe=''), secret=True)
        with self.lock: self.cache.clear()
        return {'deleted': True}
