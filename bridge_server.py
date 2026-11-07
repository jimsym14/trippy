"""Trip-scoped bridge for the resumable planning pipeline.

No SDK client initializes at import. Paid providers require explicit configured
budgets. Status/results require the unguessable run capability returned by POST.
"""
import json
import hmac
import logging
import os
from pathlib import Path
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, quote, urlsplit
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from uuid import uuid4, UUID

from trippy_config import read_environment
from trippy.sources.luna import BudgetError, ProviderConfigurationError
from trippy.planner.planning_contract import normalized_brief
from trippy.planner.pipeline import run as execute_plan, StageStore
from trippy.planner.live_provider import AzureResearchProvider, ResearchConfigurationError, configuration_issues
from trippy.planner.diagnostics import failure_details
from trippy.planner.personal_pipeline import run as execute_personal_plan
from trippy.planner.travel_provider import GoogleTravelProvider
from trippy.planner.ai_adapter import AzureIntentAdapter
import base64
from trippy.social.extract import ExtractionQueue
from trippy.social.gemini import GeminiPool


class ResearchState:
    def __init__(self):
        self.lock=threading.RLock()
        self.is_running=False
        self.started_at=0
        self.current_step='idle'
        self.step_message='Αναμονή για εκκίνηση'
        self.step_index=0
        self.total_steps=3
        self.latest_result=None
        self.error_message=None
        self.brief_context=None
        self.job_id=None
        self.jobs={}

state=ResearchState()

from trippy import usage
from trippy.usage import Usage, Controls, clean_client
_env_at_start=read_environment(Path(__file__).resolve().parent/'.env')
recorder=Usage(Path(__file__).resolve().parent/'.local/usage/usage.json', _env_at_start.get('TRIPPY_STATS_DATABASE_URL'))
usage.install(recorder)
controls=Controls(recorder)
admin_failures={}
admin_lock=threading.Lock()


def admin_allowed(handler):
    """The dashboard has its own token (never the app's), and guessing it is throttled per address."""
    expected=read_environment(root()/'.env').get('TRIPPY_ADMIN_TOKEN','').strip()
    address=(handler.headers.get('X-Forwarded-For') or handler.client_address[0]).split(',')[0].strip()
    now=time.time()
    with admin_lock:
        recent=[t for t in admin_failures.get(address,[]) if now-t<600]
        admin_failures[address]=recent
        if len(recent)>=8: return 'locked'
    supplied=handler.headers.get('Authorization','')
    supplied=supplied[7:] if supplied.startswith('Bearer ') else ''
    if len(expected)>=24 and hmac.compare_digest(expected,supplied): return 'ok'
    with admin_lock: admin_failures.setdefault(address,[]).append(now)
    return 'disabled' if len(expected)<24 else 'denied'
places_limit_lock=threading.Lock()
places_request_times=[]
photo_request_times=[]
social_request_times=[]


def places_key():
    return read_environment(root()/'.env').get('GOOGLE_PLACES_API_KEY','').strip()


def places_access_allowed(handler):
    expected=read_environment(root()/'.env').get('TRIPPY_BRIDGE_TOKEN','').strip()
    supplied=handler.headers.get('Authorization','')
    supplied=supplied[7:] if supplied.startswith('Bearer ') else ''
    return bool(expected) and hmac.compare_digest(expected,supplied)


def allow_places_request(kind='places'):
    """Keep this optional, live-only proxy from becoming an unbounded API relay.

    Photos have their own budget: one place card asks for up to eight at once,
    and sharing a 30/min bucket with typed search starved them into 429s.
    """
    now=time.time()
    times,limit={'photo':(photo_request_times,120),'social':(social_request_times,60)}.get(kind,(places_request_times,30))
    with places_limit_lock:
        times[:]=[stamp for stamp in times if now-stamp < 60]
        if len(times) >= limit:
            return False
        times.append(now)
        return True


_hours_cache={}


def google_sku(path, body, field_mask):
    """Which Google SKU a call is billed as, for the dashboard (approximate, by request shape)."""
    mask=field_mask or ''
    if '/media' in path: return 'google:photo'
    if path=='places:searchText':
        if 'places.websiteUri' in mask and 'regularOpeningHours' in mask: return 'google:text_search'
        if (body or {}).get('pageSize')==3: return 'google:social_search'
        return 'google:app_search'
    if mask=='id,regularOpeningHours,utcOffsetMinutes': return 'google:hours'
    return 'google:details'


def google_places_json(path, api_key, *, body=None, field_mask=None):
    usage.hit(google_sku(path, body, field_mask))
    data=json.dumps(body).encode() if body is not None else None
    headers={'X-Goog-Api-Key':api_key,'Accept':'application/json'}
    if data is not None: headers['Content-Type']='application/json'
    if field_mask: headers['X-Goog-FieldMask']=field_mask
    request=Request('https://places.googleapis.com/v1/'+path,data=data,headers=headers,
                    method='POST' if data is not None else 'GET')
    with urlopen(request,timeout=12) as response:
        payload=response.read(2_000_000)
    return json.loads(payload)


def social_place_search(query):
    """Google Places Text Search for one extracted venue (server-side pinning)."""
    api_key=places_key()
    if not api_key: return []
    if not allow_places_request('social'): raise RuntimeError('places_rate_limit')
    payload=google_places_json('places:searchText',api_key,body={'textQuery':query[:180],'pageSize':3,'languageCode':'en'},
        field_mask='places.id,places.displayName,places.formattedAddress,places.location,places.primaryTypeDisplayName,places.addressComponents,places.rating,places.userRatingCount')
    hits=[]
    for place in payload.get('places',[]):
        components=place.get('addressComponents',[])
        city=next((c.get('longText','') for c in components if 'locality' in c.get('types',[]) or 'postal_town' in c.get('types',[])),'')
        country=next((c.get('shortText','') for c in components if 'country' in c.get('types',[])),'')
        location=place.get('location') or {}
        hits.append({'placeID':place.get('id'),'name':(place.get('displayName') or {}).get('text',''),'address':place.get('formattedAddress',''),
            'latitude':location.get('latitude'),'longitude':location.get('longitude'),
            'primaryType':(place.get('primaryTypeDisplayName') or {}).get('text',''),'city':city,'countryCode':country,
            'rating':place.get('rating'),'reviewCount':place.get('userRatingCount')})
    return hits


def social_place_details(place_id):
    """Facts + recent reviews used to refine extracted cards (not stored beyond the job result)."""
    api_key=places_key()
    if not api_key: return {}
    if not allow_places_request('social'): raise RuntimeError('places_rate_limit')
    place=google_places_json('places/'+quote(place_id,safe=''),api_key,
        field_mask='id,formattedAddress,primaryTypeDisplayName,rating,userRatingCount,regularOpeningHours,editorialSummary,reviews')
    return {'address':place.get('formattedAddress',''),'primaryType':(place.get('primaryTypeDisplayName') or {}).get('text',''),
        'rating':place.get('rating'),'reviewCount':place.get('userRatingCount'),
        'openingHours':(place.get('regularOpeningHours') or {}).get('weekdayDescriptions',[]),
        'summary':(place.get('editorialSummary') or {}).get('text',''),
        'reviews':[{'rating':r.get('rating'),'text':(r.get('text') or {}).get('text','')} for r in place.get('reviews',[])[:5]]}


_social_queue=None
_social_lock=threading.Lock()

_gemini_pool=None
_gemini_lock=threading.Lock()


def gemini_pool():
    """One pool per process, shared by TikTok reading and plan notes, so a model
    parked for quota by one is skipped by the other. None without a key."""
    global _gemini_pool
    with _gemini_lock:
        if _gemini_pool is None:
            values=read_environment(root()/'.env')
            key=values.get('GEMINI_API_KEY','').strip()
            if not key: return None
            models=[m for m in values.get('GEMINI_MODELS','').split(',') if m.strip()]
            _gemini_pool=GeminiPool(key,models or None)
        return _gemini_pool


def social_queue():
    global _social_queue
    with _social_lock:
        if _social_queue is None:
            def pool():
                shared=gemini_pool()
                if shared is None: raise ValueError('GEMINI_API_KEY is not configured')
                return shared
            _social_queue=ExtractionQueue(pool,search=social_place_search,details=social_place_details,directory=root()/'.local/social-jobs')
        return _social_queue


_catalog_engine = None
_catalog_lock = threading.Lock()

def retain_google_references(records):
    """Persist IDs/source tags only. Never store Google photos, ratings or reviews.

    This catalog has no delete path and is independent of personal library items.
    DATABASE_URL is server-only; no database credential goes to the iOS client.
    """
    global _catalog_engine
    from sqlalchemy import create_engine, text
    from sqlalchemy.engine import make_url
    with _catalog_lock:
        if _catalog_engine is None:
            url = read_environment(root()/'.env').get('DATABASE_URL', '').strip()
            if not url:
                raise RuntimeError('place_catalog_not_configured')
            _catalog_engine = create_engine(make_url(url).set(drivername="postgresql+psycopg"), hide_parameters=True, pool_pre_ping=True, pool_size=2, max_overflow=2,
                connect_args={'connect_timeout': 4})
    with _catalog_engine.begin() as connection:
        connection.execute(text("SET LOCAL statement_timeout = '4000ms'"))
        for record in records:
            connection.execute(text("""
                INSERT INTO trippy_catalog.google_place_references(place_id, sources)
                VALUES (:id, ARRAY[CAST(:source AS text)])
                ON CONFLICT (place_id) DO UPDATE SET sources = ARRAY(
                    SELECT DISTINCT unnest(trippy_catalog.google_place_references.sources || excluded.sources))
            """), {'id': record['placeID'], 'source': record['source']})


def root(): return Path(__file__).resolve().parent

def job_directory(job_id):
    UUID(job_id)
    return root()/'.local/trip-pipeline/jobs'/job_id


def save_job(job_id):
    StageStore(job_directory(job_id)).write('status',state.jobs[job_id])


def progress(job_id, step, detail):
    labels={'searching_web':'Έρευνα για τις επιλογές σου', 'synthesizing_patch':'Οργάνωση πληροφοριών και πηγών',
            'composing':'Σύνθεση ημερών, μετακινήσεων και κόστους', 'partial':'Το πλάνο αποθηκεύτηκε με εκκρεμότητες',
            'completed':'Το πλάνο πέρασε τους ελέγχους'}
    with state.lock:
        job=state.jobs[job_id]
        diagnostics=job.setdefault('diagnostics',{'events':[]})
        if step in {'pipeline_started','task_started','task_completed','task_failed','phase_skipped',
                    'guide_started','guide_completed','notes_started','notes_completed'}:
            event={**detail,'event':step,'elapsed_seconds':round(time.time()-job.get('started_at',time.time()),1)}
            diagnostics['events']=(diagnostics.get('events',[])+[event])[-100:]
            diagnostics['elapsed_seconds']=event['elapsed_seconds']
            if step=='pipeline_started': diagnostics['planned_discovery_tasks']=detail['planned_discovery_tasks']
            if step=='task_started': diagnostics['active_task']=detail['task']; diagnostics['active_stage']=detail['stage']
            if step=='task_completed': diagnostics['completed_provider_stages']=diagnostics.get('completed_provider_stages',0)+1
            if step=='task_failed': diagnostics['last_failure']=detail
            logging.getLogger('trippy.research').info(json.dumps({'support_id':job.get('support_id'),**event}))
            save_job(job_id)
            return
        if step=='phase_completed':
            phase={'discovery':2,'checks':3,'composition':4}[detail]
            job['completed_research_phases']=sorted(set(job.get('completed_research_phases',[])+[phase]))
            save_job(job_id)
            return
        job['step']=step; job['message']=labels.get(step,detail)
        job['step_index']=1 if step=='searching_web' else 2 if step in {'synthesizing_patch','composing'} else 3
        job['current_task']=detail
        if state.job_id==job_id:
            state.current_step=step; state.step_message=job['message']; state.step_index=job['step_index']
        save_job(job_id)


def begin_job(brief):
    brief=normalized_brief(brief)
    with state.lock:
        # No timeout that lets a second thread overwrite a still-running job.
        if state.is_running: raise RuntimeError('research_already_running')
        job_id=str(uuid4())
        state.jobs[job_id]={'job_id':job_id,'is_running':True,'step':'starting','step_index':0,'total_steps':3,
            'support_id':uuid4().hex[:12],'started_at':time.time(),'diagnostics':{'events':[]},
            'message':'Ανάκτηση της διαθέσιμης έρευνας','request_context':brief,'result':None,'error':None}
        state.is_running=True; state.started_at=time.time(); state.job_id=job_id
        state.brief_context=brief; state.latest_result=None; state.error_message=None
        save_job(job_id)
        return job_id,brief


def run_pipeline(brief_data, job_id=None, *, provider=None, route_provider=None):
    if job_id is None: job_id,brief_data=begin_job(brief_data)
    try:
        values=read_environment(root()/'.env')
        personal = brief_data.get('planning_strategy') == 'personal_places'
        if provider is None and not personal:
            ledger=Path(values.get('TRIPPY_SHARED_BUDGET_LEDGER',str(root()/'.local/stage3/extraction-budget.sqlite')))
            if not ledger.is_absolute(): ledger=root()/ledger
            provider=AzureResearchProvider(values,ledger)
        report_progress=lambda step,detail:progress(job_id,step,detail) if step not in {'completed','partial'} else None
        if personal:
            place_provider=None
            if values.get('GOOGLE_PLACES_API_KEY') and values.get('TRIPPY_ALLOW_PAID_RESEARCH','').lower()=='true':
                def request_places(path, **kwargs):
                    if not allow_places_request(): raise RuntimeError('place_rate_limit')
                    return google_places_json(path,values['GOOGLE_PLACES_API_KEY'],**kwargs)
                place_provider=GoogleTravelProvider(request_places)
            # Existing AI configuration remains optional; the library can draft offline.
            if provider is None and not configuration_issues(values):
                ledger=Path(values.get('TRIPPY_SHARED_BUDGET_LEDGER',str(root()/'.local/stage3/extraction-budget.sqlite')))
                if not ledger.is_absolute(): ledger=root()/ledger
                provider=AzureResearchProvider(values,ledger)
            ai_adapter=AzureIntentAdapter(provider) if provider is not None else None
            # Free OpenStreetMap venues stand in when Google fails (a spent daily quota).
            from trippy.planner.osm_places import FallbackChain
            fallback=FallbackChain(root()) if place_provider is not None else None
            result=execute_personal_plan(brief_data,place_provider=place_provider,intelligence=provider,
                ai_adapter=ai_adapter,notes_pool=gemini_pool(),fallback_provider=fallback,
                directory=job_directory(job_id),root=root(),route_provider=route_provider,progress=report_progress)
        else:
            result=execute_plan(brief_data,provider=provider,directory=job_directory(job_id),root=root(),
                route_provider=route_provider,progress=report_progress)
        report=result.setdefault('pipeline_report',{})
        report.update(support_id=state.jobs[job_id]['support_id'],build_commit=os.environ.get('RENDER_GIT_COMMIT','local'))
        step='completed' if result['delivery_status']=='ready' else 'error' if result['delivery_status']=='failed' else 'partial'
        with state.lock:
            diagnostics=state.jobs[job_id]['diagnostics']
            diagnostics.update(place_count=len(result['places']),source_count=len(result['sources']),
                scheduled_stops=report.get('scheduled_stops',0),phase_states=report.get('phase_states',{}))
            result['pipeline_report']['diagnostics']=dict(diagnostics)
            state.jobs[job_id]['result']=result
            state.latest_result=result
            progress(job_id,step,'delivery')
            if step=='error':
                state.jobs[job_id].update(error_code=report.get('failure_code','research_failed'),
                    message='Δεν δημιουργήθηκε πλάνο. Η έρευνα δεν επέστρεψε κανένα αξιοποιήσιμο μέρος. Δες τα στοιχεία υποστήριξης για την αιτία.')
    except Exception as exc:
        # Store a safe type, not raw provider errors that can contain request data.
        with state.lock:
            job=state.jobs[job_id]
            progress(job_id,'task_failed',failure_details(exc,task=job.get('current_task','pipeline'),stage='pipeline'))
            code='research_configuration_required' if isinstance(exc,ResearchConfigurationError) else 'research_budget_unavailable' if isinstance(exc,BudgetError) else 'provider_configuration_required' if isinstance(exc,ProviderConfigurationError) else 'research_storage_unavailable' if isinstance(exc,OSError) else 'research_failed'
            messages={'research_configuration_required':'Η υπηρεσία χρειάζεται ρύθμιση των ορίων και του παρόχου πριν ξεκινήσει έρευνα.',
                'research_budget_unavailable':'Το διαθέσιμο όριο έρευνας δεν επέτρεψε την επόμενη ενέργεια. Χρειάζεται έλεγχος του ορίου και των κρατημένων χρεώσεων.',
                'provider_configuration_required':'Χρειάζεται έλεγχος της σύνδεσης της υπηρεσίας με τον πάροχο έρευνας.',
                'research_storage_unavailable':'Η υπηρεσία δεν μπόρεσε να αποθηκεύσει την έρευνα.',
                'research_failed':'Η έρευνα σταμάτησε σε στάδιο που χρειάζεται έλεγχο.'}
            state.jobs[job_id].update(step='error',error=type(exc).__name__,error_code=code,message=messages[code])
            state.current_step='error'; state.error_message=type(exc).__name__
            state.step_message=state.jobs[job_id]['message']
    finally:
        with state.lock:
            state.jobs[job_id]['is_running']=False
            if state.job_id==job_id: state.is_running=False
            save_job(job_id)
    return job_id


def read_job(job_id):
    UUID(job_id)
    with state.lock:
        if job_id in state.jobs: return dict(state.jobs[job_id])
    path=job_directory(job_id)/'status.json'
    if not path.is_file(): return None
    job=json.loads(path.read_text())
    if job['is_running']:
        # A restarted bridge cannot pretend its old thread is still working.
        job.update(is_running=False,step='interrupted',message='Η εκτέλεση διακόπηκε· τα ολοκληρωμένα στάδια διατηρήθηκαν.')
    return job


KNOWN_PATHS={'/api/status','/api/research','/api/social/extract','/api/social/status','/api/places/retain',
             '/api/places/search','/api/places/details','/api/places/photo','/api/places/hours','/api/usage/report',
             '/api/admin/summary','/api/admin/controls','/admin'}


class RequestHandler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.counted=False

    @property
    def client_id(self):
        return clean_client(self.headers.get('X-Trippy-Client'))

    def count(self,nbytes):
        if self.counted: return
        self.counted=True
        path=urlsplit(self.path).path
        if path.startswith('/api/admin') or path=='/admin': return   # the dashboard doesn't count itself
        usage.hit('api:'+(path if path in KNOWN_PATHS else 'other'),self.client_id,1,nbytes)

    def refuse(self,code):
        messages={'install_blocked':'This install has been blocked by the admin.',
                  'paid_research_paused':'Planning is paused by the admin for now.',
                  'daily_limit_reached':'Daily limit for maps lookups reached. It resets at midnight UTC.',
                  'service_daily_limit_reached':'The service reached today\'s maps limit. It resets at midnight UTC.'}
        self.send_json(403 if code=='install_blocked' else 429,{'error':code,'message':messages.get(code,code)})

    def send_html(self,status,html):
        body=html.encode()
        self.send_response(status)
        self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        # Only this page's own inline code; no third-party scripts can read the token.
        self.send_header('Content-Security-Policy',"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Referrer-Policy','no-referrer')
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass

    def read_json(self,limit):
        length=int(self.headers.get('Content-Length','0'))
        if not 0<length<=limit: raise ValueError('invalid_length')
        return json.loads(self.rfile.read(length))

    def admin(self,target,method):
        verdict=admin_allowed(self)
        if verdict!='ok':
            status={'locked':429,'disabled':503}.get(verdict,401)
            self.send_json(status,{'error':{'locked':'too_many_attempts','disabled':'admin_token_not_configured'}.get(verdict,'admin_token_required')})
            return
        if target.path=='/api/admin/controls' and method=='POST':
            try: self.send_json(200,{'controls':controls.update(self.read_json(200_000))})
            except (ValueError,TypeError,json.JSONDecodeError) as error: self.send_json(422,{'error':'invalid_controls','field':str(error)[:40]})
            except Exception: self.send_json(503,{'error':'controls_unavailable'})
            return
        if target.path=='/api/admin/summary':
            from trippy.admin_summary import build
            try:
                models=social_queue()._pool_factory().status()
            except Exception: models=[]
            values=read_environment(root()/'.env')
            try: issues=configuration_issues(values)
            except (ValueError,OSError): issues=['ENVIRONMENT_CONFIGURATION']
            try:
                summary=build(recorder.rows(30),recorder.client_reports(),values=values,issues=issues,models=models,
                              mode=recorder.mode,last_error=recorder.last_error,started=recorder.started)
            except Exception as error:
                self.send_json(503,{'error':'usage_store_unavailable','type':type(error).__name__}); return
            summary['controls']=controls.snapshot()
            summary['busy']={'plan_running':state.is_running}
            self.send_json(200,summary); return
        self.send_json(404,{'error':'not_found'})

    def send_json(self,status,payload):
        path = urlsplit(self.path).path
        if path.startswith('/api/places/'):
            logging.info('Places response route=%s status=%s code=%s', path, status,
                payload.get('errorCode') or payload.get('error') or 'ok')
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        self.end_headers()
        body=json.dumps(payload,ensure_ascii=False,allow_nan=False).encode()
        self.count(len(body))
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
    def send_image(self,status,content_type,payload):
        self.send_response(status)
        self.send_header('Content-Type',content_type)
        self.send_header('Cache-Control','no-store, max-age=0')
        self.send_header('X-Content-Type-Options','nosniff')
        self.end_headers()
        self.count(len(payload))
        try: self.wfile.write(payload)
        except (BrokenPipeError, ConnectionResetError): pass
    def google_places(self,target):
        if not places_access_allowed(self): self.send_json(401,{'error':'access_token_required'}); return True
        # Blocks and daily limits come before anything else, so a blocked install learns nothing more.
        refusal=controls.refusal(self.client_id,google=True)
        if refusal: self.refuse(refusal); return True
        usage.set_client(self.client_id)
        api_key=places_key()
        if not api_key:
            self.send_json(503,{'stage':'render','errorCode':'google_places_key_missing',
                'message':'GOOGLE_PLACES_API_KEY is missing from the Render environment.'}); return True
        if not allow_places_request('photo' if target.path=='/api/places/photo' else 'places'):
            self.send_json(429,{'error':'places_rate_limit'}); return True
        query=parse_qs(target.query)
        try:
            if target.path=='/api/places/status':
                # One Text Search IDs-only request verifies Render -> Google without
                # retrieving/storing place details or images.
                google_places_json('places:searchText',api_key,
                    body={'textQuery':'Eiffel Tower, Paris','pageSize':1,'languageCode':'en'},
                    field_mask='places.id')
                self.send_json(200,{'gateway':'connected','googlePlaces':'connected',
                    'message':'Render authenticated successfully with Google Places API (New).'}); return True
            if target.path=='/api/places/search':
                text=query.get('q',[''])[0].strip()
                if len(text)<2 or len(text)>180: self.send_json(422,{'error':'invalid_query'}); return True
                language_code=query.get('lang',['en'])[0].lower()
                if language_code not in ('en','el'): language_code='en'
                payload=google_places_json('places:searchText',api_key,body={'textQuery':text,'pageSize':12,'languageCode':language_code},
                    field_mask='places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.primaryTypeDisplayName,places.types,places.addressComponents,places.viewport')
                results=[]
                for place in payload.get('places',[]):
                    location=place.get('location') or {}
                    title=(place.get('displayName') or {}).get('text')
                    if not title or not isinstance(location.get('latitude'),(int,float)) or not isinstance(location.get('longitude'),(int,float)): continue
                    components=place.get('addressComponents') or []
                    city=next((component.get('longText','') for component in components
                        if 'locality' in component.get('types',[]) or 'postal_town' in component.get('types',[])), '')
                    country=next((component.get('shortText','') for component in components
                        if 'country' in component.get('types',[])), '')
                    matching_component=next((component for component in components
                        if title.casefold() in (component.get('longText','').casefold(),component.get('shortText','').casefold())), {})
                    viewport=place.get('viewport') or {}
                    low=viewport.get('low') or {}; high=viewport.get('high') or {}
                    latitude_span=abs(high.get('latitude',0)-low.get('latitude',0)) or None
                    longitude_span=abs(high.get('longitude',0)-low.get('longitude',0)) or None
                    place_types=place.get('types',[])
                    component_types=matching_component.get('types',[])
                    if 'country' in place_types or 'country' in component_types: boundary_level='country'
                    elif 'administrative_area_level_1' in place_types or 'administrative_area_level_1' in component_types: boundary_level='region'
                    elif 'administrative_area_level_2' in place_types or 'administrative_area_level_2' in component_types: boundary_level='district'
                    elif any(area_type in place_types or area_type in component_types for area_type in ('neighborhood','sublocality','sublocality_level_1')): boundary_level='area'
                    elif any(area_type in place_types or area_type in component_types for area_type in ('locality','postal_town')): boundary_level='city'
                    elif city and city.casefold()==title.casefold(): boundary_level='city'
                    else: boundary_level=None
                    results.append({'placeID':place.get('id'),'name':title,'address':place.get('formattedAddress',''),
                        'latitude':location['latitude'],'longitude':location['longitude'],
                        'primaryType':place.get('primaryTypeDisplayName',{}).get('text') or place.get('primaryType',''),
                        'types':place_types,'city':city,'countryCode':country,'isArea':boundary_level is not None,
                        'boundaryLevel':boundary_level,
                        'latitudeSpan':latitude_span,'longitudeSpan':longitude_span})
                self.send_json(200,{'places':results}); return True
            if target.path=='/api/places/details':
                place_id=query.get('place_id',[''])[0].strip()
                if not place_id or len(place_id)>180 or any(char not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for char in place_id):
                    self.send_json(422,{'error':'invalid_place_id'}); return True
                # Request documented top-level collections. Nested repeated-field
                # masks vary across API revisions and must not break the whole card.
                fields=','.join(['id','displayName','formattedAddress','location','primaryTypeDisplayName','rating','userRatingCount',
                    'regularOpeningHours','currentOpeningHours','internationalPhoneNumber','websiteUri','googleMapsUri',
                    'editorialSummary','photos','reviews'])
                place=google_places_json('places/'+quote(place_id,safe=''),api_key,field_mask=fields)
                photos=[]
                for photo in place.get('photos',[])[:8]:
                    name=photo.get('name')
                    if name:
                        photos.append({'name':name,'authorAttributions':photo.get('authorAttributions',[]),
                            'googleMapsURL':photo.get('googleMapsUri')})
                reviews=[]
                for review in place.get('reviews',[])[:5]:
                    author=review.get('authorAttribution') or {}
                    reviews.append({'rating':review.get('rating'),'text':(review.get('text') or {}).get('text',''),
                        'relativeTime':review.get('relativePublishTimeDescription',''),'authorName':author.get('displayName','Google Maps user'),
                        'authorURL':author.get('uri'),'authorPhotoURL':author.get('photoUri'),'googleMapsURL':review.get('googleMapsUri'),
                        'visitDate':review.get('visitDate')})
                opening=place.get('currentOpeningHours') or place.get('regularOpeningHours') or {}
                self.send_json(200,{'placeID':place.get('id',place_id),'name':(place.get('displayName') or {}).get('text',''),
                    'address':place.get('formattedAddress',''),'latitude':(place.get('location') or {}).get('latitude'),
                    'longitude':(place.get('location') or {}).get('longitude'),'primaryType':(place.get('primaryTypeDisplayName') or {}).get('text',''),
                    'rating':place.get('rating'),'reviewCount':place.get('userRatingCount'),'openNow':opening.get('openNow'),
                    'openingHours':opening.get('weekdayDescriptions',[]),'phoneNumber':place.get('internationalPhoneNumber'),
                    'websiteURL':place.get('websiteUri'),'googleMapsURL':place.get('googleMapsUri'),
                    'summary':(place.get('editorialSummary') or {}).get('text',''),'photos':photos,'reviews':reviews,
                    # Diagnostic: which top-level fields Google actually returned (names only, no content).
                    'returnedFields':sorted(place.keys())})
                return True
            if target.path=='/api/places/hours':
                # Weekly hours only, for the map's "Open now" toggle: up to 10 places per
                # call, one Place Details request each, remembered for a day.
                ids=[i.strip() for i in query.get('ids',[''])[0].split(',') if i.strip()][:10]
                allowed=set('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-')
                if not ids or any(len(i)>180 or not set(i)<=allowed for i in ids):
                    self.send_json(422,{'error':'invalid_place_ids'}); return True
                out={}
                for place_id in ids:
                    hit=_hours_cache.get(place_id)
                    if hit and time.time()-hit[0]<86400: out[place_id]=hit[1]; continue
                    try: place=google_places_json('places/'+quote(place_id,safe=''),api_key,field_mask='id,regularOpeningHours,utcOffsetMinutes')
                    except Exception: continue
                    periods=(place.get('regularOpeningHours') or {}).get('periods')
                    value={'periods':periods if isinstance(periods,list) else [],'utc_offset_minutes':place.get('utcOffsetMinutes'),
                           'known':isinstance(periods,list) and bool(periods)}
                    _hours_cache[place_id]=(time.time(),value); out[place_id]=value
                self.send_json(200,{'hours':out}); return True
            if target.path=='/api/places/photo':
                name=query.get('name',[''])[0]
                if not name.startswith('places/') or '/photos/' not in name or len(name)>4096:
                    self.send_json(422,{'error':'invalid_photo_reference'}); return True
                try: width=max(160,min(1600,int(query.get('max_width',['960'])[0])))
                except ValueError: width=960
                url='https://places.googleapis.com/v1/'+quote(name,safe='/')+'/media?maxWidthPx='+str(width)
                if query.get('format',[''])[0]=='uri':
                    # Short-lived googleusercontent URL: the app loads the bytes from Google's CDN
                    # directly instead of streaming every image through this server.
                    payload=google_places_json(quote(name,safe='/')+'/media?maxWidthPx='+str(width)+'&skipHttpRedirect=true',api_key)
                    photo_uri=payload.get('photoUri') if isinstance(payload,dict) else None
                    if not isinstance(photo_uri,str) or not photo_uri.startswith('https://'):
                        self.send_json(502,{'error':'photo_unavailable'}); return True
                    self.send_json(200,{'photoUri':photo_uri}); return True
                request=Request(url,headers={'X-Goog-Api-Key':api_key,'Accept':'image/*'})
                usage.hit('google:photo')
                with urlopen(request,timeout=15) as response:
                    image=response.read(8_000_000)
                    content_type=response.headers.get_content_type()
                if not content_type.startswith('image/') or not image: self.send_json(502,{'error':'photo_unavailable'})
                else: self.send_image(200,content_type,image)
                return True
        except HTTPError as error:
            try:
                payload=json.loads(error.read(65536))
                details=payload.get('error',{}) if isinstance(payload,dict) else {}
                code=details.get('status') or f'HTTP_{error.code}'
                message=details.get('message') or 'Google Places rejected the request.'
            except (ValueError,TypeError,json.JSONDecodeError):
                code=f'HTTP_{error.code}'; message='Google Places rejected the request.'
            if target.path=='/api/places/status':
                self.send_json(502,{'gateway':'connected','googlePlaces':'error',
                    'errorCode':code,'message':str(message)[:420]}); return True
            self.send_json(502,{'error':'google_places_unavailable','upstream_status':error.code,
                'errorCode':code,'message':str(message)[:420]}); return True
        except (URLError,TimeoutError,ValueError,KeyError,TypeError,json.JSONDecodeError):
            if target.path=='/api/places/status':
                self.send_json(502,{'gateway':'connected','googlePlaces':'error',
                    'errorCode':'google_api_unreachable',
                    'message':'Render could not reach the Google Places API.'}); return True
            self.send_json(502,{'error':'google_places_unavailable'}); return True
        return False
    def do_GET(self):
        target=urlsplit(self.path)
        if target.path=='/admin':
            self.send_html(200,(root()/'admin'/'dashboard.html').read_text()); return
        if target.path.startswith('/api/admin/'): self.admin(target,'GET'); return
        if target.path.startswith('/api/places/'): self.google_places(target); return
        if target.path in ('/api/social/extract','/api/social/status'):
            if not places_access_allowed(self): self.send_json(401,{'error':'access_token_required'}); return
            if target.path=='/api/social/status':
                try: self.send_json(200,{'models':social_queue()._pool_factory().status()})
                except Exception as error: self.send_json(503,{'error':'gemini_unavailable','message':str(error)[:300]})
                return
            job=social_queue().get(parse_qs(target.query).get('job_id',[''])[0])
            if job is None: self.send_json(404,{'error':'job_not_found'})
            else: self.send_json(200,job)
            return
        if target.path!='/api/status': self.send_json(404,{'error':'not_found'}); return
        capabilities={'api_version':3,'research_contract_version':4,'result_schema':'trippy-research-v1',
            'pipeline_version':'personal-places-v1','planning_strategies':['research','personal_places'],
            'build_commit':os.environ.get('RENDER_GIT_COMMIT','local')}
        job_id=parse_qs(target.query).get('job_id',[None])[0]
        if job_id is None:
            # Preflight does not expose another run's brief, result or job capability.
            try: issues=configuration_issues(read_environment(root()/'.env'))
            except (ValueError,OSError): issues=['ENVIRONMENT_CONFIGURATION']
            personal=parse_qs(target.query).get('strategy',[None])[0]=='personal_places'
            self.send_json(200,{**capabilities,'is_running':state.is_running,'has_result':False,
                'research_ready':personal or not issues,'configuration_issues':[] if personal else issues}); return
        try: job=read_job(job_id)
        except (ValueError,KeyError): job=None
        if job is None: self.send_json(404,{'error':'job_not_found'}); return
        self.send_json(200,{**capabilities,**job,'has_result':job['result'] is not None})
    def do_POST(self):
        target=urlsplit(self.path)
        if target.path.startswith('/api/admin/'): self.admin(target,'POST'); return
        if target.path=='/api/usage/report':
            if not places_access_allowed(self): self.send_json(401,{'error':'access_token_required'}); return
            if self.client_id=='unknown': self.send_json(422,{'error':'install_id_required'}); return
            try: payload=self.read_json(4000)
            except (ValueError,json.JSONDecodeError): self.send_json(422,{'error':'invalid_report'}); return
            recorder.report(self.client_id,payload if isinstance(payload,dict) else {})
            self.send_json(200,{'ok':True,'blocked':self.client_id in controls.snapshot()['blocked']}); return
        if urlsplit(self.path).path == '/api/social/extract':
            if not places_access_allowed(self): self.send_json(401, {'error': 'access_token_required'}); return
            refusal=controls.refusal(self.client_id)
            if refusal: self.refuse(refusal); return
            usage.hit('social:extract',self.client_id)
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 24_000_000: raise ValueError('invalid_length')
                body = json.loads(self.rfile.read(length))
                source_id = str(UUID(str(body.get('source_id'))))
                evidence = [{'origin': str(b.get('origin', ''))[:40], 'text': str(b.get('text', ''))[:40000]}
                            for b in (body.get('evidence') or [])[:40] if isinstance(b, dict)]
                images = [(str(i.get('mime', 'image/jpeg')), base64.b64decode(i['data']))
                          for i in (body.get('images') or [])[:12] if isinstance(i, dict) and i.get('data')]
                audio = body.get('audio') or None
                audio = (str(audio.get('mime', 'audio/mp4')), base64.b64decode(audio['data'])) if isinstance(audio, dict) and audio.get('data') else None
                if not evidence and not images and not audio: raise ValueError('no_evidence')
            except (ValueError, KeyError, TypeError, json.JSONDecodeError, base64.binascii.Error):
                self.send_json(422, {'error': 'invalid_social_source'}); return
            source = {'url': str(body.get('url') or '')[:500], 'author': str(body.get('author') or '')[:120],
                      'evidence': evidence, 'images': images, 'audio': audio}
            self.send_json(202, social_queue().submit(source_id, source)); return
        if urlsplit(self.path).path == '/api/places/retain':
            if not places_access_allowed(self): self.send_json(401, {'error': 'access_token_required'}); return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 50000: raise ValueError('invalid_length')
                records = json.loads(self.rfile.read(length)).get('places')
                if not isinstance(records, list) or not 0 < len(records) <= 100: raise ValueError('invalid_records')
                for record in records:
                    identifier = record.get('placeID', '')
                    if not isinstance(identifier, str) or not 0 < len(identifier) <= 180 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in identifier): raise ValueError('invalid_id')
                    if record.get('source') not in ('pins', 'saves', 'trips', 'videos', 'viewed'): raise ValueError('invalid_source')
            except (ValueError, TypeError, AttributeError):
                self.send_json(422, {'error': 'invalid_place_references'}); return
            try:
                retain_google_references(records)
            except Exception:
                logging.warning('Place reference catalog write failed; provider content was not stored.')
                self.send_json(503, {'error': 'place_catalog_unavailable'}); return
            self.send_json(200, {'retained': len(records)}); return
        if urlsplit(self.path).path!='/api/research': self.send_json(404,{'error':'not_found'}); return
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<=1000000: raise ValueError('bounded_request_required')
            brief=json.loads(self.rfile.read(length).decode())
            if isinstance(brief,dict) and brief.get('planning_strategy')=='personal_places' and not places_access_allowed(self):
                self.send_json(401,{'error':'access_token_required'}); return
            refusal=controls.refusal(self.client_id,google=True,paid=True)
            if refusal: self.refuse(refusal); return
            job_id,brief=begin_job(brief)
        except RuntimeError:
            self.send_json(409,{'error':'research_already_running'}); return
        except (ValueError,TypeError,KeyError):
            self.send_json(422,{'error':'invalid_trip_brief'}); return
        client=self.client_id
        usage.hit('plan:started',client)
        def planned():
            # The plan's own calls (Google, Wikidata, Gemini) count for the install that asked.
            usage.set_client(client)
            run_pipeline(brief,job_id)
            result=(state.jobs.get(job_id) or {}).get('result') or {}
            usage.hit('plan:'+{'ready':'ready','partial':'partial'}.get(result.get('delivery_status'),'failed'),client)
        threading.Thread(target=planned,daemon=True).start()
        self.send_json(202,{'status':'started','job_id':job_id,'status_url':'/api/status?job_id='+job_id})
    def log_message(self,format,*args): pass


def run_server(port=8080):
    logging.basicConfig(level=logging.INFO)
    server=ThreadingHTTPServer(('0.0.0.0',port),RequestHandler)
    print(f'Trippy planning bridge listening on port {port}')
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()

if __name__=='__main__':
    logging.basicConfig(level=logging.INFO,format='%(message)s')
    run_server(int(os.environ.get('PORT','8080')))
