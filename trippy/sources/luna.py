"""Explicit Azure Luna-only structured extraction with durable cost reservations.

The user supplies deployment pricing in the budget currency. Reservations are
conservative and retained on errors. No fallback model or hidden SDK retries.
"""
from contextlib import closing
from decimal import Decimal, InvalidOperation
from datetime import datetime, timezone
import json
from pathlib import Path
import sqlite3
import re
from email.utils import parsedate_to_datetime

from trippy_config import configured, valid_url
from .extraction import Extraction


class BudgetError(ValueError):
    pass


class ProviderConfigurationError(ValueError):
    def __init__(self, message, http_status=None):
        self.http_status=http_status
        super().__init__(message)


class TransientProviderError(ValueError):
    """Sanitized retry hint; only explicitly configured runners may retry."""
    def __init__(self, kind='temporary_provider_error', retry_after_seconds=None, http_status=None):
        self.kind = kind
        self.http_status = http_status
        self.retry_after_seconds = retry_after_seconds
        super().__init__(f'Luna temporary failure ({kind}); reservation retained, credentials redacted')


def retry_hint(exc):
    headers = getattr(getattr(exc, 'response', None), 'headers', {}) or {}
    for key, multiplier in (('retry-after-ms', .001), ('retry-after', 1)):
        raw = headers.get(key)
        if raw is None: continue
        try:
            delay = float(raw)*multiplier
            if 0 <= delay <= 604800: return delay
        except (ValueError, TypeError):
            if key == 'retry-after':
                try:
                    delay = (parsedate_to_datetime(raw)-datetime.now(timezone.utc)).total_seconds()
                    return max(0, delay)
                except (ValueError, TypeError, OverflowError): pass
    return None


def positive(value, field):
    try:
        number = Decimal(str(value))
        if not number.is_finite() or number <= 0: raise ValueError()
        return number
    except (InvalidOperation, ValueError):
        raise BudgetError(field + ': finite positive value required') from None


def reserve_cost(ledger, amount, cap, currency, *, group=None, chunk_id=None, max_requests=None):
    # Exact decimal text, not floating point. One durable ledger for this
    # extraction workspace, shared by concurrent invocations and retries.
    with closing(sqlite3.connect(ledger, timeout=10)) as db, db:
        db.execute('CREATE TABLE IF NOT EXISTS extraction_budget (id INTEGER PRIMARY KEY CHECK(id=1), currency TEXT, reserved TEXT)')
        db.execute('CREATE TABLE IF NOT EXISTS extraction_requests (id INTEGER PRIMARY KEY, request_group TEXT, chunk_id TEXT, amount TEXT, created_at TEXT)')
        db.execute('BEGIN IMMEDIATE')
        row = db.execute('SELECT currency,reserved FROM extraction_budget WHERE id=1').fetchone()
        if row and row[0] != currency: raise BudgetError('Budget ledger currency mismatch')
        used = Decimal(row[1]) if row else Decimal(0)
        if used + amount > cap: raise BudgetError('Extraction cost reservation would exceed configured cap')
        if group and max_requests is not None:
            count=db.execute('SELECT COUNT(*) FROM extraction_requests WHERE request_group=?',(group,)).fetchone()[0]
            if count>=max_requests:raise BudgetError('Authorized pilot request ceiling reached')
        db.execute('INSERT OR REPLACE INTO extraction_budget VALUES (1,?,?)', (currency, str(used+amount)))
        if group:
            cursor=db.execute('INSERT INTO extraction_requests (request_group,chunk_id,amount,created_at) VALUES (?,?,?,?)',
                (group,chunk_id,str(amount),datetime.now(timezone.utc).isoformat()))
            return cursor.lastrowid


def make_provider(values, ledger, *, client_factory=None, max_output_tokens=None, request_timeout=120):
    if isinstance(request_timeout, bool) or not isinstance(request_timeout, (int, float)) or not 1 <= request_timeout <= 600:
        raise BudgetError('Provider timeout must be between 1 and 600 seconds')
    if values.get('TRIPPY_ALLOW_PAID_RESEARCH', '').lower() != 'true':
        raise BudgetError('Paid research is disabled; extraction requests can still be prepared locally')
    cap = positive(values.get('TRIPPY_AI_BUDGET_AMOUNT', ''), 'TRIPPY_AI_BUDGET_AMOUNT')
    currency = values.get('TRIPPY_AI_BUDGET_CURRENCY')
    if currency not in {'EUR', 'USD'}: raise BudgetError('Budget currency must be EUR or USD')
    input_rate = positive(values.get('TRIPPY_LUNA_INPUT_PER_MILLION', ''), 'TRIPPY_LUNA_INPUT_PER_MILLION')
    output_rate = positive(values.get('TRIPPY_LUNA_OUTPUT_PER_MILLION', ''), 'TRIPPY_LUNA_OUTPUT_PER_MILLION')
    for name in ('AZURE_OPENAI_API_KEY', 'AZURE_DEPLOYMENT_LUNA'):
        if not configured(values.get(name)): raise BudgetError(name + ': required')
    if not valid_url(values.get('AZURE_OPENAI_ENDPOINT', ''), {'https'}):
        raise BudgetError('Valid HTTPS Azure endpoint required')
    try:
        max_output_tokens=max_output_tokens or int(values.get('TRIPPY_LUNA_MAX_OUTPUT_TOKENS','8000'))
        request_cap=int(values['TRIPPY_LUNA_MAX_REQUESTS']) if values.get('TRIPPY_LUNA_MAX_REQUESTS') else None
    except ValueError:raise BudgetError('Invalid token/request ceiling') from None
    if not 1000 <= max_output_tokens <= 16000: raise BudgetError('Invalid output token cap')
    if request_cap is not None and not 1<=request_cap<=100:raise BudgetError('Invalid request ceiling')
    group=values.get('TRIPPY_LUNA_REQUEST_GROUP','local-extraction')
    if not re.fullmatch(r'[a-zA-Z0-9_-]{1,100}',group):raise BudgetError('Invalid request group')
    effort=values.get('TRIPPY_LUNA_REASONING_EFFORT','low')
    if effort not in {'none','low','medium','high','xhigh','max'}:raise BudgetError('Invalid Luna reasoning effort')
    raw_dir=Path(ledger).parent/'extraction-raw-responses';raw_dir.mkdir(parents=True,mode=0o700,exist_ok=True)
    if client_factory is None:
        from openai import AzureOpenAI
        client_factory = AzureOpenAI
    client = client_factory(api_key=values['AZURE_OPENAI_API_KEY'], azure_endpoint=values['AZURE_OPENAI_ENDPOINT'],
        api_version=values.get('AZURE_OPENAI_API_VERSION', '2024-10-21'), max_retries=0, timeout=request_timeout)
    def provider(chunk):
        payload=chunk['payload']
        if chunk.get('validation_feedback'):
            payload={**payload,'untrusted_previous_candidate_and_validation_feedback':chunk['validation_feedback']}
        messages = [{'role': 'system', 'content': chunk['system_prompt']},
                    {'role': 'user', 'content': json.dumps(payload, ensure_ascii=False)}]
        # A byte-based worst-case input allowance plus schema/protocol overhead,
        # rather than an optimistic characters/4 estimate. Reserve output cap.
        max_input = len(json.dumps(messages, ensure_ascii=False).encode()) + len(json.dumps(chunk['response_schema']).encode()) + 4096
        amount = (max_input * input_rate + max_output_tokens * output_rate) / Decimal(1_000_000)
        request_id=reserve_cost(ledger, amount, cap, currency,group=group,chunk_id=chunk['id'],max_requests=request_cap)
        try:
            # Keep the raw completion before parsing, including truncated output.
            # Request the same strict schema; local Pydantic/evidence validation
            # still controls which candidates can enter the validated cache.
            response = client.chat.completions.create(model=values['AZURE_DEPLOYMENT_LUNA'],
                messages=messages, response_format={'type':'json_schema','json_schema':
                    {'name':'Extraction','strict':True,'schema':chunk['response_schema']}},
                max_completion_tokens=max_output_tokens,reasoning_effort=effort)
            usage=getattr(response,'usage',None)
            choice=response.choices[0]
            raw=response.model_dump() if hasattr(response,'model_dump') else {'finish_reason':choice.finish_reason,
                'content':getattr(choice.message,'content',None),'refusal':getattr(choice.message,'refusal',None)}
            with (raw_dir/f'request-{request_id}.json').open('x') as stream:json.dump(raw,stream,ensure_ascii=False)
            record={'at':datetime.now(timezone.utc).isoformat(),'chunk_id':chunk['id'],
                'request_id':request_id,'request_group':group,'finish_reason':choice.finish_reason,
                'model':getattr(response,'model',None),'response_id':getattr(response,'id',None),
                'usage':usage.model_dump() if usage else None,'reserved_cost':str(amount),
                'currency':currency,'pricing_basis':'configured_conservative_reservation_rates'}
            with Path(ledger).with_suffix('.usage.jsonl').open('a') as stream:
                stream.write(json.dumps(record)+'\n')
            if choice.finish_reason != 'stop':raise ValueError('Luna response incomplete: '+choice.finish_reason)
            if getattr(choice.message,'refusal',None):raise ValueError('Luna refused the extraction request')
            try:return json.loads(choice.message.content)
            except (ValueError,TypeError):raise ValueError('Luna response was not valid JSON') from None
        except Exception as exc:
            status=getattr(exc,'status_code',None)
            if status in {400,401,403,404,422}:
                raise ProviderConfigurationError(
                    f'Azure rejected the Luna request (HTTP {status}); check deployment, API version and structured-output compatibility',http_status=status) from None
            if status in {408,429,500,502,503,504} or type(exc).__name__ in {'APITimeoutError','APIConnectionError'}:
                kind = 'rate_limit' if status == 429 else 'timeout' if status == 408 or type(exc).__name__ == 'APITimeoutError' else 'service_unavailable'
                raise TransientProviderError(kind, retry_hint(exc),http_status=status) from None
            if type(exc) is ValueError:raise
            raise ValueError('Luna request failed ('+type(exc).__name__+'); reservation retained, credentials redacted') from None
    return provider
