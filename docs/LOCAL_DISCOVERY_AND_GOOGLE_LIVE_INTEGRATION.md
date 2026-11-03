# Trippy: τοπική ανακάλυψη, προηγούμενες επισκέψεις και Google live integration

> Ενεργό πλάνο 29/10/2026: [τελικές απαιτήσεις και parity](FINAL_REQUIREMENTS_AND_PARITY.md), [κοινό implementation agreement](IMPLEMENTATION_AGREEMENT_PLAN.md) και [μοναδική σειρά stages για autopilot](AUTOPILOT_STAGED_IMPLEMENTATION.md). Οι τελευταίες απαιτήσεις περιλαμβάνουν semantic prompts ανά προτίμηση, κεντρική MapKit αναζήτηση/ιδιωτική αποθήκευση pin και sourced rating snapshots μόνο `/5`. Supabase Free project δημιουργήθηκε από τον χρήστη· σύνδεση/migrations δεν επαληθεύτηκαν. Παλιά scope/status/task lists είναι ιστορικά όπου διαφέρουν· οι ειδικές λεπτομέρειες του παρόντος παραμένουν όταν συμφωνούν.

Ημερομηνία: 29 Οκτωβρίου 2026. Αναθεώρηση του ευρύτερου catalog/prompting σχεδίου με βάση τις νέες απαιτήσεις του χρήστη και σημερινή ανάγνωση επίσημων πηγών. Είναι specification προς υλοποίηση: δεν εγκαταστάθηκαν API integrations, migrations ή νέο UI, και δεν εκτελέστηκαν χρεώσιμες AI κλήσεις.

Περαιτέρω διευκρίνιση: [ACTIVITY_OPTIONS_AND_SELECTIONS.md](ACTIVITY_OPTIONS_AND_SELECTIONS.md) ορίζει city-level preference pills, stable activity slots με πολλά alternatives, user selection locks χωρίς απώλεια του pool και σύγκριση Google free caps/Apple Maps.

## Αποφάσεις που προστίθενται στο πλάνο

1. Ο καιρός αφαιρείται από το MVP, τα required research modules και τα blocking quality checks. Ενδεχόμενο basic widget μόνο αν είναι απλό και δωρεάν για την πραγματική χρήση, χωρίς νέα υποχρεωτική εξάρτηση. Δεν χαρακτηρίζουμε non-commercial free endpoint ως δωρεάν εμπορική υπηρεσία.
2. Η γεωγραφία έχει εμφανή επίπεδα ήπειρος → χώρα → πόλη → περιοχές, με δυνατότητα για περιφέρεια/μητροπολιτική περιοχή. Τα facts και τα discovery concepts έχουν σαφές geographic scope.
3. Προστίθεται shared taxonomy τοπικών εμπειριών, venue styles, cuisines, dishes και brands. Από αυτήν παράγονται δυναμικές επιλογές input και coverage tasks.
4. Προστίθεται προαιρετικό «έχω ξαναπάει» και επιλογή συγκεκριμένων ήδη επισκεμμένων places/experiences, με δυνατότητα επανεπίσκεψης.
5. Το final venue pool περνά dated opening/closure checks πριν από την επιβεβαίωση του προγράμματος. Ο Google adapter ενεργοποιείται μόνο για use που καλύπτουν το πραγματικό agreement και το προϊόν.
6. Google Places/UI Kit αποτελούν πιθανό on-demand UI layer, με billing/terms gates και fallback. Η open catalog βάση και ο planner δεν εξαρτώνται από ανεξέλεγκτο Google content export.
7. Το UI υποστηρίζει σταδιακή εμφάνιση αποτελεσμάτων από durable jobs, με provider-wide throttling. Δεν συγχέονται requests/sec με records/sec.

## Google: τι μπορεί να γίνει on demand και τι είναι δωρεάν

Το επίσημο consumer Google Maps site/app και το Google Maps Platform API είναι διαφορετικά προϊόντα. Δωρεάν πρόσβαση του χρήστη στην εφαρμογή Maps δεν συνεπάγεται δωρεάν απεριόριστο API, ούτε άδεια scraping.

Το Place Details API μπορεί τεχνικά να ανακτά πληροφορίες τη στιγμή του request. «Φρέσκια ανάκτηση» δεν σημαίνει live sensor ή βεβαιότητα ότι ο ιδιοκτήτης ενημέρωσε τα δεδομένα.

### Δυνατότητες δεδομένων

| Ανάγκη | Τι παρέχει Place Details | Τι δεν αποδεικνύει |
|---|---|---|
| Λειτουργία επιχείρησης | `businessStatus`, moved-place metadata όπου υπάρχουν | Ότι δεν υπήρξε μη δηλωμένη αλλαγή σήμερα. |
| Συνήθη ωράρια | `regularOpeningHours` | Εξαιρέσεις μιας μελλοντικής ημερομηνίας έξω από το current window. |
| Ειδικά ωράρια | `currentOpeningHours`, `specialDays`, secondary hours | Το current window είναι σήμερα και οι επόμενες έξι ημέρες, όχι αυθαίρετη travel date. |
| Rating | `rating`, `userRatingCount` | Ανεξάρτητη ποιότητα, καθολική πληρότητα ή πρόσφατη τάση όλων των reviews. |
| Reviews | Μέχρι 5 reviews, sorted by relevance | Πλήρες corpus, newest-first feed ή αξιόπιστη ανάλυση «έχει χαλάσει τελευταία». |
| Τιμές | `priceLevel`, `priceRange` όπου συμπληρώνονται | Πλήρες menu, ακριβή τιμή κάθε dish/ticket, φόρους/προσαυξήσεις ή διαθέσιμο quote. |
| Dining χαρακτηριστικά | Ορισμένα fields για dine-in, live music, vegetarian food, reservable κ.λπ. | Ζωντανή διαθεσιμότητα τραπεζιού, allergy safety ή επιβεβαιωμένη κράτηση. |
| Events | Δεν είναι καθολικό dated events feed | Πλήρες ημερολόγιο συναυλιών, festivals και temporary exhibitions. |

Πηγές: [Place resource/reference](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places), [Place Details/field tiers](https://developers.google.com/maps/documentation/places/web-service/place-details).

### Δωρεάν όρια και χρέωση

Snapshot του [Global pricing](https://developers.google.com/maps/billing-and-pricing/pricing), 29/10/2026. Ποσά USD, ανά 1.000 billable events στο πρώτο πληρωμένο volume tier· δεν περιλαμβάνουν φόρους, ξεχωριστά search/photos/AI ή ειδική συμφωνία λογαριασμού.

| SKU | Free cap / μήνα | Επόμενες 1.000 κλήσεις/events |
|---|---:|---:|
| Place Details Pro | 5.000 | $17 |
| Place Details Enterprise | 1.000 | $20 |
| Place Details Enterprise + Atmosphere | 1.000 | $25 |
| Places UI Kit Pro | 5.000 billable events | $5 |

`businessStatus` ενεργοποιεί Pro· hours/rating/count/price fields ενεργοποιούν Enterprise· reviews και επιπλέον dining fields μπορούν να ενεργοποιήσουν Enterprise + Atmosphere. Μία Place Details κλήση χρεώνεται στο υψηλότερο SKU των ζητούμενων fields, όχι άθροισμα όλων των tiers. FieldMask μόνο των αναγκαίων fields, όχι `*` σε production. Οι UI Kit billing units αξιολογούνται βάσει των δικών τους SKU rules, όχι αυθαίρετα «ένα δωρεάν event ανά πλήρη οθόνη».

Ενδεικτικά: 20 Enterprise lookups ανά trip × 50 trips = 1.000 κλήσεις, εφόσον δεν υπάρχει άλλη σχετική χρήση. Μετά το free cap, 20 επιπλέον Enterprise calls κοστίζουν περίπου $0,40 για αυτά τα calls μόνο. Mapping/search, επανέλεγχοι, photos και AI είναι ξεχωριστές δαπάνες. Το free cap αφορά billing usage, δεν είναι νέο allowance ανά χρήστη/πόλη και δεν ανανεώνεται με κάθε project.

API setup απαιτεί billing-enabled project/key για τα σχετικά services. Για στόχο μηδενικής δαπάνης: server-side monthly quota ledger, conservative cap κάτω από free allowance, controlled keys, monitoring και fallback όταν εξαντλείται. Budget alert μόνο δεν είναι hard stop και τρίτες χρήσεις στο ίδιο billing account πρέπει να συνυπολογίζονται.

### Ειδικά για Ελλάδα/ΕΟΧ: UI και prompts είναι διαφορετικά uses

Οι ειδικοί όροι εφαρμόζονται βάσει billing address και integration state, όχι απλώς επειδή ο ταξιδιώτης βρίσκεται σε ευρωπαϊκή πόλη. Για νέο ελληνικό billing account, οι [EEA Places terms](https://cloud.google.com/terms/maps-platform/eea/maps-service-terms), sections 15–16, είναι ουσιώδεις:

- Raw Places API content, πλην latitude/longitude/place ID, έχει περιορισμούς για χρήση «With any Map» και μόνο συγκεκριμένα [Permitted Uses](https://cloud.google.com/terms/maps-platform/eea-places-api-permitted-uses).
- «With any Map» περιλαμβάνει και εμφανώς συσχετισμένες κάρτες δίπλα σε χάρτη ή linking· δεν λύνεται απλώς βάζοντας το rating σε sidebar.
- Οι δύο συγκεκριμένοι περιορισμοί δεν εφαρμόζονται στο Places UI Kit. Η επίσημη [integration guide](https://developers.google.com/maps/comms/eea/places) παραπέμπει σε JavaScript/Android/iOS UI Kit για εμφάνιση Place Details με οποιονδήποτε χάρτη, άρα και τρίτο renderer όπως MapKit, με διατήρηση attribution/links/notices.
- Αυτό δεν μετατρέπει το UI Kit σε γενική πηγή raw export για τον planner. Display capability, backend analysis και data retention είναι χωριστά δικαιώματα.
- Η γενική πολιτική απαγορεύει caching/storage πέρα από εξαιρέσεις. Place IDs επιτρέπεται να διατηρούνται· οι EEA service terms επιτρέπουν temporary latitude/longitude cache έως 30 ημέρες. Δεν εφαρμόζουμε blanket «30 ημέρες» σε ratings/reviews/όλο το response.

Οι επιτρεπόμενες raw API χρήσεις περιλαμβάνουν π.χ. notes/tasks/reminders συνδεδεμένα με named places. Δεν εντοπίστηκε ρητή γενική άδεια για όλο το επιθυμητό AI travel discovery/ranking/planning workflow. Δεν παρουσιάζουμε το «δεν αποθηκεύω» ή το «είναι inference, όχι training» ως αυτόματη έγκριση. Οι γενικοί [EEA terms](https://cloud.google.com/terms/maps-platform/eea), section 3.2.3, περιέχουν επιπλέον περιορισμούς δημιουργίας περιεχομένου και AI/model improvement. Αποφεύγουμε να εξισώσουμε τον περιορισμό training με καθολική απαγόρευση κάθε inference· το proposed use χρειάζεται συγκεκριμένη κάλυψη από τα applicable terms.

**Προτεινόμενη πρακτική:** own/open facts για retrieval, enrichment και planner· optional Google UI Kit για live Place Details, ratings/review display· official/operator data για critical future-date checks. Ο raw Google planner adapter παραμένει disabled μέχρι να έχει τεκμηριωμένο permitted-use basis. Δεν μεταφέρουμε Google data σε logs, embeddings, prompt caches ή shared catalog μέσα από παράπλευρες διαδρομές.

### Gemini Grounding with Google Maps

Υπάρχει ξεχωριστό [Maps grounding tool στο Gemini](https://ai.google.dev/gemini-api/docs/maps-grounding), σχεδιασμένο για Google Maps-informed responses. Η τρέχουσα τεκμηρίωση αναφέρει English-only prompts/responses και region/data limitations. Δεν το θεωρούμε έτοιμο drop-in για το ελληνικό Trippy.

Οι [Gemini terms, Grounding with Google Maps](https://ai.google.dev/gemini-api/terms), απαιτούν display του grounded result με τα associated links στον initiating user και δεν επιτρέπουν ανεξέλεγκτη τροποποίηση, export, training ή caching. Υπάρχουν περιορισμένες εξαιρέσεις display evaluation και end-user chat history. Δεν επιτρέπεται να το μετατρέψουμε αυθαίρετα σε bulk ingestion, JSON facts για τη βάση ή νέο prompt προς άλλον provider. Το translation/rewriting επίσης δεν θεωρείται αυτόματα επιτρεπόμενο.

Για Gemini 3 και νεότερα η σημερινή τεκμηρίωση αναφέρει 5.000 δωρεάν Maps search queries/μήνα κοινά στα σχετικά μοντέλα και $14/1.000 μετά. Ένα prompt μπορεί να προκαλέσει πολλά queries· τα model tokens χρεώνονται ξεχωριστά και το pricing δεν το προσφέρει ως γενικά δωρεάν model-tier integration. Optional ξεχωριστή Google-grounded απάντηση μπορεί να εξεταστεί αργότερα, εφόσον καλύπτονται language, product use και πραγματικά account/region limits.

## Overture: ακριβής ρόλος στο πλήρες σύστημα

Το [Places schema](https://docs.overturemaps.org/schema/reference/places/place/) και ο [οδηγός Places](https://docs.overturemaps.org/guides/places/) δίνουν:

| Πεδίο/ανάγκη | Κάλυψη |
|---|---|
| Canonical/source IDs και point coordinates | Ναι, βάση για identity και spatial retrieval. |
| Name/local aliases | Schema support· πραγματική πληρότητα διαφέρει. |
| Country/locality/address | Όπου υπάρχουν, με validation της γεωγραφίας. |
| Venue taxonomy | `basic_category`, `taxonomy` με hierarchy/alternates. Η παλιά `categories` αφαιρέθηκε στο September 2026 release. |
| Websites, socials, email, phone | Προαιρετικά, όχι εγγυημένα ή πάντα σωστά. |
| Chain/brand | Προαιρετικά brand data, χρήσιμα για branches/chain discovery. |
| Source provenance/version/confidence | Ναι· confidence αφορά existence και relative filtering, όχι rating/ποιότητα εξυπηρέτησης. |
| Operating status | Προαιρετικό λειτουργεί/temporary hiatus/permanently closed, dataset observation. Το `open` δεν σημαίνει ανοικτό αυτή την ώρα ή την travel date. |
| Weekly/special opening hours | Δεν παρέχονται ως αντίστοιχο πλήρες opening-hours σύστημα στο Places schema. |
| Ratings/reviews/popularity trends | Δεν παρέχονται ως review platform feed. |
| Exact prices/menu/tickets/reservations | Δεν παρέχονται ως operational inventory/quote system. |
| Events/occurrences | Δεν παρέχονται ως dated calendar. |
| Descriptions/why visit/visit duration/local dishes | Χρειάζονται άλλες πηγές και editorial/AI enrichment. |
| Real imagery με rights | Δεν είναι πλήρες media/rights catalog. |
| Allergy/accessibility/traveler suitability | Δεν επαρκεί για επιβεβαίωση των συγκεκριμένων constraints. |
| Neighborhood boundaries/continent hierarchy | Places είναι point destinations· geography hierarchy/polygons χρειάζονται Divisions ή άλλα κατάλληλα datasets. |
| Route times/transit/itinerary | Δεν παρέχονται από Places· routing/feed/planner είναι ξεχωριστά. |

Η επίσημη τεκμηρίωση δηλώνει known duplicates/junk και χαμηλή πληρότητα properties. Άρα import με confidence filtering, identity resolution και field-quality checks, όχι αντιμετώπιση κάθε record ως verified.

**Seed:** regional import χωρίς AI για κάθε όνομα/θέση. **Συνεχής βάση:** monthly releases και changelog για updates. **Προσωπικό trip:** SQL/spatial/taxonomy retrieval από τη δική μας ενημερωμένη βάση, έπειτα στοχευμένο enrichment/operational verification. Δεν ξανακατεβάζουμε global Parquet και δεν ρωτάμε Overture ως live API για κάθε screen.

## Γεωγραφικά επίπεδα και τοπικές εμπειρίες

### Geography

`geo_units(id, kind, name, parent_id, geometry, source/version)` με continent, country, admin_region, city, neighborhood και optional metro area. UI breadcrumb: ήπειρος → χώρα → πόλη → περιοχή. Cross-border/metropolitan/informal περιοχές μπορούν να έχουν `geo_relations` για overlaps αντί να επιβάλλουμε λάθος μοναδικό γονέα.

Κάθε fact/guide/topic έχει scope. Country food context δεν αντιγράφεται σε κάθε city JSON. City override/exception μπορεί να εξειδικεύει country information. Country rule δεν γίνεται χωρίς evidence κανόνας κάθε venue. Τα venues συνδέονται με τη δική τους περιοχή· excursions έχουν destination relations και μπορούν να εξυπηρετούν πολλές base cities.

### Dynamic local facets

Προτεινόμενοι πίνακες: `discovery_concepts`, `concept_geo_scopes`, `entity_concepts`, `brands`, `dishes`, `entity_dishes`, `concept_evidence`. Τα concepts έχουν kind: venue_style, cuisine, dish, experience, brand. Λέξεις/aliases/localized UI labels και broad parent categories αποφεύγουν άσκοπα διπλότυπα.

Παραδείγματα user-requested concepts προς τεκμηρίωση:

| Scope | Concept | Parent/filter |
|---|---|---|
| Budapest | Ruin bars | Bars/nightlife |
| Athens | Modern/cocktail bars, specialty coffee, clubs | Bars/coffee/nightlife, διακριτές επιλογές |
| Greece | Fish taverns, souvlaki/seafood experiences | Venue style, dish/cuisine |
| Country/city | Specific fast-food chains | Brand + confirmed local branch availability |

Το AI προτείνει concepts και entity links από permitted evidence. Publisher/reviewer ή trusted pipeline τα επικυρώνει. Οι χαρακτηρισμοί «δημοφιλές», «χαρακτηριστικό της πόλης» και «διαθέσιμο» είναι διαφορετικοί: μεγάλος αριθμός records δεν αποδεικνύει popularity. Overture taxonomy/brand βοηθούν αλλά δεν παράγουν μόνα τους local cultural guide ή πλήρες menu/dish mapping.

Input endpoint `GET /destinations/{id}/discovery-options` διαβάζει published relevant city+country concepts, κάνει deduplication/local overrides και δείχνει επιλογές με υπαρκτά eligible candidates. Minimum candidate threshold και evidence rule είναι configurable. Η έλλειψη dataset coverage δεν παρουσιάζεται ως «δεν υπάρχει στην πόλη».

Ο χρήστης βλέπει μικρό σχετικό σύνολο επιλογών και «περισσότερα». Καμία live AI κλήση για να ζωγραφιστεί η φόρμα. Selected concepts γίνονται retrieval filters/soft boosts και coverage jobs για πραγματικά κενά. Dishes παραμένουν preferences· δεν ισοδυναμούν με allergy verification.

## «Έχω ξαναπάει» και ήδη επισκεμμένα

Προαιρετικά inputs: `visit_status=first_time|returning|unspecified`, αναζήτηση/επιλογή γνωστών places, free-text για όσα δεν είναι mapped, και ανά place `avoid_repeat|open_to_repeat|want_to_revisit`.

Προτεινόμενα private tables: `user_destination_visits`, `user_place_history`, `trip_revisit_preferences`. Δεν απαιτούμε πλήρες ιστορικό για να δημιουργηθεί trip. Ambiguous free-text resolution ζητά διόρθωση αντί να αποκλείσει λάθος χώρο. «Είδα την περιοχή» δεν σημαίνει ότι είδε όλα τα venues μέσα σε αυτήν.

Returning user χωρίς selected places παίρνει περισσότερη novelty ως soft preference. Explicit `avoid_repeat` είναι hard exclusion όπου δεν συγκρούεται με νεότερη user επιλογή. Must-see/revisit choices έχουν προτεραιότητα. Group trip χειρίζεται διαφορετικά histories χωρίς να αποκλείει αυτόματα κάτι που ένα μόνο μέλος έχει δει. Το ιστορικό δεν μεταφέρεται στο public/shared catalog.

## Έλεγχος του τελικού venue pool

1. Retrieve broad candidates από catalog με local concepts, budget, geography, traveler constraints και visit history.
2. Προσωρινή shortlist μαζί με alternatives· περιορισμένος αριθμός operational checks, όχι ολόκληρη πόλη.
3. Check identity/moved/temporary/permanent closure status και πραγματικά date/time windows με venue timezone.
4. Separate business operation από opening intervals και reservations. Overnight club hours ανήκουν σε intervals που μπορούν να περνούν τα μεσάνυχτα.
5. Εντός Google seven-day window, επιτρεπόμενο adapter/use μπορεί να αξιοποιεί current exceptions. Εκτός window: official date-specific sources ή provisional weekly-rule estimate με ρητό recheck όταν πλησιάσει το ταξίδι. Δεν μετακινούμε το API window με φανταστική ημερομηνία request.
6. Confirmed closed venue αφαιρείται από εκείνο το slot και αντικαθίσταται από συμβατή alternative. Δεν διαγράφουμε το canonical record ούτε τις παλιές user επισκέψεις/κρατήσεις.
7. Unknown παραμένει provisional με action/source link· δεν γίνεται confirmed επειδή έγινε HTTP 200. Κρίσιμο allergy/accessibility constraint χρειάζεται επαρκές evidence.
8. Deterministic time/route/cost validation και bounded repair μετά τις αλλαγές. Recheck T-7/on-use όπου είναι χρήσιμο και πριν τη δέσμευση booking σύμφωνα με source validity.

Text reviews και semantic quality-decline analysis δεν είναι product requirement. «Reviews» σημαίνει μόνο sourced αστέρια `/5`, με permitted snapshot από το ίδιο research όπου διαθέσιμο. Rating είναι optional signal, διαφορετικό από AI fit, με platform/source/observed time και retention· βλ. τελικές απαιτήσεις.

## Progressive loading χωρίς προβολή των τεχνικών ορίων

Το [Ticketmaster](https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/) τεκμηριώνει default 5 requests/sec και 5.000/day. Default page size είναι 20 events. Άρα ένα request μπορεί να φέρει 20 events και το UI να δείξει όσα έχουν ήδη ανακτηθεί χωρίς να περιμένει ένα request ανά event.

Προτεινόμενη ροή:

- Το input και οι πρώτες catalog επιλογές έρχονται από τη βάση.
- Backend δημιουργεί owner-scoped persistent job και επιστρέφει `202 + job_id`.
- Worker εκτελεί ανεξάρτητα provider tasks με global per-key token bucket, concurrency bounds, daily/monthly accounting και priority στη visible shortlist.
- SSE ή bounded polling μεταφέρει `candidates_ready`, `events_page_ready`, `verification_updated`, `plan_proposed`, `plan_validated`, `partial_error`, με sequence/version και resumable reconnect.
- Το UI δείχνει νέες κάρτες/επιβεβαιώσεις μόλις είναι διαθέσιμες. Events μπορούν να μπαίνουν σε groups των 5 αν αυτό βοηθά το layout· δεν καθυστερούμε τεχνητά έτοιμα δεδομένα για να μιμηθούμε rate limit.
- Deduplication ID, stable sort και batching UI updates περιορίζουν reorder/flicker. Το proposed plan δεν βαφτίζεται validated όσο εκκρεμούν critical checks.
- Retry-After/backoff, bounded wait και fallback κρατούν την εφαρμογή usable. Δεν εμφανίζουμε provider quota jargon· δείχνουμε «ελέγχουμε ωράρια» ή τίμια partial κατάσταση όταν δεν μπορεί να ολοκληρωθεί κάτι.

Η προοδευτική εμφάνιση μειώνει perceived waiting, δεν καταργεί φυσική latency ή shared quotas. Δέκα concurrent users δεν παίρνουν ο καθένας ανεξάρτητο allowance του ίδιου API key. Daily/monthly quota exhaustion δεν λύνεται με requests/sec throttling. Single-flight/cache χρησιμοποιούνται μόνο όπου permitted: δεν εφαρμόζουμε generic persistent/shared cache σε Google ratings/reviews.

Το σημερινό bridge έχει shared in-memory state και επιστρέφει μόνο τελικό result. Progressive loading χρειάζεται νέο owner-scoped job/event store και client rendering· δεν είναι απλή αλλαγή στο interval polling.

## Prompt caching και προτεραιότητες υλοποίησης

[OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching): κοινά taxonomy/schema/instructions σε stable reusable prefix, current candidates/facts/user history στο μεταβλητό τμήμα. Model/provider-specific cache/read/write rates και actual hit metrics. Το cache δεν ανανεώνει factual information και δεν επιτρέπει retention restricted content.

Επιπλέον: cached/versioned discovery options χωρίς AI, incremental jobs μόνο για changed evidence, output caps, offline Batch για supported enrichment, deterministic filters/calculators, bounded semantic repair και demand-driven enrichment.

Προτεραιότητες:

1. Geography/concepts/history schema και API contracts μέσα στο κοινό Postgres σχεδιασμό.
2. Regional Overture importer που διαβάζει τη σημερινή taxonomy και διατηρεί source quality/version.
3. Dynamic input options και returning-user preferences από published catalog.
4. Dated verification resolver με alternatives, uncertainty και future-window rules.
5. Durable owner-scoped jobs και progressive UI events με provider-wide quotas.
6. Optional Google UI Kit proof-of-concept σε πραγματικό iOS/UI deployment και billing cap. Raw planner integration μόνο για τεκμηριωμένο permitted use· Gemini grounding ως χωριστό optional προϊόν εφόσον ταιριάζει.
7. Μετρήσεις cost/coverage/latency πριν expansion σε περισσότερες πόλεις. Weather παραμένει εκτός MVP.

Acceptance: facet selections resolve σε πραγματικά candidates, country chains δεν εμφανίζονται χωρίς local availability, visit exclusions/revisit overrides διατηρούνται, closed venues δεν μπαίνουν σε validated slots, long-future dates δεν γίνονται confirmed από current Google hours, attribution/retention τηρούνται, quotas δεν υπερβαίνονται λόγω concurrent jobs και partial failures δεν διαγράφουν το χρηστικό αποτέλεσμα.
