import UIKit

/// One place for the app's very sparing haptic use.
///
/// A privacy utility that buzzes constantly is an anxious one. LensBeacon fires a
/// *single* soft tap the first time a likely/strong flag appears in a session, and
/// nothing else. No repeat, no escalation, no haptic on every advertisement.
@MainActor
enum Haptics {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)

    static func firstFlag() {
        soft.prepare()
        soft.impactOccurred(intensity: 0.6)
    }
}
