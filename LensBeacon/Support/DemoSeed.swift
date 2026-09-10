import Foundation

/// Seeds the Sightings log with a small, fixed set of records for App Store
/// screenshots and demos — enabled only by the `-demo-data` launch argument, which
/// is never present on a normal launch.
///
/// It is honest by construction: every record is produced by running a synthetic
/// advertisement through the *real* `ConfidenceEngine`, so the confidence band and
/// the evidence bullets on screen are exactly what the app would show for a device
/// broadcasting that advertisement. It seeds history only — it never injects a live
/// Dashboard flag, and the Dashboard's "nearby now" stays genuinely empty until a
/// real scan finds something.
enum DemoSeed {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo-data")
    }

    @MainActor
    static func apply(to store: SightingsStore, mine: MineRegistry) {
        guard isRequested, store.sightings.isEmpty else { return }

        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        // (advertisement, opaque key, rssi, when first seen, when last seen, mine?)
        // Each advertisement is chosen so the real engine lands on a different band:
        let entries: [(ConfidenceEngine.Advertisement, String, Double, Date, Date, Bool)] = [
            // manufacturer + service + name -> strong
            (.init(companyIdentifier: 0x03A3, serviceUUIDs: ["FDF0"], localName: "Ray-Ban Meta", isConnectable: true),
             "demo-strong", -49, ago(2.5), ago(0.3), false),
            // manufacturer + name -> likely
            (.init(companyIdentifier: 0x03A3, serviceUUIDs: [], localName: "Oakley Vanguard", isConnectable: true),
             "demo-likely-oakley", -63, ago(27), ago(3), false),
            // manufacturer + service, no name -> likely
            (.init(companyIdentifier: 0x0819, serviceUUIDs: ["FE60"], localName: nil, isConnectable: true),
             "demo-likely-snap", -79, ago(30), ago(22), false),
            // manufacturer only -> possible
            (.init(companyIdentifier: 0x03A3, serviceUUIDs: [], localName: nil, isConnectable: false),
             "demo-possible", -88, ago(50), ago(49), false),
            // headset name -> logged, never flagged as a covert camera
            (.init(companyIdentifier: 0x03A3, serviceUUIDs: [], localName: "Meta Quest 3", isConnectable: true),
             "demo-headset", -66, ago(120), ago(118), false),
            // the user's own glasses, marked "mine" -> suppressed from flags
            (.init(companyIdentifier: 0x03A3, serviceUUIDs: ["FDF0"], localName: "Oakley Meta", isConnectable: true),
             "demo-mine", -45, ago(96), ago(1.2), true),
        ]

        for (ad, key, rssi, first, last, isMine) in entries {
            let classification = ConfidenceEngine.classify(ad)
            let band = ProximityBand.band(forSmoothedRSSI: rssi)
            _ = store.record(peripheralKey: key, classification: classification,
                             rssi: rssi, proximity: band, at: first)
            if last != first {
                _ = store.record(peripheralKey: key, classification: classification,
                                 rssi: rssi + 3, proximity: band, at: last)
            }
            if isMine { mine.setMine(true, key: key) }
        }
        store.saveNow()
    }
}
