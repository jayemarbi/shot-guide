import SwiftUI

/// What you spent at a day's place (1.27), opened from Costs near the top of the trip page so you can add a cost the
/// moment you pay. Everything saves as you go.
struct CostsSheet: View {
    let tripID: UUID
    let day: Int

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss

    private var place: String {
        (store.trip(id: tripID)?.day(day).place ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                CostsSection(tripID: tripID, day: day)
            }
            .navigationTitle(place.isEmpty ? "Costs" : "Costs · \(place)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The costs at a day's place: add one with what it was and what it cost, and a kind if you like; tap one to change it,
/// swipe to delete it. Shows the total and the cost each, with how many people they're shared between and the currency.
/// Each change saves straight away, so a cost you add is kept whatever happens to the screen it's on (1.27).
struct CostsSection: View {
    let tripID: UUID
    let day: Int

    @EnvironmentObject var store: TripStore
    @State private var costs: [CostItem] = []
    @State private var people = 1
    @State private var currency = "AUD"
    @State private var loaded = false
    @State private var name = ""
    @State private var amountText = ""
    @State private var kind: CostKind? = nil
    @State private var editing: UUID? = nil
    @FocusState private var focus: Field?

    private enum Field {
        case name
        case amount
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Money.amount(from: amountText) != nil
    }

    var body: some View {
        addSection
        listSection
            .onAppear(perform: load)
            .onChange(of: people) { _, _ in saveSettings() }
            .onChange(of: currency) { _, _ in saveSettings() }
    }

    private var addSection: some View {
        Section {
            TextField("What it was, e.g. Park pass", text: $name)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onSubmit { focus = .amount }
            HStack {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                Text(currency)
                    .foregroundStyle(.secondary)
            }
            Picker("Kind", selection: $kind) {
                Text("None").tag(CostKind?.none)
                ForEach(CostKind.allCases) { kind in
                    Text(kind.title).tag(CostKind?.some(kind))
                }
            }
            Button(editing == nil ? "Add cost" : "Save changes", action: save)
                .disabled(!canSave)
            if editing != nil {
                Button("Don't change it", role: .cancel, action: clearDraft)
            }
        } header: {
            Text(editing == nil ? "Add a cost" : "Change a cost")
        }
    }

    private var listSection: some View {
        Section {
            if costs.isEmpty {
                Text("Nothing yet. Add what you pay for as you go: parking, entry, food, fuel, where you stay.")
                    .foregroundStyle(.secondary)
            }
            ForEach(costs) { cost in
                Button {
                    edit(cost)
                } label: {
                    CostRow(cost: cost, currency: currency)
                }
                .foregroundStyle(Color.primary)
            }
            .onDelete(perform: delete)
            Stepper(people == 1 ? "For 1 person" : "Shared between \(people) people", value: $people, in: 1...20)
            Picker("Currency", selection: $currency) {
                ForEach(Money.choices(including: currency), id: \.self) { code in
                    Text(Money.currencyName(code)).tag(code)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("What you spent here")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        guard let trip = store.trip(id: tripID) else { return "" }
        guard !costs.isEmpty else {
            return "Each place keeps its own costs, and the trip adds them up. They go in facts.txt and costs.csv, for "
                + "price lists and cost guides."
        }
        var text = "Total here: " + trip.totalLine(costs)
        let all = trip.allCosts
        if all.count > costs.count {
            text += ". Whole trip: " + trip.totalLine(all)
        }
        return text + "."
    }

    private func load() {
        guard !loaded, let trip = store.trip(id: tripID) else { return }
        loaded = true
        costs = trip.dayFacts(day)?.costs ?? []
        people = trip.people
        currency = trip.currency
    }

    /// The number of people and the currency, saved once you change them.
    private func saveSettings() {
        guard loaded, let trip = store.trip(id: tripID), trip.people != people || trip.currency != currency else { return }
        store.updateCostSettings(tripID: tripID, people: people, currency: currency)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Money.amount(from: amountText) else { return }
        if let editingID = editing, let index = costs.firstIndex(where: { $0.id == editingID }) {
            costs[index].name = trimmed
            costs[index].amount = value
            costs[index].kind = kind
        } else {
            costs.append(CostItem(name: trimmed, amount: value, kind: kind, day: day))
        }
        store.updateCosts(costs, tripID: tripID, day: day)
        clearDraft()
    }

    private func edit(_ cost: CostItem) {
        editing = cost.id
        name = cost.name
        amountText = String(format: "%.2f", cost.amount)
        kind = cost.kind
        focus = .name
    }

    private func clearDraft() {
        name = ""
        amountText = ""
        kind = nil
        editing = nil
        focus = nil
    }

    private func delete(at offsets: IndexSet) {
        let removed = offsets.map { costs[$0].id }
        costs.remove(atOffsets: offsets)
        if let editingID = editing, removed.contains(editingID) {
            clearDraft()
        }
        store.updateCosts(costs, tripID: tripID, day: day)
    }
}

/// One cost in the list: what it was, its kind and day, and the amount.
private struct CostRow: View {
    let cost: CostItem
    let currency: String

    private var details: String {
        let parts: [String] = [cost.kind?.title, cost.day.map { "Day \($0)" }].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cost.name)
                if !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Money.format(cost.amount, currency: currency))
                .monospacedDigit()
        }
    }
}

/// Links worth keeping with a place: a name and a link, as many as you like (1.27). Tap one to change it, swipe to
/// delete it. Each change saves straight away.
struct LinksSection: View {
    let tripID: UUID
    let day: Int

    @EnvironmentObject var store: TripStore
    @State private var links: [FactLink] = []
    @State private var loaded = false
    @State private var name = ""
    @State private var url = ""
    @State private var editing: UUID? = nil

    private var canSave: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section {
            ForEach(links) { link in
                Button {
                    edit(link)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.title)
                        Text(link.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color.primary)
            }
            .onDelete(perform: delete)
            TextField("Name, e.g. AllTrails", text: $name)
            TextField("Link", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(editing == nil ? "Add link" : "Save changes", action: save)
                .disabled(!canSave)
            if editing != nil {
                Button("Don't change it", role: .cancel, action: clearDraft)
            }
        } header: {
            Text("Links")
        } footer: {
            Text("As many as you like: the trail's page, where you booked, a café.")
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded, let trip = store.trip(id: tripID) else { return }
        loaded = true
        links = trip.dayFacts(day)?.links ?? []
    }

    private func save() {
        let link = FactLink.normalised(url)
        guard !link.isEmpty else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editingID = editing, let index = links.firstIndex(where: { $0.id == editingID }) {
            links[index].name = trimmed
            links[index].url = link
        } else {
            links.append(FactLink(name: trimmed, url: link))
        }
        store.updateLinks(links, tripID: tripID, day: day)
        clearDraft()
    }

    private func edit(_ link: FactLink) {
        editing = link.id
        name = link.name
        url = link.url
    }

    private func clearDraft() {
        name = ""
        url = ""
        editing = nil
    }

    private func delete(at offsets: IndexSet) {
        let removed = offsets.map { links[$0].id }
        links.remove(atOffsets: offsets)
        if let editingID = editing, removed.contains(editingID) {
            clearDraft()
        }
        store.updateLinks(links, tripID: tripID, day: day)
    }
}
