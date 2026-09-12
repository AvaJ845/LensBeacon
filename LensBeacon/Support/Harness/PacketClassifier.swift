import Foundation

// ─────────────────────────────────────────────────────────────────────────────────
// PHASE 0 — DETECTION VALIDATION HARNESS. Not part of the product's detection
// engine (`Shared/DetectionEngine.swift`) and not used by it. This is a separate,
// narrower measurement instrument answering one question: when someone is
// actually wearing paired camera glasses in public, how often do they actually
// broadcast a detectable BLE advertisement? See `HARNESS.md` for the field
// protocol and the pre-registered kill criterion. The capture UI and scanner that
// use this are `#if DEBUG`-only (`HarnessModels.swift`, `HarnessScanner.swift`,
// `HarnessCoordinator.swift`, `Views/HarnessView.swift`) and compile out of every
// Release / TestFlight / App Store build entirely. This file and
// `SessionAnalyzer.swift` stay un-gated only so they can be unit-tested directly
// — they are pure functions with no CoreBluetooth or UI dependency, and dead
// weight if never invoked, which in Release they never are.
// ─────────────────────────────────────────────────────────────────────────────────

/// The four confidence tiers this harness's classifier can assign to one raw
/// packet — matching the hypothesis set in `HARNESS.md` exactly. Deliberately
/// narrower than the product's own `DetectionTier`/`DetectionCategory`: this
/// exists to test one question, not to ship a detection.
enum ClassificationTier: String, CaseIterable, Codable, Sendable {
    /// Matched a target company ID; no payload confirmation possible/attempted.
    case companyIDOnly
    /// 0x058E/0x01AB *and* the confirming ASCII payload — the only tier that
    /// actually distinguishes Ray-Ban Meta from a Quest sharing the same ID.
    case payloadConfirmed
    /// 0x0D53 (Luxottica) — an eyewear-only vendor, so the company ID alone is
    /// unambiguous; there is nothing for a payload check to add.
    case unambiguousVendor
    /// Not one of the four target company IDs.
    case other

    /// Whether this tier counts as an actual identification for true-positive
    /// analysis. `.companyIDOnly` does not — it cannot distinguish the target
    /// device from a Quest or any other product sharing the same company ID.
    var isConfirmed: Bool { self == .payloadConfirmed || self == .unambiguousVendor }

    var title: String {
        switch self {
        case .companyIDOnly:     return "Company ID only"
        case .payloadConfirmed:  return "Payload confirmed"
        case .unambiguousVendor: return "Unambiguous vendor"
        case .other:             return "No match"
        }
    }
}

/// A capture-independent view of one stored packet. Analysis and classification
/// code takes this, never the `@Model` `RawPacket` directly (see that type's doc
/// comment) — so both stay plain, pure functions over an in-memory array, fully
/// testable with no `ModelContainer` and directly re-runnable against an entire
/// archive the moment the hypothesis changes.
struct PacketRecord: Sendable, Equatable {
    let peripheralID: String
    let timestamp: Date
    let rssi: Int
    let manufacturerDataHex: String?
    let companyID: UInt16?
    let serviceUUIDs: [String]
    let localName: String?
    let isConnectable: Bool
    let txPower: Int?

    init(
        peripheralID: String, timestamp: Date, rssi: Int,
        manufacturerDataHex: String? = nil, companyID: UInt16? = nil,
        serviceUUIDs: [String] = [], localName: String? = nil,
        isConnectable: Bool = false, txPower: Int? = nil
    ) {
        self.peripheralID = peripheralID
        self.timestamp = timestamp
        self.rssi = rssi
        self.manufacturerDataHex = manufacturerDataHex
        self.companyID = companyID
        self.serviceUUIDs = serviceUUIDs
        self.localName = localName
        self.isConnectable = isConnectable
        self.txPower = txPower
    }
}

/// Classification is a **pure function over a stored raw packet** — never
/// something computed once at capture time and thrown away. That's what makes
/// re-classifying an entire archive against a revised hypothesis (a new company
/// ID, a different fingerprint string) a one-line change here, never a
/// re-collection in the field.
enum PacketClassifier {

    // Bluetooth SIG assigned company identifiers (little-endian on the wire).
    // "Confirmed across four independent sources" per the brief that
    // commissioned this harness — but the harness's whole purpose is to
    // generate the one number none of those sources published, so treat even
    // these IDs as inputs under test, not settled fact.
    static let metaPlatforms: UInt16 = 0x01AB
    static let metaRealityLabs: UInt16 = 0x058E
    static let luxottica: UInt16 = 0x0D53
    static let snap: UInt16 = 0x03C2

    /// The ASCII fingerprint reported inside 0x058E manufacturer data on an
    /// actual Ray-Ban Meta capture, distinguishing it from a Quest sharing the
    /// same company ID. Sourced, not yet independently confirmed — this
    /// harness's own aggregate output (`payloadConfirmedRatio`) is what will
    /// confirm or refute it, not the other way around.
    static let raybanPayloadFingerprint = "META_RB_GLASS"

    static func classify(_ record: PacketRecord) -> ClassificationTier {
        classify(companyID: record.companyID, manufacturerDataHex: record.manufacturerDataHex)
    }

    static func classify(companyID: UInt16?, manufacturerDataHex: String?) -> ClassificationTier {
        guard let companyID else { return .other }
        switch companyID {
        case luxottica:
            return .unambiguousVendor
        case metaRealityLabs, metaPlatforms:
            if let hex = manufacturerDataHex, payloadContainsFingerprint(hex) {
                return .payloadConfirmed
            }
            return .companyIDOnly
        case snap:
            // No payload-disambiguation signature is in this harness's
            // hypothesis set for Snap — unlike Meta, Snap doesn't share 0x03C2
            // with a non-glasses product, so a bare company-ID match is the
            // ceiling here until evidence says otherwise.
            return .companyIDOnly
        default:
            return .other
        }
    }

    /// Decodes spaced hex and checks for the fingerprint in the bytes *after*
    /// the 2-byte company prefix. Truncated data (2 bytes or fewer — nothing
    /// after the prefix to even look at) can never match; that's the
    /// "truncated manufacturer data" edge case from the test plan, handled by
    /// falling straight through to `false` rather than a special case.
    static func payloadContainsFingerprint(_ hex: String) -> Bool {
        let bytes = Self.bytes(fromHex: hex)
        guard bytes.count > 2 else { return false }
        let text = String(decoding: bytes.dropFirst(2), as: UTF8.self)
        return text.contains(raybanPayloadFingerprint)
    }

    static func bytes(fromHex hex: String) -> [UInt8] {
        hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
    }
}
