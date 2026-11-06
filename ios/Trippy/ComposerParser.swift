import Foundation

/// What the composer understood from one message.
struct ComposerResult: Equatable {
    var destination = ""
    var startDate = ""
    var endDate = ""
    var flexible = false
    var duration = 4
    var travelers = 2
    var group = "Friends"
    var interests: Set<String> = []
    var pace: String?
    var budget = ""
    var arrivalTime = ""
    var departureTime = ""
    var stay = ""
    var message = ""
    var name = ""
    var mustSee: [ComposerPlace] = []
    /// Detailed interests (planner preference tags), e.g. "tapas".
    var tags: Set<String> = []
    var budgetBasis = "per person"
    /// "plane", "train" or "car".
    var travelMode = "plane"
    var look: ShelfLook?
}

/// A place the traveler insists on, with coordinates so the planner can schedule it.
struct ComposerPlace: Codable, Hashable {
    var name: String
    var latitude: Double?
    var longitude: Double?
    var address = ""
    var category = "attraction"
}

/// Reads plain Greek or English. It only picks up what is clearly written and
/// shows every guess as a chip the traveler can remove; the full message still
/// goes to the planner.
enum ComposerParser {
    /// Lowercase, accents off, final ς as σ (case folding turns ς into σ, so both sides must match).
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).replacingOccurrences(of: "ς", with: "σ")
    }

    static func parse(_ text: String, into base: ComposerResult) -> ComposerResult {
        var r = base
        let t = fold(text)
        func has(_ word: String) -> Bool { t.contains(fold(word)) }
        r.message = text
        // People
        if let n = firstNumber(before: ["ατομα", "atoma", "people", "persons", "adults", "ενηλικ"], in: t) { r.travelers = min(max(n, 1), 20) }
        if has("οικογεν") || has("family") || has("γονεις") || has("parents") {
            r.group = "Family"
            if firstNumber(before: ["ατομα", "people"], in: t) == nil, has("γονεις") || has("parents") { r.travelers = max(r.travelers, 3) }
        } else if has("ζευγαρ") || has("couple") || has("συντροφ") {
            r.group = "Couple"; r.travelers = 2
        } else if has("μόνος μου") || has("μόνη μου") || has("μόνος")  || has("solo") {
            r.group = "Solo"; r.travelers = 1
        } else if has("φιλ") || has("friends") { r.group = "Friends" }
        // Clock times: first is arrival, last is departure when two or more appear.
        let times = matches(#"\b([01]?\d|2[0-3])[:.]([0-5]\d)\b"#, in: text)
        if times.count >= 1 { r.arrivalTime = normalizedTime(times[0]) }
        if times.count >= 2 { r.departureTime = normalizedTime(times[times.count - 1]) }
        // Stay
        for marker in ["μενουμε ", "μενω ", "staying in ", "stay in ", "ξενοδοχειο ", "hotel "] {
            if let range = t.range(of: fold(marker)) {
                // Folding keeps one character per character for these scripts; clamp anyway.
                let offset = min(t.distance(from: t.startIndex, to: range.upperBound), text.count)
                let tail = text[text.index(text.startIndex, offsetBy: offset)...]
                r.stay = String(tail.prefix { !".,;\n(".contains($0) }).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        // Interests
        let interestWords: [(String, [String])] = [
            ("food", ["φαγητ", "tapas", "ταπας", "εστιατ", "food", "γαστρο", "αγορ", "market", "vermut", "seafood", "θαλασσιν"]),
            ("sights", ["αξιοθεατ", "μουσει", "gaudi", "γκαουντι", "sagrada", "sights", "museum", "αρχιτεκτ", "εκκλησ"]),
            ("outdoors", ["παραλι", "beach", "παρκ", "park", "θεα", "view", "βουν", "πεζοπορ", "hike"]),
            ("nightlife", ["ποτο", "bar", "μπαρ", "club", "νυχτ", "κρασ", "wine"]),
            ("shopping", ["ψωνι", "shopping", "μαγαζ"]),
            ("coffee", ["καφε", "coffee", "brunch"]),
        ]
        r.interests = Set(interestWords.filter { _, words in words.contains { has($0) } }.map(\.0))
        if has("χαλαρ") || has("relaxed") || has("slow") { r.pace = "relaxed" }
        else if has("εντατικ") || has("γεματ") || has("intense") { r.pace = "intense" }
        // Budget: "€550", "550€", "550 ευρω"
        if let m = matches(#"(€\s?\d{2,5}|\d{2,5}\s?(€|ευρω|ευρώ|euro))"#, in: text).first {
            r.budget = m.filter(\.isNumber)
        }
        return r
    }

    private static func firstNumber(before words: [String], in t: String) -> Int? {
        let greekNumbers = ["δυο": 2, "δύο": 2, "τρεις": 3, "τρια": 3, "τεσσερις": 4, "πεντε": 5, "two": 2, "three": 3, "four": 4, "five": 5]
        let greek = Dictionary(greekNumbers.map { (fold($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
        let tokens = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for (i, token) in tokens.enumerated() where i > 0 && words.contains(where: { token.hasPrefix(fold($0)) }) {
            if let n = Int(tokens[i - 1]) { return n }
            if let n = greek[tokens[i - 1]] { return n }
        }
        return nil
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func normalizedTime(_ s: String) -> String {
        let parts = s.split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
        return parts.count == 2 ? String(format: "%02d:%02d", parts[0], parts[1]) : s
    }
}

