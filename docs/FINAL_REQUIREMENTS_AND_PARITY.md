# Trippy: τελικές απαιτήσεις και έλεγχος συμφωνίας

Ημερομηνία: 30/10/2026. Ενσωματώνει τις τελευταίες διευκρινίσεις του χρήστη. Ο αρχικός parity έλεγχος ήταν documentation-only. Υλοποιήθηκαν τοπικά τα Stages 0–2: baseline/configuration, normalized model/compatibility και authenticated API/durable fake worker/budgets· βλ. IMPLEMENTATION_STATUS.md. UI integration, full connected verification, remote migrations και full catalog enrichment παραμένουν εκκρεμή. Το Luna-only extraction pilot και η bounded v2 quality evaluation εκτελέστηκαν· δεν έγινε publication.

Stage 3 basic inventory και source-preparation tooling υλοποιήθηκαν τοπικά. Νεότερη κατεύθυνση: [VIDEO_SOURCE_RESEARCH.md](VIDEO_SOURCE_RESEARCH.md). Ελεγχόμενη Greek/English/both video discovery, editable source languages ανεξάρτητα από country/output language, broad city orientation και queries ανά input dimension, manual user video links μαζί με notes και permitted timestamped transcript evidence. Η source/evidence coverage οδηγεί την επιλογή· προηγούμενα “20/15 ανά category” γίνονται optional gap benchmarks, χωρίς padding. Free discovery/local preparation δεν εγγυάται arbitrary public video transcripts ή δωρεάν Luna inference. A live 20-video source batch was acquired; local ASR produced 19 structurally emitted evidence files and one failure. Quality curation remains outstanding. The new creator defaults include Tasos Dousis, Eftychis/Happy Traveller, Tripment, Patrick Guide Barcelona, Happy to Wander, Spain Revealed, Rick Steves and Wolters World, with official channel IDs and statistics snapshots. The new creator batch has 24/24 receipt-audited video transcripts and 43 prepared extraction chunks. Structured evidence extraction, branch-aware review drafts and Overture proposals are implemented (TRANSCRIPT_EXTRACTION.md); bounded Luna-only extraction and v2 quality evaluation have executed. Resolved identities, exhaustive semantic/source coverage, final curated selection and UI integration remain pending. Bulk extraction is blocked by the new reviewed quality gate (EXTRACTION_QUALITY_GATE.md).

## Ποιο πλάνο ακολουθούμε

Latest connected verification: YouTube discovery and read-only Supabase DB/Auth health checks pass; public schema still has no app tables, migration revision, or PostGIS. Twenty raw videos were discovered without statistics ranking; audio is downloaded and local CPU transcription ended with 19 evidence outputs and one failure. Quality review remains outstanding. Luna-only place extraction has now been evaluated on two complete videos. No remote migration/data write, real user/RLS session, or publication has occurred. See IMPLEMENTATION_STATUS.md and the source-selection audit.

Αυτό το έγγραφο υπερισχύει για τις τελικές διευκρινίσεις, το scope και το σημερινό setup. Το [IMPLEMENTATION_AGREEMENT_PLAN.md](IMPLEMENTATION_AGREEMENT_PLAN.md) ορίζει το υπόλοιπο stack και product agreement. Το [AUTOPILOT_STAGED_IMPLEMENTATION.md](AUTOPILOT_STAGED_IMPLEMENTATION.md) είναι η μοναδική ενεργή σειρά υλοποίησης. Οι ειδικές specifications εξειδικεύουν αυτές τις αποφάσεις. Παλιότερα manual-only scope, πίνακες implementation status και provider/model prices είναι ιστορικά snapshots, όχι τρέχουσες εντολές ή νέες μετρήσεις.

## UI και τρόπος υλοποίησης: νεότερη διευκρίνιση χρήστη

Νεότερη συμφωνία: Barcelona πρώτη έκδοση **500 curated/enriched επιλογές, Luna μόνο**. Δεν χρησιμοποιείται Sol ως automatic fallback/audit. Αμφίβολα στοιχεία μένουν unknown ή review-needed. Raw inventory παραμένει χωριστό. Για UI κύριο native skill είναι πλέον το [Wholiver SwiftUI Design Skill](https://github.com/Wholiver/swiftui-design-skill/blob/main/SKILL.md), με επίσημη Liquid Glass τεκμηρίωση, iOS 27 availability/build checks και οργανωμένο intuitive flow· frontend-design παραμένει συμπληρωματικό. Βλ. UI_DESIGN_DIRECTION.md.

Ο χρήστης εννοεί autopilot από τον agent, σε stages, όχι παράδοση σε Copilot. Τελικό UI περίπου στη σημερινή διάταξη, με question/reimagine κάθε στοιχείου όταν υλοποιείται. Φιλοσοφία: minimalism + επιλογές/customization + personalization, modern clean design και σωστό alignment. Native SwiftUI Design Skill και συμπληρωματικό GitHub frontend-design σύμφωνα με τη νεότερη εντολή παραπάνω. Χωρίς emoji ή διακοσμητικά AI-like icons. Εφαρμογή: [UI_DESIGN_DIRECTION.md](UI_DESIGN_DIRECTION.md), αποτελέσματα stages: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

## 1. Κάθε προτίμηση γίνεται συγκεκριμένη οδηγία στο prompt

### Νεότερη επιλογή catalog από πραγματικές προτάσεις

Η αρχική technical shortlist των 500 δεν είναι αποδεκτή ως curated επιλογή. Νεότερη κατεύθυνση χρήστη: πραγματικές lists/articles/YouTube και TikTok/Instagram/Google Maps/ενδεχομένως Tripadvisor οδηγούν candidate discovery· η μεγάλη Overture βάση χρησιμεύει για matching και broad practical retrieval. Δεν περιοριζόμαστε σε αυτήν και δεν παράγουμε mainstream top lists από AI memory. Απαιτούνται ελάχιστα coverage targets ανά κύρια category/common subtype, χωριστά bars/clubs και museums/sights, με πραγματικές πηγές και fact-checking. ~500 initial enriched target, Luna μόνο· τα προηγούμενα technical quotas δεν δεσμεύουν τη σύνθεση.

Free-text “Πρόσθεσε τύπο” διατηρεί απρόβλεπτα interests. Fast food κοντά σε σχετική περιοχή ανακτάται από broad inventory, ενώ niche style requests αναζητούν published evidence ή οδηγούν σε bounded on-demand research. Source recommendations και authoritative factual verification διαχωρίζονται. Συγκεκριμένη στρατηγική και proposed minima: [SOURCE_LED_CATALOG_SELECTION.md](SOURCE_LED_CATALOG_SELECTION.md). Αυτές είναι απαιτήσεις προς υλοποίηση, όχι ήδη διαθέσιμη source pipeline ή client flow.

Οι κατηγορίες και τα local pills παραμένουν stable IDs στο normalized brief. Επιπλέον, κάθε επιλογή αντιστοιχεί σε versioned φυσική οδηγία που ο compiler ενσωματώνει στο πραγματικό prompt. Δεν αρκεί να αποστέλλονται μόνο labels σε JSON. Τα IDs εξυπηρετούν retrieval/validation· οι οδηγίες εξηγούν στο AI τι ζητά ο ταξιδιώτης και πώς ταιριάζει στο συγκεκριμένο ταξίδι.

Registry: `preference_id`, `parent_family`, `template_key`, `template_version`, localized label και semantic instruction. Το published city profile συνδέει τα local pills με ελεγμένα templates και πραγματικούς candidates. AI-generated labels δεν γίνονται ανεξέλεγκτες executable instructions. Νέα κατηγορία χρησιμοποιεί το κοινό template family και συγκεκριμένη περιγραφή intent μέχρι να αποκτήσει δικό της reviewed template.

Ο compiler συνθέτει: κοινές οδηγίες/source policy → normalized context → όλες τις selected category/concept instructions → task-specific scope → bounded evidence/candidates → output contract. Η ακριβής σειρά του reusable prefix προσαρμόζεται στον provider χωρίς να αλλάζει η σημασιολογία. Το ίδιο compiled instruction bundle χρησιμοποιείται από backend, developer dry-run και manual iOS prompt, με ένα source of truth και version metadata· offline iOS χρησιμοποιεί versioned bundled fallback του ίδιου registry.

Κοινό κείμενο σε κάθε personalized research task:

```text
Οι επιλεγμένες κατηγορίες είναι συνδυαζόμενες προτεραιότητες έρευνας και
εμπειριών για αυτό το ταξίδι. Δεν είναι αποκλειστική λίστα επιτρεπόμενων θεμάτων.
Ερεύνησε και κάθε άλλη χρήσιμη επιλογή ή πρακτική πληροφορία που συνδέεται
με τον προορισμό, τη διαδρομή και τις ανάγκες της παρέας. Μη διαγράψεις ούτε
υποβαθμίσεις άλλο ζητούμενο module λόγω επιλογής Φαγητού, Καφέ ή Αξιοθέατων.
Εφάρμοσε πραγματικά hard constraints, must-see/avoid και user locks· unknown
παραμένει unknown. Μην υποθέσεις ότι κάθε γεύμα/στάση πρέπει να υπηρετεί όλα
τα interests ούτε ότι μη επιλεγμένη κατηγορία απαγορεύεται. Προσαρμόζεις την
έμφαση και την ποικιλία στη διάρκεια, στο pace και στο διαθέσιμο budget.
```

| Επιλογή | Οδηγία που μπαίνει στο prompt, μαζί με το πραγματικό context |
|---|---|
| Φαγητό | «Ερεύνησε διαφορετικές επιλογές γευμάτων που ταιριάζουν στην παρέα, στη διατροφή και στο budget με τη δηλωμένη βάση του. Συνδύασε τοπική κουζίνα και χρήσιμες εναλλακτικές κοντά στις περιοχές/διαδρομές του ταξιδιού. Σύγκρινε ύφος, τεκμηριωμένες τιμές, ανάγκη κράτησης και meal context. Μην περιορίσεις την υπόλοιπη έρευνα σε εστιατόρια.» |
| Καφές | «Ερεύνησε καφέ και κατάλληλες στάσεις ανάπαυσης στο πλαίσιο των περιοχών και της διαδρομής. Εφάρμοσε επιλεγμένα styles και γνωστές ανάγκες της παρέας, δώσε διαφορετικές επιλογές και εξήγησε πότε/πού ταιριάζουν. Μην επιβάλλεις στάση καφέ κάθε ημέρα ούτε αποκλείσεις άλλα drinks ή δραστηριότητες.» |
| Αξιοθέατα | «Ερεύνησε χαρακτηριστικά αλλά και λιγότερο προφανή αξιοθέατα που ταιριάζουν στα interests, στις ηλικίες, στην κινητικότητα και στον χρόνο. Σύγκρινε εμπειρία, περιοχή, διάρκεια ως estimate όπου χρειάζεται, εισιτήριο και dated check state. Κράτησε alternatives και χρήσιμο ευρύτερο context, χωρίς να περιορίσεις το ταξίδι μόνο σε landmarks.» |
| Μουσεία | «Ερεύνησε διαφορετικά μουσεία/γκαλερί και σχετικές εκθέσεις σύμφωνα με τα πολιτιστικά interests και τις ημερομηνίες. Ξεχώρισε μόνιμη συλλογή από dated event, ticket eligibility από εκτίμηση και known opening από unknown.» |
| Bars / Clubs | «Ερεύνησε χωριστά bars και clubs, με επιλεγμένο style, περιοχή, ηλικιακούς κανόνες όπου τεκμηριώνονται, late-night μεταφορά και trade-offs. Είναι optional nightlife experiences, όχι υποχρεωτικό πρόγραμμα για όλη την παρέα ή κάθε βράδυ.» |
| Φύση / Εκδρομές | «Ερεύνησε φύση και εκδρομές εντός ρεαλιστικού εύρους από την πόλη βάσης. Σύγκρινε πρόσβαση/επιστροφή, διαθέσιμο χρόνο, walking effort, εποχικότητα και τεκμηριωμένους περιορισμούς. Πρότεινε ως εναλλακτικές έναντι city days, χωρίς αυτόματη αντικατάστασή τους.» |
| Αγορές | «Ερεύνησε markets, τοπικά καταστήματα και shopping experiences σύμφωνα με τα interests/budget και τις περιοχές. Ξεχώρισε shopping από food-market experience· ίδιο μέρος μπορεί να υπηρετεί περισσότερα purposes χωρίς διπλή εγγραφή.» |
| Events | «Ερεύνησε events για τις πραγματικές ημερομηνίες και interests. Ξεχώρισε confirmed occurrences, unpublished future windows και not_found από μη ύπαρξη. Μην μπλοκάρεις την υπόλοιπη έρευνα αν το ημερολόγιο είναι ελλιπές.» |

Παράδειγμα local pill: `specialty_coffee` προσθέτει «Στις επιλογές καφέ δώσε έμφαση σε τεκμηριωμένα specialty coffee venues στις σχετικές περιοχές, με broader cafe alternatives όπου η κάλυψη είναι μικρή». Το `fast_food` αφορά meal contexts, το `ruin_bar` nightlife contexts. Συνδυάζονται χωρίς να γίνουν global hard filters. Explicit «μόνο vegan» ή allergy constraint διατηρεί τη δηλωμένη αυστηρότητά του.

Στο shared city seed δεν περνά private trip context: οι ίδιες semantic families εξηγούν τι ερευνά κάθε bounded catalog task χωρίς να αποκλείουν candidates βάσει συγκεκριμένου ταξιδιώτη. Το task scope περιορίζει την εργασία του batch, όχι όλη την έρευνα του χρήστη. Εμφανίζουμε compiled prompt preview και unresolved preferences· δεν χάνονται άγνωστα IDs σιωπηρά.

## 2. Κεντρική αναζήτηση pin και προσθήκη μετά το research

Δύο χωριστές λειτουργίες: (α) άνοιγμα κάθε δραστηριότητας σε Apple/Google Maps για προβολή ή οδηγίες, (β) κεντρικό «Αναζήτησε μέρος» μέσα στο Trippy με MapKit. Η δεύτερη είναι μέρος του MVP και δεν χρειάζεται νέα AI έρευνα ή Google Places API για την απλή αναζήτηση.

Κοινό search sheet από Places, τον χάρτη και «Πρόσθεσε/άλλαξε δραστηριότητα». Αναζητά πρώτα στη δική μας διαθέσιμη βάση και προσφέρει Apple Maps search με `MKLocalSearch` για όνομα/κατηγορία/περιοχή και geographic context. Τα αποτελέσματα εμφανίζονται σε list + pins· ο χρήστης επιλέγει το ακριβές αποτέλεσμα/branch. Map viewport bias δεν θεωρείται απόλυτο geographic filter.

Ροή: search → selected pin preview → identity/deduplication → «Αποθήκευση στα μέρη μου» ή «Προσθήκη στο ταξίδι» → επιλογή υπάρχοντος slot ή νέας δραστηριότητας. Για υπάρχον slot διατηρούνται purpose, ID, alternatives και locks· νέα user selection κάνει scoped feasibility update. Μπορεί να αποθηκευτεί χωρίς να προγραμματιστεί.

Αν υπάρχει canonical match, αποθηκεύουμε owner-scoped reference και προσωπικά notes. Αν λείπει, δημιουργούμε private user place με stable Trippy ID/owner, match status και permitted source references. Η προσωπική βάση υλοποιείται ως owner-scoped tables μέσα στο ίδιο Supabase, όχι δεύτερη DB. Προώθηση στον κοινό catalog είναι ξεχωριστό validated/admin publishing step· δεν γίνεται public ένα προσωπικό pin αυτόματα.

Διαθέσιμα `MKMapItem` fields προς αξιολόγηση: name, address/location/coordinates, POI category, website, phone, timezone και identifier όπου παρέχεται/υποστηρίζεται. Η απουσία identifier δεν εμποδίζει private record: official domain/address/location βοηθούν matching, με ambiguity review. Search fields, user-entered notes και independently sourced facts κρατούν χωριστή provenance. Δεν συλλέγουμε όλο το result payload ή place-card περιεχόμενο.

Η τεχνική διαθεσιμότητα field δεν αποδεικνύει δικαίωμα μόνιμης αντιγραφής. Στο stage 0 καταγράφονται οι applicable Apple terms, permitted persistence/attribution/retention ανά field και deployment availability. Ο adapter αποθηκεύει μόνο αυτά που επιτρέπονται· fallback είναι user-owned annotation και permitted reference, με επανέλεγχο ή open/official source όπου χρειάζεται. Δεν υπόσχεται full Apple inventory export.

Pin selection δεν επιβεβαιώνει opening, prices, rating ή booking. Ελλιπή facts δεν εμποδίζουν την αποθήκευση/προσθήκη· το slot μένει provisional όπου χρειάζεται. Προαιρετικός επανέλεγχος γίνεται χωριστά και δεν ενεργοποιείται paid AI/provider call από ένα απλό Save.

Επίσημες τεχνικές πηγές ελέγχθηκαν σε αυτό το turn: [MKLocalSearch](https://developer.apple.com/documentation/mapkit/mklocalsearch), [MKMapItem](https://developer.apple.com/documentation/mapkit/mkmapitem). Η τεκμηρίωση επιβεβαιώνει search/results και τα παραπάνω attributes, όχι ολοκληρωμένο persistence-policy audit. Native MapKit χρησιμοποιείται για το pilot χωρίς νέο Google billing setup ή assumed per-pin API charge· δεν μεταφέρουμε τα quotas του Server API/MapKit JS στο native framework.

## 3. Reviews σημαίνει μόνο αστέρια στα 5

Στο προϊόν «reviews» σημαίνει sourced numerical rating `/5`. Δεν περιλαμβάνει review texts, sentiment summaries ή quality-decline analysis. Review count είναι προαιρετικό provenance/context field και legacy compatibility, όχι επιπλέον απαιτούμενο research module. Hotel classification stars δεν είναι user rating και δεν συγχέονται με αυτό.

Μπορούμε να πάρουμε rating snapshot από την ίδια τρέχουσα AI έρευνα, όταν το συγκεκριμένο venue/branch, η αριθμητική τιμή και η πηγή είναι αναγνωρίσιμα και το source/grounding agreement επιτρέπει extraction, storage και το προβλεπόμενο display. Δεν χρειάζεται ξεχωριστή ratings API κλήση ή υποχρεωτικό refresh για να γεμίσει η κάρτα. Αυτό δεν κάνει δωρεάν το ίδιο το AI/search run και δεν παρακάμπτει restrictions επειδή το αποτέλεσμα πέρασε από AI.

Snapshot fields: `entity_id`, `rating_value`, `rating_scale=5`, `platform`, `source_url/source_id`, `research_run_id`, `observed_at`, `verification_status`, `retention_until` όπου επιβάλλεται. `observed_at` γράφεται από πραγματικό retrieval/import metadata· η ημερομηνία import δεν παριστάνει τη retrieval date όταν η παλιά έρευνα δεν την αποδεικνύει. Το AI δεν γράφει τη σημερινή ημερομηνία για παλιό αποτέλεσμα.

Display: **4,6/5 · Πηγή · ελέγχθηκε [ημερομηνία]**, με snapshot/stale state και source detail. Χωρίς evidence ή permitted use, τιμή unknown και link όπου επιτρέπεται. Αν υπάρχει μόνο μη ελεγμένο imported claim, δεν εμφανίζεται ως confirmed score. Άλλη scale παραμένει στην raw permitted evidence, χωρίς αυθαίρετη μετατροπή σε `/5`. Δεν κάνουμε average διαφορετικών platforms. AI fit score/editorial recommendation είναι άλλο πεδίο και ποτέ αστέρια χρηστών.

Freshness και retention διαφέρουν: επιτρεπόμενο παλιό snapshot μπορεί να εμφανίζεται ως παλιό· expired restricted content αφαιρείται σύμφωνα με source policy. Δεν καταγράφουμε νέο observed time όταν απλώς διαβάζουμε το cache. Δεν σχεδιάζεται universal Google rating mirror ή text-review dataset.

## 4. Supabase: δημιουργημένο project, σύνδεση εκκρεμεί

Ο χρήστης δημιούργησε Supabase **Free** project: `https://zsecfyracbhhvxvzgvfw.supabase.co` (project ref `zsecfyracbhhvxvzgvfw`). Το project URL δεν είναι secret. Αυτό επιβεβαιώνεται από τη δήλωση του χρήστη· δεν έγινε remote inspection, σύνδεση ή migration σε αυτό το turn. Region, Auth, PostGIS, tables/RLS και connection details δεν έχουν επαληθευτεί.

Στο stage 0 ετοιμάζουμε `.env.example`, local configuration validation και connection instructions. Connected stage χρειάζεται publishable/anon key για το επιλεγμένο auth flow και backend-only connection credentials κατάλληλα για migrations/runtime. Privileged secret/service credentials χρειάζονται μόνο για τις trusted operations που επιλέγονται, δεν λειτουργούν ως user authorization και δεν μπαίνουν σε iOS/public Git/chat. Η έλλειψη credentials δεν εμποδίζει local code, dry-runs και offline tests.

Pilot status 29/10/2026: local Barcelona catalog με 41.461 βασικές source records, 500 preliminary shortlist και 0 enriched, migration `0003`, ~105 MB SQLite. Local API/worker και catalog publication υπάρχουν· connected Supabase storage/egress/Auth/RLS και free-plan pause handling δεν επαληθεύτηκαν. Το remote Free project δεν περιέχει αποδεδειγμένα αυτό το dataset. Δεν ενεργοποιήθηκαν paid Render/AI υπηρεσίες. Paid pilot cap €10 παραμένει πρόταση, όχι ήδη δοσμένη άδεια χρέωσης. Βλ. [CATALOG_STAGE_3.md](CATALOG_STAGE_3.md).

## 5. Έλεγχος parity και αποδεκτά όρια

| Έγγραφο | Ρόλος / διόρθωση συμφωνίας |
|---|---|
| `PRODUCT_AND_DEVELOPMENT_PLAN.md` | Διατηρεί product/design απαιτήσεις. Manual-only baseline και παλιά tasks σημειώνονται ως ιστορικά· ενεργό scope είναι shared catalog + backend + customization. |
| `RESEARCH_DATA_AND_SOURCE_STRATEGY.md` | Field-level evidence, import, calendar/customization παραμένουν. Παλιά «no Foundry integration», weather και μοντέλα/τιμές είναι dated snapshots. Ratings policy είναι sourced `/5` snapshots. |
| `DESTINATION_DATABASE_REDESIGN.md` | Shared catalog + private trips παραμένουν. Local migrations/API/admin gate και Stage-3 basic inventory/publishing υλοποιήθηκαν. Supabase connection/remote migrations και web admin UI εκκρεμούν. |
| `CATALOG_PROMPTING_AND_LIVE_DATA_PLAN.md` | Compiler + bounded scheduler παραμένουν. Προστίθενται semantic preference instructions και permitted rating snapshots στο υπάρχον research. |
| `LOCAL_DISCOVERY_AND_GOOGLE_LIVE_INTEGRATION.md` | Dynamic pills/history/progressive jobs παραμένουν. Text reviews/sentiment δεν είναι product requirement· Google είναι optional. |
| `ACTIVITY_OPTIONS_AND_SELECTIONS.md` | Options/locks παραμένουν. Κεντρικό search/save pin είναι core flow. Slot tables είναι activity-domain specialization του κοινού decision model, όχι δεύτερο selection system. |
| `INTERNAL_RESEARCH_PROMPT_BANK.md` | Bounded catalog templates παραμένουν, με semantic category intent. Προστίθεται σύνδεση με κοινό personalized preference bundle και rating snapshot rule. |
| `PROMPT_RESEARCH_AUDIT.md` | Παραμένει audit της αρχικής συνομιλίας και prototype gaps, όχι ενεργό backlog ή σημερινή runtime certification. |
| `ASSET_GENERATION_PROMPTS.md` | Παραμένει decorative artwork specification· δεν αλλάζει και δεν αντικαθιστά real venue imagery/source rights. |
| `IMPLEMENTATION_AGREEMENT_PLAN.md` | Κοινό stack/product agreement με ενημερωμένο Supabase status και ρητή σύνδεση με τις τελικές απαιτήσεις/ενεργά stages. |

Τα παραπάνω schema table names ήταν ενδεικτικά διαφορετικών revisions. Stage 1 παγιώνει ενιαίο naming: κοινό canonical entity core με typed domain records, κοινό decision/option/selection core με activity specialization, owner-scoped user places. Δεν εγκαθιστούμε παράλληλους ανταγωνιστικούς πίνακες για το ίδιο state. Τα παλιά v1/patch imports διατηρούνται με adapters.

Acceptance του redesign: κάθε selected preference παράγει contextual φυσική οδηγία χωρίς global category exclusion· mixed interests και unknown preferences δεν χάνονται· search μετά το research προσθέτει νέο pin χωρίς AI call· ίδια ταυτότητα δεν δημιουργεί duplicates· private places δεν διαρρέουν σε άλλο χρήστη/shared catalog· venue swap διατηρεί slot/options/locks και derived updates· `/5` snapshot έχει source/time και ποτέ fabricated ή live label· existing edits/imports επιβιώνουν· weather εκτός MVP· paid calls μόνο με explicit cap/authorization.
