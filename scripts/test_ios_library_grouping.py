#!/usr/bin/env python3
"""Check the production city grouping and Library palette contrast on the host."""
from pathlib import Path
import re
import math
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'ios/Trippy/TrippyApp.swift'
CHECKS = r'''
struct Item { let id: String; let city: String }
let items = [Item(id: "a", city: "Barcelona, Spain"), Item(id: "b", city: " BARCELÓNA "),
             Item(id: "c", city: "Rome, IT"), Item(id: "d", city: ""), Item(id: "e", city: "   ")]
let groups = LibraryGrouping.cities(items, city: { $0.city })
precondition(groups.count == 3)
precondition(groups.first { $0.title == "Barcelona" }!.items.map(\.id) == ["a", "b"])
precondition(groups.first { $0.title == "Unassigned" }!.items.map(\.id) == ["d", "e"])
precondition(Set(groups.flatMap { $0.items.map(\.id) }) == Set(items.map(\.id)))
precondition(groups.flatMap { $0.items }.count == items.count, "Grouping cannot duplicate or lose records")
precondition(LibraryGrouping.cities([Item](), city: { $0.city }).isEmpty)
precondition(LibraryGrouping.cities(Array(items.reversed()), city: { $0.city }).map(\.id) == groups.map(\.id), "Group identities must be stable")
precondition(LibraryGrouping.cityTitle("New York, NY, USA") == "New York")
print("PASS: Library grouping, normalized cities, missing cities, stable identities and record preservation")
'''

def rgb(hex_value):
    return [int(hex_value[i:i+2], 16) / 255 for i in (0, 2, 4)]

def luminance(value):
    linear = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in value]
    return sum(x * weight for x, weight in zip(linear, (0.2126, 0.7152, 0.0722)))

def contrast(foreground, background):
    a, b = sorted((luminance(foreground), luminance(background)))
    return (b + 0.05) / (a + 0.05)

def main():
    source = SOURCE.read_text().split('// MARK: - Library design components', 1)[1]
    model = source[source.index('struct LibraryCityGroup'):source.index('struct LibraryRaisedSurface')]
    with tempfile.TemporaryDirectory(prefix='trippy-library-checks-', dir='/tmp') as folder:
        folder = Path(folder)
        swift = folder / 'checks.swift'
        swift.write_text('import Foundation\n' + model + CHECKS)
        binary = folder / 'checks'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(ROOT / '.local/library-design/modules'), str(swift), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
    dark_tones = re.findall(r'case \(\.\w+, \.dark\): hex = "([A-F0-9]+)"', source)
    light_tones = re.findall(r'case \(\.\w+, _\): hex = "([A-F0-9]+)"', source)
    assert len(dark_tones) == len(light_tones) == 4
    minimum = 100
    for dark, tones in ((True, dark_tones), (False, light_tones)):
        values = {}
        for role in ('canvas', 'surface', 'ink', 'secondary'):
            pattern = rf'static func {role}.*?"([A-F0-9]+)" : "([A-F0-9]+)"'
            pair = re.search(pattern, source).groups()
            values[role] = rgb(pair[0 if dark else 1])
        for background in (values['canvas'], values['surface']):
            for foreground in (values['ink'], values['secondary'], *map(rgb, tones)):
                ratio = contrast(foreground, background)
                assert ratio >= 4.5, f'Text contrast {ratio:.2f}: {dark=}'
                minimum = min(minimum, ratio)
            for tone in map(rgb, tones):
                opacity = 0.10 if dark else 0.07
                badge_background = [opacity * t + (1-opacity) * b for t, b in zip(tone, background)]
                ratio = contrast(tone, badge_background)
                assert ratio >= 4.5, f'Badge text contrast {ratio:.2f}: {dark=}'
                minimum = min(minimum, ratio)
    # Bound text contrast even at the deepest pigment and extreme grain pixels.
    for dark, tones in ((True, dark_tones), (False, light_tones)):
        pigment_alpha = 0.398 if dark else 0.456
        grain_alpha = 0.29 if dark else 0.24
        for tone in map(rgb, tones):
            background = [pigment_alpha * t + (1-pigment_alpha) * (0 if dark else 1) for t in tone]
            background = [(1-grain_alpha) * b + grain_alpha * (math.sqrt(b) if dark else b*b) for b in background]
            for foreground in map(rgb, ('EAF0E8', 'DCE6DC') if dark else ('20352A', '2E4035')):
                ratio = contrast(foreground, background)
                assert ratio >= 4.5, f'Grainy gradient text contrast {ratio:.2f}: {dark=}'
                minimum = min(minimum, ratio)
    print(f'PASS: Library light/dark text and badge contrast (minimum {minimum:.2f}:1)')
    planning = SOURCE.read_text().split('// MARK: - Planning design components', 1)[1].split('// MARK: - Library design components', 1)[0]
    roles = {role: pair for role, *pair in re.findall(r'var (\w+): Color \{ color\("([A-F0-9]+)", "([A-F0-9]+)"\)', planning)}
    planning_minimum = 100
    for index in (0, 1):
        values = {role: rgb(pair[index]) for role, pair in roles.items()}
        pairs = [(foreground, background) for foreground in ('ink', 'secondaryInk', 'brand') for background in ('canvas', 'surface', 'raised')]
        pairs += [('brand', 'selectedFill'), ('inverseInk', 'brand')]
        for foreground, background in pairs:
            ratio = contrast(values[foreground], values[background])
            assert ratio >= 4.5, f'Planning text contrast {ratio:.2f}: {index=} {foreground=} {background=}'
            planning_minimum = min(planning_minimum, ratio)
    print(f'PASS: Planning light/dark text, selected pills and primary actions (minimum {planning_minimum:.2f}:1)')

if __name__ == '__main__':
    main()
