#!/usr/bin/env python3
"""Render the actual in-app Library components without compiling the full iOS app."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    source = (ROOT / 'ios/Trippy/TrippyApp.swift').read_text()
    model = source[source.index('enum LibrarySourceStatus:'):source.index('private enum TripDateLabel {')]
    identity = source.split('// MARK: - Identity design components', 1)[1].split('// MARK: - Identity editor', 1)[0]
    components = model + identity + source.split('// MARK: - Library design components', 1)[1]
    output = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/trippy-library-design').resolve()
    with tempfile.TemporaryDirectory(prefix='trippy-library-render-', dir='/tmp') as directory:
        directory = Path(directory)
        extracted = directory / 'LibraryDesign.swift'
        extracted.write_text('import SwiftUI\n' + components)
        binary = directory / 'render'
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(ROOT / '.local/library-design/modules'),
                        '-Xfrontend', '-disable-sandbox', str(extracted), str(ROOT / 'scripts/render_ios_library_design.swift'),
                        '-o', str(binary)], check=True)
        subprocess.run([str(binary), str(output), str(ROOT / 'ios/Trippy/Resources')], check=True)
    print(f'Library component previews: {output}')

if __name__ == '__main__':
    main()
