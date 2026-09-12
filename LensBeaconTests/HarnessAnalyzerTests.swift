import Testing
import Foundation

struct HarnessAnalyzerTests {

    private func hexFor(company: UInt16, asciiPayload: String) -> String {
        var bytes: [UInt8] = [UInt8(company & 0xFF), UInt8(company >> 8)]
        bytes.append(contentsOf: Array(asciiPayload.utf8))
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: - Per-device summary

    @Test func summarizeComputesIntervalsBetweenConsecutivePacketsForOnePeripheral() {
        let start = Date()
        let packets = [0.0, 5.0, 15.0].map { offset in
            PacketRecord(peripheralID: "a", timestamp: start.addingTimeInterval(offset), rssi: -50)
        }
        let summaries = SessionAnalyzer.summarize(packets)
        #expect(summaries.count == 1)
        #expect(summaries[0].intervalSeconds == [5.0, 10.0])
        #expect(summaries[0].meanIntervalSeconds == 7.5)
        #expect(summaries[0].maxIntervalSeconds == 10.0)
    }

    @Test func aSinglePacketHasNoIntervalsAtAll() {
        let summaries = SessionAnalyzer.summarize([PacketRecord(peripheralID: "a", timestamp: Date(), rssi: -50)])
        #expect(summaries[0].intervalSeconds.isEmpty)
        #expect(summaries[0].meanIntervalSeconds == nil)
    }

    /// Real bug, confirmed against an actual field capture: CoreBluetooth's
    /// `127` "no reading available" RSSI sentinel was landing directly in
    /// `max_rssi` on an exported CSV. `rssiValues` must apply the same valid-
    /// range guard as the product's own `RSSISmoother`.
    @Test func rssiStatsIgnoreTheCoreBluetoothNoReadingSentinel() {
        let now = Date()
        let packets = [-50, 127, -55, 127, -48].map { rssi in
            PacketRecord(peripheralID: "a", timestamp: now, rssi: rssi)
        }
        let summary = SessionAnalyzer.summarize(packets)[0]
        #expect(summary.rssiValues == [-50, -55, -48])
        #expect(summary.maxRSSI == -48)
        #expect(summary.minRSSI == -55)
    }

    @Test func rssiStatsAlsoIgnoreValuesAtOrBeyondNegative120() {
        let now = Date()
        let packets = [-50, -120, -150, 0].map { rssi in
            PacketRecord(peripheralID: "a", timestamp: now, rssi: rssi)
        }
        let summary = SessionAnalyzer.summarize(packets)[0]
        #expect(summary.rssiValues == [-50])
    }

    @Test func summarizeGroupsSeparatelyByPeripheralID() {
        let now = Date()
        let packets = [
            PacketRecord(peripheralID: "a", timestamp: now, rssi: -50),
            PacketRecord(peripheralID: "b", timestamp: now, rssi: -70),
            PacketRecord(peripheralID: "a", timestamp: now.addingTimeInterval(1), rssi: -52),
        ]
        let summaries = SessionAnalyzer.summarize(packets)
        #expect(summaries.count == 2)
        #expect(summaries.first { $0.peripheralID == "a" }?.packetCount == 2)
        #expect(summaries.first { $0.peripheralID == "b" }?.packetCount == 1)
    }

    // MARK: - Payload-confirmed ratio

    @Test func payloadConfirmedRatioIsNilWithNoAmbiguousPackets() {
        let packets = [PacketRecord(peripheralID: "a", timestamp: Date(), rssi: -50, companyID: PacketClassifier.luxottica)]
        #expect(SessionAnalyzer.payloadConfirmedRatio(packets) == nil)
    }

    @Test func payloadConfirmedRatioIsZeroNotNilWhenAllAmbiguousPacketsFailConfirmation() {
        let hex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "OCULUS_QUEST2")
        let packets = (0..<3).map { i in
            PacketRecord(peripheralID: "q\(i)", timestamp: Date(), rssi: -50,
                        manufacturerDataHex: hex, companyID: PacketClassifier.metaRealityLabs)
        }
        #expect(SessionAnalyzer.payloadConfirmedRatio(packets) == 0.0)
    }

    @Test func payloadConfirmedRatioReflectsAMixOfConfirmedAndUnconfirmed() {
        let confirmedHex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "META_RB_GLASS")
        let questHex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "OCULUS_QUEST2")
        let packets = [
            PacketRecord(peripheralID: "glasses", timestamp: Date(), rssi: -50, manufacturerDataHex: confirmedHex, companyID: PacketClassifier.metaRealityLabs),
            PacketRecord(peripheralID: "quest1", timestamp: Date(), rssi: -50, manufacturerDataHex: questHex, companyID: PacketClassifier.metaRealityLabs),
            PacketRecord(peripheralID: "quest2", timestamp: Date(), rssi: -50, manufacturerDataHex: questHex, companyID: PacketClassifier.metaRealityLabs),
            PacketRecord(peripheralID: "quest3", timestamp: Date(), rssi: -50, manufacturerDataHex: questHex, companyID: PacketClassifier.metaRealityLabs),
        ]
        #expect(SessionAnalyzer.payloadConfirmedRatio(packets) == 0.25)
    }

    // MARK: - Session outcomes / true-positive rate

    @Test func outcomeDetectsAConfirmedPacketAndReportsTimeToFirstDetection() {
        let start = Date()
        let confirmedHex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "META_RB_GLASS")
        let packets = [
            PacketRecord(peripheralID: "x", timestamp: start, rssi: -50, companyID: PacketClassifier.metaRealityLabs),  // company-ID-only
            PacketRecord(peripheralID: "x", timestamp: start.addingTimeInterval(42), rssi: -48,
                        manufacturerDataHex: confirmedHex, companyID: PacketClassifier.metaRealityLabs),
        ]
        let states = [DeviceStateRecord(label: "test", paired: true, worn: true)]
        let outcomes = SessionAnalyzer.outcomes(startedAt: start, deviceStates: states, packets: packets)
        #expect(outcomes.count == 1)
        #expect(outcomes[0].category == .wornAndPaired)
        #expect(outcomes[0].anyConfirmedDetection == true)
        #expect(outcomes[0].timeToFirstConfirmedDetection == 42)
    }

    /// "Payload present but split across advertisement frames" (test plan item
    /// 3) at the session level: the *first* sighting of this peripheral carries
    /// no confirming payload, but a later one does. Classification stayed
    /// strictly per-packet (see `HarnessClassifierTests
    /// .classificationIsPurelyPerPacketNeverStateful`); this is where that
    /// gets reassembled into a session-wide answer instead.
    @Test func confirmationCanArriveOnALaterPacketThanTheFirstSighting() {
        let start = Date()
        let bareHex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "")
        let confirmedHex = hexFor(company: PacketClassifier.metaRealityLabs, asciiPayload: "META_RB_GLASS")
        let packets = [
            PacketRecord(peripheralID: "x", timestamp: start, rssi: -50, manufacturerDataHex: bareHex, companyID: PacketClassifier.metaRealityLabs),
            PacketRecord(peripheralID: "x", timestamp: start.addingTimeInterval(8), rssi: -50, manufacturerDataHex: bareHex, companyID: PacketClassifier.metaRealityLabs),
            PacketRecord(peripheralID: "x", timestamp: start.addingTimeInterval(16), rssi: -49, manufacturerDataHex: confirmedHex, companyID: PacketClassifier.metaRealityLabs),
        ]
        let outcomes = SessionAnalyzer.outcomes(startedAt: start, deviceStates: [], packets: packets)
        #expect(outcomes[0].anyConfirmedDetection == true)
        #expect(outcomes[0].timeToFirstConfirmedDetection == 16)
    }

    @Test func noConfirmedPacketMeansNoDetectionAndNoTimeToFirstDetection() {
        let start = Date()
        let packets = [PacketRecord(peripheralID: "x", timestamp: start, rssi: -50, companyID: PacketClassifier.metaRealityLabs)]
        let outcomes = SessionAnalyzer.outcomes(startedAt: start, deviceStates: [], packets: packets)
        #expect(outcomes[0].anyConfirmedDetection == false)
        #expect(outcomes[0].anyCompanyIDOnlyDetection == true)
        #expect(outcomes[0].timeToFirstConfirmedDetection == nil)
    }

    @Test func outcomeWithNoTaggedDevicesStillReportsANilCategoryRow() {
        let outcomes = SessionAnalyzer.outcomes(startedAt: Date(), deviceStates: [], packets: [])
        #expect(outcomes.count == 1)
        #expect(outcomes[0].category == nil)
    }

    @Test func truePositiveRateDistinguishesNoDataFromAMeasuredZero() {
        let rates = SessionAnalyzer.truePositiveRates([])
        #expect(rates.allSatisfy { $0.rate == nil && $0.totalSessions == 0 })
    }

    @Test func truePositiveRateComputesAFractionPerCategory() {
        let outcomes = [
            SessionAnalyzer.SessionOutcome(category: .wornAndPaired, anyConfirmedDetection: true, anyCompanyIDOnlyDetection: false, timeToFirstConfirmedDetection: 5),
            SessionAnalyzer.SessionOutcome(category: .wornAndPaired, anyConfirmedDetection: false, anyCompanyIDOnlyDetection: true, timeToFirstConfirmedDetection: nil),
            SessionAnalyzer.SessionOutcome(category: .bagged, anyConfirmedDetection: false, anyCompanyIDOnlyDetection: false, timeToFirstConfirmedDetection: nil),
        ]
        let rates = SessionAnalyzer.truePositiveRates(outcomes)
        let wornPaired = rates.first { $0.category == .wornAndPaired }
        #expect(wornPaired?.detectedSessions == 1)
        #expect(wornPaired?.totalSessions == 2)
        #expect(wornPaired?.rate == 0.5)
        let bagged = rates.first { $0.category == .bagged }
        #expect(bagged?.rate == 0.0)
        let idle = rates.first { $0.category == .idlePairedNotWorn }
        #expect(idle?.rate == nil)
    }

    // MARK: - DeviceStateRecord categorization

    @Test func categoryChecksMostSpecificConditionFirst() {
        #expect(DeviceStateRecord(label: "a", poweredOff: true).category == .poweredOff)
        #expect(DeviceStateRecord(label: "a", worn: true, inBagOrCase: true, poweredOff: true).category == .poweredOff)
        #expect(DeviceStateRecord(label: "a", inBagOrCase: true).category == .bagged)
        #expect(DeviceStateRecord(label: "a", paired: true, worn: true).category == .wornAndPaired)
        #expect(DeviceStateRecord(label: "a", paired: true).category == .idlePairedNotWorn)
        #expect(DeviceStateRecord(label: "a").category == .unpairedPresent)
    }
}
