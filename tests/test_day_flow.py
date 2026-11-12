"""The phone's day re-flow (ios/Trippy/DayFlow.swift), compiled and run with swiftc.

Fixed and booked stops keep their time, the rest flows around them with a reason, the departure
day stops in time for the flight, and a shorter walking order is suggested. No network, no model.
"""
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.skipif(shutil.which("swiftc") is None, reason="swiftc not available")
def test_day_flow(tmp_path):
    binary = tmp_path / "day_flow_check"
    sources = [ROOT / "ios/Trippy/DayFlow.swift", ROOT / "tests/ios/day_flow_check.swift"]
    build = subprocess.run(["swiftc", "-O", "-parse-as-library", "-o", str(binary), *map(str, sources)], capture_output=True, text=True, timeout=600)
    assert build.returncode == 0, build.stderr
    run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    assert run.returncode == 0, run.stdout + run.stderr
    assert "all checks passed" in run.stdout
