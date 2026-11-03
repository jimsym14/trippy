# Trippy: δυναμικές προτιμήσεις πόλης και διατηρούμενες επιλογές ανά δραστηριότητα

> Ενεργό πλάνο 29/10/2026: [τελικές απαιτήσεις και parity](FINAL_REQUIREMENTS_AND_PARITY.md), [κοινό implementation agreement](IMPLEMENTATION_AGREEMENT_PLAN.md) και [μοναδική σειρά stages για autopilot](AUTOPILOT_STAGED_IMPLEMENTATION.md). Οι τελευταίες απαιτήσεις περιλαμβάνουν semantic prompts ανά προτίμηση, κεντρική MapKit αναζήτηση/ιδιωτική αποθήκευση pin και sourced rating snapshots μόνο `/5`. Supabase Free project δημιουργήθηκε από τον χρήστη· σύνδεση/migrations δεν επαληθεύτηκαν. Παλιά scope/status/task lists είναι ιστορικά όπου διαφέρουν· οι ειδικές λεπτομέρειες του παρόντος παραμένουν όταν συμφωνούν.

Ημερομηνία: 29 Οκτωβρίου 2026. Εξειδίκευση του προηγούμενου πλάνου μετά τις διευκρινίσεις του χρήστη. Πρόκειται για data/product specification, όχι εφαρμοσμένη αλλαγή στο runtime.

## Απόφαση προϊόντος

Η εφαρμογή έχει τρία επίπεδα επιλογής:

1. **Τι θέλω να ζήσω στην πόλη:** δυναμικά city-level preference pills, όπως fast food, seafood taverns, local dishes, ruin bars, specialty coffee.
2. **Πότε/πού ταιριάζει στο ταξίδι:** activity slots ανά ημέρα, π.χ. lunch κοντά στη διαδρομή ή bar το βράδυ.
3. **Ποιο συγκεκριμένο μέρος επιλέγω:** κάθε slot έχει contextual candidate pool, AI recommendation και user selection που μπορεί να κλειδωθεί χωρίς να αφαιρεί άλλες επιλογές.

Τα examples εδώ είναι ενδεικτικά UI/data examples, όχι επιβεβαιωμένες δηλώσεις ότι συγκεκριμένη πόλη έχει ένα style ή venue.

## City-level preference pills

Το destination profile και ο published κατάλογος καθορίζουν τις σχετικές επιλογές της φόρμας. Δεν απαιτείται ο χρήστης να έχει πρώτα δημιουργήσει itinerary και δεν χρειάζεται online AI call για κάθε render.

Για κάθε concept κρατάμε city/country scope, localized label, aliases, parent family, eligible candidate counts, area spread, supporting evidence και publication/version. Το AI enrichment μπορεί να ενημερώνει το city profile και να προτείνει concepts από επιτρεπόμενες πηγές. Κανονικός κώδικας υπολογίζει counts/coverage και το input API διαβάζει published data.

Παράδειγμα: αν μια πόλη έχει επαρκείς τεκμηριωμένες επιλογές seafood taverns, το input προσφέρει σχετικό pill. Δεν αρκεί να έχει description ένα συγκεκριμένο seafood restaurant· πρέπει το concept να ανήκει στο discovery profile της πόλης και να συνδέεται με πραγματικό pool.

Selected pills συνδυάζονται με άλλες προτιμήσεις (μουσεία, βόλτες, excursions). `fast_food + ruin_bar` σημαίνει soft priorities σε meal/nightlife contexts, όχι ότι κάθε γεύμα γίνεται fast food ή κάθε δραστηριότητα bar. Το σχετικό slot μπορεί να έχει primary concept και optional broader fallback family. Μελλοντική ρύθμιση frequency/strength (π.χ. once/prefer_often) υπάρχει μόνο αν βοηθά πραγματικά τη λήψη απόφασης.

Τα food και nightlife pills είναι ανεξάρτητα preference dimensions. Αν ένα style δεν έχει eligible records στη συγκεκριμένη πόλη, δεν προβάλλεται ως επιβεβαιωμένη τοπική επιλογή. Μπορεί να υποστηρίζεται free-text επιθυμία που ενεργοποιεί targeted research, με σαφές unresolved state.

## Activity slot και candidate pool

Η δραστηριότητα έχει stable `slot_id`, ανεξάρτητο από τον index της ημέρας ή το επιλεγμένο venue. Διατηρεί purpose/concepts/date/time window/area/context ακόμη και όταν αλλάζει το μαγαζί.

Προτεινόμενοι πίνακες:

| Πίνακας | Ρόλος |
|---|---|
| `trip_activity_slots` | Date, order, purpose, concept IDs, time window, duration/budget assumptions. |
| `slot_option_sets` | Versioned pool scope, retrieval criteria, previous/next context και completeness. |
| `slot_candidates` | Many-to-many σύνδεση option set ↔ canonical place ID, score/reasons/eligibility/check refs. |
| `slot_selections` | Selected place, suggested place, user/AI owner, selection lock, revision. |
| `selection_history` | Undo και προηγούμενες user choices, χωρίς αντιγραφή restricted provider content. |

Τα candidate facts παραμένουν στο κοινό catalog/observation layer. Δεν αντιγράφουμε ολόκληρο venue JSON σε κάθε ημέρα. Ένα venue μπορεί να είναι candidate για πολλά slots, ενώ το selected venue δεν προγραμματίζεται αυθαίρετα πολλαπλές φορές.

Παράδειγμα σχεδιαστικού overlay:

```json
{
  "slot_id": "trip-slot-lunch-03",
  "purpose": "lunch",
  "concept_ids": ["fast_food"],
  "option_set_id": "options-lunch-03-v1",
  "ai_suggested_place_id": "place-a",
  "selected_place_id": "place-b",
  "selection_owner": "user",
  "selection_locked": true,
  "time_locked": false
}
```

Το option set διατηρεί τα `place-a`, `place-b`, `place-c` και άλλα candidates. Το `place-b` είναι επιλεγμένο, όχι η μοναδική εγγραφή που απομένει. Κανένα από τα παραπάνω IDs δεν αντιστοιχεί σε νέο πραγματικό researched venue.

## Ranking με βάση τη δραστηριότητα

Κάθε slot ανακτά επιλογές που ταιριάζουν στο δικό του purpose και στα selected concepts. Hard filters: category/style όπου απαιτείται, date/time operation, explicit avoid/revisit choices, critical accessibility/dietary requirements και γνωστή feasibility. Unknown constraints παραμένουν σημειωμένα, όχι confirmed.

Soft ranking: preference fit, prior/next-stop travel impact, area, budget, visit duration, editorial evidence, user likes και novelty/diversity. Rating είναι optional permitted signal. Αποστάσεις ευθείας δεν παρουσιάζονται ως πραγματικός χρόνος μετάβασης.

Η αναζήτηση alternatives αγκυρώνεται στο **slot purpose και στα προηγούμενα/επόμενα stops**, όχι μόνο στην απόσταση από το τρέχον επιλεγμένο venue. Έτσι μια αλλαγή venue δεν μεταβάλλει αθέλητα το original fast-food/ruin-bar intent ή όλο το alternative pool.

Πλήθος επιλογών: αρχικά π.χ. 5–10 καλές και διαφορετικές εμφανείς επιλογές, με «όλες οι επιλογές»/pagination προς το μεγαλύτερο σχετικό pool. Ο στόχος δεν συμπληρώνεται με άσχετα venues. Διατηρούμε πληθώρα χωρίς να απαιτούμε live check εκατοντάδων μαγαζιών πριν εμφανιστεί η πρώτη οθόνη. Προτεραιότητα verification στο proposed/selected και στα visible top alternatives.

Αν δεν υπάρχουν ακριβείς concept matches, δείχνουμε ότι η κάλυψη είναι μικρή και προσφέρουμε επέκταση research ή ρητά labeled broader alternatives. Δεν παρουσιάζουμε cocktail bar ως ruin bar για να γεμίσει λίστα.

## UI με διακλαδώσεις πληροφορίας

Day card → activity card → related options → venue details → evidence/official action links.

Η activity card παρουσιάζει την προτεινόμενη ή κλειδωμένη επιλογή και button «Δες επιλογές». Οι alternatives έχουν comparable fields: σύντομο why-fit, venue/style, cuisine/dishes όπου τεκμηριώνονται, price basis, proximity/travel impact, hours/check state, reservation requirement όπου γνωστό και trade-offs. Άγνωστα πεδία δεν γίνονται μηδενικές τιμές ή δήθεν πλεονεκτήματα.

Actions:

- **Επίλεξε:** user selection του venue για αυτό το slot· σε αυτή τη ροή γίνεται explicit user-owned locked selection, με ευδιάκριτη ένδειξη.
- **Άλλαξε επιλογή:** ανοίγει το ίδιο contextual pool, δείχνει και την παλιά επιλογή και ενημερώνει την selected αναφορά.
- **Ξεκλείδωσε:** επιτρέπει μελλοντική AI πρόταση για το συγκεκριμένο slot.
- **Αναίρεση:** επαναφέρει προηγούμενη selection revision και κάνει νέο feasibility check.
- **Περισσότερες επιλογές:** pagination/retrieval ή bounded targeted enrichment για αυτό το intent/context.

Lock σημαίνει διατήρηση user choice, όχι booking ή verified opening. Κλείδωμα venue, ώρας και day order είναι διακριτά. Μια πραγματική κράτηση έχει δικό της record/status και δεν δημιουργείται επειδή ο χρήστης πάτησε «Επίλεξε».

## Επιλογή και επανασχεδιασμός χωρίς απώλεια

Selection mutation με expected revision για να μην υπερισχύσει late AI response μιας νεότερης user αλλαγής. Μόνο patch στο selected venue και σχετικές derived projections: map marker/route legs, transfer estimates, budget subtotal και time feasibility. Το stable slot και οι άλλες επιλογές παραμένουν.

AI refresh/replan παίρνει τα user-locked slots ως constraints. Δεν τα αντικαθιστά σιωπηρά και δεν ξαναγράφει unrelated days. Αν νέο δεδομένο δείξει closure ή μη εφικτό timing, διατηρεί τη δηλωμένη προτίμηση και σηματοδοτεί conflict· προτείνει αλλαγή ώρας/ημέρας ή εναλλακτικές προς επιλογή. Δεν παρουσιάζει το locked-but-closed venue ως valid plan.

Old candidates διατηρούνται ως canonical references/history, όχι αιώνια ως eligible. Νέα ημερομηνία/route/source evidence οδηγεί σε reranking/revalidation και ενδεχόμενο disabled reason. Retention πολιτικές provider εξακολουθούν να εφαρμόζονται: δεν κρατάμε expired Google reviews/ratings επειδή βρίσκονται σε alternative history.

## Κεντρική αναζήτηση και αποθήκευση pin

Core MVP: κοινό MapKit search sheet μετά το research, από Places/Map/add-or-change activity. Catalog lookup → Apple pin search → exact user selection/deduplication → private save/reference ή προσθήκη σε slot/νέα δραστηριότητα. Η προσωπική βάση είναι owner-scoped στο ίδιο Supabase. Άγνωστο νέο pin δεν προωθείται αυτόματα στον κοινό catalog, και save δεν προκαλεί paid AI/Google call. Τα διαθέσιμα πεδία αποθηκεύονται μόνο σύμφωνα με applicable Apple per-field policy· hours/prices/rating δεν επιβεβαιώνονται από το pin. Πλήρης ροή και acceptance: [τελικές απαιτήσεις](FINAL_REQUIREMENTS_AND_PARITY.md). External map/directions links παραμένουν πρόσθετη λειτουργία.

Τα `trip_activity_slots`/`slot_*` παραπάνω είναι ενδεικτική activity specialization του κοινού decision/option/selection core· το stage 1 ορίζει ένα ενιαίο schema, όχι δύο ανεξάρτητα lock/history systems.

## Χάρτες: διευκρίνιση Google και Apple

**Google δεν είναι μόνο επί πληρωμή.** Η σημερινή [τιμολόγηση](https://developers.google.com/maps/billing-and-pricing/pricing) διατηρεί monthly free caps: Place Details Pro 5.000, Enterprise 1.000, Enterprise + Atmosphere 1.000. Billing-enabled setup και permitted-use terms είναι διαφορετικά ζητήματα από το αν μια κλήση τελικά χρεώνεται. Δεν απαιτείται μετανάστευση σε Apple απλώς επειδή υπάρχουν πληρωμένα Google tiers.

Για το υπάρχον iOS app, το [native MapKit](https://developer.apple.com/documentation/mapkit) είναι η φυσική επιλογή για map rendering, POI search, annotations και routing interactions. Έχει ήδη εισαχθεί και χρησιμοποιείται στο project. Δεν χαρακτηρίζουμε το native framework με τα quotas ή billing tiers του Google Places ούτε μεταφέρουμε αυτομάτως σε αυτό τα web/server limits.

Το [Apple Maps Server API](https://developer.apple.com/documentation/applemapsserverapi) τεκμηριώνει έως **25.000 service calls/day/team**, κοινά με MapKit JS, με HTTP 429 μετά το quota και δυνατότητα quota increase request. Η daily quota δεν είναι «ανά χρήστη» ούτε απεριόριστο bulk export. Χρειάζονται Maps credentials/JWT. Η [Apple Developer Program συνδρομή](https://developer.apple.com/programs/enroll/) είναι $99 ανά έτος, με regional pricing/ειδικές εξαιρέσεις· διαφέρει από per-request usage και από δωρεάν τοπική ανάπτυξη. Eligibility/auth setup αξιολογούνται για το πραγματικό deployment.

Η Apple υποστηρίζει [local POI search](https://developer.apple.com/documentation/mapkit/mklocalsearch), [MKMapItem](https://developer.apple.com/documentation/mapkit/mkmapitem) fields όπως identity/name/location/category/website/phone και [place-detail UI](https://developer.apple.com/maps/). Από τις σημερινές πηγές δεν τεκμηριώνεται αντίστοιχο general structured feed πλήρων reviews, exact menu prices, bookable inventory και future special opening hours για τον planner. Αυτό που εμφανίζεται σε Apple place card δεν θεωρείται αυτομάτως raw data που μπορούμε να εξαγάγουμε ή να κάνουμε bulk storage.

Προτεινόμενος συνδυασμός: **MapKit για το iOS UI, Overture/δική μας βάση για inventory και alternatives, official/επιτρεπόμενες πηγές για κρίσιμα operational checks, optional Google live display όπου συμφέρει και επιτρέπεται.** Apple Maps δεν λύνει από μόνο του το full reviews/prices/hours πρόβλημα.

## Κενό από το σημερινό prototype

Το `TrippyApp.swift` έχει ήδη alternatives sheet, ranking από το imported pool και replacement μιας scheduled στάσης. Η αντικατάσταση δεν διαγράφει το shared imported place pool. Όμως:

- Τα input interest chips είναι ακόμη στατικά.
- Δεν υπάρχει published city-profile → dynamic-pill API.
- Alternatives κατατάσσονται γενικά βάσει category/tags/current-place distance, χωρίς πλήρη slot-style/date feasibility filters.
- Schedule identity χρησιμοποιεί stop/date/index ή place ID, όχι ανεξάρτητο persistent activity slot.
- Δεν υπάρχει η πλήρης έννοια user-owned selection lock/versioned candidate set και προστασία της από late AI replan.

Άρα μπορούμε να εξελίξουμε την υπάρχουσα εμπειρία alternatives, αφού πρώτα μπει το σωστό slot/selection data model. Δεν δηλώνουμε ότι οι νέες απαιτήσεις έχουν ήδη υλοποιηθεί επειδή υπάρχει button «Εναλλακτικές».

## Προτεραιότητες και acceptance

1. Stable activity slot schema + candidate relations + selection revisions/locks στο normalized trip model.
2. Published city-level discovery profile και dynamic preference pills.
3. Contextual retrieval ανά slot με diverse candidates και explicit feasibility/check states.
4. UI επιλογών και venue-level selection/unlock/undo, με preserved candidate pool.
5. Derived maps/time/cost updates και lock-preserving targeted AI patches.

Acceptance: selected concepts επιβιώνουν μετά venue swaps, alternatives παραμένουν διαθέσιμες μετά επιλογή Α→Β→Α, replan δεν αλλάζει locked selection, date changes επανελέγχουν eligibility, closure γίνεται conflict αντί silent unlock, late results δεν υπερισχύουν user choices και οι επιλογές δεν απαιτούν νέα AI κλήση για απλή προβολή/σύγκριση.
