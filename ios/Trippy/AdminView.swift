import SwiftUI
import Security

/// Admin rights inside the app: the same numbers and controls as the web dashboard (/admin).
/// Only reachable from an account the server says is admin, and every call is checked again
/// on the server with that account's session; hiding the screen is not the protection.
struct AdminView: View {
    let baseURL: String
    @ObservedObject private var account = AccountSession.shared
    @State private var summary: AdminSummary?
    @State private var error: String?
    @State private var loading = false
    @State private var limitFor: AdminSummary.Install?
    @State private var limitText = ""
    @State private var confirmBlock: AdminSummary.Install?

    var body: some View {
        Group {
            if account.isAdmin { content }
            else { ContentUnavailableView("Admin accounts only", systemImage: "lock.shield", description: Text("Sign in with an admin account to see usage and controls.")) }
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: account.isAdmin) { if account.isAdmin { await load() } }
        .refreshable { await load() }
        .alert("Daily Google limit", isPresented: Binding(get: { limitFor != nil }, set: { if !$0 { limitFor = nil } })) {
            TextField("Calls per day (empty = default)", text: $limitText).keyboardType(.numberPad)
            Button("Save") { if let install = limitFor { Task { await setLimit(install) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("For install \(limitFor?.short ?? "")") }
        .confirmationDialog("Block this install?", isPresented: Binding(get: { confirmBlock != nil }, set: { if !$0 { confirmBlock = nil } }),
                            titleVisibility: .visible) {
            Button("Block", role: .destructive) { if let install = confirmBlock { Task { await setBlocked(install, true) } } }
        } message: { Text("Its maps, plans and video requests will be refused until you unblock it.") }
    }

    @ViewBuilder private var content: some View {
        List {
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if let s = summary {
                Section {
                    LabeledContent("Installs", value: "\(s.totals.installs) · \(s.totals.active7d) active this week")
                    LabeledContent("Plans in 30 days", value: "\(s.totals.plans30d)")
                    LabeledContent("Calls per user per day", value: s.totals.avgCalls.map { String(format: "%.1f", $0) } ?? "—")
                    LabeledContent("Trips per user", value: s.totals.avgTrips.map { String(format: "%.1f", $0) } ?? "—")
                    LabeledContent("Storage per user", value: s.totals.avgStorage.map { String(format: "%.1f MB", $0) } ?? "—")
                } header: { Text("Overview") } footer: { Text("Build \(s.build) · stats \(s.storage)") }

                Section("Controls") {
                    Toggle("Planning on", isOn: Binding(get: { s.controls.paidResearch }, set: { value in Task { await update(["paid_research": value]) } }))
                    LabeledContent("Google per install / day", value: s.controls.defaultCap.map(String.init) ?? "No limit")
                    LabeledContent("Google for everyone / day", value: s.controls.globalCap.map(String.init) ?? "No limit")
                }

                Section("Google this month") {
                    ForEach(s.apis.filter { $0.group == "google" }) { api in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(api.label); Spacer(); Text("\(api.month)\(api.free.map { " / \($0)" } ?? "")").monospacedDigit().foregroundStyle(.secondary) }
                            if let free = api.free, free > 0 {
                                ProgressView(value: min(Double(api.month), Double(free)), total: Double(free))
                                    .tint(Double(api.month) / Double(free) >= 0.7 ? .orange : .green)
                            }
                        }
                    }
                }

                Section {
                    ForEach(s.installs.filter { $0.client != "unknown" }) { install in
                        let blocked = s.controls.blocked.contains(install.client)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(s.controls.notes[install.client] ?? install.short).font(.body.weight(.semibold))
                                if blocked { Text("Blocked").font(.caption.bold()).foregroundStyle(.red) }
                                if let cap = s.controls.caps[install.client] { Text("limit \(cap)").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text("\(install.trips.map(String.init) ?? "–") trips · \(install.saved.map(String.init) ?? "–") saved · \(install.storage.map { String(format: "%.1f MB", $0) } ?? "–") · \(install.plans) plans · \(install.google) Google")
                                .font(.caption).foregroundStyle(.secondary)
                            Text([install.device, install.appVersion].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .swipeActions(edge: .trailing) {
                            if blocked {
                                Button("Unblock") { Task { await setBlocked(install, false) } }.tint(.green)
                            } else {
                                Button("Block", role: .destructive) { confirmBlock = install }
                            }
                            Button("Limit") { limitText = s.controls.caps[install.client].map(String.init) ?? ""; limitFor = install }.tint(.orange)
                        }
                    }
                } header: { Text("Installs") } footer: { Text("Swipe an install to block it or set its own daily limit.") }
            } else if loading {
                Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) } }
            }
        }
    }

    // MARK: Network

    private func request(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw URLError(.badURL) }
        try await account.ensureFresh()
        var request = URLRequest(url: url, timeoutInterval: 25)
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { await account.refreshRole() }
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "Admin", code: status, userInfo: [NSLocalizedDescriptionKey: [
                "admin_token_required": "This account isn't an admin.", "too_many_attempts": "Too many tries. Try again in 10 minutes.",
                "admin_token_not_configured": "Admin isn't set up on the server yet.",
            ][code ?? ""] ?? "The server answered \(status)."])
        }
        return data
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { summary = try AdminSummary(data: try await request("/api/admin/summary")); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func update(_ changes: [String: Any]) async {
        do { _ = try await request("/api/admin/controls", body: changes); await load() }
        catch { self.error = error.localizedDescription }
    }

    private func setBlocked(_ install: AdminSummary.Install, _ block: Bool) async {
        guard let s = summary else { return }
        var list = Set(s.controls.blocked)
        if block { list.insert(install.client) } else { list.remove(install.client) }
        await update(["blocked": Array(list)])
    }

    private func setLimit(_ install: AdminSummary.Install) async {
        guard let s = summary else { return }
        var caps = s.controls.caps
        if let value = Int(limitText.trimmingCharacters(in: .whitespaces)) { caps[install.client] = max(0, value) } else { caps[install.client] = nil }
        await update(["client_caps": caps])
    }
}

/// The parts of /api/admin/summary the phone shows.
struct AdminSummary {
    struct Totals { var installs = 0, active7d = 0, plans30d = 0; var avgCalls: Double?, avgTrips: Double?, avgStorage: Double? }
    struct API: Identifiable { var id: String; var group: String; var label: String; var month: Int; var free: Int? }
    struct Install: Identifiable {
        var id: String { client }
        var client: String; var short: String; var trips: Int?; var saved: Int?; var storage: Double?
        var plans: Int; var google: Int; var device: String?; var appVersion: String?
    }
    struct Controls { var paidResearch = true; var defaultCap: Int?; var globalCap: Int?; var blocked: [String] = []; var caps: [String: Int] = [:]; var notes: [String: String] = [:] }
    var totals = Totals(); var apis: [API] = []; var installs: [Install] = []; var controls = Controls(); var build = ""; var storage = ""

    init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
        func dbl(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        let t = root["totals"] as? [String: Any] ?? [:]
        totals = Totals(installs: int(t["installs"]) ?? 0, active7d: int(t["active_7d"]) ?? 0, plans30d: int(t["plans_30d"]) ?? 0,
                        avgCalls: dbl(t["avg_calls_per_active_day"]), avgTrips: dbl(t["avg_trips"]), avgStorage: dbl(t["avg_storage_mb"]))
        apis = (root["apis"] as? [[String: Any]] ?? []).map {
            API(id: $0["metric"] as? String ?? UUID().uuidString, group: $0["group"] as? String ?? "", label: $0["label"] as? String ?? "",
                month: int($0["month"]) ?? 0, free: int($0["monthly_free"]))
        }
        installs = (root["installs"] as? [[String: Any]] ?? []).map {
            Install(client: $0["client"] as? String ?? "", short: $0["short"] as? String ?? "", trips: int($0["trips"]), saved: int($0["saved_places"]),
                    storage: dbl($0["storage_mb"]), plans: int($0["plans"]) ?? 0, google: int($0["google"]) ?? 0,
                    device: $0["device"] as? String, appVersion: $0["app_version"] as? String)
        }
        let c = root["controls"] as? [String: Any] ?? [:]
        controls = Controls(paidResearch: c["paid_research"] as? Bool ?? true, defaultCap: int(c["default_google_cap"]), globalCap: int(c["global_google_cap"]),
                            blocked: c["blocked"] as? [String] ?? [],
                            caps: (c["client_caps"] as? [String: Any] ?? [:]).compactMapValues { int($0) },
                            notes: c["notes"] as? [String: String] ?? [:])
        let h = root["health"] as? [String: Any] ?? [:]
        build = h["build"] as? String ?? ""; storage = h["storage"] as? String ?? ""
    }
}
