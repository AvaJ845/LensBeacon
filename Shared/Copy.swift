import Foundation

/// The load-bearing sentences about what LensBeacon is and is not. Kept in one place
/// so onboarding, the empty state, the evidence view and the App Store description
/// never drift, and so a reviewer skimming the app sees the same framing everywhere:
/// **awareness of a device broadcasting in the open — never accusation of a person.**
enum Copy {

    /// Must appear in onboarding AND in the empty state.
    static let notAccusation = "A detection is not proof that anyone is recording, and quiet is not proof that no one is."

    /// The standalone-silence caveat, Fellow-worded. Deliberately hedged in both
    /// directions rather than asserting "usually detectable" — whether a pair stays
    /// discoverable once connected to its owner's phone is genuinely unconfirmed
    /// pending our own hardware capture (docs/DEVICE-TESTING.md), and BLE's own
    /// mechanics (a connected peripheral typically stops advertising) argue it may
    /// not. Revisit this string the moment that capture lands either way.
    static let standaloneSilence = "Whether a pair keeps broadcasting once it's connected to its owner's phone varies by model, and LensBeacon can only detect one that is. A silent scan is never proof nothing is nearby."

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
