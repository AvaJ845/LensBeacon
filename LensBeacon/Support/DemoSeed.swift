import Foundation

/// Seeds the Sightings log with a small, fixed set of records for App Store
/// screenshots and demos — enabled only by the `-demo-data` launch argument, which
/// is never present on a normal launch.
///
/// Honest by construction: every record is produced by running a synthetic
/// advertisement through the *real* `DetectionEngine`, so the tier and the evidence
/// on screen are exactly what the app would show for a device broadcasting that
/// advertisement. It seeds history only — the Dashboard's "nearby now" stays
/// genuinely empty until a real scan finds something.
enum DemoSeed {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo-data")
    }

    /// Manufacturer data payload for a company identifier (little-endian prefix).
    private static func mfg(_ company: UInt16) -> Data {
        Data([UInt8(company & 0xFF), UInt8(company >> 8)])
    }

    @MainActor
    static func apply(to store: SightingsStore, mine: MineRegistry) {
        guard isRequested, store.sightings.isEmpty else { return }

        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        // (advertisement, opaque key, rssi, first seen, last seen, mine?)
        let entries: [(AdvertisementFields, String, Double, Date, Date, Bool)] = [
            // Tier 1 — Luxottica company ID + name → High confidence camera flag.
            (.init(manufacturerData: mfg(0x0D53), localName: "Ray-Ban Meta"),
             "demo-t1", -49, ago(2.5), ago(0.3), false),
            // Tier 3 — name only → Low, in-app badge, no notification.
            (.init(localName: "Spectacles 7C"),
             "demo-t3", -79, ago(30), ago(22), false),
            // Display glasses, no camera — Even Realities G1.
            (.init(localName: "Even G1_7_L_a1b2"),
             "demo-display", -66, ago(50), ago(44), false),
            // The user's own glasses, marked mine — suppressed from flags. A distinct
            // product from the others so the demo shows a flag AND a "mine" row.
            (.init(localName: "HeyCyan G2"),
             "demo-mine", -45, ago(96), ago(1.2), true),
        ]

        for (ad, key, rssi, first, last, isMine) in entries {
            let detection = DetectionEngine.classify(ad)
            let band = ProximityBand.band(forSmoothedRSSI: rssi)
            _ = store.record(peripheralKey: key, detection: detection, rssi: rssi, proximity: band, at: first)
            if last != first {
                _ = store.record(peripheralKey: key, detection: detection, rssi: rssi + 3, proximity: band, at: last)
            }
            if isMine { mine.setMine(true, productKey: detection.productKey) }
        }
        store.saveNow()
    }
}
