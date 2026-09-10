import SwiftUI

/// Confidence badge — colour **+ SF Symbol + word**, always all three, so it reads
/// in grayscale and to VoiceOver just as well as in colour (HIG: never colour alone).
struct WatchConfidenceBadge: View {
    let level: ConfidenceLevel

    var body: some View {
        Label(level.title, systemImage: level.symbolName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WatchPalette.confidence(level))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WatchPalette.confidence(level).opacity(0.16), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Confidence: \(level.title)")
            .accessibilityHint(level.explanation)
    }
}

/// Proximity — never an arrow, never a distance. Just Near / Nearby / Far.
struct WatchProximityLabel: View {
    let band: ProximityBand

    var body: some View {
        Label(band.title, systemImage: band.symbolName)
            .font(.caption2)
            .foregroundStyle(WatchPalette.proximity(band))
            .accessibilityLabel("Proximity: \(band.title)")
    }
}
