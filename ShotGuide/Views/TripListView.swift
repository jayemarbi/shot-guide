import SwiftUI

struct TripListView: View {
    @EnvironmentObject var store: TripStore
    @State private var showingNewTrip = false
    @State private var path: [UUID] = []
    @State private var tripToDelete: Trip? = nil
    @State private var showingLooks = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let expiry = InstallInfo.expiry {
                    Section {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            InstallLine(expiry: expiry, now: context.date)
                        }
                    }
                }
                if store.trips.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No trips yet")
                                .font(.headline)
                            Text("When you get somewhere worth filming, tap New trip.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                ForEach(store.trips) { trip in
                    NavigationLink(value: trip.id) {
                        TripRow(trip: trip)
                    }
                    .swipeActions {
                        Button {
                            tripToDelete = trip
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
            .navigationTitle("Shot Guide")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingLooks = true
                    } label: {
                        Label("Look", systemImage: "camera.filters")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTrip = true
                    } label: {
                        Label("New trip", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingLooks) {
                LookSheet()
            }
            .navigationDestination(for: UUID.self) { id in
                TripView(tripID: id)
            }
            .sheet(isPresented: $showingNewTrip) {
                NewTripView { trip in
                    showingNewTrip = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        path.append(trip.id)
                    }
                }
            }
            .alert(
                "Delete this trip?",
                isPresented: Binding(get: { tripToDelete != nil }, set: { if !$0 { tripToDelete = nil } }),
                presenting: tripToDelete
            ) { trip in
                Button("Delete trip and \(trip.clips.count) clips", role: .destructive) {
                    store.deleteTrip(trip.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: { trip in
                Text("\(trip.place) and its clips will be removed from this phone. Copy them to your SSD or PC first.")
            }
        }
    }
}

struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.place)
                .font(.headline)
            if !trip.regionLine.isEmpty {
                Text(trip.regionLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(trip.dateLine)
                Spacer()
                Text("\(trip.doneTotal) of \(trip.targetTotal) clips")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// When this install stops opening: a quiet line, turning orange in the last two days so you reinstall in time.
struct InstallLine: View {
    let expiry: Date
    let now: Date

    var body: some View {
        if expiry.timeIntervalSince(now) <= 2 * 86400 {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hourglass")
                    .frame(width: 28)
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(InstallInfo.urgentTitle(expiry: expiry, now: now))
                        .font(.headline)
                        .foregroundStyle(Color.orange)
                    Text("Reinstall from the PC before your next trip. Your trips and clips stay.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("This install runs out " + InstallInfo.dayAndTime(expiry), systemImage: "hourglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
