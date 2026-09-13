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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showWeakSignals = false
    @State private var showSettings = false
    @State private var showUnlock = false
    /// Brief calm "Listening…" beat before the reassuring "Nothing flagged" (HIG-2).
    @State private var settled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusHero(state: coordinator.state,
                               flagCount: coordinator.flags.count,
                               isScanning: coordinator.isScanning,
                               isPaused: coordinator.isPaused,
                               settled: settled,
                               onResume: { coordinator.setPaused(false); Haptics.resume() })
                    .padding(.top, 8)

                    if coordinator.state == .unauthorized || coordinator.state == .poweredOff {
                        PermissionCard(state: coordinator.state)
                    }

                    if coordinator.isScanning && !coordinator.isPaused && !coordinator.allInRange.isEmpty {
                        NearbySummary(inRange: coordinator.allInRange.count,
                                      flagged: coordinator.flags.count,
                                      headsets: coordinator.headsets.count,
                                      displayGlasses: coordinator.displayGlasses.count)
                    }

                    if !coordinator.flags.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(coordinator.flags) { flag in
                                NavigationLink(value: flag.peripheralKey) {
                                    FlagRow(flag: flag)
                                }
                                .buttonStyle(.plain)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity))
                            }
                        }
                        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85),
                                   value: coordinator.flags.map(\.id))
                    }

                    seenNotFlaggedSection
                    recentActivationsSection

                    LimitsNote()
                        .padding(.horizontal, 4)

                    if !unlock.isUnlocked {
                        UnlockPromoCard { showUnlock = true }
                    }
                }
                .padding(16)
            }
            .lensChrome()
            .scrollIndicators(.hidden)
            .navigationTitle("Nearby")
            .navigationDestination(for: String.self) { key in
                if let live = coordinator.live[key] {
                    SightingDetailView(source: .live(live))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        let wasPaused = coordinator.isPaused
                        coordinator.setPaused(!wasPaused)
                        if wasPaused { Haptics.resume() }
                    } label: {
                        Label(coordinator.isPaused ? "Resume scanning" : "Pause scanning",
                              systemImage: coordinator.isPaused ? "play.circle" : "pause.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showUnlock) { UnlockView() }
            .task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { settled = true }
            }
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

    /// Name-only camera matches, display glasses (no camera), and headsets worn
    /// openly — everything LensBeacon *sees* but deliberately does not flag or alert
    /// on — collapsed into one disclosure with a single caption. Keeps the Dashboard
    /// to: status → flags → this → everything else.
    @ViewBuilder
    private var seenNotFlaggedSection: some View {
        let items = coordinator.weakSignals + coordinator.displayGlasses + coordinator.headsets
        if !items.isEmpty {
            DisclosureGroup(isExpanded: $showWeakSignals) {
                VStack(spacing: 8) {
                    ForEach(items) { device in
                        NavigationLink(value: device.peripheralKey) {
                            OtherDeviceRow(device: device, isMine: mine.contains(productKey: device.productKey))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("A name that matched but nothing stronger, display glasses with no camera, and headsets worn openly. LensBeacon lists them — it never flags or alerts on any of them.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            } label: {
                Label("Seen nearby, not flagged (\(items.count))", systemImage: "eye")
                    .font(.subheadline.weight(.medium))
            }
            .tint(Palette.accent)
            .padding(.horizontal, 4)
        }
    }

    // `otherDevicesSection` (the "Also broadcasting nearby" disclosure listing
    // every anonymous, unmatched device in range) was cut entirely — a typical
    // room has dozens of anonymous BLE peripherals (TVs, earbuds, appliances),
    // and even collapsed by default, an always-present "(37)" count read as
    // noise rather than reassurance on a screen whose whole design goal is
    // calm. `seenNotFlaggedSection` above still shows anything that matched a
    // pattern without being flagged; `NearbySummary`'s quiet "N in range" line
    // still proves the scan is live without itemizing what's in range. App
    // Review verification note updated accordingly — see AppStore/REVIEW_NOTES.md.

    /// A signal that read strong, then vanished abruptly rather than fading —
    /// consistent with a device that just connected to a phone, and exactly as
    /// consistent with mundane things (a pocket, a turned corner). Deliberately
    /// never styled like a `FlagRow` — a guess must never look like evidence.
    @ViewBuilder
    private var recentActivationsSection: some View {
        if !coordinator.recentActivations.isEmpty {
            DisclosureGroup {
                VStack(spacing: 8) {
                    ForEach(coordinator.recentActivations) { event in
                        ActivationRow(event: event)
                    }
                    Text("A signal held strong, then stopped abruptly instead of fading — that can mean a device just connected to a phone, or just as easily that it went behind something. This is a guess, never a finding.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            } label: {
                Label("Possible activity nearby (\(coordinator.recentActivations.count))", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.medium))
            }
            .tint(Palette.secondaryText)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Nearby summary

/// One quiet line: how much Bluetooth is around, and how much of it LensBeacon
/// cares about. Gives the scan a sense of place without adding a card.
private struct NearbySummary: View {
    let inRange: Int
    let flagged: Int
    let headsets: Int
    let displayGlasses: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.caption2)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Palette.card.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline))
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        var parts = ["\(inRange) in range"]
        if flagged > 0 { parts.append("\(flagged) flagged") }
        let openly = headsets + displayGlasses
        if openly > 0 { parts.append("\(openly) worn openly") }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - Status hero

/// The top of the Dashboard. A centred presence — the beacon mark, breathing, with
/// two slow rings while it listens — that resolves into a calm count when a flag
/// appears. No siren, no red, never a full-bleed alarm.
private struct StatusHero: View {
    let state: BluetoothScanner.State
    let flagCount: Int
    let isScanning: Bool
    let isPaused: Bool
    let settled: Bool
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ScanField(active: isScanning && !isPaused && flagCount == 0, tint: tint)

            VStack(spacing: 4) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.center)
                Text(subline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if isPaused {
                Button("Resume scanning", systemImage: "play.fill", action: onResume)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .animation(.default, value: headline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(subline)")
    }

    private var headline: String {
        if isPaused { return "Scanning paused" }
        switch state {
        case .unauthorized: return "Bluetooth access is off"
        case .poweredOff:   return "Bluetooth is off"
        case .unsupported:  return "Bluetooth isn’t available"
        case .idle:         return "Not scanning"
        case .scanning:
            switch flagCount {
            case 0:  return settled ? "Nothing flagged" : "Listening"
            case 1:  return "1 camera flag nearby"
            default: return "\(flagCount) camera flags nearby"
            }
        }
    }

    private var subline: String {
        if isPaused { return "LensBeacon has stopped listening. Nothing is being detected or logged." }
        switch state {
        case .unauthorized: return "Turn on Bluetooth for LensBeacon in Settings to scan."
        case .poweredOff:   return "Turn on Bluetooth in Control Centre to scan."
        case .unsupported:  return "This device has no Bluetooth LE radio."
        case .idle:         return "Scanning resumes when you return to this screen."
        case .scanning:
            switch flagCount {
            case 0:  return settled ? Copy.notAccusation
                                    : "Checking nearby Bluetooth for camera-glasses signatures."
            default: return "Each flag shows exactly which Bluetooth signals matched. Tap for the evidence."
            }
        }
    }

    private var tint: Color {
        if isPaused { return .secondary }
        switch state {
        case .scanning where flagCount > 0: return Palette.tier(.serviceUUID)
        case .unauthorized, .poweredOff, .unsupported: return .secondary
        default: return Palette.accent
        }
    }
}

// MARK: - Rows

private struct FlagRow: View {
    let flag: LiveSighting

    var body: some View {
        HStack(spacing: 0) {
            // A quiet tier-coloured spine — informative, never loud.
            if let t = flag.tier {
                Palette.tier(t).frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 9) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(flag.title).font(.headline)
                        Spacer(minLength: 8)
                        if let t = flag.tier { TierBadge(tier: t) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(flag.title).font(.headline)
                        if let t = flag.tier { TierBadge(tier: t) }
                    }
                }
                HStack(spacing: 12) {
                    ProximityMeter(band: flag.proximity)
                    Text("seen \(flag.firstSeen, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // Signal strength (dBm) lives in the detail screen only — this card
                // already states proximity once, via the meter above. Fellows'
                // verdict: showing it twice in a "quiet" card is the loud thing.
                if let first = flag.detection.evidence.first {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.accent)
                        Text("\(first.adType.label): \(first.matchedValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 14)
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Palette.deepNavy.opacity(0.06), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full evidence")
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
        switch device.detection.category {
        case .cameraGlasses, .displayGlasses: return "eyeglasses"
        case .headset: return "visionpro"
        case .unknown: return "dot.radiowaves.right"
        }
    }

    private var category: String {
        switch device.detection.category {
        case .displayGlasses: return "Display glasses — no camera"
        case .headset:        return isMine ? "Headset — marked as yours" : "Headset — worn openly, not flagged"
        case .cameraGlasses:
            if isMine { return "Camera glasses — marked as yours" }
            return device.tier.map { "Camera glasses — \($0.title.lowercased())" } ?? "Camera glasses"
        case .unknown: return "Unrecognised Bluetooth device"
        }
    }
}

/// One inferred "possibly just connected" moment. Dashed, unfilled — deliberately
/// nothing like `FlagRow`'s solid card, so an inference can never be mistaken for
/// evidence at a glance (HIG: never encode meaning with shape/weight alone either —
/// this pairs the visual difference with an explicit label and caption text).
private struct ActivationRow: View {
    let event: ActivationEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.productName).font(.subheadline)
                Text("Signal dropped abruptly \(event.at, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.productName), signal dropped abruptly \(event.at.formatted(.relative(presentation: .named))) ago — a guess, not a confirmed activation")
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
                Text("Background scanning, a Home Screen widget, a live watch complication, unlimited history and CSV export. One payment, no subscription.")
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
