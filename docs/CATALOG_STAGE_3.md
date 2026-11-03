# Stage 3: βασική βάση Βαρκελώνης πριν από το generation

Η βασική εισαγωγή ολοκληρώθηκε τοπικά στις 29/10/2026. **41.461 πραγματικές source records, 500 preliminary shortlist records, 0 AI-enriched records.** Δεν έγινε Luna/άλλο model call ή remote Supabase write. Το Stage 3 παραμένει σε εξέλιξη ως προς τον πραγματικό Luna enrichment/provider audit.

## Τι υπάρχει στη βάση

| Στοιχείο | Μετρημένο αποτέλεσμα |
|---|---:|
| Canonical basic entities / version snapshots | 41.461 |
| Source records με address | 39.918 |
| Source records με website | 22.706 |
| Preliminary shortlist | 500 |
| AI-enriched records | 0 |
| Possible duplicate pairs | 97 |
| Distinct entities flagged review-needed | 191 |
| SQLite database size | 105.058.304 bytes, περίπου 105 MB / 100 MiB |
| Schema tables / migration | 55 / `0003` |

Source fields: primary/localized names, ακριβείς συντεταγμένες από WKB Point, original taxonomy και deterministic family, address/locality όπου υπάρχουν, source-provided website, source confidence και operating-status assertion, dataset/source IDs/license/property paths και update/retrieval metadata. Δεν αποθηκεύονται invented descriptions, hours, ticket prices, ratings, photos, personal notes ή private trip data στον κοινό catalog. Source website δεν βαφτίζεται ανεξάρτητα verified official URL. Confidence δεν είναι `/5` rating. Source operating status δεν είναι current opening-hours check.

| Family | Basic records | Preliminary shortlist |
|---|---:|---:|
| Food | 9.326 | 170 |
| Coffee / cafes / bakeries | 2.566 | 90 |
| Sights / culture | 1.071 | 100 |
| Outdoors | 798 | 65 |
| Nightlife | 4.489 | 45 |
| Shopping / source retail categories | 19.289 | 30 |
| Stay | 2.051 | — |
| Transport | 570 | — |
| Other practical categories | 1.301 | — |

Η κατανομή είναι source taxonomy mapping, όχι verified travel-quality classification. Οι 500 επιλέχθηκαν χωρίς AI με quotas και ποικιλία σε γεωγραφικά grid groups, source confidence/website και stable IDs. Είναι προσωρινό σύνολο για review/enrichment, όχι τελικές «500 καλύτερες». Τα 12 πιθανά pilot-grid cells δεν είναι administrative neighborhoods· υπάρχουν records σε 11.

## Πηγή και ακριβές scope

Pinned [Overture Places](https://docs.overturemaps.org/guides/places/) release **2026-10-21.0**, ανακτημένο μέσω επίσημου [STAC](https://stac.overturemaps.org/catalog.json). Regional DuckDB read από ένα intersecting GeoParquet asset. Το αποθηκευμένο complete extract είναι **43.927.321 bytes**· αυτό είναι artifact size, όχι μέτρηση συνολικού network transfer.

Scope bbox: west/east 2.05–2.24, south/north 41.30–41.47. Το αρχικό bbox έχει 164.441 source records, από τις οποίες 130.408 αναφέρουν locality `Barcelona`. Η τελική εισαγωγή περιλαμβάνει **source locality Barcelona και explicit travel/practical primary-category filter**. Δεν είναι όλο το business registry της πόλης, municipal-polygon extract ή δήλωση πλήρους city coverage. Το exact regex και οι assets/projection βρίσκονται στο hash-verified acquisition manifest.

Η broad αρχική προσπάθεια σταμάτησε στα όρια 64/128 MB και μετά στο 100.000-record ceiling. Τα μερικά artifacts διατηρήθηκαν χωριστά, χωρίς complete manifests, και **δεν εισήχθησαν**. Η τελική, χρήσιμη source projection ολοκληρώθηκε πλήρως εντός ορίων. Δεν γεμίσαμε την app DB με global Parquet ή άσχετες επιχειρηματικές κατηγορίες.

Wikidata structured source χρησιμοποιήθηκε για Europe/Spain/Catalonia/Barcelona names/coordinates και source references. Η selected hierarchy/timezone είναι app geographic scope configuration. Δεν δηλώνεται ότι έγινε venue enrichment από Wikidata ή ότι οι pilot grid groups είναι επίσημες γειτονιές.

Licensing/provenance: reviewed Places guide και [Overture attribution](https://docs.overturemaps.org/attribution/), explicit dataset/license whitelist, source records/policies και per-source field paths. Τα source datasets του extract περιλαμβάνουν BrightQuery, meta, Microsoft, Foursquare, AllThePlaces, Overture και μικρότερα contributing datasets. New/unknown dataset ή license χρειάζεται review, δεν κληρονομεί αυτόματα policy. Source-specific notices/attribution παραμένουν μέρος του rollout. Raw artifacts μένουν στο ignored `.local`, όχι σε Git/public exports.

## Import, identity και publication

- Complete manifest + SHA-256 + count/byte/time checks πριν ανοίξει import transaction. Point-only geometry, finite coordinates, geographic scope/country και category/source-license validation. Η τελική εισαγωγή είχε 0 rejected records και 0 duplicate source IDs.
- Stable canonical UUIDs από provider/external ID. Ίδιο ID/payload αφαιρείται ως duplicate· conflicting same ID σταματά το import. Name/proximity μόνο σημαίνει possible duplicate, όχι automatic merge. Review-needed records μένουν χωριστά στη basic βάση και αποκλείονται από shortlist.
- `0003` προσθέτει geography references, import manifests/counts, typed version snapshots και identity-conflict records. Τα `0001`/`0002` snapshots διατηρήθηκαν.
- Atomic local draft import με size cap 256.000.000 bytes και existing-DB backup. Import δεν αλλάζει την προηγούμενη published version ή user/private tables. Identical artifact reimport είναι idempotent.
- Local publication με expected active version, verified shared source/policy και complete inventory count. Rollback με republish παλιού snapshot. Removed entities μπορούν να γίνουν retired χωρίς delete ή απώλεια private references/locks.

Τρέχον local published version: `2a2dbe33-5c17-5f69-b235-4f1dc716f939`, city ID `42b5127d-f3fd-5f3b-945a-18a170979c83` (επαληθευμένα από importer και verification artifact). Publication είναι στην τοπική SQLite, όχι public Supabase deployment. Η source περιλαμβάνει 2.655 permanently-closed assertions· δεν εμφανίζονται στην default catalog search. Unknown/temporarily-closed business status παραμένει visible ως source state, χωρίς live claim.

## Commands και API

```bash
uv pip install --python .venv/bin/python -r requirements-catalog.txt
.venv/bin/python -m alembic upgrade head
.venv/bin/python -m trippy.catalog.acquire \
  --output .local/stage3/barcelona-overture-2026-10-21.geojsonl \
  --release 2026-10-21.0
.venv/bin/python -m trippy.catalog.cli import \
  --source .local/stage3/barcelona-overture-2026-10-21.geojsonl \
  --geography-source .local/stage3/geography-wikidata.json
.venv/bin/python -m trippy.catalog.cli coverage
.venv/bin/python -m trippy.catalog.cli search --query 'sagrada familia'
```

Acquisition αρνείται overwrite. Geography source είναι το αποθηκευμένο πραγματικό Wikidata `wbgetentities` response, με διατηρημένο fetch timestamp. Publish CLI απαιτεί `--version`, και σε αλλαγή/rollback `--expected-active`. CLI import είναι local-only· δεν γράφει σε remote DB. Δεν δημιουργεί schema αυτόματα.

Authenticated API:

| Route | Συμπεριφορά |
|---|---|
| `GET /v2/catalog/{city_id}/places` | Published/shared/permitted records, accent-normalized name/alias search, family/shortlist filters, exact radius after geographic prefilter και bounded cursor pagination. |
| `GET /v2/catalog/{city_id}/coverage` | Active dataset/scope και measured import/shortlist counts, χωρίς fabricated full-city percentage. |
| `POST /v2/admin/catalog/{city_id}/versions/{version_id}/publish` | Existing verified admin/MFA dependency, durable Idempotency-Key receipt και expected active version. |

Private/draft/restricted/expired source records δεν εμφανίζονται. Address/website field permissions εφαρμόζονται στην projection. Source payload δεν εξάγεται στο user API. Η βασική search είναι text containment/ID order, όχι ακόμη personalized relevance ranking· αυτό ακολουθεί με τον compiler/retrieval stage.

## Verification και συνέχεια

**89 tests passed**, από τα οποία 20 νέα catalog checks: source/hash/geometry/license validation, duplicate handling, exact counts, rollback/retirement/private-reference preservation, policy/retention, searchable aliases/radius/pagination και admin publication. `alembic check`: no new upgrade operations. Full PostgreSQL preview: 436 statements parsed με pglast, χωρίς PostgreSQL execution. Actual source import/publication/readback έγιναν σε local SQLite.

Artifacts: `.local/stage3/import-result.json`, `publication-result.json`, `verification.json`, `schema.sql`, complete source/manifest και `.local/baselines/catalog-before-stage3.sqlite`. Δεν έγινε real Supabase connection/Auth/RLS test, remote migration, frontend change ή inference.

Επόμενο μέσα στο Stage 3: source/evidence review και **Luna-only** enrichment για τις 500, με actual deployment/tool audit και συγκεκριμένα budget/caps πριν paid calls. Η μεγάλη basic βάση προηγείται του generation και θα παραμείνει μεγαλύτερη από το enriched subset. Μεταφορά στο Supabase χρειάζεται τα ήδη εκκρεμή local connection settings και connected checks. Το 105 MB SQLite measurement δεν πιστοποιεί PostgreSQL/PostGIS size, egress ή free-plan capacity για πρόσθετες πόλεις.
