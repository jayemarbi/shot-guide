import SwiftUI

/// Details about the place, for text on screen and "things to know before you go" reels.
struct TripFactsView: View {
    let tripID: UUID

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var facts = TripFacts()
    @State private var loaded = false

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
                    Text("Fill in whatever you know. These go into the trip's folder for on-screen text and \"things to know\" reels.")
                }
            }
            .navigationTitle("Trip facts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateFacts(facts, tripID: tripID)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                facts = store.trip(id: tripID)?.facts ?? TripFacts()
            }
        }
    }
}
