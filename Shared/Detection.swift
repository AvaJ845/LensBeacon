import Foundation

/// The Bluetooth advertising-data (AD) field types LensBeacon reasons about.
///
/// CoreBluetooth hands an app already-parsed keys, not the raw AD structure, so the
/// mapping is: `0xFF` ← manufacturer data, `0x03` ← the 16-bit service-UUID list,
/// `0x16` ← 16-bit service *data*, `0x09` ← the local name (CoreBluetooth merges the
/// shortened `0x08` and complete `0x09` forms and does not tell us which arrived).
enum ADType: UInt8, Codable, Sendable, CaseIterable {
    case serviceUUIDs16   = 0x03
    case shortenedName    = 0x08
    case completeName     = 0x09
    case serviceData16    = 0x16
    case manufacturerData = 0xFF

    /// Human label for the evidence row.
    var label: String {
        switch self {
        case .serviceUUIDs16, .serviceData16: return "Service UUID"
        case .shortenedName, .completeName:   return "Device name"
        case .manufacturerData:               return "Manufacturer ID"
        }
    }

    var hexCode: String { String(format: "0x%02X", rawValue) }
}

/// Confidence tier of a rule. **Tier drives every UX weight in the app** — what may
/// raise a background notification, what shows as a prominent flag vs. a quiet
/// badge, and how the evidence view frames it. It is never encoded by colour alone.
enum DetectionTier: Int, Codable, Comparable, Sendable, CaseIterable {

    /// Tier 3 — a local-name match only. Low confidence. Logged and shown in-app as a
    /// quiet badge; **never** raises a background notification.
    case name = 1
    /// Tier 2 — a 16-bit service UUID registered to a wearables vendor. Medium
    /// confidence. Alert-eligible, but the evidence view labels it a weaker signal.
    case serviceUUID = 2
    /// Tier 1 — a manufacturer company identifier. High confidence. Alert-eligible
    /// and the full-strength path (background notification + Live Activity).
    case manufacturer = 3

    static func < (l: DetectionTier, r: DetectionTier) -> Bool { l.rawValue < r.rawValue }

    /// Short chip label. Paired with `symbolName` and a sentence — colour is never the
    /// only cue (HIG: do not encode meaning with colour alone).
    var title: String {
        switch self {
        case .manufacturer: return "High confidence"
        case .serviceUUID:  return "Medium confidence"
        case .name:         return "Low confidence"
        }
    }

    var shortTitle: String {
        switch self {
        case .manufacturer: return "High"
        case .serviceUUID:  return "Medium"
        case .name:         return "Low"
        }
    }

    /// SF Symbol, so the tier reads without colour.
    var symbolName: String {
        switch self {
        case .manufacturer: return "circle.fill"
        case .serviceUUID:  return "circle.lefthalf.filled"
        case .name:         return "circle.dotted"
        }
    }

    /// One plain sentence the detail screen shows under the chip.
    var explanation: String {
        switch self {
        case .manufacturer:
            return "The advertisement carries a manufacturer identifier registered to a camera-glasses vendor. This is the strongest signal a passive scan can read."
        case .serviceUUID:
            return "The advertisement offers a Bluetooth service used by a wearables vendor. Weaker than a manufacturer match — some other devices from that vendor use it too."
        case .name:
            return "Only the advertised device name matched a known pattern. Names are freely set and easily imitated, so this alone is treated as a hint, not a finding."
        }
    }

    /// May this tier post a background local notification? Tier 3 never does.
    var canNotifyInBackground: Bool { self >= .serviceUUID }
}

/// What the matched signature says the device *is*.
enum DetectionCategory: String, Codable, Sendable, CaseIterable {
    /// Has an outward-facing camera and is worn discreetly on the face — the app's
    /// subject. Ray-Ban / Oakley Meta, Snap Spectacles.
    case cameraGlasses
    /// Smart glasses with a display but **no camera** — Even Realities G1/G2. Shown
    /// so the user knows what they are, but never presented as a camera detection.
    case displayGlasses
    /// Camera-capable but worn openly and obviously — a Meta Quest, an Apple Vision
    /// Pro. Listed so the user knows it is there, **never flagged as a covert camera
    /// and never an alert** (that would be crying wolf).
    case headset
    /// In range and logged, but nothing in the rule table matched.
    case unknown

    var isGlasses: Bool { self == .cameraGlasses || self == .displayGlasses }
}

/// One field of one advertisement that matched one rule. This *is* the evidence: the
/// user can open any flag, read every row, and disagree with it.
struct DetectionEvidence: Codable, Equatable, Sendable, Identifiable {
    /// Which AD field carried the match.
    let adType: ADType
    /// The rule that fired.
    let ruleID: String
    let ruleTitle: String
    let tier: DetectionTier
    /// What the rule that produced this row says the device is.
    let category: DetectionCategory
    /// The value that matched, formatted for a person: `0x0D53`, `0xFD5F`,
    /// `Spectacles`, `G1_7_L_a1b2`.
    let matchedValue: String
    /// The raw bytes behind it, spaced hex, exactly as they sit on the wire
    /// (little-endian): `53 0D` for company `0x0D53`, `5F FD` for UUID `0xFD5F`.
    let rawBytes: String

    var id: String { "\(ruleID)-\(adType.rawValue)" }

    /// Full VoiceOver announcement for this row.
    var accessibilityLabel: String {
        "\(adType.label): \(matchedValue). \(tier.title). Rule \(ruleTitle). Raw bytes \(spokenBytes)."
    }

    private var spokenBytes: String {
        rawBytes.split(separator: " ").joined(separator: ", ")
    }
}

/// The engine's verdict for one advertisement (or the merged verdict for a device
/// re-seen across a session). Persisted inside a `Sighting`, mirrored into the
/// widget/Live Activity snapshot.
struct Detection: Codable, Equatable, Sendable {

    var category: DetectionCategory
    /// Stable product identity for "This is mine" suppression — survives the OS
    /// rotating the peripheral's address. `nil` when unmatched.
    var productKey: String?
    /// Best human label: matched product name, else the advertised name.
    var productName: String?
    var vendor: String?
    /// Every rule that matched, strongest tier first.
    var evidence: [DetectionEvidence]

    static let none = Detection(category: .unknown, productKey: nil, productName: nil, vendor: nil, evidence: [])

    var matched: Bool { !evidence.isEmpty }
    var bestTier: DetectionTier? { evidence.map(\.tier).max() }

    /// A covert-camera device the app should raise to the user.
    var isCameraFlag: Bool { category == .cameraGlasses && matched }
    /// Display-only glasses — surfaced for what they are, never as a camera.
    var isDisplayGlasses: Bool { category == .displayGlasses && matched }
    /// Camera-capable but worn openly — listed, never flagged, never alerts.
    var isHeadset: Bool { category == .headset && matched }

    /// May this detection post a background notification? Covert camera glasses only,
    /// and only Tier 1 / Tier 2 (a bare name match never interrupts the user).
    var canNotifyInBackground: Bool {
        isCameraFlag && (bestTier?.canNotifyInBackground ?? false)
    }

    /// A short label for lists: product name → vendor device → category default.
    func displayTitle(fallback: String = "Bluetooth device") -> String {
        if let productName, !productName.isEmpty { return productName }
        if let vendor, !vendor.isEmpty { return "\(vendor) device" }
        switch category {
        case .cameraGlasses:  return "Camera glasses"
        case .displayGlasses: return "Display glasses"
        case .headset:        return "Headset"
        case .unknown:        return fallback
        }
    }

    /// Category specificity, most-specific first. A more specific category always
    /// wins a merge: Even Realities (regex) beats a camera match beats a bare
    /// shared-company-ID headset guess beats `unknown`.
    static func rank(_ c: DetectionCategory) -> Int {
        switch c {
        case .displayGlasses: return 3
        case .cameraGlasses:  return 2
        case .headset:        return 1
        case .unknown:        return 0
        }
    }

    /// Keeps the better of two readings as a device re-advertises through the
    /// session: a more specific category wins, then the higher tier, and fresh
    /// evidence is unioned in.
    func merged(with incoming: Detection) -> Detection {
        guard incoming.matched else { return self }
        guard matched else { return incoming }

        let winner: Detection
        if Self.rank(incoming.category) != Self.rank(category) {
            winner = Self.rank(incoming.category) > Self.rank(category) ? incoming : self
        } else {
            winner = (incoming.bestTier ?? .name) >= (bestTier ?? .name) ? incoming : self
        }
        let other = (winner == incoming) ? self : incoming

        var mergedEvidence = winner.evidence
        for e in other.evidence
        where e.category == winner.category && !mergedEvidence.contains(where: { $0.id == e.id }) {
            mergedEvidence.append(e)
        }
        mergedEvidence.sort { $0.tier > $1.tier }

        return Detection(
            category: winner.category,
            productKey: winner.productKey ?? productKey,
            productName: winner.productName ?? productName,
            vendor: winner.vendor ?? vendor,
            evidence: mergedEvidence
        )
    }
}
