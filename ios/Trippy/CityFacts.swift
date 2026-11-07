import Foundation
import CoreLocation

/// Country-level facts from free official sources:
/// - US State Department travel advisory level (1–4), refreshed daily.
/// - World Bank price level (PPP factor ÷ exchange rate, US = 1), refreshed monthly.
struct CountryFacts: Sendable {
    let advisoryLevel: Int?
    let advisoryTitle: String?
    let advisoryURL: URL?
    let priceLevel: Double?
    let priceYear: String?
}

actor CityFactsRepository {
    static let shared = CityFactsRepository()
    private var advisories: [String: (Int, String, URL?)]?
    private var prices: [String: (Double, String)]?

    private func cached(_ name: String, maxAge: TimeInterval, fetch: () async throws -> Data) async -> Data? {
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrippyFacts", isDirectory: true).appendingPathComponent(name)
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let fresh = (attrs?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) < maxAge } ?? false
        if fresh, let data = try? Data(contentsOf: file) { return data }
        if let data = try? await fetch() {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return data
        }
        return try? Data(contentsOf: file)  // stale beats nothing
    }

    private static func get(_ url: String) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!); request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func facts(countryCode: String) async -> CountryFacts {
        let code = countryCode.uppercased()
        if advisories == nil { advisories = await loadAdvisories() }
        if prices == nil { prices = await loadPrices() }
        let advisory = advisories?[code], price = prices?[code]
        return CountryFacts(advisoryLevel: advisory?.0, advisoryTitle: advisory?.1, advisoryURL: advisory?.2,
                            priceLevel: price?.0, priceYear: price?.1)
    }

    private struct Advisory: Decodable { let Title: String; let Link: String? }

    private func loadAdvisories() async -> [String: (Int, String, URL?)] {
        guard let data = await cached("advisories.json", maxAge: 86_400, fetch: { try await Self.get("https://cadataapi.state.gov/api/TravelAdvisories") }),
              let list = try? JSONDecoder().decode([Advisory].self, from: data) else { return [:] }
        let english = Locale(identifier: "en_US")
        func fold(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .replacingOccurrences(of: "&", with: "and").components(separatedBy: CharacterSet.letters.inverted).joined()
        }
        var byName: [String: String] = [:]
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            if let name = english.localizedString(forRegionCode: region.identifier) { byName[fold(name)] = region.identifier }
        }
        // State Department spellings that differ from Apple's.
        let aliases = ["burmamyanmar": "MM", "korearepublicof": "KR", "southkorea": "KR", "northkorea": "KP", "cotedivoire": "CI",
                       "thegambia": "GM", "thebahamas": "BS", "czechia": "CZ", "turkiye": "TR", "mainlandchina": "CN", "china": "CN",
                       "democraticrepublicofthecongo": "CD", "republicofthecongo": "CG", "macau": "MO", "hongkong": "HK",
                       "northmacedonia": "MK", "eswatini": "SZ", "caboverde": "CV", "timorleste": "TL", "israelthewestbankandgaza": "IL",
                       "unitedkingdom": "GB", "vatican": "VA", "holysee": "VA"]
        var out: [String: (Int, String, URL?)] = [:]
        for item in list {
            guard let range = item.Title.range(of: "Level "), let digit = item.Title[range.upperBound...].first?.wholeNumberValue else { continue }
            var name = String(item.Title[..<range.lowerBound])
            for cut in [" Travel Advisory", " - ", " -"] { name = name.replacingOccurrences(of: cut, with: "") }
            let key = fold(name)
            guard let code = aliases[key] ?? byName[key] else { continue }
            let label = item.Title[range.lowerBound...].split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            out[code] = (digit, label, item.Link.flatMap(URL.init(string:)))
        }
        return out
    }

    private struct Bank: Decodable {
        let value: Double?; let date: String; let country: Country
        struct Country: Decodable { let id: String }
    }

    private func loadPrices() async -> [String: (Double, String)] {
        func series(_ id: String) async -> [String: (Double, String)] {
            let url = "https://api.worldbank.org/v2/country/all/indicator/\(id)?format=json&mrnev=1&per_page=400"
            guard let data = await cached("wb-\(id).json", maxAge: 30 * 86_400, fetch: { try await Self.get(url) }),
                  let page = try? JSONSerialization.jsonObject(with: data) as? [Any], page.count > 1,
                  let rows = try? JSONDecoder().decode([Bank].self, from: JSONSerialization.data(withJSONObject: page[1])) else { return [:] }
            return Dictionary(rows.compactMap { r in r.value.map { (r.country.id, ($0, r.date)) } }, uniquingKeysWith: { a, _ in a })
        }
        let ppp = await series("PA.NUS.PPP"), fx = await series("PA.NUS.FCRF")
        var out: [String: (Double, String)] = [:]
        for (code, p) in ppp { if let f = fx[code], f.0 > 0 { out[code] = (p.0 / f.0, p.1) } }
        return out
    }
}

/// Famous places near a city, ranked by how many Wikipedia editions cover them
/// (Wikidata sitelinks). Free, global and a good proxy for "must-see".
actor FamousPlaces {
    static let shared = FamousPlaces()
    private var memory: [String: [ComposerPlace]] = [:]
    /// Settlements, districts, regions, events, organisations and transport networks: not visits.
    private static let skip: Set<String> = [
        "Q515", "Q1549591", "Q5119", "Q1637706", "Q15284", "Q2074737", "Q33146843", "Q484170", "Q747074", "Q262166", "Q1093829",
        "Q790344", "Q676050", "Q123705", "Q2983893", "Q188509", "Q3024240", "Q937876", "Q5503", "Q1656682", "Q4830453",
        "Q43229", "Q3918", "Q875538", "Q178706", "Q621985", "Q114609228", "Q26132862", "Q135976384", "Q159821", "Q27020041",
        "Q355304", "Q4022", "Q6256", "Q3624078", "Q35657", "Q107390", "Q10864048", "Q1221156", "Q3957", "Q532", "Q486972",
        "Q7930989", "Q1907114", "Q11032", "Q1248784", "Q124017602", "Q11446", "Q34442", "Q928830", "Q55488",
    ]

    private static let visitable: Set<String> = ["Q16970", "Q163687", "Q174782", "Q483453", "Q16560", "Q23413", "Q4989906",
                                                 "Q839954", "Q641226", "Q12280", "Q570116", "Q44539", "Q2977", "Q12518", "Q57821",
                                                 "Q1081138", "Q24398318", "Q162875", "Q15243209", "Q1440300"]
    private static let museums: Set<String> = ["Q33506", "Q207694", "Q16735822", "Q3329412", "Q588140", "Q1007870", "Q2668072",
                                               "Q1970365", "Q17431399", "Q839954", "Q2772772", "Q1060829"]
    private static let nature: Set<String> = ["Q22698", "Q22746", "Q1107656", "Q167346", "Q6017969", "Q54050", "Q40080", "Q8502",
                                              "Q46169", "Q3364016", "Q120560"]
    /// Planner category from Wikidata "instance of" types.
    static func category(_ types: Set<String>) -> String {
        if !types.isDisjoint(with: museums) { return "museum" }
        if !types.isDisjoint(with: nature) { return "nature" }
        return "attraction"
    }

    func places(near center: CLLocationCoordinate2D, city: String) async -> [ComposerPlace] {
        let key = String(format: "%.2f,%.2f", center.latitude, center.longitude)
        if let hit = memory[key] { return hit }
        let q = """
        SELECT ?item ?itemLabel ?loc ?links (GROUP_CONCAT(DISTINCT ?t) AS ?types) (SAMPLE(?img) AS ?image) (COUNT(?built) AS ?builtSignals) WHERE {
          SERVICE wikibase:around { ?item wdt:P625 ?loc . bd:serviceParam wikibase:center "Point(\(center.longitude) \(center.latitude))"^^geo:wktLiteral . bd:serviceParam wikibase:radius "9" . }
          ?item wikibase:sitelinks ?links . FILTER(?links > 15)
          OPTIONAL { ?item wdt:P31 ?t }
          OPTIONAL { ?item wdt:P18 ?img }
          OPTIONAL { ?item wdt:P1435|wdt:P84|wdt:P149 ?built }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        } GROUP BY ?item ?itemLabel ?loc ?links ORDER BY DESC(?links) LIMIT 90
        """
        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [URLQueryItem(name: "query", value: q)]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.setValue("Trippy/0.1 (trip planner prototype)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = (json["results"] as? [String: Any])?["bindings"] as? [[String: Any]] else { return [] }
        func value(_ row: [String: Any], _ k: String) -> String? { (row[k] as? [String: Any])?["value"] as? String }
        let cityKey = city.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var out: [ComposerPlace] = []
        for row in rows {
            guard let name = value(row, "itemLabel"), let loc = value(row, "loc") else { continue }
            let types = Set((value(row, "types") ?? "").split(separator: " ").map { String($0.split(separator: "/").last ?? "") })
            if !types.isDisjoint(with: Self.skip) { continue }
            // Visitable: a heritage listing, an architect or a style, or a known visitable kind.
            // Keeps out states, orders, treaties and institutions that merely have an address.
            let built = Int(value(row, "builtSignals") ?? "0") ?? 0
            if built == 0 && types.isDisjoint(with: Self.visitable) && types.isDisjoint(with: Self.museums) && types.isDisjoint(with: Self.nature) { continue }
            let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            // Unlabelled items come back as their Q-ID; events often slip through without a type.
            if name.hasPrefix("Q") && name.dropFirst().allSatisfy(\.isNumber) { continue }
            if folded == cityKey || ["olympic games", "championship", "summer olympics", "metro", "university"].contains(where: folded.contains) { continue }
            // "Point(lon lat)"
            let nums = loc.replacingOccurrences(of: "Point(", with: "").replacingOccurrences(of: ")", with: "").split(separator: " ").compactMap { Double($0) }
            guard nums.count == 2 else { continue }
            // Commons serves a resized copy of the item's main image.
            let image = value(row, "image").map { $0.replacingOccurrences(of: "http://", with: "https://") + "?width=480" }
            out.append(ComposerPlace(name: name, latitude: nums[1], longitude: nums[0], category: Self.category(types), imageURL: image))
            if out.count == 30 { break }
        }
        memory[key] = out
        return out
    }
}
