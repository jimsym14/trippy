"""Exercise native error/retry recovery with injected responses; no network or paid calls."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / 'ios/Trippy/TrippyApp.swift').read_text()
def section(start, end):
    return source[source.index(start):source.index(end, source.index(start))].replace('private ', '')

models = '\n'.join([
    'import Foundation\nimport MapKit',
    section('private struct TripBrief:', 'private struct DestinationHoliday:'),
    section('private enum ResearchRequestStage:', 'private struct Trip: Codable'),
    section('private struct Trip: Codable', 'private enum TripStorage'),
    section('private extension String {', 'private enum PersonalPlaceStorage'),
])
checks = r'''
@main struct Checks {
    static func main() async throws {
        let url = URL(string: "https://example.test/api/status?job_id=synthetic")!
        func response(_ code: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
        }
        func expect(_ failure: ResearchRequestError, _ action: () throws -> Void) {
            do { try action(); fatalError("expected failure") }
            catch { precondition(error as? ResearchRequestError == failure) }
        }
        expect(.missingJob) { _ = try ResearchTransport.checkedJSON(Data(), response: response(404), stage: .status) }
        expect(.httpStatus(404, .preflight)) { _ = try ResearchTransport.checkedJSON(Data(), response: response(404), stage: .preflight) }
        expect(.invalidResponse(.status)) { _ = try ResearchTransport.checkedJSON(Data("<html>".utf8), response: response(200), stage: .status) }
        _ = try ResearchTransport.checkedJSON(Data("{}".utf8), response: response(202), stage: .start)
        let config = Data(#"{"research_ready":false,"configuration_issues":["TRIPPY_AI_BUDGET_AMOUNT","secret=https://private.test"]}"#.utf8)
        expect(.configurationUnavailable(["TRIPPY_AI_BUDGET_AMOUNT"])) {
            _ = try ResearchTransport.checkedJSON(config, response: response(200), stage: .preflight)
        }
        _ = try ResearchTransport.checkedJSON(config, response: response(200), stage: .preflight, checkResearchReadiness: false)
        precondition(!ResearchTransport.shouldRetryStatus(ResearchRequestError.missingJob))
        precondition(!ResearchTransport.shouldRetryStatus(ResearchRequestError.httpStatus(502, .start)))
        var attempts = 0
        var delays: [Double] = []
        let result = try await ResearchTransport.status(url: url, transport: { request in
            precondition(request.httpMethod == "GET" && request.timeoutInterval == 60)
            attempts += 1
            if attempts == 1 { throw URLError(.timedOut) }
            return (Data("{\"step\":\"completed\"}".utf8), response(attempts == 2 ? 502 : 200))
        }, pause: { delays.append($0) })
        precondition(attempts == 3 && delays == [2,4] && result["step"] as? String == "completed")
        attempts = 0; delays = []
        do {
            _ = try await ResearchTransport.status(url: url, transport: { _ in
                attempts += 1; return (Data(), response(503))
            }, pause: { delays.append($0) })
            fatalError("expected bounded failure")
        } catch { precondition(error as? ResearchRequestError == .httpStatus(503, .status)) }
        precondition(attempts == 4 && delays == [2,4,8])
        attempts = 0
        do {
            _ = try await ResearchTransport.status(url: url, transport: { _ in
                attempts += 1; return (Data(), response(404))
            }, pause: { _ in fatalError("must not retry missing job") })
            fatalError("expected missing job")
        } catch { precondition(error as? ResearchRequestError == .missingJob) }
        precondition(attempts == 1)
        let original = Data(#"{"id":"12345678-1234-1234-1234-123456789ABC","updatedAt":100,"brief":{"destination":"Athens","notes":"keep"},"research":"opaque research","researchJobID":"old","researchBridgeURL":"https://example.test","scheduleEditsByItemID":{"p1":{"time":"10:00"}},"checklistDoneIDs":["task1"]}"#.utf8)
        var trip = try JSONDecoder().decode(Trip.self, from: original)
        let before = trip
        trip.forgetResearchJob(matching: "newer")
        precondition(trip == before, "stale callback must not clear a newer job")
        trip.forgetResearchJob(matching: "old")
        var expected = before; expected.researchJobID = nil; expected.researchBridgeURL = nil
        precondition(trip == expected, "recovery preserves research and every user field")
        let restored = try JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(trip))
        precondition(restored == expected)
        precondition(!ResearchDiagnostics.hasPlaces(["places": []]))
        precondition(ResearchDiagnostics.hasPlaces(["places": [["id": "p1"]]]))
        let diagnostic = ResearchDiagnostics.summary(["pipeline_report": ["places_researched": 0,
            "failed_stages": [["task": "discovery-food-1", "stage": "web_response", "http_status": 400,
                "code": "provider_request_rejected", "error_type": "secret=https://private.test"]]]])!
        precondition(diagnostic.contains("HTTP: 400") && diagnostic.contains("web_response"))
        precondition(!diagnostic.contains("secret") && !diagnostic.contains("private.test"))
        let phases = ResearchDiagnostics.phaseStates(["pipeline_report": ["phase_states": ["2": "failed", "3": "skipped", "4": "empty", "5": "completed"]]])
        precondition(phases == [2: "failed", 3: "skipped", 4: "empty"])
        precondition(ResearchDiagnostics.phaseDetail(phases[3])!.contains("Παραλείφθηκε"))
        print("PASS: missing job, readiness, sanitized diagnostics, bounded GET retries, no POST retries, storage recovery")
    }
}
'''
folder = root / '.local/research-screen'
folder.mkdir(parents=True, exist_ok=True)
path = folder / 'ResearchTransportCheck.swift'
path.write_text(models + checks)
binary = folder / 'research-transport-check'
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root / '.local/plan-redesign/modules'), str(path), '-o', str(binary)], check=True)
subprocess.run([str(binary)], check=True)
