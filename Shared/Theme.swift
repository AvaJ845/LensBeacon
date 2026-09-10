import SwiftUI

/// LensBeacon's visual language: calm, factual, closer to a field notebook than a
/// security console.
///
/// The palette is the Apple Fellow brand kit (`Fellow_Brief/LENSBEACON_BRAND_SPEC.md`
/// / `Icon_Source/LensBeaconBrandTokens.json`): a Beacon Blue accent on a near-white
/// canvas in light mode, lifted to Lens Cyan on a Deep Navy canvas in dark mode.
/// Status colours are a single muted blue ramp — never red, never a "go" green —
/// because "strong" should read as *certain*, not as *danger*.
///
/// Every status colour is paired with an SF Symbol and a text label in the UI, so
/// the colour is reinforcement, never the sole carrier of meaning (HIG:
/// accessibility — do not rely on colour alone).
enum Palette {

    // MARK: - Brand tokens (fixed, appearance-independent)

    /// #0B1F33 — icon field, dark-mode canvas.
    static let deepNavy   = Color(red: 0.043, green: 0.122, blue: 0.200)
    /// #3B82F6 — the interactive Beacon Blue.
    static let beaconBlue = Color(red: 0.231, green: 0.510, blue: 0.965)
    /// #63C7F2 — the lighter Lens Cyan, used as the dark-mode accent.
    static let lensCyan   = Color(red: 0.388, green: 0.780, blue: 0.949)
    /// #10B981 — reserved teal. Deliberately not used for status (avoids a
    /// "safe / all-clear" reading of a colour).
    static let teal       = Color(red: 0.063, green: 0.725, blue: 0.506)
    /// #E5EAF2
    static let coolGray   = Color(red: 0.898, green: 0.918, blue: 0.949)
    /// #64748B
    static let secondaryText = Color(red: 0.392, green: 0.455, blue: 0.545)

    // MARK: - Adaptive surfaces

    /// Interactive tint. Beacon Blue in light mode; Lens Cyan on dark for contrast
    /// against the navy canvas. Kept in exact sync with `AccentColor.colorset`.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.388, green: 0.780, blue: 0.949, alpha: 1)   // #63C7F2
            : UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)   // #3B82F6
    })

    /// Screen background. #F8FAFC light, Deep Navy #0B1F33 dark.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.043, green: 0.122, blue: 0.200, alpha: 1)
            : UIColor(red: 0.973, green: 0.980, blue: 0.988, alpha: 1)
    })

    /// Card / raised surface. White light; a lifted navy (the icon gradient's high
    /// end, #123B5D) on dark so cards never sit black-on-black.
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.071, green: 0.231, blue: 0.365, alpha: 1)
            : UIColor.white
    })

    static let hairline = Color.primary.opacity(0.08)

    // MARK: - Status colours (always paired with text + symbol in the UI)

    /// Confidence bands as one calm blue ramp:
    /// - `possible` — a quiet grey; the "one weak signal" state, should not draw the eye.
    /// - `likely`   — Beacon Blue; two signals agree.
    /// - `strong`   — a deeper, more saturated blue; reads as *settled*, not urgent.
    static func confidence(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .possible:
            return Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.64, green: 0.69, blue: 0.78, alpha: 1)      // AA on the navy card
                : UIColor(red: 0.40, green: 0.45, blue: 0.53, alpha: 1) })
        case .likely:
            return Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.478, green: 0.706, blue: 1.00, alpha: 1)
                : UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1) }) // #3B82F6
        case .strong:
            return Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.62, green: 0.84, blue: 0.98, alpha: 1)
                : UIColor(red: 0.13, green: 0.31, blue: 0.62, alpha: 1) })    // deep settled blue
        }
    }

    static func proximity(_ band: ProximityBand) -> Color {
        switch band {
        case .near:   return accent
        case .nearby: return accent.opacity(0.65)
        case .far:    return Color.secondary
        }
    }
}

extension View {
    /// Standard screen chrome: quiet canvas, brand tint, hidden default list background.
    func lensChrome() -> some View {
        self
            .tint(Palette.accent)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
    }
}
