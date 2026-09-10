import SwiftUI

/// "What's around me right now." The screen leads with a plain-language status line,
/// then the flagged devices (if any), then an opt-in list of everything else in
/// range. It is intentionally undramatic: no full-bleed red, no pulsing siren — a
/// flag is a row with a badge and its evidence, nothing more.
struct DashboardView: View {

    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(MineRegistry.self) private var mine
    @Environment(UnlockStore.self) private var unlock
    @Environment(Router.self) private var router

    @State private var showAllDevices = false
    @State private var showSettings = false
    @State private var showUnlock = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusHeader(state: coordinator.state,
                                 flagCount: coordinator.flags.count,
                                 isScanning: coordinator.isScanning)

                    if coordinator.state == .unauthorized || coordinator.state == .poweredOff {
                        PermissionCard(state: coordinator.state)
                    }

                    if !coordinator.flags.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(coordinator.flags) { flag in
                                NavigationLink(value: flag.peripheralKey) {
                                    FlagRow(flag: flag)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if coordinator.isScanning {
                        EmptyStateView(
                            symbol: "checkmark.shield",
                            title: "Nothing flagged",
                            message: "No nearby Bluetooth device matches a known camera-glasses signature."
                        )
                    }

                    otherDevicesSection

                    LimitsNote()
                        .padding(.horizontal, 4)

                    if !unlock.isUnlocked {
                        UnlockPromoCard { showUnlock = true }
                    }
                }
                .padding(16)
            }
            .lensChrome()
            .navigationTitle("Nearby")
            .navigationDestination(for: String.self) { key in
                if let live = coordinator.live[key] {
                    SightingDetailView(source: .live(live))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showUnlock) { UnlockView() }
            .task {
                // `-screen settings|unlock` launch argument — App Store screenshot
                // capture only; never set in normal operation.
                switch router.launchScreen {
                case .settings:
                    showSettings = true
                    router.launchScreen = nil
                case .unlock:
                    showUnlock = true
                    router.launchScreen = nil
                default:
                    break
                }
            }
        }
    }

    @ViewBuilder
    private var otherDevicesSection: some View {
        let others = coordinator.allInRange.filter { !$0.isCameraFlag || $0.isMine }
        if !others.isEmpty {
            DisclosureGroup(isExpanded: $showAllDevices) {
                VStack(spacing: 8) {
                    ForEach(others) { device in
                        NavigationLink(value: device.peripheralKey) {
                            OtherDeviceRow(device: device, isMine: mine.contains(device.peripheralKey))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Everything else in range (\(others.count))", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.medium))
            }
            .tint(Palette.accent)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Header

private struct StatusHeader: View {
    let state: BluetoothScanner.State
    let flagCount: Int
    let isScanning: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .symbolEffect(.pulse, options: .repeating, isActive: isScanning && flagCount == 0)
                    Text(headline)
                        .font(.title3.weight(.semibold))
                }
                Text(subline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(subline)")
    }

    private var headline: String {
        switch state {
        case .unauthorized: return "Bluetooth access is off"
        case .poweredOff:   return "Bluetooth is off"
        case .unsupported:  return "Bluetooth isn’t available"
        case .idle:         return "Not scanning"
        case .scanning:
            switch flagCount {
            case 0:  return "Scanning — nothing flagged"
            case 1:  return "1 possible camera nearby"
            default: return "\(flagCount) possible cameras nearby"
            }
        }
    }

    private var subline: String {
        switch state {
        case .unauthorized: return "Turn on Bluetooth for LensBeacon in Settings to scan."
        case .poweredOff:   return "Turn on Bluetooth in Control Center to scan."
        case .unsupported:  return "This device has no Bluetooth LE radio."
        case .idle:         return "Open scanning resumes when you return to this screen."
        case .scanning:     return flagCount == 0
            ? "LensBeacon is listening for camera-glasses signatures."
            : "Each flag below shows exactly which Bluetooth signals matched."
        }
    }

    private var symbol: String {
        switch state {
        case .scanning: return flagCount == 0 ? "dot.radiowaves.left.and.right" : "eye.trianglebadge.exclamationmark"
        case .unauthorized, .poweredOff: return "antenna.radiowaves.left.and.right.slash"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    private var tint: Color {
        switch state {
        case .scanning where flagCount > 0: return Palette.confidence(.likely)
        case .unauthorized, .poweredOff, .unsupported: return .secondary
        default: return Palette.accent
        }
    }
}

// MARK: - Rows

private struct FlagRow: View {
    let flag: LiveSighting

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(flag.title).font(.headline)
                    Spacer()
                    if let c = flag.confidence { ConfidenceBadge(level: c) }
                }
                HStack(spacing: 12) {
                    ProximityChip(band: flag.proximity)
                    Text("seen \(flag.firstSeen, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let first = flag.classification.evidence.first?.bullets.first {
                    Text(first)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("Tap for the full evidence")
                    .font(.caption2)
                    .foregroundStyle(Palette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OtherDeviceRow: View {
    let device: LiveSighting
    let isMine: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.title).font(.subheadline)
                Text(category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isMine {
                Text("Mine").font(.caption2.weight(.semibold)).foregroundStyle(Palette.accent)
            }
            ProximityChip(band: device.proximity)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var icon: String {
        switch device.classification.category {
        case .headset: return "visionpro"
        case .cameraGlasses: return "eyeglasses"
        default: return "dot.radiowaves.right"
        }
    }

    private var category: String {
        switch device.classification.category {
        case .headset: return "Headset — worn openly, not flagged"
        case .cameraGlasses: return isMine ? "Camera glasses — marked as yours" : "Camera glasses"
        default: return "Unrecognised Bluetooth device"
        }
    }
}

// MARK: - Cards

private struct PermissionCard: View {
    let state: BluetoothScanner.State

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label(state == .poweredOff ? "Bluetooth is off" : "LensBeacon needs Bluetooth",
                      systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Text(state == .poweredOff
                     ? "LensBeacon uses Bluetooth to detect nearby camera glasses. It never connects to any device."
                     : "Grant Bluetooth access so LensBeacon can scan. It is used only to listen for advertisements — never to connect or transmit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if state == .unauthorized {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct UnlockPromoCard: View {
    let action: () -> Void
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("LensBeacon Unlock", systemImage: "lock.open")
                    .font(.headline)
                Text("Background scanning, a Home Screen widget, a Live Activity, unlimited history and CSV export. One payment, no subscription.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("See what’s included", action: action)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    RootView()
        .environment(Router.shared)
        .environment(SightingsStore())
        .environment(MineRegistry())
        .environment(UnlockStore())
        .environment(ScanCoordinator(sightings: SightingsStore(), mine: MineRegistry()))
}
