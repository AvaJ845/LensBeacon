import SwiftUI

/// "Why does it think so?" — the evidence for one flag, one scroll, no deeper.
struct WatchDetailView: View {
    let flag: WatchSighting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(flag.title)
                    .font(.headline)

                if let c = flag.confidence {
                    WatchConfidenceBadge(level: c)
                    Text(c.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    WatchProximityLabel(band: flag.proximity)
                    Text("Signal strength only — no direction.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !flag.evidenceBullets.isEmpty {
                    Divider().overlay(WatchPalette.hairline)
                    Text("Evidence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(flag.evidenceBullets.enumerated()), id: \.offset) { _, bullet in
                        Label(bullet, systemImage: "checkmark.seal")
                            .font(.caption2)
                    }
                }

                Text("A match means a Bluetooth signature looks like camera glasses — not that anyone is recording. Open LensBeacon on iPhone for the full history.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
