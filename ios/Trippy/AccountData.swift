import SwiftUI

// MARK: - Moving a phone-only setup into an account

/// Everything Trippy keeps on this phone, as one document an account can hold: the app's
/// own settings and lists (trips, pins, places you've been, guide edits, home) and the video
/// library file. Device-only state (install id, onboarding flags, server address, map chrome)
/// stays on the phone.
enum AccountData {
    static let movedKey = "trippy.account.movedFor"
    private static let deviceOnly = ["trippy.install.", "trippy.onboarding.", "trippy.bridgeHost", "trippy.shareSummary",
                                     "trippy.account.", "trippy.native.map.", "trippy.home.coordinate", "trippy.guide.lastOpened"]
    /// Lists merged by their items' "id" when an account and a phone both have some.
    private static let mergeable = ["trippy.native.trips.v1", "trippy.native.personalPlaces.v1", "trippy.native.visitedPlaces.v1"]
    private static let libraryFile = "library"

    struct Summary: Equatable {
        var trips = 0, pins = 0, videos = 0, notes = 0, countries = 0
        var home: String?
        var isEmpty: Bool { trips + pins + videos + notes + countries == 0 && home == nil }
        var rows: [(String, String, Int)] {
            [("suitcase.rolling", "Trips", trips), ("mappin", "Pins and saves", pins), ("play.rectangle", "Videos", videos),
             ("note.text", "Notes", notes), ("globe.europe.africa", "Countries you’ve been", countries)].filter { $0.2 > 0 }
        }
    }

    // MARK: Collect

    static func snapshot() -> [String: Any] {
        var values: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("trippy.") && !deviceOnly.contains(where: key.hasPrefix) {
            if let data = value as? Data { values[key] = ["t": "data", "v": data.base64EncodedString()] }
            else if let text = value as? String { values[key] = ["t": "string", "v": text] }
            else if let flag = value as? Bool { values[key] = ["t": "bool", "v": flag] }
            else if let number = value as? NSNumber { values[key] = ["t": "number", "v": number] }
            else if let list = value as? [Any], JSONSerialization.isValidJSONObject(list) { values[key] = ["t": "array", "v": list] }
        }
        var files: [String: String] = [:]
        if let library = try? Data(contentsOf: SocialLibraryStore.file) { files[libraryFile] = library.base64EncodedString() }
        return ["version": 1, "saved_at": Date().timeIntervalSince1970, "defaults": values, "files": files]
    }

    static func summary(of payload: [String: Any]?) -> Summary {
        guard let payload else { return Summary() }
        let values = payload["defaults"] as? [String: [String: Any]] ?? [:]
        func list(_ key: String) -> [[String: Any]] {
            guard let entry = values[key] else { return [] }
            let raw: Data? = (entry["t"] as? String) == "data" ? (entry["v"] as? String).flatMap { Data(base64Encoded: $0) }
                : (entry["v"] as? String).map { Data($0.utf8) }
            return raw.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        }
        var result = Summary()
        result.trips = list("trippy.native.trips.v1").count
        result.pins = list("trippy.native.personalPlaces.v1").count
        result.countries = Set(list("trippy.native.visitedPlaces.v1").compactMap { $0["countryCode"] as? String }).count
        if let library = (payload["files"] as? [String: String])?[libraryFile].flatMap({ Data(base64Encoded: $0) }),
           let document = try? JSONSerialization.jsonObject(with: library) as? [String: Any] {
            result.videos = (document["sources"] as? [Any])?.count ?? 0
            result.notes = (document["notes"] as? [Any])?.count ?? 0
        }
        if let home = values["trippy.home.profile.v1"], (home["t"] as? String) == "data",
           let data = (home["v"] as? String).flatMap({ Data(base64Encoded: $0) }),
           let profile = try? JSONDecoder().decode(HomeProfile.self, from: data) { result.home = profile.label }
        return result
    }

    // MARK: Apply

    /// Writes an account's document onto this phone. `combine` keeps this phone's items too
    /// (lists are joined by id, the phone's version winning); otherwise the account's replace them.
    static func apply(_ payload: [String: Any], combine: Bool) {
        let defaults = UserDefaults.standard
        let values = payload["defaults"] as? [String: [String: Any]] ?? [:]
        for (key, entry) in values where !deviceOnly.contains(where: key.hasPrefix) {
            let type = entry["t"] as? String
            if combine, mergeable.contains(key) {
                defaults.set(merged(key: key, remote: entry), forKey: key); continue
            }
            if combine, defaults.object(forKey: key) != nil { continue }   // the phone's own setting stays
            switch type {
            case "data": if let v = (entry["v"] as? String).flatMap({ Data(base64Encoded: $0) }) { defaults.set(v, forKey: key) }
            case "string", "bool", "number", "array": defaults.set(entry["v"], forKey: key)
            default: break
            }
        }
        if let library = (payload["files"] as? [String: String])?[libraryFile].flatMap({ Data(base64Encoded: $0) }) {
            if combine, let mine = try? Data(contentsOf: SocialLibraryStore.file) {
                if let joined = mergedLibrary(mine, library) { try? write(joined) }
            } else { try? write(library) }
        }
        NotificationCenter.default.post(name: .accountDataApplied, object: nil)
    }

    private static func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: SocialLibraryStore.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: SocialLibraryStore.file, options: .atomic)
    }

    private static func merged(key: String, remote entry: [String: Any]) -> Any {
        let isData = (entry["t"] as? String) == "data"
        let remoteData: Data? = isData ? (entry["v"] as? String).flatMap { Data(base64Encoded: $0) } : (entry["v"] as? String).map { Data($0.utf8) }
        let localValue = UserDefaults.standard.object(forKey: key)
        let localData: Data? = (localValue as? Data) ?? (localValue as? String).map { Data($0.utf8) }
        func items(_ data: Data?) -> [[String: Any]] { data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? [] }
        var byID: [String: [String: Any]] = [:]
        var order: [String] = []
        for item in items(remoteData) + items(localData) {   // the phone's version comes last and wins
            let id = (item["id"] as? String) ?? "\(item["name"] ?? "")|\(item["countryCode"] ?? "")"
            if byID[id] == nil { order.append(id) }
            byID[id] = item
        }
        let joined = (try? JSONSerialization.data(withJSONObject: order.compactMap { byID[$0] })) ?? Data("[]".utf8)
        return isData ? joined : (String(data: joined, encoding: .utf8) ?? "[]")
    }

    private static func mergedLibrary(_ mine: Data, _ theirs: Data) -> Data? {
        guard var a = try? JSONSerialization.jsonObject(with: mine) as? [String: Any],
              let b = try? JSONSerialization.jsonObject(with: theirs) as? [String: Any] else { return nil }
        for key in ["sources", "places", "notes"] {
            let ours = a[key] as? [[String: Any]] ?? [], other = b[key] as? [[String: Any]] ?? []
            let ids = Set(ours.compactMap { $0["id"] as? String })
            a[key] = ours + other.filter { ($0["id"] as? String).map { !ids.contains($0) } ?? true }
        }
        return try? JSONSerialization.data(withJSONObject: a)
    }
}

extension Notification.Name {
    /// Account data was written onto this phone; screens reload what they show.
    static let accountDataApplied = Notification.Name("trippy.accountDataApplied")
    /// Someone just signed in (not during onboarding): offer the move and the tour.
    static let accountSignedIn = Notification.Name("trippy.accountSignedIn")
    /// Developer: show the first-launch setup again.
    static let replayOnboarding = Notification.Name("trippy.replayOnboarding")
}

extension AccountSession {
    func uploadData(_ payload: [String: Any]) async throws {
        try await ensureFresh()
        _ = try await send("/api/account/data", method: "POST", body: ["payload": payload])
        if let id = session?.userID { UserDefaults.standard.set(id, forKey: AccountData.movedKey) }
    }
    func downloadData() async throws -> [String: Any]? {
        try await ensureFresh()
        return try await send("/api/account/data", method: "GET", body: nil)["payload"] as? [String: Any]
    }
}

// MARK: - The move, as a sheet

/// "Bring your things into your account": what this phone has, what the account has, and
/// one clear choice. Nothing is deleted from the phone.
struct AccountMoveSheet: View {
    let onDone: () -> Void
    @ObservedObject private var account = AccountSession.shared
    @State private var local = AccountData.Summary()
    @State private var remote: AccountData.Summary?
    @State private var remotePayload: [String: Any]?
    @State private var stage = Stage.checking
    @State private var error: String?
    enum Stage { case checking, choose, working, done }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch stage {
            case .checking:
                Spacer(); HStack { Spacer(); ProgressView().controlSize(.large); Spacer() }; Spacer()
            case .choose:
                choose
            case .working:
                Spacer()
                VStack(spacing: 14) { ProgressView().controlSize(.large); Text("Moving your things…").font(Sketch.text(16, "SemiBold", relativeTo: .body)) }
                    .frame(maxWidth: .infinity)
                Spacer()
            case .done:
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Sketch.sage)
                        .symbolEffect(.bounce, value: stage == .done)
                    Text("All set").font(Sketch.display(.largeTitle, weight: .bold))
                    Text("Your account has everything from this phone.").font(Sketch.text(16, relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
                }
                .frame(maxWidth: .infinity)
                Spacer()
                primary("Continue", action: onDone)
            }
            if let error { Text(error).font(Sketch.text(14, relativeTo: .footnote)).foregroundStyle(Sketch.coral) }
        }
        .padding(24)
        .background(Sketch.paper.ignoresSafeArea())
        .task { await check() }
    }

    @ViewBuilder private var choose: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(remote?.isEmpty == false && local.isEmpty ? "Welcome back" : "Bring it with you").font(Sketch.display(.largeTitle, weight: .bold))
            Text(remote?.isEmpty == false && local.isEmpty ? "Your account has things this phone doesn’t." : "Move what’s on this phone into your account.")
                .font(Sketch.text(17, "Medium", relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
        }
        if !local.isEmpty { box("On this phone", local) }
        if let remote, !remote.isEmpty { box("In your account", remote) }
        Spacer(minLength: 0)
        VStack(spacing: 10) {
            if let remote, !remote.isEmpty, let remotePayload {
                if local.isEmpty {
                    primary("Bring to this phone") { Task { await run { AccountData.apply(remotePayload, combine: false) } } }
                } else {
                    primary("Combine both") { Task { await run { AccountData.apply(remotePayload, combine: true); try await account.uploadData(AccountData.snapshot()) } } }
                    secondary("Keep this phone’s only") { Task { await run { try await account.uploadData(AccountData.snapshot()) } } }
                }
            } else {
                primary("Move to my account") { Task { await run { try await account.uploadData(AccountData.snapshot()) } } }
            }
            Button("Not now", action: onDone).font(Sketch.text(15, "SemiBold", relativeTo: .body)).foregroundStyle(Sketch.inkSoft).frame(minHeight: 44)
        }
        Text("Nothing is removed from this phone.").font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkFaint)
            .frame(maxWidth: .infinity)
    }

    private func box(_ title: String, _ summary: AccountData.Summary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Sketch.eyebrow).tracking(1.2).foregroundStyle(Sketch.inkFaint)
            ForEach(summary.rows, id: \.1) { symbol, label, count in
                HStack(spacing: 12) {
                    Image(systemName: symbol).foregroundStyle(Sketch.inkSoft).frame(width: 22)
                    Text(label).font(Sketch.text(16, relativeTo: .body))
                    Spacer()
                    Text("\(count)").font(Sketch.text(16, "Bold", relativeTo: .body)).monospacedDigit()
                }
            }
            if let home = summary.home {
                HStack(spacing: 12) { Image(systemName: "house").foregroundStyle(Sketch.inkSoft).frame(width: 22); Text("Home"); Spacer(); Text(home).foregroundStyle(Sketch.inkSoft) }
                    .font(Sketch.text(16, relativeTo: .body))
            }
        }
        .padding(18).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Sketch.text(17, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.paper)
                .frame(maxWidth: .infinity, minHeight: 54).background(Capsule().fill(Sketch.ink))
        }.buttonStyle(SketchPressStyle())
    }
    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Sketch.text(16, "Bold", relativeTo: .body)).foregroundStyle(Sketch.ink)
                .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().strokeBorder(Sketch.rule, lineWidth: 1))
        }.buttonStyle(SketchPressStyle())
    }

    private func check() async {
        local = AccountData.summary(of: AccountData.snapshot())
        do {
            remotePayload = try await account.downloadData()
            remote = remotePayload.map { AccountData.summary(of: $0) }
        } catch { self.error = "Couldn’t reach your account. You can try again later from Account." }
        if local.isEmpty && (remote?.isEmpty ?? true) { onDone(); return }
        stage = .choose
    }

    private func run(_ work: () async throws -> Void) async {
        stage = .working
        do { try await work(); error = nil; stage = .done }
        catch { self.error = error.localizedDescription; stage = .choose }
    }
}

/// After signing in outside onboarding: move your things, then the short tour.
struct WelcomeAfterSignIn: View {
    let onDone: () -> Void
    @State private var step = 0       // 0 move, 1-3 cards
    var body: some View {
        ZStack {
            Sketch.paper.ignoresSafeArea()
            if step == 0 {
                AccountMoveSheet { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = 1 } }
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { onDone() } label: {
                            Text("Skip").font(Sketch.text(14, "SemiBold", relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                                .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(Sketch.ink.opacity(0.06)))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(.horizontal, 12)
                    BriefCardStep(card: BriefCard.all[step - 1]).id(step)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    Button { step >= 3 ? onDone() : withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step += 1 } } label: {
                        Text(step >= 3 ? "Start exploring" : "Next").font(Sketch.text(17, "Bold", relativeTo: .headline)).foregroundStyle(Sketch.paper)
                            .frame(maxWidth: .infinity, minHeight: 54).background(Capsule().fill(Sketch.ink))
                    }
                    .buttonStyle(SketchPressStyle())
                    .padding(.horizontal, 24).padding(.bottom, 12)
                }
                .background(OnboardingBackdrop(step: step + 3))
            }
        }
    }
}
