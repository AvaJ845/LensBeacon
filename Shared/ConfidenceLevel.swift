import Foundation

/// How sure LensBeacon is that a Bluetooth device is camera glasses.
///
/// The scale is deliberately coarse — three steps, not a percentage. A percentage
/// would imply a precision the underlying signals do not have: BLE advertisements
/// are noisy, manufacturers reuse company IDs across product lines, and names are
/// often absent. Three honest bands the user can reason about beat a false-precision
/// number they cannot.
///
/// Ordering matters (`Comparable`): the Dashboard sorts strongest-first, and the
/// confidence engine picks the highest band any matched rule produced.
enum ConfidenceLevel: Int, CaseIterable, Comparable, Codable, Sendable {
    /// One weak signal matched — usually a manufacturer/company ID that a known
    /// glasses vendor uses, but also uses for phones, controllers and earbuds.
    case possible = 1
    /// Two independent signals agree — e.g. the manufacturer ID *and* a service
    /// UUID that the glasses' companion protocol advertises.
    case likely = 2
    /// Manufacturer ID, service UUID, *and* the advertised name matches a known
    /// pattern for the product. About as certain as a passive scan can be.
    case strong = 3

    static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short label for badges. Sentence case, never shouting.
    var title: String {
        switch self {
        case .possible: return "Possible"
        case .likely:   return "Likely"
        case .strong:   return "Strong"
        }
    }

    /// One plain sentence the detail screen shows under the badge.
    var explanation: String {
        switch self {
        case .possible:
            return "One signal points to camera glasses. Devices like phones and earbuds can also produce this signal."
        case .likely:
            return "Two independent Bluetooth signals agree. This is probably camera glasses."
        case .strong:
            return "The manufacturer signal, a service identifier, and the device name all match a known product."
        }
    }

    /// SF Symbol paired with the badge so colour is never the only cue (HIG:
    /// accessibility — do not rely on colour alone).
    var symbolName: String {
        switch self {
        case .possible: return "circle.dotted"
        case .likely:   return "circle.lefthalf.filled"
        case .strong:   return "circle.fill"
        }
    }
}
