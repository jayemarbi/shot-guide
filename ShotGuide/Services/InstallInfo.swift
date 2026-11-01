import Foundation

/// When this install stops opening. Apps installed with a free Apple ID carry a provisioning profile that
/// runs out after 7 days. Installing the app again over the top starts the clock again and keeps your trips.
enum InstallInfo {
    static let expiry: Date? = readExpiry()

    private static func readExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        // The profile is a signed property list: the readable XML sits inside the signature.
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: [], in: start.lowerBound..<data.endIndex) else {
            return nil
        }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        let list = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil)
        return (list as? [String: Any])?["ExpirationDate"] as? Date
    }

    /// "Fri 20 Nov at 9:15 pm"
    static func dayAndTime(_ date: Date) -> String {
        let day = DateFormatter()
        day.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return day.string(from: date) + " at " + time(date)
    }

    /// "9:15 pm"
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "Runs out tomorrow at 9:15 pm", for the last two days.
    static func urgentTitle(expiry: Date, now: Date) -> String {
        if expiry <= now {
            return "This install has run out"
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(expiry) {
            return "Runs out today at " + time(expiry)
        }
        if calendar.isDateInTomorrow(expiry) {
            return "Runs out tomorrow at " + time(expiry)
        }
        return "Runs out " + dayAndTime(expiry)
    }
}
