import SwiftUI

/// One device, in full: what it is, how sure we are, the exact signals that matched,
/// a simple RSSI timeline, and the "This is mine" switch that suppresses it.
///
/// It accepts either a live in-range device or a stored record, so the Dashboard and
/// the Sightings log can both push to the same screen.
struct SightingDetailView: View {

    enum Source {
        case live(LiveSighting)
        case record(Sighting)
    }

    let source: Source

    @Environment(MineRegistry.self) private var mine
    @Environment(SightingsStore.self) private var store

    var body: some View {
        List {
            headerSection
            evidenceSection
            timelineSection
            mineSection
            explainerSection
        }
        .listStyle(.insetGrouped)
        .lensChrome()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    if let c = confidence { ConfidenceBadge(level: c) }
                }
                if let c = confidence {
                    Text(c.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if category == .headset {
                    Text("This is a headset — worn openly and obviously. LensBeacon lists it but never flags it as a hidden camera.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    if let band = liveBand { ProximityChip(band: band) }
                    Label(seenRange, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var evidenceSection: some View {
        Section("Evidence") {
            if bullets.isEmpty {
                Text("No signature clauses matched — this device is here only as a general Bluetooth sighting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    Label(bullet, systemImage: "checkmark.seal")
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        if !samples.isEmpty {
            Section("Signal timeline") {
                RSSISparkline(samples: samples)
                    .frame(height: 64)
                    .padding(.vertical, 4)
                Text("Signal strength over the last \(samples.count) readings. Higher means closer. LensBeacon makes no directional claim.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mineSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { mine.contains(peripheralKey) },
                set: { mine.setMine($0, key: peripheralKey) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This is mine")
                    Text("Stop flagging this device and hide it from alerts.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Palette.accent)
        }
    }

    private var explainerSection: some View {
        Section {
            Text("LensBeacon identifies devices only by the Bluetooth advertisements they broadcast. It never connects, never pairs, and never reads anything from a device. The identifier shown to the system rotates on its own — there is nothing here that tracks a person.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Source adapters

    private var title: String {
        switch source {
        case .live(let s):   return s.title
        case .record(let s): return s.title
        }
    }
    private var confidence: ConfidenceLevel? {
        switch source {
        case .live(let s):   return s.confidence
        case .record(let s): return s.confidence
        }
    }
    private var category: DeviceCategory {
        switch source {
        case .live(let s):   return s.classification.category ?? .other
        case .record(let s): return s.category
        }
    }
    private var peripheralKey: String {
        switch source {
        case .live(let s):   return s.peripheralKey
        case .record(let s): return s.peripheralKey
        }
    }
    private var bullets: [String] {
        switch source {
        case .live(let s):   return s.classification.evidence.flatMap(\.bullets)
        case .record(let s): return s.evidenceBullets
        }
    }
    private var liveBand: ProximityBand? {
        if case .live(let s) = source { return s.proximity }
        return nil
    }
    private var seenRange: String {
        let (first, last): (Date, Date)
        switch source {
        case .live(let s):   (first, last) = (s.firstSeen, s.lastSeen)
        case .record(let s): (first, last) = (s.firstSeen, s.lastSeen)
        }
        let f = first.formatted(date: .abbreviated, time: .shortened)
        return "First \(f) · last seen \(last.formatted(.relative(presentation: .named)))"
    }
    private var samples: [Sighting.Sample] {
        switch source {
        case .record(let s): return s.timeline
        case .live(let s):
            return store.sightings.first { $0.peripheralKey == s.peripheralKey }?.timeline ?? []
        }
    }
}

/// A minimal RSSI sparkline. No axes, no gridlines — a shape, because the exact
/// numbers do not matter, only the trend.
private struct RSSISparkline: View {
    let samples: [Sighting.Sample]

    var body: some View {
        GeometryReader { geo in
            let values = samples.map { Double($0.rssi) }
            let minV = (values.min() ?? -100) - 2
            let maxV = (values.max() ?? -40) + 2
            let span = max(maxV - minV, 1)

            Path { path in
                for (i, v) in values.enumerated() {
                    let x = values.count > 1 ? geo.size.width * Double(i) / Double(values.count - 1) : 0
                    let y = geo.size.height * (1 - (v - minV) / span)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .accessibilityLabel("Signal strength trend over \(samples.count) readings")
    }
}
