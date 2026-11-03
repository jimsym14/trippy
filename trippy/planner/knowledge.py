"""Private versioned source knowledge; canonical promotion is a separate gate."""
import argparse
import json
from pathlib import Path

from trippy.sources.coverage import private_write
from trippy.sources.curation_cycle import validate_observations
from trippy.sources.extraction import fingerprint
from .evidence import Place, retrieve


class Knowledge:
    def __init__(self, document):
        self.document = document
        self.places = [Place.model_validate(p).model_dump(mode='json') for p in document['places']]
        ids = [p['id'] for p in self.places]
        if len(set(ids)) != len(ids): raise ValueError('Duplicate knowledge place ID')
        self.city_id = document['city_id']
        if any(p['city_id'] != self.city_id for p in self.places):
            raise ValueError('Knowledge must be scoped to one city')
        if document['gates']['planner_ready'] and (not all(document['gates'].values()) or
                not self.places or any(p['identity'] != 'confirmed' for p in self.places)):
            raise ValueError('Readiness metadata cannot bypass unfinished release gates')

    @classmethod
    def load(cls, path):
        return cls(json.loads(Path(path).read_text()))

    def search(self, request):
        if request['city_id'] != self.city_id: raise ValueError('Requested city differs from knowledge snapshot')
        return {**retrieve(self.places, request), 'knowledge_version': self.document['version'],
            'dataset_planner_ready': self.document['gates']['planner_ready'],
            'source_observations': self.document['metrics']['source_observations']}


def build(observations, *, city_id, timezone, identity_decisions=None):
    validate_observations(observations)
    links = {e['decision']['observation_id']: e['candidate'] for e in (identity_decisions or {}).get('events', [])
             if e['decision']['action'] == 'link_source_identity'}
    places = []
    for observation in observations:
        candidate = links.get(observation['id'])
        if candidate:
            event = next(e for e in identity_decisions['events'] if
                e['decision']['observation_id'] == observation['id'] and e['decision']['action'] == 'link_source_identity')
            if event['source_observation_sha256'] != fingerprint(observation):
                raise ValueError('Identity decision references a changed source observation')
        facts = []
        for position, fact in enumerate(observation['facts']):
            facts.append({'id': fingerprint({'observation': observation, 'fact': fact})[:24],
                'field': fact['field'], 'value': fact['value'], 'source_url': observation['source_url'],
                'source_kind': 'primary', 'reviewed_on': observation['retrieved_at'],
                'status': 'reviewed_source', 'scope': fact.get('scope', 'venue'), 'valid_through': None})
        # Coverage cells are diagnostics, not approved fit facets. Never turn them
        # into verified filter values or clear an identity flag automatically.
        place = {'id': 'observation:'+observation['id'], 'name': observation['name'],
            'city_id': city_id, 'timezone': timezone, 'identity': 'candidate',
            'location': 'source_point' if candidate else 'unknown',
            'latitude': candidate['latitude'] if candidate else None,
            'longitude': candidate['longitude'] if candidate else None,
            'facts': facts, 'facets': [], 'parent_id': None,
            'limitations': [observation['fit_limit']] if observation.get('fit_limit') else []}
        places.append(Place.model_validate(place).model_dump(mode='json'))
    spec = {'observations_sha256': fingerprint(observations), 'identity_decisions_sha256': fingerprint(identity_decisions),
            'engine_sha256': fingerprint(Path(__file__).read_text()), 'city_id': city_id, 'timezone': timezone}
    return {'version': fingerprint(spec), 'city_id': city_id, 'manifest': spec, 'places': places,
        'metrics': {'source_observations': len(observations), 'source_identity_links': len(links),
                    'approved_canonical_places': 0, 'approved_fit_facets': 0},
        'gates': {'planner_ready': False, 'canonical_identity': False, 'semantic_review_complete': False,
                  'coverage_depth': False, 'selected_trip_checks': False, 'scenario_evaluation': False},
        'use': 'Private research snapshot only; not a canonical release or a complete planner dataset'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--observations', type=Path, nargs='+', required=True)
    parser.add_argument('--identity-decisions', type=Path)
    parser.add_argument('--city-id', required=True)
    parser.add_argument('--timezone', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    observations = [o for p in args.observations for o in json.loads(p.read_text())]
    document = build(observations, city_id=args.city_id, timezone=args.timezone,
                     identity_decisions=json.loads(args.identity_decisions.read_text()) if args.identity_decisions else None)
    if args.output.exists():
        if json.loads(args.output.read_text()) != document: raise ValueError('Versioned knowledge output differs')
    else: private_write(args.output, document)
    print(json.dumps({'output': str(args.output), 'version': document['version'], 'metrics': document['metrics'],
                      'gates': document['gates']}, indent=2))


if __name__ == '__main__': main()
