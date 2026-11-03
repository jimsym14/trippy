"""Trip-scoped bridge for the resumable planning pipeline.

No SDK client initializes at import. Paid providers require explicit configured
budgets. Status/results require the unguessable run capability returned by POST.
"""
import json
import logging
import os
from pathlib import Path
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlsplit
from uuid import uuid4, UUID

from trippy_config import read_environment
from trippy.sources.luna import BudgetError, ProviderConfigurationError
from trippy.planner.planning_contract import normalized_brief
from trippy.planner.pipeline import run as execute_plan, StageStore
from trippy.planner.live_provider import AzureResearchProvider, ResearchConfigurationError, configuration_issues
from trippy.planner.diagnostics import failure_details


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
        if step in {'pipeline_started','task_started','task_completed','task_failed','phase_skipped'}:
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
        if provider is None:
            ledger=Path(values.get('TRIPPY_SHARED_BUDGET_LEDGER',str(root()/'.local/stage3/extraction-budget.sqlite')))
            if not ledger.is_absolute(): ledger=root()/ledger
            provider=AzureResearchProvider(values,ledger)
        result=execute_plan(brief_data,provider=provider,directory=job_directory(job_id),root=root(),
            route_provider=route_provider,progress=lambda step,detail:progress(job_id,step,detail) if step not in {'completed','partial'} else None)
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


class RequestHandler(BaseHTTPRequestHandler):
    def send_json(self,status,payload):
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        self.end_headers()
        self.wfile.write(json.dumps(payload,ensure_ascii=False,allow_nan=False).encode())
    def do_GET(self):
        target=urlsplit(self.path)
        if target.path!='/api/status': self.send_json(404,{'error':'not_found'}); return
        capabilities={'api_version':3,'research_contract_version':4,'result_schema':'trippy-research-v1',
            'pipeline_version':'trip-pipeline-v1','build_commit':os.environ.get('RENDER_GIT_COMMIT','local')}
        job_id=parse_qs(target.query).get('job_id',[None])[0]
        if job_id is None:
            # Preflight does not expose another run's brief, result or job capability.
            try: issues=configuration_issues(read_environment(root()/'.env'))
            except (ValueError,OSError): issues=['ENVIRONMENT_CONFIGURATION']
            self.send_json(200,{**capabilities,'is_running':state.is_running,'has_result':False,
                'research_ready':not issues,'configuration_issues':issues}); return
        try: job=read_job(job_id)
        except (ValueError,KeyError): job=None
        if job is None: self.send_json(404,{'error':'job_not_found'}); return
        self.send_json(200,{**capabilities,**job,'has_result':job['result'] is not None})
    def do_POST(self):
        if urlsplit(self.path).path!='/api/research': self.send_json(404,{'error':'not_found'}); return
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<=1000000: raise ValueError('bounded_request_required')
            brief=json.loads(self.rfile.read(length).decode())
            job_id,brief=begin_job(brief)
        except RuntimeError:
            self.send_json(409,{'error':'research_already_running'}); return
        except (ValueError,TypeError,KeyError):
            self.send_json(422,{'error':'invalid_trip_brief'}); return
        threading.Thread(target=run_pipeline,args=(brief,job_id),daemon=True).start()
        self.send_json(202,{'status':'started','job_id':job_id,'status_url':'/api/status?job_id='+job_id})
    def log_message(self,format,*args): pass


def run_server(port=8080):
    server=HTTPServer(('0.0.0.0',port),RequestHandler)
    print(f'Trippy planning bridge listening on port {port}')
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()

if __name__=='__main__':
    logging.basicConfig(level=logging.INFO,format='%(message)s')
    run_server(int(os.environ.get('PORT','8080')))
