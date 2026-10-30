import CoreLocation
import SwiftUI

struct NewTripView: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var location: LocationService
    @Environment(\.dismiss) private var dismiss

    var onCreated: (Trip) -> Void

    @State private var place = ""
    @State private var fileCode = ""
    @State private var fileCodeEdited = false
    @State private var continent = ""
    @State private var countryCode = ""
    @State private var state = ""
    @State private var suggestedPlace = ""
    @State private var status = "Finding your location…"
    @State private var lookedUp = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    TextField("Place name, e.g. Mount Barney", text: $place)
                        .textInputAutocapitalization(.words)
                    if place.isEmpty && !suggestedPlace.isEmpty {
                        Button("Use “\(suggestedPlace)”") {
                            place = suggestedPlace
                        }
                    }
                }

                Section {
                    Picker("Continent", selection: $continent) {
                        Text("Choose").tag("")
                        ForEach(GeoData.continents, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Picker("Country", selection: $countryCode) {
                        Text("Choose").tag("")
                        ForEach(GeoData.countries(in: continent), id: \.self) { code in
                            Text(GeoData.countryName(code)).tag(code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(continent.isEmpty)
                    if let subdivisions = GeoData.subdivisions[countryCode] {
                        Picker("State", selection: $state) {
                            Text("Choose").tag("")
                            ForEach(subdivisions, id: \.self) { subdivision in
                                Text(subdivision.name).tag(subdivision.name)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } else {
                        TextField("State or region", text: $state)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text("Where")
                } footer: {
                    Text(status)
                }

                Section {
                    TextField("Short name", text: Binding(
                        get: { fileCode },
                        set: { newValue in
                            fileCode = newValue
                            fileCodeEdited = true
                        }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("File names")
                } footer: {
                    Text("Clips will be named like \(previewName)")
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(!canCreate)
                }
            }
            .onChange(of: place) { _, newValue in
                if !fileCodeEdited {
                    fileCode = TripStore.fileCode(for: newValue)
                }
            }
            .onChange(of: continent) { _, newValue in
                if !countryCode.isEmpty && GeoData.continent(for: countryCode) != newValue {
                    countryCode = ""
                    state = ""
                }
            }
            .onChange(of: countryCode) { oldValue, _ in
                if !oldValue.isEmpty {
                    state = ""
                }
            }
            .onAppear {
                location.start()
                if location.isDenied {
                    status = "Location is off for Shot Guide. Pick from the lists."
                }
                if let current = location.location {
                    lookUp(current)
                }
            }
            .onReceive(location.$location) { newLocation in
                if let newLocation, !lookedUp {
                    lookUp(newLocation)
                }
            }
        }
    }

    private var canCreate: Bool {
        !place.trimmingCharacters(in: .whitespaces).isEmpty && !countryCode.isEmpty
    }

    private var previewName: String {
        let code = fileCode.isEmpty ? "Trip" : TripStore.fileCode(for: fileCode)
        return TripStore.clipName(code: code, day: TripStore.dayString(Date(), timeZone: .current), shot: .reveal, take: 1)
    }

    private func lookUp(_ found: CLLocation) {
        lookedUp = true
        status = "Looking up where you are…"
        CLGeocoder().reverseGeocodeLocation(found) { placemarks, _ in
            DispatchQueue.main.async {
                guard let mark = placemarks?.first, let code = mark.isoCountryCode else {
                    status = "No signal for place names. Pick from the lists; your GPS point is still saved."
                    return
                }
                if countryCode.isEmpty {
                    let area = GeoData.stateName(from: mark.administrativeArea ?? "", countryCode: code)
                    continent = GeoData.continent(for: code)
                    countryCode = code
                    // Set the state after the country, which clears it when it changes.
                    DispatchQueue.main.async { state = area }
                }
                suggestedPlace = mark.areasOfInterest?.first ?? mark.locality ?? mark.name ?? ""
                status = "Filled in from your location. Change anything that's wrong."
            }
        }
    }

    private func create() {
        let coordinate = location.location?.coordinate
        do {
            let trip = try store.createTrip(
                place: place.trimmingCharacters(in: .whitespaces),
                fileCode: fileCode,
                state: state.trimmingCharacters(in: .whitespaces),
                countryCode: countryCode,
                continent: continent,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude)
            onCreated(trip)
        } catch {
            errorText = "Couldn't create the trip folder: \(error.localizedDescription)"
        }
    }
}
