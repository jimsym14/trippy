import SwiftUI

/// The cost and income model from trippy/cost_model.py. The server sends it with the admin summary;
/// the app also ships a copy (Resources/cost-model.json) so the calculator works offline.
struct CostModel {
    struct Unit { var id: String; var label: String; var usd: Double; var free: Double?; var unlimited: Bool; var verify: Bool; var note: String }
    struct Pipeline { var id: String; var label: String; var units: [String: Double]; var legal: String; var quality: String }
    struct Usage { var id: String; var label: String; var videos, plans, libraryCards, otherCards, searches: Double }
    struct Money { var id: String; var label: String; var plusMonth, plusYear, tripPass, packs, tips, affiliate: Double }
    struct Product { var id: String; var label: String; var eur: Double; var per: String; var net: Double }
    struct Stage { var id: String; var label: String; var upTo: Int?; var items: [(String, Double)] }
    struct Scenario { var id: String; var label: String; var users: Int; var usage: String; var money: String; var pipeline: String; var reuse: Double; var net: Double }
    struct Live: Identifiable { var id: String; var label: String; var month: Int }

    var version = ""; var vat = 0.24; var appleCut = 0.15
    var units: [Unit] = []; var pipelines: [Pipeline] = []; var usage: [Usage] = []; var money: [Money] = []
    var products: [Product] = []; var stages: [Stage] = []; var scenarios: [Scenario] = []; var live: [Live]?

    init?(json: Any?) {
        guard let root = json as? [String: Any], root["error"] == nil, let version = root["version"] as? String else { return nil }
        func d(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
        self.version = version; vat = d(root["vat"]); appleCut = d(root["apple_cut"])
        let order = ["google_ui_kit", "google_id_match", "gemini_video", "plan_ai", "foursquare_premium", "google_text_search", "apple_mapkit"]
        units = (root["units"] as? [String: [String: Any]] ?? [:]).map { id, u in
            Unit(id: id, label: u["label"] as? String ?? id, usd: d(u["usd"]), free: (u["free"] as? NSNumber)?.doubleValue,
                 unlimited: (u["free"] as? String) == "unlimited", verify: u["verify"] as? Bool ?? false, note: u["note"] as? String ?? "")
        }.sorted { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
        pipelines = (root["pipelines"] as? [String: [String: Any]] ?? [:]).map { id, p in
            Pipeline(id: id, label: p["label"] as? String ?? id, units: (p["units"] as? [String: Any] ?? [:]).mapValues { d($0) },
                     legal: p["legal"] as? String ?? "", quality: p["quality"] as? String ?? "")
        }.sorted { $0.label < $1.label }
        let usageOrder = ["light", "average", "heavy"], moneyOrder = ["low", "middle", "high"]
        usage = (root["usage"] as? [String: [String: Any]] ?? [:]).map { id, u in
            Usage(id: id, label: u["label"] as? String ?? id, videos: d(u["videos"]), plans: d(u["plans"]),
                  libraryCards: d(u["library_cards"]), otherCards: d(u["other_cards"]), searches: d(u["searches"]))
        }.sorted { (usageOrder.firstIndex(of: $0.id) ?? 9) < (usageOrder.firstIndex(of: $1.id) ?? 9) }
        money = (root["money"] as? [String: [String: Any]] ?? [:]).map { id, m in
            Money(id: id, label: m["label"] as? String ?? id, plusMonth: d(m["plus_month"]), plusYear: d(m["plus_year"]),
                  tripPass: d(m["trip_pass_per_year"]), packs: d(m["packs_per_year"]), tips: d(m["tips_usd_per_year"]),
                  affiliate: d(m["affiliate_usd_per_year"]))
        }.sorted { (moneyOrder.firstIndex(of: $0.id) ?? 9) < (moneyOrder.firstIndex(of: $1.id) ?? 9) }
        let productOrder = ["plus_month", "plus_year", "trip_pass", "pack"]
        products = (root["products"] as? [String: [String: Any]] ?? [:]).map { id, p in
            Product(id: id, label: p["label"] as? String ?? id, eur: d(p["eur"]), per: p["per"] as? String ?? "", net: d(p["net_usd"]))
        }.sorted { (productOrder.firstIndex(of: $0.id) ?? 9) < (productOrder.firstIndex(of: $1.id) ?? 9) }
        stages = (root["fixed"] as? [[String: Any]] ?? []).map { s in
            Stage(id: s["id"] as? String ?? "", label: s["label"] as? String ?? "", upTo: (s["up_to_users"] as? NSNumber)?.intValue,
                  items: (s["items"] as? [[String: Any]] ?? []).map { ($0["item"] as? String ?? "", d($0["usd"])) })
        }
        scenarios = (root["scenarios"] as? [[String: Any]] ?? []).map { s in
            Scenario(id: s["id"] as? String ?? "", label: s["label"] as? String ?? "", users: (s["users"] as? NSNumber)?.intValue ?? 0,
                     usage: s["usage"] as? String ?? "average", money: s["money"] as? String ?? "middle",
                     pipeline: s["pipeline"] as? String ?? "foursquare", reuse: d(s["reuse"]),
                     net: d((s["result"] as? [String: Any])?["net_usd"]))
        }
        live = (root["live"] as? [[String: Any]])?.map { Live(id: $0["metric"] as? String ?? UUID().uuidString, label: $0["label"] as? String ?? "",
                                                             month: ($0["month"] as? NSNumber)?.intValue ?? 0) }
    }

    static var bundled: CostModel? {
        guard let url = Bundle.main.url(forResource: "cost-model", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return CostModel(json: try? JSONSerialization.jsonObject(with: data))
    }

    struct Result {
        var calls: [String: Double] = [:]; var costs: [String: Double] = [:]; var variable = 0.0
        var stage: Stage?; var fixed = 0.0; var income: [(String, Double)] = []; var incomeTotal = 0.0
        var cost: Double { variable + fixed }; var net: Double { incomeTotal - cost }
        var payers = 0.0
    }

    /// Same arithmetic as `compute()` in trippy/cost_model.py; the scenario check below compares them.
    func compute(users: Double, usage u: Usage, money m: Money, pipeline: Pipeline, reuse: Double) -> Result {
        var r = Result()
        for unit in units { r.calls[unit.id] = 0 }
        r.calls["google_ui_kit"] = users * u.libraryCards
        r.calls["google_id_match"] = users * u.videos * 5
        r.calls["gemini_video"] = users * u.videos * (1 - reuse)
        for (unit, n) in pipeline.units { r.calls[unit, default: 0] += users * u.plans * n }
        r.calls["apple_mapkit"] = users * (u.otherCards + u.libraryCards + u.searches)
        for unit in units {
            let calls = r.calls[unit.id] ?? 0
            r.costs[unit.id] = unit.unlimited ? 0 : max(0, calls - (unit.free ?? 0)) * unit.usd
        }
        r.variable = r.costs.values.reduce(0, +)
        r.stage = stages.first { $0.upTo == nil || Int(users) <= $0.upTo! } ?? stages.last
        r.fixed = r.stage?.items.reduce(0) { $0 + $1.1 } ?? 0
        func net(_ id: String) -> Double { products.first { $0.id == id }?.net ?? 0 }
        r.income = [("Plus monthly", users * m.plusMonth * net("plus_month")),
                    ("Plus yearly", users * m.plusYear * net("plus_year") / 12),
                    ("Trip Pass", users * m.tripPass * net("trip_pass") / 12),
                    ("Packs", users * m.packs * net("pack") / 12),
                    ("Tips", users * m.tips * (1 - appleCut) / 12),
                    ("Booking commissions", users * m.affiliate / 12)]
        r.incomeTotal = r.income.reduce(0) { $0 + $1.1 }
        r.payers = users * (m.plusMonth + m.plusYear)
        return r
    }
}

struct CostCalculatorView: View {
    let baseURL: String
    @ObservedObject private var account = AccountSession.shared
    @State private var model: CostModel? = CostModel.bundled
    @State private var source = "Copy in the app"
    @State private var users = 10_000.0
    @State private var usageID = "average"
    @State private var moneyID = "middle"
    @State private var pipelineID = "foursquare"
    @State private var reuse = 0.5

    var body: some View {
        Group {
            if let model { content(model) }
            else { ContentUnavailableView("No cost model", systemImage: "function", description: Text("The app's copy of the model is missing.")) }
        }
        .navigationTitle("Cost calculator")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFromServer() }
        .refreshable { await loadFromServer() }
    }

    @ViewBuilder private func content(_ model: CostModel) -> some View {
        let usage = model.usage.first { $0.id == usageID } ?? model.usage.first!
        let money = model.money.first { $0.id == moneyID } ?? model.money.first!
        let pipeline = model.pipelines.first { $0.id == pipelineID } ?? model.pipelines.first!
        let r = model.compute(users: users, usage: usage, money: money, pipeline: pipeline, reuse: reuse)
        List {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.scenarios, id: \.id) { s in
                            Button(s.label) {
                                users = Double(s.users); usageID = s.usage; moneyID = s.money; pipelineID = s.pipeline; reuse = s.reuse
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }.scrollIndicators(.hidden)
            } header: { Text("Ready-made") }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Monthly active users")
                        Spacer()
                        TextField("Users", value: $users, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit().frame(maxWidth: 120)
                    }
                    Slider(value: Binding(get: { log10(max(10, users)) }, set: { users = (pow(10, $0) / 10).rounded() * 10 }), in: 1...6)
                }
                Picker("Usage per user", selection: $usageID) { ForEach(model.usage, id: \.id) { Text($0.label).tag($0.id) } }
                Picker("Who pays", selection: $moneyID) { ForEach(model.money, id: \.id) { Text($0.label).tag($0.id) } }
                Picker("Plans built from", selection: $pipelineID) { ForEach(model.pipelines, id: \.id) { Text($0.label).tag($0.id) } }
                VStack(alignment: .leading) {
                    LabeledContent("Videos reused from other users", value: reuse.formatted(.percent.precision(.fractionLength(0))))
                    Slider(value: $reuse, in: 0...0.8, step: 0.05)
                }
            } header: { Text("Assumptions") } footer: {
                Text("\(usage.label): \(fmt(usage.videos)) videos, \(fmt(usage.plans)) plans, \(fmt(usage.libraryCards)) saved-place cards a month. \(pipeline.legal). \(pipeline.quality).")
            }

            Section {
                LabeledContent("Result a month") {
                    Text(usd(r.net, sign: true)).font(.title3.bold()).monospacedDigit().foregroundStyle(r.net >= 0 ? .green : .red)
                }
                LabeledContent("Income", value: usd(r.incomeTotal))
                LabeledContent("Costs", value: usd(r.cost))
                LabeledContent("Cost per user a year", value: users > 0 ? usd(r.cost * 12 / users, cents: true) : "—")
                LabeledContent("Paying subscribers", value: r.payers.formatted(.number.precision(.fractionLength(0))))
                LabeledContent("Breaks even from", value: breakEven(model, usage: usage, money: money, pipeline: pipeline))
            } header: { Text("Result") }

            Section {
                ForEach(model.units, id: \.id) { unit in
                    let calls = r.calls[unit.id] ?? 0
                    if calls > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(unit.label + (unit.verify ? " *" : ""))
                                Spacer()
                                Text(usd(r.costs[unit.id] ?? 0)).monospacedDigit()
                            }
                            Text("\(calls.formatted(.number.notation(.compactName))) a month · \(unit.unlimited ? "free" : unit.free.map { "\(Int($0).formatted()) free, then " } ?? "")\(unit.unlimited ? "" : usd(unit.usd * 1000, cents: true) + " per 1,000")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let stage = r.stage {
                    DisclosureGroup {
                        ForEach(stage.items, id: \.0) { item in LabeledContent(item.0, value: usd(item.1, cents: true)).font(.caption) }
                    } label: { LabeledContent("Fixed (\(stage.label))", value: usd(r.fixed)) }
                }
            } header: { Text("Costs a month") } footer: { Text("* Estimate: confirm on the provider's pricing page.") }

            Section {
                ForEach(r.income, id: \.0) { item in LabeledContent(item.0, value: usd(item.1)) }
            } header: { Text("Income a month") } footer: {
                Text("Prices include \(Int(model.vat * 100))% VAT; Apple keeps \(Int(model.appleCut * 100))%. Booking commissions and tips are estimates.")
            }

            Section("What we keep per sale") {
                ForEach(model.products, id: \.id) { p in
                    LabeledContent("\(p.label) · €\(String(format: "%.2f", p.eur))", value: usd(p.net, cents: true))
                }
            }

            if let live = model.live {
                Section {
                    ForEach(live) { row in LabeledContent(row.label, value: row.month.formatted()) }
                } header: { Text("Measured this month") } footer: { Text("Real counters from the server, to check the assumptions above.") }
            }

            Section {
                ForEach(model.scenarios, id: \.id) { s in
                    let mine = model.compute(users: Double(s.users), usage: model.usage.first { $0.id == s.usage }!,
                                             money: model.money.first { $0.id == s.money }!,
                                             pipeline: model.pipelines.first { $0.id == s.pipeline }!, reuse: s.reuse).net
                    let same = abs(mine - s.net) < 1
                    LabeledContent(s.label) {
                        Label(usd(s.net, sign: true), systemImage: same ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(same ? Color.secondary : Color.orange).monospacedDigit()
                    }
                }
            } header: { Text("Model check") } footer: { Text("Server and app arithmetic agree when every row has a tick. \(source) · model \(model.version).") }
        }
    }

    private func breakEven(_ model: CostModel, usage: CostModel.Usage, money: CostModel.Money, pipeline: CostModel.Pipeline) -> String {
        var n = 100.0
        while n <= 2_000_000 {
            if model.compute(users: n, usage: usage, money: money, pipeline: pipeline, reuse: reuse).net >= 0 {
                return n.formatted(.number.notation(.compactName)) + " users"
            }
            n *= 1.15
        }
        return "Not below 2M users"
    }

    private func fmt(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func usd(_ value: Double, sign: Bool = false, cents: Bool = false) -> String {
        let text = abs(value).formatted(.currency(code: "USD").precision(.fractionLength(cents ? 2 : 0)))
        return (value < 0 ? "−" : sign && value > 0 ? "+" : "") + text
    }

    private func loadFromServer() async {
        guard account.isAdmin, let url = URL(string: baseURL + "/api/admin/summary") else { return }
        try? await account.ensureFresh()
        var request = URLRequest(url: url, timeoutInterval: 25)
        if let session = AccountSession.header { request.setValue(session, forHTTPHeaderField: "X-Trippy-Session") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let live = CostModel(json: root["cost_model"]) else { return }
        model = live; source = "From the server"
    }
}
