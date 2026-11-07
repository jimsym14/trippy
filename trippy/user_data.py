"""What an account keeps on the server: one snapshot of the app's data per user.

The phone sends its trips, saves, places it has been, notes and settings as one JSON
document (moving a phone-only setup into an account, or backing up); another phone
signed in to the same account reads it back. Only the account's own session can read or
write it, and the size is capped. Stored next to the usage stats (Postgres when
TRIPPY_STATS_DATABASE_URL is set, else a file that a Render restart clears).
"""
from __future__ import annotations

import json
import time
from pathlib import Path

MAX_BYTES = 8_000_000


class UserDataError(Exception):
    def __init__(self, status, code):
        super().__init__(code)
        self.status, self.code = status, code


class UserData:
    def __init__(self, usage, folder):
        self.usage = usage                      # its Postgres connection is reused
        self.folder = Path(folder)

    def _file(self, user_id):
        from uuid import UUID
        return self.folder / f'{UUID(user_id)}.json'

    def save(self, user_id, payload):
        if not isinstance(payload, dict): raise UserDataError(422, 'invalid_data')
        raw = json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
        if len(raw.encode()) > MAX_BYTES: raise UserDataError(413, 'too_large')
        saved_at = time.time()
        if self.usage.database_url:
            with self.usage._connect() as db:
                db.execute('''CREATE TABLE IF NOT EXISTS trippy_admin.user_data (
                    user_id text PRIMARY KEY, payload jsonb NOT NULL, bytes integer NOT NULL, updated_at timestamptz NOT NULL DEFAULT now())''')
                db.execute('''INSERT INTO trippy_admin.user_data (user_id, payload, bytes, updated_at) VALUES (%s, %s, %s, now())
                    ON CONFLICT (user_id) DO UPDATE SET payload = EXCLUDED.payload, bytes = EXCLUDED.bytes, updated_at = now()''',
                           (user_id, raw, len(raw.encode())))
        else:
            self.folder.mkdir(parents=True, exist_ok=True)
            temp = self._file(user_id).with_suffix('.tmp')
            temp.write_text(json.dumps({'payload': payload, 'updated_at': saved_at}, ensure_ascii=False))
            temp.replace(self._file(user_id))
        return {'saved': True, 'bytes': len(raw.encode()), 'updated_at': saved_at}

    def load(self, user_id):
        if self.usage.database_url:
            with self.usage._connect() as db:
                db.execute('''CREATE TABLE IF NOT EXISTS trippy_admin.user_data (
                    user_id text PRIMARY KEY, payload jsonb NOT NULL, bytes integer NOT NULL, updated_at timestamptz NOT NULL DEFAULT now())''')
                row = db.execute('SELECT payload, updated_at FROM trippy_admin.user_data WHERE user_id = %s', (user_id,)).fetchone()
            return {'payload': row[0], 'updated_at': row[1].timestamp()} if row else {'payload': None, 'updated_at': None}
        path = self._file(user_id)
        if not path.is_file(): return {'payload': None, 'updated_at': None}
        return json.loads(path.read_text())

    def delete(self, user_id):
        if self.usage.database_url:
            with self.usage._connect() as db:
                db.execute('DELETE FROM trippy_admin.user_data WHERE user_id = %s', (user_id,))
        else:
            self._file(user_id).unlink(missing_ok=True)
