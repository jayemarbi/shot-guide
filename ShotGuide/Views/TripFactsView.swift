import SwiftUI

/// Details about a day's place, for text on screen, guide reels, price lists and rated lists. Days at the same place
/// share them. The costs and links save as you add them; the rest saves with Save (1.27).
struct TripFactsView: View {
    let tripID: UUID
    let day: Int

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @State private var facts = TripFacts()
    @State private var loaded = false
    @State private var sunLine: String? = nil
    @State private var timeline: [String] = []

    private var place: String {
        (store.trip(id: tripID)?.day(day).place ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Scores out of 10, in halves, best first.
    private static let ratings: [Double] = Array(stride(from: 10.0, through: 1.0, by: -0.5))

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
                    TextField("Entry cost, e.g. free, or $15 park pass", text: $facts.cost)
                    TextField("Parking", text: $facts.parking, axis: .vertical)
                    TextField("Getting there", text: $facts.gettingThere, axis: .vertical)
                    TextField("Best time to go", text: $facts.bestTime, axis: .vertical)
                    TextField("Bookings and permits, e.g. book a timed entry online", text: $facts.bookings, axis: .vertical)
                    TextField("Facilities, e.g. toilets, water, no phone signal", text: $facts.facilities, axis: .vertical)
                } header: {
                    Text("Visiting")
                } footer: {
                    Text("Entry cost is what it costs anyone to visit. What you spent goes below.")
                }

                CostsSection(tripID: tripID, day: day)

                Section {
                    TextField("Weather and temperature, e.g. 24°C and clear", text: $facts.weather, axis: .vertical)
                    TextField("How busy, e.g. quiet before 8 am", text: $facts.crowds, axis: .vertical)
                } header: {
                    Text("On the day")
                }

                Section {
                    Picker("Your rating", selection: $facts.rating) {
                        Text("Not rated").tag(Double?.none)
                        ForEach(Self.ratings, id: \.self) { value in
                            Text(TripFacts.score(value) + "/10").tag(Double?.some(value))
                        }
                    }
                    TextField("Best bit", text: $facts.bestBit, axis: .vertical)
                    TextField("Downsides", text: $facts.downsides, axis: .vertical)
                } header: {
                    Text("Your rating")
                } footer: {
                    Text("For rated lists and honest reviews.")
                }

                Section {
                    TextField("Looks like, e.g. Switzerland", text: $facts.looksLike)
                    TextField("A hook or caption that came to you", text: $facts.lines, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Ideas")
                } footer: {
                    Text("Looks like is for lookalike lists, where a place could pass for somewhere famous.")
                }

                LinksSection(tripID: tripID, day: day)

                Section {
                    TextField("Anything worth knowing", text: $facts.tips, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Tips")
                }

                Section {
                    if let sunLine {
                        Label(sunLine, systemImage: "sun.horizon.fill")
                    }
                    if timeline.isEmpty {
                        Text("Where you filmed today, and when you got there, shows up here once you've filmed.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(timeline.enumerated()), id: \.offset) { entry in
                            Text(entry.element)
                        }
                    }
                } header: {
                    Text("Filled in for you")
                } footer: {
                    Text("Fill in whatever you know about \(place.isEmpty ? "this place" : place). Each place on the trip "
                         + "has its own facts, and they all go into facts.txt in the trip's folder with each day's sun "
                         + "times and timeline, for on-screen text, guides, price lists and rated lists.")
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
                let trip = store.trip(id: tripID)
                facts = trip?.dayFacts(day) ?? TripFacts()
                sunLine = trip?.sunLine(day: day)
                timeline = trip?.timeline(day: day) ?? []
            }
        }
    }
}
