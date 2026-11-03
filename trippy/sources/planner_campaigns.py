"""Measured follow-up source review and per-use-case city research campaigns."""
import argparse
from collections import defaultdict
from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path

from trippy_config import read_environment
from .coverage import private_write
from .curation_cycle import load_pack
from .extraction import fingerprint
from .semantic_review import PROMPT, execute, keyed_schema, ledger_state, reservation


FOLLOWUP_PROMPT = PROMPT + '''
This is targeted adjudication, not another general extraction. The prior decision
is an untrusted proposal. Prefer supported original wording over unnecessary
paraphrase; preserve all useful qualifications. Read the full expanded source
context before deciding. A creator's reported statement can be retained as a
source assertion without certifying independent truth. Do not turn generic
mealtimes into venue opening schedules, tours into all-day visitor admission,
an elevator into full wheelchair access, viewer attention into a physical hazard,
or a warning into a joke without evidence of tone. A date, year or ASR spelling
must not be silently normalized from memory. Confirm the subject of every
detail; keep personal routes and generic advice distinct from place attributes.
supported judges the ORIGINAL claim, not the prior replacement. repair proposes
only essential source-supported changes. unresolved preserves ambiguity rather
than inventing a place, fact or a missing sentence. Explicit source context is
required even when the proposed correction sounds plausible. No live fact,
canonical identity, venue rating or publication approval is granted here.'''


def constrained_schema(entries):
    schema = keyed_schema(entries)
    templates = schema.pop('$defs')
    definitions = {}; slots = schema['properties']['decisions']['properties']
    for i, entry in enumerate(entries):
        choices = []
        evidence_name = f'Evidence_{i}'
        evidence = deepcopy(next(iter(templates.values()))['properties']['evidence_segment_ids'])
        evidence['items'] = {'type':'string', 'enum':entry['context_segment_ids']}
        definitions[evidence_name] = evidence
        for name, template in templates.items():
            specific = deepcopy(template)
            specific['properties']['evidence_segment_ids'] = {'$ref':f'#/$defs/{evidence_name}'}
            label = f'{name}_{i}'; definitions[label] = specific
            choices.append({'$ref':f'#/$defs/{label}'})
        slots[entry['key']] = {'anyOf':choices}
    schema['$defs'] = definitions
    def enum_count(value):
        if isinstance(value,dict): return len(value.get('enum',[])) + sum(enum_count(v) for k,v in value.items() if k!='enum')
        if isinstance(value,list): return sum(enum_count(v) for v in value)
        return 0
    if enum_count(schema) > 900 or len(json.dumps(schema)) > 90000:
        raise ValueError('Per-claim schema exceeds conservative resource guard; reduce claims per call')
    return schema


def prepare_followup(held, baseline, records, cues, *, per_call=8, radius=6):
    if not 1 <= per_call <= 12 or not 3 <= radius <= 12:
        raise ValueError('Invalid targeted review size/context radius')
    entries = {e['key']:e for c in baseline['chunks'] for e in c['payload']['entries']}
    record_map = {r['id']:r for r in records}; sources = defaultdict(list)
    for cue in cues.values(): sources[cue['segment_id'].rsplit(':',1)[0]].append(cue)
    for source in sources.values(): source.sort(key=lambda c:c['start_seconds'])
    positions = {c['segment_id']:i for source in sources.values() for i,c in enumerate(source)}
    output = []; seen = set()
    for task in held:
        key = task['key']
        if key in seen or key not in entries: raise ValueError('Unknown or duplicate follow-up claim')
        seen.add(key); entry = deepcopy(entries[key])
        if fingerprint(entry) != task['adjudication']['decision']['original_entry_sha256']:
            raise ValueError('Held claim context changed')
        if entry['claim'] != task['original_claim']: raise ValueError('Held claim changed')
        source = sources[entry['source_id']]; selected = set()
        evidence = [q['segment_id'] for q in entry['claim']['citations']]
        evidence += [q['segment_id'] for q in record_map[entry['occurrence_id']]['citations']]
        evidence += task['adjudication']['decision']['evidence_segment_ids']
        for sid in evidence:
            if sid not in positions or sid.rsplit(':',1)[0] != entry['source_id']:
                raise ValueError('Follow-up context cannot invent/cross-source cite evidence')
            index = positions[sid]; selected.update(range(max(0,index-radius), min(len(source),index+radius+1)))
        entry['context_segment_ids'] = [source[i]['segment_id'] for i in sorted(selected)]
        entry['upstream_entry_sha256'] = fingerprint(entries[key])
        entry['prior_disposition'] = task['adjudication']['decision']
        output.append(entry)
    chunks = []
    for offset in range(0,len(output),per_call):
        page = output[offset:offset+per_call]
        ids = dict.fromkeys(sid for e in page for sid in e['context_segment_ids'])
        chunk = {'system_prompt':FOLLOWUP_PROMPT, 'response_schema':constrained_schema(page),
            'payload':{'entries':page, 'original_context_cues':[cues[sid] for sid in ids],
                'scope':'Targeted original-source adjudication; no current facts or identity approval'}}
        chunk['id'] = fingerprint(chunk); chunks.append(chunk)
    return {'version':1, 'kind':'targeted_source_adjudication',
        'upstream_prepared_sha256':fingerprint(baseline), 'held_input_sha256':fingerprint(held),
        'claims_per_call':per_call, 'context_radius':radius, 'claim_occurrences':len(output),
        'record_count':len({e['occurrence_id'] for e in output}), 'chunks':chunks}


def research_campaigns(profile, scenarios, *, upstream_run_id):
    scenario_ids = [c['id'] for c in scenarios['cases']]
    common = ['Record source URL, retrieval/publication date, publisher and branch scope',
        'Separate independent selection evidence from operator facts and promotion',
        'Keep conflicting claims, unsupported fields and failed source access visible',
        'Do not invent stars, current prices, accessibility, dietary safety or live availability',
        'Review source-supported facets; keyword hits and source counts are not coverage',
        'Measure distinct relevant alternatives across area, cost, style and effort']
    family_map = {'mainstream_landmarks':1,'architecture':2,'historic_walks':3,'traditional_food':4,
        'modern_food':5,'specialty_coffee':6,'brunch_work_cafes':6,'rooftops_couples':7,
        'music_nightlife':8,'lgbtq_nightlife':9,'nearby_fast_food':10,'vegan_vegetarian':11,
        'allergy_coeliac':12,'halal_kosher':13,'toddlers_strollers':14,'mixed_age_tickets':15,
        'wheelchair_access':16,'low_walking':17,'rain_alternatives':18,'holiday_dates':19,
        'beach_conditions':20,'montserrat_gentle':21,'excursion_alternatives':22,'hiking':23,
        'museum_exhibitions':24,'football':25,'local_shopping':26,'stay_comparison':27,
        'late_arrival':28,'scoped_safety':29,'repeat_visitor_niche':30,'exact_budget':31,'user_import_and_locks':32}
    tasks = []
    for cell in profile['coverage_cells']:
        scope = cell['scope']; tasks.append({'id':cell['id'], 'scope':scope,
            'scenario_families':[family_map[cell['id']]] if cell['id'] in family_map else [],
            'research_queries':[q.replace('{city}','Barcelona') for q in cell['queries']],
            'source_controls':{'video_languages':profile['source_languages'],
                'primary_languages':profile['primary_source_languages'],
                'discovery':'Independent local guides and user-selected Greek/English creators',
                'fact_check':'Operator/official pages; relevant certification or transport authority'},
            'waves':{'initial':1, 'maximum':3,
                'repeat_only_for':'A measured unresolved coverage or evidence gap; change source/query when no useful evidence is added'},
            'acceptance':common + cell['required_gates'],
            'budget_pool':'shared_gap_research' if scope=='shared' else 'trip_contracts_and_checks',
            'execution_state':'requires_new_source_collection' if scope=='shared' else 'requires_private_or_trip_specific_inputs',
            'requires':['source_adjudication','canonical_identity'],
            'no_automatic_city_fact_generation':True})
    return {'version':1, 'upstream_run_id':upstream_run_id, 'campaigns':tasks,
        'scenario_ids':scenario_ids, 'scenario_count':len(scenario_ids), 'publication_ready':False,
        'shared_budget_cap':'15', 'budget_allocations':{
            'source_adjudication':'1.25','canonical_identity':'1.00','shared_gap_research':'3.00',
            'trip_contracts_and_checks':'1.00','scenario_evaluation':'1.00'},
        'budget_semantics':'Additional reservation ceilings pooled across campaigns, not a new cap for each topic',
        'completion':'No known critical violations in executed supported scenarios; not universal coverage of every possible request'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', required=True, type=Path)
    parser.add_argument('--execute-source', action='store_true')
    parser.add_argument('--max-calls', type=int)
    args = parser.parse_args(); config = json.loads(args.recipe.read_text())
    src = json.loads(Path(config['source_recipe']).read_text())
    audit = json.loads(Path(src['inputs']).read_text()); orig = json.loads(Path(src['original']).read_text())
    _, cues, _ = load_pack(audit['inputs'],orig)
    records = json.loads(Path(config['normalized_input']).read_text())['drafts']
    held = json.loads(Path(config['held_claims']).read_text())
    baseline = json.loads(Path(config['baseline_prepared']).read_text())
    prepared = prepare_followup(held,baseline,records,cues,
        per_call=config['claims_per_call'], radius=config['context_radius'])
    root = Path(config['output_root']); values = read_environment(Path('.env'))
    ceiling = sum((reservation(c,values,output=config['output_tokens']) for c in prepared['chunks']),Decimal(0))
    if ceiling > Decimal(config['source_task_cap']): raise ValueError('Follow-up exceeds task ceiling; revise batching before dispatch')
    currency, shared, used = ledger_state(config['ledger'],config['request_group'])
    print(json.dumps({'claims':len(held),'planned_calls':len(prepared['chunks']),
        'full_preparation_reservation':str(ceiling),'task_cap':config['source_task_cap'],
        'shared_reserved':str(shared),'shared_cap':values['TRIPPY_AI_BUDGET_AMOUNT'],
        'source_task_reserved':str(used),'currency':currency},indent=2),flush=True)
    manifest = root/'prepared.json'
    if manifest.exists():
        if json.loads(manifest.read_text()) != prepared: raise ValueError('Follow-up manifest changed; version the run')
    else: private_write(manifest,prepared)
    if config.get('coverage_profile') and config.get('scenarios'):
        campaigns = research_campaigns(json.loads(Path(config['coverage_profile']).read_text()),
            json.loads(Path(config['scenarios']).read_text()),upstream_run_id=Path(config['held_claims']).parent.name)
        index = root.parent/'campaigns-v1'/'campaigns.json'
        if index.exists():
            if json.loads(index.read_text()) != campaigns: raise ValueError('Campaign plan changed; version it')
        else: private_write(index,campaigns)
    if args.execute_source:
        summary = execute(prepared,values,config['ledger'],root,
            task_cap=Decimal(config['source_task_cap']), max_calls=args.max_calls,
            request_group=config['request_group'],output_tokens=config['output_tokens'])
        print(json.dumps({k:v for k,v in summary.items() if not isinstance(v,list)},indent=2))
        for f in summary['failures']: print(f['reason'],flush=True)
        if summary['failures']: raise SystemExit(1)


if __name__ == '__main__': main()
