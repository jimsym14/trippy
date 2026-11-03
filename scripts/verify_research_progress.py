"""Exercise production research phase mapping without storage, UI or paid APIs."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / 'ios/Trippy/TrippyApp.swift').read_text()
start = source.index('private struct ResearchOperation:')
end = source.index('private struct Trip: Codable', start)
model = source[start:end].replace('private ', '')
program = 'import Foundation\n' + model + '''
precondition(ResearchOperation.planned.map(\\.step) == [1, 2, 3, 4, 5])
precondition(Set(ResearchOperation.planned.map(\\.symbol)).count == 5)
precondition(ResearchOperation.phase(serverStep: "searching_web", task: "discovery-food-1") == 2)
precondition(ResearchOperation.phase(serverStep: "synthesizing_patch", task: "discovery-food-1") == 2)
precondition(ResearchOperation.phase(serverStep: "searching_web", task: "selected-checks-1") == 3)
precondition(ResearchOperation.phase(serverStep: "synthesizing_patch", task: "selected-checks-1") == 3)
precondition(ResearchOperation.phase(serverStep: "composing", task: "source_based_draft") == 2)
precondition(ResearchOperation.phase(serverStep: "composing", task: "constraints_routes_costs") == 4)
precondition(ResearchOperation.phase(serverStep: "interrupted", task: "") == nil)
precondition(ResearchOperation.completedPhases([2, 3, 4, 5, 99, -1]) == Set([2, 3, 4]), "Local save cannot be certified by server progress")
print("PASS: five distinct phases, correct discovery/check/draft/final mapping, interrupted state and locally owned saving")
'''
folder = root / '.local/research-screen'
folder.mkdir(parents=True, exist_ok=True)
path = folder / 'ResearchProgressCheck.swift'
path.write_text(program)
binary = folder / 'research-progress-check'
subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(root / '.local/plan-redesign/modules'), str(path), '-o', str(binary)], check=True)
subprocess.run([str(binary)], check=True)
