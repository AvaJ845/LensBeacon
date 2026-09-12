import Testing
import Foundation

struct DetectionRuleTableTests {

    private let table = DetectionRuleTable.current

    @Test func schemaVersionIsSet() {
        #expect(table.schemaVersion == DetectionRuleTable.currentSchemaVersion)
    }

    @Test func ruleIDsAreUnique() {
        let ids = table.rules.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyRuleHasAProductKeyAndNote() {
        for r in table.rules {
            #expect(!r.productKey.isEmpty, "\(r.id) missing productKey")
            #expect(!r.note.isEmpty, "\(r.id) missing note")
        }
    }

    @Test func tierIsDerivedFromTheMatchKind() {
        // Not a drift guard any more — `tier` is computed — just a readability check.
        #expect(RuleMatch.companyID(0x1234).tier == .manufacturer)
        #expect(RuleMatch.serviceUUID16("ABCD").tier == .serviceUUID)
        #expect(RuleMatch.nameContains("x").tier == .name)
        #expect(RuleMatch.nameRegex("x").tier == .name)
    }

    @Test func everyNameRegexRuleCompiles() {
        for r in table.rules {
            if case .nameRegex(let p) = r.match {
                #expect(DetectionRuleTable.compiledRegexes[p] != nil, "\(r.id): \(p) failed to compile")
            }
        }
    }

    @Test func serviceUUIDFilterListIsDerivedFromTheRules() {
        #expect(table.serviceUUIDs16.contains("FD5F"))
    }

    @Test func tableRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(table)
        let back = try JSONDecoder().decode(DetectionRuleTable.self, from: data)
        #expect(back == table)
    }

    @Test func noRuleMatchesOnAnExcludedVendorCompanyID() {
        for excluded in [UInt16(0x00E0), UInt16(0x0075), UInt16(0x05D6)] {
            for r in table.rules {
                if case .companyID(let id) = r.match { #expect(id != excluded) }
            }
        }
    }
}
