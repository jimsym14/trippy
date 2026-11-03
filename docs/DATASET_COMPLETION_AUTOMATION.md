# Αυτοματοποιημένη ολοκλήρωση των τριών επιπέδων

1 Νοεμβρίου 2026. Έτοιμη τοπική ουρά για editorial review, branch matching και
operator field checks. Έχει εκτελεστεί και ελεγχθεί offline. Δεν έχουν γίνει νέες
paid Luna κλήσεις ή live HTTP checks κατά την κατασκευή της.

## Εκτέλεση

Αρκεί μία εντολή. Οι εργασίες και οι απαραίτητες εξαρτήσεις εκτελούνται από την
ουρά· δεν χρειάζεται να ξεκινήσεις διαδοχικά τα παλιά scripts.

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-completion.sh
```

Κράτησε το Mac ανοιχτό. Το `caffeinate` είναι αυτόματο. Μετά από διακοπή,
επανεκτέλεσε την ίδια εντολή. Τα content-invalid outputs διατηρούνται για review
και δεν προκαλούν αυτόματο paid repair loop.

Status χωρίς API κλήσεις:

```sh
/Volumes/CrucialX9/Code_Backup/Trippy/project/.local/stage3/run-barcelona-completion.sh status
```

Προετοιμασία μόνο: τελευταίο argument mode `prepare`. Το `offline` εκτελεί μόνο
τοπική δουλειά και επαναχρησιμοποιεί επιτρεπόμενα cached receipts· μη διαθέσιμες
HTTP/AI εργασίες παραμένουν deferred και μπορούν να συνεχιστούν με το κανονικό run.
Αντιγράφουμε στο Terminal μόνο τις εντολές, όχι το JSON output.

## Τι περιλαμβάνει το frozen run

| Επίπεδο | Input / δουλειά | Output |
|---|---|---|
| Νόημα και tags | 243 ανεξέταστα source claims· 627 facet proposals, 1.075 details, 149 activity fits | Keyed dispositions με source evidence, assertion scope και lifecycle· χωριστό staged source pack |
| Ταυτότητα | 303 candidate groups πάνω στα 41.461 inventory entities· 24 bounded coffee/bakery/brunch/grocery discovery candidates | Candidates και αυστηρές operator-to-inventory branch αντιστοιχίσεις όπου υπάρχουν αρκετά στοιχεία |
| Τρέχουσες πληροφορίες | Έως 60 συγκεκριμένα operator URLs· 10 επιπλέον URLs παραμένουν εκτός αρχικού ορίου | JSON-LD observations, προτάσεις από ακριβή excerpts, field-level refresh states |

Τα 627 facets είναι 593 ανεξέταστες προτάσεις συν 34 vocabulary quarantines.
Τα 20 χειροκίνητα tag reviews και η ενεργή χειροκίνητα ελεγμένη πηγή διατηρούνται.
Οι τέσσερις ήδη ελεγμένες ASR ασάφειες δεν στέλνονται ξανά στο Luna σαν να ήταν
ανεξέταστες. Η χειροκίνητη επιλογή τους δεν παρακάμπτεται.

Τα 24 discovery candidates επιλέγονται από inventory categories, με μικρά όρια
και κατανομή ανά area. Δεν αποδεικνύουν specialty coffee, brunch quality ή σημερινή
διαθεσιμότητα και δεν προστίθενται υποχρεωτικά στο πρόγραμμα.

## Κόστος και retries

- Αρχική συντηρητική reservation για τις 179 βασικές AI κλήσεις: **$3.3559797**.
- Νέο combined queue ceiling: **$4.75**, μέσα στο αρχικό shared **$15**.
- Το shared ledger ήταν **$9.7357103** πριν την εκτέλεση. Δεν μηδενίζεται και οι
  αποτυχημένες reservations παραμένουν. Το reserve δεν είναι το τελικό invoice.
- Τα stage caps είναι αλληλεπικαλυπτόμενα maxima, όχι επιπλέον προϋπολογισμοί.
  Κάθε dispatch ελέγχει stage, combined queue και shared ceiling.
- Transient failures: έως τρεις προσπάθειες· rate limits: έως οκτώ, με backoff
  και `Retry-After`. Έως 100 paid requests ανά stage, μαζί με retries.
- HTTP: έως 240 requests ανά run, μαζί με robots και redirects. Κοινό per-host
  pacing. Socket timeout 20s και isolated wall deadline 60s ανά HTTP retrieval.
- Συνολική αναμονή έως 12 ώρες, persisted. Μεγαλύτερα provider waits και εξαντλημένα
  όρια παράγουν καθαρό handoff. Η ουρά δεν κάνει busy retry επ' αόριστον.

Κοινό dispatch lock και provider cooldown εμποδίζουν διαφορετικά completion runs
να διπλοχρεώσουν το ίδιο διαθέσιμο receipt ή να αγνοήσουν κοινό rate limit.
Το αρχικό shared budget reservation παραμένει atomic και με άλλα παλιά scripts.
Δεν συνιστάται ταυτόχρονη εκτέλεση παλιών paid scripts, επειδή καταναλώνουν το ίδιο
shared ceiling χωρίς να ολοκληρώνουν αυτή την ουρά.

## Κανόνες αποδοχής

Source/editorial αποτελέσματα παραμένουν **staged candidates**, ξεχωριστά από την
ενεργή ελεγμένη έκδοση. Κάθε upstream claim βρίσκεται είτε στο staged pack είτε
στα held claims. Αλλαγές δεν σβήνουν το αρχικό claim ή τις χειροκίνητες αποφάσεις.

Αυτόματη αποδοχή branch identity απαιτεί μοναδική συμφωνία κυριολεκτικού ονόματος,
operator host, civic address και μη αντικρουόμενης family, χωρίς γνωστό closure ή
inventory identity conflict. Αυτό αφορά το συγκεκριμένο operator branch. Δεν
επιβεβαιώνει αυτόματα ασαφή transcript aliases, είσοδο ή access chain.

Το JSON-LD αποθηκεύεται ως structured source observation. Η εξαγωγή από prose
παραμένει proposal, ακόμη και με ακριβές quote. Μια γενική bodega παράδοση ή ένα
πρωινό επίσκεψης δεν γίνονται αυτόματα μόνιμα service tags. Μη διαθέσιμη ή ασαφής
πληροφορία παραμένει unknown. Lifecycle/refresh metadata δεν αποδεικνύει αλήθεια.

## APIs, cache και μελλοντική ανανέωση

Η αρχική εκτέλεση χρησιμοποιεί το τοπικό Overture inventory και δημόσιες operator
σελίδες. Δεν απαιτεί νέο API key, πέρα από το ήδη ρυθμισμένο Luna environment.
Δεν έχει συνδεθεί γενικό web-search API και το Luna δεν κάνει browsing.

Υπάρχει επίσης adapter για ρητά configured δημόσια operator JSON feeds. Το
`operator_feeds` στο recipe είναι αρχικά κενό. Για προσθήκη feed ορίζουμε πραγματικό
URL, `records_pointer`, `name_pointer`, `address_pointer`, `field_pointers`,
bounded `max_records` και optional `schema_types`. Οι pointers είναι RFC6901,
π.χ. `/locations`, `/name`, `/address`, `{"published_hours":"/hours"}`. Δεν
εφευρίσκουμε endpoint ή fields και δεν θεωρούμε οποιοδήποτε JSON booking API.
Νέο provider/config απαιτεί νέα frozen run version με το ίδιο ledger.

Operator receipts έχουν κοινό bounded cache έως 24 ώρες. Cache hit δεν προχωρά
το `checked_at`. Με fresh fetch και ίδιο περιεχόμενο, η επεξεργασία prose μπορεί
να επαναχρησιμοποιήσει την ίδια model response χωρίς νέα paid κλήση. Παλιά
observations και immutable per-job receipts παραμένουν διαθέσιμα.

Το `refresh` δημιουργεί νέα dated output folder και εκτυπώνει το ακριβές
`recipe.json` για resume. Δεν αλλάζει inference pools ή μηδενίζει budget. Η
εντολή είναι `run-barcelona-completion.sh refresh`. Για resume του συγκεκριμένου
refresh χρησιμοποιούμε `run-barcelona-completion.sh run /path/to/recipe.json`.
Χρησιμοποιείται όταν απαιτούνται νέοι έλεγχοι, όχι ως επανάληψη όλου του extraction.

Οι refresh deadlines είναι configurable κανόνες επανελέγχου: published hours
τρεις ημέρες, price statements επτά, business status μία, μενού δεκατέσσερις,
ονόματα/διευθύνσεις τριάντα. Δεν είναι effective dates ούτε εγγύηση για μέλλον.
Date-specific tickets/table availability και verified entrance/access chain
παραμένουν μη υποστηριζόμενες δυνατότητες της αρχικής διαμόρφωσης.

## Πού βρίσκονται τα αποτελέσματα

`.local/stage3/planner-release-v1/completion-v1/`:

- `preview.json`, `prepared.json`: κόστος, όρια και frozen inputs.
- `status.json`, `completion-report.json`: πρόοδος, πραγματικά counts και handoffs.
- `jobs.sqlite`, `results/`, `candidates/`: checkpoints και immutable receipts.
- `staged-source-pack.json`: claims, held items, ID mapping και editorial lineage.
- `annotation-review-results.json`: νέα dispositions και τα διατηρημένα manual reviews.
- `identity-results.json`: candidates και τεκμηριωμένα branch links.
- `operational-results.json`: structured observations, prose proposals και refresh states.
- `runner.log`: user-run stdout, χωρίς credentials.

`execution_complete` σημαίνει ότι όλες οι προγραμματισμένες εργασίες επέστρεψαν
έγκυρο αποτέλεσμα. `queue_drained` μπορεί να είναι true ακόμη και με deferred ή
failed jobs. Κανένα από τα δύο δεν σημαίνει `dataset_ready` ή `ready_to_publish`.
Partial execution επιστρέφει exit code 2 και διατηρεί όλη την πρόοδο.

## Verification

Preparation checkpoint (historical): **286 tests passed.** The real Barcelona offline run conserved all 2,028
claims, kept 1,781 active / 247 held and preserved the 20 manual tag reviews.
The local inventory job produced 303 candidate groups. The 179 AI and 60 HTTP
jobs remain deferred with zero consumed attempts/reservations, ready for the live
launcher. Shared reserved remains $9.7357103.

## Executed run and offline recovery — 1 November 2026

The live queue drained with 218 succeeded jobs, 49 review handoffs and five
exhausted HTTP jobs (272 total, including 32 dynamically created prose extraction
jobs). Shared reservation is **$13.3432175 / $15**, including $3.6075072 for this
completion queue. Reservation is a conservative budget commitment, not an invoice.
Do not rerun the paid queue to repair schema/content handoffs.

An independent offline recovery module validates saved candidates per item, so a
bad item does not discard valid siblings. It preserves foreign/invalid evidence
in quarantine, clears redundant replacements, separates unapplied context text
suggestions, and holds implicit changes disguised as `retain`. Frozen engine
files, original receipts, ledger and manually curated source pack remain intact.

```sh
cd /Volumes/CrucialX9/Code_Backup/Trippy/project
.venv/bin/python -m trippy.research.completion_recovery --run .local/stage3/planner-release-v1/completion-v1
```

Executed immutable output:
`.local/stage3/planner-release-v1/completion-recovery-v1/db5df2eb48ceb00b/`.

| Measure | Recovered result |
| --- | ---: |
| Source decision slots validated | 243 / 243 |
| Source repair / supported / unresolved | 144 / 62 / 37 |
| Annotation slots validated | 1,826 / 1,851 |
| Annotation retain / context / reject / repair / unresolved | 1,148 / 360 / 72 / 39 / 207 |
| Individual quarantines | 25 (23 facets, one detail, one activity fit) |
| Staged active / held claims | 1,987 / 41 |
| Total source claims conserved | 2,028 |
| New paid or HTTP calls in recovery | 0 |

Protocol validation does not establish semantic correctness. The recovered pack
contains automated editorial candidates; it is not the active manually curated
pack (1,781 active / 247 held). Neither pack approves current facts or planner
release. The 41 staged holds comprise 37 unresolved followups and four preserved
manual holds. Source repairs and annotation repairs still need editorial
acceptance before production use; context suggestions remain unapplied.

Saved operator evidence yielded two manual source-to-catalog links, Velada at
Ferran 25 and La Pedrera-Casa Milà at Passeig de Gràcia 92, with explicit original
receipt and normalization lineage. Artifact:
`.local/stage3/planner-release-v1/manual-operator-links-v1/0224a51fe3433c1f/`.
This approves only those source/catalog correspondences, not transcript aliases,
full canonical admission, entrances, trip dates or availability. The earlier
`0d0fa318594c75e2` scratch packet is superseded by this plan-bound packet.

Four concrete subjects remain held in `held-identity-diagnostics.json`: Moco
structured metadata says Montcada 2 while saved visitor prose says Montcada 25;
MOOD Sants has a 1–3 civic range; Sant Joan and Urquinaona have different catalog
names at the operator address. Do not merge by address alone or infer rebranding.
The 303 inventory candidate groups are review proposals, not approved places.

Next work is targeted editorial review of repairs/holds and annotations,
shortlisted branch/alias resolution, selected current-field checks, and executed
planner scenarios. The 59 structured field observations and 125 prose proposals
remain source observations; zero fields are trip-verified. Web search remains
disconnected; Luna processed supplied evidence and separately fetched operator
pages. Booking availability and entrance/access verification still require
appropriate providers or explicit source review.

**290 unittest tests pass** after recovery. Real saved-candidate replay produced
the identical immutable output, with no HTTP/model calls. `git diff --check`
passed. Production/UI/planner publication remains pending.

Later manual annotation pass: all 136 repair/reject/quarantine handoffs were
compared with their quotes. Findings: 35 confirmed annotation errors, three
formatting problems, 40 unnecessary/overly strict model changes, 21 taxonomy
gaps, 19 evidence gaps and 18 scope clarifications. A private effective annotation
layer applies 51 replacements, retains 40, scopes 14 as context, rejects 15 and
holds 16, with all previous 20 manual reviews preserved. Source claims remain
unchanged; unreviewed automated annotations do not inherit manual eligibility.
See [manual correction](BARCELONA_FINAL_ANNOTATION_CORRECTION.md) for exact artifacts,
before/after examples, offline replay and scope limits. 296 tests pass.

The subsequent [executed dataset integration](BARCELONA_DATASET_INTEGRATION.md)
manually reviewed all 243 source followups and selected a new private JSON/SQLite
edition with 1,986 active / 42 held claims. Editorial admission coverage is 97.93%
(before 87.82%, target 95%), not planner readiness or factual accuracy. The previous
manual source pack, annotation receipts, holds and budget ledger are preserved;
future editorial work uses the new active edition selection. 302 tests pass and
real immutable reconstruction/SQLite content checks passed with zero paid/HTTP calls.

Offline execution ελέγχει πραγματικά τα Barcelona inputs, schema sizes, local
inventory, claim conservation και manual tag bindings, με μηδενικές HTTP/paid
κλήσεις. Tests καλύπτουν interrupted receipts, resume, invalid evidence, global
cooldown, budgets, bounded HTTP workers, branch ambiguity, cache freshness,
taxonomy/scope guards και future-date limitations. Τα live operator pages και τα
πραγματικά model outputs θα αξιολογηθούν από το user-run και τα handoffs του.
