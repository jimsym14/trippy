# Trippy: limits, costs, bottlenecks and a business model

November 2026. Prices are list prices from third-party summaries of each provider's pricing page. Check them
on the provider's own page before committing money. Call counts per action are read from the code. The live
version of the bottleneck table is on the admin dashboard (`/admin` → *Limits, costs and bottlenecks*) and in
the app's Admin screen. Both come from [`trippy/capacity.py`](../trippy/capacity.py), so update prices there.

Real usage so far (admin API, 7 Nov 2026): 2 installs, 53 requests and 16 Google calls (8 searches, 8 card
opens). No plans or videos have run on the server yet, so every per-user figure below is an estimate.

---

## 1. What each action costs

| Action | Google calls | AI | Cost once the free calls are spent |
|---|---|---|---|
| One trip plan | 10 Text Search (Enterprise) | Azure intent (<$0.01), Gemini notes (free tier) | **≈ $0.36** |
| One video read (~5 places) | ~7 Text Search + 5 Place Details with reviews | Gemini 1–2 calls (≈$0.01 on the paid tier) | **≈ $0.38** |
| A month of browsing | 30 photos, 6 cards, 5 searches, 5 hours checks | none | **≈ $0.64** |
| **An "active user" month** (1 plan + 4 videos + browsing) | ~43 Text Search, 26 Details, 30 photos | ≈ $0.05 | **≈ $2.47** |

Google sets the free calls per **billing SKU**, not per feature. Plans, video matching and search in the app all
bill as *Text Search (Enterprise)* and share **1,000 free calls a month**. The old admin table showed 1,000 free
for each of the three, which overstated the free room three times over. The new SKU table fixes this.

### Measured on 11 Nov 2026: the new default planner

`scripts/planner_cost_quality.py` runs real plans through the live path (AI place ideas checked on OpenStreetMap, notes by Gemini, no Google call) and counts every call. Costs are paid-tier list prices with tokens estimated from text length; on Gemini's free tier each of these is $0.

| Trip | First plan | AI calls | OpenStreetMap lookups | Paid-tier cost | Same request again |
|---|---|---|---|---|---|
| Rome, 3 days, 2 people | 2.5–4.5 min | 3 ideas + 1 notes | 37–43 | **≈ $0.03** | 0 calls, under 3 s |
| Athens, 2 days, 4 friends | 1.5 min | 3 + 1 | 24–28 | **≈ $0.025** | 0 calls, instant |
| Lisbon, 4 days, 3 people | 2 min | 3 + 1 | 34–41 | **≈ $0.03** | 0 calls, instant |
| Barcelona, 2 days, with 23 indexed videos | 1 min | 2 + 1 | 20 | **≈ $0.02** | 1 notes call, 20 s |

Against the old default (10 Google Text Search calls, ≈ $0.36 a plan after the free calls) that is roughly **a twelfth of the cost**, and no Google rating is used to choose places. The price is time: the free OpenStreetMap check allows one lookup a second, so a first plan for a new request takes minutes. Lookups are kept for a month and shared by everyone, so a city gets faster as it is planned. A self-hosted or paid lookup server would remove the wait (see the optimization path).

Automatic checks on those plans (every day has stops, two meals a day, asked-for categories and must-sees present, no repeats, walks between stops under 45 minutes): Athens, Lisbon and Barcelona pass; Rome fails one check (one 48-minute walk between two stops). Known gap: the last day of the 4-day Lisbon trip has an empty afternoon. Whether a plan is one you would enjoy still needs a person to read it.

## 2. Bottlenecks in every part of the app

"When" means when the limit bites: **Now** = with a handful of users, **Soon** = tens to a hundred,
**At scale** = hundreds to thousands.

| Part | When | Free limit | One user | Many users | Upgrade | Code? |
|---|---|---|---|---|---|---|
| Google Text Search (plans, video matching, search) | **Now** | 1,000 / month, shared | Fine (a heavy user ≈ 170) | ~20 active users use it up, then ≈ $1.50 per active user | IDs-only search (free SKU) + details only for kept places; cache by city; drop rating fields from video matching (Pro SKU, 5,000 free) | yes |
| Google Place Details with reviews | Soon | 1,000 / month | Fine | ~40 active users | Polish video places when the card opens, not up front | yes |
| Google Photos (proxied by the bridge) | Soon | 1,000 / month | Fine | ~30 active users; the bytes count as Render bandwidth | One photo per card, more on tap | yes |
| Admin Google caps | **Now** | ~4,000 free calls across all SKUs | — | The default "everyone" cap (200 a day = 6,000 a month) allows **$45–175 a month** of paid calls | Set Cloud Console daily quotas (~33 a day per SKU) and a $1 budget alert. This is the only hard $0 guarantee | no |
| Gemini (videos, plan notes) | Soon | Per-model daily and per-minute limits; 6-model fallback pool | Each call takes ~55 s and the timeout is 60 s | Long videos ≈ 85k tokens; few fit per minute. Google may use free-tier inputs, so a privacy policy must say so | Turn on billing (≈ $0.01 per video); raise the timeout to 150 s | timeout only |
| Azure OpenAI (reading the trip request) | At scale | Paid, capped at $15 | Fine | ~1,500 plans, then planning stops | Raise the budget or move this step to Gemini | no |
| Render (bridge) | Soon | 512 MB, 0.1 CPU, sleeps after 15 min | First request after a quiet spell waits ~1 min; a restart loses plans and videos in progress | One video worker; ~5 big uploads at once can run out of memory | Starter $7 at launch; jobs in Postgres plus a separate worker past ~500 users | later |
| Supabase email codes | **Now** | Built-in email ≈ 2 per hour for the whole project | Works for you | The 3rd sign-up in an hour gets no code | Custom SMTP (e.g. Resend free tier, ~100 a day / 3,000 a month) | no |
| Supabase Postgres | At scale | 500 MB, 5 GB egress, 50k MAU; pauses after 7 idle days; no backups | Fine if something uses it weekly | ~1,000–2,500 accounts with backups (200–500 KB each, 8 MB max) | Pro $25 at ~1,000 accounts or at public launch (backups); later keep backups in Storage | later |
| Free credits | **Now** | 3 plans + 20 videos per account a month | The shared app token skips credits (development) | A maxed account ≈ **$9 a month**; 5 of them use all free Text Search; new account = new credits | Free = 1 plan + 3 videos, shared daily pool with a queue, credits tied to the device | yes |
| Apple signing | **Now** | Free Apple ID: 7-day installs, only phones plugged into your Mac | Reinstall every 7 days | Friends can't install remotely | Developer Program $99/yr → TestFlight | no |

### Supabase: what the current app needs

| Setting | Current app | Free plan | Verdict |
|---|---|---|---|
| Monthly active users (auth) | you + friends | 50,000 | plenty |
| Auth emails | 1 code per sign-in | ~2 an hour built in | **set up custom SMTP now** |
| Database | stats rows (~2 KB per active user a day) + 1 backup per account (≤ 8 MB) | 500 MB | fine to ~1,000 accounts |
| Egress | backups sync on sign-in and backup | 5 GB | fine to a few hundred users |
| Inactivity | the bridge writes stats only when someone uses the app | pauses after 7 idle days | a paused project means nobody can sign in; add a weekly ping or use Pro |
| Backups | account snapshots live here | none on Free | Pro before strangers trust you with data |

## 3. Fixed costs

| Item | Per month | Per year | When you need it |
|---|---|---|---|
| Claude Pro | $20 monthly, or $16.67 on annual | $200 annual / $240 monthly | Building (now). Max 5x is $100 a month (monthly only) if you go full time |
| Apple Developer Program | $8.25 | $99 | Before sharing with friends remotely, TestFlight, the App Store or Sign in with Apple |
| Render Starter | $7 | $84 | Launch (no sleep) |
| Domain (privacy policy, email sender) | ~$1 | ~$12 | Launch |
| Custom SMTP | $0 | $0 | Now (free tier) |
| Supabase Pro | $25 | $300 | ~1,000 accounts or public launch |
| Render Standard | $25 | $300 | Parallel jobs, ~1,000 active users |

**Year one, just you and a few friends:** Claude Pro $200 + Apple $99 = **$299** (≈ $25 a month). Everything
else stays free. **Public launch year:** add Render Starter and a domain ≈ **$395** plus usage.

## 4. Cost per user (from `capacity.py`)

| Active users | Setup | Google | AI | Fixed | **Total / month** | Per user |
|---|---|---|---|---|---|---|
| 1 | now (free services) | $0 | $0.05 | $24.92 | **$25** | $25 (all fixed) |
| 100 | launch (Render Starter) | $170 | $5 | $33 | **$207** | $2.07 |
| 1,000 | scale (Render Std, Supabase Pro, Claude Max) | $2,378 | $50 | $159 | **$2,587** | $2.59 |

The figure that matters is **≈ $2.40 of usage per active user a month**, and almost all of it is Google.
Mio charges $29.99 a year, which leaves ≈ $2.12 a month after Apple's 15%, and only paying users bring that in.
**At today's call pattern Trippy loses money on every active user, paying or not.** That makes the Google
optimizations below the most important business task, ahead of any pricing work.

### The optimization path (needs code)

1. **Match video places with Apple Maps, not Google.** MapKit search on the phone is free. The Apple Maps Server
   API is free up to a daily limit for Developer Program members (≈ 25,000 calls a day). Check the current limit.
   Keep Google only for ratings and photos when someone opens a card. This removes most of the ≈ $0.38 per video.
2. **Plans: IDs-only Text Search** (an Essentials SKU with free use), then fetch details only for the ~12 places
   a plan keeps, and cache place IDs per city so the second Rome plan reuses the first one's searches.
3. **Polish lazily:** fetch reviews only when a card is opened.
4. **Photos:** one per card, more on tap.

Rough target after 1–4: **≈ $0.50–0.90 per active user a month**, which works with Mio-level prices.
This is an estimate; measure it on the dashboard once real plans and videos run.

## 5. Ways to make money

| Option | How it works | Your numbers | Apple rules | Verdict |
|---|---|---|---|---|
| **Tip jar / "buy me a coffee"** | In-app consumable purchases of €1.99, €4.99 or €9.99 | Expect ~0.5–1% of active users to tip about €3; you keep 85% | Tips to the developer must use in-app purchase. A Buy Me a Coffee link inside the app is allowed only on the US storefront; a link on your website is fine | Do it, for goodwill. It won't cover costs |
| **Free tier with a queue** | Every account gets **1 plan + 3 video reads a month**. Free jobs share a daily pool and wait in line when it is empty ("ready tomorrow morning") | Per maxed free account: ≈ $1.50 today, ≈ $0.40 optimized. The free calls carry ~25 such accounts at $0 | none | **Set this now** (admin controls: plans 1, videos 3) |
| **Credit packs** | e.g. 10 video reads €1.99, 3 plans €1.99 | Net €1.69. Costs $3.80 / $1.08 today (loss on videos), ≈ $1.00 / $0.40 optimized | Consumable IAP | After the optimizations; pay-as-you-go is the safest margin |
| **Subscription "Trippy Plus"** | €3.99 a month or €24.99 a year: 5 plans + 30 videos a month (fair use), no queue | Net €3.39 or €1.77 a month. An average subscriber (1–2 plans + ~8 videos) costs ≈ $1.20 optimized | Auto-renewing IAP; Small Business Program = 15% | The main model, once optimized. Priced just under Mio ($7.99 / $29.99) |
| **Limits on calls** | Already built: per-install and global Google caps, monthly credits, blocking | — | — | Keep. Add Cloud Console quotas as the hard stop |

Recommended order: **(1)** now: free tier 1 + 3 with a queue, Cloud quotas, custom SMTP. **(2)** With the
Developer Program: TestFlight for friends, tip jar. **(3)** After the Apple Maps and lazy-detail work: Plus
subscription and credit packs.

### Freemium math

With 1,000 active free users, 3% conversion gives 30 subscribers ≈ €53–100 a month. A free user must therefore
cost close to nothing, which is why the free tier is small, queued and capped by a global pool. Without the
optimizations even 1 + 3 free costs ≈ $1.50 per active free user. Plan on most registered users being inactive in
any given month; cost follows use, not account count.

## 6. People who make new accounts for free credits

Credits are counted per account today, so a new email means new credits. Defences, cheapest first:

1. **A global daily free pool** (code). Abuse can never cost more than the pool, so the free-tier
   bill stays at $0 however many accounts exist. Extra accounts just wait in the same queue.
2. **Credits per device as well as per account** (code + Developer Program). Apple **DeviceCheck** stores
   2 bits per device for your team. They survive reinstalls and new accounts, so you can mark "free credits used
   this month" on the device itself.
3. **App Attest** (code + Developer Program). Only the genuine app on a real iPhone can call the bridge, which
   stops scripts and leaked tokens.
4. **Sign-in choices** (no code). Prefer Sign in with Apple or Google; block disposable email domains for codes.
5. **Admin blocking** (already built): block an install from the dashboard.

## 7. Scalability

* **Up to ~100 users:** fine on free services, apart from Google calls and the Supabase email limit.
* **~100–500:** Render Starter (no sleep), paid Gemini key, Cloud quotas, optimized Google use.
* **~500–5,000:** the bridge runs plans in a thread and videos on one worker, with jobs in memory. Move jobs
  into Postgres, run a separate worker, use Render Standard and Supabase Pro.
* **Beyond:** more workers, and Google volume tiers (Text Search drops from $35 to $28 at 100k+).

## 8. Questions you asked

**Can I share it with friends now without the Developer Program?** Only friends who bring their iPhone to your
Mac. With a free Apple ID, Xcode installs to phones you plug in (Developer Mode on). The install expires after
7 days: your current profiles expire on **9 November 2026**. There is a limit of 3 free-team apps per phone, and
no TestFlight or Sign in with Apple (email codes work). For friends elsewhere you need the **$99 program** and
TestFlight (up to 10,000 testers, builds last 90 days).

**Does the app work when my phone is not on the same Wi-Fi as my Mac?** Yes. The app talks to the Render bridge
(`trippy-research-89fm.onrender.com`), not to your Mac, so it works on any network or on cellular. Caveats:
the first request after 15 quiet minutes waits about a minute while Render wakes up. The installed build
stops opening when its 7-day profile expires; reinstall from Xcode. Server-side features (such as reading
video frames) arrive only after the bridge redeploys from GitHub.

**Is Trippy a reasonable product next to Mio and Been?** Mio (TikTok/Reels → map, $7.99 a month / $29.99 a
year) and Been-style trackers ($10–23 a year) each do one thing. Trippy does both, plus AI day-by-day plans,
so a price in Mio's range is defensible. The open question is unit cost, not price: section 4.
