import Foundation
import CoreLocation

// MARK: - Destination catalog
//
// A hand-kept list of places worth a trip, with what each is good for. It lives in the app, so
// "Where next?" and the journey planner cost nothing to run and work offline.
// Costs and best months are editorial estimates, not live prices or forecasts.

/// What a place is good for. Each destination scores 0–3 on every trait.
enum TripTrait: Int, CaseIterable, Identifiable {
    case culture, food, nightlife, beach, nature, adventure, romance, family, shopping, quiet
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .culture: "Culture & history"; case .food: "Food"; case .nightlife: "Nightlife"; case .beach: "Beach & sea"
        case .nature: "Nature & views"; case .adventure: "Adventure"; case .romance: "Romantic"; case .family: "Easy with kids"
        case .shopping: "Markets & shops"; case .quiet: "Off the beaten path"
        }
    }
    var short: String {
        switch self {
        case .culture: "culture"; case .food: "food"; case .nightlife: "nightlife"; case .beach: "beaches"; case .nature: "nature"
        case .adventure: "adventure"; case .romance: "romance"; case .family: "family days"; case .shopping: "shopping"; case .quiet: "few crowds"
        }
    }
    var symbol: String {
        switch self {
        case .culture: "building.columns"; case .food: "fork.knife"; case .nightlife: "wineglass"; case .beach: "beach.umbrella"
        case .nature: "mountain.2"; case .adventure: "figure.hiking"; case .romance: "heart"; case .family: "figure.2.and.child.holdinghands"
        case .shopping: "bag"; case .quiet: "leaf"
        }
    }
    /// The planner interest this trait maps to when a trip is created.
    var interest: String? {
        switch self {
        case .culture: "sights"; case .food: "food"; case .nightlife: "nightlife"; case .beach, .nature, .adventure: "outdoors"
        case .shopping: "shopping"; default: nil
        }
    }
}

struct Destination: Identifiable, Hashable {
    let name: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    /// 1 cheap … 4 expensive, for a day on the ground.
    let cost: Int
    /// 1 small town or island, 2 city, 3 big city: how many days it fills.
    let size: Int
    /// Months (1–12) when it is at its best.
    let months: Set<Int>
    let traits: [Float]
    /// "g" reachable overland, "f" needs a ferry, "a" realistically by air only.
    let access: Character

    var id: String { name + "|" + countryCode }
    /// The town to plan around: "Bergen & fjords" plans in Bergen.
    var planName: String { name.components(separatedBy: " & ").first ?? name }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var country: String { Locale(identifier: "en").localizedString(forRegionCode: countryCode) ?? countryCode }
    var continent: String { WorldContinentCatalog.name(for: countryCode) }
    var flag: String {
        countryCode.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }
    /// A typical day per person in euros: a mid-range bed, meals and getting around.
    var dailyCost: Int { [55, 90, 140, 210][min(max(cost, 1), 4) - 1] }
    func trait(_ t: TripTrait) -> Float { traits[t.rawValue] }
    /// The strongest traits, best first.
    var highlights: [TripTrait] {
        TripTrait.allCases.filter { trait($0) >= 2 }.sorted { trait($0) > trait($1) }
    }
    static func == (a: Destination, b: Destination) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum DestinationCatalog {
    static let all: [Destination] = table.split(separator: "\n").compactMap { line in
        let f = line.split(separator: "|").map(String.init)
        guard f.count == 9, let lat = Double(f[2]), let lon = Double(f[3]), let cost = Int(f[4]), let size = Int(f[5]), f[7].count == 10 else { return nil }
        let months = Set(f[6].compactMap { $0.hexDigitValue }.filter { (1...12).contains($0) })
        return Destination(name: f[0], countryCode: f[1], latitude: lat, longitude: lon, cost: cost, size: size, months: months,
                           traits: f[7].compactMap { $0.wholeNumberValue.map(Float.init) }, access: f[8].first ?? "g")
    }

    static func named(_ name: String) -> Destination? {
        let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return all.first { key.hasPrefix($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
    }
    static func nearest(to coordinate: CLLocationCoordinate2D, within km: Double) -> Destination? {
        all.map { ($0, Geo.km(coordinate, $0.coordinate)) }.filter { $0.1 <= km }.min { $0.1 < $1.1 }?.0
    }

    // name|country|lat|lon|cost|size|best months (1-9, a=Oct, b=Nov, c=Dec)|culture food nightlife beach nature adventure romance family shopping quiet|access
    private static let table = """
    Lisbon|PT|38.72|-9.14|2|3|3456789a|3320112221|g
    Porto|PT|41.15|-8.61|2|2|456789a|3321112111|g
    Algarve|PT|37.02|-7.93|2|2|56789a|1113221301|g
    Madeira|PT|32.65|-16.91|2|2|3456789ab|1201331202|a
    Azores|PT|37.74|-25.67|2|1|56789|1100331203|a
    Madrid|ES|40.42|-3.70|2|3|3456ab9a|3330001231|g
    Barcelona|ES|41.39|2.17|3|3|3456789a|3332112230|g
    Seville|ES|37.39|-5.98|2|2|345ab9a|3320102111|g
    Granada|ES|37.18|-3.60|2|2|3456 9ab|3210212102|g
    Valencia|ES|39.47|-0.38|2|2|3456789a|2322102211|g
    San Sebastian|ES|43.32|-1.98|3|1|56789|2312212101|g
    Bilbao|ES|43.26|-2.93|2|2|56789|3310101111|g
    Mallorca|ES|39.57|2.65|3|2|56789a|1223221301|f
    Ibiza|ES|38.91|1.43|4|1|6789|0133102000|f
    Tenerife|ES|28.29|-16.63|2|2|123456789abc|1113331301|a
    Paris|FR|48.86|2.35|4|3|456789ac|3320003230|g
    Lyon|FR|45.76|4.84|3|2|456789|2310102121|g
    Nice|FR|43.70|7.27|3|2|56789|2212212211|g
    Bordeaux|FR|44.84|-0.58|3|2|56789a|2310103111|g
    Marseille|FR|43.30|5.37|2|2|56789|2222211111|g
    Strasbourg|FR|48.58|7.75|3|1|56789c|3200103112|g
    Corsica|FR|42.04|9.01|3|1|6789|1103332203|f
    Chamonix|FR|45.92|6.87|4|1|12367 89c|0101331202|g
    London|GB|51.51|-0.13|4|3|456789c|3330002330|g
    Edinburgh|GB|55.95|-3.19|3|2|56789|3221211211|g
    Inverness & Highlands|GB|57.12|-4.71|3|1|56789|1100331103|g
    Bath & Cotswolds|GB|51.38|-2.36|3|1|456789|3100202202|g
    Dublin|IE|53.35|-6.26|4|2|56789|2231101110|f
    Galway & Wild Atlantic Way|IE|53.27|-9.05|3|1|56789|1211331103|f
    Amsterdam|NL|52.37|4.90|4|2|456789|3231002220|g
    Brussels|BE|50.85|4.35|3|2|456789c|2320001121|g
    Bruges|BE|51.21|3.22|3|1|456789c|3200003201|g
    Berlin|DE|52.52|13.40|3|3|56789c|3331001220|g
    Munich|DE|48.14|11.58|3|3|56789ac|3221111221|g
    Hamburg|DE|53.55|9.99|3|3|56789|2231001121|g
    Cologne|DE|50.94|6.96|3|2|56789c|2221001121|g
    Dresden|DE|51.05|13.74|2|2|56789c|3110102112|g
    Freiburg & Black Forest|DE|48.00|8.20|3|1|56789a|1100321303|g
    Vienna|AT|48.21|16.37|3|3|456789c|3320003221|g
    Salzburg|AT|47.80|13.04|3|1|56789c|3200213201|g
    Innsbruck|AT|47.27|11.39|3|1|12367 89c|1101331202|g
    Zurich|CH|47.37|8.54|4|2|56789c|2211201120|g
    Lucerne & Alps|CH|47.05|8.31|4|1|56789|1100332302|g
    Zermatt|CH|46.02|7.75|4|1|12367 89|0100332102|g
    Rome|IT|41.90|12.50|3|3|3456 9ab|3320003220|g
    Florence|IT|43.77|11.26|3|2|3456 9a|3310103220|g
    Venice|IT|45.44|12.32|4|2|345 9ab|3200003110|g
    Milan|IT|45.46|9.19|3|3|3456 9a|2330001130|g
    Naples|IT|40.85|14.27|2|3|3456 9a|3320101111|g
    Amalfi Coast|IT|40.63|14.60|4|1|56 9a|1203223101|g
    Cinque Terre|IT|44.13|9.71|3|1|456 9a|1203322101|g
    Bologna|IT|44.49|11.34|2|2|3456 9a|2320002112|g
    Turin|IT|45.07|7.69|2|2|3456 9a|3310102112|g
    Puglia|IT|40.35|18.17|2|2|56789a|2313202202|g
    Sicily|IT|37.60|14.02|2|3|456 9a|3313312202|f
    Sardinia|IT|40.12|9.01|3|2|6789|1203322303|f
    Cortina & Dolomites|IT|46.41|11.84|3|1|12367 89|0200332203|g
    Lake Como|IT|46.02|9.26|4|1|56789|1200303201|g
    Athens|GR|37.98|23.73|2|3|3456 9ab|3331102211|g
    Thessaloniki|GR|40.64|22.94|2|2|3456 9ab|2331101112|g
    Santorini|GR|36.39|25.46|4|1|56 9a|1203203000|f
    Mykonos|GR|37.45|25.33|4|1|6789|0133102010|f
    Crete|GR|35.24|24.81|2|3|56789a|2313322302|f
    Naxos & Paros|GR|37.10|25.38|2|1|6789|1213212303|f
    Corfu|GR|39.62|19.92|2|2|56789|2213212302|f
    Rhodes|GR|36.43|28.22|2|2|56789a|3213212301|f
    Zagori & Meteora|GR|39.72|21.63|1|1|456 9a|2200332103|g
    Nafplio & Peloponnese|GR|37.07|22.43|2|2|456 9a|3213312203|g
    Milos|GR|36.72|24.44|3|1|6789|0203313103|f
    Istanbul|TR|41.01|28.98|2|3|456 9ab|3330002231|g
    Cappadocia|TR|38.64|34.83|2|1|456 9a|2100333202|g
    Fethiye & Turquoise Coast|TR|36.62|29.12|2|2|56789a|2213322202|g
    Dubrovnik|HR|42.65|18.09|3|1|56 9a|3213213100|g
    Split & islands|HR|43.51|16.44|3|2|6789|2223222201|g
    Zagreb|HR|45.81|15.98|2|2|56789c|2220101112|g
    Plitvice & Istria|HR|45.24|13.94|2|1|56789|1203322303|g
    Ljubljana & Bled|SI|46.05|14.51|2|1|56789|2210322203|g
    Kotor Bay|ME|42.42|18.77|2|1|56789|2112322203|g
    Sarande & Albanian Riviera|AL|40.10|19.75|1|1|6789|1113322103|g
    Tirana|AL|41.33|19.82|1|2|456 9a|2221101113|g
    Sarajevo & Mostar|BA|43.86|18.41|1|2|56789|3210211113|g
    Belgrade|RS|44.79|20.45|1|3|56789|2231001112|g
    Sofia|BG|42.70|23.32|1|2|56789|2221201112|g
    Bucharest|RO|44.43|26.10|1|3|56789|2231001112|g
    Brasov & Transylvania|RO|45.65|25.60|1|2|56789a|3100322203|g
    Budapest|HU|47.50|19.04|2|3|456789c|3331002121|g
    Prague|CZ|50.08|14.44|2|3|456789c|3231003121|g
    Krakow|PL|50.06|19.94|1|2|56789c|3221002112|g
    Warsaw|PL|52.23|21.01|2|3|56789|2221001122|g
    Gdansk|PL|54.35|18.65|1|2|6789|2211101212|g
    Zakopane & Tatras|PL|49.30|19.95|1|1|12 6789|1100331203|g
    Bratislava|SK|48.15|17.11|2|1|56789|2121001112|g
    Copenhagen|DK|55.68|12.57|4|2|56789|3321002320|g
    Stockholm|SE|59.33|18.07|4|3|6789|3221202320|g
    Gothenburg|SE|57.71|11.97|3|2|6789|2221201212|g
    Oslo|NO|59.91|10.75|4|2|6789|2211301210|g
    Bergen & fjords|NO|60.39|5.32|4|1|6789|1100333203|g
    Lofoten|NO|68.21|13.61|4|1|23 6789|0100333103|g
    Tromso|NO|69.65|18.96|4|1|123 bc|1100333203|a
    Helsinki|FI|60.17|24.94|3|2|6789|2221201221|g
    Rovaniemi & Lapland|FI|66.50|25.73|4|1|123 c|0100332303|a
    Tallinn|EE|59.44|24.75|2|1|56789c|3121002112|g
    Riga|LV|56.95|24.11|2|2|56789|2121001112|g
    Vilnius|LT|54.69|25.28|1|2|56789|2121002113|g
    Reykjavik & Golden Circle|IS|64.15|-21.94|4|1|6789|1111333201|a
    Vik & Iceland Ring Road|IS|64.96|-19.02|4|2|6789|0100333103|a
    Malta|MT|35.90|14.51|2|2|456 9a|3212211201|a
    Cyprus|CY|34.92|33.63|2|2|456 9ab|2213211301|a
    Tbilisi|GE|41.72|44.83|1|2|456 9a|3321212113|a
    Yerevan|AM|40.18|44.51|1|2|56 9a|3210211103|a
    Marrakech|MA|31.63|-7.99|1|2|345 abc|3310222131|a
    Fes & Chefchaouen|MA|34.03|-5.00|1|2|345 9ab|3200212123|a
    Essaouira & Atlas|MA|31.51|-9.77|1|1|3456 9ab|2112332113|a
    Tunis & Sidi Bou Said|TN|36.81|10.18|1|2|345 9ab|3112102112|a
    Cairo & Nile|EG|30.04|31.24|1|3|123 abc|3200122221|a
    Hurghada & Red Sea|EG|27.26|33.81|1|1|123456 9abc|0013232300|a
    Petra & Jordan|JO|30.33|35.44|2|2|345 9ab|3200233202|a
    Dubai|AE|25.20|55.27|4|3|123 bc|1232011330|a
    Muscat & Oman|OM|23.59|58.41|3|2|123 bc|2102332203|a
    Cape Town|ZA|-33.92|18.42|2|3|123 abc|2322332211|a
    Kruger & Garden Route|ZA|-24.01|31.49|3|2|56789a|0100333303|a
    Zanzibar|TZ|-6.16|39.20|2|1|12 6789a|2113222202|a
    Arusha & Serengeti|TZ|-2.33|34.83|4|1|12 6789a|0000333203|a
    Nairobi & Kenya safari|KE|-1.29|36.82|3|2|12 6789a|1002333202|a
    Mauritius|MU|-20.35|57.55|3|1|456 9abc|0103223301|a
    Seychelles|SC|-4.68|55.48|4|1|45 9ab|0003323202|a
    New York|US|40.71|-74.01|4|3|456 9ac|3330002330|a
    Big Sur & California Coast|US|36.60|-121.90|4|2|456789a|1312332311|a
    San Francisco|US|37.77|-122.42|4|2|456 9a|2321211220|a
    Los Angeles|US|34.05|-118.24|4|3|3456 9ab|2332101320|a
    Zion & Utah parks|US|37.30|-113.03|3|2|345 9a|0100333303|a
    New Orleans|US|29.95|-90.07|3|2|234 abc|2332001111|a
    Maui & Hawaii|US|20.80|-156.33|4|2|456 9a|1113333301|a
    Miami & Keys|US|25.76|-80.19|4|2|1234 bc|1233111220|a
    Chicago|US|41.88|-87.63|3|3|56789|2331001221|a
    Vancouver & Rockies|CA|49.28|-123.12|3|2|6789|1211332311|a
    Montreal & Quebec|CA|45.50|-73.57|3|2|6789a|2331102221|a
    Mexico City|MX|19.43|-99.13|2|3|1234 abc|3331101231|a
    Oaxaca|MX|17.07|-96.73|1|2|1234 abc|3321211123|a
    Tulum & Yucatan|MX|20.63|-87.07|2|2|1234 bc|2223222301|a
    La Fortuna & Costa Rica|CR|9.75|-83.75|3|2|1234 c|0102333302|a
    Havana & Cuba|CU|23.11|-82.37|2|2|1234 bc|3122101212|a
    Cartagena & Colombia coffee|CO|10.39|-75.48|2|2|123 78c|2222222112|a
    Cusco & Machu Picchu|PE|-13.53|-71.97|2|2|56789|3300233112|a
    Rio de Janeiro|BR|-22.91|-43.17|2|3|3456 9ab|2233212110|a
    Buenos Aires|AR|-34.60|-58.38|2|3|345 9ab|3331002221|a
    El Chalten & Patagonia|AR|-49.33|-72.89|3|1|123 bc|0100333003|a
    Atacama & Santiago|CL|-22.91|-68.20|3|2|345 9ab|1200333103|a
    Tokyo|JP|35.68|139.69|3|3|345 abc|3330102330|a
    Kyoto & Osaka|JP|35.01|135.77|3|3|345 ab|3320203221|a
    Takayama & Japanese Alps|JP|36.24|137.97|3|1|12 45 9ab|2200322103|a
    Seoul|KR|37.57|126.98|2|3|45 9ab|2331101230|a
    Bangkok|TH|13.76|100.50|1|3|12 bc|2331001231|a
    Chiang Mai|TH|18.79|98.99|1|2|12 bc|2310222212|a
    Phuket & Thai islands|TH|7.88|98.39|2|2|1234 c|0123222200|a
    Hanoi & Ha Long|VN|21.03|105.85|1|2|34 9ab|3311222112|a
    Hoi An & central Vietnam|VN|15.88|108.34|1|1|2345|2312212222|a
    Bali|ID|-8.41|115.19|1|2|56789a|2223322211|a
    Singapore|SG|1.35|103.82|4|2|23456789|2321101330|a
    Kandy & Sri Lanka|LK|7.29|80.64|1|2|123 c|2203332202|a
    Jaipur & Rajasthan|IN|26.92|75.79|1|3|123 abc|3300122122|a
    Kerala & Goa|IN|9.93|76.27|1|2|123 bc|1213222202|a
    Kathmandu & Nepal|NP|27.72|85.32|1|2|34 abc|2100333003|a
    Maldives|MV|3.20|73.22|4|1|1234 bc|0003213201|a
    Samarkand & Silk Road|UZ|39.65|66.96|1|2|45 9a|3200112113|a
    Hong Kong|HK|22.32|114.17|3|2|123 abc|2331101330|a
    Taipei & Taiwan|TW|25.03|121.57|2|2|345 abc|2311222222|a
    Palawan & Philippine islands|PH|11.20|119.41|1|1|12345 c|0013332102|a
    Sydney|AU|-33.87|151.21|4|3|123 9abc|2322211320|a
    Melbourne & Great Ocean Road|AU|-37.81|144.96|3|3|123 bc|2321221221|a
    Queenstown & South Island|NZ|-45.03|168.66|3|2|123 bc|0100333203|a
    """
}

// MARK: - Geography helpers

enum Geo {
    static func km(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6371.0, p = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * p, dLon = (b.longitude - a.longitude) * p
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * p) * cos(b.latitude * p) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
    /// Points along the great circle from a to b.
    static func arc(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, steps: Int = 32) -> [CLLocationCoordinate2D] {
        let p = Double.pi / 180
        func vector(_ c: CLLocationCoordinate2D) -> SIMD3<Double> {
            SIMD3(cos(c.latitude * p) * cos(c.longitude * p), cos(c.latitude * p) * sin(c.longitude * p), sin(c.latitude * p))
        }
        let va = vector(a), vb = vector(b)
        let omega = acos(max(-1, min(1, (va * vb).sum())))
        guard omega > 1e-6 else { return [a, b] }
        return (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let v = (va * sin((1 - t) * omega) + vb * sin(t * omega)) / sin(omega)
            return CLLocationCoordinate2D(latitude: asin(max(-1, min(1, v.z))) / p, longitude: atan2(v.y, v.x) / p)
        }
    }
}
