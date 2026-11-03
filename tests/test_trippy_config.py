import json
import tempfile
import unittest
from pathlib import Path

from trippy_config import DEFAULTS, audit_configuration, read_environment


class ConfigurationTests(unittest.TestCase):
    def test_shell_overrides_file_without_executing_or_expanding_values(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            path.write_text('export AZURE_OPENAI_API_KEY="$(do-not-run)"\nTRIPPY_ENVIRONMENT=local # local value\n')
            values = read_environment(path, {"TRIPPY_ENVIRONMENT": "test"})
        self.assertEqual(values["AZURE_OPENAI_API_KEY"], "$(do-not-run)")
        self.assertEqual(values["TRIPPY_ENVIRONMENT"], "test")

    def test_validation_never_discloses_secret_or_connection_credentials(self):
        secret = "SENSITIVE_DO_NOT_DISPLAY"
        values = {**DEFAULTS, "AZURE_OPENAI_API_KEY": secret,
                  "SUPABASE_URL": f"https://user:{secret}@example.org/",
                  "DATABASE_URL": f"postgresql://user:{secret}@example.org:invalid/postgres"}
        report = audit_configuration(values, "connected")
        self.assertEqual(report["status"], "invalid")
        self.assertNotIn(secret, json.dumps(report))
        self.assertFalse(any("example.org" in error for error in report["errors"]))

    def test_offline_does_not_require_credentials_or_enable_paid_research(self):
        report = audit_configuration(DEFAULTS)
        self.assertEqual(report["status"], "valid")
        self.assertFalse(report["paid_research_requested"])
        self.assertEqual(report["live_verification"], "not_performed")

    def test_connected_requires_project_database_and_public_auth_key(self):
        values = {**DEFAULTS, "SUPABASE_URL": "https://example.supabase.co",
                  "DATABASE_URL": "postgresql://user:password@db.example.org/postgres"}
        self.assertEqual(audit_configuration(values, "connected")["status"], "invalid")
        values["SUPABASE_PUBLISHABLE_KEY"] = "sb_publishable_synthetic"
        self.assertEqual(audit_configuration(values, "connected")["status"], "valid")

    def test_paid_request_requires_valid_currency_and_finite_positive_cap(self):
        for cap in ("", "NaN", "Infinity", "0", "-1"):
            values = {**DEFAULTS, "TRIPPY_ALLOW_PAID_RESEARCH": "true",
                      "TRIPPY_AI_BUDGET_AMOUNT": cap, "TRIPPY_AI_BUDGET_CURRENCY": "EUR"}
            with self.subTest(cap=cap):
                self.assertEqual(audit_configuration(values)["status"], "invalid")
        values["TRIPPY_AI_BUDGET_AMOUNT"] = "2.50"
        self.assertEqual(audit_configuration(values)["status"], "valid")
        values["TRIPPY_AI_BUDGET_CURRENCY"] = "unknown"
        self.assertEqual(audit_configuration(values)["status"], "invalid")

    def test_malformed_dotenv_reports_line_number_without_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            path.write_text('SECRET="never-print-this\n')
            with self.assertRaisesRegex(ValueError, "line 1") as raised:
                read_environment(path, {})
        self.assertNotIn("never-print-this", str(raised.exception))
