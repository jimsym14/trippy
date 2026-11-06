# Place preview and reference retention

The native draggable sheet opens at 360pt (280pt for areas), expands to large, and exposes Save, Pin, Directions and More. There is one combined place card, with no Apple/Google/Both selector or separate Apple provider card. The preview shows up to four 640px photos; summaries expand in the large detent.

The Google photo gateway now accepts references up to 4096 characters rather than 500. ThreadingHTTPServer prevents slow photos from serializing unrelated search/details requests. Photos are live, ephemeral and attributed; failures show the provider message where available. Live rendering against the deployed gateway has not been verified.

Hosted Supabase migration `durable_google_place_references` creates private `trippy_catalog.google_place_references`. RLS is enabled, with all access revoked from public/anon/authenticated. Only the server database role accesses this table. The intentional no-policy advisory describes its deny-by-default access. A transactional insert/read/rollback verified the table.

POST /api/places/retain requires the existing bridge token and accepts at most 100 validated IDs with source tags pins/saves/trips/videos/viewed. DATABASE_URL stays on the server. There is no catalog delete endpoint, and removal from a personal library does not delete references. Known IDs are registered independently of map filters. Video-source references do not create manual user pins. Places without a Google ID require resolution first; the current sheet resolves when opened.

The database stores only Google IDs and app source tags. Google photos, ratings, reviews, summaries and addresses are fetched live, not stored permanently, following https://developers.google.com/maps/documentation/places/web-service/policies . This is not an offline Google-details cache. Source tags are catalog provenance, not per-user ownership or library records.

The new gateway code must be deployed with DATABASE_URL and existing bridge/Google configuration before automatic registration and the photo fix reach the phone. Missing database configuration reports HTTP 503 and catalog.unavailable in performance logs without blocking the place preview.

Map annotation bounds updates preserve the projected center, rather than resetting frame origin during star transitions. Physical-phone behavior remains to be verified.

Checks: three mocked gateway tests, four existing research transport tests, simulator compilation. No paid Google API request was performed.

## Google content redesign

PlaceDetailsContent separates rating/status chips, photos, description and attribution from expandable hour/review cards. It uses Plus Jakarta typography and librarySurface styling, plus subdued photo borders. All returned reviews, attributions, visit dates and links remain available. Initial detent lowered to 360pt; large reveals the full summary.

The combined sheet uses immediate Apple/basic name, address and contact data as fallback and enriches shops with Google details. Geographic areas skip Google enrichment. Call and Website are deduplicated, and linked videos use compact play/title/summary rows with associated notes. Provider attribution remains visible. This selects a practical information mix; Google paid fields remain billed at the configured provider tiers.

## November 5 corrections

Shop sheet peek lowered to 260pt, with an intermediate 520pt detent and large. Removed X and bottom action bar. Save/Pin/More are below the title; Directions/Call/Website share one contact row. City badge aligns with title, with a taller 40pt two-row label and separated counters.

STATLAS public snapshot retrieved 2026-11-05 includes 3000 real city entries, reduced to identity, coordinates and safety/cost/bars. Bundle size about 405KB. It supplies immediate fallback with background live refresh; fresh in-memory live data takes priority. Attribution retained in UI. Named-city matching prevents Barcelona from resolving to nearer Eixample. Swift verification decoded all entries and checked Barcelona (89.8 safety, 158.2 cost) plus rejection for wrong country. No fabricated values. Source: https://statlas.net/api/map?metric=safety-index . Data: CC BY 4.0.

Google failure messages are now visible with Retry rather than one generic hidden error. Missing bridge token is distinguished from HTTP/provider and decoder/transport failures. Details timeout 15s. Gateway field mask uses documented top-level photos/reviews/hour objects. Actual deployed failure remains unverified pending Render workspace confirmation; external gateway request timed out. Do not claim live Google photo/ratings success.

## Render inspection

Confirmed workspace My Workspace (tea-dbgc5o4s728c73dvmheg). Service srv-dbgcde67bikc73fmn190 is on free plan, auto-deploys main, and still runs b2e0720 from November 3. App logs show several Google searches reaching send_json(200) after clients disconnected (BrokenPipeError). This proves some Google search requests succeeded upstream, but does not verify details/photos or identify every failure.

Gateway concurrency/photo/field-mask/reference changes and sanitized status logging committed locally as 38e191a. Terminal GitHub push failed DNS twice; connector blob creation was denied HTTP 403 Resource not accessible by integration. Browser access host is unavailable. No deployment happened. App place-ID resolution and detail fetch can now wait up to 90s for a free-service cold start; interactive search keeps its 6s limit.
