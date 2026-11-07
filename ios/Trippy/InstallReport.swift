import Foundation
import UIKit

/// An anonymous id for this install, sent with every request to the Trippy server so
/// the admin dashboard can count calls per install. It is a random UUID made on the
/// phone: no name, account or device identifier is involved, and deleting the app resets it.
enum TrippyInstall {
    private static let key = "trippy.install.id"
    static let id: String = {
        if let existing = UserDefaults.standard.string(forKey: key), UUID(uuidString: existing) != nil { return existing }
        let made = UUID().uuidString.lowercased()
        UserDefaults.standard.set(made, forKey: key)
        return made
    }()

    private static let lastReportKey = "trippy.install.lastReport"

    /// Counts only (trips, saved places, storage), at most every 6 hours. Trip contents never leave the phone.
    static func reportIfDue(baseURL: String, token: String, trips: Int, plannedTrips: Int, savedPlaces: Int, videos: Int) async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, let url = URL(string: baseURL + "/api/usage/report") else { return }
        let last = UserDefaults.standard.double(forKey: lastReportKey)
        guard Date().timeIntervalSince1970 - last > 6 * 3600 else { return }
        let megabytes = await Task.detached(priority: .background) { storageMegabytes() }.value
        let body: [String: Any] = [
            "trips": trips, "planned_trips": plannedTrips, "saved_places": savedPlaces, "videos": videos,
            "storage_mb": (megabytes * 10).rounded() / 10,
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "ios": UIDevice.current.systemVersion, "device": deviceModel(),
        ]
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(id, forHTTPHeaderField: "X-Trippy-Client")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let (_, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastReportKey)
        }
    }

    /// What the app keeps on the phone: its documents, support files, caches and settings.
    static func storageMegabytes() -> Double {
        let manager = FileManager.default
        var total: Int64 = 0
        let folders: [FileManager.SearchPathDirectory] = [.documentDirectory, .applicationSupportDirectory, .cachesDirectory, .libraryDirectory]
        var seen = Set<String>()
        for folder in folders {
            guard let root = manager.urls(for: folder, in: .userDomainMask).first,
                  let walker = manager.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { continue }
            for case let file as URL in walker where seen.insert(file.path).inserted {
                let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
            }
        }
        return Double(total) / 1_000_000
    }

    private static func deviceModel() -> String {
        var info = utsname(); uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
