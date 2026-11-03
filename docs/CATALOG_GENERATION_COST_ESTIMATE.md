# Εκτίμηση κόστους παραγωγής catalog

29/10/2026. Εκτίμηση πριν από το Stage 2, όχι paid benchmark ή επιβεβαιωμένο Azure quote. USD, πριν από φόρους. Δεν εγκρίνει paid runs, subscriptions ή deployment.

**Νεότερη απόφαση χρήστη: Barcelona 500 curated/enriched επιλογές, Luna μόνο.** Οι πίνακες Sol/hybrid παραμένουν συγκριτικά cost scenarios, όχι ενεργή στρατηγική ή fallback. Κεντρικό Luna model estimate για 500 εγγραφές ~$0.59, συν actual search/provider costs· δεν είναι τιμή πλήρους operational verification.

## Προτεινόμενη στρατηγική

Open datasets και deterministic code για αρχική εισαγωγή, normalization και εύκολα duplicates. Luna μόνο για extraction/classification και semantic enrichment από διαθέσιμα τεκμήρια. Αμφίσημες ταυτοποιήσεις και semantic conflicts παραμένουν review-needed· δεν γίνεται Sol escalation. Η επιλογή μοντέλου δεν αντικαθιστά την τεκμηρίωση: μη διαθέσιμα facts παραμένουν unknown, ratings είναι μόνο sourced snapshots /5 και προσωπικά δεδομένα δεν δημοσιεύονται.

Το 5% Sol review παρακάτω είναι συγκριτική υπόθεση κόστους, όχι ενεργή εντολή ή μετρημένη ανάγκη. Το Luna pilot ελέγχεται με source-backed records για identity, unsupported claims, category fidelity και valid structured output. Δεν αλλάζουμε ακόμη τον υπάρχοντα Azure provider/deployment.

## Επίσημες τιμές αναφοράς

Standard, σύντομα requests, ανά 1 εκατομμύριο tokens:

| Μοντέλο | Input | Output |
|---|---:|---:|
| GPT-6 Luna | $0.10 | $0.50 |
| GPT-6.1 Sol | $2.00 | $10.00 |

Πηγές που ελέγχθηκαν: [Luna](https://developers.openai.com/api/docs/models/gpt-6-luna), [Sol 6.1](https://developers.openai.com/api/docs/models/gpt-6.1-sol). Για ίδιο input/output, Sol είναι 20×. Δεν υπολογίζονται cache/Batch εκπτώσεις. Reasoning tokens περιλαμβάνονται στο billed output budget, όχι μόνο στο εμφανιζόμενο JSON.

[OpenAI pricing](https://developers.openai.com/api/docs/pricing): non-preview web search $10/1.000 calls, επιπλέον retrieved content tokens στα model rates. Αυτές είναι τιμές direct OpenAI API. Azure scout model, grounding tool, region και account rates παραμένουν ανεπιβεβαίωτα· δεν αποδίδουμε αυτές τις τιμές αυτόματα στο Azure invoice.

## Αναπαραγώγιμος υπολογισμός

Κεντρική υπόθεση ανά enriched record: 4.000 amortized input tokens, 1.000 billed output tokens, 30% επιπλέον allowance για retries/δεύτερα περάσματα. Το input περιλαμβάνει πηγές, search content και κατανεμημένο shared prompt overhead. Πραγματικά μεγάλα evidence payloads χρειάζονται επανεκτίμηση.

```text
model_cost(N, input_rate, output_rate)
  = N × (4,000 × input_rate + 1,000 × output_rate) / 1,000,000 × 1.30
hybrid_cost(N) = luna_cost(N) + 0.05 × sol_cost(N)
search_fee = actual_total_search_calls × 0.01
```

Το hybrid κάνει Luna σε όλες τις εγγραφές και επιπλέον Sol σε 5%, με ίδιο token budget ανά review. Το tool fee βασίζεται σε actual calls, μαζί με retries, όχι στον αριθμό discovery tasks.

| Enriched records | Μόνο Luna | Luna + Sol review 5% | Μόνο Sol | Search fee: 0,2–1 call/record |
|---|---:|---:|---:|---:|
| 500 | $0.59 | $1.17 | $11.70 | $1–5 |
| 5.000 | $5.85 | $11.70 | $117 | $10–50 |
| 50.000 | $58.50 | $117 | $1.170 | $100–500 |
| 500.000 | $585 | $1.170 | $11.700 | $1.000–5.000 |

Δεν χρειάζεται search ανά εγγραφή όταν οι πηγές υπάρχουν ήδη. Το εύρος search είναι illustrative sensitivity, όχι μετρημένη coverage ανάγκη. Εάν απαιτούνται πολλές επιβεβαιώσεις ανά place, το κόστος ανεβαίνει αναλογικά.

Για ευρύτερο token sensitivity χρησιμοποιούμε 3.000–8.000 input και 600–2.000 billed output ανά record, με ίδιο 30% allowance και 5% Sol review. Μαζί με το παραπάνω search scenario προκύπτουν στρογγυλεμένα planning ranges:

| Enriched records | Hybrid tokens + illustrative search |
|---|---:|
| 5.000 | περίπου $20–75 |
| 50.000 | περίπου $180–750 |
| 500.000 | περίπου $1.800–7.500 |

Αυτά αφορούν αρχικό semantic enrichment, όχι πλήρη operational verification κάθε εγγραφής. Δεν περιλαμβάνουν ανάπτυξη λογισμικού, ανθρώπινο έλεγχο, backend hosting, DB/storage/egress, embeddings, paid source licenses ή provider-specific πρόσθετα. Δεν γίνεται μετατροπή σε EUR χωρίς ισοτιμία.

## Πρώτη πόλη και μεγάλη βάση

Το Barcelona stage στοχεύει 1.000–5.000 raw entities, **500 curated/enriched με Luna μόνο** και 30–60 high-detail shortlist records. Raw dataset import δεν χρειάζεται LLM inference. Για πρώτη πόλη προτείνεται planning reserve $5–15 για AI/search, με ξεχωριστά αυστηρά caps και διακοπή όταν εξαντλούνται· δεν είναι εγγυημένο κόστος πλήρους επαλήθευσης. Το προηγούμενο προτεινόμενο €10 pilot cap παραμένει μη εγκεκριμένο, δεν ενεργοποιείται από αυτό το έγγραφο.

Τα 500.000 enriched records δεν είναι υπόσχεση ότι χωρούν στο Supabase Free. Χρειάζεται μέτρηση bytes ανά entity μαζί με indexes/observations/history και έλεγχος των τρεχόντων project limits. Δεν εισάγουμε global dataset χωρίς regional filtering. Μεγάλη raw βάση μπορεί να έχει πολύ μικρότερο enriched subset.

Refresh γίνεται σε αλλαγμένες/ληγμένες πληροφορίες και trip shortlist, όχι rebuild όλης της βάσης κάθε μήνα. Π.χ. για 50.000 enriched records, εάν 10% χρειάζονται το ίδιο enrichment σε έναν κύκλο, το κεντρικό hybrid model estimate είναι $11.70, συν τα actual search/provider fees. Το 10% είναι παράδειγμα, όχι πρόβλεψη freshness.

## Συνέχεια υλοποίησης

Stage 2 παραμένει backend/auth/durable jobs/progress, revision-aware mutations και budget reservations/reconciliation. Χρειάζονται ξεχωριστοί μετρητές model tokens, search calls, retries και ανά-city/job caps πριν από unattended generation. Stage 3 αρχίζει με regional import και μετρήσεις μεγέθους/coverage. Καμία paid κλήση ή Stage 2 αλλαγή κώδικα δεν έγινε για αυτή την εκτίμηση.
