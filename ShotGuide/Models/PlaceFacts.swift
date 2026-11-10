import Foundation

// What you spent at each place, links worth keeping, and the day's timeline and sun times (1.27), for price lists,
// cost guides, rated lists and "24 hours in…" itineraries. It all goes into facts.txt, and the costs into costs.csv.

/// What a cost was for, so a cost-breakdown reel can group them. Picking one is optional.
enum CostKind: String, Codable, CaseIterable, Identifiable {
    case gettingThere
    case stay
    case food
    case activities
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingThere: return "Getting there"
        case .stay: return "Stay"
        case .food: return "Food and drink"
        case .activities: return "Activities"
        case .other: return "Other"
        }
    }
}

/// One thing you paid for at a place: what it was and what it cost, in the trip's currency.
struct CostItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amount: Double
    var kind: CostKind? = nil
    /// When you added it, and on which day of the trip, for day-by-day breakdowns.
    var addedAt = Date()
    var day: Int? = nil
}

/// A link worth keeping with a place: the trail's page, where you booked, a café.
struct FactLink: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var url: String

    /// The name, or the website when there isn't one.
    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return URL(string: url)?.host ?? url
    }

    /// A link as typed, with https:// added when it has no scheme.
    static func normalised(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return trimmed }
        return "https://" + trimmed
    }
}

/// Amounts and currencies for costs.
enum Money {
    /// Reads an amount as it was typed: "15", "15.50", "15,50", "$1,200", "1 200,50" or "1.200,50". A mark with one or
    /// two digits after it is the decimal point; any other marks group thousands. nil when there's no number in it.
    static func amount(from text: String) -> Double? {
        let kept = Array(text.filter { ($0.isASCII && $0.isNumber) || $0 == "." || $0 == "," })
        guard kept.contains(where: { $0.isNumber }) else { return nil }
        let marks = kept.indices.filter { kept[$0] == "." || kept[$0] == "," }
        var decimalAt: Int? = nil
        if let last = marks.last {
            let sameKind = marks.filter { kept[$0] == kept[last] }.count
            let digitsAfter = kept.count - last - 1
            if sameKind < marks.count {
                // Both kinds of mark: the last one is the decimal point, like "1,200.50" or "1.200,50".
                decimalAt = last
            } else if sameKind == 1 && digitsAfter > 0 && digitsAfter <= 2 {
                // "15.5" or "15,50". "1,200" groups thousands.
                decimalAt = last
            }
        }
        var number = ""
        for (index, character) in kept.enumerated() {
            if character.isNumber {
                number.append(character)
            } else if index == decimalAt {
                number.append(".")
            }
        }
        if number.hasPrefix(".") {
            number = "0" + number
        }
        return Double(number).map { ($0 * 100).rounded() / 100 }
    }

    /// "$15.00", in a currency, written the phone's way.
    static func format(_ amount: Double, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }

    /// A country's currency, like "USD" for the US, or the phone's own when there's no country.
    static func currency(forCountry code: String) -> String {
        if !code.isEmpty, let currency = Locale(identifier: "en_" + code.uppercased()).currency?.identifier {
            return currency
        }
        return Locale.current.currency?.identifier ?? "AUD"
    }

    /// The currencies to pick from: the ones travel is most likely to need, and the trip's own.
    static func choices(including current: String) -> [String] {
        let common = ["AED", "ARS", "AUD", "BRL", "CAD", "CHF", "CLP", "CNY", "COP", "CRC", "CZK", "DKK", "EGP", "EUR",
                      "FJD", "GBP", "HKD", "IDR", "INR", "ISK", "JPY", "KRW", "KZT", "LKR", "MAD", "MXN", "MYR", "NOK",
                      "NPR", "NZD", "PEN", "PHP", "PLN", "SEK", "SGD", "THB", "TRY", "TWD", "USD", "VND", "XPF", "ZAR"]
        return Array(Set(common + [current])).sorted()
    }

    /// "AUD · Australian Dollar".
    static func currencyName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code).map { "\(code) · \($0)" } ?? code
    }

    /// The number of people new trips share costs between: the last one you picked.
    static var lastPeople: Int {
        get { max(1, UserDefaults.standard.integer(forKey: "costs.people")) }
        set { UserDefaults.standard.set(max(1, newValue), forKey: "costs.people") }
    }
}

extension Trip {
    /// The currency costs are in: the one you picked, or the country's own (US dollars in the US).
    var currency: String {
        if let currencyCode, !currencyCode.isEmpty {
            return currencyCode
        }
        return Money.currency(forCountry: countryCode)
    }

    /// How many people the costs are shared between, for the cost each: at least 1.
    var people: Int {
        max(1, costPeople ?? Money.lastPeople)
    }

    /// Each place once, in the order of its first day, with what you spent there.
    var costsByPlace: [(place: String, costs: [CostItem])] {
        var places: [String] = []
        var result: [(place: String, costs: [CostItem])] = []
        for tripDay in allDays where !places.contains(tripDay.place) {
            places.append(tripDay.place)
            let costs = dayFacts(tripDay.number)?.costs ?? []
            if !costs.isEmpty {
                result.append((place: tripDay.place, costs: costs))
            }
        }
        return result
    }

    /// Every cost on the trip.
    var allCosts: [CostItem] {
        costsByPlace.flatMap { $0.costs }
    }

    static func total(_ costs: [CostItem]) -> Double {
        costs.reduce(0) { $0 + $1.amount }
    }

    /// "$51.00", or "$51.00 · $25.50 each" when the costs are shared.
    func totalLine(_ costs: [CostItem]) -> String {
        let total = Self.total(costs)
        let line = Money.format(total, currency: currency)
        guard people > 1 else { return line }
        return line + " · " + Money.format(total / Double(people), currency: currency) + " each"
    }

    /// The time zone a day was filmed in: its first clip's, or the phone's.
    func timeZone(onDay number: Int) -> TimeZone {
        clips(onDay: number).min { $0.recordedAt < $1.recordedAt }
            .flatMap { TimeZone(identifier: $0.timeZoneID) } ?? .current
    }

    private func timeFormatter(onDay number: Int) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timeZone(onDay: number)
        return formatter
    }

    /// "Sunrise 5:01 am, golden hour until 5:40 am. Golden hour from 5:52 pm, sunset 6:31 pm." at a day's place, or nil
    /// without a location.
    func sunLine(day number: Int) -> String? {
        let tripDay = day(number)
        guard let latitude = tripDay.latitude ?? self.latitude, let longitude = tripDay.longitude ?? self.longitude else {
            return nil
        }
        let times = SunCalc.dayTimes(on: tripDay.startedAt, timeZone: timeZone(onDay: number), latitude: latitude,
                                     longitude: longitude)
        let formatter = timeFormatter(onDay: number)
        func time(_ date: Date?) -> String? {
            date.map { formatter.string(from: $0) }
        }
        var parts: [String] = []
        if let sunrise = time(times.sunrise) {
            let golden: String = time(times.morningGoldenEnds).map { ", golden hour until " + $0 } ?? ""
            parts.append("Sunrise " + sunrise + golden + ".")
        }
        if let sunset = time(times.sunset) {
            let golden: String = time(times.eveningGoldenStarts).map { "Golden hour from " + $0 + ", sunset " } ?? "Sunset "
            parts.append(golden + sunset + ".")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Each spot you filmed at on a day and when you got there, from your clips: "7:40 am  Lower Falls · 12 clips". A spot
    /// with only clips added from another day comes after the rest, with that day's date: "4 Nov 10:41 pm  Scene 2" (1.27.1).
    func timeline(day number: Int) -> [String] {
        let formatter = timeFormatter(onDay: number)
        let zone = timeZone(onDay: number)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = zone
        dateFormatter.setLocalizedDateFormatFromTemplate("dMMM")
        let today = day(number).startedAt
        var onTheDay: [(at: Date, line: String)] = []
        var fromOtherDays: [(at: Date, line: String)] = []
        for scene in scenes(onDay: number) {
            // When you got there that day, or when its first clip was filmed if they were all added from another day.
            let first = scene.clips.first { calendar.isDate($0.recordedAt, inSameDayAs: today) }
            guard let arrived = first ?? scene.clips.first else { continue }
            let count = scene.clips.count
            let clipCount = count == 1 ? "1 clip" : "\(count) clips"
            let time = formatter.string(from: arrived.recordedAt)
            if first != nil {
                onTheDay.append((at: arrived.recordedAt, line: "\(time)  \(scene.name) · \(clipCount)"))
            } else {
                let date = dateFormatter.string(from: arrived.recordedAt)
                fromOtherDays.append((at: arrived.recordedAt, line: "\(date) \(time)  \(scene.name) · \(clipCount)"))
            }
        }
        let ordered = onTheDay.sorted { $0.at < $1.at } + fromOtherDays.sorted { $0.at < $1.at }
        return ordered.map { $0.line }
    }

    /// facts.txt: each place's facts, what you spent there and its links, then each day there with the sun's times and
    /// when you got to each spot, and at the end what the whole trip cost. nil for a trip with nothing to say yet.
    var factsText: String? {
        var places: [String] = []
        var sections: [String] = []
        for tripDay in allDays where !places.contains(tripDay.place) {
            places.append(tripDay.place)
            var blocks: [String] = []
            let facts = dayFacts(tripDay.number) ?? TripFacts()
            if !facts.text.isEmpty {
                blocks.append(facts.text)
            }
            if !facts.costs.isEmpty {
                blocks.append(costsText(facts.costs))
            }
            if !facts.links.isEmpty {
                blocks.append((["Links:"] + facts.links.map { "- \($0.title): \($0.url)" }).joined(separator: "\n"))
            }
            for day in allDays where day.place == tripDay.place {
                let lines = [day.label] + [sunLine(day: day.number)].compactMap { $0 } + timeline(day: day.number)
                if lines.count > 1 {
                    blocks.append(lines.joined(separator: "\n"))
                }
            }
            if !blocks.isEmpty {
                sections.append(([tripDay.place] + blocks).joined(separator: "\n\n"))
            }
        }
        if costsByPlace.count > 1 {
            sections.append("Whole trip\n\nSpent: " + totalLine(allCosts))
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n\n") + "\n"
    }

    /// A place's costs for facts.txt: each with its kind and day, then the total and the cost each.
    private func costsText(_ costs: [CostItem]) -> String {
        let header = "Spent, in \(currency)" + (people > 1 ? ", shared between \(people)" : "") + ":"
        let items = costs.map { cost -> String in
            let details: [String] = [cost.kind?.title, cost.day.map { "day \($0)" }].compactMap { $0 }
            let amount = Money.format(cost.amount, currency: currency)
            let note = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
            return "- \(cost.name): \(amount)\(note)"
        }
        return ([header] + items + ["Total: " + totalLine(costs)]).joined(separator: "\n")
    }
}
