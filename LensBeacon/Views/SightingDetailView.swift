import SwiftUI

/// One device, in full: what it is, the detection tier and why, the exact AD fields
/// that matched with their raw bytes, a simple RSSI timeline, and the "This is mine"
/// switch that suppresses the whole product.
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
    @State private var contributionGuess: DeviceGuess?

    var body: some View {
        List {
            headerSection
            evidenceSection
            contributeSection
            timelineSection
            if productKey != nil { mineSection }
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
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.title3.weight(.semibold))
                        Spacer(minLength: 8)
                        headerChip
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.title3.weight(.semibold))
                        headerChip
                    }
                }

                Text(headerExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let band = displayBand {
                    ProximityMeter(band: band)
                    SignalDetailRow(band: band, rssi: displayRSSI)
                }
                Label(seenRange, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var headerChip: some View {
        if isDisplayGlasses {
            NoCameraChip()
        } else if detection.isHeadset {
            Label("Worn openly", systemImage: "eye").font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        } else if let tier {
            TierBadge(tier: tier)
        }
    }

    private var headerExplanation: String {
        if isDisplayGlasses { return Copy.displayGlasses }
        if detection.isHeadset {
            return "This is a headset — a Meta Quest or an Apple Vision Pro. It carries cameras but is worn openly and obviously. LensBeacon lists it so you know it's here; it is never a covert-camera flag and never raises an alert."
        }
        if let tier { return tier.explanation }
        return "Nothing in the rule table matched. This device is here only as a general Bluetooth sighting."
    }

    private var evidenceSection: some View {
        Section {
            if evidence.isEmpty {
                Text("No rule matched. Logged as a nearby Bluetooth device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(evidence) { row in
                    EvidenceRow(evidence: row)
                }
            }
        } header: {
            Text("Evidence")
        } footer: {
            Text(Copy.notAccusation)
        }
    }

    /// Live devices only — a stored record's raw fields were never kept (only
    /// recognised glasses persist evidence at all; see `SightingsStore.record`).
    /// This is the one path that can turn an *unmatched* device, which has no
    /// evidence to show above, into something reportable.
    @ViewBuilder
    private var contributeSection: some View {
        if case .live(let live) = source {
            Section {
                Text("Wasn't recognised, or recognised wrong? Send the fields LensBeacon read from it, and what you believe it is — LensBeacon still makes no network request of its own; you choose where this goes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("What do you think this is?", selection: $contributionGuess) {
                    Text("Choose one").tag(DeviceGuess?.none)
                    ForEach(DeviceGuess.allCases) { guess in
                        Text(guess.rawValue).tag(Optional(guess))
                    }
                }
                ShareLink(
                    item: ContributionReport.text(for: live.lastAdvertisement, detection: live.detection, guess: contributionGuess)
                ) {
                    Label("Share as evidence", systemImage: "square.and.arrow.up")
                }
                .disabled(contributionGuess == nil)
            } header: {
                Text("Suggest what this is")
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        if samples.count >= 2 {
            Section {
                RSSISparkline(samples: samples)
                    .frame(height: 64)
                    .padding(.vertical, 4)
                Text("Signal strength over the last \(samples.count) readings. \(Copy.proximityOnly)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Signal timeline")
            }
        } else if samples.count == 1 {
            Section("Signal timeline") {
                Text("Seen once, briefly — not enough readings yet to show a trend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mineSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { mine.contains(productKey: productKey) },
                set: { mine.setMine($0, productKey: productKey) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("These are mine")
                    Text("Stop flagging \(title) and hide it from background alerts. Applies wherever this signature appears.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Palette.accent)
        }
    }

    private var explainerSection: some View {
        Section {
            Text("LensBeacon only reads advertisements — it never connects, pairs, or requests anything from a device. The identifier the system shows here rotates on its own, so it cannot be followed over time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Source adapters

    private var detection: Detection {
        switch source {
        case .live(let s):   return s.detection
        case .record(let s): return s.detection
        }
    }
    private var title: String { detection.displayTitle() }
    private var tier: DetectionTier? { detection.bestTier }
    private var isDisplayGlasses: Bool { detection.isDisplayGlasses }
    private var evidence: [DetectionEvidence] { detection.evidence }
    private var productKey: String? { detection.productKey }

    /// The band to show under the header: the live smoothed reading for a device
    /// still in range, or the last reading on file for a stored record. A record's
    /// number is clearly a *past* one (it sits above "last seen …"), so showing it
    /// is a history fact, not a claim that this is happening right now.
    private var displayBand: ProximityBand? {
        switch source {
        case .live(let s):   return s.proximity
        case .record(let s): return s.timeline.last?.proximity
        }
    }
    private var displayRSSI: Int? {
        switch source {
        case .live(let s):   return Int(s.smoother.value.rounded())
        case .record(let s): return s.timeline.last?.rssi
        }
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

/// One AD field that matched a rule, with its raw bytes. Fully labelled for VoiceOver.
private struct EvidenceRow: View {
    let evidence: DetectionEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(evidence.adType.label, systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                TierBadge(tier: evidence.tier, compact: true)
            }
            // The value + raw bytes ARE the evidence — the app's central promise is
            // that you can read them, so they get primary ink and a legible size.
            Text(evidence.matchedValue)
                .font(.callout.monospaced().weight(.medium))
                .textSelection(.enabled)
            Text("AD \(evidence.adType.hexCode)  ·  raw \(evidence.rawBytes)")
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(evidence.ruleTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(evidence.accessibilityLabel)
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
        .accessibilityElement()
        .accessibilityLabel("Signal strength trend")
        .accessibilityValue(axValue)
    }

    private var axValue: String {
        let values = samples.map(\.rssi)
        guard let first = values.first, let last = values.last,
              let low = values.min(), let high = values.max() else {
            return "No readings yet"
        }
        let direction = last > first + 3 ? "rising" : (last < first - 3 ? "falling" : "steady")
        return "\(samples.count) readings, \(direction). From \(first) to \(last) dBm, ranging \(low) to \(high). Higher is closer."
    }
}
