import SwiftUI

/// Confidence badge. Colour + symbol + word, always all three, so it survives
/// grayscale, Increase Contrast, and VoiceOver equally well.
struct ConfidenceBadge: View {
    let level: ConfidenceLevel
    var compact = false

    var body: some View {
        Label {
            Text(level.title)
        } icon: {
            Image(systemName: level.symbolName)
        }
        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        .foregroundStyle(Palette.confidence(level))
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(Palette.confidence(level).opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence: \(level.title)")
        .accessibilityHint(level.explanation)
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
                bullet("A device that is already paired to its owner's phone often goes quiet and won't be detected.")
                bullet("Some wearables only advertise briefly. LensBeacon may see them once and then not again.")
                bullet("A match means a Bluetooth signature looks like camera glasses — not that anyone is recording.")
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

/// Card container matching the theme.
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
    }
}
