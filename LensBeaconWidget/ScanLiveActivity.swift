import WidgetKit
import SwiftUI
import ActivityKit

/// Lock Screen + Dynamic Island presentation for the background-scan Live Activity.
///
/// Tone: a status line, not an alarm. It says "LensBeacon is scanning" and a count.
/// No red, no siren glyph, no "THREAT" language. The user can end it from the Lock
/// Screen at any time, which also stops background scanning (the app observes the
/// activity ending).
struct ScanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScanActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Palette.canvas.opacity(0.9))
                .activitySystemActionForegroundColor(Palette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.flaggedCount)", systemImage: "eyeglasses")
                        .font(.title3.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let band = context.state.nearestBand {
                        Text(band.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.flaggedCount == 0
                         ? "LensBeacon is scanning. Nothing flagged."
                         : "LensBeacon flagged \(context.state.flaggedCount) nearby.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "dot.radiowaves.left.and.right")
            } compactTrailing: {
                Text("\(context.state.flaggedCount)")
            } minimal: {
                Text("\(context.state.flaggedCount)")
            }
            .keylineTint(Palette.accent)
        }
    }
}

private struct LockScreenView: View {
    let state: ScanActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("LensBeacon — \(state.headline)")
                    .font(.subheadline.weight(.semibold))
                Text(subline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }

    private var subline: String {
        var parts: [String] = []
        if let c = state.strongestConfidence { parts.append("strongest: \(c.title)") }
        if let b = state.nearestBand { parts.append("nearest: \(b.title)") }
        if parts.isEmpty { return "Scanning in the background" }
        return parts.joined(separator: " · ")
    }
}
