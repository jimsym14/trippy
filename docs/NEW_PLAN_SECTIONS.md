# New plan layout: sections, sources, costs

Notes from 8 November 2026, from your list of what the new plan should have.

**Today's gap:** the planner returns no tickets, transport, holiday checks, booking tasks or cost estimate.
Both the current and blend planners report these as gaps
(https://claude.ai/artifact/XWAgSwN9cbWtdrHPCoTYnw).

**Costs:** per plan unless noted. Shared caches are per city and month, so most users pay nothing for them.

## Navigation
- **Section bar:** a sticky row of section chips at the top (Days · TikTok · Food · Nightlife · Sights · Museums · Transport · Costs · Checklist). Tapping one scrolls to its section; the active chip follows scrolling.
- **Sections:** every section folds open and closed with a plain chevron. The open/closed state is remembered per plan.
- **Empty sections:** a section with nothing in it isn't shown, and neither is its chip.

## Sections

| Section | What it shows | Source | Cost | Tier |
|---|---|---|---|---|
| Days | Timeline per day, as now | Planner | in plan | Free |
| From your TikToks | Saved TikTok places in this city, with the creator's tips, and which day they're on | Our extraction, already stored | $0 | Free |
| Food | Lunch and dinner picks with a reason, what to order, when to go, price band | Blend tips; TikTok notes first | in plan (blend) | Free; "more picks" is Plus |
| Nightlife | Bars and late spots with the same detail: music, crowd, when it fills up | Blend, bar/club categories | in plan | Free; "more" is Plus |
| Sights | Sights with a short why and a tip; landmarks marked as such | Blend + Wikidata | in plan | Free |
| Museums | Museums with free days, closing day, and time needed | Blend; free-day facts via AI fill, cached per museum | ≈ $0.002 once per museum per month | Free shows the list; Plus fills the details |
| Each kind of stop | Coffee, markets, parks and so on, each as its own short list | Blend categories | in plan | Free |
| Holidays | One line: "No public holidays on your dates" or the holiday and what closes. A calendar only when something closes. | Public holiday API (free, e.g. Nager.Date) + cached closure rules | $0 | Free |
| Transport | Line map with toggle per line, ticket options for this trip, airport transfer | Line shapes from OpenStreetMap route relations (free, cached per city); fares cached per city | $0 per plan; ≈ $0.01 per city per month to refresh fares | Map free; personal fare advice Plus |
| Costs | Expense picture with a simple calculator | Plan prices + user's own entries | $0 | Free |
| Checklist | Bookings, tickets, documents, packing, by date | Planner booking tasks + AI fill for missing deadlines | $0 / fill | Free list; Plus fills deadlines |

### Food and nightlife: genuine tips
- **Order of sources:** the user's TikTok notes first (real people, already ours), then the blend's tips. The blend is told to write like a local alternative blog: what to order, where to sit, what to skip.
- **With billing on the Gemini key:** Google Search grounding lets the tips cite actual blog posts. That costs about $0.014 per search and fits Plus.
- **"Not touristy" carries through:** places over 10,000 reviews or tagged as postcard landmarks are dropped from food and nightlife.

### Transport section
- **Map:** MapKit overlays drawn from OpenStreetMap route relations, fetched once per city through the Overpass API and stored as a small file. Metro, tram and bus lines each have a chip to show or hide them.
- **Personal ticket advice:**
  - **Inputs:** trip days, traveller ages and student status (asked once, see AI_PILLS_AND_FILL_BUTTONS.md).
  - **Fares:** the city's fare table (single, day pass, 3-day, 5-day, airport, reduced fares), refreshed monthly by one grounded AI call and checked against the operator's page.
  - **Output:** "2 people × 3-day ticket = €40, cheaper than 12 singles (€50)". The arithmetic is ours, not the model's.
- **Cost:** about 1 cent per city per month; $0 per plan.

### Expense picture and calculator
- **What it shows:** one bar per day, split by kind (food, tickets, transport, stay), with a total and per-person figure on top.
- **Changing it:** tapping a segment opens its items; any price can be edited. Totals update live and split by traveller count.
- **Missing prices:** they show as "unknown", never as €0. Plus users get an AI fill button there.

### Checklist
- **Grouped by when:** Before you go / On day 1 / On day 2.
- **Built from:** the plan (book Acropolis tickets, reserve dinner at X), the transport section (buy the 3-day ticket at the airport), and documents (ID, insurance).
- **Missing deadlines:** each one is a single AI fill (Plus), batched per plan.

## Free vs Plus
- **Free:** every section, the transport map, the holiday line, the calculator, the checklist.
- **Plus:** more picks per section, AI fill for empty fields (ticket prices, deadlines, museum free days), personal fare advice, blog-cited tips, live pills while typing.

## Build order
1. Section bar + foldable sections, and drop empty sections (app only).
2. Holidays line and expense calculator (free data, no AI).
3. TikTok, food, nightlife, sights, museums sections, from blend data already in the plan.
4. Transport map from OpenStreetMap, then fares.
5. AI fill buttons and Plus limits.
