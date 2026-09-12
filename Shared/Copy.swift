import Foundation

/// The load-bearing sentences about what LensBeacon is and is not. Kept in one place
/// so onboarding, the empty state, the evidence view and the App Store description
/// never drift, and so a reviewer skimming the app sees the same framing everywhere:
/// **awareness of a device broadcasting in the open — never accusation of a person.**
enum Copy {

    /// Must appear in onboarding AND in the empty state.
    static let notAccusation = "A detection is not proof that anyone is recording, and quiet is not proof that no one is."

    /// The standalone-silence caveat, Fellow-worded.
    static let standaloneSilence = "Most camera glasses keep broadcasting while they are worn, so they are usually detectable. A few standalone models with no phone link can stay silent."

    /// Proximity honesty.
    static let proximityOnly = "Signal strength gives a rough sense of distance only. LensBeacon never shows a direction, a track, or a name."

    /// Even Realities line for the display-glasses category.
    static let displayGlasses = "These are display glasses with no camera. LensBeacon lists them so you know what they are; it never counts them as a camera nearby."

    /// Bluetooth advertisements carry no signature — every field a device broadcasts
    /// is self-reported, including the manufacturer identifier. A $0 BLE advertiser
    /// tool can clone one in under a minute (confirmed against a real capture); a
    /// tier says how specific a match is, never that the broadcaster is genuine.
    static let selfReported = "Every field here is self-reported by the device, the same way a name tag can say anything. LensBeacon reads it, but can't verify it — a match names a signature, never a guarantee."
}
