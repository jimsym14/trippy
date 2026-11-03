# Trippy: υλοποίηση σε autopilot και ελεγχόμενα στάδια

Ημερομηνία: 29/10/2026. Ο χρήστης εννοεί αυτόνομη υλοποίηση από τον agent, όχι μεταφορά σε Copilot. Ενεργή σειρά εργασίας σε διαδοχικά reviewable stages, χωρίς επαναλαμβανόμενη επιβεβαίωση για routine local work. Τα Stages 0–2 και η βασική εισαγωγή του Stage 3 υλοποιήθηκαν τοπικά· Luna enrichment εκκρεμεί. Αποτελέσματα στο IMPLEMENTATION_STATUS.md και CATALOG_STAGE_3.md.

Διάβασε πρώτα [FINAL_REQUIREMENTS_AND_PARITY.md](FINAL_REQUIREMENTS_AND_PARITY.md), έπειτα [IMPLEMENTATION_AGREEMENT_PLAN.md](IMPLEMENTATION_AGREEMENT_PLAN.md). Χρησιμοποίησε τις υπόλοιπες specifications για λεπτομέρειες. Παλιές task lists δεν καθορίζουν διαφορετικό scope/order. Supabase Free project υπάρχει· remote configuration παραμένει προς επαλήθευση. Για κάθε UI flow διάβασε το UI_DESIGN_DIRECTION.md, το Wholiver SwiftUI Design Skill/σχετικά references και συμπληρωματικά frontend-design, μαζί με επίσημα Liquid Glass docs και iOS 27 availability/build checks.

## Κοινές οδηγίες για κάθε stage

Πριν από το Stage 2: [catalog cost estimate](CATALOG_GENERATION_COST_ESTIMATE.md). Πρόκειται για reference scenarios, όχι Azure quote ή authorization για paid generation. **Νεότερη απόφαση: Barcelona 500 curated/enriched επιλογές, Luna μόνο, χωρίς Sol fallback.** UI stages χρησιμοποιούν το Wholiver SwiftUI Design Skill μαζί με επίσημη Liquid Glass τεκμηρίωση/iOS 27 checks και frontend-design ως συμπληρωματικό critique.

- Ένα stage κάθε φορά, με συγκεκριμένο diff, appropriate checks, αποτέλεσμα και επόμενο dependency. Routine local reversible work συνεχίζεται μέσα στο stage χωρίς επαναλαμβανόμενες επιβεβαιώσεις.
- Προστάτευσε υπάρχουσες αλλαγές, private data/imports και selections. Μην κάνεις reset/διαγραφή για να καθαρίσεις το workspace. Secrets και πραγματικά user/catalog dumps δεν μπαίνουν σε Git.
- Κράτησε το manual import και το v1 compatibility όσο μεταβαίνει το backend/client. Προσάρμοσε δομές πριν αφαιρέσεις παλιά code paths.
- Code/migrations/configuration γίνονται reviewable τοπικά πριν από remote application. Μην εκτελέσεις paid AI/search/provider run, paid subscription ή deployment από αυτή την οδηγία. Τέτοιες ενέργειες χρειάζονται το συγκεκριμένο setup/cap και την ισχύουσα authorization.
- Tests για πραγματικές invariants και απαιτούμενα checks. Μην κάνεις paid calls μέσα σε tests. Σε έλλειψη credential συνέχισε offline implementation· ανέφερε χωριστά ό,τι δεν επαληθεύτηκε live.
- Στο τέλος ενημέρωσε πραγματικό implementation status, verification και limitations. Plan document δεν αποτελεί απόδειξη υλοποίησης.

## Στάδια και acceptance gates

Latest execution 30/10/2026: official creator discovery now includes eight editable verified channel defaults and statistics snapshots. Barcelona multipart episodes were found; local audio acquisition completed and CPU transcription is complete, with 24/24 receipt-audited video transcripts and 43 prepared extraction chunks. Structured extraction, exact evidence validation, review drafts, a Luna-only budget gate and read-only Overture proposals are implemented. Live paid extraction, final curation, app schema/data/PostGIS and real login/RLS remain pending. No remote writes or paid calls. IMPLEMENTATION_STATUS.md and TRANSCRIPT_EXTRACTION.md supersede older snapshots.

| Stage | Παραδοτέο | Gate πριν το επόμενο stage |
|---|---|---|
| 0 — Baseline/config/provider audit — local complete | Καταγραφή κώδικα/contracts/local changes, non-destructive backup plan, offline fixtures, env template/validation, Supabase connection guide, πρώτη frontend-design pass, Apple per-field persistence policy και actual Azure capabilities/usage audit plan. | Existing Python checks και prompt dry-run χωρίς δίκτυο/χρέωση· σαφής λίστα verified/unverified setup. Καμία remote migration ή paid benchmark. |
| 1 — Ενιαίο model και migrations — local complete | Geography, canonical entities/typed facts, sources/observations/rating snapshots, owner-scoped private places, decisions/options/locks/history, preferences/template registry, jobs/usage schema. v1/patch compatibility και local user-data migration. | Ένα schema/naming, foreign keys/unique IDs, non-destructive migration/rollback strategy, private data boundaries. Local migration checks· remote apply ξεχωριστό connected βήμα. |
| 2 — Backend/Auth/jobs — local complete | FastAPI repositories/routes, verified owner/admin identity, RLS/ownership, durable queue/leases/fencing, progress events, idempotency και usage reservations/reconciliation. | Isolation δύο χρηστών, unauthorized catalog writes blocked, duplicate jobs deduped, retries/late worker writes safe, budget cap enforcement με fake providers. Connected PostgreSQL/Auth verification εκκρεμεί χωριστά. |
| 3 — Barcelona catalog — basic local complete, enrichment pending | Regional Overture + Wikidata geography: 41.461 basic records, 500 preliminary shortlist, 0 enriched. Local identity/coverage/publishing και basic name/spatial search έτοιμα. Target 500 curated/enriched, Luna only. | Basic import verified: 89 tests, migration 0003, ~105 MB SQLite, no private content in shared publish. Source/evidence review, actual Luna adapter/caps και connected Supabase size/Auth checks εκκρεμούν· παραμένουμε στο Stage 3. |
| 4 — Preferences και κοινός compiler | Standard categories + dynamic local pills/history, versioned semantic instructions με full trip context, shared backend/manual/dry-run generation και scoped retrieval/pagination. | Φαγητό+Καφές+Αξιοθέατα παράγουν συγκεκριμένες οδηγίες και διατηρούν όλα τα modules· local pill περιορίζει το σωστό context· unknown intent visible· κοινές versions και preserved user constraints. |
| 5 — Central MapKit search/save | Common search sheet/service, catalog-first + Apple pin search, selected match, private save/reference, add to trip/slot, duplicates/ambiguity handling. External Maps links επίσης. | Μετά research βρίσκεις νέο μέρος, το σώζεις ιδιωτικά και το βάζεις στο πλάνο χωρίς AI/Google paid call· existing entity reused· unrelated selections διατηρούνται· persisted fields ακολουθούν stage-0 source policy. |
| 6 — Planner/checks/rating snapshots | Bounded candidate retrieval, dated operational checks, typed `/5` snapshots από permitted research, deterministic routes/time/cost checks, targeted patches/repairs. | Closed-date conflicts, unknown handling, source/time metadata, no fake/live ratings ή text-review work, correct money totals, locks preserved και fake-provider budgets enforced. Paid pilot χωριστό αφού εγκριθεί συγκεκριμένο cap. |
| 7 — iOS workspace και progressive results | Shared compare/select/lock/unlock/undo UI για activities/transport/tickets/stay, stable options, reconnect/sequence-safe progress, source details και local cache/migration. Συνδέει την ήδη έτοιμη map search flow. Frontend-design skill: αμφισβήτηση/reimagine κάθε οθόνης, περίπου ίδιο layout, minimal clean components/alignment, χωρίς emoji/AI chrome, screenshot critique. | Α→Β→Α κρατά options, late AI response δεν υπερισχύει user lock, reconnect χωρίς duplicate effects, date change revalidation, old trips/imports preserved. Simulator build και visual flow checks. |
| 8 — Admin και rollout | Admin coverage/source health/diffs/costs, version publish/rollback, final integration verification και concrete deployment configuration. | Reviewable local artifacts, auth/admin checks, backups/restore approach, real capacity/cost measurements όπου έγιναν. Remote deployment και paid services μόνο με authorization για το συγκεκριμένο rollout. |

Νεότερα Stage 3/4 gates: [source-led selection](SOURCE_LED_CATALOG_SELECTION.md) με πραγματικές lists/articles/videos/social recommendations, identity matching, category/common-subtype coverage minima και ανεξάρτητο fact-checking. Η υπάρχουσα technical shortlist δεν εγκρίνεται για generation· revised ~500 source-backed manifest προηγείται pilot. Stage 4 προσθέτει free-text type με preserved intent και catalog-first/on-demand retrieval, χωρίς καθολικό αποκλεισμό practical venues ή υπόσχεση κάλυψης κάθε niche.

Περαιτέρω Stage 3/4 direction: [video-source research](VIDEO_SOURCE_RESEARCH.md), broad orientation και source/evidence coverage αντί mandatory venue quotas. Local 17-topic Greek/English planner, official YouTube discovery, audio download, and CPU ASR are implemented; the 20-video transcript batch finished with 19 structurally emitted evidence files and one failed item; quality flags remain under review. Current candidate selection used relevance only, has no video-statistics ranking, and omits the named creator seeds. Transcript-to-place extraction, evidence-grounded Overture matching, source-quality scoring, and review remain pending. Stage 4/7 retain editable language/channel presets and user video links/notes with owner-scoped evidence and processing preview. Free-only discovery does not enable paid fallback.

Concrete current execution order: [SOURCE_RESEARCH_NEXT_STEPS.md](SOURCE_RESEARCH_NEXT_STEPS.md): small broad discovery → permitted content pilot → real place/evidence pilot → coverage expansion. Four-query Greek/English pilot profile ready, capped at 20 candidates. Source CLI supports safe existing `.env` key loading. YouTube key, actual content access and paid extraction caps remain the corresponding live dependencies; do not skip to bulk generation.

Για connected verification χρησιμοποίησε το project `https://zsecfyracbhhvxvzgvfw.supabase.co`, αφού δοθούν τα απαραίτητα local backend/auth settings. Μην συμπεράνεις region, key, DB password ή υπάρχον schema από το URL.

## Αρχικό Stage 0 brief (ιστορικό, εκτελέστηκε τοπικά)

```text
Αρχική εντολή που εκτελέστηκε στο Stage 0, πριν δοθεί η συνέχεια για Stage 1:
Εργάζεσαι στο repository Trippy. Εκτέλεσε ΜΟΝΟ το Stage 0 από
docs/AUTOPILOT_STAGED_IMPLEMENTATION.md. Διάβασε πρώτα
docs/FINAL_REQUIREMENTS_AND_PARITY.md και docs/IMPLEMENTATION_AGREEMENT_PLAN.md.

Κατάγραψε το υπάρχον SwiftUI/Python implementation και contracts, προστάτευσε
όλες τις υφιστάμενες αλλαγές/imports/user state, ετοίμασε non-destructive
baseline/backup strategy και συνθετικά offline fixtures όπου χρειάζονται.
Προετοίμασε configuration template/validation και connection instructions
για το Supabase Free project https://zsecfyracbhhvxvzgvfw.supabase.co χωρίς
secrets. Κατάγραψε Apple MapKit available fields και applicable persistence
policy ανά field, καθώς και τι χρειάζεται για audit του πραγματικού Azure
deployment/tool και cost upper bounds. Unknown capabilities μένουν unknown.

Τρέξε τα υπάρχοντα appropriate Python checks και developer prompt dry-run
χωρίς paid/network provider calls. Αν είναι εφικτό κάνε baseline iOS build
και κατέγραψε το πραγματικό αποτέλεσμα. Μην αλλάξεις το product flow ή
ξεκινήσεις το Stage 1. Μην κάνεις remote migrations/deployment, paid calls,
subscriptions, destructive reset ή commit/push από αυτή την εντολή.

Παράδωσε συγκεκριμένο diff, checks/results, verified/unverified setup και
dependencies για Stage 1. Τα semantic preference prompts, central pin
search/save και sourced /5 rating snapshots είναι συμφωνημένες απαιτήσεις
προς υλοποίηση στα αντίστοιχα stages, όχι σημερινές implemented δυνατότητες.
```
