"""Library → missing places → optional AI/checks → deterministic map-ready draft."""
from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path

from research_pipeline import trip_dates, has_coordinates
from .planning_contract import normalized_brief, categories, validate_batch
from .place_graph import library_graph, graph_batch, attach_graph
from .plan_engine import merge_batches, compose_plan
from .pipeline import StageStore, grounded_batch
from .diagnostics import failure_details
from .search_intent import (
    fallback_intent, keyword_intent, merge_intent_categories, intent_enriched_task,
)

VERSION = 'personal-places-v1'


def missing_tasks(brief, graph, intent=None):
    """Return discovery tasks, expanded by any inferred categories from intent.

    The brief's explicit interests are always included.  Intent may add
    extra inferred categories, but it cannot remove explicit ones.
    If intent is None or fallback, only brief categories are used.
    """
    from .search_intent import SearchIntent
    _intent = intent if isinstance(intent, SearchIntent) else None
    retrieval_cats = (
        merge_intent_categories(categories(brief), _intent)
        if _intent else categories(brief)
    )
    days = max(1, len(trip_dates(brief)))
    tasks = []
    for category in retrieval_cats:
        if category == 'event': continue
        target = min(12, days * (2 if category in {'attraction','food'} else 1))
        count = sum(p['selected'] and p.get('category') == category for p in graph['places'])
        if count < target:
            base_task = {'id':'places-'+category, 'category':category, 'target':target-count}
            # Attach AI-derived retrieval signals when extraction succeeded.
            task = (
                intent_enriched_task(base_task, _intent)
                if (_intent and _intent.extraction_path in {'ai_derived', 'keyword_fallback'})
                else base_task
            )
            tasks.append(task)
    # One lookup per category, never a per-city transcript campaign.
    return tasks[:10]


def run(brief, *, directory, root, place_provider=None, intelligence=None, route_provider=None,
        ai_adapter=None, judge_enabled=False, progress=None, community_nodes=(), notes_pool=None):
    """Run the personal_places planning pipeline.

    ai_adapter  – optional AIAdapter used to extract SearchIntent from the
                  user's natural-language request (custom_instructions).
                  When None or when extraction returns None, a fallback intent
                  derived from the validated brief is used instead.
                  The planning engine (compose_plan, merge_batches) is never
                  modified regardless of which adapter is configured.
    judge_enabled – candidate judging is an extra model call; it stays off
                  unless a caller explicitly opts in (Stage 2A is paused).
    """
    brief = normalized_brief(brief)
    progress = progress or (lambda stage, detail:None)
    store = StageStore(directory)
    graph = library_graph(brief, community_nodes)
    if place_provider is None:
        catalog_path = Path(root) / '.local/catalog.sqlite'
        if catalog_path.is_file():
            from .travel_provider import LocalCatalogTravelProvider
            place_provider = LocalCatalogTravelProvider(root)
    inputs = {'pipeline':VERSION, 'brief':brief, 'graph':graph,
              'provider':getattr(place_provider, 'name', None),
              'intelligence_enabled':intelligence is not None,
              'ai_adapter':getattr(ai_adapter, 'name', None),
              'research_on':datetime.now(timezone.utc).date().isoformat()}
    marker = store.directory/'run-input.json'
    if marker.exists() and json.loads(marker.read_text()) != inputs:
        raise ValueError('Resume requires identical library, brief and provider')
    store.write('run-input',inputs); store.write('place-graph',graph)

    # --- Stage 1: extract intent from natural-language request ----------------
    # Intent refines retrieval only.  It never overwrites validated brief fields,
    # locked stops, excluded_place_ids, budget limits, or any explicit constraint.
    # Explicit constraints always win over inferred signals.
    raw_request = (brief.get('custom_instructions') or '').strip()
    intent = None
    if ai_adapter is not None and raw_request:
        intent = ai_adapter.extract_intent(raw_request, brief)
    if intent is None:
        # No model, or extraction failed: a fixed keyword vocabulary still lets
        # "Gaudí, tapas" steer retrieval; otherwise use the brief alone.
        intent = keyword_intent(brief) or fallback_intent(brief)
    if intent.area_hint is None and raw_request:
        # Neighbourhood names come from the city's boundary data (any city that
        # has it), so "focus on Gràcia" works without a model.
        from dataclasses import replace
        from trippy.catalog.boundaries import AreaIndex
        index = AreaIndex.load(root, brief['destination'])
        named = index.mentioned_in(raw_request) if index else None
        if named:
            intent = replace(intent, area_hint=named,
                             extraction_path=('keyword_fallback' if intent.extraction_path == 'fallback'
                                              else intent.extraction_path))
    # Detailed interests picked in the app steer retrieval like typed themes.
    from .search_intent import tag_themes
    picked = tag_themes(brief.get('preference_tags'))
    if picked and not set(picked) <= set(intent.vibe_tags):
        from dataclasses import replace
        intent = replace(intent, vibe_tags=sorted(set(intent.vibe_tags) | set(picked)),
                         extraction_path=('keyword_fallback' if intent.extraction_path == 'fallback'
                                          else intent.extraction_path))
    # -------------------------------------------------------------------------

    tasks = missing_tasks(brief, graph, intent=intent); batches = [validate_batch(graph_batch(graph))]
    failures = []; completed = []
    progress('pipeline_started', {'planned_discovery_tasks':len(tasks)})
    def document(): return attach_graph(merge_batches(batches, brief), graph)
    for task in tasks:
        if place_provider is None: break
        progress('task_started', {'task':task['id'], 'stage':'place_retrieval'})
        try:
            batches.append(store.run(task['id'], {'task':task,'brief':brief},
                lambda:validate_batch(place_provider.discover(task, brief))))
            completed.append(task['id'])
            progress('task_completed', {'task':task['id'], 'stage':'place_retrieval', 'place_count':len(batches[-1]['places'])})
        except Exception as exc:
            failure = failure_details(exc, task=task['id'], stage='place_retrieval')
            failures.append(failure); progress('task_failed', failure); break
    # Famous places the provider missed, free from Wikidata (live providers only:
    # the local catalog already carries Wikidata fame).
    if getattr(place_provider, 'name', None) == 'google_places' and not failures:
        from . import famous
        points = sorted((p['coordinates']['latitude'], p['coordinates']['longitude']) for b in batches[1:] for p in b['places']
                        if p['coordinates'].get('latitude') is not None)
        wanted = set(categories(brief)) & {'attraction', 'museum', 'nature'}
        # Sightseeing includes the very famous museums and parks (the Vatican Museums
        # are a sight in Rome), even when "museums" wasn't picked as an interest.
        if 'attraction' in wanted: wanted |= {'museum', 'nature'}
        if points and wanted:
            middle = points[len(points) // 2]
            items = famous.famous_items(root, brief['destination'], middle[0], sorted(p[1] for p in points)[len(points) // 2],
                                        log=lambda event, detail: progress(event, detail))
            if items:
                extra = validate_batch(famous.enrich(batches, items, wanted))
                if extra['places']: batches.append(extra)
                progress('famous_added', {'places': len(extra['places']), 'known': len(items)})
    planning_brief = brief
    if intent and intent.area_hint:
        from .plan_engine import key
        area_tag = f'area:{key(intent.area_hint)}'
        if area_tag not in brief['preference_tags']:
            planning_brief = {
                **brief,
                'preference_tags': sorted(set(brief['preference_tags'] + [area_tag]))
            }

    doc = document()

    # --- Stage 2A: Optional Candidate Judging ---------------------------------
    # Evaluated ONLY when deterministic ranking identifies an ambiguity (tie)
    # among retrieved catalog candidates. Personal pins (priority 100) are never
    # overridden by judged scores. Bounded candidate set (<=8).
    from .candidate_judge import detect_ranking_ambiguity

    judge_status = 'skipped'
    judge_candidates_count = 0
    judge_ambiguity_detected = False

    if (judge_enabled and ai_adapter is not None and hasattr(ai_adapter, 'judge_candidates')
            and doc['places'] and not failures):
        ambiguous_candidates = detect_ranking_ambiguity(doc['places'], planning_brief)
        if ambiguous_candidates:
            judge_ambiguity_detected = True
            judge_candidates_count = len(ambiguous_candidates)
            progress('judging_candidates', {'candidate_count': len(ambiguous_candidates)})
            judge_result = ai_adapter.judge_candidates(
                ambiguous_candidates,
                planning_brief,
                criteria={'custom_instructions': planning_brief.get('custom_instructions') or ''},
            )
            if judge_result and judge_result.rankings:
                judge_status = 'succeeded'
                score_map = {r.place_id: r.score for r in judge_result.rankings}
                for p in doc['places']:
                    if p['id'] in score_map:
                        p['judge_score'] = score_map[p['id']]
            else:
                judge_status = getattr(ai_adapter, 'last_judge_status', 'failed')
    # -------------------------------------------------------------------------

    # AI receives real identities and notes, not a blank request to invent a city.
    # The same bounded provider boundary can be backed by a travel MCP adapter.
    if intelligence is not None and doc['places'] and not failures:
        short = compose_plan(doc, planning_brief, route_provider=route_provider)
        selected = {s['place_id'] for d in short['itinerary']['days'] for s in d['stops']}
        shortlist = sorted(doc['places'], key=lambda p:(p['id'] not in selected, -p.get('personal_priority',0), p['id']))[:12]
        for offset in range(0,len(shortlist),4):
            subset = shortlist[offset:offset+4]
            task = {'id':f'selected-checks-{offset//4+1}', 'kind':'selected_checks', 'categories':sorted({p['category'] for p in subset}),
                'target':len(subset), 'places':subset, 'dates':trip_dates(brief),
                'requirements':brief['dietary_needs']+brief['mobility_requirements']}
            context = {'known_sources':doc['sources'], 'library_nodes':graph['nodes'], 'candidates':[], 'practical_source_context':[]}
            try:
                batches.append(grounded_batch(intelligence, task, brief, context, store, progress)); completed.append(task['id'])
            except Exception as exc:
                failure=failure_details(exc,task=task['id'],stage='selected_checks')
                failures.append(failure); progress('task_failed',failure); break
        doc=document()
    progress('composing','personal_places')
    result=compose_plan(doc, planning_brief, route_provider=route_provider)
    pending=result['plan_validation']['pending']
    if tasks and place_provider is None: pending.append({'code':'place_provider_required','categories':[t['category'] for t in tasks]})
    unresolved=[p['id'] for p in graph['places'] if not p['selected']]
    if unresolved: pending.append({'code':'saved_place_resolution_required','place_ids':unresolved})
    note_ids=[n['id'] for n in graph['nodes'] if n['kind']=='note' and n.get('text')]
    if note_ids or brief.get('custom_instructions'):
        pending.append({'code':'personal_instructions_need_review','node_ids':note_ids})
    area_shortfalls = [
        w['message'] for w in result.get('warnings', [])
        if 'area_inventory_shortfall' in w.get('message', '')
    ]
    if area_shortfalls:
        pending.append({'code':'area_inventory_shortfall','details':area_shortfalls})
    stops=sum(len(d['stops']) for d in result['itinerary']['days'])
    # Area names: one free reverse-geocode per area (cached), else "around <its best place>".
    if result.get('areas'):
        from .area_names import name_areas
        name_areas(root, result['areas'], log=lambda event, detail: progress(event, detail))
    # One bounded Gemini call writes day titles and per-stop reasons; the
    # schedule above is final and never changes here.
    notes_report={'status':'off'}
    if notes_pool is not None and stops:
        from . import plan_notes
        progress('guide_started', {'destination':brief['destination']})
        listings=plan_notes.guide_listings(root, brief['destination'])
        scheduled={s['place_id'] for d in result['itinerary']['days'] for s in d['stops']}
        guide=plan_notes.match_guide([p for p in result['places'] if p['id'] in scheduled], listings)
        progress('guide_completed', {'listings':len(listings),'matched':len(guide)})
        progress('notes_started', {'stops':stops})
        notes_report=plan_notes.annotate(notes_pool, result, planning_brief, guide, cache_dir=Path(root)/'.local/plan-notes')
        progress('notes_completed', {k:v for k,v in notes_report.items() if k!='retry_at'})
    # Weekly hours travel as a tag through validation; the plan carries them as a field.
    from .travel_provider import opening_hours_from_tags
    for place in result['places']:
        hours=opening_hours_from_tags(place)
        if hours: place['opening_hours']=hours
    if pending or failures: result['plan_validation']['status']='needs_checks'; result['delivery_status']='partial'
    if not result['places']: result['delivery_status']='failed'
    result['pipeline_report']={'version':VERSION,'scheduling_owned_by':'deterministic_engine','scheduled_stops':stops,
        'tasks':len(tasks), 'completed_task_ids':completed, 'failed_stages':failures,
        'library_nodes':len(graph['nodes']), 'library_places':len(graph['places']),
        'community_nodes':sum(n['kind']=='community' for n in graph['nodes']),
        'source_occurrences_available':len(graph['nodes']), 'places_researched':len(result['places']),
        'completed_research_phases':([2] if not failures else [])+([3] if intelligence and not failures else [])+([4] if stops else []),
        'phase_states':{'2':'failed' if failures else 'completed','3':'completed' if intelligence and not failures else 'skipped','4':'completed' if stops else 'empty'},
        'place_provider':getattr(place_provider,'name',None), 'transcript_campaign_required':False,
        'intent_extraction_path':intent.extraction_path,
        'intent_extraction_model':intent.extraction_model,
        'intent_inferred_categories':intent.inferred_categories,
        'area_shortfalls':area_shortfalls,
        'notes':notes_report,
        'judge_invoked':judge_ambiguity_detected and judge_status != 'skipped',
        'judge_status':judge_status,
        'judge_ambiguity_detected':judge_ambiguity_detected,
        'judge_candidates_count':judge_candidates_count,
        'model_usage':ai_adapter.ledger.get_metrics() if getattr(ai_adapter, 'ledger', None) else None}
    store.write('trippy-research',result)
    progress('completed' if result['delivery_status']=='ready' else 'partial','delivery')
    return result
