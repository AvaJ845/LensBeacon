import SwiftUI

/// The history: the camera and display glasses LensBeacon has recognised, newest
/// first, each with its evidence — filterable to just the ones you've marked yours.
/// The free tier shows the last 7 days; Unlock shows everything.
struct SightingsView: View {

    @Environment(SightingsStore.self) private var store
    @Environment(MineRegistry.self) private var mine
    @Environment(UnlockStore.self) private var unlock
    @Environment(Router.self) private var router

    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var filter: SightingsStore.Filter = .all
    @State private var exportDocument: CSVDocument?
    @State private var showClearConfirm = false
    @State private var path: [UUID] = []

    private var rows: [Sighting] { store.filtered(filter, mine: mine) }

    /// A segmented control overflows past .xxLarge; fall back to a menu at
    /// accessibility text sizes (HIG-1).
    @ViewBuilder
    private var filterPicker: some View {
        let picker = Picker("Filter", selection: $filter) {
            ForEach(SightingsStore.Filter.allCases) { Text($0.rawValue).tag($0) }
        }
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    filterPicker
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
                                SightingRow(sighting: sighting, isMine: mine.contains(productKey: sighting.productKey))
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
            .task {
                // `-screen detail` launch argument — push the first flagged record
                // for App Store capture. Screenshot tooling only.
                if router.launchScreen == .sightingDetail {
                    router.launchScreen = nil
                    if let first = store.filtered(.all, mine: mine).first {
                        path = [first.id]
                    }
                }
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
        case .all:  return "No glasses seen yet"
        case .mine: return "No glasses marked as yours"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all:  return "When LensBeacon recognises a pair of camera or display glasses, it appears here with the evidence. Anonymous phones and tags are shown live on the Nearby tab but never logged."
        case .mine: return "Open a pair of glasses and turn on “These are mine” to stop LensBeacon flagging them."
        }
    }
}

private struct SightingRow: View {
    let sighting: Sighting
    let isMine: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(sighting.title).font(.subheadline.weight(.medium))
                Text("last seen \(sighting.lastSeen, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if sighting.isDisplayGlasses {
                    NoCameraChip()
                } else if let t = sighting.tier {
                    TierBadge(tier: t, compact: true)
                }
                if isMine {
                    Text("Mine").font(.caption2.weight(.semibold)).foregroundStyle(Palette.accent)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch sighting.category {
        case .cameraGlasses:  return "eyeglasses"
        case .displayGlasses: return "eyeglasses"
        case .headset:        return "visionpro"
        case .unknown:        return "dot.radiowaves.right"
        }
    }

    private var iconColor: Color {
        guard sighting.isCameraFlag, let t = sighting.tier else { return .secondary }
        return Palette.tier(t)
    }
}
