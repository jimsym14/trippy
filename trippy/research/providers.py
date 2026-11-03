"""Bounded operator HTTP/JSON-LD adapters and conservative branch identity checks."""
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
import ipaddress
import json
import socket
import multiprocessing
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit, parse_qsl
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.robotparser import RobotFileParser

from trippy.catalog.normalize import normalize_text
from trippy.sources.extraction import fingerprint
from trippy.sources.identity_review import address_key, host
from trippy.sources.luna import TransientProviderError


USER_AGENT = 'TrippyResearch/1.0 (bounded operator-source checks)'
CAPABILITIES = {
    'local_overture': {'network': False, 'identity_candidates': True, 'live_hours': False,
                      'date_specific_availability': False, 'entrance_verified': False},
    'operator_jsonld': {'network': True, 'structured_published_fields': True,
                       'date_specific_availability': False, 'entrance_verified': False},
    'operator_json': {'network': True, 'configured_field_mapping': True,
                     'date_specific_availability': False, 'entrance_verified': False},
    'luna_source_extraction': {'network': True, 'web_search': False, 'proposals_only': True},
}


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def public_url(url, *, resolver=socket.getaddrinfo):
    """Reject private targets, credentials and unexpected protocols before fetching."""
    try:
        p = urlsplit(url)
        if p.scheme != 'https' or not p.hostname or p.username or p.password or p.port not in {None, 443} or p.fragment:
            raise ValueError()
        if any(c.isspace() for c in url): raise ValueError()
        if any(any(word in key.lower() for word in ('token','secret','password','api_key','apikey','signature'))
               or key.lower()=='key' for key,_ in parse_qsl(p.query)):
            raise ValueError()
        addresses = resolver(p.hostname, 443, type=socket.SOCK_STREAM)
        if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
            raise ValueError()
    except (ValueError, OSError):
        raise ValueError('Operator URL must resolve to public HTTPS without credentials') from None
    return url


def canonical_url(url):
    p = urlsplit(url)
    if not p.hostname or p.username or p.password or p.scheme not in {'http', 'https'} or p.port not in {None, 80, 443}:
        raise ValueError('Unsupported source URL')
    if any(c.isspace() for c in url) or any(
            any(word in key.lower() for word in ('token','secret','password','api_key','apikey','signature'))
            or key.lower()=='key' for key,_ in parse_qsl(p.query)):
        raise ValueError('Source URL cannot contain credentials or whitespace')
    return urlunsplit(('https', p.netloc.removesuffix(':80').removesuffix(':443'), p.path or '/', p.query, ''))


class SafeRedirect(HTTPRedirectHandler):
    def __init__(self, request_hook=None): self.request_hook=request_hook

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        public_url(newurl)
        if host(newurl) != host(req.full_url):
            raise ValueError('Cross-domain operator redirect requires a new source entry')
        if self.request_hook: self.request_hook(host(newurl))
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def http_get(url, *, timeout=20, max_bytes=1_000_000, request_hook=None):
    public_url(url)
    if request_hook: request_hook(host(url))
    request = Request(url, headers={'User-Agent': USER_AGENT, 'Accept': 'text/html, application/ld+json, application/json, text/plain'})
    try:
        with build_opener(SafeRedirect(request_hook)).open(request, timeout=timeout) as response:
            body = response.read(max_bytes+1)
            if len(body) > max_bytes: raise ValueError('Operator response exceeds bounded byte limit')
            content_type = response.headers.get_content_type()
            if content_type not in {'text/html', 'application/json', 'application/ld+json', 'text/plain'}:
                raise ValueError('Unsupported operator response content type')
            return {'body': body.decode(response.headers.get_content_charset() or 'utf-8', errors='replace'),
                    'content_type': content_type, 'url': response.url, 'status': response.status}
    except HTTPError as exc:
        if exc.code in {408, 429, 500, 502, 503, 504}:
            raw = exc.headers.get('Retry-After', '')
            try: delay = max(0, min(604800, float(raw)))
            except ValueError:
                from email.utils import parsedate_to_datetime
                try: delay = max(0, (parsedate_to_datetime(raw)-datetime.now(timezone.utc)).total_seconds())
                except (ValueError, TypeError): delay = None
            raise TransientProviderError('rate_limit' if exc.code==429 else 'service_unavailable', delay) from None
        raise ValueError(f'Operator source unavailable (HTTP {exc.code})') from None
    except (URLError, TimeoutError, OSError):
        raise TransientProviderError('service_unavailable') from None


def http_worker(url, timeout, max_bytes, connection):
    try:
        def hook(domain):
            connection.send(('request',domain))
            if connection.recv()!='continue': raise ValueError('HTTP dispatch not granted')
        connection.send(('ok',http_get(url,timeout=timeout,max_bytes=max_bytes,request_hook=hook)))
    except TransientProviderError as exc:
        connection.send(('transient',exc.kind,exc.retry_after_seconds))
    except Exception:
        connection.send(('invalid','Operator URL/content/access requires review'))
    finally: connection.close()


def bounded_http_get(url, *, timeout=20, max_bytes=1_000_000, request_hook=None,
                     deadline_seconds=60, worker=http_worker):
    """A trickling response or stuck DNS cannot hold the unattended runner forever.

    The parent grants and accounts for each physical request, including redirects.
    Network work is isolated and killed at the wall deadline, like Luna requests.
    """
    context=multiprocessing.get_context('spawn'); receiver,sender=context.Pipe(duplex=True)
    process=context.Process(target=worker,args=(url,timeout,max_bytes,sender),daemon=True)
    started=time.monotonic()
    try:
        process.start(); sender.close()
        while True:
            remaining=deadline_seconds-(time.monotonic()-started)
            if remaining<=0 or not receiver.poll(remaining):
                raise TransientProviderError('http_worker_deadline')
            try: message=receiver.recv()
            except EOFError: raise TransientProviderError('http_worker_exited') from None
            if message[0]=='request':
                if request_hook: request_hook(message[1])
                receiver.send('continue')
            elif message[0]=='ok': return message[1]
            elif message[0]=='transient': raise TransientProviderError(message[1],message[2])
            else: raise ValueError('Operator URL/content/access requires review')
    finally:
        receiver.close(); sender.close()
        if process.pid is not None:
            if process.is_alive(): process.terminate()
            process.join(timeout=3)
            if process.is_alive(): process.kill(); process.join(timeout=3)


def robots_allowed(url, *, getter=http_get, request_hook=None):
    p = urlsplit(url); robots_url = urlunsplit((p.scheme, p.netloc, '/robots.txt', '', ''))
    try: fetched = getter(robots_url, request_hook=request_hook)
    except ValueError as exc:
        if '(HTTP 404)' in str(exc): return True
        raise
    parser = RobotFileParser(); parser.parse(fetched['body'].splitlines())
    return parser.can_fetch(USER_AGENT, url)


class OperatorHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.hidden = []; self.ld = None; self.ld_documents = []; self.text = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in {'script', 'style', 'noscript', 'svg'}:
            self.hidden.append(tag)
            if tag=='script' and attrs.get('type', '').split(';')[0].strip()=='application/ld+json': self.ld=[]
        if tag in {'p', 'div', 'li', 'br', 'h1', 'h2', 'h3', 'address', 'tr'} and not self.hidden:
            self.text.append('\n')

    def handle_endtag(self, tag):
        if self.hidden and self.hidden[-1]==tag:
            if tag=='script' and self.ld is not None:
                try: self.ld_documents.append(json.loads(''.join(self.ld)))
                except (ValueError, TypeError): pass
                self.ld=None
            self.hidden.pop()
        if tag in {'p', 'div', 'li', 'h1', 'h2', 'h3', 'address', 'tr'} and not self.hidden:
            self.text.append('\n')

    def handle_data(self, data):
        if self.ld is not None: self.ld.append(data)
        elif not self.hidden: self.text.append(data)


LOCAL_TYPES = {'LocalBusiness', 'CafeOrCoffeeShop', 'Restaurant', 'Bakery', 'BarOrPub',
               'GroceryStore', 'Store', 'Hotel', 'Museum', 'TouristAttraction', 'Park',
               'PerformingArtsTheater', 'StadiumOrArena', 'FoodEstablishment'}
LD_FIELDS = {'name': 'name', 'address': 'address', 'openingHours': 'published_hours',
             'openingHoursSpecification': 'published_hours', 'servesCuisine': 'cuisine_statement',
             'hasMenu': 'menu_reference', 'menu': 'menu_reference', 'priceRange': 'price_statement',
             'telephone': 'telephone', 'url': 'website', 'geo': 'source_coordinates'}


def ld_nodes(value, pointer=''):
    if isinstance(value, list):
        for index, item in enumerate(value): yield from ld_nodes(item, f'{pointer}/{index}')
    elif isinstance(value, dict):
        types = value.get('@type', [])
        if isinstance(types, str): types = [types]
        if set(types) & LOCAL_TYPES: yield pointer, value
        for key, child in value.items():
            if isinstance(child, (dict, list)):
                yield from ld_nodes(child, pointer+'/'+key.replace('~', '~0').replace('/', '~1'))


def structured_observations(documents, url, checked_at):
    observations = []; seen = set()
    for index, document in enumerate(documents):
        for pointer, node in ld_nodes(document):
            if not isinstance(node.get('name'), str) or not node['name'].strip(): continue
            address = node.get('address'); text_address = None
            if isinstance(address, dict):
                text_address = ', '.join(str(address[k]) for k in
                    ('streetAddress', 'postalCode', 'addressLocality') if isinstance(address.get(k), (str, int))) or None
            elif isinstance(address, str): text_address = address
            identity = fingerprint({'name': node['name'], 'address': text_address})
            if identity in seen: continue
            seen.add(identity); facts = []
            for source_field, field in LD_FIELDS.items():
                value = node.get(source_field)
                if value is None: continue
                encoded = json.dumps(value, ensure_ascii=False, sort_keys=True)
                if len(encoded)>2000: continue
                facts.append({'field': field, 'value': value,
                    'source_pointer': f'/{index}{pointer}/{source_field}',
                    'source_value_sha256': fingerprint(value), 'status': 'structured_source_observation',
                    'checked_at': checked_at, 'source_url': url, 'current_trip_verified': False})
            observations.append({'id': identity, 'name': node['name'], 'address': text_address,
                'schema_types': node.get('@type'), 'website_url': node.get('url'),
                'source_url': url, 'checked_at': checked_at, 'facts': facts})
    return observations


def excerpt_sections(text, *, max_chars=10000, section_chars=700):
    lines = [' '.join(line.split()) for line in text.splitlines() if line.strip()]
    # Keep the title and windows around concrete venue/operational text rather
    # than sending footer navigation or the whole page to the model.
    terms = ('hour', 'open', 'monday', 'tuesday', 'saturday', 'sunday', 'carrer', 'calle',
             'address', 'coffee', 'breakfast', 'brunch', 'gluten', 'vegan', 'menu',
             'horari', 'lunes', 'sábado', 'cafè', 'café', 'supermerc', 'closed')
    wanted = set(range(min(8, len(lines))))
    for i, line in enumerate(lines):
        if any(word in line.lower() for word in terms):
            wanted.update(range(max(0,i-2), min(len(lines),i+3)))
    content = '\n'.join(lines[i] for i in sorted(wanted))[:max_chars]
    return [{'id': fingerprint({'offset': offset, 'text': content[offset:offset+section_chars]}),
             'text': content[offset:offset+section_chars]}
            for offset in range(0, len(content), section_chars)]


def fetch_operator(url, *, getter=http_get, request_hook=None, checked_at=None, check_robots=True):
    if check_robots and not robots_allowed(url, getter=getter, request_hook=request_hook):
        raise ValueError('Operator robots policy disallows this path')
    fetched = getter(url, request_hook=request_hook)
    now = checked_at or utc_now(); documents = []; text = ''
    if fetched['content_type'] in {'application/json', 'application/ld+json'}:
        try: documents=[json.loads(fetched['body'])]
        except ValueError: raise ValueError('Operator JSON is invalid') from None
    elif fetched['content_type']=='text/html':
        parser=OperatorHTML(); parser.feed(fetched['body']); documents=parser.ld_documents; text=''.join(parser.text)
    else: text=fetched['body']
    return {'url': fetched['url'], 'checked_at': now, 'body_sha256': fingerprint(fetched['body']),
        'sections': excerpt_sections(text),
        'structured_observations': structured_observations(documents, fetched['url'], now),
        'adapter': 'operator_jsonld', 'date_specific_availability_supported': False,
        'raw_html_persisted': False}


def json_pointer(document, pointer):
    if pointer=='': return document
    if not isinstance(pointer,str) or not pointer.startswith('/'):
        raise ValueError('Configured API field requires an RFC6901 JSON pointer')
    value=document
    for component in pointer[1:].split('/'):
        key=component.replace('~1','/').replace('~0','~')
        try: value=value[int(key)] if isinstance(value,list) else value[key]
        except (ValueError,IndexError,KeyError,TypeError): return None
    return value


def fetch_operator_feed(spec, *, getter=http_get, request_hook=None, checked_at=None):
    """Read a configured public operator JSON feed; no guessed API fields."""
    allowed=set(PAGE_FEED_FIELDS)
    if not set(spec['field_pointers'])<=allowed:
        raise ValueError('API field mapping is outside the supported capability contract')
    if spec.get('check_robots',True) and not robots_allowed(spec['url'],getter=getter,request_hook=request_hook):
        raise ValueError('Operator robots policy disallows the feed')
    fetched=getter(spec['url'],request_hook=request_hook)
    if fetched['content_type'] not in {'application/json','application/ld+json'}:
        raise ValueError('Configured operator feed did not return JSON')
    try: document=json.loads(fetched['body'])
    except ValueError: raise ValueError('Configured operator feed returned invalid JSON') from None
    records=json_pointer(document,spec['records_pointer'])
    if not isinstance(records,list) or len(records)>spec.get('max_records',100):
        raise ValueError('Configured feed requires a bounded records array')
    now=checked_at or utc_now(); observations=[]
    for index,record in enumerate(records):
        name=json_pointer(record,spec['name_pointer']); address=json_pointer(record,spec['address_pointer'])
        if not isinstance(name,str) or not name.strip(): continue
        if address is not None and not isinstance(address,str):
            raise ValueError('Feed address mapping must identify an explicit address string')
        facts=[]
        for field,pointer in spec['field_pointers'].items():
            value=json_pointer(record,pointer)
            if value is None: continue
            if len(json.dumps(value,ensure_ascii=False))>2000:
                raise ValueError('Configured feed field exceeds bounded value size')
            facts.append({'field':field,'value':value,'status':'structured_source_observation',
                'source_pointer':spec['records_pointer']+'/'+str(index)+pointer,
                'source_value_sha256':fingerprint(value),'source_url':fetched['url'],
                'checked_at':now,'current_trip_verified':False})
        observations.append({'id':fingerprint({'name':name,'address':address}),
            'name':name,'address':address,'schema_types':spec.get('schema_types',[]),
            'source_url':fetched['url'],'checked_at':now,'facts':facts})
    return {'url':fetched['url'],'checked_at':now,'body_sha256':fingerprint(fetched['body']),
        'sections':[],'structured_observations':observations,'adapter':'operator_json',
        'date_specific_availability_supported':False,'raw_html_persisted':False}


PAGE_FEED_FIELDS={'name','address','published_hours','business_status','price_statement',
                  'menu_reference','service_statement','dietary_statement','access_statement','source_coordinates'}


def automatic_identity(observation, candidates):
    """Unique name + operator host + civic address, never name-only matching."""
    matches = []
    type_families={'CafeOrCoffeeShop':'coffee','Bakery':'coffee','Restaurant':'food',
        'BarOrPub':'nightlife','GroceryStore':'shopping','Store':'shopping','Hotel':'stay',
        'Museum':'sights','TouristAttraction':'sights','Park':'outdoors',
        'PerformingArtsTheater':'sights','StadiumOrArena':'sights'}
    kinds=observation.get('schema_types',[])
    if isinstance(kinds,str): kinds=[kinds]
    families={type_families[k] for k in kinds if k in type_families}
    key = address_key(observation.get('address'))
    for candidate in candidates:
        if (key and key==address_key(candidate.get('address')) and
            normalize_text(observation['name'])==normalize_text(candidate['name']) and
            host(observation['source_url'])==host(candidate.get('website_url')) and
            (not families or candidate.get('family') in families) and
            candidate.get('operating_status') not in {'temporarily_closed', 'permanently_closed'} and
            candidate.get('identity_status')!='review_needed' and
            'catalog_identity_conflict' not in candidate.get('blockers', [])):
            matches.append(candidate)
    unique = {c['entity_id']: c for c in matches}
    if len(unique)!=1:
        return {'observation_id': observation['id'], 'status': 'identity_review_required',
                'eligible_candidate_count': len(unique), 'canonical_identity_verified': False}
    candidate = next(iter(unique.values()))
    return {'observation_id': observation['id'], 'entity_id': candidate['entity_id'],
        'candidate_sha256': fingerprint(candidate), 'status': 'operator_catalog_branch_correspondence',
        'source_url': observation['source_url'], 'branch_address': observation['address'],
        'canonical_identity_verified': True, 'entrance_verified': False,
        'admission_rule': 'unique_literal_name_operator_host_civic_address_and_nonconflicting_family',
        'scope': 'Operator branch identity only; transcript aliases, entrance and current fields are separate gates'}


def field_state(fact, *, as_of, refresh_days, requested_date=None):
    """A cache hit never advances checked_at; refresh is not future validity."""
    checked = datetime.fromisoformat(fact['checked_at'])
    if checked.tzinfo is None: raise ValueError('Field check needs timezone-aware timestamp')
    point = datetime.fromisoformat(as_of)
    if point.tzinfo is None: raise ValueError('Refresh resolver needs timezone-aware timestamp')
    deadline = checked + timedelta(days=refresh_days)
    stale = point < checked or point >= deadline
    return {'state': 'refresh_required' if stale else 'published_baseline_observed',
            'checked_at': fact['checked_at'], 'refresh_after': deadline.isoformat(),
            'requested_date': requested_date, 'current_trip_verified': False,
            'date_specific_check_required': requested_date is not None,
            'note': 'Refresh deadline controls rechecking; it is not an effective/availability date'}
