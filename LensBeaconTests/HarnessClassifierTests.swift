import Testing
import Foundation

/// Phase 0 detection validation harness — the classifier is a pure function
/// over a stored packet (see `PacketClassifier.swift`), so every edge case from
/// the harness test plan is directly testable with no CoreBluetooth and no
/// capture step.
struct HarnessClassifierTests {

    private func record(companyID: UInt16?, hex: String? = nil) -> PacketRecord {
        PacketRecord(peripheralID: "p", timestamp: Date(), rssi: -50, manufacturerDataHex: hex, companyID: companyID)
    }

    @Test func luxotticaAloneIsUnambiguous() {
        #expect(PacketClassifier.classify(record(companyID: PacketClassifier.luxottica)) == .unambiguousVendor)
    }

    @Test func metaRealityLabsWithTheFingerprintIsPayloadConfirmed() {
        let hex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "META_RB_GLASS")
        #expect(PacketClassifier.classify(record(companyID: PacketClassifier.metaRealityLabs, hex: hex)) == .payloadConfirmed)
    }

    @Test func metaPlatformsWithTheFingerprintIsAlsoPayloadConfirmed() {
        let hex = hexFor(company: PacketClassifier.metaPlatforms, asciiPayload: "META_RB_GLASS")
        #expect(PacketClassifier.classify(record(companyID: PacketClassifier.metaPlatforms, hex: hex)) == .payloadConfirmed)
    }

    // MARK: - Test plan item 3: classifier edge cases

    @Test func truncatedManufacturerDataNeverConfirms() {
        // Just the 2-byte company prefix, nothing after it to check.
        let hex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "")
        #expect(PacketClassifier.classify(record(companyID: PacketClassifier.metaRealityLabs, hex: hex)) == .companyIDOnly)
    }

    @Test func manufacturerDataOfExactlyTwoBytesNeverConfirms() {
        #expect(!PacketClassifier.payloadContainsFingerprint("8E 05"))
    }

    @Test func absentManufacturerDataIsOtherEvenIfSomehowNoCompanyID() {
        #expect(PacketClassifier.classify(record(companyID: nil, hex: nil)) == .other)
    }

    @Test func malformedNonTextPayloadNeverAccidentallyConfirms() {
        // Random binary bytes after the company prefix — lossy UTF-8 decoding
        // must never accidentally spell the fingerprint.
        let hex = "8E 05 00 FF 01 FE 02 FD 03 FC"
        #expect(PacketClassifier.classify(record(companyID: PacketClassifier.metaRealityLabs, hex: hex)) == .companyIDOnly)
    }

    @Test func correctCompanyIDWrongPayloadIsCompanyIDOnly() {
        // This is the Quest negative-control case at the classifier level: same
        // company ID as the glasses, a real but different ASCII payload.
        let hex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "OCULUS_QUEST2")
        #expect(PacketClassifier.classify(record(companyID: PacketClassifier.metaRealityLabs, hex: hex)) == .companyIDOnly)
        #expect(!PacketClassifier.classify(record(companyID: PacketClassifier.metaRealityLabs, hex: hex)).isConfirmed)
    }

    @Test func snapCompanyIDHasNoPayloadCheckDefined() {
        #expect(PacketClassifier.classify(record(companyID: PacketClassifier.snap)) == .companyIDOnly)
    }

    @Test func unrelatedCompanyIDIsOther() {
        #expect(PacketClassifier.classify(record(companyID: 0x004C)) == .other) // Apple, Inc.
    }

    /// "Payload present but split across advertisement frames": CoreBluetooth
    /// doesn't expose true link-layer fragmentation to an app — each
    /// `didDiscover` callback already hands over one fully-assembled
    /// manufacturer-data blob. What actually happens on real hardware is a
    /// device alternating between advertisement payloads that omit the
    /// fingerprint and ones that carry it (a legacy 31-byte advertisement is
    /// cramped, so not every broadcast interval needs to repeat everything).
    /// The classifier stays strictly per-packet on purpose — this is what
    /// `SessionAnalyzer`'s session-level aggregation exists to handle instead
    /// (see `HarnessAnalyzerTests.confirmationCanArriveOnALaterPacketThanTheFirstSighting`).
    @Test func classificationIsPurelyPerPacketNeverStateful() {
        let withoutFingerprint = record(companyID: PacketClassifier.metaRealityLabs, hex: hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: ""))
        let withFingerprint = record(companyID: PacketClassifier.metaRealityLabs, hex: hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "META_RB_GLASS"))
        #expect(PacketClassifier.classify(withoutFingerprint) == .companyIDOnly)
        #expect(PacketClassifier.classify(withFingerprint) == .payloadConfirmed)
    }

    // MARK: - Helpers

    private func hexFor(company: UInt16, asciiPayload: String) -> String {
        var bytes: [UInt8] = [UInt8(company & 0xFF), UInt8(company >> 8)]
        bytes.append(contentsOf: Array(asciiPayload.utf8))
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
