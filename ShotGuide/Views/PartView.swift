import SwiftUI

/// One part of the day (1.28), like At the spot: its shots in the order you'd film them, grouped by what the phone goes
/// on so the tripod only goes up once, with roughly how long each group takes. The creative shots are in a drop-down
/// at the bottom. Tap a shot for its card, then film it. Swipe one away when the place doesn't have it.
struct PartView: View {
    let tripID: UUID
    let day: Int
    let part: TripPhase

    @EnvironmentObject var store: TripStore
    @State private var card: ShotRow? = nil
    @AppStorage("creativeOpen") private var creativeOpen = false

    var body: some View {
        Group {
            if let trip = store.trip(id: tripID) {
                list(trip)
            } else {
                Text("This trip couldn't be found.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(part.title)
        .shotFlow(tripID: tripID, day: day, card: $card)
    }

    private func list(_ trip: Trip) -> some View {
        List {
            Section {
                Text(part.intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            ForEach(part.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        rowButton(row, trip: trip, short: usesShortTitles(group))
                    }
                } header: {
                    Text(header(for: group, trip: trip))
                } footer: {
                    if group.rows.contains(where: { $0.roleInfo?.isSubstitute == true }) {
                        Text("A swap-in stands in for one the place doesn't have.")
                    }
                }
            }
            if !part.creative.isEmpty {
                creativeSection(trip)
            }
            if hasRowsThatCount(trip) {
                Section {
                } footer: {
                    Text("Swipe a shot left for Not today when the place doesn't have it. It stops counting against the day.")
                }
            }
        }
    }

    /// On B-roll's own groups and On the way, the group already says the shot, so the rows just say the kind.
    private func usesShortTitles(_ group: RowGroup) -> Bool {
        part == .onTheWay || group.id == "broll" || group.id == "detail"
    }

    /// "Tripod · 7 shots · about 15 min", or "B-roll · 6 kinds, plus 2 swap-ins · all done".
    private func header(for group: RowGroup, trip: Trip) -> String {
        var pieces = [group.title]
        let roles = group.rows.compactMap { $0.roleInfo }
        if group.id == "broll" || group.id == "detail", roles.count == group.rows.count {
            let usual = roles.filter { !$0.isSubstitute && !$0.isOptional }.count
            let swaps = roles.filter { $0.isSubstitute }.count
            var kinds = "\(usual) kinds"
            if swaps == 1 {
                kinds += ", plus a swap-in"
            } else if swaps > 1 {
                kinds += ", plus \(swaps) swap-ins"
            }
            pieces.append(kinds)
        } else {
            pieces.append(group.rows.count == 1 ? "1 shot" : "\(group.rows.count) shots")
        }
        if let minutes = trip.minutesLeft(in: group.rows, day: day) {
            pieces.append(minutes == 0 ? "all done" : "about \(minutes) min")
        }
        return pieces.joined(separator: " · ")
    }

    private func hasRowsThatCount(_ trip: Trip) -> Bool {
        part.rows.contains { trip.canSetAside($0, day: day) || trip.isNotToday($0, day: day) }
    }

    private func rowButton(_ row: ShotRow, trip: Trip, short: Bool) -> some View {
        let status = trip.status(of: row, day: day)
        let away = trip.isNotToday(row, day: day)
        let canSwipe = trip.canSetAside(row, day: day)
        return Button {
            card = row
        } label: {
            ShotRowLabel(title: short ? row.shortTitle : row.title, line: row.line, status: status)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if away {
                Button {
                    store.setNotToday(row.key, away: false, day: day, tripID: tripID)
                } label: {
                    Label("Back on", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
            } else if canSwipe {
                Button {
                    store.setNotToday(row.key, away: true, day: day, tripID: tripID)
                } label: {
                    Label("Not today", systemImage: "moon.zzz.fill")
                }
                .tint(.gray)
            }
        }
    }

    // MARK: Creative shots

    private func creativeSection(_ trip: Trip) -> some View {
        Section {
            DisclosureGroup(isExpanded: $creativeOpen) {
                ForEach(part.creative) { row in
                    creativeRow(row, trip: trip)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Creative shots")
                        .font(.headline)
                    Text("Pick any you want today. They don't count towards the day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func creativeRow(_ row: ShotRow, trip: Trip) -> some View {
        let filmed = trip.takes(of: row, day: day).count
        let label = ShotRowLabel(title: row.title, line: row.line, status: filmed > 0 ? RowStatus.filmed(filmed) : nil,
                                 mount: row.mount.title)
        if row.shot == .matchCut {
            // Pick the move first: the camera sticks to it, so every place lines up.
            Menu {
                Section("Which move?") {
                    ForEach(MatchMove.allCases) { move in
                        Button {
                            card = ShotRow(shot: .matchCut, variant: move.rawValue)
                        } label: {
                            Text(moveTitle(move))
                        }
                    }
                }
            } label: {
                label
            }
        } else {
            Button {
                card = row
            } label: {
                label
            }
        }
    }

    /// "Leap · filmed at 3 places".
    private func moveTitle(_ move: MatchMove) -> String {
        let places = move.places(in: store.trips)
        guard places > 0 else { return move.title }
        return move.title + " · filmed at \(places) \(places == 1 ? "place" : "places")"
    }
}

/// A shot on a list: its name, a short line, and how it's going today.
struct ShotRowLabel: View {
    let title: String
    let line: String
    let status: RowStatus?
    /// For the creative shots: what the phone goes on.
    var mount: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .opacity(status == RowStatus.notToday ? 0.45 : 1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let status {
                    RowStatusBadge(status: status)
                }
                if let mount {
                    Text(mount)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .foregroundStyle(Color.primary)
    }
}

/// "0/1", a green "✓ 2", "Not today", "optional", "swap-in" or "extra".
struct RowStatusBadge: View {
    let status: RowStatus

    var body: some View {
        switch status {
        case .notToday:
            pill("Not today", colour: .secondary)
        case .filmed(let count):
            Label("\(count)", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.green)
                .accessibilityLabel(count == 1 ? "Filmed" : "Filmed \(count) times")
        case .progress(let done, let target):
            if target > 0 && done >= target {
                Label("\(done)/\(target)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.green)
            } else {
                Text("\(done)/\(target)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .optional:
            pill("optional", colour: .secondary)
        case .swapIn:
            pill("swap-in", colour: .secondary)
        case .extra, .spare:
            pill("extra", colour: .secondary)
        }
    }

    private func pill(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(colour)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
    }
}
