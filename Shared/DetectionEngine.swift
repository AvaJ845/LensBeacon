import Foundation

/// The advertisement fields the engine reasons about, distilled from CoreBluetooth's
/// already-parsed keys. Nothing `CB`-typed reaches here, and the raw manufacturer
/// bytes are kept so the evidence view can show exactly what matched.
struct AdvertisementFields: Sendable, Equatable {
    /// The full manufacturer-specific payload (AD type `0xFF`), company prefix first.
    var manufacturerData: Data?
    /// 16-bit service UUIDs from the service-UUID list (AD type `0x03`), 4-hex upper.
    var serviceUUIDs16: Set<String>
    /// 16-bit service UUIDs that carried service *data* (AD type `0x16`).
    var serviceDataUUIDs16: Set<String>
    /// The advertised local name (AD type `0x08` / `0x09`).
    var localName: String?
    var isConnectable: Bool

    init(manufacturerData: Data? = nil,
         serviceUUIDs16: Set<String> = [],
         serviceDataUUIDs16: Set<String> = [],
         localName: String? = nil,
         isConnectable: Bool = false) {
        self.manufacturerData = manufacturerData
        self.serviceUUIDs16 = Set(serviceUUIDs16.map { $0.uppercased() })
        self.serviceDataUUIDs16 = Set(serviceDataUUIDs16.map { $0.uppercased() })
        self.localName = localName
        self.isConnectable = isConnectable
    }

    /// Company identifier — bytes 0–1 of the manufacturer data, little-endian.
    var companyIdentifier: UInt16? {
        guard let d = manufacturerData, d.count >= 2 else { return nil }
        let lo = UInt16(d[d.startIndex])
        let hi = UInt16(d[d.index(after: d.startIndex)])
        return lo | (hi << 8)
    }

    /// Company bytes exactly as they sit on the wire, e.g. `53 0D` for `0x0D53`.
    var companyWireBytes: String? {
        guard let d = manufacturerData, d.count >= 2 else { return nil }
        return String(format: "%02X %02X", d[d.startIndex], d[d.index(after: d.startIndex)])
    }
}

/// Turns one advertisement into a `Detection` plus the evidence behind it.
///
/// Pure and synchronous by design — unit-testable with no Bluetooth radio, and the
/// "why was this flagged" screen renders the *same* structure the decision came from.
enum DetectionEngine {

    static func classify(_ ad: AdvertisementFields,
                         table: DetectionRuleTable = .current) -> Detection {

        var hits: [(rule: DetectionRule, evidence: DetectionEvidence)] = []
        for rule in table.rules {
            if let ev = evaluate(rule, against: ad) { hits.append((rule, ev)) }
        }
        guard let bestRank = hits.map({ Detection.rank($0.rule.category) }).max() else { return .none }

        // The most *specific* category present wins — Even Realities (display, no
        // camera) beats a camera match beats a bare shared-company-ID headset guess.
        // Within the winning category, the highest-tier rule leads.
        let winning = hits
            .filter { Detection.rank($0.rule.category) == bestRank }
            .sorted { $0.evidence.tier > $1.evidence.tier }
        let lead = winning[0].rule

        return Detection(
            category: lead.category,
            productKey: lead.productKey,
            productName: lead.productName.isEmpty ? ad.localName : lead.productName,
            vendor: lead.vendor.isEmpty ? nil : lead.vendor,
            evidence: winning.map(\.evidence)
        )
    }

    // MARK: - One rule

    private static func evaluate(_ rule: DetectionRule,
                                 against ad: AdvertisementFields) -> DetectionEvidence? {
        switch rule.match {

        case .companyID(let id):
            guard ad.companyIdentifier == id else { return nil }
            return DetectionEvidence(
                adType: .manufacturerData, ruleID: rule.id, ruleTitle: rule.note,
                tier: rule.tier, category: rule.category,
                matchedValue: String(format: "0x%04X", id),
                rawBytes: ad.companyWireBytes ?? wireBytes(of: id)
            )

        case .serviceUUID16(let uuid):
            let target = uuid.uppercased()
            if ad.serviceUUIDs16.contains(target) {
                return DetectionEvidence(
                    adType: .serviceUUIDs16, ruleID: rule.id, ruleTitle: rule.note,
                    tier: rule.tier, category: rule.category,
                    matchedValue: "0x\(target)", rawBytes: wireBytes(ofHex: target)
                )
            }
            if ad.serviceDataUUIDs16.contains(target) {
                return DetectionEvidence(
                    adType: .serviceData16, ruleID: rule.id, ruleTitle: rule.note,
                    tier: rule.tier, category: rule.category,
                    matchedValue: "0x\(target)", rawBytes: wireBytes(ofHex: target)
                )
            }
            return nil

        case .nameContains(let needle):
            guard let name = ad.localName,
                  name.range(of: needle, options: .caseInsensitive) != nil else { return nil }
            return DetectionEvidence(
                adType: .completeName, ruleID: rule.id, ruleTitle: rule.note,
                tier: rule.tier, category: rule.category,
                matchedValue: name, rawBytes: utf8Hex(name)
            )

        case .nameRegex(let pattern):
            guard let name = ad.localName,
                  let re = DetectionRuleTable.compiledRegexes[pattern],
                  re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
            else { return nil }
            return DetectionEvidence(
                adType: .completeName, ruleID: rule.id, ruleTitle: rule.note,
                tier: rule.tier, category: rule.category,
                matchedValue: name, rawBytes: utf8Hex(name)
            )
        }
    }

    // MARK: - Formatting helpers

    private static func wireBytes(of value: UInt16) -> String {
        String(format: "%02X %02X", value & 0xFF, value >> 8)
    }
    private static func wireBytes(ofHex hex: String) -> String {
        guard let v = UInt16(hex, radix: 16) else { return hex }
        return wireBytes(of: v)
    }
    private static func utf8Hex(_ s: String) -> String {
        s.utf8.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
