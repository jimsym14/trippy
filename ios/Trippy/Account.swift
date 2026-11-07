import SwiftUI
import CryptoKit
import Security

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

    func signOut() {
        session = nil; isAdmin = false
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
        session = new
        SessionStore.save(new)
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

// MARK: - Account screen (Settings)

struct AccountView: View {
    @ObservedObject private var account = AccountSession.shared
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var showSignIn = false
    @State private var home = HomeProfileStore.load()

    var body: some View {
        Form {
            if account.isSignedIn {
                Section {
                    LabeledContent("Signed in as", value: account.email ?? "Apple ID")
                    if account.isAdmin { Label("Admin", systemImage: "lock.shield.fill").foregroundStyle(Sketch.sage) }
                }
                if account.isAdmin {
                    Section { NavigationLink { AdminView(baseURL: AccountSession.baseURL) } label: { Label("Admin dashboard", systemImage: "chart.bar.xaxis") } }
                }
            } else {
                Section {
                    Button { showSignIn = true } label: { Label("Sign in or create an account", systemImage: "person.crop.circle.badge.plus") }
                } footer: { Text("Optional. Backs up your trips and lets you use Trippy on a new phone.") }
            }
            Section {
                NavigationLink { HomeEditView { home = HomeProfileStore.load() } } label: {
                    LabeledContent("Where you live", value: home?.label ?? "Not set")
                }
            } header: { Text("Home") } footer: { Text("Your map opens here and shows a home pin.") }
            if account.isSignedIn {
                Section {
                    Button("Sign out") { account.signOut() }
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                } footer: { Text("Deleting removes your account from Trippy’s server. Trips on this phone stay here.") }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Account")
        .task { await account.refreshRole() }
        .sheet(isPresented: $showSignIn) { SignInSheet() }
        .confirmationDialog("Delete your Trippy account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { do { try await account.deleteAccount() } catch { self.error = error.localizedDescription } }
            }
        } message: { Text("This can’t be undone.") }
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
