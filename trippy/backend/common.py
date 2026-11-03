from contextlib import contextmanager
from datetime import datetime, timezone
from hashlib import sha256
import json


class DomainError(Exception):
    def __init__(self, code, status=409):
        self.code, self.status = code, status
        super().__init__(code)


def utcnow():
    return datetime.now(timezone.utc)


def fingerprint(value):
    return sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                             ensure_ascii=False, allow_nan=False).encode()).hexdigest()


@contextmanager
def transaction(engine):
    """SQLite serializes writers; PostgreSQL uses row locks inside transactions."""
    with engine.connect() as connection:
        if connection.dialect.name == "sqlite":
            connection.exec_driver_sql("BEGIN IMMEDIATE")
        else:
            connection.begin()
        try:
            yield connection
            connection.commit()
        except BaseException:
            connection.rollback()
            raise


def row(connection, table, predicate, *, lock=False):
    statement = table.select().where(predicate)
    if lock:
        statement = statement.with_for_update()
    result = connection.execute(statement).mappings().first()
    if result is None:
        raise DomainError("not_found", 404)
    return dict(result)
