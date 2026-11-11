# Saves, pins, videos, notes and trips: one architecture

Pins, saves, saving a video, saving to a trip and saving a video to a trip all end up in the same place: the map. That made them look like five features. They are **one record shape**, combined in different ways:

> **What** (a place or a video) × **Where** (General or a Trip) × **How strongly** (pin or Must do)

| Word in the app | What it really is | Purpose |
| --- | --- | --- |
| **Place** | One real venue. Identity = `PlaceKey` (`google:<place_id>`, else folded `name\|city`). | Never duplicated. Every pin, note, take and video mention of the same venue points at the same key. |
| **Pin** | A place in a collection, `pinned = true`. | "I'm interested." It's the default whenever anything brings a place in. |
| **Must do** (heart, stored as `saved`) | The same record, `saved = true`. | "I really want to go." It's a stronger intent on the same pin, not a second record. |
| **Collection** | General (`savedPlaces`) or a Trip (`trip.savedPins`). | Saving *to a trip* only changes where the record lives. |
| **Video** (source) | A post you shared (`ImportedSocialSource`), with `destination.tripID` = its collection. | Where places and tips came from. Saving a video means its places are pinned into the video's collection, with `sourceIDs` recording which videos mentioned each place. |
| **Note** | Text about a place (`kind = "place"`, one per `PlaceKey`), a tips post (`kind = "tips"`), or your own (`kind = nil`). | Your memory. Each video writes its own section (`fromSources[sourceID]`), and you write `userText`. |
| **Take** | Your one-tap answers about a place (`PlaceTake`, one per `PlaceKey`). | Been? Got in? Overhyped / value for money / expensive / cheap / modern / traditional / mid / nothing special. |

### Notes come in four shapes

| Shape (`kind`) | One per | What is in it | Links to |
| --- | --- | --- | --- |
| **Place** (`place`) | real place (`placeKey`) | what each video said about that place, plus your own text | the place, every video that mentions it, its trip |
| **Tips** (`tips`) | city (and trip) | general advice with no single venue: transport, money, etiquette. Every video about the city adds its own section | the videos |
| **Guide** (`guide`) | video | the whole video on one page: its general tips, then each place with the tips for that place | every place of the video (`linkedPlaceIDs` = their `PlaceKey`s), the video |
| **Yours** (`nil`) | note you wrote | your text | whatever you linked |

A tips-only post writes a tips note. A places post writes a place note per place and one guide. A mixed post writes all three. Tips with no city stay in a note of their own. Re-reading a video replaces its sections; a section that no longer applies is removed, and a note left empty goes with it. Videos read before guides existed get theirs when the library next loads (`backfillGuideNotes`).

## What a shared post is, and where it is filed

One Gemini read per post (unchanged cost) now also returns:

| Field | Values |
| --- | --- |
| `relevant` | false for anything not about travel: nothing is pinned, no note is written, and the verdict is kept so nobody pays to read it again |
| `guide_types` | venue, area_guide, city_guide, themed_list, route, hidden_spots, must_see, tips, foods (a post can be several) |
| `scope` | level (place … continent), name, the widest named region ("Alps", "Balkans") and every country it covers |
| `theme`, `foods`, `route` | "cheap eats"; dishes with where to have them; a route's mode, days, cost and stops in order |

**The relevance gate never trusts the caption alone** (the Interrail slideshow we tested has an empty caption). The free text the phone already has (caption, stickers, slide OCR, auto-captions) is checked first; only when it can't tell either way does a tiny call look at that text plus the cover and first slide. If that call fails, the post is read anyway.

`trippy/social/guides.py` files every read post under its own level and every level above it (a Rome food list shows under Rome, Italy and Europe; an Interrail route under each country it crosses). Tips pool the same way: a city's own, then its country's, then its continent's, each said once. Served by `/api/community/guides` and `/api/community/tips`, shown in **Community → Guides**, and opened as a full-screen story (one idea per page).

## One index: the Library atlas

`ios/Trippy/LibraryAtlas.swift` builds `LibraryAtlas` from the stores above every time the Library draws. Nothing new is stored. It holds one `AtlasPlace` per real place with everything that points at it (pins in General and in trips, the videos, its note, your take, its trips) and the same links backwards (`places(inVideo:)`, `places(inTrip:)`, `noteIDsByVideo`). A place found once by Google ID and once by name is merged; two Google IDs that share a name stay apart. Each place carries a `search` string made of its own words and the words of what links to it, so searching "burnt leek" or a creator's handle finds the place.

- **Pins tab** (`AtlasPlacesView`): each place once, grouped by city, with chips that jump to its videos, note, take and trips. Filters: Must do, From videos, Noted, In trips, Been.
- **Notes tab** (`AtlasNotesView`): filters by shape (Guides, Places, Tips, Yours); each note shows the places and videos it links to.
- **Place sheet** (`AtlasPlaceSheet`): everything about one place, opened from any tab.
- **Videos tab**: each poster shows how many places and notes it produced and the trip it was saved to.

So "save video to trip" is just **video × Trip**: its places become pins in that trip, its notes are filed under that trip, and it is still the same place everywhere else.

## Video → everything, once

1. **Share.** The phone asks the bridge whether the post is already indexed (`POST /api/social/extract` with `probe: true`, keyed by `tiktok:<post id>`).
2. **Indexed already** (by anyone): the stored read comes back immediately. No upload, no Gemini call, no Places call and no credit is spent.
3. **Not indexed:** the media is uploaded and Gemini reads it **once**. The result is stored in `.local/social-index/videos.sqlite` for every later saver. Two people sharing the same post at the same moment share one job.
4. The read returns `post_kind` (`places` / `tips` / `mixed`), `tips[]` and, for each place, `moments[]`: the caption/speech timeline (`0:09 — "the burnt leek is the dish"`).
5. The app then, for each place:
   - **Pin:** adds the place, or joins the existing pin for the same place, in the video's collection (+ `sourceIDs`).
   - **Note:** adds the place's single note, or adds this video's section to it. Re-reading replaces that section. Places the re-read no longer finds lose only this video's section.
   - Tips posts get a **tips note** and sit in the **Tips** shelf of Videos.

## Public vs yours

Every indexed video is **public**: TikTok posts anyone shared (read once) and the YouTube creator videos from the research pipeline. Browse them in **Videos → Community** (`/api/community/videos`, `/api/community/video`). Each video is organised by category, with the creator's stance (Recommended / Mixed / Skip it) and a timeline whose timestamps open YouTube at that second. Tips have their own tab. Only our short summaries and a link are shown, never transcripts or verbatim quotes.

Nothing from the community lands on **your** map by itself. Pins happen only when:

| You… | Result |
| --- | --- |
| share a TikTok to trippy | its shops are pinned in the share's collection (as before) |
| **Save** a community video → *Save to «City»* | the video is kept with that city; **no pins**, no place notes (`destination.mode = "video"`) |
| **Save** → *Save and pin all N spots* | the video is kept and every shop with coordinates is pinned |
| tap 📌 on one shop in a community video | just that shop is pinned |

A shop's card on the map shows a **"N TikToks & videos about this place"** button that jumps to the section listing them. The list comes from `/api/community/place` and matches by Google place ID, or by the same name in the same city.

## Trip plans

`bridge_server.community_plan_nodes` fills the planner's `community_nodes` (weight 10, far below your own pins/saves at 90–100), and keeps them with the job so retries are identical. A community place is used only if:
- it has real coordinates;
- the creator recommended it (or was mixed);
- its category is one the trip asked for;
- it isn't excluded;
- the community hasn't clearly rejected it (3+ takes and a majority of overhyped/mid/nothing special, or a majority turned away);
- it fits the user's own preferences (budget trips drop places most people call expensive; traditional/modern taste drops the opposite).

YouTube creator venues already linked to catalog identities are added the same way, so live providers get them too.

### You choose which videos feed a plan

The trip form's last step lists the indexed videos for the destination (`GET /api/community/plan-sources?city=`, a count over what is already indexed, no provider call). The choice travels in the brief as `community: {use, videos}`:

| `use` | What the planner gets |
| --- | --- |
| `auto` (default, and what older app versions send by omitting the field) | the rules above |
| `picked` | only the ticked videos. Everything they recommend counts, not only the trip's categories, and it ranks at 50: above automatic community (10), below your own videos (60) |
| `off` | no community places, including the YouTube creators' combined picks |

## Quick take (a button, one question at a time)

Each place in a post, and each place note, shows `PlaceQuickTakeCard`: the summary, the caption timeline, a **Your take** button and a **Note** button. *Your take* opens `PlaceTakeFlow`: *Have you been?* → *Did you get in?* → *How was it?* (multi-select) → *Anything to remember?* Each answer moves on by itself. **Not yet** and **Didn't get in** end the flow there.

- Every tap saves straight away. Opposite tags (cheap/expensive, modern/traditional) clear each other.
- The last step appends `«Name»'s notes: …` to the place note. **Note** opens the full editor, where every section, including what the video wrote, is editable.
- The map button opens the place's link: Google Maps by place ID, or Apple Maps by coordinates.

## Collected knowledge across users

`/api/places/takes` (`.local/social-index/takes.sqlite`) keeps one answer per person per Google place ID (the account if signed in, else the install). It returns only counts, such as "in 3 videos · 12 been · 80% got in", and per-tag counts shown on the bubbles. It also returns the tips repeated most across every indexed video of that place. Voters are never returned. Personal free-text notes stay on the phone; only structured answers and public video tips are shared.

## No double counting

- The map already merges markers by place ID, Google ID and name+point (`MapPlaceIdentity`). The same place pinned, hearted and mentioned by two videos is one marker.
- The Videos header and the share recap count unique `PlaceKey`s, not mentions.
- A pin, a video mention and a note of the same place are one place with three views of it. They're never three places.

## Not done yet

- The shop card shows community videos but not the take card yet.
- Community YouTube videos exist for Barcelona only (that's what the research pipeline has extracted). Their places have no coordinates of their own, so they can't be pinned one by one; they reach plans through catalog-linked endorsements.
- Trip shares made before this change keep their places on the general map. Only new reads pin into the trip.
