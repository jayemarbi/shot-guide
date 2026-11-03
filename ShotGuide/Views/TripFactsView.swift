import SwiftUI

/// Details about a day's place, for text on screen and guide reels. Days at the same place share them.
struct TripFactsView: View {
    let tripID: UUID
    let day: Int

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var facts = TripFacts()
    @State private var loaded = false

    private var place: String {
        (store.trip(id: tripID)?.day(day).place ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Distance, e.g. 8 km return", text: $facts.distance)
                    TextField("Time, e.g. 3 hours", text: $facts.time)
                    TextField("Elevation gain, e.g. 600 m", text: $facts.elevation)
                    Picker("Difficulty", selection: $facts.difficulty) {
                        Text("Not set").tag("")
                        Text("Easy").tag("Easy")
                        Text("Moderate").tag("Moderate")
                        Text("Hard").tag("Hard")
                    }
                } header: {
                    Text("The walk")
                }

                Section {
                    TextField("Cost, e.g. free, or $15 park pass", text: $facts.cost)
                    TextField("Parking", text: $facts.parking, axis: .vertical)
                    TextField("Getting there", text: $facts.gettingThere, axis: .vertical)
                    TextField("Best time to go", text: $facts.bestTime, axis: .vertical)
                } header: {
                    Text("Visiting")
                }

                Section {
                    TextField("Anything worth knowing", text: $facts.tips, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Tips")
                } footer: {
                    Text("Fill in whatever you know about \(place.isEmpty ? "this place" : place). Each place on the trip "
                         + "has its own facts, and they all go into facts.txt in the trip's folder, for on-screen text and "
                         + "guide reels.")
                }
            }
            .navigationTitle(place.isEmpty ? "Place facts" : place)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateFacts(facts, tripID: tripID, day: day)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                facts = store.trip(id: tripID)?.dayFacts(day) ?? TripFacts()
            }
        }
    }
}
