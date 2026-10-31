import SwiftUI

struct TripListView: View {
    @EnvironmentObject var store: TripStore
    @State private var showingNewTrip = false
    @State private var path: [UUID] = []
    @State private var tripToDelete: Trip? = nil

    var body: some View {
        NavigationStack(path: $path) {
            List {
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTrip = true
                    } label: {
                        Label("New trip", systemImage: "plus")
                    }
                }
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
                Text(trip.createdAt, style: .date)
                Spacer()
                Text("\(trip.doneTotal) of \(trip.targetTotal) clips")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
