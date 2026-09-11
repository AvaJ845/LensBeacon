import SwiftUI

/// The whole watch app: one glanceable screen.
///
/// Hierarchy is deliberately two levels deep — this list, and a detail per flag.
/// No tabs, no history, no settings. The watch answers one question ("is there a
/// camera near me right now?") and, on a tap, "why does it think so?".
struct WatchRootView: View {

    @Environment(WatchScanModel.self) private var model
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch model.state {
                    case .unauthorized, .poweredOff, .unsupported:
                        UnavailableCard(state: model.state)
                    default:
                        if model.flags.isEmpty {
                            ScanningState(isScanning: model.isScanning)
                        } else {
                            summary
                            ForEach(model.flags) { flag in
                                NavigationLink(value: flag.id) {
                                    FlagRow(flag: flag)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .scrollContentBackground(.hidden)
            .background(WatchPalette.canvas.ignoresSafeArea())
            .navigationTitle("LensBeacon")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let flag = model.flags.first(where: { $0.id == id }) {
                    WatchDetailView(flag: flag)
                }
            }
            .task {
                // `-screen detail` — App Store screenshot capture only.
                if ProcessInfo.processInfo.arguments.contains("-screen"),
                   ProcessInfo.processInfo.arguments.contains("detail"),
                   let first = model.flags.first {
                    path = [first.id]
                }
            }
        }
        .tint(WatchPalette.accent)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.flags.count == 1 ? "Camera glasses nearby" : "\(model.flags.count) camera glasses nearby")
                .font(.headline)
            if let t = model.strongestTier, let b = model.nearestBand {
                Text("\(t.title) · nearest \(b.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - States

private struct ScanningState: View {
    let isScanning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(WatchPalette.accent)
                .symbolEffect(.pulse, options: .repeating, isActive: isScanning && !reduceMotion)
            Text(isScanning ? "Scanning" : "Not scanning")
                .font(.headline)
            Text(isScanning
                 ? "Nothing nearby matches a camera-glasses signature."
                 : "Open LensBeacon to start.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
    }
}

private struct UnavailableCard: View {
    let state: BluetoothScanner.State

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(.headline)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WatchPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var title: String {
        switch state {
        case .unauthorized: return "Bluetooth access is off"
        case .poweredOff:   return "Bluetooth is off"
        default:            return "Bluetooth unavailable"
        }
    }
    private var detail: String {
        switch state {
        case .unauthorized: return "Allow Bluetooth for LensBeacon on your watch to scan."
        case .poweredOff:   return "Turn Bluetooth on to scan."
        default:            return "This watch has no Bluetooth LE radio."
        }
    }
}

// MARK: - Row

private struct FlagRow: View {
    let flag: WatchSighting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(flag.title)
                .font(.headline)
                .lineLimit(1)
            HStack {
                if let t = flag.tier { WatchTierBadge(tier: t) }
                Spacer(minLength: 4)
                WatchProximityLabel(band: flag.proximity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WatchPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
