import Foundation

/// A coarse distance bucket derived from RSSI.
///
/// LensBeacon makes **no directional claim** — no arrows, no "getting warmer", no
/// metres. RSSI through a real body and real walls is far too noisy for that, and a
/// confident arrow pointing at a stranger is exactly the alarmist UI this app must
/// not be. Three buckets, smoothed over a short window, is the honest ceiling.
enum ProximityBand: Int, Comparable, Codable, Sendable, CaseIterable {
    case far = 0
    case nearby = 1
    case near = 2

    static func < (lhs: ProximityBand, rhs: ProximityBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .near:   return "Near"
        case .nearby: return "Nearby"
        case .far:    return "Far"
        }
    }

    var symbolName: String {
        switch self {
        case .near:   return "dot.radiowaves.left.and.right"
        case .nearby: return "wave.3.right"
        case .far:    return "wave.3.right.circle"
        }
    }

    /// Thresholds in dBm. RSSI is negative; closer is less negative. These are
    /// deliberately wide so a hand movement does not make the band flicker.
    ///
    /// - `>= -55`  : within a couple of metres — `near`
    /// - `-55..-75`: same room — `nearby`
    /// - `< -75`   : across the room or through a wall — `far`
    static func band(forSmoothedRSSI rssi: Double) -> ProximityBand {
        switch rssi {
        case let r where r >= -55: return .near
        case let r where r >= -75: return .nearby
        default:                   return .far
        }
    }

    /// A plain-English translation of the band for the curious reader who taps
    /// into "Signal details" — never a number of metres or feet, because RSSI
    /// through a real body, pocket, or wall can't support one. Lowercase, meant
    /// to complete a sentence like "Near — \(roughDistanceHint)".
    var roughDistanceHint: String {
        switch self {
        case .near:   return "roughly arm's length to a few steps away"
        case .nearby: return "roughly the same room"
        case .far:    return "across the room, through a wall, or farther"
        }
    }
}

/// Exponential moving average over RSSI samples for one device.
///
/// CoreBluetooth delivers a fresh RSSI on every advertisement — several a second for
/// an active device. Feeding raw values to the UI makes the proximity band strobe.
/// This smooths with a light EMA and only reports a band change when the smoothed
/// value has genuinely crossed a threshold, so the Dashboard stays calm.
struct RSSISmoother: Sendable, Equatable {
    /// 0…1. Lower = smoother and slower to react. 0.25 settles in roughly a second
    /// of steady advertising without lagging a real approach.
    private let alpha: Double
    private(set) var value: Double

    init(initialRSSI: Double, alpha: Double = 0.25) {
        self.alpha = alpha
        self.value = initialRSSI
    }

    mutating func add(_ sample: Double) {
        // Ignore the sentinel CoreBluetooth uses when it has no reading (127) and
        // absurd values that only mean "unknown".
        guard sample < 0, sample > -120 else { return }
        value = alpha * sample + (1 - alpha) * value
    }

    var band: ProximityBand { ProximityBand.band(forSmoothedRSSI: value) }
}
