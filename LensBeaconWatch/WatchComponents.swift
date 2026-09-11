import SwiftUI

/// Tier badge — colour **+ SF Symbol + word**, always all three, so it reads in
/// grayscale and to VoiceOver just as well as in colour (HIG: never colour alone).
struct WatchTierBadge: View {
    let tier: DetectionTier

    var body: some View {
        Label(tier.shortTitle, systemImage: tier.symbolName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WatchPalette.tier(tier))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WatchPalette.tier(tier).opacity(0.16), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Signal strength: \(tier.title)")
            .accessibilityHint(tier.explanation)
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
