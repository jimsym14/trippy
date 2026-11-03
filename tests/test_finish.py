from contextlib import closing
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from trippy.planner.draft import validate_trip, compose
from trippy.planner.dataset_reader import compile_dataset, retrieve_activity, map_layers
from trippy.research.finish import Campaign, evidence_jobs, write_compiled_sqlite, DeferredWork
from trippy.sources.extraction import fingerprint
from trippy.sources.luna import TransientProviderError


def fixture():
    claim={'dimension':'other','value':'Coffee and breakfast here','citations':[]}
    record={'id':'record','upstream_occurrence_id':'original','name':'Cafe','kind':'venue',
            'identity_uncertain':False,'source':{'url':'https://example.com','external_id':'video'},
            'claims':[claim],'claim_review_metadata':[]}
    annotations=[]
    for activity in ('coffee_break','breakfast_out','brunch'):
        entry={'record_id':'record','proposal':{'claim_ids':[fingerprint(claim)]}}
        annotations.append({'key':activity,'original_entry':entry,'effective':{'kind':'activity_fit',
            'proposal':{'activity_id':activity,'claim_ids':[fingerprint(claim)]}},
            'source_discovery_eligible':True,'manual_decision':{'action':'retain'},'status':'retain'})
    bundle={'normalized':{'drafts':[record]},'held_claims':[{'key':'held'}],
        'annotations':annotations,'preserved_manual_reviews':[],'identity_links':{'events':[]},
        'operational':{'structured_fields':[],'prose_proposals':[]}}
    return bundle,compile_dataset(bundle)


def trip(**values):
    return {'synthetic':True,'start_date':'2030-01-10','end_date':'2030-01-12','activities':[],**values}


class FinishReaderTests(unittest.TestCase):
    def test_pending_or_stale_claims_cannot_become_tags(self):
        bundle,_=fixture();bundle['annotations'][0]['manual_decision']=None
        bundle['annotations'][1]['effective']['proposal']['claim_ids']=['foreign']
        compiled=compile_dataset(bundle)
        self.assertFalse(retrieve_activity(compiled,'coffee_break')['items'])
        self.assertFalse(retrieve_activity(compiled,'breakfast_out')['items'])
        self.assertEqual(compiled['held_claims'],bundle['held_claims'])
        self.assertEqual(compiled['annotation_lineage'],bundle['annotations'])

    def test_old_pack_does_not_inherit_new_annotation_admissions(self):
        bundle,_=fixture();old=deepcopy(bundle['normalized']);old['drafts'][0]['claims']=[]
        self.assertFalse(retrieve_activity(compile_dataset(bundle,pack=old),'coffee_break')['items'])

    def test_exclusion_and_empty_groceries_supply(self):
        _,compiled=fixture()
        self.assertTrue(retrieve_activity(compiled,'groceries')['coverage_gap'])
        self.assertFalse(retrieve_activity(compiled,'coffee_break',excluded_ids=['source:original'])['items'])

    def test_no_name_based_identity_dedup_or_invented_pin(self):
        bundle,_=fixture();r=deepcopy(bundle['normalized']['drafts'][0]);r['id']='second';r['upstream_occurrence_id']='second'
        bundle['normalized']['drafts'].append(r);compiled=compile_dataset(bundle)
        self.assertEqual(len(compiled['places']),2)
        self.assertTrue(all(p['canonical_id'] is None for p in compiled['places']))
        layer=map_layers(compiled,['source:original'])['layers']['coffee']
        self.assertEqual(len(layer['according_to_plan']),1)
        self.assertIsNone(layer['according_to_plan'][0]['pin'])

    def test_changed_migration_evidence_is_rejected(self):
        bundle,_=fixture();entry=bundle['annotations'][0]['original_entry'];effective=bundle['annotations'][0]['effective']
        rule={'annotation_key':'coffee_break','source_entry_sha256':'stale','effective_sha256':fingerprint(effective),
              'review_method':'agent_exact_source_quote_comparison','reason':'Compared','key':'place_type','value':'cafe'}
        with self.assertRaisesRegex(ValueError,'Stale'):compile_dataset(bundle,migrations=[rule])


class FinishDraftTests(unittest.TestCase):
    def test_daily_coffee_and_breakfast_merge_with_longer_meal_window(self):
        _,compiled=fixture();plan=compose(compiled,trip(activities=[{'id':'coffee_break','frequency':'daily'},
                                                       {'id':'breakfast_out','frequency':'daily'}]))
        self.assertEqual([len(d['stops']) for d in plan['days']],[1,1,1])
        self.assertTrue(all(d['stops'][0]['duration_minutes']==60 for d in plan['days']))
        self.assertFalse(plan['validation']['dated_checks_executed'])
        self.assertIsNone(plan['budget']['known_total_eur'])

    def test_brunch_and_coffee_share_one_supported_occurrence(self):
        _,compiled=fixture();p=compose(compiled,trip(activities=[{'id':'brunch'},{'id':'coffee_break'}]))
        self.assertEqual(p['days'][0]['stops'][0]['activities'],['brunch','coffee_break'])
        self.assertEqual(len(p['days'][0]['stops']),1)

    def test_once_coffee_only_first_day(self):
        _,compiled=fixture();p=compose(compiled,trip(activities=[{'id':'coffee_break','frequency':'once'}]))
        self.assertEqual([len(d['stops']) for d in p['days']],[1,0,0])

    def test_stay_provided_does_not_add_groceries(self):
        _,compiled=fixture();p=compose(compiled,trip(breakfast_at_stay='provided'))
        self.assertNotIn('groceries',p['retrieval'])
        self.assertTrue(all(s['place_id'] is None for d in p['days'] for s in d['stops']))

    def test_stay_supplies_records_missing_groceries_once(self):
        _,compiled=fixture();p=compose(compiled,trip(breakfast_at_stay='buy_supplies'))
        self.assertEqual(p['days'][0]['pending'][0]['activity'],'groceries')
        self.assertFalse(p['days'][1]['pending'])

    def test_unknown_stay_breakfast_never_assumed_provided(self):
        _,compiled=fixture();p=compose(compiled,trip(breakfast_at_stay='unknown'))
        self.assertIn('stay_breakfast_provision_unknown',p['days'][0]['stops'][0]['pending'])

    def test_hard_requirements_do_not_admit_unsupported_places(self):
        _,compiled=fixture()
        for requirement in ('allergy','dietary','accessibility'):
            p=compose(compiled,trip(hard_requirements=[requirement],activities=[{'id':'coffee_break'}]))
            self.assertFalse(p['days'][0]['stops'])
            self.assertTrue(p['days'][0]['pending'])

    def test_lock_preserved_and_new_stop_fits_around_it(self):
        _,compiled=fixture();lock={'place_id':'source:original','day':'2030-01-10','start_minute':600,'duration_minutes':60}
        p=compose(compiled,trip(locks=[lock],activities=[{'id':'coffee_break'}]))
        self.assertEqual(p['days'][0]['stops'][0]['start_minute'],600)
        self.assertTrue(p['days'][0]['stops'][0]['locked'])
        self.assertFalse(p['validation']['errors'])

    def test_overlapping_locks_report_invalid_not_rewritten(self):
        _,compiled=fixture();lock={'place_id':'source:original','day':'2030-01-10','start_minute':600,'duration_minutes':60}
        p=compose(compiled,trip(locks=[lock,{**lock,'start_minute':630}]))
        self.assertEqual(p['validation']['state'],'invalid_constraints')

    def test_unknown_input_and_ambiguous_stay_choice_rejected(self):
        registry={'activities':[{'id':'breakfast_at_stay'}]}
        with self.assertRaises(ValueError):validate_trip(trip(typo=True),registry)
        with self.assertRaises(ValueError):validate_trip(trip(activities=[{'id':'breakfast_at_stay'}]),registry)


class FinishCheckpointTests(unittest.TestCase):
    def test_successful_checkpoint_reused_and_tamper_detected(self):
        with tempfile.TemporaryDirectory() as folder:
            c=Campaign(folder,{'test':1});c.stage('one',lambda:{'result':1})
            self.assertEqual(c.stage('one',lambda:self.fail('reran')),{'result':1})
            (c.folder/'one.json').write_text('{}')
            with self.assertRaisesRegex(ValueError,'Checkpoint'):c.stage('one',lambda:{})

    def test_interrupted_stage_retries_without_losing_previous_stage(self):
        with tempfile.TemporaryDirectory() as folder:
            c=Campaign(folder,{'test':1});c.stage('one',lambda:{'result':1})
            with self.assertRaises(RuntimeError):c.stage('two',lambda:(_ for _ in ()).throw(RuntimeError()))
            self.assertEqual(c.stage('one',lambda:self.fail('lost checkpoint')),{'result':1})
            self.assertEqual(c.stage('two',lambda:{'result':2}),{'result':2})

    def test_full_compiled_sqlite_detects_changed_document(self):
        _,compiled=fixture()
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'compiled.sqlite';write_compiled_sqlite(path,compiled)
            with closing(sqlite3.connect(path)) as db:
                db.execute("UPDATE places SET document='{}'");db.commit()
            with self.assertRaisesRegex(ValueError,'SQLite'):write_compiled_sqlite(path,compiled)

    def test_offline_never_dispatches_operator_request(self):
        _,compiled=fixture();retrieval={'coffee':retrieve_activity(compiled,'coffee_break')}
        limits={'shortlist_source_occurrences':60,'operator_pages':30,'http_requests':150,'connected_wall_seconds':1,'transient_attempts':4}
        with tempfile.TemporaryDirectory() as folder,patch('trippy.research.providers.fetch_operator') as fetch:
            result=evidence_jobs(Campaign(folder,{'test':1}),compiled,retrieval,
                [{'place_id':'source:original','url':'https://example.com'}],False,limits)
            fetch.assert_not_called();self.assertEqual(result['operator_pages'][0]['state'],'deferred_offline')

    def test_long_retry_after_is_saved_and_resume_reuses_successful_receipt(self):
        _,compiled=fixture();retrieval={'coffee':retrieve_activity(compiled,'coffee_break')}
        sources=[{'place_id':'source:original','url':'https://example.com'}]
        limits={'shortlist_source_occurrences':60,'operator_pages':30,'http_requests':150,'connected_wall_seconds':1,'transient_attempts':4}
        with tempfile.TemporaryDirectory() as folder:
            c=Campaign(folder,{'test':1})
            with patch('trippy.research.providers.fetch_operator',side_effect=TransientProviderError('rate_limit',86400)):
                with self.assertRaises(DeferredWork):evidence_jobs(c,compiled,retrieval,sources,True,limits)
            with closing(sqlite3.connect(c.db_path)) as db:
                retry_at=db.execute('SELECT retry_at FROM pages').fetchone()[0]
                self.assertGreater(retry_at,0);db.execute('UPDATE pages SET retry_at=0');db.execute('UPDATE cooldowns SET until=0');db.commit()
            with patch('trippy.research.providers.fetch_operator',return_value={'body_sha256':'receipt'}) as fetch:
                evidence_jobs(c,compiled,retrieval,sources,True,limits);self.assertEqual(fetch.call_count,1)
            with patch('trippy.research.providers.fetch_operator') as fetch:
                result=evidence_jobs(c,compiled,retrieval,sources,True,limits)
                fetch.assert_not_called();self.assertEqual(result['operator_pages'][0]['state'],'observed_not_admitted')

    def test_host_cooldown_prevents_next_page_request(self):
        _,compiled=fixture();retrieval={'coffee':retrieve_activity(compiled,'coffee_break')}
        sources=[{'place_id':'source:original','url':'https://example.com/a'},
                 {'place_id':'source:original','url':'https://example.com/b'}]
        limits={'shortlist_source_occurrences':60,'operator_pages':30,'http_requests':150,'connected_wall_seconds':1,'transient_attempts':4}
        with tempfile.TemporaryDirectory() as folder,patch('trippy.research.providers.fetch_operator',
            side_effect=TransientProviderError('rate_limit',86400)) as fetch:
            with self.assertRaises(DeferredWork):evidence_jobs(Campaign(folder,{'test':1}),compiled,retrieval,sources,True,limits)
            self.assertEqual(fetch.call_count,1)
