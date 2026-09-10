import SwiftUI

/// LensBeacon's visual language: calm, factual, closer to a field notebook than a
/// security console. The palette is deliberately quiet — a single teal accent, warm
/// neutral surfaces, and status colours that are muted rather than siren-bright.
///
/// Every status colour has a text label and an SF Symbol beside it in the UI, so the
/// colour is reinforcement, never the sole carrier of meaning (HIG accessibility).
enum Palette {

    /// Interactive tint. A deep teal in light mode; lifted for contrast on dark.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.78, blue: 0.76, alpha: 1)
            : UIColor(red: 0.10, green: 0.42, blue: 0.42, alpha: 1)
    })

    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1)
            : UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1)
    })

    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.15, blue: 0.17, alpha: 1)
            : UIColor.white
    })

    static let hairline = Color.primary.opacity(0.08)

    // MARK: - Status colours (always paired with text + symbol in the UI)

    /// Confidence bands. Muted amber → clay, never red. "Strong" must still not read
    /// as danger — it reads as *certain*, which is a calm thing to be.
    static func confidence(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .possible:
            return Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.70, green: 0.70, blue: 0.74, alpha: 1)
                : UIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1) })
        case .likely:
            return Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.92, green: 0.74, blue: 0.42, alpha: 1)
                : UIColor(red: 0.72, green: 0.52, blue: 0.16, alpha: 1) })
        case .strong:
            return Color(uiColor: UIColor { t in t.userInterfaceStyle == .dark
                ? UIColor(red: 0.86, green: 0.56, blue: 0.42, alpha: 1)
                : UIColor(red: 0.68, green: 0.36, blue: 0.24, alpha: 1) })
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

extension View {
    /// Standard screen chrome: quiet canvas, teal tint, hidden default list background.
    func lensChrome() -> some View {
        self
            .tint(Palette.accent)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
    }
}
