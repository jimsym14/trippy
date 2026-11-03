"""Offline provider boundary. No Azure/OpenAI client is initialized here."""

from dataclasses import dataclass
from pydantic import ValidationError

from .budgets import Budgets, Limits, RateCard
from .common import DomainError
from .contracts import ProviderResult


class RetryableBeforeDispatch(Exception):
    """A trusted adapter proves no billable request was sent."""


@dataclass(frozen=True)
class ProviderRequest:
    job: dict
    limits: Limits
    dispatch_key: str


class FakeProvider:
    provider = "fake"
    paid = False

    def __init__(self):
        self.calls = 0

    def run(self, request, heartbeat):
        self.calls += 1
        heartbeat()
        return ProviderResult(input_tokens=0, output_tokens=0, tool_calls=0,
                              summary="Offline pipeline preview; no AI research was performed.")


class Worker:
    def __init__(self, queue, provider=None, *, rate=None, limits=None):
        self.queue = queue
        self.provider = provider or FakeProvider()
        self.rate = rate or RateCard()
        self.limits = limits or Limits()
        self.budgets = Budgets(queue.engine)
        if self.provider.paid:
            raise ValueError("Paid adapters are disabled in Stage 2 pending provider audit and agreed caps")
        if self.provider.provider != self.rate.provider or queue.provider != self.rate.provider:
            raise ValueError("Worker, queue and verified rate card must use the same provider")

    def run_once(self):
        claimed = self.queue.claim()
        if claimed is None:
            return {"status": "idle"}
        job, lease = claimed
        reservation_id, settled = None, False
        try:
            reservation_id = self.budgets.reserve(job, lease, self.rate, self.limits)
            response = self.provider.run(ProviderRequest(job, self.limits, reservation_id),
                                         lambda: self.queue.heartbeat(lease))
            result = ProviderResult.model_validate(response)
            settlement = self.budgets.settle(reservation_id, result=result, rate=self.rate)
            settled = True
            if settlement["overrun"] or result.input_tokens > self.limits.input_tokens or result.output_tokens > self.limits.output_tokens or result.tool_calls > self.limits.tool_calls:
                raise DomainError("provider_limit_exceeded")
            self.queue.finish(lease, result)
            return {"job_id": job["id"], "status": "completed"}
        except RetryableBeforeDispatch:
            if reservation_id and not settled:
                self.budgets.settle(reservation_id, undispatched=True)
            return self._fail(lease, "not_dispatched", retry=True)
        except (DomainError, ValidationError) as error:
            if reservation_id and not settled:
                self.budgets.settle(reservation_id, uncertain=True)
            reason = error.code if isinstance(error, DomainError) else "invalid_provider_result"
            return self._fail(lease, reason)
        except Exception:
            # Never put raw provider/DB exceptions, prompts or tokens in events.
            if reservation_id and not settled:
                self.budgets.settle(reservation_id, uncertain=True)
            return self._fail(lease, "dispatch_outcome_unknown")

    def _fail(self, lease, reason, *, retry=False):
        try:
            self.queue.fail(lease, reason, retry=retry)
        except DomainError as error:
            if error.code != "lease_lost":
                raise
            return {"job_id": lease.job_id, "status": "lease_lost"}
        return {"job_id": lease.job_id, "status": "retry_pending" if retry else "failed", "reason": reason}
