import Foundation

/// One persisted row in the Sightings log, keyed by the app's opaque peripheral key.
///
/// There is one record per `peripheralKey`, and re-seeing that key updates
/// `lastSeen`, appends to the capped `timeline`, and keeps the *strongest*
/// `Detection` observed — a device seen at Tier 3 once and Tier 1 later stays at
/// Tier 1, because that is the honest high-water mark.
///
/// **The key is not a stable device identity.** iOS rotates the per-app peripheral
/// UUID along with the hardware address (often every 15 minutes), and LensBeacon
/// makes no attempt to defeat that. So one physical pair of glasses seen across a
/// long session becomes several rows — that is the privacy design working, not a
/// bug. "This is mine" suppression keys on the resolved product (`detection.productKey`),
/// not on this rotating key, so it survives the rotation and a relaunch.
struct Sighting: Identifiable, Codable, Equatable, Sendable {

    /// A single RSSI reading, for the per-device signal timeline. Capped hard
    /// (`maxTimelineSamples`) so the log cannot grow without bound.
    struct Sample: Codable, Equatable, Sendable {
        var at: Date
        var rssi: Int
        var tier: DetectionTier?
        var proximity: ProximityBand
    }

    let id: UUID
    /// iOS per-app peripheral UUID string. Opaque local key — never a hardware MAC.
    let peripheralKey: String

    var firstSeen: Date
    var lastSeen: Date

    /// The strongest detection observed for this key, with all its evidence.
    var detection: Detection

    var timeline: [Sample]

    static let maxTimelineSamples = 60

    // MARK: - Derived

    var category: DetectionCategory { detection.category }
    var tier: DetectionTier? { detection.bestTier }
    var isCameraFlag: Bool { detection.isCameraFlag }
    var isDisplayGlasses: Bool { detection.isDisplayGlasses }
    var productKey: String? { detection.productKey }
    var evidence: [DetectionEvidence] { detection.evidence }

    /// A short, stable label for lists.
    var title: String { detection.displayTitle() }

    // MARK: - Mutation

    /// Folds a fresh detection + reading into this record.
    mutating func update(
        with detection: Detection,
        rssi: Double,
        proximity: ProximityBand,
        at date: Date
    ) {
        lastSeen = date
        self.detection = self.detection.merged(with: detection)

        timeline.append(
            Sample(at: date, rssi: Int(rssi.rounded()), tier: detection.bestTier, proximity: proximity)
        )
        if timeline.count > Self.maxTimelineSamples {
            timeline.removeFirst(timeline.count - Self.maxTimelineSamples)
        }
    }

    static func make(
        peripheralKey: String,
        detection: Detection,
        rssi: Double,
        proximity: ProximityBand,
        at date: Date
    ) -> Sighting {
        Sighting(
            id: UUID(),
            peripheralKey: peripheralKey,
            firstSeen: date,
            lastSeen: date,
            detection: detection,
            timeline: [Sample(at: date, rssi: Int(rssi.rounded()), tier: detection.bestTier, proximity: proximity)]
        )
    }
}

/// A device currently (or very recently) in range — the Dashboard's unit of display.
/// Purely in-memory; the durable version is `Sighting`.
struct LiveSighting: Identifiable, Equatable, Sendable {
    var id: String { peripheralKey }
    let peripheralKey: String

    var detection: Detection
    var smoother: RSSISmoother
    var firstSeen: Date
    var lastSeen: Date
    /// The user marked this product "mine" — suppressed from flags and alerts.
    var isMine: Bool
    /// The most recent raw advertisement, kept only in memory for as long as the
    /// device is in range. It's what "Suggest what this is" reads from — for an
    /// unmatched device, `detection.evidence` is empty (nothing matched), so this
    /// is the only place its fields exist to contribute at all. Never persisted:
    /// dropped the moment the device leaves range, same as everything else here.
    var lastAdvertisement: AdvertisementFields

    var proximity: ProximityBand { smoother.band }
    var tier: DetectionTier? { detection.bestTier }
    var isCameraFlag: Bool { detection.isCameraFlag }
    var isDisplayGlasses: Bool { detection.isDisplayGlasses }
    var productKey: String? { detection.productKey }

    var title: String { detection.displayTitle() }
}
