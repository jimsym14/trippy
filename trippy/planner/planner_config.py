"""How plans are built, chosen by an admin from fixed lists, and what a trip costs with each choice.

The admin page (web and app) shows a dropdown per choice and the estimated cost of a trip as a
breakdown; saving stores the choice in admin controls (`planner`) and every plan after that uses it.
Only values in OPTIONS are accepted, so a dropdown can't switch on anything unplanned.

Token counts come from real calls on 9 Nov 2026 (one blend call: ~450 tokens in, ~1,200 out;
Flash models also spend ~1,000 thinking tokens, an estimate). Prices: Gemini pricing page and
our Azure contract values in .env, checked 9 Nov 2026.
"""
from copy import deepcopy

# Models that can write place ideas, with what they can and can't do.
MODELS = {
    'gemini-3.6-flash': {'label': 'Gemini 3.6 Flash', 'in': 0.75, 'out': 3.75, 'think': 1000, 'free_tier': True,
                         'maps': 'Paid tier only ($14 per 1,000 after 5,000 free a month)', 'web': 'Paid tier only',
                         'reviews': 'From training only; no live reviews without grounding',
                         'speed': '≈ 16 s per category', 'notes': 'Best food picks in the 9 Nov tests. Price doubles 1 Jan 2027.'},
    'gemini-3.8-flash': {'label': 'Gemini 3.8 Flash', 'in': 0.75, 'out': 3.75, 'think': 3000, 'free_tier': True,
                         'maps': 'Paid tier only ($14 per 1,000 after 5,000 free a month)', 'web': 'Paid tier only',
                         'reviews': 'From training only; no live reviews without grounding',
                         'speed': 'Slow: up to 5 min per call in the 8 Nov test', 'notes': 'Strongest reasoning; too slow for plans today.'},
    'gemini-3.5-flash-lite': {'label': 'Gemini 3.5 Flash-Lite', 'in': 0.30, 'out': 2.50, 'think': 0, 'free_tier': True,
                              'maps': 'Paid tier only ($14 per 1,000 after 5,000 free a month)', 'web': 'Paid tier only',
                              'reviews': 'From training only', 'speed': '≈ 4–11 s per category',
                              'notes': 'Fast; sometimes puts a sight or café in the wrong list (the check drops it).'},
    'gemini-3.1-flash-lite': {'label': 'Gemini 3.1 Flash-Lite', 'in': 0.25, 'out': 1.50, 'think': 0, 'free_tier': True,
                              'maps': 'Paid tier only', 'web': 'Paid tier only', 'reviews': 'From training only',
                              'speed': '≈ 6 s per category', 'notes': 'Cheapest; older knowledge.'},
    'azure-luna': {'label': 'GPT-6 Luna (Azure)', 'in': 0.30, 'out': 1.00, 'think': 800, 'free_tier': False,
                   'maps': 'No map data', 'web': 'Web search through our Azure agent (blogs, review sites), billed per search',
                   'reviews': 'Can read review sites and blogs when web search is on', 'speed': 'Not measured for this task',
                   'notes': 'Paid only; counts against TRIPPY_AI_BUDGET_AMOUNT. Not yet tested for place ideas.'},
}

OPTIONS = {
    'place_finder': {'label': 'Places come from', 'choices': {
        'google_search': 'Google search per category',
        'gemini_blend': 'AI ideas, checked as real places',
        'open_data': 'Open data only (OpenStreetMap, Wikivoyage)'}},
    'idea_model': {'label': 'AI for place ideas', 'choices': {k: v['label'] for k, v in MODELS.items()}},
    'gemini_tier': {'label': 'Gemini billing', 'choices': {'free': 'Free tier (limits; Google may use inputs)', 'paid': 'Paid tier'}},
    'place_check': {'label': 'Check ideas against', 'choices': {
        'osm': 'OpenStreetMap only (free)',
        'osm_then_google': 'OpenStreetMap, then Google for misses',
        'google': 'Google for every idea'}},
    'request_reader': {'label': 'Reading the request', 'choices': {'azure-luna': 'GPT-6 Luna (Azure)', 'keywords': 'Keywords only (free)'}},
}
DEFAULT = {'place_finder': 'gemini_blend', 'idea_model': 'gemini-3.6-flash', 'gemini_tier': 'free',
           'place_check': 'osm_then_google', 'request_reader': 'azure-luna'}

GOOGLE_TEXT_SEARCH_ENTERPRISE = 0.035   # today's planner search (rating, hours, website)
GOOGLE_CHECK = 0.005                    # the blend's check: IDs-only search (free) + Details Essentials
IDEAS_PER_CATEGORY = 8                  # what the blend asks for, about target + 4
SECOND_ROUND_SHARE = 0.3                # categories that needed a second AI round in tests
OSM_MISS_SHARE = 0.35                   # ideas the free check couldn't confirm in tests
LUNA_WEB_SEARCH = 0.01                  # per web search through the Azure agent (estimate)


def clean(value):
    """A full, valid planner config from a partial one; raises ValueError on anything off the lists."""
    if not isinstance(value, dict): raise ValueError('planner')
    config = deepcopy(DEFAULT)
    for key, choice in value.items():
        if key not in OPTIONS or choice not in OPTIONS[key]['choices']: raise ValueError('planner.' + str(key)[:20])
        config[key] = choice
    return config


def _model_call_usd(model, tier, calls, tokens_in=450, tokens_out=1200):
    spec = MODELS[model]
    per_call = (tokens_in * spec['in'] + (tokens_out + spec['think']) * spec['out']) / 1e6
    paid = per_call * calls
    free = spec['free_tier'] and tier == 'free'
    return (0.0 if free else paid), paid


def estimate(config, *, days=2, categories=5):
    """Estimated cost of one trip, line by line. `paid_usd` is what a line costs once off the free tier."""
    config = clean(config)
    days, categories = max(1, int(days)), max(1, int(categories))
    lines = []

    def add(step, choice, calls, usd, paid=None, note=''):
        lines.append({'step': step, 'choice': choice, 'calls': round(calls, 1), 'usd': round(usd, 4),
                      'paid_usd': round(usd if paid is None else paid, 4), 'note': note})

    if config['request_reader'] == 'azure-luna':
        usd = (3000 * MODELS['azure-luna']['in'] + 1500 * MODELS['azure-luna']['out']) / 1e6
        add('Reading the request', 'GPT-6 Luna', 1, usd)
    else:
        add('Reading the request', 'Keywords', 0, 0)

    finder = config['place_finder']
    if finder == 'google_search':
        searches = min(10, categories)
        add('Finding places', 'Google search', searches, searches * GOOGLE_TEXT_SEARCH_ENTERPRISE,
            note='After the 1,000 free searches a month')
    elif finder == 'open_data':
        add('Finding places', 'OpenStreetMap + Wikivoyage', categories, 0, note='Free; fewer and plainer places')
    else:
        model = config['idea_model']
        calls = categories * (1 + SECOND_ROUND_SHARE)
        if model == 'azure-luna':
            usd = _model_call_usd(model, 'paid', calls)[0] + categories * LUNA_WEB_SEARCH
            add('Finding places', MODELS[model]['label'] + ' + web search', calls, usd, note='Web search cost is an estimate')
        else:
            usd, paid = _model_call_usd(model, config['gemini_tier'], calls)
            add('Finding places', MODELS[model]['label'] + (' (free tier)' if usd == 0 and paid else ''), calls, usd, paid,
                note='Free tier: limited requests a day' if usd == 0 and paid else '')
        ideas = categories * IDEAS_PER_CATEGORY * (1 + SECOND_ROUND_SHARE)
        check = config['place_check']
        if check == 'osm':
            add('Checking places are real', 'OpenStreetMap', ideas, 0, note='Free; ~35% of ideas not confirmed')
        elif check == 'osm_then_google':
            misses = ideas * OSM_MISS_SHARE
            add('Checking places are real', 'OpenStreetMap, Google for misses', ideas, misses * GOOGLE_CHECK,
                note=f'≈ {round(misses)} Google checks at $0.005, after 10,000 free a month')
        else:
            add('Checking places are real', 'Google', ideas, ideas * GOOGLE_CHECK, note='$0.005 each, after 10,000 free a month')

    add('Famous sights', 'Wikidata', 1, 0, note='Free')
    notes_calls = days + 1
    usd, paid = _model_call_usd('gemini-3.5-flash-lite', config['gemini_tier'], notes_calls, 1500, 1500)
    add('Plan notes and day themes', 'Gemini (notes pool)', notes_calls, usd, paid,
        note='Free tier' if usd == 0 and paid else '')
    total = sum(l['usd'] for l in lines)
    return {'config': config, 'days': days, 'categories': categories, 'lines': lines,
            'total_usd': round(total, 4), 'paid_total_usd': round(sum(l['paid_usd'] for l in lines), 4),
            'warnings': warnings(config)}


def warnings(config):
    """Plain-language risks of a choice, shown next to the dropdowns."""
    out = []
    if config['place_finder'] == 'google_search':
        out.append('Google ratings are used to choose places, which Google\'s EEA terms don\'t allow for trip planning.')
    if config['place_finder'] == 'gemini_blend' and config['idea_model'] == 'gemini-3.8-flash':
        out.append('Gemini 3.8 Flash took up to 5 minutes a call in tests; plans may time out.')
    if config['place_finder'] == 'gemini_blend' and config['gemini_tier'] == 'free' and config['idea_model'].startswith('gemini'):
        out.append('Free tier: a busy day can hit Gemini\'s limits, and Google may use the prompts to improve its models.')
    if config['place_finder'] == 'gemini_blend' and config['place_check'] == 'google':
        out.append('Every idea is checked on Google: most expensive check, and it uses the daily Google quota fast.')
    if config['idea_model'] == 'azure-luna' and config['place_finder'] == 'gemini_blend':
        out.append('GPT-6 Luna for place ideas hasn\'t been tested yet.')
    return out


def catalog():
    """Everything the admin page needs to draw the dropdowns and the model comparison."""
    return {'options': {k: {'label': v['label'], 'choices': [{'id': c, 'label': l} for c, l in v['choices'].items()]}
                        for k, v in OPTIONS.items()},
            'models': [dict(v, id=k) for k, v in MODELS.items()], 'default': DEFAULT}
