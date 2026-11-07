"""Bottlenecks, free limits and cost per user, for the admin dashboard and the in-app admin screen.

Pure data plus arithmetic, no network. Prices are list prices checked in November 2026
(third-party summaries of each provider's pricing page); confirm them on the provider's own
page before relying on them. Per-action call counts are estimates read from the code:
* a plan makes up to 10 Google Text Search calls (`personal_pipeline.tasks[:10]`),
* a video matches ~5 places, ~1.3 searches each, then one Place Details (reviews) per match,
* a person browsing for a month opens ~30 photos, ~6 place cards, ~5 searches, ~5 hours checks.
The full write-up is docs/BUSINESS_AND_LIMITS.md.
"""
from __future__ import annotations

# --- Google Places SKUs (USD per call after the monthly free calls) ----------------
# Free calls are per SKU per billing account per month, shared by every metric on that SKU.
SKUS = {
    'text_search_enterprise': {'label': 'Text Search (Enterprise)', 'free': 1000, 'price': 0.035,
                               'metrics': ['google:text_search', 'google:app_search', 'google:social_search']},
    'details_atmosphere': {'label': 'Place Details (Enterprise + Atmosphere)', 'free': 1000, 'price': 0.025,
                           'metrics': ['google:details']},
    'details_enterprise': {'label': 'Place Details (Enterprise, hours)', 'free': 1000, 'price': 0.020,
                           'metrics': ['google:hours']},
    'photos': {'label': 'Place Photos', 'free': 1000, 'price': 0.007, 'metrics': ['google:photo']},
}

# Calls per action, per SKU.
ACTIONS = {
    'plan': {'label': 'One trip plan', 'google': {'text_search_enterprise': 10}, 'ai_paid_usd': 0.01},
    'video': {'label': 'One video read (~5 places)', 'google': {'text_search_enterprise': 7, 'details_atmosphere': 5}, 'ai_paid_usd': 0.01},
    'browse': {'label': 'A month of browsing', 'google': {'photos': 30, 'details_atmosphere': 6, 'text_search_enterprise': 5,
                                                          'details_enterprise': 5}, 'ai_paid_usd': 0.0},
}
# An "active user" month: one plan, four videos, normal browsing.
ACTIVE_MONTH = {'plan': 1, 'video': 4, 'browse': 1}

# Fixed monthly costs (USD) at each stage.
FIXED = {
    'now': [('Apple Developer Program', 99 / 12, 'Needed for TestFlight, the App Store, Sign in with Apple, installs that last over 7 days'),
            ('Claude Pro (annual)', 200 / 12, '$200 a year; $20 a month if paid monthly'),
            ('Render (free)', 0, 'Sleeps after 15 min idle'), ('Supabase (free)', 0, 'Pauses after 7 idle days'),
            ('Gemini (free tier)', 0, 'Google may use free-tier inputs to improve its models')],
    'launch': [('Apple Developer Program', 99 / 12, ''), ('Claude Pro (annual)', 200 / 12, ''),
               ('Render Starter', 7, 'Always on, 512 MB'), ('Email (custom SMTP, free tier)', 0, 'Needed for email sign-in codes'),
               ('Domain', 1, '~$12 a year'), ('Gemini paid tier', 0, 'Pay per use, cents per video')],
    'scale': [('Apple Developer Program', 99 / 12, ''), ('Claude Max 5x', 100, 'If you build full time'),
              ('Render Standard', 25, '2 GB, room for parallel jobs'), ('Supabase Pro', 25, 'No pause, backups, 8 GB database'),
              ('Domain', 1, '')],
}

# Severity: "now" = hits with a handful of users, "soon" = tens to a hundred, "scale" = hundreds to thousands.
BOTTLENECKS = [
    {'id': 'google_text_search', 'service': 'Google Places · Text Search', 'severity': 'now',
     'used_by': 'Plans (10 calls each), video place matching (~7 per video), search in the app',
     'free_limit': '1,000 calls a month, shared by all three uses', 'paid': '$35 per 1,000',
     'one_user': 'A heavy user (3 plans + 20 videos) uses ~170 a month: fine.',
     'scale': '~20 active users use up the free calls; then about $1.50 per active user a month.',
     'upgrade': 'Search with IDs only (free SKU) and fetch details only for places a plan keeps; cache by city; '
                'drop rating fields from video matching (Pro SKU, 5,000 free).', 'code': True},
    {'id': 'google_details', 'service': 'Google Places · Place Details with reviews', 'severity': 'soon',
     'used_by': 'Opening a place card, and polishing each place found in a video',
     'free_limit': '1,000 calls a month', 'paid': '$25 per 1,000',
     'one_user': 'Fine.', 'scale': '~40 active users; video polishing is most of it.',
     'upgrade': 'Polish video places only when the card is opened; ask for reviews only on the card.', 'code': True},
    {'id': 'google_photos', 'service': 'Google Places · Photos (served through the bridge)', 'severity': 'soon',
     'used_by': 'Place cards and plan maps', 'free_limit': '1,000 photos a month', 'paid': '$7 per 1,000',
     'one_user': 'Fine.', 'scale': '~30 active users; the photo bytes also count as Render bandwidth.',
     'upgrade': 'One photo per card, more on tap; smaller widths.', 'code': True},
    {'id': 'google_caps', 'service': 'Admin caps vs free calls', 'severity': 'now',
     'used_by': 'Admin controls: Google per install / day and for everyone / day',
     'free_limit': 'About 4,000 Google calls a month are free in total (all SKUs)',
     'paid': 'The default "everyone" cap of 200 a day allows ~6,000 a month',
     'one_user': '—', 'scale': 'At full use the current caps allow roughly $45–175 a month of paid Google calls (depends on which SKU the calls hit).',
     'upgrade': 'Hard guarantee, no code: in Google Cloud Console set daily quotas of ~33 for Text Search, Place Details and '
                'Photos (≈1,000 a month each) and add a budget alert at $1.', 'code': False},
    {'id': 'gemini', 'service': 'Gemini (videos, plan notes)', 'severity': 'soon',
     'used_by': 'Reading each video (1–2 calls) and writing plan notes',
     'free_limit': 'Per-model daily and per-minute limits; the pool falls through 6 models',
     'paid': 'About $0.01 per video on Flash',
     'one_user': 'Fine. Each call takes ~55 s and the timeout is 60 s, so a slow answer is retried on another model.',
     'scale': 'Long videos are ~85k tokens; per-minute token limits allow only a few at once. '
              'Free-tier inputs may be used by Google, which a privacy policy must say.',
     'upgrade': 'Turn on billing for the Gemini key (paid tier: higher limits, inputs not used for training); raise the timeout.', 'code': False},
    {'id': 'azure', 'service': 'Azure OpenAI (plan request reading)', 'severity': 'scale',
     'used_by': 'Understanding the trip request', 'free_limit': 'Paid, capped by TRIPPY_AI_BUDGET_AMOUNT ($15)',
     'paid': 'Under $0.01 per plan typically, $0.22 worst case', 'one_user': 'Fine.',
     'scale': 'The $15 cap covers ~1,500 typical plans, then planning stops.', 'upgrade': 'Raise the budget, or move this step to Gemini.', 'code': False},
    {'id': 'render', 'service': 'Render (the bridge server)', 'severity': 'soon',
     'used_by': 'Every request from the app', 'free_limit': 'Free web service: 512 MB, 0.1 CPU, sleeps after 15 min idle',
     'paid': 'Starter $7 a month (always on); Standard $25 (2 GB)',
     'one_user': 'The first request after a quiet spell waits ~1 min. A restart loses plans and videos in progress.',
     'scale': 'One worker reads videos one at a time; ~5 large uploads at once can run out of memory; photo bytes count as bandwidth.',
     'upgrade': 'Starter at launch; keep jobs in Postgres and run a separate worker past ~500 users.', 'code': True},
    {'id': 'supabase_email', 'service': 'Supabase Auth · email codes', 'severity': 'now',
     'used_by': 'Email sign-in codes', 'free_limit': 'Built-in email: about 2 emails an hour for the whole project',
     'paid': 'Custom SMTP: free tiers of about 100 emails a day (e.g. Resend)',
     'one_user': 'Works for you.', 'scale': 'A third friend signing up in the same hour gets no code.',
     'upgrade': 'Connect a custom SMTP provider in Supabase (no code); also lets you edit the email templates.', 'code': False},
    {'id': 'supabase_db', 'service': 'Supabase Postgres (stats, controls, account backups)', 'severity': 'scale',
     'used_by': 'Usage counters, admin controls, one backup snapshot per account (up to 8 MB)',
     'free_limit': '500 MB database, 5 GB egress, 50,000 monthly active users; pauses after 7 idle days',
     'paid': 'Pro $25 a month: 8 GB, 250 GB egress, 100,000 MAU, no pause',
     'one_user': 'Fine, as long as something uses it once a week.',
     'scale': '~1,000–2,500 accounts with backups fill 500 MB (200–500 KB each); syncing a big snapshot often uses egress.',
     'upgrade': 'Pro past ~1,000 accounts; store backups as files in Supabase Storage instead of rows.', 'code': True},
    {'id': 'credits', 'service': 'Free credits and shared token', 'severity': 'now',
     'used_by': 'Monthly free plans and video reads per account',
     'free_limit': 'Defaults: 3 plans and 20 video reads per account a month',
     'paid': 'A maxed-out free account costs ~$9 a month in Google calls',
     'one_user': 'The shared app token skips credits entirely (meant for development).',
     'scale': 'Credits are per account, so new accounts get new credits; five maxed accounts use all the free Text Search calls.',
     'upgrade': 'Free = 1 plan + 3 videos; a daily shared pool with a queue; tie free credits to the device (Apple DeviceCheck).', 'code': True},
    {'id': 'apple', 'service': 'Apple signing', 'severity': 'now',
     'used_by': 'Installing the app on phones', 'free_limit': 'Free Apple ID: installs expire after 7 days, only on phones plugged into your Mac',
     'paid': 'Apple Developer Program $99 a year', 'one_user': 'Reinstall from Xcode every 7 days.',
     'scale': 'Friends cannot install without coming to your Mac; no TestFlight, App Store or Sign in with Apple.',
     'upgrade': 'Join the program before sharing; then TestFlight (up to 10,000 testers).', 'code': False},
]


def action_cost(action, *, free=False):
    """USD for one action at paid prices (free=False) — the marginal cost once free calls are spent."""
    spec = ACTIONS[action]
    google = sum(SKUS[sku]['price'] * calls for sku, calls in spec['google'].items())
    return round(google + spec['ai_paid_usd'], 3)


def monthly_calls(active_users, month=ACTIVE_MONTH):
    calls = {sku: 0 for sku in SKUS}
    for action, times in month.items():
        for sku, n in ACTIONS[action]['google'].items():
            calls[sku] += n * times * active_users
    return calls


def scenario(active_users, stage):
    """Monthly USD for `active_users` active users: Google after free calls, AI, fixed costs."""
    calls = monthly_calls(active_users)
    google = sum(max(0, n - SKUS[sku]['free']) * SKUS[sku]['price'] for sku, n in calls.items())
    ai = sum(ACTIONS[a]['ai_paid_usd'] * t for a, t in ACTIVE_MONTH.items()) * active_users
    fixed = sum(cost for _, cost, _ in FIXED[stage])
    total = google + ai + fixed
    return {'active_users': active_users, 'stage': stage, 'google_usd': round(google, 2), 'ai_usd': round(ai, 2),
            'fixed_usd': round(fixed, 2), 'total_usd': round(total, 2),
            'per_user_usd': round(total / active_users, 2) if active_users else None,
            'variable_per_user_usd': round((google + ai) / active_users, 2) if active_users else None}


def free_capacity():
    """How many active users the free Google calls carry, limited by the tightest SKU."""
    per_user = monthly_calls(1)
    limits = {sku: SKUS[sku]['free'] // n for sku, n in per_user.items() if n}
    tightest = min(limits, key=limits.get)
    return {'active_users': limits[tightest], 'tightest': SKUS[tightest]['label'], 'by_sku': limits}


def build(rows, controls, *, today):
    """The `capacity` block of /api/admin/summary."""
    month = today[:7]
    used = {sku: 0 for sku in SKUS}
    for day, metric, _client, count, _ in rows:
        if not str(day).startswith(month): continue
        for sku, spec in SKUS.items():
            if metric in spec['metrics']: used[sku] += count
    skus = [{'id': sku, 'label': s['label'], 'used': used[sku], 'free': s['free'], 'price_per_1000': round(s['price'] * 1000, 2),
             'share': round(used[sku] / s['free'], 3), 'overage_usd': round(max(0, used[sku] - s['free']) * s['price'], 2)}
            for sku, s in SKUS.items()]
    cap = controls.get('global_google_cap')
    free_total = sum(s['free'] for s in SKUS.values())
    exposure = None
    if cap is not None:
        # Low: the calls spread over every SKU at the average price. High: all of them on Text Search.
        avg_price = sum(s['price'] for s in SKUS.values()) / len(SKUS)
        text = SKUS['text_search_enterprise']
        exposure = {'cap_per_day': cap, 'calls_per_month': cap * 30, 'free_calls': free_total,
                    'low_usd': round(max(0, cap * 30 - free_total) * avg_price, 2),
                    'high_usd': round(max(0, cap * 30 - text['free']) * text['price'], 2)}
    plans, videos = controls.get('free_plans_per_month', 3), controls.get('free_videos_per_month', 20)
    maxed = {'plan': max(plans, 0), 'video': max(videos, 0), 'browse': 1}
    maxed_cost = sum(action_cost(a) * t for a, t in maxed.items())
    maxed_ts = monthly_calls(1, maxed)['text_search_enterprise']
    return {
        'checked': '2026-11', 'skus': skus, 'exposure': exposure,
        'actions': [{'id': a, 'label': s['label'], 'usd': action_cost(a)} for a, s in ACTIONS.items()],
        'active_month': ACTIVE_MONTH, 'free_capacity': free_capacity(),
        'free_credit_account': {'plans': plans, 'videos': videos, 'usd': round(maxed_cost, 2),
                                'accounts_in_free_tier': (SKUS['text_search_enterprise']['free'] // maxed_ts) if maxed_ts else None},
        'scenarios': [scenario(1, 'now'), scenario(100, 'launch'), scenario(1000, 'scale')],
        'fixed': {stage: [{'item': n, 'usd': round(c, 2), 'note': note} for n, c, note in items] for stage, items in FIXED.items()},
        'bottlenecks': BOTTLENECKS,
    }
