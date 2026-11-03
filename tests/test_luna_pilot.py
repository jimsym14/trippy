import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tests import test_creator_extraction as fixtures
from trippy.sources.extraction import execute_chunks
from trippy.sources.luna import BudgetError, ProviderConfigurationError, reserve_cost
from decimal import Decimal
from trippy.sources.pilot import run_pilot, validate_pilot


class LunaPilotTests(unittest.TestCase):
    def prepared(self):
        chunk,_=fixtures.ExtractionTests().fixture()
        return {'version':1,'planned_calls':1,'chunks':[chunk]}

    def test_offline_preview_never_instantiates_provider(self):
        with tempfile.TemporaryDirectory() as directory,patch('trippy.sources.pilot.make_provider') as provider:
            report=run_pilot(self.prepared(),{},Path(directory)/'preview.json')
            provider.assert_not_called()
            self.assertEqual(report['paid_calls'],0)
            self.assertEqual(report['cost_preview']['planned_calls'],1)

    def test_changed_prepared_payload_rejected(self):
        prepared=self.prepared()
        prepared['chunks'][0]['payload']['segments'][0]['text']='changed source'
        with self.assertRaises(ValueError):validate_pilot(prepared)

    def test_missing_budget_persists_blocked_report_without_calls(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'report.json'
            with self.assertRaises(BudgetError):run_pilot(self.prepared(),{},output,execute=True,
                budget_ledger=Path(directory)/'budget.sqlite')
            self.assertEqual(json.loads(output.read_text())['status'],'pilot_blocked_configuration')

    def test_configuration_error_stops_entire_batch_without_retry(self):
        chunk=self.prepared()['chunks'][0]
        second=copy.deepcopy(chunk);second['id']='second'
        calls=[]
        def provider(c):
            calls.append(c['id'])
            raise ProviderConfigurationError('HTTP 400 structured output not supported')
        with tempfile.TemporaryDirectory() as directory:
            results,errors=execute_chunks([chunk,second],provider,directory)
        self.assertFalse(results)
        self.assertEqual(len(calls),1)
        self.assertEqual([e['error_type'] for e in errors],
            ['ProviderConfigurationError','NotAttemptedProviderConfiguration'])

    def test_existing_output_rejected_before_provider_work(self):
        with tempfile.TemporaryDirectory() as directory,patch('trippy.sources.pilot.make_provider') as provider:
            output=Path(directory)/'report.json';output.write_text('existing')
            with self.assertRaises(ValueError):run_pilot(self.prepared(),{},output,execute=True)
            provider.assert_not_called()

    def test_request_ceiling_persists_across_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger=Path(directory)/'budget.sqlite'
            reserve_cost(ledger,Decimal('.01'),Decimal('1'),'USD',group='pilot',chunk_id='first',max_requests=1)
            with self.assertRaises(BudgetError):
                reserve_cost(ledger,Decimal('.01'),Decimal('1'),'USD',group='pilot',chunk_id='second',max_requests=1)

    def test_rejected_candidate_is_preserved_and_feedback_reaches_retry(self):
        chunk,valid=fixtures.ExtractionTests().fixture();calls=[]
        invalid=copy.deepcopy(valid);invalid['mentions'][0]['citations'][0]['quote']='invented'
        def provider(request):
            calls.append(request)
            return invalid if len(calls)==1 else valid
        with tempfile.TemporaryDirectory() as directory:
            results,errors=execute_chunks([chunk],provider,directory)
            self.assertFalse(errors);self.assertEqual(len(results),1)
            files=list((Path(directory)/'diagnostics').glob('*.json'))
            self.assertEqual(len(files),1)
            self.assertEqual(json.loads(files[0].read_text())['candidate_status'],'unvalidated_not_publishable')
            self.assertIn('validation_feedback',calls[1])


if __name__=='__main__':unittest.main()
