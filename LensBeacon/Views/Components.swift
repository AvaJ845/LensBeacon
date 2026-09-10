import SwiftUI

/// Detection-tier badge. Colour + symbol + word, always all three, so it survives
/// grayscale, Increase Contrast, and VoiceOver equally well — the tier is never
/// carried by colour alone.
struct TierBadge: View {
    let tier: DetectionTier
    var compact = false

    var body: some View {
        Label {
            Text(tier.title)
        } icon: {
            Image(systemName: tier.symbolName)
        }
        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        .foregroundStyle(Palette.tier(tier))
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(Palette.tier(tier).opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal strength: \(tier.title)")
        .accessibilityHint(tier.explanation)
    }
}

/// A quiet "display glasses — no camera" chip for Even Realities and similar.
struct NoCameraChip: View {
    var body: some View {
        Label("No camera", systemImage: "eye.slash")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .accessibilityLabel("Display glasses, no camera")
    }
}

/// Proximity band chip. Never an arrow, never a distance — just near / nearby / far.
struct ProximityChip: View {
    let band: ProximityBand

    var body: some View {
        Label(band.title, systemImage: band.symbolName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Palette.proximity(band))
            .accessibilityLabel("Proximity: \(band.title)")
    }
}

/// Three ascending bars filled by band, next to the word. A glanceable proximity
/// read — deliberately coarse, and it makes **no** claim about distance in metres or
/// direction (the signal cannot support either).
struct ProximityMeter: View {
    let band: ProximityBand

    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i < level ? Palette.proximity(band) : Color.secondary.opacity(0.25))
                        .frame(width: 4, height: CGFloat(6 + i * 5))
                }
            }
            Text(band.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Palette.proximity(band))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Proximity: \(band.title). A rough sense of distance only — no direction.")
    }

    private var level: Int {
        switch band {
        case .far:    return 1
        case .nearby: return 2
        case .near:   return 3
        }
    }
}

/// A calm, reusable empty state — icon, one line of title, one line of detail.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 320)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The little "what this can't see" disclosure used on the Dashboard and in
/// onboarding. Honesty about the tool's limits is part of the calm-utility posture.
struct LimitsNote: View {
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                bullet(Copy.notAccusation)
                bullet(Copy.standaloneSilence)
                bullet(Copy.proximityOnly)
                bullet("Device signatures are refined with each update as vendors change how their hardware broadcasts.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        } label: {
            Label("What LensBeacon can’t tell you", systemImage: "info.circle")
                .font(.footnote.weight(.medium))
        }
        .tint(Palette.accent)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text)
        }
    }
}

/// Card container matching the theme — a soft raised surface, a hairline, and a
/// whisper of shadow for depth (kept low so nothing "floats").
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.hairline)
            )
            .shadow(color: Palette.deepNavy.opacity(0.06), radius: 8, y: 3)
    }
}
