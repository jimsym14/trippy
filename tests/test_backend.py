import concurrent.futures
from datetime import timedelta, timezone
from decimal import Decimal
from pathlib import Path
import tempfile
import unittest
from uuid import uuid4

from alembic import command
from alembic.config import Config
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from fastapi.testclient import TestClient
import jwt
from sqlalchemy import insert, select, update

from trippy.data import schema_v2 as s
from trippy.data.database import make_engine, sqlite_url
from trippy.backend.api import create_app
from trippy.backend.auth import Principal, SupabaseJWTVerifier
from trippy.backend.budgets import Budgets, Limits, RateCard
from trippy.backend.common import DomainError, transaction, utcnow
from trippy.backend.contracts import NewJob, Proposal, ProviderResult, SelectionMutation
from trippy.backend.queue import Queue
from trippy.backend.worker import FakeProvider, RetryableBeforeDispatch, Worker

ROOT = Path(__file__).resolve().parents[1]
OWNER_A = "00000000-0000-4000-8000-000000000001"
OWNER_B = "00000000-0000-4000-8000-000000000002"
URL = "https://example.supabase.co"


class BackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        config = Config(str(ROOT / "alembic.ini"))
        self.url = sqlite_url(Path(self.temp.name) / "backend.sqlite")
        config.set_main_option("sqlalchemy.url", self.url)
        command.upgrade(config, "head")
        self.engine = make_engine(self.url)
        self.verifier = SupabaseJWTVerifier(URL, key_resolver=lambda token: self.key.public_key())
        self.client = TestClient(create_app(self.engine, auth=self.verifier, job_cap=Decimal("0.1")))
        self.queue = self.client.app.state.queue
        self.repo = self.client.app.state.repository
        self.budgets = Budgets(self.engine)
        self.trip_a, self.trip_b, self.decision_a, self.decision_b = [str(uuid4()) for _ in range(4)]
        self.candidates = [str(uuid4()), str(uuid4())]
        self.other_candidate = str(uuid4())
        with transaction(self.engine) as c:
            c.execute(insert(s.app_users), [{"id": OWNER_A}, {"id": OWNER_B}])
            for owner, trip, decision, candidates in ((OWNER_A, self.trip_a, self.decision_a, self.candidates),
                                                     (OWNER_B, self.trip_b, self.decision_b, [self.other_candidate])):
                c.execute(insert(s.trips).values(id=trip, owner_id=owner, destination="Barcelona"))
                c.execute(insert(s.trip_decisions).values(id=decision, owner_id=owner, trip_id=trip,
                          kind="activity", purpose="Museum", context={}))
                option_set = str(uuid4())
                c.execute(insert(s.decision_option_sets).values(id=option_set, owner_id=owner,
                          decision_id=decision, version=1, retrieval_context={}))
                for candidate in candidates:
                    place = str(uuid4())
                    c.execute(insert(s.user_places).values(id=place, owner_id=owner, name="Synthetic place"))
                    c.execute(insert(s.decision_candidates).values(id=candidate, owner_id=owner, decision_id=decision,
                              option_set_id=option_set, user_place_id=place, eligibility_status="candidate"))
                c.execute(insert(s.decision_selections).values(owner_id=owner, decision_id=decision,
                          selected_candidate_id=candidates[0]))
            now = utcnow()
            for scope in ("global", "owner:" + OWNER_A, "owner:" + OWNER_B):
                self.budgets.configure(c, scope_key=scope, provider="fake", currency="USD",
                    period_start=now-timedelta(days=1), period_end=now+timedelta(days=30), cap_amount=Decimal("1"))

    def tearDown(self):
        self.client.close()
        self.engine.dispose()
        self.temp.cleanup()

    def token(self, owner=OWNER_A, **changes):
        now = utcnow()
        claims = {"sub": owner, "iss": URL + "/auth/v1", "aud": "authenticated", "role": "authenticated",
                  "iat": now, "exp": now + timedelta(minutes=10), "app_metadata": {}, "aal": "aal1"}
        claims.update(changes)
        return jwt.encode(claims, self.key, algorithm="RS256", headers={"kid": "test-key"})

    def headers(self, owner=OWNER_A, key=None, **claims):
        headers = {"Authorization": "Bearer " + self.token(owner, **claims)}
        if key:
            headers["Idempotency-Key"] = key
        return headers

    def enqueue(self, key="job", trip=None, owner=OWNER_A):
        body = NewJob(task_type="trip_research", trip_id=trip or self.trip_a,
                      expected_trip_revision=0, budget_amount=Decimal("0.1")).model_dump(mode="json")
        return self.queue.enqueue(Principal(owner), key, body)["job_id"]

    def mutation(self, action, revision=0, trip_revision=0, candidate=None, history=None):
        return SelectionMutation(action=action, expected_revision=revision, expected_trip_revision=trip_revision,
                                 candidate_id=candidate, history_revision=history).model_dump(mode="json")

    def state(self):
        return self.repo.get_trip(OWNER_A, self.trip_a)

    def result(self, candidate=None, **usage):
        return ProviderResult(proposals=[Proposal(decision_id=self.decision_a,
            candidate_id=candidate or self.candidates[1], expected_revision=0)],
            input_tokens=usage.get("input_tokens", 100), output_tokens=usage.get("output_tokens", 100),
            tool_calls=usage.get("tool_calls", 0), summary="Synthetic result")

    def test_access_tokens_require_valid_signature_issuer_audience_role_expiry_and_uuid(self):
        for changes in ({"iss": "https://wrong.invalid/auth/v1"}, {"aud": "wrong"}, {"role": "service_role"},
                        {"exp": utcnow()-timedelta(minutes=1)}, {"sub": "not-a-uuid"}):
            response = self.client.get("/v2/trips", headers={"Authorization": "Bearer " + self.token(**changes)})
            self.assertEqual(response.status_code, 401)
        wrong = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        forged = jwt.encode(jwt.decode(self.token(), options={"verify_signature": False}), wrong,
                            algorithm="RS256", headers={"kid": "test-key"})
        self.assertEqual(self.client.get("/v2/trips", headers={"Authorization": "Bearer "+forged}).status_code, 401)
        self.assertEqual(self.client.get("/v2/trips").status_code, 401)

    def test_unsigned_and_hmac_tokens_are_rejected(self):
        claims = jwt.decode(self.token(), options={"verify_signature": False})
        for algorithm, key in (("none", None), ("HS256", "a"*64)):
            encoded = jwt.encode(claims, key, algorithm=algorithm, headers={"kid": "test-key"})
            self.assertEqual(self.client.get("/v2/trips", headers={"Authorization": "Bearer "+encoded}).status_code, 401)

    def test_supabase_es256_user_tokens_are_supported(self):
        key = ec.generate_private_key(ec.SECP256R1())
        verifier = SupabaseJWTVerifier(URL, key_resolver=lambda token: key.public_key())
        claims = jwt.decode(self.token(), options={"verify_signature": False})
        token = jwt.encode(claims, key, algorithm="ES256", headers={"kid":"ec-key"})
        self.assertEqual(verifier.verify(token).owner_id, OWNER_A)

    def test_unconfigured_auth_fails_closed_and_health_is_not_auth_evidence(self):
        with TestClient(create_app(self.engine)) as client:
            self.assertEqual(client.get("/health").status_code, 200)
            self.assertEqual(client.get("/v2/trips", headers=self.headers()).status_code, 503)

    def test_two_users_have_isolated_trip_job_and_usage_endpoints(self):
        job = self.enqueue()
        Worker(self.queue).run_once()
        self.assertEqual(self.client.get("/v2/trips", headers=self.headers(OWNER_B)).json()["items"][0]["id"], self.trip_b)
        for path in (f"/v2/trips/{self.trip_a}", f"/v2/jobs/{job}", f"/v2/jobs/{job}/events"):
            self.assertEqual(self.client.get(path, headers=self.headers(OWNER_B)).status_code, 404)
        self.assertEqual(self.client.post(f"/v2/jobs/{job}/cancel", headers=self.headers(OWNER_B, "cancel")).status_code, 404)
        self.assertEqual(self.client.get("/v2/usage", headers=self.headers(OWNER_B)).json()["items"], [])
        self.assertEqual(len(self.client.get("/v2/usage", headers=self.headers()).json()["items"]), 1)

    def test_owner_and_admin_body_flags_are_rejected_and_user_metadata_cannot_escalate(self):
        response = self.client.post("/v2/trips", headers=self.headers(key="new"), json={"destination":"B", "owner_id":OWNER_B})
        self.assertEqual(response.status_code, 422)
        now = utcnow()
        body = {"scope_key": "global", "provider": "fake", "period_start": now.isoformat(),
                "period_end": (now+timedelta(days=1)).isoformat(), "cap_amount": "1"}
        for claims in ({"user_metadata":{"trippy_role":"admin"}, "aal":"aal2"},
                       {"app_metadata":{"trippy_role":"admin"}, "aal":"aal1"}):
            self.assertEqual(self.client.post("/v2/admin/budgets", headers=self.headers(key="admin", **claims), json=body).status_code, 403)
        response = self.client.post("/v2/admin/budgets", headers=self.headers(key="real-admin",
            app_metadata={"trippy_role":"admin"}, aal="aal2"), json=body)
        self.assertEqual(response.status_code, 201)

    def test_trip_creation_is_idempotent_and_does_not_trust_client_owner(self):
        body = {"destination":"Barcelona"}
        first = self.client.post("/v2/trips", headers=self.headers(key="new"), json=body)
        second = self.client.post("/v2/trips", headers=self.headers(key="new"), json=body)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(first.json(), second.json())
        self.assertEqual(first.json()["owner_id"], OWNER_A)
        conflict = self.client.post("/v2/trips", headers=self.headers(key="new"), json={"destination":"Athens"})
        self.assertEqual(conflict.status_code, 409)

    def test_cross_owner_selection_and_foreign_candidate_cannot_mutate(self):
        for owner, candidate, status in ((OWNER_B,self.candidates[1],404), (OWNER_A,self.other_candidate,422)):
            response = self.client.post(f"/v2/trips/{self.trip_a}/decisions/{self.decision_a}/selection",
                headers=self.headers(owner,"selection"), json=self.mutation("select", candidate=candidate))
            self.assertEqual(response.status_code,status)
        self.assertEqual(self.state()["revision"],0)

    def test_select_lock_unlock_undo_preserve_candidates_and_history(self):
        requests = [self.mutation("select",candidate=self.candidates[1]), self.mutation("lock",1,1),
                    self.mutation("unlock",2,2), self.mutation("undo",3,3,history=0)]
        for index, body in enumerate(requests):
            response = self.repo.mutate_selection(OWNER_A,self.trip_a,self.decision_a,f"mutation-{index}",body)
            self.assertEqual(response["trip_revision"],index+1)
            self.assertEqual(len(response["decision"]["candidates"]),2)
        selection = self.state()["decisions"][0]["selection"]
        self.assertEqual(selection["selected_candidate_id"],self.candidates[0])
        self.assertEqual(selection["selection_owner"],"user")
        with self.engine.connect() as c:
            history = c.execute(select(s.selection_history.c.revision).where(s.selection_history.c.decision_id==self.decision_a)).scalars().all()
            self.assertEqual(sorted(history),[0,1,2,3,4])

    def test_duplicate_selection_returns_receipt_and_stale_revision_is_rejected(self):
        body=self.mutation("select",candidate=self.candidates[1])
        first=self.repo.mutate_selection(OWNER_A,self.trip_a,self.decision_a,"select",body)
        self.assertEqual(first,self.repo.mutate_selection(OWNER_A,self.trip_a,self.decision_a,"select",body))
        with self.assertRaises(DomainError) as caught:
            self.repo.mutate_selection(OWNER_A,self.trip_a,self.decision_a,"stale",body)
        self.assertEqual(caught.exception.code,"revision_conflict")

    def test_date_patch_keeps_selection_and_marks_checks_for_revalidation(self):
        response=self.repo.patch_trip(OWNER_A,self.trip_a,"dates",{"expected_revision":0,"date_mode":"fixed",
                                    "arrival_date":"2026-12-05","departure_date":"2026-12-06"})
        self.assertEqual(response["checks_status"],"needs_revalidation")
        self.assertEqual(self.state()["decisions"][0]["selection"]["selected_candidate_id"],self.candidates[0])
        invalid=self.client.patch(f"/v2/trips/{self.trip_a}",headers=self.headers(key="bad-dates"),
            json={"expected_revision":1,"departure_date":"2026-12-01"})
        self.assertEqual(invalid.status_code,422)
        self.assertEqual(self.state()["revision"],1)

    def test_jobs_deduplicate_across_keys_and_receipts_survive_completion(self):
        first=self.enqueue("one")
        second=self.enqueue("two")
        self.assertEqual(first,second)
        self.assertEqual(Worker(self.queue).run_once()["status"],"completed")
        self.assertEqual(self.enqueue("one"),first)
        self.assertNotEqual(self.enqueue("new-after-complete"),first)

    def test_job_creation_rejects_wrong_owner_stale_snapshot_and_excess_budget(self):
        for owner,body,status in ((OWNER_B,{"task_type":"trip_research","trip_id":self.trip_a,"expected_trip_revision":0},404),
            (OWNER_A,{"task_type":"trip_research","trip_id":self.trip_a,"expected_trip_revision":9},409),
            (OWNER_A,{"task_type":"trip_research","trip_id":self.trip_a,"expected_trip_revision":0,"budget_amount":"1"},422),
            (OWNER_A,{"task_type":"catalog_enrichment","city_id":str(uuid4())},403)):
            response=self.client.post("/v2/jobs",headers=self.headers(owner,str(uuid4())),json=body)
            self.assertEqual(response.status_code,status)

    def test_event_cursor_reconnect_has_ordered_nonduplicate_sequences(self):
        job=self.enqueue()
        first=self.queue.events(OWNER_A,job,0,1)
        Worker(self.queue).run_once()
        second=self.queue.events(OWNER_A,job,first[-1]["sequence"],100)
        self.assertEqual([v["sequence"] for v in first+second],[1,2,3])
        self.assertEqual(self.queue.events(OWNER_A,job,3,100),[])
        self.assertNotIn("lease_token", self.queue.get(OWNER_A,job))

    def test_late_ai_cannot_overwrite_user_lock_or_date_change(self):
        job=self.enqueue()
        _,lease=self.queue.claim()
        self.repo.mutate_selection(OWNER_A,self.trip_a,self.decision_a,"lock",self.mutation("lock"))
        self.queue.finish(lease,self.result())
        selected=self.state()["decisions"][0]["selection"]
        self.assertTrue(selected["selection_locked"])
        self.assertEqual(selected["selected_candidate_id"],self.candidates[0])
        self.assertEqual(self.queue.get(OWNER_A,job)["result"]["applied"][0]["status"],"stale_skipped")

    def test_ai_updates_suggestion_but_preserves_unlocked_user_selection(self):
        self.repo.mutate_selection(OWNER_A,self.trip_a,self.decision_a,"select",self.mutation("select",candidate=self.candidates[0]))
        body=NewJob(task_type="trip_research",trip_id=self.trip_a,expected_trip_revision=1,budget_amount=Decimal(".1")).model_dump(mode="json")
        self.queue.enqueue(Principal(OWNER_A),"job",body)
        _,lease=self.queue.claim()
        result=self.result()
        result.proposals[0].expected_revision=1
        self.queue.finish(lease,result)
        selected=self.state()["decisions"][0]["selection"]
        self.assertEqual(selected["selected_candidate_id"],self.candidates[0])
        self.assertEqual(selected["suggested_candidate_id"],self.candidates[1])

    def test_cross_owner_ai_proposals_rollback_entire_result(self):
        job=self.enqueue()
        _,lease=self.queue.claim()
        result=self.result()
        result.proposals.append(Proposal(decision_id=self.decision_b,candidate_id=self.other_candidate,expected_revision=0))
        with self.assertRaises(DomainError):
            self.queue.finish(lease,result)
        self.assertEqual(self.state()["revision"],0)
        self.assertIsNone(self.queue.get(OWNER_A,job)["result"])

    def test_expired_lease_is_reclaimed_and_old_worker_is_fenced(self):
        self.enqueue()
        _,first=self.queue.claim()
        with transaction(self.engine) as c:
            c.execute(update(s.research_jobs).where(s.research_jobs.c.id==first.job_id).values(lease_until=utcnow()-timedelta(seconds=1)))
        _,second=self.queue.claim()
        self.assertEqual(second.fence,first.fence+1)
        with self.assertRaises(DomainError):
            self.queue.finish(first,self.result())
        with self.assertRaises(DomainError):
            self.queue.heartbeat(first)
        self.queue.finish(second,self.result())

    def test_cancel_fences_worker_and_does_not_fake_refund_dispatched_usage(self):
        job=self.enqueue()
        data,lease=self.queue.claim()
        rate=RateCard(input_per_million=Decimal("1"),output_per_million=Decimal("5"),per_tool_call=Decimal(".01"))
        reservation=self.budgets.reserve(data,lease,rate,Limits(1000,1000,1))
        self.queue.cancel(OWNER_A,job,"cancel")
        with self.assertRaises(DomainError):
            self.queue.finish(lease,self.result())
        with self.engine.connect() as c:
            self.assertEqual(c.execute(select(s.usage_reservations.c.status).where(s.usage_reservations.c.id==reservation)).scalar_one(),"reserved")
        self.budgets.settle(reservation,result=self.result(),rate=rate)
        self.assertEqual(self.queue.get(OWNER_A,job)["status"],"cancelled")

    def test_atomic_cap_exhaustion_and_exact_idempotent_reconciliation(self):
        job=self.enqueue()
        data,lease=self.queue.claim()
        rate=RateCard(input_per_million=Decimal("1"),output_per_million=Decimal("5"),per_tool_call=Decimal(".01"))
        with transaction(self.engine) as c:
            c.execute(update(s.budget_accounts).where(s.budget_accounts.c.scope_key=="global").values(cap_amount=Decimal(".015")))
        with self.assertRaises(DomainError) as caught:
            self.budgets.reserve(data,lease,rate,Limits(1000,1000,1))
        self.assertEqual(caught.exception.code,"budget_exhausted")
        with self.engine.connect() as c:
            self.assertTrue(all(v==0 for v in c.execute(select(s.budget_accounts.c.held_amount)).scalars()))
        with transaction(self.engine) as c:
            c.execute(update(s.budget_accounts).where(s.budget_accounts.c.scope_key=="global").values(cap_amount=Decimal("1")))
        reservation=self.budgets.reserve(data,lease,rate,Limits(1000,1000,1))
        for _ in range(2):
            self.budgets.settle(reservation,result=self.result(),rate=rate)
        with self.engine.connect() as c:
            amount=c.execute(select(s.budget_accounts.c.spent_amount).where(s.budget_accounts.c.scope_key=="global")).scalar_one()
            self.assertEqual(amount,Decimal(".000600"))
            self.assertTrue(all(v==0 for v in c.execute(select(s.budget_accounts.c.held_amount)).scalars()))

    def test_reservation_key_never_authorizes_second_dispatch_and_unknown_holds_block_retry(self):
        self.enqueue()
        data,lease=self.queue.claim()
        rate=RateCard(per_tool_call=Decimal(".01"))
        reservation=self.budgets.reserve(data,lease,rate,Limits(0,0,1))
        with self.assertRaises(DomainError):
            self.budgets.reserve(data,lease,rate,Limits(0,0,1))
        self.budgets.settle(reservation,uncertain=True)
        with transaction(self.engine) as c:
            c.execute(update(s.research_jobs).where(s.research_jobs.c.id==lease.job_id).values(lease_until=utcnow()-timedelta(seconds=1)))
        self.assertIsNone(self.queue.claim())
        self.assertEqual(self.queue.get(OWNER_A,lease.job_id)["status"],"failed")
        with self.engine.connect() as c:
            held=c.execute(select(s.budget_accounts.c.held_amount).where(s.budget_accounts.c.scope_key=="global")).scalar_one()
            self.assertEqual(held,Decimal(".01"))

    def test_worker_retries_only_proven_undispatched_calls_and_stops_at_bound(self):
        class NotSent(FakeProvider):
            def run(self,request,heartbeat):
                self.calls+=1
                raise RetryableBeforeDispatch()
        self.enqueue()
        provider=NotSent()
        worker=Worker(self.queue,provider)
        for _ in range(3):
            worker.run_once()
            with transaction(self.engine) as c:
                c.execute(update(s.research_jobs).values(next_run_at=utcnow()-timedelta(seconds=1)))
        self.assertEqual(provider.calls,3)
        self.assertEqual(worker.run_once()["status"],"idle")
        with self.engine.connect() as c:
            self.assertEqual(c.execute(select(s.research_jobs.c.status)).scalar_one(),"dead_letter")
            self.assertEqual(set(c.execute(select(s.usage_reservations.c.status)).scalars()),{"released"})

    def test_worker_unknown_failure_keeps_reservation_and_redacts_events(self):
        class Unknown(FakeProvider):
            def run(self,request,heartbeat):
                raise RuntimeError("secret-token-from-provider")
        job=self.enqueue()
        outcome=Worker(self.queue,Unknown(),rate=RateCard(per_tool_call=Decimal(".01")),limits=Limits(0,0,1)).run_once()
        self.assertEqual(outcome["reason"],"dispatch_outcome_unknown")
        self.assertNotIn("secret-token",str(self.queue.events(OWNER_A,job,0,100)))
        with self.engine.connect() as c:
            self.assertEqual(c.execute(select(s.usage_reservations.c.status)).scalar_one(),"uncertain")

    def test_worker_records_overrun_and_rejects_result_without_hiding_spend(self):
        class TooMuch(FakeProvider):
            def run(self,request,heartbeat):
                return ProviderResult(input_tokens=0,output_tokens=0,tool_calls=2)
        job=self.enqueue()
        outcome=Worker(self.queue,TooMuch(),rate=RateCard(per_tool_call=Decimal(".01")),limits=Limits(0,0,1)).run_once()
        self.assertEqual(outcome["reason"],"provider_limit_exceeded")
        with self.engine.connect() as c:
            self.assertEqual(c.execute(select(s.usage_reservations.c.actual_amount)).scalar_one(),Decimal(".02"))
        self.assertIsNone(self.queue.get(OWNER_A,job)["result"])

    def test_missing_global_budget_and_paid_adapter_fail_closed(self):
        self.enqueue()
        with transaction(self.engine) as c:
            c.execute(update(s.budget_accounts).where(s.budget_accounts.c.scope_key=="global").values(period_end=utcnow()-timedelta(hours=1)))
        provider=FakeProvider()
        self.assertEqual(Worker(self.queue,provider).run_once()["reason"],"budget_not_configured")
        self.assertEqual(provider.calls,0)
        provider.paid=True
        with self.assertRaises(ValueError):
            Worker(self.queue,provider)

    def test_concurrent_claims_obey_provider_concurrency_limit(self):
        self.enqueue("a")
        self.enqueue("b",trip=self.trip_b,owner=OWNER_B)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            claims=list(pool.map(lambda _:self.queue.claim(),range(2)))
        self.assertEqual(sum(v is not None for v in claims),1)

    def test_concurrent_duplicate_api_requests_create_one_trip(self):
        def create(_):
            return self.repo.create_trip(OWNER_A,"concurrent-create",{"destination":"Barcelona"})
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            values=list(pool.map(create,range(2)))
        self.assertEqual(values[0],values[1])

    def test_concurrent_reservations_cannot_overspend_shared_cap(self):
        queue = Queue(self.engine, job_cap=Decimal(".1"), max_concurrency=2)
        self.enqueue("a")
        self.enqueue("b", trip=self.trip_b, owner=OWNER_B)
        claims = [queue.claim(), queue.claim()]
        with transaction(self.engine) as c:
            c.execute(update(s.budget_accounts).where(s.budget_accounts.c.scope_key == "global").values(cap_amount=Decimal(".02")))
        rate = RateCard(input_per_million=Decimal("1"), output_per_million=Decimal("5"), per_tool_call=Decimal(".01"))
        def reserve(claim):
            try:
                return self.budgets.reserve(claim[0], claim[1], rate, Limits(1000,1000,1))
            except DomainError as error:
                return error.code
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(reserve, claims))
        self.assertEqual(outcomes.count("budget_exhausted"), 1)
        with self.engine.connect() as c:
            self.assertEqual(c.execute(select(s.budget_accounts.c.held_amount).where(s.budget_accounts.c.scope_key == "global")).scalar_one(),Decimal(".016"))

    def test_budget_periods_normalize_offsets_before_sqlite_storage(self):
        start = utcnow().astimezone(timezone(timedelta(hours=2)))
        with transaction(self.engine) as c:
            first = self.budgets.configure(c, scope_key="city:"+str(uuid4()), provider="fake", currency="USD",
                period_start=start, period_end=start+timedelta(days=1), cap_amount=Decimal("1"))
            second = self.budgets.configure(c, scope_key=first["scope_key"], provider="fake", currency="USD",
                period_start=start.astimezone(timezone.utc), period_end=(start+timedelta(days=1)).astimezone(timezone.utc),
                cap_amount=Decimal("1"))
            self.assertEqual(first["id"],second["id"])

    def test_crash_after_billing_reconciliation_cannot_dispatch_again(self):
        self.enqueue()
        job, lease = self.queue.claim()
        reservation = self.budgets.reserve(job, lease, RateCard(), Limits())
        self.budgets.settle(reservation, result=self.result(), rate=RateCard())
        with transaction(self.engine) as c:
            c.execute(update(s.research_jobs).where(s.research_jobs.c.id == lease.job_id).values(lease_until=utcnow()-timedelta(seconds=1)))
        self.assertIsNone(self.queue.claim())
        self.assertEqual(self.queue.get(OWNER_A, lease.job_id)["status"], "failed")

    def test_slot_time_and_order_mutations_preserve_selection_and_fence_ai(self):
        day_id = str(uuid4())
        with transaction(self.engine) as c:
            c.execute(insert(s.trip_days).values(id=day_id, owner_id=OWNER_A, trip_id=self.trip_a, day_number=1))
            c.execute(insert(s.activity_slots).values(decision_id=self.decision_a, owner_id=OWNER_A,
                      trip_id=self.trip_a, day_id=day_id, position=0))
        self.enqueue()
        _, lease = self.queue.claim()
        response = self.client.patch(f"/v2/trips/{self.trip_a}/decisions/{self.decision_a}/slot",
            headers=self.headers(key="slot"), json={"expected_revision":0, "expected_trip_revision":0,
            "starts_at":"10:30:00", "time_locked":True, "order_locked":True})
        self.assertEqual(response.status_code,200)
        self.assertTrue(response.json()["slot"]["time_locked"])
        self.queue.finish(lease,self.result())
        state=self.state()["decisions"][0]
        self.assertEqual(state["selection"]["selected_candidate_id"],self.candidates[0])
        self.assertEqual(str(state["slot"]["starts_at"]),"10:30:00")
        order=self.client.post(f"/v2/trips/{self.trip_a}/days/{day_id}/order",headers=self.headers(key="order"),
            json={"expected_trip_revision":1,"decision_ids":[self.decision_a]})
        self.assertEqual(order.status_code,200)
        bad=self.client.post(f"/v2/trips/{self.trip_a}/days/{day_id}/order",headers=self.headers(key="bad-order"),
            json={"expected_trip_revision":2,"decision_ids":[self.other_candidate]})
        self.assertEqual(bad.status_code,422)
        self.assertEqual(self.state()["revision"],2)

    def test_request_size_pagination_and_validation_errors_are_bounded(self):
        response=self.client.post("/v2/trips",headers=self.headers(key="large"),json={"destination":"x"*70000})
        self.assertEqual(response.status_code,413)
        response=self.client.get("/v2/trips?limit=1000",headers=self.headers())
        self.assertEqual(response.status_code,422)
        response=self.client.post("/v2/trips",headers=self.headers(key="secret"),json={"destination": "Barcelona", "secret": "must-not-echo"})
        self.assertEqual(response.status_code,422)
        self.assertNotIn("must-not-echo",response.text)


if __name__ == "__main__":
    unittest.main()
