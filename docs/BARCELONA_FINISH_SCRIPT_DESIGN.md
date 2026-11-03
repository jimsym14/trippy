# Τελικό script ολοκλήρωσης: συγκεκριμένος σχεδιασμός

Σχεδιασμός 2 Νοεμβρίου 2026. Το script θα συνδέσει τη διορθωμένη βάση με
retrieval, optional activities, φίλτρα και ελεγχόμενα draft plans. Θα παράγει
σύγκριση πριν/μετά και μικρή λίστα πραγματικών εκκρεμοτήτων. Δεν είναι νέα μαζική
εξαγωγή βίντεο ή καθολική έγκριση AI προτάσεων.

**Νεότερη κατάσταση:** υπάρχει εκτελέσιμος runner με offline integration,
16 synthetic behavior cases και bounded explicit operator-page checks. Ακριβείς
εντολές και περιορισμοί στο [BARCELONA_FINISH_RUNNER.md](BARCELONA_FINISH_RUNNER.md).
Το παρόν παραμένει το ευρύτερο design reference: Places/Routes integration,
full itinerary validation και UI rendering δεν ολοκληρώθηκαν από τον runner. Το
`configs/barcelona-finish-design-v1.json` καταγράφει τις εξαρτήσεις, τα όρια και τα
κριτήρια. Το executable configuration είναι `configs/barcelona-finish-v1.json`.

## Μία εντολή, διαδοχικά στάδια

Προτεινόμενη διεπαφή μετά την υλοποίηση:

```sh
.local/stage3/run-barcelona-finish.sh offline
.local/stage3/run-barcelona-finish.sh connected --trip <trip-file.json>
.local/stage3/run-barcelona-finish.sh resume --campaign <campaign-id>
.local/stage3/run-barcelona-finish.sh status --campaign <campaign-id>
```

Το offline είναι η προεπιλογή: χρησιμοποιεί αποθηκευμένα στοιχεία και εκτελεί
όλες τις ανεξάρτητες εργασίες χωρίς δίκτυο ή AI. Το connected εκτελεί μόνο
προδιαγεγραμμένες εργασίες που αντιστοιχούν σε διαθέσιμη δυνατότητα provider.
Χωρίς πραγματικά trip dates παράγεται reusable discovery snapshot και synthetic
test plans· κανένα από αυτά δεν χαρακτηρίζεται έλεγχος πραγματικού ταξιδιού.

| Στάδιο | Εργασία | Παραδοτέο / όρος εξόδου |
| --- | --- | --- |
| 1. Audit | Πάγωμα edition/input hashes, έλεγχος 2.028 slots και SQLite parity | Αποτυχία διατήρησης σταματά τα εξαρτώμενα στάδια |
| 2. Compile | Reader για την επιλεγμένη έκδοση, evidence mapping, reviewed taxonomy | Snapshot με ξεχωριστές recommendations, proposals, facts και identities |
| 3. Retrieve | Ίδιοι κανόνες ranking πριν/μετά, δραστηριότητες και φίλτρα | Αποτελέσματα με evidence IDs, shortlist και κενά |
| 4. Targeted evidence | Cache → τοπικά candidates → επίσημες σελίδες/configured APIs → προαιρετικό Luna | Νέες παρατηρήσεις, συγκρούσεις, proposals· όχι αυτόματη τελική έγκριση |
| 5. Adjudicate shortlist | Εφαρμογή τεκμηριωμένων αποφάσεων, ασφαλών mappings και manual decisions | Μόνο admissible στοιχεία· unresolved μένουν ορατά |
| 6. Plan/export | Deterministic σύνθεση, transfers, τοπικές διορθώσεις, map/panel payloads | Draft plans και validation ανά constraint |
| 7. Evaluate | Fixed expected sets, semantic regressions, πριν/μετά, interruption/resume | Τελικό report με πραγματικά gates και συγκεκριμένο handoff |

Τα στάδια έχουν αυτή τη σειρά. Μέσα στο evidence stage, ανεξάρτητα places μπορούν
να συνεχίζουν όσο ένας provider περιμένει rate limit. Εξαρτώμενη έγκριση ή plan
check δεν εκτελείται με ελλείποντα στοιχεία σαν να είχαν επιτύχει.

## 1. Διατήρηση και immutable inputs

Χρησιμοποιούμε το υπάρχον `trippy.research.dataset_audit`, τον έλεγχο SQLite και
το `active-dataset.json`. Το campaign αποθηκεύει edition hash, registry version,
trip/preferences hash, compiler/policy versions και providers capabilities.
Η μελλοντική αλλαγή οποιουδήποτε input δημιουργεί νέο campaign ή ρητό delta· δεν
μεταβάλλει το νόημα ενός παλιού checkpoint.

Διατηρούνται 549 source occurrences, 2.028 claim slots, 42 held claims,
1.851 νέα annotations, 20 προηγούμενα manual reviews, observations και receipts.
Η απουσία από το default retrieval δεν μετρά ως διαγραφή. Το report ελέγχει
ξεχωριστά storage conservation, eligibility και πραγματική retrievability.

## 2. Reader και taxonomy αντί για νέα prose inference

Νέος `trippy/planner/dataset_reader.py` θα διαβάζει την επιλεγμένη edition και θα
επιστρέφει τέσσερις ανεξάρτητες κατηγορίες:

- Source recommendations, με το αρχικό video/cue και χρόνο δημοσίευσης.
- Pending annotations / περιγραφικό context, διαθέσιμα για έρευνα και αιτιολόγηση.
- Reviewed typed tags με current claim bindings και σαφή subject scope.
- Canonical identities / operational observations με δική τους προέλευση και ισχύ.

Δεν μετατρέπουμε αυτόματα source fact σε verified operational fact. Η μεταφορά
στο σημερινό `Fact` δεν πρέπει να εξισώνει τον χρόνο review με τον χρόνο που
παρατηρήθηκε ένα ωράριο. Recommendation evidence χρειάζεται δικό του contract.
Source occurrence IDs παραμένουν lineage IDs· canonical place ID είναι άλλο πεδίο.
Name similarity δεν συγχωνεύει branches. Market, vendor, stadium και museum έχουν
ρητή parent/subvenue σχέση όπου αυτή τεκμηριώνεται.

Το registry γίνεται v2 με church, stadium, food_hall, plaza και pastry_shop,
κρατώντας τις παλιές τιμές και explicit migration table. Οι 37 facet→detail
μεταφορές επανεξετάζονται μόνο όπου υπάρχει ήδη manual source comparison που
επιτρέπει συγκεκριμένο typed value. Οι υπόλοιπες παραμένουν context. Κανένα
batch promotion των 1.715 pending annotations.

Το ίδιο compiled snapshot τροφοδοτεί φίλτρα, research packets και planner.
Κάθε mapping αποθηκεύει original entry, effective typed value, review method και
evidence IDs, ώστε να μη χρειάζεται νέο AI classification σε κάθε request.

## 3. Retrieval, shortlist και optional activities

Ο reader εκθέτει source discovery candidates ακόμη και όταν η canonical
ταυτότητα εκκρεμεί. Τα map pins και οι προγραμματισμένες στάσεις χρειάζονται
χωριστό location/identity gate. Χωρίς συντεταγμένες εμφανίζεται list item με
εκκρεμότητα· δεν εφευρίσκεται pin ή route.

Πρώτα hard exclusions/locks, μετά matching tags, source recommendations και
τεκμηριωμένη ποιότητα, τέλος route fit και κόστος. Ranking weights είναι versioned,
οι ισοβαθμίες λύνονται με stable IDs. Ratings διαφορετικών providers δεν
συγχωνεύονται ως ισοδύναμες κλίμακες· ελλείπον rating δεν γίνεται μηδέν.
Απόσταση χωρίς route provider είναι μόνο proximity estimate, όχι χρόνος διαδρομής.

Όρια πρώτου campaign: έως 60 unique shortlisted places, έως έξι candidates ανά
activity/area και μία στοχευμένη επέκταση για αποδεδειγμένο κενό. Τα 60 είναι cap,
όχι quota που γεμίζει με άσχετα μαγαζιά. Μεγάλη shortlist δημιουργεί visible
deferred queue, όχι απεριόριστη έρευνα όλης της πόλης.

| Input | Deterministic συμπεριφορά |
| --- | --- |
| Coffee once | Μία προαιρετική παύση κοντά στη διαδρομή· όχι όλα τα cafés |
| Coffee every day | Έως μία παύση ανά επιλεγμένη ημέρα, με πιθανή συγχώνευση σε breakfast/brunch |
| Brunch + coffee | Μία στάση με δύο labels όταν το μέρος υποστηρίζει και τα δύο |
| Breakfast at stay: provided | Stay-time block, χωρίς αυτόματο café ή supermarket |
| Breakfast at stay: buy supplies | Σύντομη προμήθεια κοντά στη διαμονή/διαδρομή· ελέγχεται για επαναχρησιμοποίηση σε επόμενες ημέρες |
| Breakfast at stay: unknown | Εκκρεμότητα και προαιρετική εναλλακτική· δεν υποθέτουμε ότι παρέχεται |
| Bakery/café breakfast | Επιλεγμένο service/meal context, όχι κάθε bakery ανεξαρτήτως προσφοράς |
| Optional activity χωρίς κατάλληλο μέρος | Alternative ή unsatisfied soft preference· όχι υποχρεωτικό λάθος stop |

Η συχνότητα καθημερινού καφέ δεν γίνεται νέο place tag. Είναι κανόνας trip
composition. Groceries/minimarket είναι typed place/service categories.

Map payload: plan, coffee, breakfast/brunch, restaurants, bars, sights, groceries.
Scopes: `according_to_plan`, `all_known_candidates`, με optional viewport και
distance limit. Το «όλα» σημαίνει όλα τα γνωστά αποτελέσματα του snapshot/ερωτήματος,
όχι εξαντλητική κάλυψη καταστημάτων της πόλης. Pending/candidate layers έχουν σαφή
σήμανση και δεν αναμειγνύονται με confirmed scheduled pins.

## 4. Πότε χρειάζεται provider ή Luna

| Πληροφορία | Διαδρομή τεκμηρίωσης | Περιορισμός |
| --- | --- | --- |
| Όνομα/branch/address | Existing receipts + Overture candidates + operator/Places evidence | Ίδιο όνομα ή domain μόνο του δεν αρκεί για branch |
| Coordinates/category/status | Configured Places adapter ή τεκμηριωμένη επίσημη πηγή | Source point δεν πιστοποιεί είσοδο |
| Hours/menus/prices | Operator structured fields / explicit feed / supplied page | Published schedule δεν εγγυάται μελλοντική λειτουργία |
| Travel time | Configured route adapter με mode, departure/arrival scope | Duration είναι provider estimate, όχι εγγύηση χρόνου |
| Date-specific tickets/table/event | Provider που όντως εκθέτει date/party availability | Απλό webpage/Places δεν υποκαθιστά αυτή τη δυνατότητα |
| Why choose / source recommendation | Ήδη reviewed transcript/detail | Διατηρείται ως recommendation, όχι current service |
| Δύσκολο source passage | Luna με συγκεκριμένα αποσπάσματα, schema και evidence IDs | Proposal only, χωρίς web search ή final adjudication |

Υπάρχουν ήδη operator HTTP/JSON-LD και configured JSON-feed adapters. Places και
Routes integration σε αυτό το pipeline **χρειάζεται υλοποίηση**, credentials,
capability mapping και ανεξάρτητο budget. Δεν περιλαμβάνουμε υποθετικές API κλήσεις
στο run σαν να είναι έτοιμες.

Το existing conflict Moco/MOOD γίνεται regression case. Structured JSON-LD δεν
κερδίζει αυτόματα έναντι αντικρουόμενης επίσημης visitor page. Η αυτόματη identity
admission θέλει approved provider ID ή explicit reviewed rule με συμβατό address,
coordinates και branch· conflict/rename/ASR alias παραπέμπεται χειροκίνητα.

Luna χρησιμοποιείται μόνο μετά από cache miss και αποτυχία απλού structured
mapping. Θέλουμε source text + permitted evidence IDs + schema + scope rules,
όχι prompt «διόρθωσε ό,τι λείπει». Αν η AI απόκριση αποτύχει content validation,
αποθηκεύεται το receipt και δημιουργείται handoff χωρίς ατέρμονα reprompt.

Freshness ανά πεδίο: αποθηκεύουμε observed_at, fetched_at, reviewed_at,
source applicability και recheck_due_at. Το cache TTL σημαίνει χρόνο ανανέωσης,
όχι χρονική εγγύηση αλήθειας. Availability αποθηκεύεται για την πραγματική
ημερομηνία/party/provider scope. Hard constraints μένουν unknown χωρίς επαρκή
τεκμηρίωση. Αντί για ανανέωση όλης της πόλης ανανεώνουμε shortlisted/selected fields.

## 5. Σύνθεση και validation χωρίς περιττό verification φόρτο

Νέος μικρός deterministic composer: fixed arrival/departure και locks →
day/area anchors → meal windows → optional pauses → alternatives. Επιλέγει από
ελεγχόμενα candidates, με stable tie-breaks και έως δύο repair rounds. Δεν
παραδίδουμε το constraint solving στο Luna.

Ο σημερινός `validate_stops` παραμένει ο αυστηρός έλεγχος των supplied dated facts.
Προστίθεται `validate_draft` με explicit policies, χωρίς να βαφτίζεται το strict
`needs_checks` ως verified:

- Draft: δηλωμένες duration/cost/route estimates επιτρέπονται, με αβεβαιότητα.
- Dated selection: opening-window applicability, booked anchors και required
  constraints ελέγχονται· published hours δεν γίνονται guaranteed availability.
- Allergy/access hard requirement: χωρίς applicable evidence δεν ικανοποιείται.
- Open park/free walk: δεν ζητάμε εισιτήριο, verified price ή building entrance
  όταν δεν απαιτείται από τη συγκεκριμένη στάση. Άγνωστο κόστος δεν γίνεται δωρεάν.
- Coffee/breakfast pause: budget range με basis/source, merge semantics και
  feasibility check· όχι τεκμηριωμένο πραγματικό ποσό αν δεν υπάρχει menu.

Τα states είναι `draft_with_estimates`, `needs_selected_checks`,
`invalid_constraints` και `validated_under_declared_policy`. Κανένα state δεν
σημαίνει booked ή εγγυημένη μελλοντική διαθεσιμότητα.

Αλλαγή preference/lock ενημερώνει μόνο εξαρτώμενα days, candidates, route edges και
cost totals. Cache keys περιλαμβάνουν place IDs, input/policy hashes και temporal
scope. Manual locks και αρχική user intent παραμένουν testable invariants.

Export `trip-view.json`: days/stops/alternatives, why choose, source tips,
dishes, historical context, budget rows, unresolved checks, map layers,
panel/table descriptors και media references με attribution. Το κοινό contract
χρησιμοποιείται από UI και guide export. Το script δεν υλοποιεί ολόκληρο το
UI ούτε δημιουργεί εικόνες χωρίς πραγματικό asset/provider.

## 6. Πραγματικά μετρήσιμη ολοκλήρωση

Fixed expected sets δημιουργούνται με manual source comparison πριν από την
αξιολόγηση. Δεν παράγουμε «σωστές απαντήσεις» από τα ίδια φίλτρα που εξετάζουμε.
Στο πρώτο pass ελέγχουμε τις 16 scenario families του manifest και αρνητικές
περιπτώσεις wrong subject/seafood→tapas/scenic→sunset/Moco branch conflict.
Τα scenario IDs είναι σχεδιασμός· test trips και expected sets πρέπει να γραφτούν.

| Gate | Στόχος | Τι αποδεικνύει |
| --- | --- | --- |
| Conservation/provenance/bindings | 100% | Η νέα διαδρομή δεν χάνει stored lineage |
| Known wrong-subject/fit regression | 0 | Συγκεκριμένα διορθωμένα λάθη δεν επιστρέφουν |
| Filter precision/recall | ≥95% στο fixed reviewed benchmark | Retrieval ορθότητα μόνο στο δηλωμένο test set |
| User locks/hard exclusions | 100% των regression cases | Ο έλεγχος τηρεί explicit inputs |
| Optional merge semantics | Όλα τα βασικά cases περνούν | Coffee/brunch και groceries δεν παράγουν διπλές στάσεις |
| Draft feasibility | Όλα τα scoped test plans ελέγχονται, με ρητά pending fields | Λειτουργεί η σύνθεση, όχι πραγματική availability |
| Real selected-trip checks | Report ανά stop/field | Καμία γενική «ready» ένδειξη χωρίς ημερομηνίες/providers |
| `chat.md` parity | Manual rubric για detail, alternatives, locality, tables/maps/panels | Coverage των απαιτήσεων, όχι αυτόματη εγγύηση καλύτερου UX |

Ο ίδιος compiler/ranking τρέχει για παλιά και νέα source editions με σταθερό
reference χρόνο και ίδιο policy. Η παλιά βάση δεν δανείζεται τις νέες manual
admissions. Μετράμε ξεχωριστά την επίδραση source correction, taxonomy mapping και
νέας provider evidence. Οι διορθωμένες source IDs/cues συγκρίνονται με occurrence
lineage, όχι με IDs που μεταβάλλονται όταν αλλάζει το περιεχόμενο.

Δεν υπάρχει «95% dataset accuracy» metric. Το ήδη μετρημένο 97,93% παραμένει
editorial admission coverage. Το νέο ≥95% αφορά μόνο precision/recall σε fixed
reviewed cases, με δημοσίευση numerator/denominator και gaps. Δεν μειώνουμε το
benchmark όταν υπάρχουν μη υποστηριζόμενα activities. Coverage gaps αναφέρονται
ανεξάρτητα από precision και preservation.

## 7. Run control, budget και τελικό handoff

Επεκτείνουμε με wrapper τα υπάρχοντα durable queue, receipts, reservation και
deadline primitives. Τα frozen παλιά engines/ledger δεν ξαναγράφονται. Job key:
input hash + stage + policy/provider version + temporal scope. Attempt receipt
αποθηκεύεται πριν από semantic parsing. Restart επαληθεύει output hashes.

Για πληρωμένες κλήσεις το crash μετά το dispatch δεν σημαίνει δωρεάν retry:
η reservation παραμένει· ambiguous dispatch παραπέμπεται ή χρησιμοποιεί provider
idempotency όπου αυτή υπάρχει. Δεν υποσχόμαστε exactly-once inference χωρίς τέτοια
δυνατότητα. Μία τοπική campaign lock αποκλείει διπλό runner.

429/Retry-After δίνει provider cooldown χωρίς πρόωρο retry. Fallback 15/30/60s,
έως τέσσερις attempts, heartbeat 15s, sleep slices έως 30s. Μεγάλο Retry-After
διατηρεί το πραγματικό retry_at· αν υπερβαίνει το campaign deadline, σημειώνεται
deferred. Content errors, auth failures και unsupported capabilities δεν
αντιμετωπίζονται ως transient network errors.

Τερματισμός campaign μετά από 12 ώρες connected wall time ή όρια προϋπολογισμού,
με αποθηκευμένο queue. Κανένα απεριόριστο wait/repair loop. Independent offline
evaluation συνεχίζεται και αναφέρει missing-provider gates.

Προτεινόμενο συντηρητικό όριο νέου Luna campaign: $0,75 και έως 20 κλήσεις,
πάντα μέσα στο υφιστάμενο shared ceiling $15 και αφού διαβαστεί ο πραγματικός
τρέχων ledger. Το τελευταίο audit είδε $13,3432175 reserved, όχι actual billing.
Το offline κοστίζει μηδέν. Έως 150 physical HTTP requests και 30 νέες operator
pages· redirects/robots/retries μετρούν. Νέες paid Places/Routes κλήσεις default
$0 μέχρι να καθοριστούν provider και ξεχωριστό budget. Δεν χρειάζεται μεγάλο
νέο AI budget για το βασικό integration.

Παραδοτέα ανά campaign:

```text
manifest.json, queue.sqlite, receipts/
compiled-dataset.sqlite, retrieval-before.json, retrieval-after.json
identity-decisions.json, operational-observations.json
plans/, trip-view.json, map-layers.json
conservation.json, regressions.json, metrics.json
manual-handoff.json, report.md, status.json
```

Handoff entry: subject ID, ακριβής ερώτηση/σύγκρουση, evidence refs, επίδραση σε
selected scenario, απαιτούμενος provider ή manual action. Οι 42 held claims δεν
γίνονται υποχρεωτικά blockers εφόσον δεν χρειάζονται για το επιλεγμένο plan.

Τελικές ενδείξεις χωριστά: queue_drained, offline_audit_passed,
retrieval_benchmark_passed, draft_scenarios_passed, selected_trip_checks_complete,
ui_contract_validated, publication_ready. Το queue_drained δεν συνεπάγεται κανένα
από τα υπόλοιπα. Η private edition παραμένει candidate μέχρι να περάσουν τα
δηλωμένα integration gates· αποδοχή γίνεται με ξεχωριστή atomic selector update
που ελέγχει ότι η αρχική επιλογή δεν άλλαξε. Remote publication δεν αποτελεί
ενέργεια αυτού του runner.

## Σειρά υλοποίησης και τελικό όριο scope

1. Reader/contracts/registry migration + source preservation και filter tests.
2. Deterministic retrieval/activity composition + μικρός draft composer και
   trip-view contract, χωρίς νέα network dependencies.
3. Campaign wrapper με retry/resume/status και shortlist evidence jobs.
4. Χειροκίνητα expected sets, πραγματικό πριν/μετά και bounded handoff.
5. Places/Routes adapters μόνο αν τα μετρημένα gaps τα απαιτούν, με provider
   capability tests και ρητό budget πριν από connected execution.

Αυτό ολοκληρώνει το συγκεκριμένο integration campaign. Δεν επαναλαμβάνουμε
ολόκληρο το video pipeline, δεν επεκτείνουμε σε όλες τις πόλεις, δεν ξαναγράφουμε
το UI και δεν προσθέτουμε νέες δραστηριότητες έξω από το υπάρχον registry σε αυτό
το pass. Αργότερα αλλάζει provider ή UI category μέσω adapter/registry και
στοχευμένων invalidations, αντί για επανάληψη όλης της βάσης.
