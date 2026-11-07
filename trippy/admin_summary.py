"""What the admin dashboard shows: APIs, limits, settings, installs. Pure, no network.

Secrets are never returned: the settings list says only whether each key is set.
"""
from __future__ import annotations

import os
import platform
import resource
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone

# Group, label, monthly free cap (None = no fixed cap), note. Google's free caps are
# per SKU per month on the billing account; verify current numbers in Cloud Console.
METRICS = {
    'google:text_search': ('google', 'Places Text Search', 1000, 'Enterprise SKU (asks for website, rating, hours)'),
    'google:app_search': ('google', 'Places search from the app', 1000, 'Enterprise SKU (rating fields)'),
    'google:details': ('google', 'Place Details (card)', 1000, 'Enterprise + Atmosphere SKU (reviews, photos)'),
    'google:hours': ('google', 'Place Details (opening hours)', 1000, 'Enterprise SKU'),
    'google:photo': ('google', 'Place Photos', 1000, 'Photo SKU'),
    'google:social_search': ('google', 'Video place matching', 1000, 'Enterprise SKU (rating fields)'),
    'ai:gemini': ('ai', 'Gemini (videos and plan notes)', None, 'Free tier: per-model daily limits, see model status'),
    'ai:azure': ('ai', 'Azure OpenAI', None, 'Paid, capped by TRIPPY_AI_BUDGET_AMOUNT'),
    'free:wikidata': ('free', 'Wikidata (famous places)', None, 'Free; be polite (one query per city, cached 30 days)'),
    'free:wikivoyage': ('free', 'Wikivoyage (city guide)', None, 'Free; cached 30 days'),
    'free:nominatim': ('free', 'Nominatim (area names, geocoding)', None, 'Free; max 1 request a second'),
    'free:overpass': ('free', 'Overpass (OpenStreetMap)', None, 'Free; slow under load'),
}
RATE_LIMITS = [('Places search and details', '30 / minute'), ('Place photos', '120 / minute'), ('Video matching', '60 / minute')]
SETTINGS = [
    ('GOOGLE_PLACES_API_KEY', 'Google Places key', True), ('GEMINI_API_KEY', 'Gemini key', True),
    ('TRIPPY_BRIDGE_TOKEN', 'App access token', True), ('TRIPPY_ADMIN_TOKEN', 'Dashboard token', False),
    ('TRIPPY_STATS_DATABASE_URL', 'Stats database (keeps these numbers across restarts)', False),
    ('AZURE_OPENAI_API_KEY', 'Azure OpenAI key', False), ('AZURE_OPENAI_ENDPOINT', 'Azure OpenAI endpoint', False),
    ('YOUTUBE_API_KEY', 'YouTube key', False),
    ('SUPABASE_URL', 'Accounts: Supabase project', False), ('SUPABASE_PUBLISHABLE_KEY', 'Accounts: Supabase publishable key', False),
    ('SUPABASE_SECRET_KEY', 'Accounts: delete-account key', False), ('TRIPPY_ADMIN_EMAILS', 'Admin accounts', False),
]
PUBLIC_VALUES = ['TRIPPY_ALLOW_PAID_RESEARCH', 'TRIPPY_AI_BUDGET_AMOUNT', 'TRIPPY_AI_BUDGET_CURRENCY']


def _group(metric):
    if metric in METRICS: return METRICS[metric][0]
    return metric.split(':', 1)[0]


def build(rows, clients, *, values, issues=(), models=None, mode='memory', last_error=None, started=None, days=30, now=None):
    now = now or datetime.now(timezone.utc)
    today = now.date()
    day_list = [(today - timedelta(days=i)).isoformat() for i in range(days - 1, -1, -1)]
    month_start = today.replace(day=1).isoformat()
    week_start = (today - timedelta(days=6)).isoformat()

    # --- APIs ------------------------------------------------------------------
    per_metric = defaultdict(lambda: {'today': 0, 'week': 0, 'month': 0, 'days30': 0})
    daily = {d: {'google': 0, 'ai': 0, 'free': 0} for d in day_list}
    requests = defaultdict(lambda: {'count': 0, 'bytes': 0})
    per_client = defaultdict(lambda: {'requests': 0, 'bytes': 0, 'google': 0, 'ai': 0, 'free': 0, 'plans': 0,
                                      'plans_ready': 0, 'videos': 0, 'days': set()})
    for day, metric, client, count, nbytes in rows:
        group = _group(metric)
        if group in {'google', 'ai', 'free'}:
            m = per_metric[metric]
            m['days30'] += count
            if day == today.isoformat(): m['today'] += count
            if day >= week_start: m['week'] += count
            if day >= month_start: m['month'] += count
            if day in daily: daily[day][group] += count
        c = per_client[client]
        if group == 'api':
            requests[metric[4:]]['count'] += count; requests[metric[4:]]['bytes'] += nbytes
            c['requests'] += count; c['bytes'] += nbytes; c['days'].add(day)
        elif group in {'google', 'ai', 'free'}: c[group] += count
        elif metric == 'plan:started': c['plans'] += count
        elif metric == 'plan:ready': c['plans_ready'] += count
        elif metric == 'social:extract': c['videos'] += count
    apis = []
    for metric, (group, label, cap, note) in METRICS.items():
        m = per_metric.get(metric, {'today': 0, 'week': 0, 'month': 0, 'days30': 0})
        apis.append({'metric': metric, 'group': group, 'label': label, **m, 'monthly_free': cap, 'note': note,
                     'share_of_free': round(m['month'] / cap, 3) if cap else None})

    # --- Installs ----------------------------------------------------------------
    installs = []
    for client in set(per_client) | set(clients):
        if client == 'unknown' and client not in per_client: continue
        c = per_client.get(client) or {'requests': 0, 'bytes': 0, 'google': 0, 'ai': 0, 'free': 0, 'plans': 0, 'plans_ready': 0, 'videos': 0, 'days': set()}
        info = clients.get(client, {})
        report = info.get('report') or {}
        active = len(c['days'])
        installs.append({'client': client, 'short': client[:8], 'first_seen': info.get('first_seen'), 'last_seen': info.get('last_seen'),
                         'requests': c['requests'], 'mb_transferred': round(c['bytes'] / 1e6, 2), 'google': c['google'], 'ai': c['ai'],
                         'free': c['free'], 'plans': c['plans'], 'plans_ready': c['plans_ready'], 'videos': c['videos'],
                         'active_days': active, 'calls_per_active_day': round(c['requests'] / active, 1) if active else 0,
                         'trips': report.get('trips'), 'planned_trips': report.get('planned_trips'),
                         'saved_places': report.get('saved_places'), 'storage_mb': report.get('storage_mb'),
                         'app_version': report.get('app_version'), 'device': report.get('device'), 'ios': report.get('ios')})
    installs.sort(key=lambda i: -(i['last_seen'] or 0))
    known = [i for i in installs if i['client'] != 'unknown']
    def average(key):
        values = [i[key] for i in known if isinstance(i[key], (int, float))]
        return round(sum(values) / len(values), 1) if values else None
    week_ago = time.time() - 7 * 86400
    totals = {'installs': len(known), 'active_7d': sum(1 for i in known if (i['last_seen'] or 0) >= week_ago),
              'requests_30d': sum(i['requests'] for i in installs),
              'plans_30d': sum(i['plans'] for i in installs), 'plans_ready_30d': sum(i['plans_ready'] for i in installs),
              'avg_calls_per_active_day': average('calls_per_active_day'), 'avg_trips': average('trips'),
              'avg_saved_places': average('saved_places'), 'avg_storage_mb': average('storage_mb'),
              'avg_plans': average('plans'), 'avg_google_calls': average('google')}

    # --- Settings and health -----------------------------------------------------
    settings = [{'key': key, 'label': label, 'required': required, 'set': bool((values.get(key) or '').strip())}
                for key, label, required in SETTINGS]
    public = {key: values.get(key) for key in PUBLIC_VALUES}
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    rss_mb = rss / (1024 * 1024) if sys.platform == 'darwin' else rss / 1024
    health = {'build': os.environ.get('RENDER_GIT_COMMIT', 'local')[:7], 'uptime_seconds': int(time.time() - (started or time.time())),
              'memory_mb': round(rss_mb, 1), 'python': platform.python_version(), 'storage': mode,
              'storage_note': {'postgres': 'Kept in the database.',
                               'file': 'Kept on the server disk: a Render restart or deploy clears it. Add TRIPPY_STATS_DATABASE_URL to keep it.',
                               'memory': 'In memory only.'}[mode],
              'last_error': last_error, 'issues': list(issues), 'host': 'Render (free plan: sleeps after 15 min idle, 512 MB)'}
    return {'generated_at': now.isoformat(), 'health': health, 'apis': apis, 'rate_limits': RATE_LIMITS,
            'models': models or [], 'daily': [{'day': d, **daily[d]} for d in day_list],
            'endpoints': sorted(({'path': p, **v} for p, v in requests.items()), key=lambda r: -r['count']),
            'installs': installs, 'totals': totals, 'settings': settings, 'public_settings': public}
