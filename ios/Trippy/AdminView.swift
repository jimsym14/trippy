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

                if let planner = s.planner {
                    PlannerAdminSection(planner: planner, baseURL: baseURL) { config in await update(["planner": config]) }
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

                if let cap = s.capacity {
                    Section {
                        LabeledContent("Active users on free calls", value: "\(cap.freeUsers)")
                        LabeledContent("One plan / one video", value: String(format: "$%.2f / $%.2f", cap.planUSD, cap.videoUSD))
                        ForEach(cap.scenarios) { row in
                            LabeledContent("\(row.users) active user\(row.users == 1 ? "" : "s")",
                                           value: String(format: "$%.0f a month · $%.2f each", row.total, row.perUser))
                        }
                    } header: { Text("Costs") } footer: { Text("Tightest free limit: \(cap.tightest). Estimates; full analysis in docs/BUSINESS_AND_LIMITS.md.") }

                    Section("Bottlenecks") {
                        ForEach(cap.bottlenecks) { item in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Free: \(item.freeLimit)")
                                    Text("One user: \(item.oneUser)")
                                    Text("Many users: \(item.scale)")
                                    Text("Upgrade: \(item.upgrade)\(item.code ? " (needs code)" : " (no code)")")
                                    Text("Paid: \(item.paid)").foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            } label: {
                                HStack {
                                    Text(item.service).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(item.severityLabel).font(.caption.bold())
                                        .foregroundStyle(item.severity == "now" ? .red : item.severity == "soon" ? .orange : .secondary)
                                }
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
    struct Capacity {
        struct Scenario: Identifiable { var id: Int { users }; var users: Int; var total: Double; var perUser: Double }
        struct Bottleneck: Identifiable {
            var id: String; var service: String; var severity: String; var freeLimit: String; var oneUser: String
            var scale: String; var upgrade: String; var paid: String; var code: Bool
            var severityLabel: String { ["now": "Now", "soon": "Soon"][severity] ?? "At scale" }
        }
        var freeUsers = 0; var tightest = ""; var planUSD = 0.0; var videoUSD = 0.0
        var scenarios: [Scenario] = []; var bottlenecks: [Bottleneck] = []
    }
    var totals = Totals(); var apis: [API] = []; var installs: [Install] = []; var controls = Controls(); var build = ""; var storage = ""
    var capacity: Capacity?
    var planner: PlannerAdmin?

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
        if let cap = root["capacity"] as? [String: Any], cap["error"] == nil {
            var c = Capacity()
            let free = cap["free_capacity"] as? [String: Any] ?? [:]
            c.freeUsers = int(free["active_users"]) ?? 0; c.tightest = free["tightest"] as? String ?? ""
            for action in cap["actions"] as? [[String: Any]] ?? [] {
                if action["id"] as? String == "plan" { c.planUSD = dbl(action["usd"]) ?? 0 }
                if action["id"] as? String == "video" { c.videoUSD = dbl(action["usd"]) ?? 0 }
            }
            c.scenarios = (cap["scenarios"] as? [[String: Any]] ?? []).map {
                .init(users: int($0["active_users"]) ?? 0, total: dbl($0["total_usd"]) ?? 0, perUser: dbl($0["per_user_usd"]) ?? 0)
            }
            c.bottlenecks = (cap["bottlenecks"] as? [[String: Any]] ?? []).map {
                .init(id: $0["id"] as? String ?? UUID().uuidString, service: $0["service"] as? String ?? "", severity: $0["severity"] as? String ?? "",
                      freeLimit: $0["free_limit"] as? String ?? "", oneUser: $0["one_user"] as? String ?? "", scale: $0["scale"] as? String ?? "",
                      upgrade: $0["upgrade"] as? String ?? "", paid: $0["paid"] as? String ?? "", code: $0["code"] as? Bool ?? false)
            }
            capacity = c
        }
        planner = PlannerAdmin(json: root["planner"])
        let h = root["health"] as? [String: Any] ?? [:]
        build = h["build"] as? String ?? ""; storage = h["storage"] as? String ?? ""
    }
}


/// Admin → Planner: how plans are built (fixed choices from the server), and what a trip costs.
struct PlannerAdmin {
    struct Option: Identifiable { var id: String; var label: String; var choices: [(id: String, label: String)] }
    struct Line: Identifiable { var id: String { step }; var step: String; var choice: String; var calls: Double; var usd: Double; var paid: Double; var note: String }
    struct Estimate { var days = 2; var lines: [Line] = []; var total = 0.0; var paidTotal = 0.0; var warnings: [String] = [] }
    struct Model: Identifiable { var id: String; var label: String; var priceIn: Double; var priceOut: Double; var freeTier: Bool; var maps: String; var reviews: String; var speed: String; var notes: String }
    struct Plan: Identifiable { var id: String; var destination: String; var days: Int; var stops: Int; var status: String; var finder: String; var detail: String; var estimate: Estimate }
    var options: [Option] = []; var config: [String: String] = [:]; var models: [Model] = []; var recent: [Plan] = []; var estimate = Estimate()

    init?(json: Any?) {
        guard let root = json as? [String: Any], root["error"] == nil, let opts = root["options"] as? [String: Any] else { return nil }
        let order = ["place_finder", "idea_model", "gemini_tier", "place_check", "request_reader"]
        options = order.compactMap { key in
            guard let o = opts[key] as? [String: Any] else { return nil }
            return Option(id: key, label: o["label"] as? String ?? key,
                          choices: (o["choices"] as? [[String: Any]] ?? []).map { ($0["id"] as? String ?? "", $0["label"] as? String ?? "") })
        }
        config = root["config"] as? [String: String] ?? [:]
        models = (root["models"] as? [[String: Any]] ?? []).map { m in
            Model(id: m["id"] as? String ?? "", label: m["label"] as? String ?? "", priceIn: (m["in"] as? NSNumber)?.doubleValue ?? 0,
                  priceOut: (m["out"] as? NSNumber)?.doubleValue ?? 0, freeTier: m["free_tier"] as? Bool ?? false,
                  maps: m["maps"] as? String ?? "", reviews: m["reviews"] as? String ?? "", speed: m["speed"] as? String ?? "", notes: m["notes"] as? String ?? "")
        }
        estimate = Self.estimate((root["estimates"] as? [String: Any])?["2"]) ?? Estimate()
        let finders = Dictionary(uniqueKeysWithValues: (options.first { $0.id == "place_finder" }?.choices ?? []).map { ($0.id, $0.label) })
        recent = (root["recent"] as? [[String: Any]] ?? []).enumerated().map { index, r in
            let c = r["config"] as? [String: String] ?? [:]
            return Plan(id: (r["job"] as? String ?? "") + "\(index)", destination: r["destination"] as? String ?? "Trip",
                        days: (r["days"] as? NSNumber)?.intValue ?? 0, stops: (r["stops"] as? NSNumber)?.intValue ?? 0,
                        status: r["status"] as? String ?? "", finder: finders[c["place_finder"] ?? ""] ?? (c["place_finder"] ?? ""),
                        detail: c["place_finder"] == "gemini_blend" ? [c["idea_model"], c["gemini_tier"], c["place_check"]].compactMap { $0 }.joined(separator: " · ") : "",
                        estimate: Self.estimate(r["estimate"]) ?? Estimate())
        }
    }

    static func estimate(_ json: Any?) -> Estimate? {
        guard let e = json as? [String: Any] else { return nil }
        func d(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
        return Estimate(days: (e["days"] as? NSNumber)?.intValue ?? 2,
                        lines: (e["lines"] as? [[String: Any]] ?? []).map {
                            Line(step: $0["step"] as? String ?? "", choice: $0["choice"] as? String ?? "", calls: d($0["calls"]),
                                 usd: d($0["usd"]), paid: d($0["paid_usd"]), note: $0["note"] as? String ?? "") },
                        total: d(e["total_usd"]), paidTotal: d(e["paid_total_usd"]), warnings: e["warnings"] as? [String] ?? [])
    }
}

struct PlannerAdminSection: View {
    let planner: PlannerAdmin
    let baseURL: String
    let save: ([String: String]) async -> Void
    @State private var draft: [String: String] = [:]
    @State private var days = 2
    @State private var estimate: PlannerAdmin.Estimate?
    @State private var saving = false

    private var current: [String: String] { draft.isEmpty ? planner.config : draft }
    private var changed: Bool { !draft.isEmpty && draft != planner.config }

    var body: some View {
        Section {
            ForEach(planner.options) { option in
                Picker(option.label, selection: Binding(get: { current[option.id] ?? "" }, set: { value in
                    var next = current; next[option.id] = value; draft = next
                })) {
                    ForEach(option.choices, id: \.id) { Text($0.label).tag($0.id) }
                }
                .disabled(["idea_model", "gemini_tier", "place_check"].contains(option.id) && current["place_finder"] != "gemini_blend")
            }
            Stepper("Trip length: \(days) day\(days == 1 ? "" : "s")", value: $days, in: 1...14)
            let e = estimate ?? planner.estimate
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.usd(e.total) + " per \(e.days)-day trip").font(.title3.bold()).monospacedDigit()
                if e.paidTotal != e.total { Text(Self.usd(e.paidTotal) + " once off Gemini's free tier").font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(e.lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.step).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Self.usd(line.usd)).monospacedDigit()
                    }
                    Text(line.choice + (line.note.isEmpty ? "" : " · " + line.note)).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(e.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            Button(saving ? "Saving…" : "Save planner") {
                saving = true
                Task { await save(current); saving = false; draft = [:] }
            }
            .disabled(!changed || saving)
        } header: { Text("Planner") } footer: { Text("Saving applies to every plan from then on.") }
        .task(id: "\(current)\(days)") { await loadEstimate() }

        Section("AI models compared") {
            ForEach(planner.models) { m in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Maps: \(m.maps)"); Text("Reviews: \(m.reviews)"); Text("Speed: \(m.speed)"); Text(m.notes).foregroundStyle(.secondary)
                    }.font(.caption)
                } label: {
                    HStack {
                        Text(m.label)
                        Spacer()
                        Text(String(format: "$%.2f · $%.2f", m.priceIn, m.priceOut)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        if m.freeTier { Text("Free tier").font(.caption2.bold()).foregroundStyle(.green) }
                    }
                }
            }
        }

        if !planner.recent.isEmpty {
            Section("Recent plans") {
                ForEach(planner.recent) { plan in
                    DisclosureGroup {
                        ForEach(plan.estimate.lines) { line in
                            LabeledContent(line.step, value: Self.usd(line.usd)).font(.caption)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text("\(plan.destination) · \(plan.days) days").font(.subheadline.weight(.semibold)); Spacer(); Text(Self.usd(plan.estimate.total)).monospacedDigit() }
                            Text(plan.finder + (plan.detail.isEmpty ? "" : " · " + plan.detail) + " · \(plan.stops) stops").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func loadEstimate() async {
        guard let json = try? JSONSerialization.data(withJSONObject: current), let config = String(data: json, encoding: .utf8),
              var components = URLComponents(string: baseURL + "/api/admin/planner-estimate") else { return }
        components.queryItems = [URLQueryItem(name: "config", value: config), URLQueryItem(name: "days", value: String(days))]
        guard let url = components.url else { return }
        try? await AccountSession.shared.ensureFresh()
        var request = URLRequest(url: url, timeoutInterval: 20)
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = PlannerAdmin.estimate(try? JSONSerialization.jsonObject(with: data)) else { return }
        estimate = parsed
    }

    static func usd(_ value: Double) -> String { value == 0 ? "$0" : String(format: value < 0.1 ? "$%.3f" : "$%.2f", value) }
}


#if DEBUG
/// `-TrippyPlannerAdminDemo`: the Planner admin section with sample data, for screenshots (no admin sign-in needed).
struct PlannerAdminDemo: View {
    static let json = #"""
{"options": {"place_finder": {"label": "Places come from", "choices": [{"id": "google_search", "label": "Google search per category (today)"}, {"id": "gemini_blend", "label": "AI ideas, checked as real places"}, {"id": "open_data", "label": "Open data only (OpenStreetMap, Wikivoyage)"}]}, "idea_model": {"label": "AI for place ideas", "choices": [{"id": "gemini-3.6-flash", "label": "Gemini 3.6 Flash"}, {"id": "gemini-3.8-flash", "label": "Gemini 3.8 Flash"}, {"id": "gemini-3.5-flash-lite", "label": "Gemini 3.5 Flash-Lite"}, {"id": "gemini-3.1-flash-lite", "label": "Gemini 3.1 Flash-Lite"}, {"id": "azure-luna", "label": "GPT-6 Luna (Azure)"}]}, "gemini_tier": {"label": "Gemini billing", "choices": [{"id": "free", "label": "Free tier (limits; Google may use inputs)"}, {"id": "paid", "label": "Paid tier"}]}, "place_check": {"label": "Check ideas against", "choices": [{"id": "osm", "label": "OpenStreetMap only (free)"}, {"id": "osm_then_google", "label": "OpenStreetMap, then Google for misses"}, {"id": "google", "label": "Google for every idea"}]}, "request_reader": {"label": "Reading the request", "choices": [{"id": "azure-luna", "label": "GPT-6 Luna (Azure)"}, {"id": "keywords", "label": "Keywords only (free)"}]}}, "models": [{"label": "Gemini 3.6 Flash", "in": 0.75, "out": 3.75, "think": 1000, "free_tier": true, "maps": "Paid tier only ($14 per 1,000 after 5,000 free a month)", "web": "Paid tier only", "reviews": "From training only; no live reviews without grounding", "speed": "≈ 16 s per category", "notes": "Best food picks in the 9 Nov tests. Price doubles 1 Jan 2027.", "id": "gemini-3.6-flash"}, {"label": "Gemini 3.8 Flash", "in": 0.75, "out": 3.75, "think": 3000, "free_tier": true, "maps": "Paid tier only ($14 per 1,000 after 5,000 free a month)", "web": "Paid tier only", "reviews": "From training only; no live reviews without grounding", "speed": "Slow: up to 5 min per call in the 8 Nov test", "notes": "Strongest reasoning; too slow for plans today.", "id": "gemini-3.8-flash"}, {"label": "Gemini 3.5 Flash-Lite", "in": 0.3, "out": 2.5, "think": 0, "free_tier": true, "maps": "Paid tier only ($14 per 1,000 after 5,000 free a month)", "web": "Paid tier only", "reviews": "From training only", "speed": "≈ 4–11 s per category", "notes": "Fast; sometimes puts a sight or café in the wrong list (the check drops it).", "id": "gemini-3.5-flash-lite"}, {"label": "Gemini 3.1 Flash-Lite", "in": 0.25, "out": 1.5, "think": 0, "free_tier": true, "maps": "Paid tier only", "web": "Paid tier only", "reviews": "From training only", "speed": "≈ 6 s per category", "notes": "Cheapest; older knowledge.", "id": "gemini-3.1-flash-lite"}, {"label": "GPT-6 Luna (Azure)", "in": 0.3, "out": 1.0, "think": 800, "free_tier": false, "maps": "No map data", "web": "Web search through our Azure agent (blogs, review sites), billed per search", "reviews": "Can read review sites and blogs when web search is on", "speed": "Not measured for this task", "notes": "Paid only; counts against TRIPPY_AI_BUDGET_AMOUNT. Not yet tested for place ideas.", "id": "azure-luna"}], "default": {"place_finder": "google_search", "idea_model": "gemini-3.6-flash", "gemini_tier": "free", "place_check": "osm_then_google", "request_reader": "azure-luna"}, "config": {"place_finder": "google_search", "idea_model": "gemini-3.6-flash", "gemini_tier": "free", "place_check": "osm_then_google", "request_reader": "azure-luna"}, "estimates": {"2": {"config": {"place_finder": "google_search", "idea_model": "gemini-3.6-flash", "gemini_tier": "free", "place_check": "osm_then_google", "request_reader": "azure-luna"}, "days": 2, "categories": 5, "lines": [{"step": "Reading the request", "choice": "GPT-6 Luna", "calls": 1, "usd": 0.0024, "paid_usd": 0.0024, "note": ""}, {"step": "Finding places", "choice": "Google search", "calls": 5, "usd": 0.175, "paid_usd": 0.175, "note": "After the 1,000 free searches a month"}, {"step": "Famous sights", "choice": "Wikidata", "calls": 1, "usd": 0, "paid_usd": 0, "note": "Free"}, {"step": "Plan notes and day themes", "choice": "Gemini (notes pool)", "calls": 3, "usd": 0.0, "paid_usd": 0.0126, "note": "Free tier"}], "total_usd": 0.1774, "paid_total_usd": 0.19, "warnings": ["Google ratings are used to choose places, which Google's EEA terms don't allow for trip planning."]}}, "recent": [{"job": "a1b2c3d4", "destination": "Rome", "days": 2, "stops": 17, "status": "partial", "config": {"place_finder": "gemini_blend", "idea_model": "gemini-3.6-flash", "gemini_tier": "free", "place_check": "osm_then_google", "request_reader": "azure-luna"}, "estimate": {"config": {"place_finder": "gemini_blend", "idea_model": "gemini-3.6-flash", "gemini_tier": "free", "place_check": "osm_then_google", "request_reader": "azure-luna"}, "days": 2, "categories": 5, "lines": [{"step": "Reading the request", "choice": "GPT-6 Luna", "calls": 1, "usd": 0.0024, "paid_usd": 0.0024, "note": ""}, {"step": "Finding places", "choice": "Gemini 3.6 Flash (free tier)", "calls": 6.5, "usd": 0.0, "paid_usd": 0.0558, "note": "Free tier: limited requests a day"}, {"step": "Checking places are real", "choice": "OpenStreetMap, Google for misses", "calls": 52.0, "usd": 0.091, "paid_usd": 0.091, "note": "≈ 18 Google checks at $0.005, after 10,000 free a month"}, {"step": "Famous sights", "choice": "Wikidata", "calls": 1, "usd": 0, "paid_usd": 0, "note": "Free"}, {"step": "Plan notes and day themes", "choice": "Gemini (notes pool)", "calls": 3, "usd": 0.0, "paid_usd": 0.0126, "note": "Free tier"}], "total_usd": 0.0934, "paid_total_usd": 0.1618, "warnings": ["Free tier: a busy day can hit Gemini's limits, and Google may use the prompts to improve its models."]}}, {"job": "e5f6a7b8", "destination": "Athens", "days": 2, "stops": 21, "status": "partial", "config": {"place_finder": "google_search", "idea_model": "gemini-3.6-flash", "gemini_tier": "free", "place_check": "osm_then_google", "request_reader": "azure-luna"}, "estimate": {"config": {"place_finder": "google_search", "idea_model": "gemini-3.6-flash", "gemini_tier": "free", "place_check": "osm_then_google", "request_reader": "azure-luna"}, "days": 2, "categories": 5, "lines": [{"step": "Reading the request", "choice": "GPT-6 Luna", "calls": 1, "usd": 0.0024, "paid_usd": 0.0024, "note": ""}, {"step": "Finding places", "choice": "Google search", "calls": 5, "usd": 0.175, "paid_usd": 0.175, "note": "After the 1,000 free searches a month"}, {"step": "Famous sights", "choice": "Wikidata", "calls": 1, "usd": 0, "paid_usd": 0, "note": "Free"}, {"step": "Plan notes and day themes", "choice": "Gemini (notes pool)", "calls": 3, "usd": 0.0, "paid_usd": 0.0126, "note": "Free tier"}], "total_usd": 0.1774, "paid_total_usd": 0.19, "warnings": ["Google ratings are used to choose places, which Google's EEA terms don't allow for trip planning."]}}]}
"""#
    var body: some View {
        NavigationStack {
            List {
                if let planner = PlannerAdmin(json: try? JSONSerialization.jsonObject(with: Data(Self.json.utf8))) {
                    PlannerAdminSection(planner: planner, baseURL: "http://127.0.0.1:9") { _ in }
                }
            }
            .navigationTitle("Admin").navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
