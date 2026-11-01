import Foundation
import UserNotifications

/// Notifications before golden hour, sunset and blue hour, with the shots that suit the light.
/// Scheduled for where you are whenever you open a trip you're filming, replacing the last ones.
enum LightAlerts {
    static let identifiers = ["light.golden", "light.sunset", "light.blue"]

    private struct Alert {
        let id: String
        let date: Date
        let title: String
        let body: String
    }

    static func schedule(place: String, latitude: Double, longitude: Double) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let alerts = upcoming(place: place, latitude: latitude, longitude: longitude, after: Date())
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
            }
        }
    }

    /// The next evening's alerts, within the next 18 hours.
    private static func upcoming(place: String, latitude: Double, longitude: Double, after now: Date) -> [Alert] {
        var alerts: [Alert] = []
        let lead: TimeInterval = 15 * 60
        if let golden = SunCalc.nextCrossing(of: 6, rising: false, after: now, latitude: latitude, longitude: longitude) {
            alerts.append(Alert(
                id: "light.golden", date: golden.addingTimeInterval(-lead),
                title: "Golden hour in 15 minutes",
                body: "Good light at \(place) for MOMENT, WALKAWAY, TELE and SILHOUETTE."))
        }
        if let sunset = SunCalc.nextCrossing(of: SunCalc.horizon, rising: false, after: now, latitude: latitude, longitude: longitude) {
            alerts.append(Alert(
                id: "light.sunset", date: sunset.addingTimeInterval(-lead),
                title: "Sunset in 15 minutes",
                body: "Start a TIMELAPSE now, or set up a SILHOUETTE."))
            alerts.append(Alert(
                id: "light.blue", date: sunset,
                title: "Blue hour now",
                body: "Soft light for about 20 minutes. City lights coming on make a great TIMELAPSE."))
        }
        let latest = now.addingTimeInterval(18 * 3600)
        return alerts.filter { $0.date > now.addingTimeInterval(30) && $0.date < latest }
    }
}

/// Shows alerts as a banner while the app is open, without a sound, so a sound never ends up in a clip.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
