import SwiftUI

/// The history: every BLE device LensBeacon has seen, newest activity first,
/// filterable to just camera glasses or just the devices you've marked as yours.
/// The free tier shows the last 7 days; Unlock shows everything.
struct SightingsView: View {

    @Environment(SightingsStore.self) private var store
    @Environment(MineRegistry.self) private var mine
    @Environment(UnlockStore.self) private var unlock
    @Environment(Router.self) private var router

    @State private var filter: SightingsStore.Filter = .glasses
    @State private var exportDocument: CSVDocument?
    @State private var showClearConfirm = false

    private var rows: [Sighting] { store.filtered(filter, mine: mine) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(SightingsStore.Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if rows.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "clock.arrow.circlepath",
                            title: emptyTitle,
                            message: emptyMessage
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(rows) { sighting in
                            NavigationLink(value: sighting.id) {
                                SightingRow(sighting: sighting, isMine: mine.contains(sighting.peripheralKey))
                            }
                        }
                    } footer: {
                        retentionFooter
                    }
                }
            }
            .listStyle(.insetGrouped)
            .lensChrome()
            .navigationTitle("Sightings")
            .navigationDestination(for: UUID.self) { id in
                if let sighting = store.sightings.first(where: { $0.id == id }) {
                    SightingDetailView(source: .record(sighting))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Export CSV", systemImage: "square.and.arrow.up") { prepareExport() }
                            .disabled(rows.isEmpty)
                        Button("Clear history", systemImage: "trash", role: .destructive) {
                            showClearConfirm = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "LensBeacon-Sightings"
            ) { _ in exportDocument = nil }
            .confirmationDialog("Clear all sightings history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { store.clearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every recorded sighting from this iPhone. It cannot be undone.")
            }
            .onChange(of: router.pendingSightingKey) { _, key in
                guard let key, let sighting = store.sightings.first(where: { $0.peripheralKey == key }) else { return }
                filter = .all
                router.pendingSightingKey = nil
                _ = sighting // navigation handled by list; filter switch surfaces it
            }
        }
    }

    private func prepareExport() {
        guard unlock.isUnlocked else { return }
        exportDocument = CSVDocument(text: store.exportCSV(mine: mine))
    }

    @ViewBuilder
    private var retentionFooter: some View {
        if unlock.isUnlocked {
            Text("Unlimited history is on. \(rows.count) shown.")
        } else {
            Text("Free history covers the last 7 days. LensBeacon Unlock keeps everything and adds CSV export.")
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .glasses: return "No camera glasses seen yet"
        case .all:     return "Nothing seen yet"
        case .mine:    return "No devices marked as yours"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .glasses: return "When LensBeacon spots a device matching camera glasses, it will appear here with its evidence."
        case .all:     return "Open the Nearby tab and let LensBeacon scan for a moment."
        case .mine:    return "Open a sighting and tap “This is mine” to stop LensBeacon flagging your own glasses."
        }
    }
}

private struct SightingRow: View {
    let sighting: Sighting
    let isMine: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(sighting.isCameraFlag ? Palette.confidence(sighting.confidence ?? .possible) : .secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(sighting.title).font(.subheadline.weight(.medium))
                Text("last seen \(sighting.lastSeen, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let c = sighting.confidence { ConfidenceBadge(level: c, compact: true) }
                if isMine {
                    Text("Mine").font(.caption2.weight(.semibold)).foregroundStyle(Palette.accent)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch sighting.category {
        case .cameraGlasses: return "eyeglasses"
        case .headset:       return "visionpro"
        case .other:         return "dot.radiowaves.right"
        }
    }
}
