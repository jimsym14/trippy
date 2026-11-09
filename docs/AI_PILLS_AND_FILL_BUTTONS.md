# Pills and AI fill buttons

Notes from 8 November 2026. Goal: richer input and richer plans without loose AI calls. Every AI call
has a known slot, a fixed output shape, a cost and a cache key, and runs only when the user asks or
the slot is empty.

## 1. Pills on the input page

### New pill: "Not touristy"
Keep this exact name. It's the most useful steer the Athens plan lab found
(https://claude.ai/artifact/SxjNnWQtAXy7jYPqtXkSW4).

What it does in the pipeline:
- It prefers places with local-language reviews and moderate review counts.
- It keeps at most one landmark a day, and only when it's the best option for that slot. The plan says why.
- It swaps famous viewpoints for quieter ones, unless the user also picked "First time here".
- It is measurable: share of stops over 10,000 Google reviews. The quality gate can track it.

### More pills, grouped (each maps to retrieval and ranking signals, not just prompt text)
- **Pace:** Slow mornings · Packed days · Siesta break · Late nights
- **Feel:** Not touristy · Local favourites · Hidden gems · Classic must-sees · First time here · Been before
- **Food:** Old-school tavernas · Street food · Specialty coffee · Natural wine · Seafood · Vegetarian-friendly · Michelin-ish · Cheap eats
- **Doing:** A bit of history · Deep history · Art · Markets · Bookshops · Viewpoints · Sunset spot · Beaches · Hikes · Nightlife · Live music
- **Who:** With kids · With grandparents · Accessible · With a dog · Solo · Couple
- **Budget:** € · €€ · €€€ · Free things first

Each pill has a definition in code: retrieval queries it adds, ranking weights it changes, and a sentence
for the model. Pills stay data, so the free tier gets them all at no AI cost.

### Live pills for Plus (while typing)
- **Trigger:** typing pauses for 1.2 s, the request text changed by at least 12 characters, and at most one call every 8 s.
- **Output:** one call to Flash-Lite (about $0.0004) returns:
  - up to 6 suggested pills from the fixed list;
  - up to 3 new free-text pills, for example "Rembetiko night";
  - one tip line.
- **Shape:** fixed JSON; anything outside the shape is dropped.
- **Animation:** suggestions slide in as ghost pills; tapping one makes it solid.
- **Never:** no call per keystroke, no call on the free tier. The free tier gets keyword-matched pill suggestions from the fixed list, offline.

## 2. AI fill buttons in the plan (Plus)

Rule: **show a button only where the pipeline left a field empty.** Never hide or replace data we already have.

### Slot registry (decide every fillable field ahead of time)
Each fillable field is one registry entry:

| Field | Inputs it needs | Output shape | Model | Cache key | Shared? |
|---|---|---|---|---|---|
| Ticket prices | traveller groups (see below) | `{adult, student, senior, child:{price, max_age}, free_rules[], source_url, checked_on}` | Flash + search grounding | place ID + month | Yes, across users |
| Opening hours on the trip dates | dates | `{date: hours or "closed", reason}` | Flash-Lite + grounding | place ID + date | Yes |
| Booking needed? | date, party size | `{required: bool, lead_days, url}` | Flash-Lite + grounding | place ID + season | Yes |
| Getting there (between stops) | from, to, time | no AI: Apple travel times | — | — | — |
| Places to stay | dates, budget, area pills | `[{name, area, why, price_band}]` max 5, each checked by place ID | Flash + checks | city + area + budget + month | Partly |
| Flights | home airport, dates | `[{route, typical_price_band, airlines}]` plus deep links | Flash-Lite + grounding | route + month | Yes |
| What to order | place ID | `{dishes[] max 4, tip}` | Flash-Lite, from our TikTok notes first | place ID | Yes |
| Rainy-day swap | plan day | `{replace_stop, with_place_id, why}` | Flash-Lite over the existing pool | plan + day | No |

### Traveller groups, asked once
Ticket prices need to know who is going. Ask once in trip setup, in its own small section, not on every button:
- adults; students (with or without an EU student card); seniors (age); children (ages);
- citizenship group (EU / non-EU), because many European sites price by it.

The ticket button then asks Gemini only for the groups present. If the trip has no children, the
answer has no child price.

### Making calls efficient
- **Batch per plan:** one tap on "Fill missing ticket prices" fills every empty ticket field in the plan in one call, not one call per stop.
- **Shared cache:** a fact like a museum's ticket price, cached by place ID and month, serves every user. Most taps will cost nothing.
- **Fixed JSON schemas** with `source_url` and `checked_on`. If the model can't find a source, the field says "Not found", never a guess.
- **Model per field:** Flash-Lite by default. Flash only where reading many sources matters (tickets, places to stay).
- **Credits:** each fill uses one Plus credit, and a batch counts once. The calculator in Settings should get a "fills per user" line.
- **Logging:** each fill records field, cache hit or miss, model, tokens and cost, so the admin dashboard shows which buttons are worth it.

### Design
- **The button:** a small "✦ Fill" capsule in the empty field's place, using the Sketch palette.
- **While filling:** a shimmer.
- **When filled:** the value fades in with a "✦ AI · source" chip. Tapping the chip shows the source link and the date it was checked.
- **Sheets for inputs:** fields that need inputs, such as traveller groups or the home airport, open a short sheet the first time, then remember the answer.

## 3. Plan pipeline direction (from the plan lab)

The best plan came from the "blend":
1. Gemini Flash-Lite suggests places for the request and pills.
2. Each suggestion is confirmed as a real place by ID.
3. Flash-Lite builds the days, choosing only from real IDs.
4. Our engine validates the result and drops repeats, invented IDs and long walks.

Measured: about 7 s and $0.007 of AI.

Open items:
- Better name matching (Greek and shortened names).
- Grounding with Google Maps once billing is on.
- Run the quality gate across several cities.
