"""Versioned authenticated API. Factory injection supports network-free tests."""

from decimal import Decimal
from uuid import UUID

from fastapi import Depends, FastAPI, Header, Query
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select

from trippy.data import schema_v2 as s
from .auth import RejectAllAuth
from .budgets import Budgets
from .common import DomainError, transaction
from .contracts import BudgetConfiguration, DayOrderMutation, NewJob, NewTrip, SelectionMutation, SlotMutation, TripPatch
from .queue import Queue
from .repository import Repository, receipt, save_receipt


class BodyLimit:
    def __init__(self, app, max_bytes=65536):
        self.app, self.max_bytes = app, max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            body.extend(message.get("body", b""))
            if len(body) > self.max_bytes:
                response = JSONResponse({"error": "request_too_large"}, status_code=413)
                return await response(scope, receive, send)
            if not message.get("more_body", False):
                break
        sent = False

        async def replay():
            nonlocal sent
            if not sent:
                sent = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        await self.app(scope, replay, send)


def create_app(engine, *, auth=None, provider="fake", job_cap=Decimal("0"), planner_knowledge=None):
    auth = auth or RejectAllAuth()
    repository, queue = Repository(engine), Queue(engine, provider=provider, job_cap=job_cap)
    app = FastAPI(title="Trippy backend", version="2.0", docs_url=None, redoc_url=None, openapi_url=None)
    app.add_middleware(BodyLimit)
    app.state.queue = queue
    app.state.repository = repository

    @app.exception_handler(DomainError)
    async def domain_error(request, error):
        headers = {"Cache-Control": "no-store"}
        if error.status == 401:
            headers["WWW-Authenticate"] = "Bearer"
        return JSONResponse({"error": error.code}, status_code=error.status, headers=headers)

    # FastAPI's default validation body may echo submitted secrets. Expose only
    # field locations and error types, never the original request values.
    from fastapi.exceptions import RequestValidationError

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, error):
        return JSONResponse({"error": "invalid_request", "fields": [
            {"loc": list(e["loc"]), "type": e["type"]} for e in error.errors()]}, status_code=422)

    @app.middleware("http")
    async def private_cache(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    bearer = HTTPBearer(auto_error=False)

    def principal(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        if credentials is None or len(credentials.credentials) > 16384:
            raise DomainError("access_token_required", 401)
        return auth.verify(credentials.credentials)

    def admin(user=Depends(principal)):
        if not user.admin:
            raise DomainError("admin_required", 403)
        return user

    def request_key(idempotency_key: str = Header(alias="Idempotency-Key", min_length=1, max_length=128)):
        if any(ord(v) < 33 or ord(v) > 126 for v in idempotency_key):
            raise DomainError("invalid_idempotency_key", 422)
        return idempotency_key

    from trippy.planner.evidence import Search

    @app.post("/v2/planner/knowledge/search")
    def planner_search(body: Search, user=Depends(principal)):
        if planner_knowledge is None:
            raise DomainError("planner_knowledge_not_configured", 503)
        if body.city_id != planner_knowledge.city_id:
            raise DomainError("planner_city_not_available", 404)
        return planner_knowledge.search(body.model_dump(mode="json"))

    @app.get("/health")
    def health():
        return {"status": "ok", "api_version": 2, "paid_adapters_enabled": False}

    @app.get("/v2/trips")
    def trips(user=Depends(principal), after: UUID | None = None, limit: int = Query(default=30, ge=1, le=100)):
        values = repository.list_trips(user.owner_id, after=str(after) if after else None, limit=limit)
        return {"items": values, "next_cursor": values[-1]["id"] if len(values) == limit else None}

    @app.post("/v2/trips", status_code=201)
    def new_trip(body: NewTrip, user=Depends(principal), key=Depends(request_key)):
        if not body.destination.strip():
            raise DomainError("destination_required", 422)
        return repository.create_trip(user.owner_id, key, body.model_dump(mode="json"))

    @app.get("/v2/trips/{trip_id}")
    def trip(trip_id: UUID, user=Depends(principal)):
        return repository.get_trip(user.owner_id, str(trip_id))

    @app.patch("/v2/trips/{trip_id}")
    def patch_trip(trip_id: UUID, body: TripPatch, user=Depends(principal), key=Depends(request_key)):
        return repository.patch_trip(user.owner_id, str(trip_id), key, body.model_dump(mode="json", exclude_unset=True))

    @app.post("/v2/trips/{trip_id}/decisions/{decision_id}/selection")
    def selection(trip_id: UUID, decision_id: UUID, body: SelectionMutation,
                  user=Depends(principal), key=Depends(request_key)):
        return repository.mutate_selection(user.owner_id, str(trip_id), str(decision_id), key, body.model_dump(mode="json"))

    @app.patch("/v2/trips/{trip_id}/decisions/{decision_id}/slot")
    def slot(trip_id: UUID, decision_id: UUID, body: SlotMutation, user=Depends(principal), key=Depends(request_key)):
        return repository.mutate_slot(user.owner_id, str(trip_id), str(decision_id), key,
                                      body.model_dump(mode="json", exclude_unset=True))

    @app.post("/v2/trips/{trip_id}/days/{day_id}/order")
    def order(trip_id: UUID, day_id: UUID, body: DayOrderMutation, user=Depends(principal), key=Depends(request_key)):
        return repository.reorder_day(user.owner_id, str(trip_id), str(day_id), key, body.model_dump(mode="json"))

    @app.post("/v2/jobs", status_code=202)
    def new_job(body: NewJob, user=Depends(principal), key=Depends(request_key)):
        return queue.enqueue(user, key, body.model_dump(mode="json"))

    @app.get("/v2/jobs/{job_id}")
    def job(job_id: UUID, user=Depends(principal)):
        return queue.get(user.owner_id, str(job_id))

    @app.get("/v2/jobs/{job_id}/events")
    def events(job_id: UUID, user=Depends(principal), after: int = Query(default=0, ge=0),
               limit: int = Query(default=50, ge=1, le=100)):
        values = queue.events(user.owner_id, str(job_id), after, limit)
        return {"items": values, "next_sequence": values[-1]["sequence"] if values else after}

    @app.post("/v2/jobs/{job_id}/cancel")
    def cancel(job_id: UUID, user=Depends(principal), key=Depends(request_key)):
        return queue.cancel(user.owner_id, str(job_id), key)

    @app.get("/v2/usage")
    def usage(user=Depends(principal), after: UUID | None = None, limit: int = Query(default=30, ge=1, le=100)):
        with engine.connect() as c:
            query = select(s.usage_reservations).where(s.usage_reservations.c.owner_id == user.owner_id)
            if after:
                query = query.where(s.usage_reservations.c.id > str(after))
            values = [dict(r) for r in c.execute(query.order_by(s.usage_reservations.c.id).limit(limit)).mappings()]
            return {"items": values, "next_cursor": values[-1]["id"] if len(values) == limit else None}

    @app.post("/v2/admin/budgets", status_code=201)
    def configure_budget(body: BudgetConfiguration, user=Depends(admin), key=Depends(request_key)):
        shape = {"operation": "budget", **body.model_dump(mode="json")}
        with transaction(engine) as c:
            cached = receipt(c, user.owner_id, key, shape)
            if cached is not None:
                return cached
            result = Budgets(engine).configure(c, **body.model_dump())
            return save_receipt(c, user.owner_id, key, shape, result)

    from trippy.catalog.api import register_routes
    register_routes(app, engine, principal, admin, request_key)
    return app
