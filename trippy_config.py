"""Offline configuration audit for the staged backend. Never connects or calls AI.

Reports field presence and safe validation errors, never credential values.
Existing bridge/client paths are intentionally unchanged in Stage 0.
"""

import argparse
import json
import os
import re
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import urlsplit


FIELDS = (
    "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY",
    "DATABASE_URL", "MIGRATION_DATABASE_URL", "SUPABASE_SECRET_KEY",
    "AZURE_OPENAI_API_KEY", "AZURE_AGENT_ENDPOINT", "AZURE_OPENAI_ENDPOINT",
    "AZURE_OPENAI_API_VERSION", "AZURE_DEPLOYMENT_LUNA", "TRIPPY_BRIDGE_TOKEN",
    "TRIPPY_ENVIRONMENT", "TRIPPY_ALLOW_PAID_RESEARCH", "TRIPPY_AI_BUDGET_AMOUNT",
    "TRIPPY_AI_BUDGET_CURRENCY", "TRIPPY_DB_POOL_SIZE", "TRIPPY_WORKER_CONCURRENCY",
)
DEFAULTS = {
    "TRIPPY_ENVIRONMENT": "local", "TRIPPY_ALLOW_PAID_RESEARCH": "false",
    "TRIPPY_DB_POOL_SIZE": "3", "TRIPPY_WORKER_CONCURRENCY": "1",
}


def read_environment(path=None, environ=None):
    """Minimal dotenv reader: no expansion, evaluation, logging or env mutation.

    Real environment settings override the local file, including explicit blanks.
    Parsing errors refer only to a line number, never its contents.
    """
    values = dict(DEFAULTS)
    if path is not None and Path(path).is_file():
        for line_number, raw in enumerate(Path(path).read_text().splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            key, separator, value = line.partition("=")
            key = key.strip()
            if not separator or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
                raise ValueError(f"Invalid environment assignment at line {line_number}")
            value = value.strip()
            if value.startswith(("'", '"')):
                if len(value) < 2 or value[-1] != value[0]:
                    raise ValueError(f"Unclosed environment quote at line {line_number}")
                value = value[1:-1]
            else:
                value = re.split(r"\s+#", value, maxsplit=1)[0].rstrip()
            values[key] = value
    values.update(os.environ if environ is None else environ)
    return values


def configured(value):
    text = str(value or "").strip()
    return bool(text) and not any(token in text.lower() for token in (
        "replace_with", "your-resource", "your-project", "your-deployment",
        "generate_a_long_random_token", "your-password", "<password>",
    ))


def valid_url(value, schemes, allow_credentials=False):
    try:
        parts = urlsplit(value)
        port = parts.port  # Reject malformed ports without exposing the input.
        if port is not None and not 1 <= port <= 65535:
            return False
        return bool(
            parts.scheme in schemes and parts.hostname
            and not any(c.isspace() for c in value)
            and not parts.fragment
            and (allow_credentials or not (parts.username or parts.password or parts.query))
        )
    except (ValueError, TypeError):
        return False


def audit_configuration(values, mode="offline"):
    if mode not in {"offline", "connected", "research"}:
        raise ValueError("Unsupported configuration audit mode")
    presence = {key: configured(values.get(key)) for key in FIELDS}
    errors = []
    requirements = {
        "offline": (),
        "connected": ("SUPABASE_URL", "DATABASE_URL"),
        "research": ("AZURE_OPENAI_API_KEY", "AZURE_AGENT_ENDPOINT",
                     "AZURE_OPENAI_ENDPOINT", "AZURE_DEPLOYMENT_LUNA"),
    }
    for field in requirements[mode]:
        if not presence[field]:
            errors.append(f"{field}: required for {mode} mode")
    if mode == "connected" and not (presence["SUPABASE_PUBLISHABLE_KEY"] or presence["SUPABASE_ANON_KEY"]):
        errors.append("SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY: required for the auth flow")
    for field in ("SUPABASE_URL", "AZURE_AGENT_ENDPOINT", "AZURE_OPENAI_ENDPOINT"):
        if presence[field] and not valid_url(values[field], {"https"}):
            errors.append(f"{field}: expected an HTTPS URL without embedded credentials or query")
    for field in ("DATABASE_URL", "MIGRATION_DATABASE_URL"):
        if presence[field] and not valid_url(values[field], {"postgresql", "postgresql+psycopg"}, True):
            errors.append(f"{field}: expected a valid PostgreSQL connection URL")
    for field, maximum in (("TRIPPY_DB_POOL_SIZE", 20), ("TRIPPY_WORKER_CONCURRENCY", 8)):
        try:
            number = int(values.get(field, DEFAULTS[field]))
            if not 1 <= number <= maximum:
                raise ValueError
        except (ValueError, TypeError):
            errors.append(f"{field}: expected a bounded positive integer")
    if values.get("TRIPPY_ENVIRONMENT", "local") not in {"local", "test", "production"}:
        errors.append("TRIPPY_ENVIRONMENT: expected local, test or production")
    paid = values.get("TRIPPY_ALLOW_PAID_RESEARCH", "false").strip().lower()
    if paid not in {"true", "false"}:
        errors.append("TRIPPY_ALLOW_PAID_RESEARCH: expected true or false")
    if paid == "true":
        try:
            amount = Decimal(values.get("TRIPPY_AI_BUDGET_AMOUNT", ""))
            if not amount.is_finite() or amount <= 0:
                raise ValueError
        except (ValueError, TypeError, InvalidOperation):
            errors.append("TRIPPY_AI_BUDGET_AMOUNT: a finite positive cap is required")
        if values.get("TRIPPY_AI_BUDGET_CURRENCY") not in {"EUR", "USD"}:
            errors.append("TRIPPY_AI_BUDGET_CURRENCY: expected EUR or USD")
    return {
        "mode": mode, "status": "invalid" if errors else "valid",
        "configured_fields": presence, "errors": errors,
        "paid_research_requested": paid == "true",
        "live_verification": "not_performed",
        "note": "Configuration audit only; existing research clients do not enforce this budget yet.",
    }


def main():
    parser = argparse.ArgumentParser(description="Validate configuration offline without exposing secrets")
    parser.add_argument("--env-file", type=Path, default=Path(__file__).with_name(".env"))
    parser.add_argument("--mode", choices=("offline", "connected", "research"), default="offline")
    args = parser.parse_args()
    try:
        report = audit_configuration(read_environment(args.env_file), args.mode)
    except ValueError as exc:
        report = {"status": "invalid", "errors": [str(exc)], "live_verification": "not_performed"}
    except OSError:
        report = {"status": "invalid", "errors": ["Cannot read configuration file"], "live_verification": "not_performed"}
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "valid" else 1


if __name__ == "__main__":
    raise SystemExit(main())
