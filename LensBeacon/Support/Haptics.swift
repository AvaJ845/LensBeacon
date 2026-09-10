import UIKit

/// One place for the app's very sparing haptic use.
///
/// A privacy utility that buzzes constantly is an anxious one. LensBeacon fires a
/// *single* soft tap the first time a flag appears in a session, and a light one
/// when the user resumes scanning. Nothing else — no repeat, no escalation, no
/// haptic on every advertisement.
@MainActor
enum Haptics {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    /// The first likely/strong camera flag of a session.
    static func firstFlag() {
        soft.prepare()
        soft.impactOccurred(intensity: 0.6)
    }

    /// Scanning turned back on.
    static func resume() {
        rigid.prepare()
        rigid.impactOccurred(intensity: 0.4)
    }
}
