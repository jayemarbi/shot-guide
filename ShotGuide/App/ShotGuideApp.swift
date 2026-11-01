import SwiftUI
import UserNotifications

@main
struct ShotGuideApp: App {
    @StateObject private var store = TripStore()
    @StateObject private var location = LocationService()
    @StateObject private var tagLibrary = TagLibrary()
    @StateObject private var songs = SongLibrary()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            TripListView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(tagLibrary)
                .environmentObject(songs)
                .preferredColorScheme(.dark)
                .tint(.orange)
                .onAppear { location.start() }
        }
    }
}
