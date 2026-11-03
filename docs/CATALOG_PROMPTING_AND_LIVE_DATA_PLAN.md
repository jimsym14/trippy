# Trippy: μεγάλη βάση πόλεων, οικονομικό prompting και επίκαιρα δεδομένα

> Ενεργό πλάνο 29/10/2026: [τελικές απαιτήσεις και parity](FINAL_REQUIREMENTS_AND_PARITY.md), [κοινό implementation agreement](IMPLEMENTATION_AGREEMENT_PLAN.md) και [μοναδική σειρά stages για autopilot](AUTOPILOT_STAGED_IMPLEMENTATION.md). Οι τελευταίες απαιτήσεις περιλαμβάνουν semantic prompts ανά προτίμηση, κεντρική MapKit αναζήτηση/ιδιωτική αποθήκευση pin και sourced rating snapshots μόνο `/5`. Supabase Free project δημιουργήθηκε από τον χρήστη· read-only DB/Auth health επαληθεύτηκαν, remote app migrations παραμένουν εκκρεμή. Παλιά scope/status/task lists είναι ιστορικά όπου διαφέρουν· οι ειδικές λεπτομέρειες του παρόντος παραμένουν όταν συμφωνούν.

Αρχικός έλεγχος κώδικα και επίσημων πηγών: 28 Οκτωβρίου 2026. Συμπληρώνει το `DESTINATION_DATABASE_REDESIGN.md` με αποφάσεις για ingestion, scheduler, live providers και κόστος. Status 29/10/2026: basic ingestion/identity/coverage/versioned publication και catalog API υλοποιήθηκαν τοπικά στο [Stage 3](CATALOG_STAGE_3.md): 41.461 source records, 500 preliminary shortlist, 0 enriched. Scheduler/compiler/live enrichment παραμένουν specification. Δεν έγιναν χρεώσιμες AI κλήσεις, remote provisioning ή deployment.

Αναθεώρηση 29/10/2026: [LOCAL_DISCOVERY_AND_GOOGLE_LIVE_INTEGRATION.md](LOCAL_DISCOVERY_AND_GOOGLE_LIVE_INTEGRATION.md) προσθέτει geographic hierarchy, local discovery inputs, visit history, on-demand Google/UI Kit με συγκεκριμένα free caps/EEA uses και progressive jobs. Σε αυτά τα θέματα υπερισχύει η αναθεώρηση. Ο καιρός αφαιρείται από το MVP.

## Προτεινόμενη απόφαση

Νεότερη απόφαση για επιλογή και κάλυψη: [SOURCE_LED_CATALOG_SELECTION.md](SOURCE_LED_CATALOG_SELECTION.md). Οι initial curated candidates προέρχονται από πραγματικές recommendation lists/articles/videos/social sources, όχι model memory ή closed selection μόνο από Overture. Category/common-subtype minima οδηγούν τη σύνθεση· niche intents και free-text types εξυπηρετούνται catalog-first/on demand. Source recommendations δεν αντικαθιστούν authoritative fact checking.

Latest video-source status: initial Greek/English YouTube metadata discovery produced 20 raw candidates (relevance order only; no popularity statistics), all 20 audio files were downloaded, and the CPU transcription batch completed with 19 structural evidence files and one failed transcript; quality issues are recorded in its review audit. The candidate list is not quality-approved. Overture/Wikidata basic inventory is already imported, but transcript-to-place extraction, evidence-grounded deduplication against that inventory, and model enrichment have not run. See [VIDEO_SOURCE_RESEARCH.md](VIDEO_SOURCE_RESEARCH.md) and its extraction contract.

Διατηρούμε μεγάλο κοινό catalog ανά πόλη. Το γεμίζουμε πρώτα από επιτρεπόμενα structured datasets και μετά χρησιμοποιούμε AI για κενά, κατηγοριοποίηση, σχέσεις, χρήσιμη περιγραφή και planning. Ξεχωρίζουμε canonical entities, observations με χρονική ισχύ, ανακτήσιμες πηγές και προσωπικά ταξίδια. Το πλήθος prompts προκύπτει από πραγματικά κενά και διαθέσιμο budget, όχι από σταθερό αριθμό επαναλήψεων.

Δεν υπάρχει τεκμηριωμένη δωρεάν καθολική πηγή που να εγγυάται πλήρη και επίκαιρα reviews, ακριβείς τιμές, events και διαθεσιμότητα όλων των επιχειρήσεων. Deterministic retrieval σημαίνει επαναλήψιμη διαδικασία πάνω σε συγκεκριμένη πηγή/έκδοση· δεν κάνει αληθή, πλήρη ή συνεχώς διαθέσιμα τα δεδομένα της πηγής.

## Σημερινός κώδικας και πραγματικό κενό

- `research_pipeline.py`: ένα μεγάλο scout prompt, synthesis prompt, δομικό audit και derived maps.
- `run_research.py`: preview χωρίς χρέωση· με `--execute`, ένα Foundry research request και ένα Azure synthesis request.
- `bridge_server.py`: ίδιο pipeline, κοινή in-memory κατάσταση και τοπικό JSON output. Χρειάζεται owner-scoped persistent jobs πριν από πολυχρηστική εφαρμογή.
- `research_contract.json`: trip export. Στα `places` αναμειγνύει ταυτότητα, τιμή, rating και travel-date status, με provenance κυρίως σε επίπεδο record. Δεν είναι normalized catalog schema ούτε πλήρες JSON Schema validation.
- Το παρακάτω script audit είναι baseline snapshot. Τα Stages 1/2 πλέον έχουν local migrations και νέο authenticated API/fake worker/budget ledger· βλ. IMPLEMENTATION_STATUS.md. Catalog importers και τοπικό βασικό inventory υπάρχουν. Transcript extraction έχει strict validator, read-only Overture proposals και gated Luna provider (TRANSCRIPT_EXTRACTION.md). Live paid verification και scheduler/freshness integration εκκρεμούν. Το legacy script δεν απέκτησε τα budget safeguards του νέου backend.

Το export v1 μπορεί να παραμείνει συμβατό με το iOS prototype: backend projection από τους νέους πίνακες προς το παλιό JSON. Δεν χρησιμοποιούμε το export ως primary storage. Μελλοντικό v2 προσθέτει observation IDs, field evidence και freshness χωρίς να σπάει σιωπηρά παλιά imports.

## Τέσσερα διακριτά επίπεδα δεδομένων

| Επίπεδο | Περιεχόμενο | Συμπεριφορά |
|---|---|---|
| Catalog | Ταυτότητα, aliases, κατηγορία, θέση, γειτονιά, κοντινές εκδρομές, provider IDs | Κοινό, reusable, versioned. Ακόμη και αυτά μπορούν να αλλάξουν. |
| Observations | Ωράρια, menu/ticket prices, platform rating/count, business status, events, ημερήσιες εξαιρέσεις | Πηγή, actual retrieval time, validity, freshness και retention policy ανά πεδίο. |
| Retrieval references | Official page, API endpoint και lookup ID, feed, parser, permitted fields, refresh policy | Μόνιμη δυνατότητα επανελέγχου όπου επιτρέπεται· ένα URL μόνο δεν αρκεί. |
| Trip/user overlay | Dates, travelers, preferences, selected stops, bookings, user edits, assumptions | Προσωπικά δεδομένα, owner-scoped. Catalog refresh δεν τα αντικαθιστά. |

Ένα restaurant είναι catalog entity. Το rating του είναι observation μιας συγκεκριμένης πλατφόρμας. Η τιμή ενός menu έχει currency, basis, inclusion/exclusion και ημερομηνία. Ένα event συνδέεται με μόνιμο venue αλλά έχει δικές του occurrences, dates, status και λήξη. Η κράτηση ανήκει στο ταξίδι του χρήστη.

Η διατροφική/προσβασιμότητας πληροφορία χρειάζεται evidence. Το AI fit score είναι editorial estimate με supporting claim IDs, διαφορετικό από επίσημο κανόνα ή επιβεβαίωση ασφάλειας.

### Ελάχιστοι πίνακες και indexes

| Πίνακες | Χρήση |
|---|---|
| `destinations`, `areas`, `entities`, `entity_relations` | Canonical γεωγραφία, places/activities και σύνδεση εκδρομών με πολλαπλές πόλεις. |
| `provider_entities` | `(provider, external_id)` unique, mapping σε canonical entity, match evidence/status, dataset release. |
| `source_registry`, `retrieval_refs`, `fetch_runs` | Policies, lookup/endpoint/parser version, actual fetch status/time. Τα raw responses αποθηκεύονται μόνο όπου επιτρέπεται. |
| `observations`, `observation_evidence` | Field value/unit/basis, evidence, temporal validity, observed time, expiry, conflict/version. |
| `opening_rules`, `opening_exceptions`, `ticket_products`, `price_observations` | Typed συχνά ερωτώμενα δεδομένα και ημερομηνιακές εξαιρέσεις. |
| `events`, `event_occurrences` | Ένα event/series και συγκεκριμένες εμφανίσεις/ακυρώσεις. |
| `classifications`, `coverage_cells`, `catalog_versions` | AI/editorial annotations, measured gaps, publishing/versioning. |
| `research_jobs`, `job_attempts`, `usage_ledger` | Durable queue, leases, retry history, κόστος που δεσμεύτηκε/μετρήθηκε. |
| `trips`, `trip_preferences`, `trip_stops`, `bookings`, `user_overrides` | Private user state και σχέσεις με catalog. |

Στο observation κρατάμε τουλάχιστον `entity_id`, `field_key`, `value`, `unit/basis`, `source_id`, `fetch_run_id`, `observed_at`, `valid_from`, `valid_until`, `refresh_after`, `retention_until`, `verification_status` και `supersedes_id`. Το `checked_at` γράφεται από πραγματικό fetch, όχι από το μοντέλο. Το freshness υπολογίζεται από χρόνο/policy· η επιβεβαίωση από evidence. Δεν συγχέουμε «παλιό» με «λάθος» ούτε «φρέσκο» με «επιβεβαιωμένο».

Indexes: destination/category/publication status, PostGIS spatial index, full-text name/aliases, entity+field+observed time, entity+local date, event date window, job status+next_run_at και unique job deduplication key. Συχνά φίλτρα έχουν typed columns/tables· JSONB εξυπηρετεί source-specific extensions, χωρίς να κρύβει όλα τα δεδομένα σε ένα blob.

Entity resolution: external ID πρώτα, μετά official domain/address/coordinates/local aliases. Όνομα ή embedding μόνο δεν αποδεικνύει ταύτιση. Αβέβαια merges πάνε σε review, ιδίως αλυσίδες με πολλά branches.

## Πηγές και εργαλεία

Οι παρακάτω πηγές ανοίχτηκαν και διαβάστηκαν. Τα limits είναι snapshots, όχι συμβατική εγγύηση για κάθε λογαριασμό ή μελλοντική χρήση.

| Ανάγκη | Προτεινόμενη επιλογή | Όριο και πρακτική απόφαση |
|---|---|---|
| Μεγάλο initial place inventory | [Overture Maps Places](https://docs.overturemaps.org/guides/places/) | Open dataset με IDs, categories, geometry και source metadata, monthly releases. Το συγκεκριμένο Places theme περιγράφεται με CDLA Permissive/Apache και source-specific licensing. Δεν μεταφέρουμε αυτόματα την ίδια άδεια σε άλλα themes. Δεν δίνει καθολικά live reviews/τιμές/λειτουργία. |
| Ανάγνωση regional Parquet | [DuckDB](https://duckdb.org/docs/2.0/data/parquet/overview.html) | Τοπικό ingestion/filtering, import μόνο της ζητούμενης περιοχής. Δεν χρειάζεται να φορτώσουμε παγκόσμιο dataset στη μικρή app DB. Compute/download/storage μπορεί να κοστίζουν. |
| Γενική γνώση και identifiers | [Wikidata](https://www.wikidata.org/wiki/Wikidata:Data_access) | Structured data CC0, API/query limits. Batch/cache permitted results, όχι public SPARQL ανά user interaction. Commons media έχουν δική τους άδεια ανά αρχείο. |
| Χαρτογραφικά features και διαδρομές | [OpenStreetMap](https://www.openstreetmap.org/copyright) | ODbL/attribution και obligations για derived databases. Διατηρούμε provenance και αξιολογούμε licensing πριν συγχωνεύσουμε προς αναδιανομή. Public endpoints/tiles δεν είναι δωρεάν production infrastructure. |
| Geocoding prototype | [Nominatim policy](https://operations.osmfoundation.org/policies/nominatim/) | Public instance: maximum 1 request/sec, restrictions σε bulk/systematic queries, client autocomplete απαγορεύεται. Προτιμούμε source coordinates, MapKit για iOS interactions όπου επιτρέπεται, και replaceable geocoder provider σε scale. |
| Αργίες | [Nager holiday API](https://date.nager.at/api) και επίσημες περιφερειακές/δημοτικές πηγές | Η σημερινή σελίδα τεκμηριώνει v4 με country/year και subdivision metadata. Επιβεβαιώνουμε πραγματική coverage/terms πριν integration. Αργία δεν αποδεικνύει κλείσιμο venue. |
| Μεταφορές | Επίσημα [GTFS Schedule / Realtime](https://gtfs.org/documentation/overview/) feeds | Schedule και service exceptions ξεχωριστά από realtime. Το standard δεν δίνει από μόνο του παγκόσμιο feed/API, άδεια ή πλήρεις fares. Coverage ανά authority/city. |
| Events | Δημοτικό open data, official venue feeds, [Ticketmaster Discovery](https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/) | Τεκμηριωμένο default 5.000 calls/day και 5 requests/sec· deep paging περιορισμένο στα πρώτα 1.000 items. Discovery subset, όχι πλήρες ημερολόγιο ούτε εγγύηση live inventory. Terms/retention ελέγχονται πριν storage. |
| Ωράρια/τιμές | Official structured APIs, feeds, JSON-LD όπου υπάρχει, source-specific adapters | Αν δεν υπάρχει structured endpoint, permitted HTML parsing με monitored parser. Δεν εγγυόμαστε καθολικό extraction. AI extraction είναι fallback proposal με evidence, όχι deterministic verification. |
| Αστέρια `/5` | Permitted snapshot από το ίδιο AI research, αλλιώς source link/unknown· licensed live provider optional | Συγκεκριμένο venue, platform/source και πραγματικό observed time. Δεν απαιτείται text review ή νέα ratings API κλήση. Δεν βρέθηκε universal free live feed· source/grounding terms παραμένουν. |
| Optional Google Places | [Policies](https://developers.google.com/maps/documentation/places/web-service/policies), [field billing](https://developers.google.com/maps/documentation/places/web-service/data-fields), [EEA FAQ](https://developers.google.com/maps/comms/eea/faq) | Rating/count και reviews ενεργοποιούν διαφορετικά SKUs. `place_id` επιτρέπεται να αποθηκεύεται· γενικό permanent mirroring του content δεν επιτρέπεται πέρα από exceptions. Για νέο EEA integration η FAQ κατευθύνει map display στο Places UI Kit, όχι απευθείας Places API data πάνω σε MapKit. Ελέγχουμε account/region/use/AI restrictions πριν integration. |
| Καιρός | Εκτός MVP με απόφαση 29/10/2026 | Προαιρετική μελλοντική προσθήκη μόνο αν είναι απλή και δωρεάν για την πραγματική χρήση. Το free Open-Meteo endpoint είναι non-commercial, όχι δωρεάν εμπορική εξάρτηση. |
| DB/Auth | [Supabase](https://supabase.com/pricing) | Προτεινόμενη ενιαία λύση: PostgreSQL, PostGIS, Auth/RLS. Free 500 MB database, 50.000 MAUs, 5 GB egress και pause μετά από μία εβδομάδα αδράνειας. Pro από $25/month· επιπλέον υπηρεσίες/usage μπορούν να αυξήσουν το σύνολο. |
| Εναλλακτική DB | [Neon](https://neon.com/pricing) | PostgreSQL με permanent bounded free plan και scale-to-zero. Τρέχουσα pricing περιλαμβάνει και Managed Better Auth/Data API· δεν το περιγράφουμε ως αποκλειστικά database. Επιλογή αν αυτά ταιριάζουν καλύτερα στο deployment, όχι δεύτερη app DB παράλληλα. |
| Constraints/βελτιστοποίηση | [OR-Tools](https://developers.google.com/optimization/routing) | Open-source solver για routing/time windows. Χρειάζεται πραγματικό distance/time matrix· δεν παρέχει οδικά δεδομένα ή live transit. Αρχικά απλό bounded deterministic ranking/validation, solver όταν η πολυπλοκότητα το δικαιολογεί. |

Για το web UI μπορούμε να χρησιμοποιήσουμε MapLibre, αλλά renderer και tile service είναι διαφορετικά κόστη/terms. Self-hosted geocoding/routing είναι επιλογή σε scale, με compute και operational κόστος· δεν είναι «δωρεάν υπηρεσία». Δεν επιβεβαιώθηκαν τρέχοντα hosted openrouteservice plans επειδή οι σχετικές επίσημες σελίδες επέστρεψαν 404· δεν βασίζουμε budget σε παλιές ποσοστώσεις.

## Retrieval references αντί για ανεξέλεγκτη αποθήκευση

Παράδειγμα reference:

```json
{
  "entity_id": "canonical-venue-id",
  "provider": "official-venue",
  "external_id": "venue-lookup-id",
  "source_url": "https://example.org/venue/tickets",
  "adapter_version": "official-tickets-v1",
  "requested_fields": ["opening_exceptions", "ticket_price"],
  "refresh_policy": "on_selected_trip_and_before_booking",
  "retention_policy_id": "reviewed-provider-policy"
}
```

Το reference επιτρέπει επανεκτέλεση lookup. Ο resolver ελέγχει allowed use, fetch status, schema, identity και ημερομηνίες. HTTP 200 ή ενεργό link δεν επιβεβαιώνει από μόνο του την τιμή/λειτουργία. Εάν η πληροφορία δεν δημοσιεύεται, δείχνουμε unknown και action link. API credentials παραμένουν στο backend και δεν αποθηκεύονται μέσα σε URLs που εμφανίζονται στον χρήστη.

Όπου επιτρέπεται, κρατάμε observations/evidence ώστε να υπάρχουν ιστορικό και επαναχρήση. Όπου δεν επιτρέπεται, κρατάμε μόνο permitted identifiers/reference metadata και ανακτούμε on demand για το επιτρεπόμενο use. Expired licensed content διαγράφεται σύμφωνα με policy· stale fallback και audit log δεν αποτελούν παράκαμψη retention. AI summaries/embeddings από περιορισμένο content απαιτούν επίσης permitted use.

## Αυτόματος και μεγάλος σχεδιασμός prompts

Ο scheduler δεν στέλνει όλη την πόλη σε ένα prompt. Δημιουργεί queue από `area × category × missing_field_family`, με source coverage, priority, cost reservation και stop conditions. Συνδυασμοί χωρίς χρήσιμο στόχο γίνονται `not_applicable`, όχι χρεώσιμα prompts.

### Φάσεις και prompt types

1. **Import χωρίς LLM:** Overture regional extract, Wikidata links, επιλεγμένα city feeds. Deduplication, validation και source registration.
2. **Coverage analysis με κώδικα:** Counts ανά category/area, identity/evidence completeness, stale facts, unknown fields και διαθέσιμες source capabilities.
3. **Discovery μόνο για κενά:** Μία category/area, known IDs, bounded candidate target, novelty requirement και permitted sources. Επιστρέφει candidates, attempted searches και unresolved gaps.
4. **Evidence extraction:** Official pages/feeds ανά 20–50 entities όπου χωράει στο context budget. Structured parser πρώτα· μικρό AI μοντέλο για δύσκολο extraction μόνο όταν αξίζει.
5. **Classification και relations:** Multi-label annotations και visit-duration estimates πάνω σε διαθέσιμο evidence. Nearby alternatives, neighborhood/day-trip links και reasons. Όχι AI επινόηση coordinates ή verified age rules.
6. **Grounding/consistency review:** Deterministic schema/ID/date/units checks πρώτα. AI review μόνο για σημασιολογικές αντιφάσεις που δεν καλύπτει ο validator, με ακριβείς claim IDs.
7. **Targeted repair:** Μόνο failed entities/fields, evidence και validation errors. Bounded retries, όχι rewrite ολόκληρου catalog.
8. **Trip planning:** Bounded candidate pool, actual travel dates, relevant observations, routes/constraints και user state. Μικρό trip overlay, όχι νέα αντιγραφή catalog.
9. **Trip refresh/replan:** Μόνο αλλαγμένο stop/date/constraint. Οι υπόλοιπες user επιλογές διατηρούνται.

Ο δυναμικός prompt compiler συνθέτει versioned templates + semantic category/pill instructions + task parameters + schema + source policy + μικρό data slice. Στο personalized research οι οδηγίες εξηγούν κάθε επιλογή μέσα στο πλήρες trip context χωρίς global exclusions· βλ. FINAL_REQUIREMENTS_AND_PARITY.md. IDs σε JSON δεν αντικαθιστούν τις οδηγίες. Το μοντέλο μπορεί να προτείνει νέα tasks, αλλά ο scheduler εφαρμόζει allowed task types, budgets και priorities. Αποφεύγουμε ανεξέλεγκτα αυτοτροποποιούμενα prompts.

### Πιλοτικοί στόχοι για μεγάλη πόλη

Στόχοι σχεδιασμού, όχι επιβεβαιωμένη coverage ή υποχρεωτικά πλήθη:

- Αρχικό planning range ήταν 1.000–5.000 raw candidates. Πραγματικό Stage-3 αποτέλεσμα: **41.461 basic source records**, χωρίς ισχυρισμό πλήρους απογραφής πόλης· βλ. CATALOG_STAGE_3.md.
- **500 curated/enriched επιλογές** σε πρώτη έκδοση, με διαφορετικές περιοχές και κατηγορίες, όχι μόνο top tourist attractions. Νεότερη συμφωνία: **Luna μόνο**, χωρίς Sol fallback· uncertain/ambiguous cases παραμένουν review-needed αντί escalation σε άλλο μοντέλο.
- 30–60 high-detail επιλογές για αρχικά πραγματικά ταξίδια και alternatives.
- 8–12 useful area groups × 10–14 categories ως coverage matrix· όχι prompt για κάθε cell. Αρχικά έως 24–48 prioritized discovery tasks μόνο για ανεπαρκή cells, με μικρό πιλοτικό budget που μπορεί να σταματήσει πολύ νωρίτερα.
- Extraction/classification batches συνήθως 20–50 entities, αλλά το πραγματικό μέγεθος μειώνεται ανάλογα με source text/context/output.

Με μεγάλο αριθμό καλών imported entities μπορεί να χρειάζονται λιγότερα discovery prompts και περισσότερα σύντομα classification tasks. Με ανεπαρκές budget σταματάμε με σαφή measured gaps. Οι χρήστες επιταχύνουν enrichment σε συχνά χρησιμοποιούμενα entities· δεν προκαλούν πλήρη seed κάθε νέας πόλης.

Συγκεκριμένη επόμενη ροή: [CATALOG_ENRICHMENT_STAGE_3.md](CATALOG_ENRICHMENT_STAGE_3.md). Identity/core-landmark review και revised shortlist πρώτα, 20-record Luna pilot εντός των 500 μετά το provider/cap gate, validation και υπόλοιπες 480. Οι 500 δεν περιορίζουν τη searchable basic βάση και δεν καλύπτουν αυτόματα events/passes/transport ή κάθε extra discovery task.

### Novelty, πληρότητα και stop conditions

Μετράμε χωριστά `inventory_coverage`, `identity_quality`, `evidence_coverage`, `freshness_coverage`, `trip_feasibility` και `unresolved_conflicts`. Οι denominators είναι explicit pilot targets/known eligible records, όχι ισχυρισμός ότι γνωρίζουμε όλα τα μέρη της πόλης. Δεν υπάρχει ενιαίο «100% verified city».

Task priority: expected useful new entities or resolved fields × relevance × reuse potential × source quality / estimated cost. Η αρχική εκτίμηση βαθμολογείται heuristic και ενημερώνεται από πραγματικά αποτελέσματα.

Σταματάμε όταν καλύπτεται ο στόχος του cell, όταν διαδοχικά batches δεν δίνουν επαρκή νέα χρήσιμα records, όταν εξαντλείται source scope ή budget, ή όταν απαιτείται review. Δεν γεμίζουμε quotas με hallucinations. Sampling reviews ελέγχουν substantive grounding, όχι μόνο πόσα rows υπάρχουν.

## Όρια κόστους και αξιοπιστία jobs

- Budgets ανά destination seed, daily refresh, trip, user και provider· application-level ledger, όχι μόνο dashboard alert.
- Atomic reservation πριν από request: estimated worst-case tokens/tool/search/provider cost. Μετά reconciled actual usage. Χωρίς δυνατότητα εύλογου upper bound, αποφεύγουμε unattended autonomous research για strict budgets.
- Περιορίζουμε output tokens, candidate count, searches/tool calls όπου το API επιτρέπει, concurrency και retry attempts. Polling timeout δεν σημαίνει ότι ένα provider job έπαψε να χρεώνεται· χρειάζεται cancellation/status reconciliation.
- Durable Postgres queue με `FOR UPDATE SKIP LOCKED`, lease expiry/heartbeat, unique idempotency key, attempt history, exponential backoff και dead-letter state. Ο lease μηχανισμός χρειάζεται fencing ώστε παλιός worker να μην γράφει πάνω σε νεότερο αποτέλεσμα.
- Single-flight refresh ανά provider/entity/field/date window: δέκα χρήστες δεν προκαλούν δέκα ίδια fetches. Cache keys συμπεριλαμβάνουν language/currency/eligibility όπου αλλάζουν το αποτέλεσμα. Private bookings/offers δεν μοιράζονται σαν public cache.
- Content hash/ETag/Last-Modified όπου υποστηρίζονται μειώνουν επεξεργασία όταν η πηγή δεν άλλαξε. Δικαιώματα/retention προηγούνται caching.
- Δημοσιεύουμε validated proposals σε versioned catalog. Auto-publish μπορεί να επιτρέπεται για low-risk trusted-source updates· identity conflicts και unsupported high-impact claims απαιτούν review.

### AI τεχνικές οικονομίας

[OpenAI Batch API](https://developers.openai.com/api/docs/guides/batch): η επίσημη τεκμηρίωση αναφέρει 50% χαμηλότερο κόστος για κατάλληλα asynchronous API requests και παράθυρο 24 ωρών. Κατάλληλο για offline classification/enrichment· όχι για interactive planner. Δεν υποθέτουμε ότι το σημερινό Azure/Foundry agent endpoint υποστηρίζει την ίδια λειτουργία ή τιμολόγηση. Ελέγχουμε κάθε provider/deployment ξεχωριστά.

[OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching): reusable stable prefix για schema/taxonomy/instructions, μεταβλητά records μετά. Eligible minimums, retention και cache-read/write pricing εξαρτώνται από model/mode. Μετράμε cache-hit usage, όχι υπόσχεση καθολικής έκπτωσης. Δεν μεγαλώνουμε άσκοπα κάθε prompt για να φτάσει cache threshold.

Μικρό μοντέλο για extraction/classification πάνω σε μικρό evidence bundle. Ισχυρότερο μόνο για δύσκολη synthesis ή αποτυχημένο planning. Structured Outputs/JSON Schema όπου υποστηρίζεται μαζί με backend validation· schema adherence δεν εγγυάται αλήθεια. Το σημερινό `json_object` εγγυάται JSON mode, όχι ολόκληρο relational contract.

Δεν προτείνεται αλλαγή σε συγκεκριμένο «latest model» χωρίς benchmark σε πραγματικά Trippy cases και επιβεβαίωση deployment/pricing. Για το υπάρχον pipeline μετράμε χωριστά scout και synthesis αντί να αποδίδουμε όλη τη δαπάνη στο δεύτερο μοντέλο.

### Οικονομικό μοντέλο

```text
monthly_total = infra + shared_refresh + new_city_seeds
              + trips × (targeted_fetches + planning + expected_repairs)
              + provider/storage/egress charges

cost_per_call = input_tokens × input_rate + output_tokens × output_rate
              + cache/tool/search/provider charges
```

Οι token rates χρησιμοποιούν κοινή μονάδα, π.χ. ανά εκατομμύριο tokens. Eligibility για Batch/cache δεν εφαρμόζεται αυτόματα σε όλα τα επιμέρους charges.

Υποθετικό παράδειγμα απόσβεσης, όχι πρόβλεψη τιμών: αν city seed είναι €10 και εξοικονόμηση €0,25 ανά reuse, η αρχική απόσβεση θέλει 40 reuses πριν συνυπολογιστούν refresh/infra. Για έναν χρήστη αρχίζουμε με λίγες πόλεις και demand-driven enrichment. Σε εφαρμογή, το shared catalog και η shared refresh cache έχουν μεγαλύτερη αξία.

## Freshness και εμπειρία χρήστη

Αρχικές πολιτικές προς tuning από source contracts και usage:

| Πεδίο | Refresh heuristic | Χρήση στο ταξίδι |
|---|---|---|
| Identity/geo/basic category | Monthly dataset release, event-driven correction | Match και location έλεγχος αν υπάρχει conflict/closure indication. |
| Editorial context/relations | 3–12 μήνες ή νέα evidence | Χωρίς να παρουσιάζεται ως live fact. |
| Weekly hours/public ticket prices | 7–30 ημέρες όπου policy επιτρέπει | Στοχευμένος έλεγχος σημαντικών στάσεων/ημερομηνιών. |
| Ratings `/5` snapshots | Source-specific freshness/retention· χωρίς υποχρεωτικό live refresh | Source/date visible, stale state όπου permitted· expired restricted content αφαιρείται. Count optional. |
| Events/dated exceptions | 6–24 ώρες σε active date windows | Official confirmation, cancellation status και expiry μετά occurrence. |
| Weather | Δεν προγραμματίζεται στο MVP | Δεν μπλοκάρει research ή planning. |
| Bookable inventory/quote | Πολύ σύντομη validity ορισμένη από provider | Νέος έλεγχος πριν booking. Observation δεν είναι κράτηση. |

TTL δεν εγγυάται ότι η πληροφορία δεν άλλαξε πριν λήξει. Το UI δείχνει πηγή και χρόνο ελέγχου, ξεχωρίζει εκτίμηση/παλιά πληροφορία/ανεπιβεβαίωτο στοιχείο και δίνει official action link. Planner μπορεί να χρησιμοποιεί provisional stop με alternative· δεν παρουσιάζει unknown ως confirmed open.

Ο χρήστης χρειάζεται απλό brief και μία ενέργεια δημιουργίας ταξιδιού. Η εσωτερική πολυπλοκότητα μένει στο admin: coverage matrix, jobs, sources, conflicts, changes, costs και freshness. Τα εργαλεία enrichment λειτουργούν ανεξάρτητα από τα user requests.

## Αρχική σειρά υλοποίησης από έναν χρήστη μέχρι εφαρμογή

Η ακόλουθη επισκόπηση αντικαταστάθηκε ως execution order από το [autopilot plan](AUTOPILOT_STAGED_IMPLEMENTATION.md).

1. **Schema και private storage:** Supabase/Postgres, typed entities/observations, provider registry, migrations, Auth/RLS, user isolation και συμβατή v1 export projection. Persistent ownership αντικαθιστά shared bridge state.
2. **Barcelona pilot:** Overture regional import + Wikidata + επιλεγμένες official sources. Μικρό source-quality/licensing review πριν από μεγάλη εισαγωγή. Catalog query API με SQL/spatial/full-text filters.
3. **Τοπικός scheduler πρώτα:** Dry-run manifest με tasks, prompt versions, targets και budget estimates. Μικρό measured paid pilot αφού ρυθμιστούν explicit caps, έπειτα expansion μόνο όπου τα αποτελέσματα το δικαιολογούν.
4. **Live adapters/resolver:** Official hours/prices, holiday checks, events και transit. Shared refresh/deduplication, unknown handling, source health/format change detection. Permitted `/5` research snapshots όπου υπάρχουν, αλλιώς source links/unknown.
5. **Planner και validation:** Retrieve π.χ. 30–80 relevant candidates με compact records, refresh αρχικά μόνο shortlist/critical constraints, AI plan και deterministic cost/route/time checks. Προβλέπουμε provider matrix πριν την τελική σειρά και ένα bounded repair όταν χρειάζεται.
6. **Admin web UI:** Coverage, review conflicts/proposals, budget/usage, source health, version publish/rollback. Δεν απαιτούμε edit όλων των records χειροκίνητα.
7. **Scale όταν μετρηθεί ανάγκη:** Περισσότεροι queue workers, connection pooling, selective partitioning/indexes, backups και paid production capacity. Προαιρετικό pgvector για semantic retrieval μετά τα hard filters. Redis/Temporal/graph DB/Kubernetes δεν είναι αρχική προϋπόθεση.

Acceptance criteria για pilot: κανένα cross-user αποτέλεσμα, κανένα duplicate job/fetch για ίδιο active key, πραγματικό usage reconciliation, preserved user overrides, null/unknown σε ανεπιβεβαίωτα facts, source evidence στα critical fields, dated closures εκτός confirmed plan, αναπαραγώγιμα budget totals και καθαρό partial status όταν η source coverage είναι ανεπαρκής.

Το προτεινόμενο σύστημα είναι μεγάλο στην κάλυψη και επιλεκτικό στην AI εργασία. Η ανοιχτή βάση μειώνει discovery κόστος, η κοινή normalized DB επιτρέπει επανάχρηση, οι retrievable references διατηρούν τη δυνατότητα επανελέγχου και ο planner αξιοποιεί μόνο ό,τι σχετίζεται με το συγκεκριμένο ταξίδι.
