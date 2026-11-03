# Trippy: normalized model και Stage 1 migrations

Stage 1, 29/10/2026. Ενεργό scope: [τελικές απαιτήσεις](FINAL_REQUIREMENTS_AND_PARITY.md). Το schema και οι adapters έχουν υλοποιηθεί τοπικά· το backend/Auth/UI και η remote εφαρμογή ακολουθούν στα επόμενα stages.

## Μία δομή για κάθε τύπο state

| Layer | Πίνακες / σκοπός |
|---|---|
| Geography | `geographies`, `geography_relations`: typed continent/country/region/city/area και πρόσθετες σχέσεις. |
| Shared catalog | `entities`, aliases/relations, typed `activities`, `catalog_versions`, provider identity mappings. |
| Source policy/evidence | `source_policies`, `source_records`, `retrieval_references`, `observations`: scope, permission/version, actual observed time, validity, retention και verification. |
| Typed volatile facts | `rating_snapshots`, `opening_rules`, `opening_exceptions`, `price_observations`, `ticket_products`, `event_occurrences`, `classifications`. |
| Personal places | `user_places`, tags/references, owner, optional canonical mapping και private facts. Δεν είναι δεύτερη database. |
| Personal trip | `trips`, `trip_days`, preferences, visit history, reactions, overrides, bookings και atomic cost lines. |
| Decisions/options | `trip_decisions` → `decision_option_sets` → `decision_candidates`, με ξεχωριστά `decision_selections` και `selection_history`. `activity_slots` εξειδικεύει το activity kind, δεν δημιουργεί δεύτερο selection system. |
| Durable work foundation | `research_jobs`, `job_events`, `usage_reservations`, `usage_ledger`. Queue execution, budget transactions και API είναι Stage 2. |
| Compatibility | `research_runs`, `legacy_migration_state`, `research_extensions`: migration IDs/app-owned backup state και unsupported fields/modules. Δεν αντικαθιστούν τα relational core records. |

Το frozen schema είναι στο `trippy/data/schema_v1.py`, με 47 πίνακες. Το `schema.py` εκθέτει την τρέχουσα SQLAlchemy metadata. Released snapshots δεν αλλάζουν στις επόμενες φάσεις: νέα schema changes χρειάζονται νέα Alembic revision.

Stage 2: revision `0002`/`schema_v2.py` προσθέτει budget accounts/allocations, mutation receipts και job results (51 συνολικά). Το αρχικό snapshot παραμένει αμετάβλητο. [Backend transactions και verification](BACKEND_STAGE_2.md). Full changed-import diff παραμένει χωριστό compatibility integration· typed API mutations είναι revision-aware, ενώ changed legacy imports συνεχίζουν να απορρίπτονται με conflict.

Stage 3: revision `0003`/`schema_v3.py` προσθέτει `geography_references`, `catalog_import_runs`, `catalog_snapshots`, `catalog_identity_conflicts` (**55 tables** συνολικά). Τα `schema_v1.py`/`schema_v2.py` παραμένουν frozen. Local source inventory: 41.461 Barcelona entities/snapshots, 500 preliminary shortlist, 0 AI enriched. Hash-validated atomic import, permitted field projection, expected-version publish/rollback και catalog read API υλοποιήθηκαν· Supabase/PostgreSQL execution και Luna enrichment εκκρεμούν. [Αποτελέσματα Stage 3](CATALOG_STAGE_3.md).

Το [trippy-trip-v2 JSON Schema](../schemas/trippy-trip-v2.schema.json) περιγράφει το typed trip/import overlay: private places, canonical references, days, stable decisions, candidate references, selection ownership/locks και χωριστό app-owned state. Canonical facts ανακτώνται από το catalog αντί να αντιγράφονται σε κάθε slot.

## Referential integrity και permissions

Owner-scoped composite FKs συνδέουν trip/day/decision/options/selection/private-place/source/job/usage records. Μια επιλογή δεν μπορεί να δείξει candidate άλλης απόφασης, ούτε ένα slot σε ημέρα άλλου trip. Shared/private source scopes έχουν nonnullable `scope_key` για να μην παρακάμπτονται οι σύνθετες FKs από null owner values.

PostgreSQL revision περιλαμβάνει RLS για όλους τους νέους πίνακες. Authenticated clients διαβάζουν own data και published permitted catalog/evidence, χωρίς απευθείας write grants. Client mutations θα περνούν από verified backend transactions. Service credentials παραμένουν trusted infrastructure και δεν ισοδυναμούν με user authorization. RLS δεν έχει δοκιμαστεί ακόμη σε πραγματικό PostgreSQL/Supabase session.

Retention-expired observations και τα σχετικά typed facts αποκλείονται από το PostgreSQL read policy. Source permission/source identity και publication checks περιορίζουν τα shared reads. Physical expiry deletion/refresh jobs ακολουθούν στα provider/job stages.

Στη PostgreSQL migration το PostGIS εγκαθίσταται στο `extensions` schema αν δεν υπάρχει. Spatial indexes χρησιμοποιούν το πραγματικό schema της extension, ώστε να υποστηρίζεται και ήδη εγκατεστημένη extension σε άλλο schema. Υπάρχει GIN name-search index. PostgreSQL expression indexes διατηρούνται χωριστά από cross-dialect metadata και εξαιρούνται από accidental autogenerate drops. Η εκτέλεση χρειάζεται διαθέσιμο PostGIS και κατάλληλα migration privileges, προς connected verification.

## Εγκατάσταση και τοπική migration

```bash
uv venv --python python3 .venv
uv pip install --python .venv/bin/python -r requirements-dev.txt
.venv/bin/python -m alembic upgrade head
.venv/bin/python -m unittest discover -s tests -v
```

Default target είναι το Git-ignored `.local/catalog.sqlite`. Οι SQLite foreign keys ενεργοποιούνται σε κάθε connection. Η SQLite είναι test/pilot substrate· production target παραμένει Supabase PostgreSQL/PostGIS.

Πλήρες PostgreSQL SQL preview χωρίς credentials ή connection:

```bash
.venv/bin/python -m alembic -x dialect=postgresql upgrade head --sql
```

Connected migration απαιτεί `MIGRATION_DATABASE_URL` και ρητό `-x connected=true`, μετά από read-only inventory/backup και review του SQL. Το πρώτο migration δημιουργεί μόνο τους νέους Trippy πίνακες· αν βρει conflicting names αποτυγχάνει αντί να κάνει drop ή overwrite. Δεν αλλάζει permissions σε άλλους υπάρχοντες πίνακες.

Το initial-schema downgrade καταστρέφει δεδομένα και είναι blocked by default. Για disposable test DB μόνο υπάρχει explicit `-x allow_destructive_downgrade=true`. Για πραγματικά trips η προτεινόμενη ανάκτηση είναι verified backup restore ή corrective forward migration.

## Non-destructive legacy migration

```bash
.venv/bin/python -m trippy.migrate_legacy \
  --input /path/to/exported-library.json \
  --owner-id VERIFIED_OWNER_UUID \
  --output-dir .local/legacy-migration
```

Δέχεται native iOS trip/library exports, draft trips και standalone full `trippy-research-v1`. Standalone research χρειάζεται επιπλέον σταθερό `--trip-key`. Preview δεν ανοίγει DB ή provider clients. Γράφει ακριβές backup και normalized preview σε private files με permissions `0600`, χωρίς overwrite διαφορετικού περιεχομένου. Το πρωτότυπο δεν αλλάζει.

Με `--apply-local --database .local/catalog.sqlite` εισάγεται transactionally στην ήδη migrated SQLite. Ο importer είναι σκόπιμα local-only: remote legacy copying χρειάζεται provider-policy και verified-owner integration. Δεν προωθεί κανένα imported place/source στον κοινό catalog.

IDs είναι deterministic UUID5 ανά owner/trip/legacy record. Slots χωρίζονται από place identity. Παλιά native `place|...` schedule replacements αποκτούν σταθερό slot κατά τη migration· το intent παλαιότερου swap δεν επινοείται όταν το prototype δεν το αποθήκευε.

Η migration διατηρεί schedule order, unscheduled original slots, time/cost edits, reactions, checklist flags, budget entries, cached coordinate metadata και unsupported extensions. Δεν δημιουργεί booking από user selection. Duplicate imports είναι idempotent· changed legacy imports προκαλούν conflict αντί overwrite. Το Stage 2 πρόσθεσε revision-aware API mutations· πλήρες changed-import apply/diff παραμένει εκκρεμές compatibility integration.

Record-level citations γίνονται unverified claims. Δεν προσθέτουν πραγματικό `observed_at` ούτε αποδεικνύουν field-level evidence. Snapshot table δέχεται μόνο explicit scale 5 και valid numeric value· source/platform/time/permission verification ακολουθεί στο Stage 6. Η v1 projection δεν εμφανίζει unverified imported numeric stars ως confirmed score, αλλά διατηρεί το αρχικό claim στο v2 και το ακριβές backup.

Υπάρχοντα transport/ticket/event/overview/custom modules διατηρούνται ως compatibility extensions όπου δεν υπάρχει ακόμη typed provider conversion. Canonical reference projection χρειάζεται catalog retrieval στο backend. Το `export_research_v1` παράγει selected-plan projection· το πλήρες customization/lock state παραμένει στο v2 overlay.

## Έλεγχοι και πραγματικά όρια

Τα integration tests εφαρμόζουν migrations σε προσωρινές SQLite databases, ελέγχουν schema drift/upgrade/downgrade, cross-owner FKs, slot/candidate integrity, atomic import rollback, idempotency, preservation και private CLI backups. Generated PostgreSQL/RLS SQL και το PostGIS DO block περνούν PostgreSQL parser χωρίς δικτυακή σύνδεση.

Δεν εκτελέστηκε PostgreSQL server/PostGIS/RLS integration ή remote Supabase migration. Το πραγματικό iOS UserDefaults store δεν αλλάζει από αυτή τη φάση· export/backup και client migration integration ακολουθούν στο UI/backend rollout. Το παλιό bridge και η σημερινή διάταξη συνεχίζουν την υπάρχουσα λειτουργία τους.
