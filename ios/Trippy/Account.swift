import SwiftUI
import PhotosUI
import CryptoKit
import Security
import AuthenticationServices

/// A Trippy account, through our own server only: the phone never holds a Supabase or
/// Google key. The server signs people in (Apple or a 6-digit email code), returns a
/// session, and checks it on every request; the admin role is decided on the server too.
@MainActor final class AccountSession: ObservableObject {
    static let shared = AccountSession()

    struct Session: Codable, Equatable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var email: String?
    }

    @Published private(set) var session: Session?
    @Published private(set) var isAdmin = false
    @Published private(set) var credits: Credits?

    /// What an account may still use this month (plans, videos). The server owns the numbers;
    /// later plans or subscriptions only change what it returns.
    struct Credits: Equatable {
        struct Item: Identifiable, Equatable {
            let id: String
            let label: String
            let used: Int
            let limit: Int
            var unlimited: Bool { limit < 0 }
        }
        let plan: String
        let items: [Item]
        func remaining(_ id: String) -> Int? {
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            return item.unlimited ? nil : max(0, item.limit - item.used)
        }
    }

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    private init() {
        session = SessionStore.load()
        if session != nil { Task { await refreshRole() } }
    }

    nonisolated static var baseURL: String {
        let host = (UserDefaults.standard.string(forKey: "trippy.bridgeHost") ?? "https://trippy-research-89fm.onrender.com/")
            .trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return host.lowercased().hasPrefix("http") ? host : "http://\(host):8080"
    }

    /// Sent with every request to the Trippy server once signed in.
    nonisolated static var header: String? {
        guard let session = SessionStore.load() else { return nil }
        return session.accessToken
    }

    // MARK: Sign in

    func sendEmailCode(_ email: String) async throws {
        _ = try await post("/api/auth/email/start", ["email": email])
    }

    func verifyEmail(_ email: String, code: String) async throws {
        accept(try await post("/api/auth/email/verify", ["email": email, "code": code]))
        await refreshRole()
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        accept(try await post("/api/auth/apple", ["id_token": idToken, "nonce": nonce]))
        await refreshRole()
    }

    /// Google through Supabase, in the system browser sheet, with PKCE: the code is exchanged on
    /// our server, and only this phone knows the verifier.
    func signInWithGoogle(using web: WebAuthenticationSession) async throws {
        let verifier = Self.makeNonce() + Self.makeNonce()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let start = try await post("/api/auth/google/start", ["code_challenge": challenge, "redirect_to": Self.callback])
        guard let address = start["url"] as? String, let url = URL(string: address) else { throw AccountError(status: 502, code: "auth_unavailable") }
        let returned: URL
        do { returned = try await web.authenticate(using: url, callbackURLScheme: "trippy", preferredBrowserSession: .ephemeral) }
        catch { throw AccountError(status: -1, code: "cancelled") }
        guard let code = URLComponents(url: returned, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AccountError(status: 400, code: "invalid_code") }
        accept(try await post("/api/auth/exchange", ["code": code, "code_verifier": verifier]))
        await refreshRole()
    }

    static let callback = "trippy://auth-callback"

    func signOut() {
        session = nil; isAdmin = false; credits = nil
        SessionStore.save(nil)
    }

    /// Deletes the account on the server (as the App Store requires) and signs out here.
    func deleteAccount() async throws {
        try await ensureFresh()
        _ = try await post("/api/auth/delete", [:], authorized: true)
        signOut()
    }

    /// Asks the server who this is; only the server can say "admin".
    func refreshRole() async {
        do {
            try await ensureFresh()
            let me = try await get("/api/me")
            isAdmin = me["admin"] as? Bool ?? false
            if let raw = me["credits"] as? [String: Any] {
                let items = (raw["items"] as? [[String: Any]] ?? []).compactMap { item -> Credits.Item? in
                    guard let id = item["id"] as? String else { return nil }
                    return .init(id: id, label: item["label"] as? String ?? id, used: (item["used"] as? NSNumber)?.intValue ?? 0,
                                 limit: (item["limit"] as? NSNumber)?.intValue ?? 0)
                }
                credits = Credits(plan: raw["plan"] as? String ?? "free", items: items)
            }
            if var current = session, let email = me["email"] as? String { current.email = email; session = current; SessionStore.save(current) }
        } catch let error as AccountError where error.status == 401 {
            signOut()
        } catch {
            // Offline: keep the last known session, but no admin screen without the server's word.
            isAdmin = false
        }
    }

    func ensureFresh() async throws {
        guard let current = session, current.expiresAt.timeIntervalSinceNow < 120 else { return }
        accept(try await post("/api/auth/refresh", ["refresh_token": current.refreshToken]))
    }

    private func accept(_ body: [String: Any]) {
        guard let access = body["access_token"] as? String, let refresh = body["refresh_token"] as? String,
              let user = body["user"] as? [String: Any], let id = user["id"] as? String else { return }
        let expires = (body["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let new = Session(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expires),
                          userID: id, email: user["email"] as? String)
        let fresh = session == nil
        session = new
        SessionStore.save(new)
        // A new sign-in (not a token refresh): the app offers to move this phone's things, then the tour.
        if fresh { NotificationCenter.default.post(name: .accountSignedIn, object: nil) }
    }

    // MARK: Network

    struct AccountError: LocalizedError {
        let status: Int
        let code: String
        var errorDescription: String? {
            switch code {
            case "invalid_code": "That code didn’t work. Check it or ask for a new one."
            case "too_many_requests": "Too many tries. Wait a minute and try again."
            case "accounts_not_configured": "Accounts aren’t switched on on the server yet."
            case "invalid_email": "That email doesn’t look right."
            case "cancelled": "Sign-in was cancelled."
            case "provider_not_enabled": "Google sign-in isn’t switched on on the server yet."
            case "credits_used": "You’ve used this month’s free credits."
            case "account_required": "This needs a Trippy account."
            default: status == 0 ? "No connection. Try again when you’re online." : "Sign-in didn’t work (\(code))."
            }
        }
    }

    private func request(_ path: String, method: String, body: [String: Any]?, authorized: Bool) async throws -> [String: Any] {
        guard let url = URL(string: Self.baseURL + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue(TrippyInstall.id, forHTTPHeaderField: "X-Trippy-Client")
        if authorized, let token = session?.accessToken { request.setValue(token, forHTTPHeaderField: "X-Trippy-Session") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw AccountError(status: 0, code: "offline") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(status) else { throw AccountError(status: status, code: json["error"] as? String ?? "http_\(status)") }
        return json
    }
    /// An authorised call with this account's session (account data, and later sync).
    func send(_ path: String, method: String, body: [String: Any]?) async throws -> [String: Any] {
        try await request(path, method: method, body: body, authorized: true)
    }
    private func post(_ path: String, _ body: [String: Any], authorized: Bool = false) async throws -> [String: Any] {
        try await request(path, method: "POST", body: body, authorized: authorized)
    }
    private func get(_ path: String) async throws -> [String: Any] {
        try await request(path, method: "GET", body: nil, authorized: true)
    }

    // MARK: Apple nonce

    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The session in the Keychain, this device only.
private enum SessionStore: Sendable {
    private static let service = "com.dimitrisymeonidis.trippy.session"
    static func load() -> AccountSession.Session? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AccountSession.Session.self, from: data)
    }
    static func save(_ session: AccountSession.Session?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

// MARK: - Profile

/// The profile photo and name stay on this phone.
enum ProfileStore {
    static let nameKey = "trippy.profile.name"
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("profile-photo.jpg")
    }
    static func photo() -> UIImage? { UIImage(contentsOfFile: file.path) }
    static func save(_ image: UIImage?) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let image, let data = image.preparingThumbnail(of: CGSize(width: 400, height: 400))?.jpegData(compressionQuality: 0.85) {
            try? data.write(to: file, options: .atomic)
        } else { try? FileManager.default.removeItem(at: file) }
        NotificationCenter.default.post(name: .profileChanged, object: nil)
    }
}

extension Notification.Name { static let profileChanged = Notification.Name("trippy.profileChanged") }

/// A round photo, or initials on a warm colour.
struct ProfileAvatar: View {
    var size: CGFloat = 40
    @ObservedObject private var account = AccountSession.shared
    @AppStorage(ProfileStore.nameKey) private var name = ""
    @State private var photo = ProfileStore.photo()
    private var initials: String {
        let source = name.isEmpty ? (account.email ?? "") : name
        let parts = source.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
    var body: some View {
        Group {
            if let photo { Image(uiImage: photo).resizable().scaledToFill() }
            else if !initials.isEmpty {
                Text(initials).font(.system(size: size * 0.38, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Sketch.coral.gradient)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.42)).foregroundStyle(Sketch.inkSoft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Sketch.paperDeep)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .onReceive(NotificationCenter.default.publisher(for: .profileChanged)) { _ in photo = ProfileStore.photo() }
        .accessibilityHidden(true)
    }
}

// MARK: - Account (replaces Settings)

/// Everything about you in one place: who you are, your plan and its limits, your home and
/// places, the app's settings, and the admin dashboard for admins.
struct AccountHub: View {
    var onConnections: (() -> Void)? = nil
    @ObservedObject private var account = AccountSession.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProfileStore.nameKey) private var name = ""
    @AppStorage("trippy.native.darkMode") private var darkMode = false
    @AppStorage("trippy.native.visitedPlaces.v1") private var visited = "[]"
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showSignIn = false
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var error: String?
    @State private var home = HomeProfileStore.load()
    @State private var showMove = false

    /// Debug builds (Xcode) and admin accounts get the tools to replay setup and sign-in.
    private var showsDeveloper: Bool {
        #if DEBUG
        return true
        #else
        return account.isAdmin
        #endif
    }

    private var countries: Int { Set(VisitedPlace.decode(visited).compactMap(\.countryCode)).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    planCard
                    group("Your Trippy") {
                        NavigationLink { HomeEditView { home = HomeProfileStore.load() } } label: { row("house", "Home", value: home?.label ?? "Not set") }
                        separator
                        row("globe.europe.africa", "Places you’ve been", value: countries == 0 ? "None yet" : "\(countries) \(countries == 1 ? "country" : "countries")", chevron: false)
                        if account.isSignedIn {
                            separator
                            Button { showMove = true } label: {
                                row("arrow.up.doc", "Move this phone’s things", value: UserDefaults.standard.string(forKey: AccountData.movedKey) == account.session?.userID ? "Done" : "To your account")
                            }
                        }
                    }
                    group("Settings") {
                        Toggle(isOn: $darkMode) { rowLabel("moon", "Dark appearance") }.tint(Sketch.ink).padding(.horizontal, 16).frame(minHeight: 52)
                        separator
                        Button { NotificationOpener.open(UIApplication.openSettingsURLString) } label: { row("bell", "Notifications & location", value: "iOS Settings") }
                    }
                    if showsDeveloper {
                        group("Developer") {
                            Button { dismiss(); NotificationCenter.default.post(name: .replayOnboarding, object: nil) } label: { row("arrow.counterclockwise", "Replay setup", value: nil) }
                            separator
                            Button { showSignIn = true } label: { row("person.badge.key", "Show sign-in", value: account.isSignedIn ? "Signed in" : nil) }
                            separator
                            Button { dismiss(); NotificationCenter.default.post(name: .accountSignedIn, object: nil) } label: { row("sparkles.rectangle.stack", "Show welcome and tour", value: nil) }
                            if let onConnections {
                                separator
                                Button { dismiss(); onConnections() } label: { row("wrench.and.screwdriver", "Server connection", value: nil) }
                            }
                            separator
                            NavigationLink { CostCalculatorView(baseURL: AccountSession.baseURL) } label: { row("function", "Cost calculator", value: "Costs, income, users") }
                        }
                    }
                    if account.isAdmin {
                        group("Admin") {
                            NavigationLink { AdminView(baseURL: AccountSession.baseURL) } label: { row("chart.bar.xaxis", "Dashboard", value: "Usage, limits, installs") }
                            separator
                            NavigationLink { CostCalculatorView(baseURL: AccountSession.baseURL) } label: { row("function", "Cost calculator", value: "Live model") }
                        }
                    }
                    if account.isSignedIn {
                        group(nil) {
                            Button { confirmSignOut = true } label: { row("rectangle.portrait.and.arrow.right", "Sign out", value: nil, chevron: false) }
                            separator
                            Button { confirmDelete = true } label: { row("trash", "Delete account", value: nil, chevron: false, destructive: true) }
                        }
                    }
                    if let error { Text(error).font(Sketch.text(14, relativeTo: .footnote)).foregroundStyle(Sketch.coral) }
                    Text("Trippy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(Sketch.text(12, relativeTo: .caption)).foregroundStyle(Sketch.inkFaint).padding(.top, 4)
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .background(Sketch.paper.ignoresSafeArea())
            .navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await account.refreshRole() }
            .sheet(isPresented: $showSignIn) { SignInSheet() }
            .sheet(isPresented: $showMove) { AccountMoveSheet { showMove = false } }
            .onChange(of: pickedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) { ProfileStore.save(image) }
                }
            }
            .confirmationDialog("Sign out of Trippy?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { account.signOut() }
            } message: { Text("Your map and trips stay on this phone.") }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task { do { try await account.deleteAccount() } catch { self.error = error.localizedDescription } }
                }
            } message: { Text("This removes your account from Trippy’s server and can’t be undone. Trips on this phone stay.") }
        }
        .tint(Sketch.ink)
    }

    // Photo, name, email.
    private var header: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                ProfileAvatar(size: 92)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.paper)
                            .frame(width: 28, height: 28).background(Circle().fill(Sketch.ink)).overlay(Circle().strokeBorder(Sketch.paper, lineWidth: 2))
                    }
            }
            .accessibilityLabel("Change profile photo")
            TextField("Your name", text: $name).font(Sketch.display(.title2, weight: .bold)).multilineTextAlignment(.center)
                .textContentType(.name).submitLabel(.done)
            if account.isSignedIn {
                HStack(spacing: 6) {
                    Text(account.email ?? "Signed in").font(Sketch.text(15, relativeTo: .subheadline)).foregroundStyle(Sketch.inkSoft)
                    if account.isAdmin {
                        Text("ADMIN").font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(Sketch.paper)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(Sketch.sage))
                    }
                }
            } else {
                Button { showSignIn = true } label: {
                    Text("Sign in or create an account").font(Sketch.text(15, "Bold", relativeTo: .subheadline)).foregroundStyle(Sketch.paper)
                        .padding(.horizontal, 18).frame(minHeight: 44).background(Capsule().fill(Sketch.ink))
                }
                .buttonStyle(SketchPressStyle())
            }
        }
        .padding(.top, 12)
    }

    // The plan and what's left this month; opens the full plan page.
    private var planCard: some View {
        NavigationLink { PlanPage() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YOUR PLAN").font(Sketch.eyebrow).tracking(1.2).foregroundStyle(Sketch.inkFaint)
                        Text(account.isSignedIn ? (account.credits?.plan.capitalized ?? "Free") : "On this phone").font(Sketch.display(.title3, weight: .bold))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Sketch.inkFaint)
                }
                if let credits = account.credits {
                    ForEach(credits.items) { item in LimitBar(item: item) }
                } else {
                    Text(account.isSignedIn ? "Loading your limits…" : "Sign in for plans, video reading and free monthly credits.")
                        .font(Sketch.text(14, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).multilineTextAlignment(.leading)
                }
            }
            .foregroundStyle(Sketch.ink)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Sketch.rule, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var separator: some View { Rectangle().fill(Sketch.rule).frame(height: 0.5).padding(.leading, 52) }

    private func group<Content: View>(_ title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title.uppercased()).font(Sketch.eyebrow).tracking(1.2).foregroundStyle(Sketch.inkFaint).padding(.leading, 4) }
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sketch.card))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Sketch.rule, lineWidth: 0.7))
        }
    }

    private func rowLabel(_ symbol: String, _ title: String, destructive: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(destructive ? Sketch.coral : Sketch.inkSoft).frame(width: 22)
            Text(title).font(Sketch.text(16, relativeTo: .body)).foregroundStyle(destructive ? Sketch.coral : Sketch.ink)
        }
    }

    private func row(_ symbol: String, _ title: String, value: String?, chevron: Bool = true, destructive: Bool = false) -> some View {
        HStack(spacing: 10) {
            rowLabel(symbol, title, destructive: destructive)
            Spacer(minLength: 8)
            if let value { Text(value).font(Sketch.text(15, relativeTo: .subheadline)).foregroundStyle(Sketch.inkFaint).lineLimit(1) }
            if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.inkFaint) }
        }
        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
    }
}

enum NotificationOpener {
    @MainActor static func open(_ address: String) { if let url = URL(string: address) { UIApplication.shared.open(url) } }
}

/// One limit: what's used of what's included this month.
struct LimitBar: View {
    let item: AccountSession.Credits.Item
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.label).font(Sketch.text(15, "SemiBold", relativeTo: .subheadline))
                Spacer()
                Text(item.unlimited ? "Unlimited" : "\(max(0, item.limit - item.used)) of \(item.limit) left")
                    .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkSoft).monospacedDigit()
            }
            if !item.unlimited {
                GeometryReader { bar in
                    Capsule().fill(Sketch.paperDeep)
                        .overlay(alignment: .leading) {
                            Capsule().fill(item.used >= item.limit ? Sketch.coral : Sketch.sage)
                                .frame(width: bar.size.width * min(1, CGFloat(item.used) / CGFloat(max(item.limit, 1))))
                        }
                }
                .frame(height: 6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan page

/// What's included, what's used, and what's coming. Built so paid plans slot in later:
/// the numbers all come from the server (`/api/me` credits).
struct PlanPage: View {
    @ObservedObject private var account = AccountSession.shared
    @State private var showSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.isSignedIn ? (account.credits?.plan.capitalized ?? "Free") : "On this phone")
                        .font(Sketch.display(.largeTitle, weight: .bold))
                    Text(renewal).font(Sketch.text(16, "Medium", relativeTo: .body)).foregroundStyle(Sketch.inkSoft)
                }
                if let credits = account.credits {
                    VStack(spacing: 16) { ForEach(credits.items) { LimitBar(item: $0) } }
                        .padding(18).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Sketch.card))
                }
                VStack(spacing: 12) {
                    tier("Free", price: "€0", lines: ["Map, saves and places you’ve been", "\(limit("plans", fallback: 3)) plans a month", "\(limit("videos", fallback: 20)) TikToks read a month"],
                         current: account.isSignedIn && account.credits?.plan != "admin")
                    tier("Pro", price: "Soon", lines: ["More plans and video reading", "Credits for each trip", "Everything in Free"], current: false, soon: true)
                }
                if !account.isSignedIn {
                    Button { showSignIn = true } label: {
                        Text("Sign in to get your free credits").font(Sketch.text(16, "Bold", relativeTo: .body)).foregroundStyle(Sketch.paper)
                            .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(Sketch.ink))
                    }
                    .buttonStyle(SketchPressStyle())
                }
                Text("Without an account, your map, saves and places keep working on this phone.")
                    .font(Sketch.text(13, relativeTo: .footnote)).foregroundStyle(Sketch.inkFaint)
            }
            .padding(20)
        }
        .background(Sketch.paper.ignoresSafeArea())
        .navigationTitle("Plan").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSignIn) { SignInSheet() }
        .task { await account.refreshRole() }
    }

    private var renewal: String {
        guard account.isSignedIn else { return "Plans and video reading need an account." }
        let next = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now))
            .flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
        return next.map { "Credits renew on \($0.formatted(.dateTime.day().month(.wide)))." } ?? "Credits renew monthly."
    }

    private func limit(_ id: String, fallback: Int) -> String {
        guard let item = account.credits?.items.first(where: { $0.id == id }) else { return "\(fallback)" }
        return item.unlimited ? "Unlimited" : "\(item.limit)"
    }

    private func tier(_ name: String, price: String, lines: [String], current: Bool, soon: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).font(Sketch.display(.title3, weight: .bold))
                if current {
                    Text("CURRENT").font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(Sketch.paper)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(Sketch.ink))
                }
                Spacer()
                Text(price).font(Sketch.text(16, "Bold", relativeTo: .body)).foregroundStyle(soon ? Sketch.inkFaint : Sketch.ink)
            }
            ForEach(lines, id: \.self) { line in
                Label { Text(line).font(Sketch.text(15, relativeTo: .subheadline)) } icon: { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Sketch.sage) }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Sketch.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(current ? Sketch.ink : Sketch.rule, lineWidth: current ? 1.5 : 0.7))
        .opacity(soon ? 0.7 : 1)
    }
}

/// "Where you live", from Settings.
struct HomeEditView: View {
    let onSave: () -> Void
    @State private var home = HomeProfileStore.load() ?? HomeProfile()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HomeStep(home: $home)
            .background(Sketch.paper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { HomeProfileStore.save(home); onSave(); dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The onboarding's account step on its own, for Settings.
struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            AccountStep { dismiss() }.background(Sketch.paper)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
