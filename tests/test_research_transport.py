"""Research readiness is inspectable without SDK clients or paid calls."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

import bridge_server
from trippy.planner.live_provider import configuration_issues, AzureResearchProvider
from trippy.sources.luna import BudgetError


def valid_config():
    # Synthetic rates only for validation; never dispatched to a provider.
    return dict(TRIPPY_ALLOW_PAID_RESEARCH='true', TRIPPY_AI_BUDGET_AMOUNT='1',
        TRIPPY_AI_BUDGET_CURRENCY='EUR', TRIPPY_WEB_RESERVATION_PER_CALL='.01',
        TRIPPY_LUNA_INPUT_PER_MILLION='1', TRIPPY_LUNA_OUTPUT_PER_MILLION='1',
        AZURE_AGENT_ENDPOINT='https://example.test/agent',
        AZURE_OPENAI_ENDPOINT='https://example.test/model',
        AZURE_OPENAI_API_KEY='synthetic-secret', AZURE_DEPLOYMENT_LUNA='synthetic-model')


class ResearchReadinessTests(unittest.TestCase):
    def test_invalid_values_return_only_names_and_never_initialize_clients(self):
        values=valid_config()
        self.assertEqual(configuration_issues(values), [])
        for name, value in [('TRIPPY_AI_BUDGET_AMOUNT','nan'),
                ('TRIPPY_LUNA_INPUT_PER_MILLION','0'),
                ('AZURE_AGENT_ENDPOINT','https://user:secret@example.test'),
                ('AZURE_DEPLOYMENT_LUNA','your-deployment')]:
            with self.subTest(name=name):
                invalid=values | {name:value}
                self.assertEqual(configuration_issues(invalid), [name])
                client=Mock(side_effect=AssertionError('must not initialize'))
                with self.assertRaises(BudgetError) as caught:
                    AzureResearchProvider(invalid, '/unused', agent_factory=client, model_factory=client)
                self.assertNotIn('synthetic-secret', str(caught.exception))
                self.assertNotIn(value, str(caught.exception))
                client.assert_not_called()

    def get(self, path):
        handler=object.__new__(bridge_server.RequestHandler)
        handler.path=path
        reply=[]
        handler.send_json=lambda status,payload:reply.append((status,payload))
        handler.do_GET()
        return reply[0]

    def test_preflight_reports_readiness_and_existing_job_remains_readable(self):
        with tempfile.TemporaryDirectory() as folder, \
                patch.object(bridge_server,'root',return_value=Path(folder)), \
                patch.object(bridge_server,'state',bridge_server.ResearchState()), \
                patch.object(bridge_server,'read_environment',return_value={}):
            job,_=bridge_server.begin_job({'destination':'Athens'})
            code,payload=self.get('/api/status')
            self.assertEqual(code,200)
            self.assertFalse(payload['research_ready'])
            self.assertIn('TRIPPY_ALLOW_PAID_RESEARCH',payload['configuration_issues'])
            self.assertFalse({'job_id','request_context','result'} & payload.keys())
            with patch.object(bridge_server,'read_environment',side_effect=AssertionError('job read must not check config')):
                self.assertEqual(self.get('/api/status?job_id='+job)[0],200)
            with patch.object(bridge_server,'read_environment',return_value=valid_config()):
                self.assertTrue(self.get('/api/status')[1]['research_ready'])
            # Simulate ephemeral files lost on redeploy, plus a fresh process.
            (bridge_server.job_directory(job)/'status.json').unlink()
            bridge_server.state=bridge_server.ResearchState()
            self.assertEqual(self.get('/api/status?job_id='+job),(404,{'error':'job_not_found'}))

    def test_environment_parse_failure_has_safe_diagnostic(self):
        with patch.object(bridge_server,'read_environment',side_effect=ValueError('private data')):
            self.assertEqual(self.get('/api/status')[1]['configuration_issues'],['ENVIRONMENT_CONFIGURATION'])

    def test_configuration_and_exhausted_budget_have_distinct_safe_errors(self):
        from trippy.planner.live_provider import ResearchConfigurationError
        for error,expected in [(ResearchConfigurationError('secret'),'research_configuration_required'),
                (BudgetError('secret'),'research_budget_unavailable')]:
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as folder, \
                    patch.object(bridge_server,'root',return_value=Path(folder)), \
                    patch.object(bridge_server,'state',bridge_server.ResearchState()), \
                    patch.object(bridge_server,'read_environment',return_value={}), \
                    patch.object(bridge_server,'execute_plan',side_effect=error):
                job,brief=bridge_server.begin_job({'destination':'Athens'})
                bridge_server.run_pipeline(brief,job,provider=object())
                result=bridge_server.read_job(job)
                self.assertEqual(result['error_code'],expected)
                self.assertFalse(result['is_running'])
                self.assertNotIn('secret',str(result))
