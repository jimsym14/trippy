#!/usr/bin/env python3
"""Render the production planning controls in light/dark composition galleries."""
from pathlib import Path
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'ios/Trippy/TrippyApp.swift').read_text()
components = source.split('// MARK: - Planning design components', 1)[1].split('// MARK: - Library design components', 1)[0]
flow = source[source.index('private struct PillFlowLayout:'):source.index('private struct TripCalendarSelection:')]
output = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/trippy-planning-design').resolve()
with tempfile.TemporaryDirectory(prefix='trippy-planning-render-', dir='/tmp') as folder:
    folder = Path(folder)
    extracted = folder / 'PlanningDesign.swift'
    extracted.write_text('import SwiftUI\n' + flow + components + (ROOT / 'scripts/render_ios_planning_design.swift').read_text())
    binary = folder / 'render'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(ROOT / '.local/library-design/modules'), '-Xfrontend', '-disable-sandbox', str(extracted), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(output), str(ROOT / 'ios/Trippy/Resources')], check=True)
print(f'Planning component previews: {output}')
