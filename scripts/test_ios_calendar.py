#!/usr/bin/env python3
"""Run regression checks against the iOS calendar's actual selection model.

Requires Xcode's Swift compiler; does not require a Simulator or network access.
"""
from pathlib import Path
import re
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "ios/Trippy/TrippyApp.swift"
SWIFT_CHECKS = r"""
func calendar(_ zone: String) -> Calendar {
 var c = Calendar(identifier: .gregorian)
 c.timeZone = TimeZone(identifier: zone)!
 return c
}
func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
 calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}
for zone in ["Europe/Athens", "Europe/Madrid", "America/New_York", "Pacific/Auckland"] {
 let c = calendar(zone)
 for (a, b, expected) in [( (2026,3,27), (2026,3,31), 4), ((2026,10,23),(2026,10,27),4), ((2026,12,30),(2027,1,2),3), ((2028,2,28),(2028,3,1),2), ((2026,11,2),(2026,11,2),0)] {
  let start = date(a.0,a.1,a.2,calendar:c), end = date(b.0,b.1,b.2,calendar:c)
  let range = TripCalendarSelection(start:start,end:end)
  precondition(range.nightCount(calendar:c) == expected, "Incorrect night count: \(zone)")
 }
 var range = TripCalendarSelection()
 let a = date(2026,11,2,calendar:c), b = date(2026,11,8,calendar:c)
 range = range.selecting(a,calendar:c)
 precondition(range.start == a && range.end == nil)
 let unchangedArrival = range
 range = range.selecting(b,calendar:c)
 precondition(unchangedArrival.start == a && unchangedArrival.end == nil, "Selection must be a value copy")
 precondition(range.start == a && range.end == b && range.nightCount(calendar:c) == 6)
 range = range.selecting(a,calendar:c)
 precondition(range.start == a && range.end == nil)
 range = range.selecting(a,calendar:c)
 precondition(range.end == nil)
 let laterOnArrivalDay = c.date(byAdding: .hour, value: 3, to: a)!
 range = range.selecting(laterOnArrivalDay,calendar:c)
 precondition(range.start == laterOnArrivalDay && range.end == nil, "Same civil day must restart even with a different time")
 range = range.selecting(date(2026,11,1,calendar:c),calendar:c)
 precondition(range.start == date(2026,11,1,calendar:c) && range.end == nil)
}
print("PASS: selection, restart, same/earlier dates, DST, year boundary and leap day in 4 time zones")
"""


def main():
    source = SOURCE.read_text()
    match = re.search(r"private struct TripCalendarSelection[^\n{]*\{.*?^\}", source, re.S | re.M)
    if match is None:
        raise RuntimeError("TripCalendarSelection was not found")
    model = match.group().replace("private struct", "struct", 1)
    scratch = PROJECT / ".local"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="calendar-regression-", dir=scratch) as folder:
        folder = Path(folder)
        swift = folder / "main.swift"
        executable = folder / "calendar-regression"
        swift.write_text("import Foundation\n" + model + "\n" + SWIFT_CHECKS)
        subprocess.run(["swiftc", "-module-cache-path", str(folder / "modules"), str(swift), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
