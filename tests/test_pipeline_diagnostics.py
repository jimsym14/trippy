"""Offline regressions for empty delivery and safe provider diagnostics."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import bridge_server
from trippy.planner.diagnostics import ResearchProviderError, failure_details
from trippy.planner.live_provider import AzureResearchProvider
from trippy.planner.pipeline import run
from tests.test_trip_pipeline import BRIEF, EMPTY_DATASET, RecordedProvider
from tests.test_research_transport import valid_config


class PipelineDiagnosticsTests(unittest.TestCase):
    def test_first_web_failure_does_not_deliver_an_empty_plan(self):
        provider=RecordedProvider()
        provider.research=Mock(side_effect=ResearchProviderError('web_conversation','provider_request_rejected',http_status=404))
        with tempfile.TemporaryDirectory() as folder:
            events=[]
            result=run(BRIEF,provider=provider,directory=folder,root=folder,dataset=EMPTY_DATASET,
                progress=lambda step,detail:events.append((step,detail)))
            self.assertEqual(result['delivery_status'],'failed')
            self.assertEqual(result['pipeline_report']['completed_research_phases'],[])
            self.assertEqual(result['pipeline_report']['phase_states'],{'2':'failed','3':'skipped','4':'empty'})
            failure=result['pipeline_report']['failed_stages'][0]
            self.assertEqual((failure['stage'],failure['http_status']),('web_conversation',404))
            provider.research.assert_called_once()
            self.assertEqual(provider.calls,[], 'No normalizer or subsequent paid work after failure')
            self.assertNotIn(('phase_completed','composition'),events)
            self.assertTrue(any(step=='task_failed' for step,_ in events))

    def test_normalization_failure_is_distinct_from_web_failure(self):
        provider=RecordedProvider()
        provider.normalize=lambda *_: {'invalid':'private fixture text'}
        with tempfile.TemporaryDirectory() as folder:
            result=run(BRIEF,provider=provider,directory=folder,root=folder,dataset=EMPTY_DATASET)
            failure=result['pipeline_report']['failed_stages'][0]
            self.assertEqual(failure['stage'],'luna_normalization')
            self.assertEqual(failure['code'],'research_validation_failed')
            self.assertNotIn('private fixture text',json.dumps(failure))

    def test_web_http_error_survives_sanitization_without_error_body(self):
        class HTTPError(Exception):
            status_code=400
            body={'error':{'param':'max_tool_calls','message':'private provider message'}}
        for stage in ['web_conversation','web_response']:
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as folder:
                error=HTTPError('api-key=private-secret, prompt=private text')
                create=Mock(return_value=SimpleNamespace(id='synthetic'))
                respond=Mock(side_effect=error)
                if stage=='web_conversation': create.side_effect=error
                client=SimpleNamespace(conversations=SimpleNamespace(create=create),responses=SimpleNamespace(create=respond))
                with patch('trippy.planner.live_provider.make_provider',return_value=Mock()):
                    provider=AzureResearchProvider(valid_config(),Path(folder)/'ledger.sqlite',agent_factory=Mock(return_value=client))
                with self.assertRaises(ResearchProviderError) as caught:
                    provider.research('private prompt','discovery-food-1')
                details=failure_details(caught.exception,task='discovery-food-1',stage='web_research')
                self.assertEqual(details['stage'],stage)
                self.assertEqual(details['http_status'],400)
                self.assertEqual(details['parameter'],'max_tool_calls')
                self.assertNotIn('private',json.dumps(details))
                self.assertNotIn('private',str(caught.exception))
                create.assert_called_once()
                self.assertEqual(respond.call_count,0 if stage=='web_conversation' else 1)

    def test_incomplete_response_reports_token_limit_without_normalization(self):
        response=SimpleNamespace(status='incomplete',incomplete_details=SimpleNamespace(reason='max_output_tokens'),
            model_dump=lambda: {'status':'incomplete','private':'retained locally'})
        client=SimpleNamespace(conversations=SimpleNamespace(create=lambda:SimpleNamespace(id='synthetic')),
            responses=SimpleNamespace(create=lambda **kwargs:response))
        with tempfile.TemporaryDirectory() as folder, patch('trippy.planner.live_provider.make_provider',return_value=Mock()):
            provider=AzureResearchProvider(valid_config(),Path(folder)/'ledger.sqlite',agent_factory=Mock(return_value=client))
            with self.assertRaises(ResearchProviderError) as caught: provider.research('private','discovery-food-1')
            details=failure_details(caught.exception,task='discovery-food-1',stage='web_research')
            self.assertEqual(details['reason'],'max_output_tokens')
            self.assertNotIn('private',json.dumps(details))

    def test_bridge_retains_support_diagnostics_but_reports_error(self):
        provider=RecordedProvider()
        provider.research=Mock(side_effect=TimeoutError('private prompt'))
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(bridge_server,'root',return_value=Path(folder)), \
                patch.object(bridge_server,'state',bridge_server.ResearchState()), \
                patch.object(bridge_server,'read_environment',return_value={}):
            job,brief=bridge_server.begin_job(BRIEF | {'custom_instructions':'private instructions'})
            with self.assertLogs('trippy.research',level='INFO') as logs:
                bridge_server.run_pipeline(brief,job,provider=provider)
            status=bridge_server.read_job(job)
            self.assertEqual(status['step'],'error')
            self.assertFalse(status['is_running'])
            self.assertEqual(status['diagnostics']['place_count'],0)
            self.assertEqual(status['diagnostics']['last_failure']['code'],'provider_connection_failed')
            self.assertEqual(status['result']['pipeline_report']['support_id'],status['support_id'])
            self.assertNotIn('private','\n'.join(logs.output))
            self.assertNotIn(job,'\n'.join(logs.output), 'Support logs do not leak job capability')
