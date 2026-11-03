from decimal import Decimal
import json
from pathlib import Path
import tempfile
import unittest

from trippy.research.product_benchmark import token_cost, future_cost, historical_usage


class ProductBenchmarkTests(unittest.TestCase):
    def test_token_cost_uses_exact_decimal_and_rejects_invalid_rates(self):
        self.assertEqual(Decimal(token_cost(24000,8000,'0.30','1.00')),Decimal('0.0152'))
        for rate in ('NaN','Infinity','-1'):
            with self.subTest(rate=rate),self.assertRaises(ValueError):token_cost(1,1,rate,'1')

    def test_unknown_provider_price_is_not_treated_as_zero_total(self):
        case={'days':3,'assumed_new_evidence_jobs':1,'assumed_unique_place_details':20,
              'assumed_selected_route_edges':12}
        value=future_cost(case,('0.30','1.00'))
        self.assertEqual(Decimal(value['cold_model_estimate_usd']),Decimal('0.0208'))
        self.assertIsNone(value['real_connected_total_usd'])
        self.assertIsNone(value['travel_spending_eur'])
        self.assertEqual(Decimal(value['one_targeted_ai_patch_model_estimate_usd']),Decimal('0.0044'))

    def test_long_trip_synthesis_respects_output_ceiling_and_prices_repeated_input(self):
        case={'days':14,'assumed_new_evidence_jobs':3,'assumed_unique_place_details':60,
              'assumed_selected_route_edges':56}
        value=future_cost(case,('0.30','1.00'))
        self.assertEqual(value['optional_guide_synthesis_calls'],5)
        self.assertEqual(value['assumed_model_calls'],8)
        self.assertEqual(value['input_tokens'],152000)
        self.assertEqual(Decimal(value['cold_model_estimate_usd']),Decimal('0.0896'))
        self.assertEqual(Decimal(value['deterministic_guide_renderer_plus_gap_extraction_only_model_estimate_usd']),Decimal('0.0168'))

    def test_reasoning_tokens_are_not_billed_twice_and_duplicates_are_not_added(self):
        receipt={'response_id':'same','model':'luna','usage':{'prompt_tokens':1000,'completion_tokens':1000,
                 'completion_tokens_details':{'reasoning_tokens':200},'prompt_tokens_details':{'cached_tokens':100},
                 'latency_checkpoint':{'service_ttlt_ms':1000,'user_visible_ttft_ms':100}}}
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'usage.jsonl';path.write_text(json.dumps(receipt)+'\n'+json.dumps(receipt)+'\n')
            value=historical_usage(path,('0.30','1.00'))
            self.assertEqual(value['unique_response_receipts'],1)
            self.assertEqual(value['duplicates'],1)
            self.assertEqual(value['output_tokens'],1000)
            self.assertEqual(Decimal(value['estimate_using_current_project_rates_usd']),Decimal('0.0013'))

    def test_conflicting_replayed_usage_is_rejected(self):
        one={'response_id':'same','usage':{'prompt_tokens':1,'completion_tokens':1}}
        two={**one,'usage':{'prompt_tokens':2,'completion_tokens':1}}
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'usage.jsonl';path.write_text(json.dumps(one)+'\n'+json.dumps(two)+'\n')
            with self.assertRaisesRegex(ValueError,'Conflicting'):historical_usage(path,('0.30','1.00'))
