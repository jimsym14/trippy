"""Real-data planner gate: runs only when the local Barcelona catalog exists."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('planner_quality_gate', ROOT / 'scripts/planner_quality_gate.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


@unittest.skipUnless((ROOT / '.local/catalog.sqlite').is_file(), 'local catalog not available')
class PlannerQualityGateTests(unittest.TestCase):
    def test_fixed_barcelona_cases_pass_automatic_checks(self):
        categories = gate.categories_by_entity()
        for case in gate.CASES:
            with self.subTest(case=case['id']):
                result, again = gate.plan(case), gate.plan(case)
                checks, failures = gate.evaluate(case, result, again, categories)
                self.assertEqual(failures, [], checks)


if __name__ == '__main__':
    unittest.main()
