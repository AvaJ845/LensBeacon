import Foundation

/// How a single rule tests an advertisement. Exactly one case per rule. The match
/// kind *is* the tier — there is no separate field to drift out of sync.
enum RuleMatch: Codable, Equatable, Sendable {
    /// Manufacturer company identifier (AD type `0xFF`, bytes 0–1, little-endian on
    /// the wire). Tier 1.
    case companyID(UInt16)
    /// A 16-bit service UUID, matched in either the service-UUID list (`0x03`) or
    /// service data (`0x16`). Tier 2. Stored as a 4-char uppercase hex string.
    case serviceUUID16(String)
    /// The advertised local name (`0x08` / `0x09`) contains this substring,
    /// case-insensitively. Tier 3.
    case nameContains(String)
    /// The advertised local name matches this anchored regular expression. Tier 3.
    case nameRegex(String)

    var tier: DetectionTier {
        switch self {
        case .companyID:      return .manufacturer
        case .serviceUUID16:  return .serviceUUID
        case .nameContains, .nameRegex: return .name
        }
    }
}

/// One entry in the detection table.
struct DetectionRule: Codable, Equatable, Sendable, Identifiable {
    /// Unique, stable rule id.
    let id: String
    /// Product identity used for "This is mine" suppression — several rules can share
    /// one product key (e.g. a company-ID rule and a name rule for the same glasses).
    let productKey: String
    let productName: String
    let vendor: String
    let category: DetectionCategory
    let match: RuleMatch
    /// One line, shown verbatim in the evidence view.
    let note: String

    /// Tier is derived from the match kind, never stored.
    var tier: DetectionTier { match.tier }
}

/// The versioned, data-driven rule table. Add a signature by adding a `DetectionRule`
/// to `current` and bumping nothing but this file — the scan and UI layers never
/// change. `schemaVersion` guards the `Codable` shape if the table is ever persisted
/// or shipped as JSON.
struct DetectionRuleTable: Codable, Equatable, Sendable {

    let schemaVersion: Int
    let rules: [DetectionRule]

    static let currentSchemaVersion = 3

    /// Every 16-bit service UUID any rule matches on — the CoreBluetooth background
    /// scan filter (a `nil`-services scan is dropped almost immediately off-screen).
    var serviceUUIDs16: [String] {
        rules.compactMap {
            if case .serviceUUID16(let u) = $0.match { return u.uppercased() }
            return nil
        }
    }

    /// The name-regex rules compiled once, keyed by pattern. A plain `let` is
    /// thread-safe with no lock — the table is a compile-time constant.
    static let compiledRegexes: [String: NSRegularExpression] = {
        var out: [String: NSRegularExpression] = [:]
        for rule in current.rules {
            if case .nameRegex(let pattern) = rule.match, out[pattern] == nil {
                out[pattern] = try? NSRegularExpression(pattern: pattern)
            }
        }
        return out
    }()

    // ─────────────────────────────────────────────────────────────────────────────
    // SIGNATURE SET.  Sources: first-party captures + the public ZuckOff detector.
    // See docs/RULES.md for how to add one from a capture.
    //
    // TWO SHARED IDENTIFIERS THAT MUST NOT STAND ALONE AS A CAMERA FLAG:
    //   0x058E  Meta Platforms Technologies (Reality Labs / Oculus) — used by the
    //           Meta Quest *and* the Ray-Ban / Oakley Meta glasses. First-party
    //           testing (2026-09-10) confirmed a Quest with no glasses present
    //           advertises 0x058E. So a bare 0x058E is classified as a *headset*
    //           (worn openly, never flagged, never alerts). A real pair of glasses
    //           is identified by 0x0D53 (Luxottica) or a glasses name, which
    //           outranks the headset guess.
    //   0xFD5F  Oculus VR service UUID — Quest. Also a headset signal.
    //
    // DELIBERATELY EXCLUDED — do not re-add without a second discriminator:
    //   0x00E0  Google  — every Pixel and every Fast Pair accessory broadcasts it.
    //   0x0075  Samsung — same, louder. Neither ships camera glasses.
    // A future rule that needs any of these MUST gate on a second signal, never the
    // company ID by itself. This comment is load-bearing: leave it here.
    // ─────────────────────────────────────────────────────────────────────────────

    static let current = DetectionRuleTable(
        schemaVersion: currentSchemaVersion,
        rules: [

            // ── Camera glasses — Tier 1, manufacturer company ID (0xFF). ──────────
            DetectionRule(
                id: "luxottica-company",
                productKey: "meta-glasses",
                productName: "Ray-Ban / Oakley Meta",
                vendor: "EssilorLuxottica",
                category: .cameraGlasses,
                match: .companyID(0x0D53),
                note: "Manufacturer identifier 0x0D53 is registered to EssilorLuxottica, maker of the Ray-Ban Meta and Oakley Meta frames — glasses, not a headset."
            ),
            DetectionRule(
                id: "snap-company",
                productKey: "snap-spectacles",
                productName: "Snap Spectacles",
                vendor: "Snap",
                category: .cameraGlasses,
                match: .companyID(0x03C2),
                note: "Manufacturer identifier 0x03C2 is registered to Snap Inc., maker of Spectacles."
            ),

            // ── Camera glasses — Tier 3, advertised name. Never alerts on its own. ─
            DetectionRule(
                id: "name-rayban-meta",
                productKey: "meta-glasses",
                productName: "Ray-Ban / Oakley Meta",
                vendor: "Meta",
                category: .cameraGlasses,
                match: .nameRegex(#"(?i)\b(ray-?ban|oakley|meta view|meta glasses)\b"#),
                note: "The advertised name matches a Ray-Ban / Oakley Meta pattern. A name is freely set — treated as a hint, but enough to say this is glasses, not a Quest."
            ),
            DetectionRule(
                id: "name-spectacles",
                productKey: "snap-spectacles",
                productName: "Snap Spectacles",
                vendor: "Snap",
                category: .cameraGlasses,
                match: .nameContains("Spectacles"),
                note: "The advertised name contains “Spectacles”. Name match only."
            ),
            DetectionRule(
                id: "name-heycyan",
                productKey: "heycyan",
                productName: "HeyCyan glasses",
                vendor: "HeyCyan",
                category: .cameraGlasses,
                match: .nameContains("HeyCyan"),
                note: "The advertised name contains “HeyCyan”, a camera-glasses brand. Name match only."
            ),
            DetectionRule(
                id: "name-vistaview",
                productKey: "vistaview",
                productName: "VistaView glasses",
                vendor: "VistaView",
                category: .cameraGlasses,
                match: .nameContains("VistaView"),
                note: "The advertised name contains “VistaView”, a camera-glasses brand. Name match only."
            ),

            // ── Display glasses — NO CAMERA. Even Realities G1 / G2. ──────────────
            DetectionRule(
                id: "even-realities-g1",
                productKey: "even-realities",
                productName: "Even Realities G1 / G2",
                vendor: "Even Realities",
                category: .displayGlasses,
                match: .nameRegex(#"^G1_\d+_[LR]_"#),
                note: "Even Realities G1/G2 are display-only glasses with no camera. Each arm advertises separately as G1_<channel>_<L|R>_<id>."
            ),

            // ── Headsets — camera-capable but worn openly. Listed, never flagged. ─
            DetectionRule(
                id: "meta-reality-labs-company",
                productKey: "meta-headset",
                productName: "Meta wearable",
                vendor: "Meta Platforms",
                category: .headset,
                match: .companyID(0x058E),
                note: "Manufacturer identifier 0x058E is Meta Platforms Technologies (Reality Labs / Oculus) — shared by the Quest and the Meta glasses. On its own it is treated as a headset; a Luxottica ID or a glasses name upgrades it to camera glasses."
            ),
            DetectionRule(
                id: "oculus-service",
                productKey: "meta-headset",
                productName: "Meta Quest",
                vendor: "Meta Platforms",
                category: .headset,
                match: .serviceUUID16("FD5F"),
                note: "Bluetooth service 0xFD5F is registered to Oculus VR — a Meta Quest headset."
            ),
            DetectionRule(
                id: "name-quest",
                productKey: "meta-headset",
                productName: "Meta Quest",
                vendor: "Meta Platforms",
                category: .headset,
                match: .nameRegex(#"(?i)\b(quest|oculus)\b"#),
                note: "The advertised name matches a Meta Quest / Oculus headset — worn openly, not a covert camera."
            ),
            DetectionRule(
                id: "name-visionpro",
                productKey: "apple-vision-pro",
                productName: "Apple Vision Pro",
                vendor: "Apple",
                category: .headset,
                match: .nameContains("VisionPro"),
                note: "The advertised name contains “VisionPro” — an Apple Vision Pro headset, worn openly."
            ),
        ]
    )
}
