"""Provider-agnostic AIAdapter protocol and built-in implementations.

The adapter isolates every provider-specific detail — API endpoints,
authentication, SDK types, response parsing — from the planning engine.
The planning engine calls extract_intent() and optional judge_candidates();
it never sees credentials, SDK objects, or provider-specific error types.

Two-phase reservation through ModelUsageLedger ensures quota enforcement
before dispatch, reconciling actual usage without logging secrets or private data.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Protocol, runtime_checkable

from .search_intent import (
    INTENT_SCHEMA,
    INTENT_SYSTEM,
    SearchIntent,
    fallback_intent,
    validate_intent,
)
from .candidate_judge import (
    JUDGE_SCHEMA,
    JUDGE_SYSTEM,
    JudgeResult,
    MAX_JUDGE_CANDIDATES,
    sanitize_candidates_for_judge,
    validate_judge_response,
)
from .model_ledger import ModelUsageLedger, QuotaExceededError, QuotaLimits

logger = logging.getLogger(__name__)


# --- protocol -----------------------------------------------------------------

@runtime_checkable
class AIAdapter(Protocol):
    """Minimal interface for model inference in planning.

    The planning engine depends only on this protocol.
    Provider-specific API calls, model IDs, authentication, and response
    parsing stay inside each implementation; they never reach the caller.

    Changing the provider requires implementing this protocol and updating
    configuration — not changing personal_pipeline.py or any planning module.
    """

    #: Human-readable provider identifier used in diagnostics (not a secret).
    name: str

    def extract_intent(self, raw_request: str, brief: dict) -> Optional[SearchIntent]:
        """Parse a natural-language request into a validated SearchIntent.

        Returns None on any failure (provider error, timeout, schema violation).
        Must never raise — catch all provider exceptions internally.
        Must never log API keys, raw response bodies, or personal note text.
        """
        ...

    def judge_candidates(
        self, candidates: List[Dict[str, Any]], brief: dict, criteria: Optional[dict] = None
    ) -> Optional[JudgeResult]:
        """Optionally rank a bounded list of already-retrieved candidates.

        Returns None on any failure, quota exhaustion, or validation error.
        Must never invent places or coordinates.
        Must never raise — catch all exceptions internally.
        """
        ...


# --- safe no-op ---------------------------------------------------------------

class FallbackOnlyAdapter:
    """Safe adapter used when no AI provider is configured.

    Returns None unconditionally so personal_pipeline falls back to
    brief-derived intent and deterministic ranking without any AI call.
    """
    name = 'fallback_only'

    def extract_intent(self, raw_request: str, brief: dict) -> Optional[SearchIntent]:
        return None

    def judge_candidates(
        self, candidates: List[Dict[str, Any]], brief: dict, criteria: Optional[dict] = None
    ) -> Optional[JudgeResult]:
        return None


# --- Azure implementation -----------------------------------------------------

class AzureIntentAdapter:
    """Intent extraction and optional candidate judging using the Luna normalizer.

    Wraps the normalize() method on AzureResearchProvider or any provider
    conforming to normalize(system, payload, schema, task_id).
    Supports two-phase quota reservation and reconciliation via ModelUsageLedger.
    """

    def __init__(
        self,
        provider,
        *,
        model_name: Optional[str] = None,
        ledger: Optional[ModelUsageLedger] = None,
        limits: Optional[QuotaLimits] = None,
    ):
        """
        provider   – object with normalize(system, payload, schema, task_id).
        model_name – human-readable identifier for diagnostics only.
        ledger     – optional ModelUsageLedger for quota enforcement & token accounting.
        limits     – optional QuotaLimits overriding the ledger defaults.
        """
        self._provider = provider
        self.name = model_name or getattr(provider, 'name', 'azure')
        self._ledger = ledger
        self._limits = limits
        self.last_judge_status: str = 'idle'

    @property
    def ledger(self) -> Optional[ModelUsageLedger]:
        return self._ledger

    def extract_intent(self, raw_request: str, brief: dict) -> Optional[SearchIntent]:
        if not raw_request or not raw_request.strip():
            return None

        reservation_id = None
        if self._ledger is not None:
            try:
                reservation_id = self._ledger.reserve(
                    self.name,
                    self.name,
                    estimated_tokens=1500,
                    task_id="intent-extraction",
                    limits=self._limits,
                )
            except QuotaExceededError as exc:
                logger.warning("Intent extraction denied by quota (%s); using fallback", exc)
                return None

        payload = {
            'trip_request': raw_request[:4000],
            'destination': brief.get('destination', ''),
            'instruction': (
                'Extract travel preferences from trip_request. '
                'Do not invent place names, addresses, coordinates, prices, '
                'hours, or any factual venue details. '
                'Return only the structured fields in the response schema.'
            ),
        }
        try:
            result = self._provider.normalize(
                INTENT_SYSTEM, payload, INTENT_SCHEMA, 'intent-extraction'
            )
            if not isinstance(result, dict):
                logger.warning(
                    'Intent extraction: provider returned non-dict (%s); using fallback',
                    type(result).__name__,
                )
                if self._ledger and reservation_id:
                    self._ledger.reconcile(reservation_id, status='failed')
                return None

            # Usage metadata is transport bookkeeping, not model output: strip it
            # before strict schema validation so it is never treated as intent.
            usage = result.get('__usage__')
            result = {k: v for k, v in result.items() if k != '__usage__'}
            intent = validate_intent(result, brief, model_name=self.name)
            if self._ledger and reservation_id:
                prompt_tokens = usage.get('prompt_tokens') if usage else None
                completion_tokens = usage.get('completion_tokens') if usage else None
                self._ledger.reconcile(
                    reservation_id,
                    status='succeeded',
                    prompt_tokens=prompt_tokens,
                    completion_tokens=completion_tokens,
                )
            return intent
        except ValueError as exc:
            logger.warning('Intent extraction schema violation (%s); using fallback', exc)
            if self._ledger and reservation_id:
                self._ledger.reconcile(reservation_id, status='failed')
            return None
        except Exception as exc:
            logger.warning(
                'Intent extraction provider error (%s); using fallback',
                type(exc).__name__,
            )
            if self._ledger and reservation_id:
                status = 'timeout' if 'timeout' in type(exc).__name__.lower() else 'failed'
                self._ledger.reconcile(reservation_id, status=status)
            return None

    def judge_candidates(
        self, candidates: List[Dict[str, Any]], brief: dict, criteria: Optional[dict] = None
    ) -> Optional[JudgeResult]:
        if not candidates:
            self.last_judge_status = 'skipped'
            return None

        sanitized = sanitize_candidates_for_judge(candidates)
        if not sanitized:
            self.last_judge_status = 'skipped'
            return None

        reservation_id = None
        if self._ledger is not None:
            try:
                reservation_id = self._ledger.reserve(
                    self.name,
                    self.name,
                    estimated_tokens=2000,
                    task_id="candidate-judging",
                    limits=self._limits,
                )
            except QuotaExceededError as exc:
                self.last_judge_status = 'quota_denied'
                logger.warning("Candidate judging denied by quota (%s); skipping judging", exc)
                return None

        payload = {
            "candidates": sanitized,
            "destination": brief.get("destination", ""),
            "interests": brief.get("interests", []),
            "custom_instructions": (brief.get("custom_instructions") or "")[:500],
            "criteria": criteria or {},
        }
        allowed_ids = {c["id"] for c in sanitized}

        try:
            result = self._provider.normalize(
                JUDGE_SYSTEM, payload, JUDGE_SCHEMA, 'candidate-judging'
            )
            usage = result.get('__usage__') if isinstance(result, dict) else None
            if isinstance(result, dict):
                result = {k: v for k, v in result.items() if k != '__usage__'}
            validated = validate_judge_response(result, allowed_ids, model_name=self.name)
            if validated is None:
                self.last_judge_status = 'failed'
                if self._ledger and reservation_id:
                    self._ledger.reconcile(reservation_id, status='failed')
                return None

            self.last_judge_status = 'succeeded'
            if self._ledger and reservation_id:
                prompt_tokens = usage.get('prompt_tokens') if usage else None
                completion_tokens = usage.get('completion_tokens') if usage else None
                self._ledger.reconcile(
                    reservation_id,
                    status='succeeded',
                    prompt_tokens=prompt_tokens,
                    completion_tokens=completion_tokens,
                )
            return validated
        except Exception as exc:
            self.last_judge_status = 'failed'
            logger.warning(
                'Candidate judging provider error (%s); falling back to deterministic ranking',
                type(exc).__name__,
            )
            if self._ledger and reservation_id:
                status = 'timeout' if 'timeout' in type(exc).__name__.lower() else 'failed'
                self._ledger.reconcile(reservation_id, status=status)
            return None


AzureModelAdapter = AzureIntentAdapter
