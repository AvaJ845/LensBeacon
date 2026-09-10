import Testing
import Foundation

struct SignatureTableTests {

    @Test func everySignatureHasAtLeastOneClause() {
        for sig in SignatureTable.all {
            let hasClause = sig.companyIdentifier != nil
                || !sig.serviceUUIDs.isEmpty
                || !sig.namePatterns.isEmpty
            #expect(hasClause, "signature \(sig.id) has no matchable clause")
        }
    }

    @Test func cameraGlassesSubsetExcludesHeadsets() {
        #expect(SignatureTable.cameraGlasses.allSatisfy { $0.category == .cameraGlasses })
        #expect(SignatureTable.cameraGlasses.contains { $0.id == "rayban-meta" })
        #expect(!SignatureTable.cameraGlasses.contains { $0.id == "meta-quest" })
    }

    @Test func evaluateRequiresCompanyMatchWhenSpecified() {
        let sig = SignatureTable.all.first { $0.id == "snap-spectacles" }!
        // Wrong company → nil (signature does not apply at all).
        #expect(sig.evaluate(companyIdentifier: 0x0001, serviceUUIDs: [], localName: "Spectacles") == nil)
        // Right company → at least the manufacturer clause.
        let matched = sig.evaluate(companyIdentifier: 0x0819, serviceUUIDs: [], localName: nil)
        #expect(matched?.contains(.manufacturer) == true)
    }

    @Test func signatureIDsAreUnique() {
        let ids = SignatureTable.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
