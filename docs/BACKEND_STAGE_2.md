# Stage 2: backend, auth, jobs και budgets

Τοπικό runtime και verification, 29/10/2026. Νέο FastAPI `/v2` API και SQLite fake-provider worker. Δεν άλλαξε ο παλιός bridge, ο iOS client ή deployment. Connected Supabase/PostgreSQL, πραγματικό login και Azure usage παραμένουν προς επαλήθευση.

## Εκτέλεση

```bash
.venv/bin/python -m alembic upgrade head
.venv/bin/python -m uvicorn trippy.backend.runtime:app --factory --host 127.0.0.1 --port 8766
```

Η factory διαβάζει local configuration, χρησιμοποιεί `.local/catalog.sqlite` και δεν δημιουργεί schema. Remote runtime απαιτεί `TRIPPY_BACKEND_CONNECTED=true` και `DATABASE_URL`· remote migration παραμένει ξεχωριστό explicit βήμα. Η factory δεν ενεργοποιεί Azure ή οποιονδήποτε paid adapter ακόμη και αν υπάρχουν legacy Azure credentials ή `TRIPPY_ALLOW_PAID_RESEARCH=true`.

Χωρίς network/auth credentials, πλήρες synthetic smoke σε **καινούργιο disposable αρχείο**:

```bash
.venv/bin/python -m trippy.backend.cli preview --database .local/stage2/demo.sqlite
.venv/bin/python -m trippy.backend.cli worker --database .local/stage2/demo.sqlite --once
```

Το preview αρνείται overwrite, δημιουργεί private SQLite file, εφαρμόζει migrations, synthetic owner/trip, zero-dollar fake budgets και job. Ο worker χρησιμοποιεί SQLite paths, ποτέ remote URLs. Χωρίς `--once` δουλεύει με polling 3 seconds μέχρι διακοπή. `completed` σε fake preview σημαίνει επιτυχημένο pipeline preview, όχι ολοκληρωμένο AI research ή παραγωγή των 500 places.

## Authentication και authorization

`Authorization: Bearer <Supabase user access token>`. Επαλήθευση signature μέσω σταθερού trusted project JWKS, issuer `/auth/v1`, audience `authenticated`, role, expiry/issued-at και UUID subject. ES256/RS256 μόνο· legacy HS256 project χρειάζεται χωριστή supported verification πριν συνδεθεί. Δεν χρησιμοποιείται `TRIPPY_BRIDGE_TOKEN` ως user identity.

Admin απαιτεί signed server-managed `app_metadata.trippy_role=admin` **και** `aal=aal2`. `user_metadata`, body flags και privileged service keys δεν παρέχουν user/admin identity. Επίσημες πηγές: [Supabase JWT verification](https://supabase.com/docs/guides/auth/jwts), [signing keys](https://supabase.com/docs/guides/auth/signing-keys), [claims/AAL](https://supabase.com/docs/guides/auth/jwt-fields). Το δικό μας project signing algorithm και Auth settings δεν επαληθεύτηκαν live. JWKS caching 5 λεπτών στον verifier χρειάζεται operational rotation/revocation review πριν rollout.

Το backend ελέγχει owner σε κάθε private query/transaction. PostgreSQL migrations έχουν client read-only RLS από Stage 1 και backend-only grants για τα Stage-2 tables. Η backend DB role πρέπει να έχει τα συμφωνημένα trusted rights· το URL δεν αποδεικνύει ότι υπάρχουν. Η SQLite επιβεβαιώνει app ownership/FKs, όχι πραγματική PostgreSQL RLS execution.

## API contract

Όλες οι mutations απαιτούν `Idempotency-Key` (1–128 printable characters). Ίδιο owner/key/request επιστρέφει durable receipt. Αλλαγή περιεχομένου ή operation με το ίδιο key δίνει conflict. Cross-owner resources δίνουν 404. Extra body fields απορρίπτονται, body limit 64 KiB και private responses `no-store`. Δεν εμφανίζονται original request values στα validation errors.

| Endpoint | Συμπεριφορά |
|---|---|
| `GET /health` | Liveness/version, paid adapters false· δεν αποδεικνύει DB/Auth readiness. |
| `GET/POST /v2/trips` | Owner-scoped list/cursor και idempotent draft creation. |
| `GET/PATCH /v2/trips/{id}` | Decisions/candidates/selection/days/slots· date patch με expected revision και needs-revalidation. |
| `POST /v2/trips/{id}/decisions/{id}/selection` | select/lock/unlock/undo, expected trip + decision revision, candidate membership και history. |
| `PATCH /v2/trips/{id}/decisions/{id}/slot` | Local time/duration/scheduling και χωριστά time/order locks· revision guard. |
| `POST /v2/trips/{id}/days/{id}/order` | Exact set των existing day slots, χωρίς απώλεια candidates/selection/locks. |
| `POST /v2/jobs` | Trip snapshot ή admin-only city enrichment job, bounded scope και server job cap. |
| `GET /v2/jobs/{id}` | Private status/result, χωρίς internal lease token/prompt. |
| `GET /v2/jobs/{id}/events?after=N&limit=50` | Durable monotonically sequenced events και reconnect cursor. Polling τώρα· transport SSE δεν απαιτείται για cursor correctness. |
| `POST /v2/jobs/{id}/cancel` | Fences worker writes, χωρίς υποτιθέμενη επιστροφή ήδη dispatched χρέωσης. |
| `GET /v2/usage` | Owner-scoped reservations/status/costs με bounded pagination. |
| `POST /v2/admin/budgets` | Immutable scoped period/cap configuration από verified admin. |

User changes έχουν προτεραιότητα. AI patch επιτρέπεται μόνο μέσα στο original trip/decision/candidate snapshot. Νεότερο trip/decision revision γίνεται `stale_skipped`. User-owned επιλογή παραμένει ακόμη και unlocked· AI μπορεί να δώσει suggestion. Άλλος owner/candidate ή invalid proposal ακυρώνει όλη την result transaction. Date/time/order αλλαγές σηματοδοτούν revalidation· δεν ισχυρίζονται ότι έγινε live feasibility check.

## Queue και accounting

Το Stage-1 snapshot παραμένει immutable. Revision `0002` προσθέτει τέσσερις πίνακες: `budget_accounts`, `reservation_allocations`, `mutation_receipts`, `job_results` (51 συνολικά). Current metadata στο `schema_v2.py`. Migration forward-only by default, guarded destructive downgrade.

Queue: persistent active dedup, lease token + incrementing fence, heartbeat, cancellation fence, bounded attempts/backoff/dead-letter. SQLite `BEGIN IMMEDIATE` serializes writers. PostgreSQL row locks, `SKIP LOCKED` και provider advisory lock αποτρέπουν concurrent claims πάνω από configured concurrency. Τοπικό default 1, allowed bounded range 1–20. Όλοι οι workers πρέπει να έχουν ίδιο provider concurrency configuration.

Πριν dispatch: exact Decimal worst-case token/tool cost και atomic reservation σε **όλα** τα applicable accounts. Required global + owner + job, και city για catalog jobs. Προαιρετικά trip/city και πολλαπλά daily/monthly windows εφαρμόζονται μαζί αν έχουν ρυθμιστεί. Το request μπορεί να μειώσει τον per-job cap, δεν μπορεί να ξεπεράσει το server ceiling. Runtime/fake CLI default $0· πραγματικά rate cards δεν προκύπτουν από client ή παλιά price docs.

Settlement: actual input/output/tool counts και ίδιο provider/currency. Idempotent identical reconciliation, explicit release μόνο για αποδεδειγμένα undispatched requests. Unknown outcome κρατά ολόκληρο reservation. Reconciled/released terminal state δεν ξαναχρεώνεται. Actual overrun γράφεται πλήρως και μπλοκάρει περαιτέρω reservations όπου εξαντλεί cap· δεν κρύβεται με clamp. Reservation key δεν αποτελεί άδεια δεύτερου dispatch.

Crash μετά από πιθανό dispatch ή μετά από billing reconciliation πριν result commit απαιτεί recovery, όχι αυτόματο δεύτερο provider call. Retries γίνονται μόνο για trusted `RetryableBeforeDispatch`. Το result μπορεί να χαθεί σε αυτό το crash window, αλλά ο worker αποφεύγει διπλό dispatch. Future provider-specific recovery/idempotency, request-time cancellation, rate-limit token bucket, exact provider token bounds και real billing reconciliation χρειάζονται τον provider audit πριν ενεργοποιηθεί paid adapter.

## Verification και όρια

Network-free tests χρησιμοποιούν signed synthetic RSA JWTs, δύο owners, disposable migrated SQLite databases και fake provider. Καλύπτουν isolation, admin/MFA, forged/expired tokens, receipts/concurrency, select/lock/unlock/undo, dates/slots/order, stale/foreign AI patches, leases/cancel/retries, unknown usage, budget rollback και concurrent shared-cap reservations. PostgreSQL SQL preview parsing και Alembic drift check γίνονται χωριστά· δεν αντικαθιστούν connected execution.

Δεν υλοποιούνται εδώ city importer/publishing, preference compiler, πραγματικός research adapter, iOS integration ή full changed-import diff/merge. Το υπάρχον legacy importer συνεχίζει να απορρίπτει changed imports αντί να χάνει locks· νέα typed mutations έχουν revision-aware apply. Αυτά διατηρούνται στα αντίστοιχα επόμενα stages.
