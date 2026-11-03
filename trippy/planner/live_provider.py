"""Explicitly enabled, bounded Azure adapters sharing the existing spend ledger."""
from datetime import datetime, timezone
from pathlib import Path
import json
from trippy.sources.luna import BudgetError, make_provider, positive, reserve_cost
from trippy_config import configured, valid_url


class ResearchConfigurationError(BudgetError):
    """Missing configuration, distinct from an exhausted spend allowance."""


def configuration_issues(values):
    """Return setting names only; no clients, network calls or credential values."""
    issues=[]
    if values.get('TRIPPY_ALLOW_PAID_RESEARCH','').lower()!='true':
        issues.append('TRIPPY_ALLOW_PAID_RESEARCH')
    for name in ('TRIPPY_AI_BUDGET_AMOUNT','TRIPPY_WEB_RESERVATION_PER_CALL',
                 'TRIPPY_LUNA_INPUT_PER_MILLION','TRIPPY_LUNA_OUTPUT_PER_MILLION'):
        try: positive(values.get(name),name)
        except BudgetError: issues.append(name)
    if values.get('TRIPPY_AI_BUDGET_CURRENCY') not in {'USD','EUR'}:
        issues.append('TRIPPY_AI_BUDGET_CURRENCY')
    for name in ('AZURE_AGENT_ENDPOINT','AZURE_OPENAI_ENDPOINT'):
        if not valid_url(values.get(name,''),{'https'}): issues.append(name)
    for name in ('AZURE_OPENAI_API_KEY','AZURE_DEPLOYMENT_LUNA'):
        if not configured(values.get(name)): issues.append(name)
    return sorted(issues)


class AzureResearchProvider:
    def __init__(self, values, ledger, *, agent_factory=None, model_factory=None):
        # The normalizer uses the existing durable global ledger/rate contract.
        # It reserves before dispatch, keeps unknown spend held and never retries
        # silently. No stronger-model fallback is permitted.
        issues=configuration_issues(values)
        if issues: raise ResearchConfigurationError('Research configuration required: '+', '.join(issues))
        self.cap=positive(values.get('TRIPPY_AI_BUDGET_AMOUNT'),'TRIPPY_AI_BUDGET_AMOUNT')
        self.currency=values.get('TRIPPY_AI_BUDGET_CURRENCY')
        self.web_reservation=positive(values.get('TRIPPY_WEB_RESERVATION_PER_CALL'),'TRIPPY_WEB_RESERVATION_PER_CALL')
        if self.currency not in {'USD','EUR'}: raise BudgetError('Explicit budget currency is required')
        if not valid_url(values.get('AZURE_AGENT_ENDPOINT',''),{'https'}) or not configured(values.get('AZURE_OPENAI_API_KEY')):
            raise BudgetError('Configured Azure agent endpoint/key required')
        self.ledger=Path(ledger); self.ledger.parent.mkdir(parents=True,exist_ok=True)
        if agent_factory is None:
            from openai import OpenAI
            agent_factory=OpenAI
        self.agent=agent_factory(base_url=values['AZURE_AGENT_ENDPOINT'],api_key='unused',
            default_headers={'api-key':values['AZURE_OPENAI_API_KEY']},default_query={'api-version':'v1'},
            max_retries=0,timeout=120)
        self.normalize_call=make_provider({**values,'TRIPPY_LUNA_REQUEST_GROUP':'trip-pipeline'},self.ledger,
            client_factory=model_factory,max_output_tokens=8000,request_timeout=120)
    def research(self, prompt, task_id):
        request_id=reserve_cost(self.ledger,self.web_reservation,self.cap,self.currency,
            group='trip-web',chunk_id=task_id)
        folder=self.ledger.parent/'trip-web-receipts'; folder.mkdir(exist_ok=True,mode=0o700)
        try:
            conversation=self.agent.conversations.create()
            response=self.agent.responses.create(conversation=conversation.id,
                input=[{'role':'user','content':prompt}],max_output_tokens=6000,max_tool_calls=4)
            raw=response.model_dump()
            (folder/f'{request_id}.json').write_text(json.dumps(raw,ensure_ascii=False))
            if getattr(response,'status',None)!='completed' or not response.output_text:
                raise ValueError('Web research did not complete; receipt retained')
            citations=[]
            for output in raw.get('output',[]):
                for content in output.get('content',[]):
                    citations += [a['url'] for a in content.get('annotations',[]) if a.get('type')=='url_citation' and a.get('url')]
            return {'text':response.output_text,'citation_urls':sorted(set(citations)),
                    'retrieved_at':datetime.now(timezone.utc).isoformat(),'response_id':response.id,
                    'usage':raw.get('usage'),'reservation_id':request_id}
        except Exception as exc:
            (folder/f'{request_id}-failure.json').write_text(json.dumps({'status':'uncertain','type':type(exc).__name__,
                'reservation_retained':True,'task':task_id}))
            raise ValueError('Web request failed; inspect the retained receipt before retrying') from None
    def normalize(self, system, payload, schema, task_id):
        return self.normalize_call({'id':task_id,'system_prompt':system,'payload':payload,'response_schema':schema})
