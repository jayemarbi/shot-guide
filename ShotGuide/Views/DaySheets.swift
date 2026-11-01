import CoreLocation
import SwiftUI

/// One trip type in a list: icon, name, what it's for, and a tick when it's picked.
struct TripTypeRow: View {
    let type: TripType
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.symbol)
                .frame(width: 28)
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(type.title)
                Text(type.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.orange)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The trip types as rows to tap, for new trips, new days and changing a day's type.
struct TripTypeList: View {
    @Binding var selection: TripType

    var body: some View {
        ForEach(TripType.allCases) { type in
            Button {
                selection = type
            } label: {
                TripTypeRow(type: type, selected: selection == type)
            }
            .foregroundStyle(Color.primary)
        }
    }
}

/// Starts the next day of a trip: a fresh shot list, at the same place or somewhere new, with its own type.
struct StartDaySheet: View {
    let tripID: UUID
    var onStarted: (Int) -> Void

    @EnvironmentObject var store: TripStore
    @EnvironmentObject var location: LocationService
    @Environment(\.dismiss) private var dismiss

    @State private var somewhereNew = false
    @State private var place = ""
    @State private var suggestedPlace = ""
    @State private var type: TripType = .general
    @State private var loaded = false

    private var trip: Trip? { store.trip(id: tripID) }
    private var lastDay: TripDay? { trip.map { $0.day($0.lastDayNumber) } }
    private var nextNumber: Int { (trip?.lastDayNumber ?? 1) + 1 }

    private var canStart: Bool {
        !somewhereNew || !place.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                whereSection
                Section {
                    TripTypeList(selection: $type)
                } header: {
                    Text("Day \(nextNumber) type")
                } footer: {
                    Text("Day \(nextNumber - 1) keeps its own shot list and clips. Switch days at the top of the trip.")
                }
            }
            .navigationTitle("Start day \(nextNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: start)
                        .disabled(!canStart)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var whereSection: some View {
        Section {
            Button {
                somewhereNew = false
            } label: {
                checkRow("Still at \(lastDay?.place ?? "the same place")", on: !somewhereNew)
            }
            Button {
                somewhereNew = true
            } label: {
                checkRow("Somewhere new", on: somewhereNew)
            }
            if somewhereNew {
                TextField("Place name, e.g. Surfers Paradise", text: $place)
                    .textInputAutocapitalization(.words)
                if place.isEmpty && !suggestedPlace.isEmpty {
                    Button("Use “\(suggestedPlace)”") {
                        place = suggestedPlace
                    }
                }
            }
        } header: {
            Text("Where are you today?")
        } footer: {
            Text("A new place gets its own name in the file names. Its clips stay in this trip's folder.")
        }
    }

    private func checkRow(_ text: String, on: Bool) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(Color.primary)
            Spacer()
            if on {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.orange)
            }
        }
        .contentShape(Rectangle())
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        type = lastDay?.type ?? .general
        let currentPlace = lastDay?.place ?? ""
        guard let current = location.location else { return }
        CLGeocoder().reverseGeocodeLocation(current) { placemarks, _ in
            let mark = placemarks?.first
            let found = mark?.areasOfInterest?.first ?? mark?.locality ?? mark?.name ?? ""
            DispatchQueue.main.async {
                if found != currentPlace {
                    suggestedPlace = found
                }
            }
        }
    }

    private func start() {
        let coordinate = location.location?.coordinate
        let newPlace: String? = somewhereNew ? place : nil
        if let number = store.addDay(tripID: tripID, place: newPlace, type: type,
                                     latitude: coordinate?.latitude, longitude: coordinate?.longitude) {
            onStarted(number)
        }
        dismiss()
    }
}

/// Changes one day's trip type.
struct TypePickerSheet: View {
    let tripID: UUID
    let day: Int

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var type: TripType = .general
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TripTypeList(selection: $type)
                } footer: {
                    Text("Changes which shots count, how many takes each needs, and the tips. Clips you've filmed stay as they are.")
                }
            }
            .navigationTitle("Day \(day) type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.setType(type, day: day, tripID: tripID)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if !loaded {
                    loaded = true
                    type = store.trip(id: tripID)?.day(day).type ?? .general
                }
            }
        }
    }
}
