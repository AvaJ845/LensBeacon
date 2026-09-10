import SwiftUI

/// The watch app's palette. Same Apple Fellow brand tokens as `Palette` on iOS, but
/// declared with plain SwiftUI `Color` (watchOS has no `UIColor` trait closures and
/// the watch UI is always on a dark field).
///
/// Per the brand brief the navy background must stay *visibly lifted* — never
/// black-on-black — so `canvas` is Deep Navy and `card` is a lifted navy, not black.
enum WatchPalette {
    static let accent   = Color(red: 0.388, green: 0.780, blue: 0.949)   // #63C7F2 Lens Cyan
    static let canvas   = Color(red: 0.043, green: 0.122, blue: 0.200)   // #0B1F33 Deep Navy
    static let card     = Color(red: 0.071, green: 0.231, blue: 0.365)   // lifted navy (#123B5D)
    static let hairline = Color.white.opacity(0.12)

    /// The same calm blue confidence ramp as iOS, tuned for the dark watch field.
    static func confidence(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .possible: return Color(red: 0.66, green: 0.71, blue: 0.80)
        case .likely:   return Color(red: 0.478, green: 0.706, blue: 1.00)
        case .strong:   return Color(red: 0.62, green: 0.84, blue: 0.98)
        }
    }

    static func proximity(_ band: ProximityBand) -> Color {
        switch band {
        case .near:   return accent
        case .nearby: return accent.opacity(0.7)
        case .far:    return Color.secondary
        }
    }
}
