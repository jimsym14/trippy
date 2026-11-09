"""The cost and income model behind the in-app cost calculator (Settings → Admin → Cost calculator).

One source of truth: the server sends `snapshot()` with /api/admin/summary, and the app ships a
copy (ios/Trippy/Resources/cost-model.json) for when it's offline. tests/test_cost_model.py fails
when the copy is out of date; refresh it with `python3 -m trippy.cost_model --write`.

Prices are list prices checked in November 2026. Figures marked `verify` could not be confirmed on
the provider's own pricing page and are estimates. Usage per user is an assumption, not a measurement;
the `live` block next to it shows what this month's real counters say.

Architecture modelled (EEA-compliant, November 2026):
* Place cards: Apple MapKit data in our own layout (free); Apple's place card on request (free).
* Saved, pinned and TikTok places also load Google's Places UI Kit rating line (billed per load).
* Search: Apple search plus the user's own places (free).
* TikTok videos: Gemini reads the video; Google place IDs come from the free IDs-only search.
* Plans: one of the pipeline options below.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

VERSION = '2026-11-08'
EUR_TO_USD = 1.10

# Unit prices in USD. `free` is calls per month at no charge (None = no free calls; 'unlimited' = always free).
UNITS = {
    'google_ui_kit': {'label': 'Google Places UI Kit load', 'usd': 0.001, 'free': 10_000, 'verify': True,
                      'note': 'Place Details UI Kit (Essentials), billed per load. Pricing page not reachable; confirm in Cloud Console.'},
    'google_id_match': {'label': 'Google place ID match', 'usd': 0.0, 'free': 'unlimited', 'verify': False,
                        'note': 'Text Search Essentials (IDs only) has no charge.'},
    'google_text_search': {'label': 'Google Text Search (Enterprise)', 'usd': 0.035, 'free': 1_000, 'verify': False,
                           'note': 'Today\'s planner. Not allowed for planning under the EEA terms.'},
    'gemini_video': {'label': 'Gemini reading one video', 'usd': 0.005, 'free': None, 'verify': True,
                     'note': 'Paid tier, low media resolution. Free tier is $0 but Google may use the inputs.'},
    'plan_ai': {'label': 'AI work in one plan', 'usd': 0.01, 'free': None, 'verify': True,
                'note': 'Request reading and plan notes.'},
    'foursquare_premium': {'label': 'Foursquare Premium call (ratings, hours)', 'usd': 0.01875, 'free': None, 'verify': False,
                           'note': 'No free Premium calls. Data may not be stored on pay-as-you-go, only place IDs.'},
    'gemini_lite_call': {'label': 'Gemini Flash-Lite call (place ideas)', 'usd': 0.0006, 'free': None, 'verify': True,
                         'note': 'Measured in the 8 Nov plan comparison: 5 calls a plan, about $0.003 in all.'},
    'google_place_check': {'label': 'Google place check (ID + location)', 'usd': 0.005, 'free': 10_000, 'verify': True,
                           'note': 'IDs-only search (free) plus Place Details Essentials for the location.'},
    'apple_mapkit': {'label': 'Apple MapKit (phone) and Maps Server API', 'usd': 0.0, 'free': 'unlimited', 'verify': False,
                     'note': 'Free with the Developer Program; server API capped at 25,000 calls a day.'},
}

# How a plan is built, and what each option costs per plan.
PLAN_PIPELINES = {
    'open_data': {'label': 'Open data + TikTok score', 'units': {'plan_ai': 1},
                  'legal': 'Allowed', 'quality': 'Lower: no ratings for places outside the user\'s saves'},
    'foursquare': {'label': 'Foursquare ratings, live', 'units': {'plan_ai': 1, 'foursquare_premium': 6},
                   'legal': 'Allowed (credit Foursquare; nothing stored but IDs)', 'quality': 'Good in big cities, thinner in Greece'},
    'gemini_blend': {'label': 'Gemini blend (ideas checked by Google)', 'units': {'plan_ai': 1, 'gemini_lite_call': 5, 'google_place_check': 33},
                     'legal': 'Grey: uses Google place checks for planning', 'quality': 'Most local; fewer landmarks; needs good place checks'},
    'google_today': {'label': 'Google ratings (today\'s planner)', 'units': {'plan_ai': 1, 'google_text_search': 10},
                     'legal': 'Not allowed under the EEA terms', 'quality': 'Best data'},
}

# What one user does in a month, by kind of user.
USAGE_PRESETS = {
    'light': {'label': 'Light', 'videos': 1, 'plans': 0.1, 'library_cards': 8, 'other_cards': 10, 'searches': 4},
    'average': {'label': 'Average', 'videos': 4, 'plans': 0.2, 'library_cards': 25, 'other_cards': 20, 'searches': 10},
    'heavy': {'label': 'Heavy', 'videos': 20, 'plans': 1.0, 'library_cards': 120, 'other_cards': 60, 'searches': 40},
}

# Products. Prices in EUR including 24% Greek VAT; Apple keeps 15% (Small Business Program).
VAT = 0.24
APPLE_CUT = 0.15
PRODUCTS = {
    'plus_month': {'label': 'Plus monthly', 'eur': 2.99, 'per': 'month'},
    'plus_year': {'label': 'Plus yearly', 'eur': 19.99, 'per': 'year'},
    'trip_pass': {'label': 'Trip Pass', 'eur': 3.99, 'per': 'purchase'},
    'pack': {'label': 'Pack', 'eur': 0.99, 'per': 'purchase'},
}

# Who pays, as shares of all monthly active users, plus other income per user per year.
MONEY_PRESETS = {
    'low': {'label': 'Low', 'plus_month': 0.005, 'plus_year': 0.005, 'trip_pass_per_year': 0.01, 'packs_per_year': 0.01,
            'tips_usd_per_year': 0.01, 'affiliate_usd_per_year': 0.10},
    'middle': {'label': 'Middle', 'plus_month': 0.01, 'plus_year': 0.015, 'trip_pass_per_year': 0.03, 'packs_per_year': 0.03,
               'tips_usd_per_year': 0.03, 'affiliate_usd_per_year': 0.40},
    'high': {'label': 'High', 'plus_month': 0.02, 'plus_year': 0.03, 'trip_pass_per_year': 0.06, 'packs_per_year': 0.06,
             'tips_usd_per_year': 0.06, 'affiliate_usd_per_year': 0.90},
}

# Fixed monthly costs (USD), picked by number of monthly active users.
FIXED_STAGES = [
    {'id': 'launch', 'label': 'Launch', 'up_to_users': 2_000, 'items': [
        ('Apple Developer Program', 99 / 12), ('Claude Pro', 200 / 12), ('Render Starter (web)', 7),
        ('Supabase Free', 0), ('Email (SMTP free tier)', 0), ('Domain', 1)]},
    {'id': 'growth', 'label': 'Growth', 'up_to_users': 20_000, 'items': [
        ('Apple Developer Program', 99 / 12), ('Claude Max 5x', 100), ('Render Standard web', 25), ('Render Standard worker', 25),
        ('Supabase Pro', 25), ('Email (SMTP)', 20), ('Domain', 1)]},
    {'id': 'scale', 'label': 'Scale', 'up_to_users': None, 'items': [
        ('Apple Developer Program', 99 / 12), ('Claude Max 5x', 100), ('Render Pro workspace', 19),
        ('Render 2 × Standard web', 50), ('Render 3 × Standard worker', 75), ('Render extra bandwidth', 50),
        ('Supabase Pro + compute', 60), ('Email (SMTP)', 35), ('Monitoring', 30), ('Domain', 1)]},
]

# Ready-made scenarios for the calculator.
SCENARIOS = [
    {'id': 'launch', 'label': '1,000 users', 'users': 1_000, 'usage': 'average', 'money': 'middle', 'pipeline': 'foursquare', 'reuse': 0.3},
    {'id': 'growth', 'label': '10,000 users', 'users': 10_000, 'usage': 'average', 'money': 'middle', 'pipeline': 'foursquare', 'reuse': 0.5},
    {'id': 'scale', 'label': '100,000 users', 'users': 100_000, 'usage': 'average', 'money': 'middle', 'pipeline': 'foursquare', 'reuse': 0.6},
    {'id': 'worst', 'label': '10,000, low income', 'users': 10_000, 'usage': 'heavy', 'money': 'low', 'pipeline': 'foursquare', 'reuse': 0.3},
]

# Counters from the usage store that the calculator shows as "this month, measured".
LIVE_METRICS = {'google:ui_kit': 'UI Kit loads', 'google:id_match': 'Place ID matches', 'social:extract': 'Videos read',
                'plan:started': 'Plans started', 'google:text_search': 'Planner Google searches'}


def net_usd(eur):
    """What we keep from a price in EUR: VAT out, then Apple's cut, in USD."""
    return eur / (1 + VAT) * (1 - APPLE_CUT) * EUR_TO_USD


def fixed_stage(users):
    for stage in FIXED_STAGES:
        if stage['up_to_users'] is None or users <= stage['up_to_users']:
            return stage
    return FIXED_STAGES[-1]


def _paid(unit, calls):
    spec = UNITS[unit]
    free = spec['free']
    if free == 'unlimited': return 0.0
    return max(0.0, calls - (free or 0)) * spec['usd']


def compute(users, usage='average', money='middle', pipeline='foursquare', reuse=0.0):
    """Monthly USD for `users` monthly active users. `reuse` is the share of videos already read for
    someone else (their result is reused, so Gemini isn't called again)."""
    u = USAGE_PRESETS[usage] if isinstance(usage, str) else usage
    m = MONEY_PRESETS[money] if isinstance(money, str) else money
    calls = {unit: 0.0 for unit in UNITS}
    calls['google_ui_kit'] = users * u['library_cards']
    calls['google_id_match'] = users * u['videos'] * 5
    calls['gemini_video'] = users * u['videos'] * (1 - reuse)
    for unit, n in PLAN_PIPELINES[pipeline]['units'].items():
        calls[unit] += users * u['plans'] * n
    calls['apple_mapkit'] = users * (u['other_cards'] + u['library_cards'] + u['searches'])
    costs = {unit: round(_paid(unit, n), 2) for unit, n in calls.items()}
    variable = sum(costs.values())
    stage = fixed_stage(users)
    fixed = sum(c for _, c in stage['items'])
    income = {
        'plus_month': users * m['plus_month'] * net_usd(PRODUCTS['plus_month']['eur']),
        'plus_year': users * m['plus_year'] * net_usd(PRODUCTS['plus_year']['eur']) / 12,
        'trip_pass': users * m['trip_pass_per_year'] * net_usd(PRODUCTS['trip_pass']['eur']) / 12,
        'pack': users * m['packs_per_year'] * net_usd(PRODUCTS['pack']['eur']) / 12,
        'tips': users * m['tips_usd_per_year'] * (1 - APPLE_CUT) / 12,
        'affiliate': users * m['affiliate_usd_per_year'] / 12,
    }
    income = {k: round(v, 2) for k, v in income.items()}
    total_income = sum(income.values())
    total_cost = variable + fixed
    return {'users': users, 'calls': {k: round(v) for k, v in calls.items()}, 'costs': costs,
            'variable_usd': round(variable, 2), 'fixed_stage': stage['id'], 'fixed_usd': round(fixed, 2),
            'income': income, 'income_usd': round(total_income, 2), 'cost_usd': round(total_cost, 2),
            'net_usd': round(total_income - total_cost, 2),
            'cost_per_user_year_usd': round(total_cost * 12 / users, 2) if users else None,
            'payers': round(users * (m['plus_month'] + m['plus_year']))}


def snapshot(rows=(), *, today=None):
    """Everything the calculator needs, plus this month's measured counters when `rows` are given."""
    live = None
    if today:
        month = today[:7]
        live = {metric: 0 for metric in LIVE_METRICS}
        for day, metric, _client, count, _bytes in rows:
            if str(day).startswith(month) and metric in live: live[metric] += count
        live = [{'metric': k, 'label': LIVE_METRICS[k], 'month': v} for k, v in live.items()]
    return {
        'version': VERSION, 'eur_to_usd': EUR_TO_USD, 'vat': VAT, 'apple_cut': APPLE_CUT,
        'units': UNITS, 'pipelines': PLAN_PIPELINES, 'usage': USAGE_PRESETS, 'money': MONEY_PRESETS,
        'products': {k: dict(v, net_usd=round(net_usd(v['eur']), 4)) for k, v in PRODUCTS.items()},
        'fixed': [dict(s, items=[{'item': n, 'usd': round(c, 2)} for n, c in s['items']]) for s in FIXED_STAGES],
        'scenarios': [dict(s, result=compute(s['users'], s['usage'], s['money'], s['pipeline'], s['reuse'])) for s in SCENARIOS],
        'live': live,
    }


BUNDLED = Path(__file__).resolve().parents[1] / 'ios' / 'Trippy' / 'Resources' / 'cost-model.json'


def bundled_text():
    return json.dumps(snapshot(), indent=1, sort_keys=True, ensure_ascii=False) + '\n'


if __name__ == '__main__':
    if '--write' in sys.argv:
        BUNDLED.write_text(bundled_text())
        print('wrote', BUNDLED)
    else:
        for s in SCENARIOS:
            r = compute(s['users'], s['usage'], s['money'], s['pipeline'], s['reuse'])
            print(f"{s['label']:>20}: cost ${r['cost_usd']:>9,.2f}  income ${r['income_usd']:>9,.2f}  net ${r['net_usd']:>9,.2f}")
