import Foundation

// See `PacketClassifier.swift` for why this file is un-gated (pure + testable)
// while the capture/session UI that produces its inputs is `#if DEBUG`-only.

/// Ground truth for one physical device the operator says was actually present
/// during a session, in the plain, capture-independent shape analysis code
/// takes — mirrors the `#if DEBUG` `@Model DeviceState`. Independent booleans,
/// not one enum: the operator answers each question as observed, and a
/// combination the field protocol doesn't expect (e.g. `poweredOff && worn`)
/// is still recorded rather than disallowed — forcing a premature category at
/// entry time would hide an operator's mistake instead of surfacing it.
/// `category` below derives the bucket the true-positive analysis actually uses.
struct DeviceStateRecord: Sendable, Equatable {
    let label: String
    let present: Bool
    let paired: Bool
    let worn: Bool
    let activelyRecording: Bool
    let inBagOrCase: Bool
    let poweredOff: Bool

    init(
        label: String, present: Bool = true, paired: Bool = false, worn: Bool = false,
        activelyRecording: Bool = false, inBagOrCase: Bool = false, poweredOff: Bool = false
    ) {
        self.label = label
        self.present = present
        self.paired = paired
        self.worn = worn
        self.activelyRecording = activelyRecording
        self.inBagOrCase = inBagOrCase
        self.poweredOff = poweredOff
    }

    /// The single segmentation bucket this state falls into for true-positive
    /// analysis — most-specific condition checked first, so a device can only
    /// ever land in one bucket even if the operator's answers overlap oddly.
    var category: DeviceStateCategory {
        if poweredOff { return .poweredOff }
        if inBagOrCase { return .bagged }
        if worn && paired { return .wornAndPaired }
        if paired { return .idlePairedNotWorn }
        return .unpairedPresent
    }
}

enum DeviceStateCategory: String, CaseIterable, Sendable, Hashable {
    case wornAndPaired
    case idlePairedNotWorn
    case bagged
    case poweredOff
    case unpairedPresent

    var title: String {
        switch self {
        case .wornAndPaired:     return "Worn + paired"
        case .idlePairedNotWorn: return "Paired, not worn (idle)"
        case .bagged:            return "In bag/case"
        case .poweredOff:        return "Powered off"
        case .unpairedPresent:   return "Present, unpaired"
        }
    }
}

/// Every computation here operates on plain `[PacketRecord]`/`[DeviceStateRecord]`
/// arrays — no persistence type crosses this boundary, so the whole analysis
/// layer is re-runnable, offline, against an entire archive the moment the
/// classification hypothesis changes, exactly as the harness spec requires.
enum SessionAnalyzer {

    // MARK: - Per-device summary

    struct DeviceSummary: Identifiable, Sendable {
        var id: String { peripheralID }
        let peripheralID: String
        let packetCount: Int
        /// "0x058E" → count, one entry per company ID actually seen from this peripheral.
        let companyIDCounts: [String: Int]
        let confirmedCount: Int
        let companyIDOnlyCount: Int
        let firstSeen: Date
        let lastSeen: Date
        /// Gaps between consecutive packets from this peripheral, in seconds —
        /// the crux metric. A device seen once in 40 minutes is not detectable
        /// in practice, even though it technically "detected" once.
        let intervalSeconds: [Double]
        let rssiValues: [Int]

        var meanIntervalSeconds: Double? {
            intervalSeconds.isEmpty ? nil : intervalSeconds.reduce(0, +) / Double(intervalSeconds.count)
        }
        var medianIntervalSeconds: Double? { Self.median(intervalSeconds) }
        var maxIntervalSeconds: Double? { intervalSeconds.max() }
        var meanRSSI: Double? {
            rssiValues.isEmpty ? nil : Double(rssiValues.reduce(0, +)) / Double(rssiValues.count)
        }
        var minRSSI: Int? { rssiValues.min() }
        var maxRSSI: Int? { rssiValues.max() }

        private static func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
    }

    static func summarize(_ packets: [PacketRecord]) -> [DeviceSummary] {
        let grouped = Dictionary(grouping: packets, by: \.peripheralID)
        return grouped.map { peripheralID, group in
            let sorted = group.sorted { $0.timestamp < $1.timestamp }
            var companyIDCounts: [String: Int] = [:]
            var confirmed = 0
            var companyOnly = 0
            for p in sorted {
                if let id = p.companyID {
                    companyIDCounts[String(format: "0x%04X", id), default: 0] += 1
                }
                switch PacketClassifier.classify(p) {
                case .payloadConfirmed, .unambiguousVendor: confirmed += 1
                case .companyIDOnly: companyOnly += 1
                case .other: break
                }
            }
            var intervals: [Double] = []
            if sorted.count > 1 {
                for i in 1..<sorted.count {
                    intervals.append(sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp))
                }
            }
            return DeviceSummary(
                peripheralID: peripheralID,
                packetCount: sorted.count,
                companyIDCounts: companyIDCounts,
                confirmedCount: confirmed,
                companyIDOnlyCount: companyOnly,
                firstSeen: sorted.first!.timestamp,
                lastSeen: sorted.last!.timestamp,
                intervalSeconds: intervals,
                rssiValues: sorted.map(\.rssi)
            )
        }.sorted { $0.packetCount > $1.packetCount }
    }

    // MARK: - Payload-confirmed vs company-ID-only ratio

    /// Of packets whose company ID is one where a payload check is even
    /// meaningful (0x058E / 0x01AB — shared with Quest), what fraction carried
    /// the confirming fingerprint. `nil` when no such packet exists in the set
    /// — never `0`, since "no ambiguous packets seen" and "all of them failed
    /// confirmation" are very different findings.
    ///
    /// This is the number that quantifies the false-positive problem a bare
    /// company-ID scanner ships with: a low ratio here means most of what such
    /// a scanner would flag as "glasses" on these IDs is something else, most
    /// plausibly a Quest.
    static func payloadConfirmedRatio(_ packets: [PacketRecord]) -> Double? {
        let ambiguous = packets.filter {
            $0.companyID == PacketClassifier.metaRealityLabs || $0.companyID == PacketClassifier.metaPlatforms
        }
        guard !ambiguous.isEmpty else { return nil }
        let confirmed = ambiguous.filter { PacketClassifier.classify($0) == .payloadConfirmed }.count
        return Double(confirmed) / Double(ambiguous.count)
    }

    // MARK: - True positive / time-to-first-detection, by ground-truth category

    struct SessionOutcome: Sendable {
        let category: DeviceStateCategory?     // nil when the session tagged no devices
        let anyConfirmedDetection: Bool
        let anyCompanyIDOnlyDetection: Bool
        let timeToFirstConfirmedDetection: TimeInterval?
    }

    /// One outcome per tagged device state in a session — **not** per packet or
    /// per peripheral, because there is no reliable way to attribute a specific
    /// rotating `peripheralID` to a specific named device the operator tagged
    /// (iOS rotates it; see `RawPacket`'s doc comment). A session with more than
    /// one tagged device can only honestly answer "was *any* confirmed
    /// signature seen at all", never "which of the N devices produced it" — the
    /// field protocol in `HARNESS.md` exists specifically to steer around this
    /// by asking for one tagged device per session wherever the crux question
    /// is what's being measured.
    static func outcomes(
        startedAt: Date, deviceStates: [DeviceStateRecord], packets: [PacketRecord]
    ) -> [SessionOutcome] {
        let confirmedPackets = packets
            .filter { PacketClassifier.classify($0).isConfirmed }
            .sorted { $0.timestamp < $1.timestamp }
        let anyConfirmed = !confirmedPackets.isEmpty
        let anyCompanyIDOnly = packets.contains { PacketClassifier.classify($0) == .companyIDOnly }
        let ttfd = confirmedPackets.first.map { $0.timestamp.timeIntervalSince(startedAt) }

        guard !deviceStates.isEmpty else {
            return [SessionOutcome(
                category: nil, anyConfirmedDetection: anyConfirmed,
                anyCompanyIDOnlyDetection: anyCompanyIDOnly, timeToFirstConfirmedDetection: ttfd
            )]
        }
        return deviceStates.map { state in
            SessionOutcome(
                category: state.category, anyConfirmedDetection: anyConfirmed,
                anyCompanyIDOnlyDetection: anyCompanyIDOnly, timeToFirstConfirmedDetection: ttfd
            )
        }
    }

    /// Aggregate true-positive rate across many sessions' outcomes, grouped by
    /// ground-truth category. `totalSessions == 0` (rate `nil`) must never be
    /// rendered the same way as a real `0%` — they mean very different things:
    /// no data yet, versus a measured zero detection rate.
    struct TruePositiveRate: Sendable {
        let category: DeviceStateCategory
        let detectedSessions: Int
        let totalSessions: Int
        var rate: Double? { totalSessions == 0 ? nil : Double(detectedSessions) / Double(totalSessions) }
    }

    static func truePositiveRates(_ outcomes: [SessionOutcome]) -> [TruePositiveRate] {
        DeviceStateCategory.allCases.map { category in
            let matching = outcomes.filter { $0.category == category }
            let detected = matching.filter(\.anyConfirmedDetection).count
            return TruePositiveRate(category: category, detectedSessions: detected, totalSessions: matching.count)
        }
    }
}
