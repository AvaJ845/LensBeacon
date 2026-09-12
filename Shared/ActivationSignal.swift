import Foundation

/// Infers a possible "just entered a connection" transition from a short RSSI
/// trajectory: a device reading strong and holding, then abruptly gone — a
/// **cliff** — as opposed to one that was already fading through the bands
/// before it stopped being seen.
///
/// The reasoning: once a BLE central and peripheral complete a connection, the
/// peripheral generally leaves the advertising channels for the connection's own
/// hopping schedule — the same mechanism that can make an already-worn,
/// already-connected pair of camera glasses invisible to any passive scanner
/// (see `SECURITY.md`'s "Known, permanent limitation"). A cliff is *consistent*
/// with that moment. It is exactly as consistent with a body blocking the
/// signal, a phone going into a pocket, or someone turning a corner — RSSI
/// through the real world is noisy, and this cannot tell those apart.
///
/// That's why this is a hypothesis to surface calmly, never a confirmed event —
/// see `DetectionCategory` for the equivalent honesty already applied to
/// evidence-based tiers. It has no push notification and no persistence; it is
/// not wired to one until a real false-positive rate is known from field use.
enum ActivationSignal {
    /// `history` is the smoothed RSSI trajectory, oldest first, ending with the
    /// last reading before the device stopped being seen.
    static func isLikelyCliff(
        history: [Double],
        sampleInterval: TimeInterval,
        strongThreshold: Double = -60,
        minSamples: Int = 6,
        minDuration: TimeInterval = 3
    ) -> Bool {
        guard history.count >= minSamples,
              Double(history.count) * sampleInterval >= minDuration
        else { return false }

        // Held strong for every recent reading — a fade would show the tail
        // declining through weaker bands before the device actually vanished;
        // a cliff holds strong right up to the last sample taken.
        return history.suffix(minSamples).allSatisfy { $0 >= strongThreshold }
    }
}

/// One inferred "possibly just connected" moment — in-memory only, never
/// persisted, never a notification. Deliberately visually distinct from a
/// `Detection`-based flag wherever it's shown: this is inference, not evidence.
struct ActivationEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let peripheralKey: String
    let productName: String
    let category: DetectionCategory
    let lastRSSI: Double
    let at: Date

    init(peripheralKey: String, productName: String, category: DetectionCategory, lastRSSI: Double, at: Date = Date()) {
        self.id = UUID()
        self.peripheralKey = peripheralKey
        self.productName = productName
        self.category = category
        self.lastRSSI = lastRSSI
        self.at = at
    }
}
