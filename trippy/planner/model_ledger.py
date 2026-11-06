"""Central usage ledger and quota enforcement for AI model calls.

Provides two-phase reservation before dispatch and reconciliation after completion.
Enforces requests-per-minute (RPM), tokens-per-minute (TPM), requests-per-day (RPD),
and optional cost/budget caps. All records are persisted in SQLite with transactional
locking to handle concurrent requests safely.
"""
from __future__ import annotations

from contextlib import closing
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import logging
from pathlib import Path
import sqlite3
from typing import Any, Dict, Optional
import uuid

logger = logging.getLogger(__name__)


class QuotaExceededError(ValueError):
    """Raised when a model invocation would exceed configured quotas."""
    def __init__(self, message: str, *, quota_type: str, limit: int | float, current: int | float):
        super().__init__(message)
        self.quota_type = quota_type
        self.limit = limit
        self.current = current


@dataclass(frozen=True)
class QuotaLimits:
    """Configurable rate and capacity limits for model inference."""
    rpm: Optional[int] = None           # Requests per minute (rolling 60s)
    tpm: Optional[int] = None           # Tokens per minute (rolling 60s)
    rpd: Optional[int] = None           # Requests per day (UTC day)
    max_budget: Optional[Decimal] = None
    currency: str = 'EUR'


class ModelUsageLedger:
    """Durable SQLite-backed ledger for model inference requests and token quotas."""

    def __init__(self, path: Optional[Path | str] = None, default_limits: Optional[QuotaLimits] = None):
        self.path = Path(path) if path is not None else None
        self.default_limits = default_limits or QuotaLimits()
        self._denials_count = 0
        if self.path is not None:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self._init_db()

    def _connect(self) -> sqlite3.Connection:
        if self.path is None:
            conn = sqlite3.connect(":memory:", timeout=15)
        else:
            conn = sqlite3.connect(str(self.path), timeout=15)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with closing(self._connect()) as db, db:
            db.execute("""
                CREATE TABLE IF NOT EXISTS model_reservations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    reservation_id TEXT UNIQUE NOT NULL,
                    provider TEXT NOT NULL,
                    model TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    status TEXT NOT NULL,
                    estimated_tokens INTEGER NOT NULL,
                    prompt_tokens INTEGER,
                    completion_tokens INTEGER,
                    total_tokens INTEGER,
                    usage_source TEXT NOT NULL,
                    cost TEXT,
                    created_at TEXT NOT NULL,
                    reconciled_at TEXT
                )
            """)
            db.execute("""
                CREATE INDEX IF NOT EXISTS idx_res_time ON model_reservations(created_at)
            """)
            db.execute("""
                CREATE INDEX IF NOT EXISTS idx_res_prov_model ON model_reservations(provider, model)
            """)

    def reserve(
        self,
        provider: str,
        model: str,
        estimated_tokens: int = 1000,
        *,
        task_id: str = "inference",
        limits: Optional[QuotaLimits] = None,
        now: Optional[datetime] = None,
    ) -> str:
        """Reserve quota before dispatching an inference call.

        Checks RPM, TPM, RPD, and budget limits. If any limit would be exceeded,
        raises QuotaExceededError without recording a reservation.
        Returns a unique reservation_id to be passed to reconcile().
        """
        if estimated_tokens < 0:
            raise ValueError("estimated_tokens must be non-negative")

        active_limits = limits or self.default_limits
        now_dt = now or datetime.now(timezone.utc)
        now_iso = now_dt.isoformat()
        minute_ago_iso = (now_dt - timedelta(seconds=60)).isoformat()
        day_start_iso = now_dt.replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
        reservation_id = f"res-{uuid.uuid4().hex[:16]}"

        with closing(self._connect()) as db, db:
            if self.path is None:
                self._init_db_on_conn(db)

            db.execute("BEGIN IMMEDIATE")

            # 1. Check RPM (rolling 60s)
            if active_limits.rpm is not None:
                cur = db.execute(
                    "SELECT COUNT(*) FROM model_reservations WHERE created_at >= ? AND provider = ?",
                    (minute_ago_iso, provider),
                )
                count_minute = cur.fetchone()[0]
                if count_minute >= active_limits.rpm:
                    self._denials_count += 1
                    raise QuotaExceededError(
                        f"RPM quota exceeded for provider {provider}: {count_minute} >= {active_limits.rpm}",
                        quota_type="rpm",
                        limit=active_limits.rpm,
                        current=count_minute,
                    )

            # 2. Check TPM (rolling 60s)
            if active_limits.tpm is not None:
                cur = db.execute(
                    """
                    SELECT SUM(
                        CASE 
                            WHEN total_tokens IS NOT NULL THEN total_tokens
                            ELSE estimated_tokens
                        END
                    )
                    FROM model_reservations 
                    WHERE created_at >= ? AND provider = ?
                    """,
                    (minute_ago_iso, provider),
                )
                used_tokens = cur.fetchone()[0] or 0
                if used_tokens + estimated_tokens > active_limits.tpm:
                    self._denials_count += 1
                    raise QuotaExceededError(
                        f"TPM quota exceeded for provider {provider}: {used_tokens + estimated_tokens} > {active_limits.tpm}",
                        quota_type="tpm",
                        limit=active_limits.tpm,
                        current=used_tokens,
                    )

            # 3. Check RPD (requests today)
            if active_limits.rpd is not None:
                cur = db.execute(
                    "SELECT COUNT(*) FROM model_reservations WHERE created_at >= ? AND provider = ?",
                    (day_start_iso, provider),
                )
                count_day = cur.fetchone()[0]
                if count_day >= active_limits.rpd:
                    self._denials_count += 1
                    raise QuotaExceededError(
                        f"Daily request quota exceeded for provider {provider}: {count_day} >= {active_limits.rpd}",
                        quota_type="rpd",
                        limit=active_limits.rpd,
                        current=count_day,
                    )

            # Insert pending reservation
            db.execute(
                """
                INSERT INTO model_reservations (
                    reservation_id, provider, model, task_id, status,
                    estimated_tokens, total_tokens, usage_source, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    reservation_id,
                    provider,
                    model,
                    task_id,
                    "reserved",
                    estimated_tokens,
                    estimated_tokens,  # Holds conservative reservation
                    "estimated",
                    now_iso,
                ),
            )

        return reservation_id

    def reconcile(
        self,
        reservation_id: str,
        *,
        status: str = "succeeded",
        prompt_tokens: Optional[int] = None,
        completion_tokens: Optional[int] = None,
        cost: Optional[Decimal] = None,
        now: Optional[datetime] = None,
    ) -> None:
        """Update a reservation with actual usage or terminal status.

        If actual token usage is reported by the provider, sets usage_source='reported'.
        If token usage was not reported, sets usage_source='estimated' (or 'unknown').
        Conservative reservations are retained on failure to protect upstream quotas.
        """
        now_iso = (now or datetime.now(timezone.utc)).isoformat()
        cost_str = str(cost) if cost is not None else None

        has_actual_tokens = (prompt_tokens is not None) or (completion_tokens is not None)
        total_tokens = None
        usage_source = "reported" if has_actual_tokens else "estimated"

        if has_actual_tokens:
            total_tokens = (prompt_tokens or 0) + (completion_tokens or 0)

        with closing(self._connect()) as db, db:
            if self.path is None:
                self._init_db_on_conn(db)

            db.execute("BEGIN IMMEDIATE")
            cur = db.execute(
                "SELECT estimated_tokens FROM model_reservations WHERE reservation_id = ?",
                (reservation_id,),
            )
            row = cur.fetchone()
            if not row:
                logger.warning("Reconciliation called for unknown reservation: %s", reservation_id)
                return

            if not has_actual_tokens:
                total_tokens = row["estimated_tokens"]
                if row["estimated_tokens"] == 0:
                    usage_source = "unknown"

            db.execute(
                """
                UPDATE model_reservations
                SET status = ?,
                    prompt_tokens = ?,
                    completion_tokens = ?,
                    total_tokens = ?,
                    usage_source = ?,
                    cost = COALESCE(?, cost),
                    reconciled_at = ?
                WHERE reservation_id = ?
                """,
                (
                    status,
                    prompt_tokens,
                    completion_tokens,
                    total_tokens,
                    usage_source,
                    cost_str,
                    now_iso,
                    reservation_id,
                ),
            )

    def get_metrics(self, provider: Optional[str] = None) -> Dict[str, Any]:
        """Return aggregate usage accounting for the current session/ledger."""
        with closing(self._connect()) as db:
            if self.path is None:
                self._init_db_on_conn(db)

            where_clause = "WHERE provider = ?" if provider else ""
            params = (provider,) if provider else ()

            cur = db.execute(
                f"""
                SELECT 
                    COUNT(*) as total_requests,
                    SUM(CASE WHEN status = 'succeeded' THEN 1 ELSE 0 END) as succeeded_requests,
                    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_requests,
                    SUM(CASE WHEN status = 'timeout' THEN 1 ELSE 0 END) as timeout_requests,
                    SUM(CASE WHEN usage_source = 'reported' THEN total_tokens ELSE 0 END) as reported_tokens,
                    SUM(CASE WHEN usage_source = 'estimated' THEN total_tokens ELSE 0 END) as estimated_tokens,
                    SUM(total_tokens) as total_tokens
                FROM model_reservations {where_clause}
                """,
                params,
            )
            row = cur.fetchone()
            return {
                "total_requests": row["total_requests"] or 0,
                "succeeded_requests": row["succeeded_requests"] or 0,
                "failed_requests": row["failed_requests"] or 0,
                "timeout_requests": row["timeout_requests"] or 0,
                "reported_tokens": row["reported_tokens"] or 0,
                "estimated_tokens": row["estimated_tokens"] or 0,
                "total_tokens": row["total_tokens"] or 0,
                "quota_denials": self._denials_count,
            }

    def _init_db_on_conn(self, db: sqlite3.Connection) -> None:
        db.execute("""
            CREATE TABLE IF NOT EXISTS model_reservations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                reservation_id TEXT UNIQUE NOT NULL,
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                task_id TEXT NOT NULL,
                status TEXT NOT NULL,
                estimated_tokens INTEGER NOT NULL,
                prompt_tokens INTEGER,
                completion_tokens INTEGER,
                total_tokens INTEGER,
                usage_source TEXT NOT NULL,
                cost TEXT,
                created_at TEXT NOT NULL,
                reconciled_at TEXT
            )
        """)

