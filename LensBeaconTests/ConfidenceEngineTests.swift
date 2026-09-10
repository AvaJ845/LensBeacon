import Testing
import Foundation
// The engine sources (Shared/) are compiled directly into this bundle, so they are
// in the same module — no import of the app target is needed or possible.

/// The confidence engine is the app's core judgement. These tests pin the mapping
/// from matched signals → confidence band, and the rules that keep headsets from
/// ever being escalated to a covert-camera flag.
struct ConfidenceEngineTests {

    private let metaCompany: UInt16 = 0x03A3
    private let snapCompany: UInt16 = 0x0819

    @Test func manufacturerAloneIsPossible() {
        let ad = ConfidenceEngine.Advertisement(
            companyIdentifier: metaCompany, serviceUUIDs: [], localName: nil, isConnectable: true
        )
        let result = ConfidenceEngine.classify(ad)
        #expect(result.category == .cameraGlasses)
        #expect(result.confidence == .possible)
        #expect(result.evidence.first?.matched.contains(.manufacturer) == true)
    }

    @Test func manufacturerPlusServiceIsLikely() {
        let ad = ConfidenceEngine.Advertisement(
            companyIdentifier: metaCompany, serviceUUIDs: ["FDF0"], localName: nil, isConnectable: true
        )
        #expect(ConfidenceEngine.classify(ad).confidence == .likely)
    }

    @Test func allThreeSignalsIsStrong() {
        let ad = ConfidenceEngine.Advertisement(
            companyIdentifier: metaCompany, serviceUUIDs: ["FDF0"],
            localName: "Ray-Ban Meta 12AB", isConnectable: true
        )
        let result = ConfidenceEngine.classify(ad)
        #expect(result.confidence == .strong)
        #expect(result.productName == "Ray-Ban Meta")
        #expect(result.evidence.first?.bullets.count == 3)
    }

    @Test func serviceAndNameWithoutManufacturerStillLikely() {
        let ad = ConfidenceEngine.Advertisement(
            companyIdentifier: nil, serviceUUIDs: ["FE60"],
            localName: "Spectacles", isConnectable: true
        )
        let result = ConfidenceEngine.classify(ad)
        #expect(result.category == .cameraGlasses)
        #expect(result.confidence == .likely)
    }

    @Test func questIsHeadsetNeverCameraFlag() {
        let ad = ConfidenceEngine.Advertisement(
            companyIdentifier: metaCompany, serviceUUIDs: ["FDF0"],
            localName: "Meta Quest 3", isConnectable: true
        )
        let result = ConfidenceEngine.classify(ad)
        #expect(result.category == .headset)
        #expect(result.confidence == nil)
        #expect(result.isCameraFlag == false)
    }

    @Test func unrelatedDeviceIsUnmatched() {
        let ad = ConfidenceEngine.Advertisement(
            companyIdentifier: 0x0001, serviceUUIDs: ["180F"],
            localName: "Someone's AirPods", isConnectable: true
        )
        let result = ConfidenceEngine.classify(ad)
        #expect(result.category == nil)
        #expect(result.isCameraFlag == false)
    }

    @Test func caseInsensitiveNameMatch() {
        let ad = ConfidenceEngine.Advertisement(
            companyIdentifier: snapCompany, serviceUUIDs: [], localName: "SPECTACLES-9F", isConnectable: true
        )
        #expect(ConfidenceEngine.classify(ad).category == .cameraGlasses)
    }

    @Test func confidenceMappingIsExhaustive() {
        #expect(ConfidenceEngine.confidence(for: [.manufacturer]) == .possible)
        #expect(ConfidenceEngine.confidence(for: [.serviceUUID]) == .possible)
        #expect(ConfidenceEngine.confidence(for: [.manufacturer, .serviceUUID]) == .likely)
        #expect(ConfidenceEngine.confidence(for: [.manufacturer, .namePattern]) == .likely)
        #expect(ConfidenceEngine.confidence(for: [.manufacturer, .serviceUUID, .namePattern]) == .strong)
    }
}
