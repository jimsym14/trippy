# Trippy: συγκεντρωτικό πλάνο για συμφωνία πριν τη μαζική υλοποίηση

> Ενεργό πλάνο 29/10/2026: [τελικές απαιτήσεις και parity](FINAL_REQUIREMENTS_AND_PARITY.md), [κοινό implementation agreement](IMPLEMENTATION_AGREEMENT_PLAN.md) και [μοναδική σειρά stages για autopilot](AUTOPILOT_STAGED_IMPLEMENTATION.md). Οι τελευταίες απαιτήσεις περιλαμβάνουν semantic prompts ανά προτίμηση, κεντρική MapKit αναζήτηση/ιδιωτική αποθήκευση pin και sourced rating snapshots μόνο `/5`. Supabase Free project δημιουργήθηκε από τον χρήστη· σύνδεση/migrations δεν επαληθεύτηκαν. Παλιά scope/status/task lists είναι ιστορικά όπου διαφέρουν· οι ειδικές λεπτομέρειες του παρόντος παραμένουν όταν συμφωνούν.

Ημερομηνία: 29 Οκτωβρίου 2026. Συγκεντρώνει τις απαιτήσεις της συνομιλίας και το συμφωνημένο implementation scope. Τα τοπικά Stages 0–2 και η βασική εισαγωγή του Stage 3 ολοκληρώθηκαν (βλ. IMPLEMENTATION_STATUS.md). Υπάρχουν 41.461 βασικές εγγραφές Βαρκελώνης και 500 preliminary shortlist, με 0 enriched records. SQLite migrations μέχρι `0003`, local catalog API/publication και fake worker είναι έτοιμα, με PostgreSQL SQL preview. Ο χρήστης δημιούργησε Supabase Free project· δεν έγινε remote migration, αλλαγή iOS client/deployed legacy bridge, paid AI run ή deployment.

## 1. Product agreement

Νεότερη κατεύθυνση selection: [SOURCE_LED_CATALOG_SELECTION.md](SOURCE_LED_CATALOG_SELECTION.md). Curated ~500 από πραγματικές recommendation sources, matching στη μεγάλη βάση και validated νέες entities, category/subtype coverage minima, χωριστό fact-checking και free-text type/on-demand requests. Αντικαθιστά την αρχική confidence/grid shortlist· δεν περιορίζει τη retrieval βάση στις 500.

Περαιτέρω διευκρίνιση: [VIDEO_SOURCE_RESEARCH.md](VIDEO_SOURCE_RESEARCH.md). Ελεγχόμενη Greek/English/both source discovery, broad city orientation → efficient query variants → permitted transcription/evidence batches → gaps, με optional coverage benchmarks αντί υποχρεωτικών αριθμητικών quotas. User notes δέχονται video links ως private inspiration. Official YouTube quota discovery μπορεί να αποφύγει paid search APIs· arbitrary public captions, TikTok/Reddit access και δωρεάν Luna inference δεν θεωρούνται εγγυημένα.

Νεότερη συμφωνία χρήστη: Barcelona target 500 curated/enriched επιλογές, **Luna μόνο**, χωρίς Sol fallback. Κύριο native UI skill [Wholiver SwiftUI Design Skill](https://github.com/Wholiver/swiftui-design-skill/blob/main/SKILL.md), με επίσημες Liquid Glass best practices και iOS 27 verification στα UI stages· βλ. UI_DESIGN_DIRECTION.md. Το Stage 2 προσθέτει τοπικό `/v2` API/worker, όχι αλλαγή στον deployed legacy bridge· πραγματική κατάσταση στο IMPLEMENTATION_STATUS.md.

Το Trippy είναι ένα customizable travel workspace που προσφέρει contextual επιλογές σε κάθε απόφαση: αξιοθέατα, φαγητό/καφές/nightlife, εκδρομές, ημέρες/ώρες, διαδρομές/μεταφορές, tickets/passes και διαμονή όταν υπάρχουν στοιχεία. Ο χρήστης επιλέγει, συγκρίνει, κλειδώνει, αλλάζει ή αναιρεί χωρίς να χάνονται οι υπόλοιπες επιλογές.

Η ίδια interaction pattern εφαρμόζεται σε όλες τις decision cards: selected/suggested option, related alternatives, comparable characteristics, evidence/check state, select/lock/unlock/undo και optional search. Πραγματικά facts (π.χ. επίσημο ωράριο/τιμή) έχουν evidence και δεν αλλάζουν για να ταιριάξουν στην προτίμηση. User estimates/assumptions παραμένουν ξεχωριστά. Επιλογή δεν συνεπάγεται booking.

Input: standard categories όπως Φαγητό, Καφές, Bars, Clubs, Αξιοθέατα, Μουσεία, Φύση, Εκδρομές, Αγορές και Events, μαζί με city/country-specific pills. Οι τοπικές επιλογές εξειδικεύουν τις standard κατηγορίες, δεν τις αντικαθιστούν. Selected preferences συνδυάζονται με budget, pace, walking/mobility, dietary constraints, must-see/avoid, ages/group needs και returning-user history. Progressively disclosed optional inputs περιορίζουν το cognitive load. Unknown παραμένει unknown, όχι σιωπηρή υπόθεση.

Στόχος: να πλησιάζει το πρώτο αποτέλεσμα τις πραγματικές προτιμήσεις του χρήστη, με διαθέσιμη επιλογή αλλαγών μέσα στο ίδιο app. Δεν εγγυόμαστε μηδενικές μετέπειτα αλλαγές όταν αλλάζουν πηγές/κρατήσεις/προτιμήσεις.

## 2. Τι είναι όντως έτοιμο σήμερα

| Κατάσταση | Στοιχείο |
|---|---|
| Υπάρχει στον κώδικα | SwiftUI iOS app, MapKit, brief/prompt generation, research import, βασικά pools/alternatives, local selections/order/likes και Azure bridge calls. |
| Υπάρχει στον κώδικα | Shared scout+synthesis helpers, structural validation/coverage report, developer dry-run χωρίς χρέωση. |
| Ρυθμισμένο τοπικά, όχι live verified σήμερα | Azure API key/endpoints και synthesis deployment fields στο `.env`. Δεν τυπώθηκαν τιμές secrets. |
| Υλοποιήθηκε τοπικά στο Stage 1 | Normalized schema, migrations, private place/decision/option/selection/lock/history και jobs/usage tables, v1/patch compatibility και private migration tooling. PostgreSQL SQL/RLS έτοιμα προς connected verification. |
| Υλοποιήθηκε τοπικά στο Stage 2 | Verified JWT/owner/admin mutation API, durable fake-provider queue/progress και budget/ledger transactions. Connected Supabase/Auth/RLS execution και πραγματικός provider εκκρεμούν. |
| Υλοποιήθηκε τοπικά στο Stage 3 | Source ingestion/identity/coverage/versioned publishing και basic catalog search: 41.461 records, 500 preliminary shortlist, ~105 MB SQLite, migration 0003. Βλ. CATALOG_STAGE_3.md. |
| Δεν έχει υλοποιηθεί ως runtime | Luna enrichment/πραγματικός research adapter, city profiles/dynamic pills, πλήρες iOS decision UI και progressive results. Connected Supabase catalog εκκρεμεί. |
| Project δημιουργήθηκε από τον χρήστη, σύνδεση εκκρεμεί | Supabase Free: `https://zsecfyracbhhvxvzgvfw.supabase.co`. Auth/region/credentials/PostGIS/schema/RLS δεν επαληθεύτηκαν remote. Το URL μόνο δεν ολοκληρώνει τη σύνδεση. |
| Περιβάλλον δοκιμών διαθέσιμο | Xcode toolchain και iOS 27.1 Simulator runtime εντοπίστηκαν. Το παλιό README που αναφέρει απουσία Xcode δεν είναι σημερινή απόδειξη. Δεν έγινε app build σε αυτό το planning turn. |

Συνεπώς: **το API/data architecture έχει συγκεκριμένη πρόταση, αλλά δεν έχουν “τακτοποιηθεί όλα” επιχειρησιακά.** Χρειάζονται provisioning, endpoint/tool audit, auth/isolation, usage measurement και pilot verification.

## 3. Stack και boundaries

| Layer | Επιλογή |
|---|---|
| iOS client | SwiftUI, MapKit, typed trip/decision models και local cached view state. |
| Backend | Python/FastAPI, Pydantic validation, versioned API contracts· σταδιακή αντικατάσταση του shared HTTP bridge. |
| DB | Supabase managed PostgreSQL + PostGIS, normalized tables, Supabase Auth, RLS και server ownership checks. |
| DB access/migrations | SQLAlchemy 2 + Alembic και Postgres driver, bounded connection pool. |
| Jobs | Postgres durable queue/leases/idempotency, ξεχωριστός worker με same Python core και persisted progress events. |
| Streaming | SSE με sequence/reconnect, bounded polling fallback στο iOS. |
| Ingestion | DuckDB για regional Overture Parquet, source-specific importers, identity/source-quality checks. Heavy initial import τοπικά ή σε κατάλληλο batch compute, όχι υποχρεωτικά σε 512 MB service. |
| AI | Provider adapter με το υπάρχον Azure deployment αρχικά· task-specific prompts, verified endpoint capabilities και measured billing. Model switch μόνο αν οι μετρήσεις το δικαιολογούν. |
| Admin | CLI/dry-run πρώτα· μικρό React/Vite admin με Supabase login, backend-authorized admin role για coverage, review/publishing και budgets. |
| Hosting | Render API + worker για online λειτουργία. Local execution για το πρώτο οικονομικό pilot. |
| Storage | Private permitted snapshots και attributed assets, source retention rules, backups. Όχι live user/catalog dumps σε public Git. |

Δεν απαιτούνται στην πρώτη έκδοση graph DB, Redis, Kubernetes ή ξεχωριστό vector service. pgvector/solver/extra workers προστίθενται όταν μετρηθεί ανάγκη. Backend service credentials δεν είναι user authorization: private queries χρησιμοποιούν verified owner identity και appropriate DB roles/RLS, ενώ trusted service operations έχουν ξεχωριστό scope.

## 4. Data model

Geography: continent → country → city → areas, με admin/metro/overlap relations όπου χρειάζεται. Canonical catalog: places, activities, venues, brands, dishes, local discovery concepts και relations. Sources/observations: field evidence, real fetch time, validity/freshness, retention, conflicts. User layer: trips, preferences, visit history, decisions, option sets, selections, bookings και overrides.

Γενίκευση του activity model: `trip_decisions` με stable ID/type/purpose/context και related `decision_option_sets`, `decision_candidates`, `decision_selections`, `selection_history`. Activity slots, transport legs, accommodation decisions και ticket/pass comparisons είναι typed kinds του ίδιου βασικού pattern, με διαφορετικά constraints/fields. Δεν επιβάλλουμε ένα άμορφο JSON για όλα: διατηρούνται typed domain records.

User lock αφορά επιλογή, ώρα ή σειρά χωριστά. AI proposals δεν υπερισχύουν νεότερων user selections. Όταν ένα selected option γίνεται unavailable, διατηρείται η user επιλογή ως conflict και προτείνονται alternatives. Provider-expired content δεν διατηρείται επειδή βρίσκεται σε selection history.

Υφιστάμενα v1 imports υποστηρίζονται από compatibility adapter. Νέο internal/v2 contract μεταφέρει stable decisions και option sets. v1 export μπορεί να δίνει selected plan projection, με σαφή περιορισμό ότι δεν κωδικοποιεί από μόνο του όλο το νέο customization state. Existing local user edits/imports μεταφέρονται με migration και backup, όχι διαγραφή.

## 5. APIs και επιλογές αναζήτησης

| Πηγή | Πρώτη φάση | Ανάγκη setup/κόστος |
|---|---|---|
| Overture Places | Regional inventory, taxonomy/brand/source IDs, monthly updates | Δεν απαιτεί πληρωμένο Places API key. Compute/download/storage έχουν πρακτικά όρια/κόστος. |
| Wikidata/Commons | Identity/context και media μόνο με πραγματική άδεια | No required paid key· public API limits/attribution ανά dataset/file. |
| Official city/venue/transit sources | Επιλεγμένοι adapters για prices/hours/exceptions/events/GTFS | Coverage και terms ανά πηγή· δεν εγγυόμαστε παγκόσμιο δωρεάν unified API. |
| Nager/official holiday sources | Country/region/date checks | Επιβεβαίωση endpoint/version και local holiday coverage. |
| MapKit | iOS map/search/route/place UI | Ήδη στο app· δεν θεωρείται general free review/inventory feed. |
| Google Maps URLs | Optional search/directions link από decision context | Χωρίς API key ή Google API call charge. Ανοίγει Google Maps/app/browser και δεν επιστρέφει structured results στο Trippy. |
| Apple Maps search | Core κεντρική αναζήτηση pin, private save και add-to-trip μετά το research | Bounded user-initiated MapKit lookup, exact match/deduplication, permitted per-field persistence και owner scope. Δεν απαιτεί νέα AI/Google Places call. |
| Google Places/UI Kit | Optional live UI enrichment, όχι mandatory core | Billing setup/free SKU caps/EEA use review πριν ενεργοποίηση. No general mirroring/prompt export. |
| Ticketmaster | Optional συμπληρωματικά events | API key, source policy, default 5 requests/sec/5.000/day· δεν είναι πλήρες calendar. |
| Azure model API | Classification/extraction/synthesis/planning | Υπάρχον configured deployment· live capability και usage audit χρειάζεται. Paid inference, caps πριν paid run. |
| Azure web search/grounding | Optional bounded user research όπου terms επιτρέπουν | Πρόσθετη χρέωση και ειδικοί output/display/work-product όροι. Δεν είναι default bulk catalog exporter. |
| Weather | Εκτός MVP | Κανένα required setup. |

[Google Maps URLs](https://developers.google.com/maps/documentation/urls/get-started) υποστηρίζουν search χωρίς API key. In-app external-search action μπορεί να συμπληρώνει τις επιλογές με βάση τη δραστηριότητα, την περιοχή και τις επιλεγμένες προτιμήσεις. User-shared link δεν είναι αυτόματη άδεια scraping/εισαγωγής Google content: κρατάμε permitted reference/user intent και ταυτοποιούμε με τη δική μας βάση ή permitted source. Δεν υπόσχεται αυτόματο return των Google results στο app.

Semantic category/pill instructions ενσωματώνονται σε κάθε personalized prompt, μαζί με το συνολικό trip context, χωρίς να αποκλείουν άλλα χρήσιμα research modules. Reviews στο προϊόν σημαίνει sourced αστέρια `/5` μόνο· permitted snapshots μπορούν να προκύπτουν από το ίδιο research χωρίς υποχρεωτική ratings API κλήση. Βλ. [τελικές λεπτομέρειες](FINAL_REQUIREMENTS_AND_PARITY.md).

### Azure audit πριν επεκταθεί το σημερινό pipeline

Η [νέα Azure Web Search documentation](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/web-search) αναφέρει χρήση Grounding with Bing και πρόσθετη χρέωση/terms. Το σημερινό configured agent/tool δεν προσδιορίζεται πλήρως από τον τοπικό Python client και το όνομα των environment fields. Δεν υποθέτουμε ότι είναι το νέο API surface ή ότι υποστηρίζει όλα τα model/cache/budget parameters.

Οι [enterprise Bing grounding terms](https://www.microsoft.com/en-us/bing/apis/grounding-legal-enterprise) επιτρέπουν περιορισμένη ενσωμάτωση σε work product υπό προϋποθέσεις, όχι γενικό database/index/crawl substitute του Output, και επιβάλλουν display/attribution/derivative restrictions. Οι γενικοί μη-enterprise όροι δεν εφαρμόζονται αυτομάτως στο Foundry. Audit στο πραγματικό resource/agreement πριν χρήση συγκεκριμένου grounding output στο proposed workflow. Η βάση χτίζεται από open datasets και independently permitted official sources, όχι από ανεξέλεγκτη αποθήκευση grounded reports.

## 6. Pipeline

### Shared city pipeline

1. Register geographic scope και permitted providers/source policies.
2. Import regional Overture/Wikidata/city data, deduplicate και validate identities.
3. Measure area/category/concept coverage και missing evidence/operational facts.
4. Generate bounded jobs μόνο για χρήσιμα gaps, με explicit budget/reservations.
5. Fetch/parse permitted sources· AI enrichment/classification πάνω σε επιτρεπόμενα evidence bundles.
6. Validate schema, claims/IDs, units, conflicts και quality. Review ambiguous merges/high-risk unsupported claims.
7. Publish versioned city profile/catalog και dynamic pills, χωρίς μεταφορά private user histories.
8. Refresh με source release/change/TTL και upcoming-demand priority.

### Personalized trip pipeline

1. Standard categories + local pills + brief/history/constraints.
2. SQL/spatial/context retrieval από shared catalog, χωρίς όλη τη βάση μέσα στο prompt.
3. Candidate pools και diverse options ανά decision/slot, με cross-slot feasibility.
4. Prioritized current checks στα proposed/visible critical options: operation, dated hours, exceptions, official tickets/transport.
5. AI proposed plan με supporting IDs, assumptions, options και alternatives. Hours/date unknowns διατηρούνται ρητά.
6. Deterministic date/opening/route/time/cost validation και bounded targeted repair.
7. Progressive UI με provisional/validated states, comparison, user locks και undo.
8. Changes προκαλούν scoped recalculation/recheck και patch γύρω από preserved user choices.

Οι hotels/flights/restaurant reservations δεν γίνονται live bookable inventory χωρίς κατάλληλο provider integration. Πρώτη φάση: user-supplied candidates/quotes, official links, decision comparisons και check state. Ticket/pass recommendations χρησιμοποιούν real known products/eligibility, όχι εφευρεμένες τιμές.

## 7. Οικονομία και responsiveness

Task budgets ανά city seed/refresh/trip/user/provider με atomic reservations και actual usage reconciliation. Output/search/retry/concurrency caps. Provider-wide token bucket και daily/monthly counters. Single-flight refresh και permissible caches αποφεύγουν duplicated fetches.

Stable taxonomy/schema/instructions prefix για supported [Azure prompt caching](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/prompt-caching), με actual hit/read/write usage measurement. Δεν θεωρούμε το cache δωρεάν, δεν προσθέτουμε αστήρικτα parameters σε old endpoints και δεν μπερδεύουμε prompt cache με permission για provider-content retention. Offline Batch μόνο όπου το συγκεκριμένο deployment/API υποστηρίζει measured discount.

First catalog options χωρίς live AI call. Events/providers έρχονται paginated. SSE job events προσθέτουν results/checks χωρίς να διαγράφουν visible user choices. Top options ελέγχονται πρώτα, υπόλοιπα lazy loading. Global rate limits δεν είναι ανά χρήστη και monthly exhaustion δεν λύνεται με slower requests. Κάθε late event έχει sequence/revision ώστε να μη μεταβάλλει νεότερο lock.

## 8. Κόστη και προτεινόμενα όρια

Snapshot από [Supabase pricing](https://supabase.com/pricing), [Render pricing](https://render.com/pricing) και [Render Free](https://render.com/docs/free), 29/10/2026. Τα amounts USD είναι infrastructure examples, όχι προσφορά SLA ή συνολική πρόβλεψη εφαρμογής. Render Hobby workspace base $0· compute ξεχωριστά. Εδώ υποθέτουμε API $7 + worker $7, χωρίς paid Render workspace tier. Δεν απαιτείται δεύτερο Render PostgreSQL επειδή η DB είναι Supabase.

| Φάση | Υποδομή / μήνα | Περιορισμοί |
|---|---:|---|
| Local single-user pilot + Supabase Free | $0 πρόσθετα | Worker/API τρέχουν στο Mac. Free DB 500 MB/pausing/egress limits. AI ξεχωριστά. |
| Online μικρό pilot: Supabase Free + API/worker μικρού μεγέθους | Περίπου $14 | Free DB bounds/pausing και περιορισμένο compute. Δεν είναι εγγύηση production capacity. |
| Αρχική παραγωγή: Supabase Pro + API/worker μικρού μεγέθους | Από περίπου $39 | $25 + $7 + $7· συν AI, providers, overages/storage/egress και όποια πρόσθετη capacity χρειαστεί. |

Το Render Free μπορεί να χρησιμοποιηθεί σε demo αλλά spins down μετά από 15 λεπτά idle και χρειάζεται περίπου ένα λεπτό να ξυπνήσει. Δεν ταιριάζει στην απαιτούμενη online εμπειρία χωρίς αναμονή ούτε σε unattended always-on worker. Local filesystem του Render δεν είναι persistent database.

Πρόταση προς συμφωνία: **αρχικό συνολικό paid AI pilot cap €10** για λίγα πραγματικά tasks και μετά configurable monthly cap, π.χ. €10 για προσωπική δοκιμή. Τα amounts είναι όρια διακοπής, όχι υπόσχεση ότι καλύπτουν ολόκληρη πόλη ή όλα τα trips. USD/EUR δεν συνδυάζονται χωρίς exchange assumptions.

Exact AI €/trip και city seed θα προκύψουν από model/deployment pricing, tokens/tool calls, extraction quality, repair rate και reuse. Δεν έχουμε usage ledger/measurements σήμερα για ακριβή πρόβλεψη. Model tokens και grounding/search είναι ξεχωριστές χρεώσεις. Για Apple App Store distribution, Developer Program συνήθως $99/year· δεν είναι Maps per-call charge. Προαιρετικό Google ενεργοποιείται μόνο με server caps/account-wide usage monitoring και fallback.

## 9. Setup που χρειάζεται ο χρήστης

| Πότε | Ενέργεια |
|---|---|
| Πριν το connected pilot | Το Supabase Free project υπάρχει· επαλήθευση της πραγματικής region/Auth και παροχή connection settings μέσω local `.env`/Render env, όχι client bundle. |
| Πριν paid AI benchmark | Επιβεβαίωση Azure project/resource, actual deployment names/models/tool και billing access. Οι υπάρχουσες τιμές παραμένουν όπου λειτουργούν· δεν ζητείται νέο OpenAI account by default. Συμφωνία pilot cap. |
| Πριν online rollout | Render API/worker services, env settings/DB connection, appropriate service plans και deploy access. Local phase δεν χρειάζεται paid hosting. |
| Πριν admin publishing | Admin user και role/MFA, auth redirect settings. Ο backend ελέγχει τον ρόλο, δεν αρκεί client flag. |
| Για physical device/TestFlight | Apple signing team/Developer Program αν απαιτείται· το Xcode και Simulator είναι διαθέσιμα εδώ. |
| Αργότερα, προαιρετικά | Ticketmaster API key, Google project/UI Kit και Apple server credentials μόνο όταν υπάρχει συγκεκριμένη ανάγκη. Δεν χρειάζονται όλα πριν ξεκινήσουμε. |

Ο agent αναλαμβάνει code/config/templates/migrations και τεχνικό έλεγχο. Account signup, paid subscription/terms και user-owned credentials διαχειρίζονται μέσω των αντίστοιχων λογαριασμών. Οι τελικές υπηρεσίες/ρυθμίσεις θα είναι συγκεκριμένες και reviewable πριν από online rollout.

## 10. Αρχική σειρά υλοποίησης (αντικαταστάθηκε από το autopilot plan)

Η ενεργή σειρά είναι αποκλειστικά το [AUTOPILOT_STAGED_IMPLEMENTATION.md](AUTOPILOT_STAGED_IMPLEMENTATION.md), με συγκεκριμένο compiler stage, central search/save stage και rating-snapshot acceptance. Ο παρακάτω αρχικός πίνακας διατηρείται ως συνοπτική ιστορική αντιστοίχιση.

| Βήμα | Παραδοτέο/verification |
|---|---|
| 0. Baseline και provider audit | Backup/import fixtures, contract inventory, existing Azure capabilities/tool terms, plan για supported APIs. Tiny paid benchmark μόνο μέσα σε agreed cap. |
| 1. Normalized model | Migrations, typed geography/catalog/observations/decisions/options/locks/user history, compatibility imports και non-destructive local migration. |
| 2. Backend/auth/jobs | FastAPI, verified ownership/admin role, persistent job state, queue/retries/usage ledger, safe endpoint replacement του shared bridge. Tests για isolation/idempotency. |
| 3. Barcelona data pilot | Regional Overture ingestion, identity filtering, permitted source registry, initial useful enrichment και measured coverage. No global bulk import. |
| 4. Personalized retrieval | Standard + local pills, visit history, scoped options ανά decision, feasibility και paginated search. |
| 5. Planner/checks | Proposed plan, real deterministic totals/routes, date checks/uncertainty και targeted repairs με budgets. |
| 6. iOS interaction overhaul | Shared decision UI pattern σε όλο το app: compare/select/lock/unlock/undo, preserved alternatives, progressive results και external search links. |
| 7. Admin/publishing | Coverage/job/source-health/cost/diff UI και version publish/rollback. |
| 8. Validation/rollout | Python integration tests, Swift model/lock tests, Simulator build και visual flows. Staged backend/client deploy με compatible fallback και backup. |

Οι αλλαγές παραδίδονται σε διαδοχικά reviewable κομμάτια του ίδιου συνολικού redesign. Δεν γίνονται όλα τα runtime/data/API changes σε ένα μη ελέγξιμο rewrite. Tests εστιάζουν σε πραγματικές invariants: ownership, stable IDs, preserved locks/options, late AI results, closed-date constraints, correct money totals και budget enforcement.

## 11. Σημεία που παραμένουν ανοιχτά πριν τον μαζικό αυτοματισμό

- Actual Azure agent/tool/deployment, applicable enterprise agreement και measured output/search costs.
- Coverage/terms των official city/venue adapters: μπορεί να παραμένουν unknown facts και manual checks.
- Google raw data χρήση για AI ranking/planning δεν έχει γενική έγκριση· optional UI/links έχουν ξεχωριστή τεκμηρίωση.
- Τα αστέρια `/5` μπορούν να κρατούν permitted research snapshots· universal free live ratings και exact booking inventory δεν είναι εγγυημένα. Δεν μπλοκάρουν το core customization/catalog app.
- Production capacity/budget sizing προκύπτουν από pilot measurements· $39 είναι starting configuration, όχι τιμή για οποιοδήποτε scale.

Προτεινόμενο αρχικό scope προς συμφωνία: **ένα Barcelona pilot, shared catalog και source evidence, standard + local preferences, options/locks σε όλο το travel workspace, MapKit central pin search/private save/add-to-trip και δωρεάν Maps links, semantic preference prompts, sourced `/5` snapshots, Azure inference με μικρό cap, optional providers αργότερα και weather εκτός MVP.**

Σχετικές εξειδικεύσεις: [Catalog/prompting/live data](CATALOG_PROMPTING_AND_LIVE_DATA_PLAN.md), [Local discovery/Google live](LOCAL_DISCOVERY_AND_GOOGLE_LIVE_INTEGRATION.md), [Activity alternatives/selection locks](ACTIVITY_OPTIONS_AND_SELECTIONS.md). Σε product scope, stack, cost assumptions και rollout order υπερισχύει αυτό το συγκεντρωτικό πλάνο.
