import SwiftUI

@main
struct ShotGuideApp: App {
    @StateObject private var store = TripStore()
    @StateObject private var location = LocationService()
    @StateObject private var tagLibrary = TagLibrary()

    var body: some Scene {
        WindowGroup {
            TripListView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(tagLibrary)
                .preferredColorScheme(.dark)
                .tint(.orange)
                .onAppear { location.start() }
        }
    }
}
