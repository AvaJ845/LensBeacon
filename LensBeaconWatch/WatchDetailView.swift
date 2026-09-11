import SwiftUI

/// "Why does it think so?" — the evidence for one flag, one scroll, no deeper.
struct WatchDetailView: View {
    let flag: WatchSighting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(flag.title)
                    .font(.headline)

                if let t = flag.tier {
                    WatchTierBadge(tier: t)
                    Text(t.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    WatchProximityLabel(band: flag.proximity)
                    Text("Signal strength only — no direction.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !flag.evidence.isEmpty {
                    Divider().overlay(WatchPalette.hairline)
                    Text("Evidence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(flag.evidence) { e in
                        VStack(alignment: .leading, spacing: 1) {
                            Label("\(e.adType.label): \(e.matchedValue)", systemImage: "checkmark.seal")
                                .font(.caption2)
                            Text("raw \(e.rawBytes) · \(e.tier.shortTitle)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(e.accessibilityLabel)
                    }
                }

                Text(Copy.notAccusation + " Open LensBeacon on iPhone for the full history.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .scrollContentBackground(.hidden)
        .background(WatchPalette.canvas.ignoresSafeArea())
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
