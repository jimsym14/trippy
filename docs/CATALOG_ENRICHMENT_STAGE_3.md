# Stage 3: ροή εμπλουτισμού μετά τη βασική εισαγωγή

29/10/2026. Implementation specification για το επόμενο μέρος του Stage 3, όχι υλοποιημένος enrichment adapter ή άδεια συγκεκριμένου paid run. Ισχύει Barcelona **500 αρχικές enriched επιλογές, Luna μόνο**, χωρίς Sol fallback. Η local βάση έχει 41.461 basic records και 0 enriched· βλ. [πραγματικά αποτελέσματα](CATALOG_STAGE_3.md).

Νεότερη διευκρίνιση: [SOURCE_LED_CATALOG_SELECTION.md](SOURCE_LED_CATALOG_SELECTION.md) υπερισχύει ως προς candidate selection. Πραγματικές recommendations/list/video sources → matching στο broad inventory ή verified νέες entities → category/subtype minima → revised shortlist. Free-text niche requests εξυπηρετούνται on demand· δεν προσπαθούμε να προκαθορίσουμε κάθε πιθανό style. Τα παρακάτω evidence/validation/publication gates παραμένουν.

Νεότερη video strategy: [VIDEO_SOURCE_RESEARCH.md](VIDEO_SOURCE_RESEARCH.md). Category/subtype αριθμοί είναι optional coverage benchmarks· broad source orientation, editable query variants και marginal new-evidence/gap analysis οδηγούν discovery πριν το Luna pilot. Greek/English source presets, user links και permitted local transcript evidence προβλέπονται· δεν θεωρούμε διαθέσιμα αυθαίρετα public captions ή δωρεάν Luna calls.

## Τι εμπλουτίζεται

Οι 500 είναι το αρχικό enriched subset, όχι το όριο της searchable βάσης ή ένας μόνιμα κλειστός κατάλογος. Οι υπόλοιπες basic records παραμένουν διαθέσιμες στη backend catalog search, με εμφανές basic/source state. Η iOS σύνδεση αυτού του API ακολουθεί σε επόμενο stage.

Το enrichment προσθέτει νέα πεδία και σχέσεις στις ίδιες stable entities, όχι μόνο καλύτερη διατύπωση των imported names. Περιλαμβάνει τεκμηριωμένη σύντομη περιγραφή, multi-label styles/interests, συγκεκριμένο experience/meal/visit context, neighborhood associations, nearby alternatives και estimated visit duration όπου έχει βάση. Ωράρια, τιμές, dietary/accessibility/age rules και numerical rating `/5` χρειάζονται ανακτήσιμη πηγή και πραγματικό retrieval time. Estimates και AI annotations είναι χωριστά από verified facts· έλλειψη evidence σημαίνει unknown.

City/area context, ticket/pass/transport concepts και dated events είναι χωριστά tasks με κατάλληλες entities/relations/observations. Δεν προκύπτουν αυτόματα από 500 venue descriptions και δεν περιλαμβάνονται σιωπηρά στο κόστος τους. Coverage gaps μπορούν να οδηγήσουν σε bounded discovery νέων records, μετά identity/source validation, αντί να γεμίζουμε όλες τις quotas από κακή πηγή. Οι αρχικές 500 μπορούν να αντικατασταθούν πριν το paid run· καθαρά νέα πρόσθετα enrichment tasks υπακούν στο ίδιο ξεχωριστό budget scope.

## Σειρά εκτέλεσης

1. **Identity και shortlist review χωρίς paid inference.** Ελέγχουμε essential landmark coverage, exact branch/name/address/location, official-domain matches, source conflicts, κατηγορία και πραγματική χρησιμότητα. Η source confidence δεν είναι editorial quality ή επαληθευμένη λειτουργία. Αμφιβολίες δεν συγχωνεύονται αυτόματα. Εξισορροπούμε core sights, local discoveries, food/coffee styles και περιοχές· τα σημερινά grid cells δεν είναι validated neighborhood names.
2. **Evidence preparation.** Ξεκινάμε από επιτρεπόμενα open/official structured sources, και επιβεβαιωμένες official pages όπου δικαιολογείται. Parser πρώτα, bounded text slice μετά. Κάθε claim συνδέεται με source URL/ID, πραγματικό fetched time, field path και applicable policy. Δεν αντιμετωπίζουμε οποιοδήποτε imported website ως verified official source. Content πηγών αντιμετωπίζεται ως δεδομένα, όχι εντολές προς το AI.
3. **Luna pilot σε 20 από τις 500.** Αντιπροσωπευτικές κατηγορίες/περιοχές και διαφορετική evidence completeness. Versioned natural-language task/category instructions, source policy, stable IDs, evidence και structured output schema. Το shared city task δεν περιέχει private trip context. Μέγιστα input/output, retries, concurrency και explicit cost reservation πριν dispatch. Paid εκτέλεση μόνο μετά actual deployment/tool/cost audit και συγκεκριμένο cap· API key στο backend. Το δείγμα μετρά μέσα στις 500, δεν είναι 20 επιπλέον.
4. **Validation και επέκταση στις υπόλοιπες 480.** Deterministic identity/schema/units/source/date checks, έλεγχος αν κάθε factual claim υποστηρίζεται από evidence, sample semantic review και measured usage. Πρακτικά αρχικά batches 10–20 records, προσαρμογή στο πραγματικό evidence/output μέγεθος. Repairs μόνο στα αποτυχημένα πεδία, με bounded retries. Χωρίς Sol escalation· unresolved records παραμένουν review-needed. Δεν χαρακτηρίζεται enriched όποιο record απλώς πέρασε από model call.
5. **Versioned publication.** Draft annotations/relations και observations δημοσιεύονται μόνο μετά τους αντίστοιχους ελέγχους. Published basic source snapshot και previous version παραμένουν διαθέσιμα για rollback. Η local publication προηγείται του χωριστού connected Supabase migration/readback/Auth/RLS/size verification. Private places/notes δεν δημοσιεύονται.

Μετά την πρώτη έκδοση, entity εκτός των 500 μπορεί να εμπλουτιστεί αν επιλεγεί σε ταξίδι ή υπάρχει χρήσιμο coverage gap. Existing evidence/cache επαναχρησιμοποιείται, νέα paid εργασία χρειάζεται εφαρμόσιμο trip/city budget και σαφές request flow. Απλό catalog search ή MapKit Save δεν πυροδοτεί paid research. Trip-specific dates, routes και preferences αποτελούν overlay· δεν ξαναγράφουν κοινά facts ή user locks.

## Πρώτο πραγματικό εύρημα του review

Read-only search στις 29/10/2026 για `sagrada familia`, family `sights`, επέστρεψε τέσσερις source records. Η εγγραφή `94ac5a70-6eea-5d63-ac84-b939da2b0495` με name `Sagrada Familia`, address `Carrer Mallorca, 401`, source coordinates `41.4032211, 2.1748700` και website `https://sagradafamilia.org/` δεν είναι στη preliminary shortlist. Υπάρχουν άλλες ομώνυμες source records με διαφορετικές διευθύνσεις/συντεταγμένες και ένα amusement park. Αυτό απαιτεί independent identity/landmark review· ούτε το domain μόνο ούτε το όνομα πιστοποιούν τη σωστή ταυτότητα. Δεν έγινε εδώ correction, merge, νέα publication ή paid call.

Η προσωρινή επιλογή βασίζεται σε category/grid diversity, confidence και website presence, όχι σε επιβεβαιωμένο core-landmark checklist. Συνεπώς το άμεσο επόμενο deliverable είναι review manifest και revised shortlist πριν από τον πραγματικό adapter/pilot, χωρίς να ισχυριζόμαστε ότι οι σημερινές 500 είναι ήδη curated.

## Quality audit και αλλαγή της μεθόδου selection

Read-only local audit: `.local/stage3/shortlist-quality-audit.json`. Στις σημερινές 500 υπάρχουν 11 `movie_theater` records στα sights, 8 grocery/building-supply/warehouse-club records στα shopping και 20 `tapas_bar` records στα nightlife. Εμφανίζονται 6 Starbucks branches και 7 Parfois branches. Συνολικά 64 entities έχουν τουλάχιστον ένα από τα συγκεκριμένα heuristic review signals· αυτό δεν είναι συνολική εκτίμηση error rate, απόδειξη duplicates ή verdict για τα υπόλοιπα 436. Η classification των tapas χρειάζεται meal/nightlife multi-label context, όχι απλή απόρριψη.

Η μεγάλη Overture βάση είναι source inventory, όχι curated recommendation dataset. Shopping 19.289 / 41.461 (~46,5%)· ο αριθμός records δεν αποδεικνύει tourist coverage ή σωστές διευθύνσεις. Locality label, bbox και source confidence δεν πιστοποιούν κατάλληλη θέση ή real-world identity. Ο αρχικός allocator είναι technical baseline και **δεν εγκρίνεται ως τελική selection για paid enrichment**.

Η revised επιλογή θα διαχωρίζει eligibility από ranking και diversity:

- Eligibility: διασταυρωμένη ταυτότητα/θέση, κατάλληλο travel context, διαθέσιμο επιτρεπόμενο evidence, χωρίς unresolved critical identity conflict. Πρακτικά venues μπορούν να παραμείνουν searchable χωρίς να καταλαμβάνουν editorial shortlist slots.
- Ranking: χρησιμότητα για συγκεκριμένα travel contexts, core-landmark coverage, διακριτή εμπειρία, τεκμηρίωση, δυνατότητα επαναχρησιμοποίησης και διαθέσιμη πληροφορία· source confidence δεν χρησιμοποιείται ως quality/recommendation score.
- Diversity: core landmarks και local discoveries, πραγματικές περιοχές μετά geography validation, styles/cuisines, budget ranges όπου τεκμηριώνονται και προσβασιμότητα όπου είναι γνωστή. Αποφεύγεται υπερβολική εκπροσώπηση ίδιου brand χωρίς ξεχωριστή χρησιμότητα branch. Αλυσίδες/fast food δεν αποκλείονται καθολικά: παραμένουν επιλογές όταν εξυπηρετούν user preferences.
- Coverage: independently sourced core-landmark checklist και επιλεγμένες official/open city ή cultural sources. Candidate generation δεν κλείνει μέσα στην Overture βάση. Missing candidates προστίθενται μόνο μετά provenance/identity validation· το initial enriched target παραμένει 500, χωρίς σιωπηρό extra paid scope.
- Review manifest ανά candidate: selection reason, evidence references, category/area context, quality/conflict state, γιατί επιλέχθηκε ή αντικαταστάθηκε. Καμία αυθαίρετη εγγύηση ότι quota count σημαίνει quality.

## Fact-checking πριν τη δημοσίευση

Το fact-checking είναι field-level acceptance gate για κάθε factual claim και αρχίζει πριν το Luna run. Το AI γράφει προτάσεις πάνω σε evidence· δεύτερη γνώμη του ίδιου μοντέλου δεν είναι ανεξάρτητη διασταύρωση. Schema validation από μόνο του δεν αποδεικνύει truth.

| Πεδίο | Έλεγχος και κατάσταση |
|---|---|
| Name / branch / address / coordinates | Exact entity matching σε authoritative source, με γεωγραφικό έλεγχο και επιπλέον corroboration όταν υπάρχουν conflicts. Shared domain δεν αποδεικνύει ότι δύο θέσεις είναι το ίδιο venue. |
| Περιγραφή / styles / interests | Κάθε factual statement συνδέεται με evidence. Editorial tags έχουν rationale και παραμένουν annotations· η πηγή δεν αλλάζει για να ταιριάξει στο prompt. |
| Ωράρια / τιμές / tickets | Επίσημη applicable πηγή, retrieval date, validity window, currency/basis/eligibility και exceptions. Research snapshot δεν είναι live availability ή booking confirmation. Trip-date check γίνεται χωριστά όταν χρειάζεται. |
| Dietary / accessibility / ηλικιακοί κανόνες | Explicit source statement για το exact venue και το αντίστοιχο scope. Δεν συμπεραίνονται από όνομα, cuisine ή γενική κατηγορία. Conflicts απαιτούν review. |
| Rating `/5` | Αναγνωρίσιμο venue/platform/value/scale, source URL, actual observed time και permitted snapshot use. Χωρίς evidence: unknown. Καμία παραγωγή rating από model opinion ή hotel stars. |
| Duration / effort / fit | Marked estimate ή annotation, με βάση και limitations. Δεν παρουσιάζεται ως verified source fact. |

Missing evidence αφήνει το αντίστοιχο πεδίο unknown· δεν κατασκευάζουμε facts για να συμπληρωθεί το record. Critical identity conflict εμποδίζει promotion στη curated shortlist. Καταγράφονται fact coverage, conflicts, freshness και quality-review status χωριστά από `is_enriched`. Ακόμη και published enrichment δεν σημαίνει ότι όλα τα πεδία είναι επιβεβαιωμένα ή επίκαιρα. Source changes απαιτούν targeted refresh· δεν ξαναγράφουμε όλη τη βάση ούτε εμφανίζουμε φρέσκο observed time επειδή διαβάστηκε η cache.
