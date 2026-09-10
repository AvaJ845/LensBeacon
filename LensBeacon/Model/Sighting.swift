import Foundation

/// One persisted row in the Sightings log: everything LensBeacon has ever seen a
/// given BLE device do, aggregated by the app's opaque peripheral key.
///
/// There is exactly one record per `peripheralKey`. Re-seeing a device updates
/// `lastSeen`, appends to the capped `timeline`, and keeps the *strongest*
/// classification observed — a device that was `possible` once and `strong` later
/// stays `strong` in the log, because that is the honest high-water mark.
struct Sighting: Identifiable, Codable, Equatable, Sendable {

    /// A single RSSI reading, for the per-device signal timeline. Capped hard
    /// (`maxTimelineSamples`) so the log cannot grow without bound.
    struct Sample: Codable, Equatable, Sendable {
        var at: Date
        var rssi: Int
        var confidence: ConfidenceLevel?
        var proximity: ProximityBand
    }

    let id: UUID
    /// iOS per-app peripheral UUID string. Opaque local key — never a hardware MAC.
    let peripheralKey: String

    var firstSeen: Date
    var lastSeen: Date

    var category: DeviceCategory
    /// Strongest confidence ever observed for this device (camera glasses only).
    var confidence: ConfidenceLevel?
    var productName: String?
    var vendor: String?
    /// Evidence bullets for the strongest classification — what actually matched.
    var evidenceBullets: [String]

    var timeline: [Sample]

    static let maxTimelineSamples = 60

    var isCameraFlag: Bool { category == .cameraGlasses && confidence != nil }

    /// A short, stable label for lists. Falls back through product → vendor → generic.
    var title: String {
        if let productName { return productName }
        if let vendor { return "\(vendor) device" }
        switch category {
        case .cameraGlasses: return "Camera glasses"
        case .headset:       return "Headset"
        case .other:         return "Bluetooth device"
        }
    }

    /// Folds a fresh classification + reading into this record.
    mutating func update(
        with classification: ConfidenceEngine.Classification,
        rssi: Double,
        proximity: ProximityBand,
        at date: Date
    ) {
        lastSeen = date

        // Keep the strongest classification seen so far.
        let incomingConfidence = classification.confidence
        let isStronger: Bool = {
            switch (confidence, incomingConfidence) {
            case (nil, .some): return true
            case let (.some(a), .some(b)): return b > a
            default: return false
            }
        }()
        if isStronger || category == .other {
            if let cat = classification.category { category = cat }
            confidence = incomingConfidence ?? confidence
            productName = classification.productName ?? productName
            vendor = classification.vendor ?? vendor
            let bullets = classification.evidence.flatMap(\.bullets)
            if !bullets.isEmpty { evidenceBullets = bullets }
        }

        timeline.append(
            Sample(at: date, rssi: Int(rssi.rounded()),
                   confidence: incomingConfidence, proximity: proximity)
        )
        if timeline.count > Self.maxTimelineSamples {
            timeline.removeFirst(timeline.count - Self.maxTimelineSamples)
        }
    }

    static func make(
        peripheralKey: String,
        classification: ConfidenceEngine.Classification,
        rssi: Double,
        proximity: ProximityBand,
        at date: Date
    ) -> Sighting {
        Sighting(
            id: UUID(),
            peripheralKey: peripheralKey,
            firstSeen: date,
            lastSeen: date,
            category: classification.category ?? .other,
            confidence: classification.confidence,
            productName: classification.productName,
            vendor: classification.vendor,
            evidenceBullets: classification.evidence.flatMap(\.bullets),
            timeline: [
                Sample(at: date, rssi: Int(rssi.rounded()),
                       confidence: classification.confidence, proximity: proximity)
            ]
        )
    }
}

/// A device currently (or very recently) in range — the Dashboard's unit of display.
/// Purely in-memory; the durable version is `Sighting`.
struct LiveSighting: Identifiable, Equatable, Sendable {
    var id: String { peripheralKey }
    let peripheralKey: String

    var classification: ConfidenceEngine.Classification
    var smoother: RSSISmoother
    var firstSeen: Date
    var lastSeen: Date
    var isMine: Bool

    var proximity: ProximityBand { smoother.band }
    var confidence: ConfidenceLevel? { classification.confidence }
    var isCameraFlag: Bool { classification.isCameraFlag }

    var title: String {
        classification.productName
            ?? classification.vendor.map { "\($0) device" }
            ?? "Bluetooth device"
    }
}
