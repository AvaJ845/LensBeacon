import Testing
import Foundation

/// The tiered rule engine is the app's core judgement. These pin the little-endian
/// company-ID parse, service-UUID matching in both AD forms, the Even Realities
/// regex, tier → alert gating, and — critically — that the deliberately excluded
/// Google and Samsung company IDs never match.
struct DetectionEngineTests {

    private func mfg(_ company: UInt16, trailing: [UInt8] = [0x01, 0x02]) -> Data {
        Data([UInt8(company & 0xFF), UInt8(company >> 8)] + trailing)
    }

    // MARK: - Tier 1 — company ID, little-endian on the wire

    @Test func luxotticaCompanyIDParsesLittleEndianAndFlagsTier1() {
        // 0x0D53 sits on the wire as 53 0D.
        let d = DetectionEngine.classify(.init(manufacturerData: Data([0x53, 0x0D, 0xAA])))
        #expect(d.category == .cameraGlasses)
        #expect(d.bestTier == .manufacturer)
        #expect(d.productKey == "meta-glasses")
        let e = d.evidence.first
        #expect(e?.adType == .manufacturerData)
        #expect(e?.matchedValue == "0x0D53")
        #expect(e?.rawBytes == "53 0D")
    }

    @Test func metaSharedCompanyIDAloneIsAHeadsetNotACameraFlag() {
        // 0x058E (Meta Reality Labs / Oculus) is shared by the Quest and the Meta
        // glasses. A first-party test found a Quest with no glasses present advertises
        // it — so on its own it must NOT be a camera flag. Regression for 2026-09-10.
        let d = DetectionEngine.classify(.init(manufacturerData: mfg(0x058E)))
        #expect(d.category == .headset)
        #expect(d.isCameraFlag == false)
        #expect(d.canNotifyInBackground == false)
        #expect(d.evidence.first?.matchedValue == "0x058E")
        #expect(d.evidence.first?.rawBytes == "8E 05")
    }

    @Test func metaSharedCompanyIDPlusGlassesNameIsCameraGlasses() {
        // The same ID with a Ray-Ban name — now it's glasses, and camera outranks
        // the headset guess.
        let d = DetectionEngine.classify(.init(manufacturerData: mfg(0x058E), localName: "Ray-Ban Meta 4F"))
        #expect(d.category == .cameraGlasses)
        #expect(d.isCameraFlag)
    }

    @Test func meta01ABAloneIsAlsoAHeadsetNotACameraFlag() {
        // 0x01AB is the other confirmed Meta Platforms company ID (source: the
        // Bluetooth SIG assigned-numbers registry, cross-checked independently of
        // the community write-up that first reported it) — treated exactly like
        // 0x058E until a first-party capture confirms which product broadcasts it.
        let d = DetectionEngine.classify(.init(manufacturerData: mfg(0x01AB)))
        #expect(d.category == .headset)
        #expect(d.isCameraFlag == false)
    }

    @Test func meta01ABPlusGlassesNameIsCameraGlasses() {
        let d = DetectionEngine.classify(.init(manufacturerData: mfg(0x01AB), localName: "Oakley Meta"))
        #expect(d.category == .cameraGlasses)
        #expect(d.isCameraFlag)
    }

    @Test func snapCompanyID() {
        let d = DetectionEngine.classify(.init(manufacturerData: mfg(0x03C2)))
        #expect(d.bestTier == .manufacturer)
        #expect(d.evidence.first?.matchedValue == "0x03C2")
        #expect(d.evidence.first?.rawBytes == "C2 03")
    }

    // MARK: - Manufacturer-data ASCII fingerprint (no live rule yet — infrastructure
    // only, ready for the day a real capture confirms a string like "META_RB_GLASS"
    // actually appears; tested against a throwaway table so `.current` stays clean
    // of unconfirmed rules).

    @Test func manufacturerDataContainsMatchesAnEmbeddedASCIIFingerprint() {
        let testTable = DetectionRuleTable(schemaVersion: 1, rules: [
            DetectionRule(id: "t", productKey: "p", productName: "Test Glasses", vendor: "V",
                          category: .cameraGlasses, match: .manufacturerDataContains("META_RB_GLASS"), note: "t"),
        ])
        var data = mfg(0x0D53)
        data.append(contentsOf: Array("META_RB_GLASS".utf8))

        let d = DetectionEngine.classify(.init(manufacturerData: data), table: testTable)
        #expect(d.category == .cameraGlasses)
        #expect(d.bestTier == .manufacturer)
        #expect(d.evidence.first?.matchedValue == "META_RB_GLASS")
    }

    @Test func manufacturerDataContainsIsCaseInsensitiveAndIgnoresTheCompanyPrefix() {
        let testTable = DetectionRuleTable(schemaVersion: 1, rules: [
            DetectionRule(id: "t", productKey: "p", productName: "P", vendor: "V",
                          category: .cameraGlasses, match: .manufacturerDataContains("hello"), note: "t"),
        ])
        var data = mfg(0x0D53)
        data.append(contentsOf: Array("xxHELLOxx".utf8))

        let d = DetectionEngine.classify(.init(manufacturerData: data), table: testTable)
        #expect(d.category == .cameraGlasses)
    }

    @Test func manufacturerDataContainsDoesNotMatchWhenTheStringIsAbsent() {
        let testTable = DetectionRuleTable(schemaVersion: 1, rules: [
            DetectionRule(id: "t", productKey: "p", productName: "P", vendor: "V",
                          category: .cameraGlasses, match: .manufacturerDataContains("META_RB_GLASS"), note: "t"),
        ])
        let d = DetectionEngine.classify(.init(manufacturerData: mfg(0x0D53)), table: testTable)
        #expect(d.category == .unknown)
    }

    // MARK: - Service UUID, both AD forms (0xFD5F → Oculus → headset)

    @Test func oculusServiceMatchesInTheServiceUUIDList_0x03() {
        let d = DetectionEngine.classify(.init(serviceUUIDs16: ["FD5F"]))
        #expect(d.category == .headset)
        #expect(d.bestTier == .serviceUUID)
        #expect(d.evidence.first?.adType == .serviceUUIDs16)
        #expect(d.evidence.first?.rawBytes == "5F FD")
        #expect(d.canNotifyInBackground == false)
    }

    @Test func oculusServiceMatchesInServiceData_0x16() {
        let d = DetectionEngine.classify(.init(serviceDataUUIDs16: ["FD5F"]))
        #expect(d.category == .headset)
        #expect(d.evidence.first?.adType == .serviceData16)
    }

    @Test func quest2FullCapture_resolvesToHeadsetHighConfidence() {
        // Exactly what a Meta Quest 2 broadcasts (captured 2026-09-10):
        // company 0x058E, service 0xFEB8 (list + data), name "Quest 2".
        let d = DetectionEngine.classify(.init(
            manufacturerData: Data([0x8E, 0x05, 0x31, 0x57, 0x4D, 0x48]),
            serviceUUIDs16: ["FEB8"],
            serviceDataUUIDs16: ["FEB8"],
            localName: "Quest 2"
        ))
        #expect(d.category == .headset)
        #expect(d.bestTier == .manufacturer)          // "High"
        #expect(d.isCameraFlag == false)
        #expect(d.canNotifyInBackground == false)
    }

    @Test func feb8AloneIsAHeadsetSignal() {
        #expect(DetectionEngine.classify(.init(serviceUUIDs16: ["FEB8"])).category == .headset)
    }

    // MARK: - Tier 3 — names

    @Test func spectaclesNameIsTier3() {
        let d = DetectionEngine.classify(.init(localName: "Spectacles 4F"))
        #expect(d.category == .cameraGlasses)
        #expect(d.bestTier == .name)
    }

    @Test func evenRealitiesG2Capture_isDisplayGlassesByCompanyOrName() {
        // The real advertisement (captured 2026-09-10): 0x5245 ("ER") + this name.
        let d = DetectionEngine.classify(.init(
            manufacturerData: Data([0x45, 0x52, 0x53, 0x32, 0x31, 0x31]),
            localName: "Even G2_32_L_5EFC69"
        ))
        #expect(d.category == .displayGlasses)
        #expect(d.isCameraFlag == false)
        #expect(d.canNotifyInBackground == false)
        #expect(d.productKey == "even-realities")

        // Name alone (either arm, G1 or G2) still resolves.
        for name in ["Even G2_32_L_5EFC69", "Even G2_32_R_5EFC70", "Even G1_7_L_a1b2"] {
            #expect(DetectionEngine.classify(.init(localName: name)).category == .displayGlasses, "\(name)")
        }
        // Near-misses must not match.
        for name in ["Even G3_1_L_x", "Evening G2_1_L_x", "Even G2_L_x", "G1_7_L_x"] {
            #expect(DetectionEngine.classify(.init(localName: name)).matched == false, "\(name)")
        }
    }

    @Test func displayGlassesWinsEvenIfAWeakerCameraRuleAlsoFires() {
        // Name matches the Even Realities arm pattern AND a camera name — display wins.
        let d = DetectionEngine.classify(.init(localName: "Even G2_7_L_Spectacles"))
        #expect(d.category == .displayGlasses)
    }

    // MARK: - Tier drives alert gating

    @Test func tierGatesBackgroundNotifications() {
        // Tier 1 camera glasses → may notify.
        #expect(DetectionEngine.classify(.init(manufacturerData: Data([0x53, 0x0D]))).canNotifyInBackground == true)
        // Tier 3 name-only camera glasses → never interrupts.
        #expect(DetectionEngine.classify(.init(localName: "Spectacles")).canNotifyInBackground == false)
        // Headset / display glasses → never.
        #expect(DetectionEngine.classify(.init(serviceUUIDs16: ["FD5F"])).canNotifyInBackground == false)
        #expect(DetectionEngine.classify(.init(localName: "Even G1_7_L_x")).canNotifyInBackground == false)
        #expect(DetectionEngine.classify(.init(localName: "Meta Quest 3")).canNotifyInBackground == false)
    }

    // MARK: - Every tier admits it's self-reported, not verified

    /// A manufacturer ID and a service UUID are exactly as spoofable as a device
    /// name — a $0 BLE advertiser tool can clone any of them (confirmed against a
    /// real capture: a cloned 0x058E broadcast with a custom name). "Confidence"
    /// must never read as "verified"; pin that every tier's explanation says so.
    @Test func everyTierExplanationAdmitsItsSelfReported() {
        for tier: DetectionTier in [.manufacturer, .serviceUUID, .name] {
            #expect(
                tier.explanation.localizedCaseInsensitiveContains("self-report")
                    || tier.explanation.localizedCaseInsensitiveContains("freely set"),
                "\(tier) explanation should admit the signal is self-reported, not verified: \(tier.explanation)"
            )
        }
    }

    // MARK: - Deliberately excluded — must NEVER match

    @Test func googleCompanyIDDoesNotMatch() {
        // 0x00E0 — every Pixel / Fast Pair device. Wire bytes E0 00.
        let d = DetectionEngine.classify(.init(manufacturerData: Data([0xE0, 0x00, 0x11, 0x22])))
        #expect(d.matched == false)
        #expect(d.category == .unknown)
    }

    @Test func samsungCompanyIDDoesNotMatch() {
        // 0x0075 — wire bytes 75 00.
        let d = DetectionEngine.classify(.init(manufacturerData: Data([0x75, 0x00, 0x11, 0x22])))
        #expect(d.matched == false)
    }

    @Test func unrelatedDeviceIsUnmatchedButStillLoggable() {
        let d = DetectionEngine.classify(.init(
            manufacturerData: Data([0x4C, 0x00]), serviceUUIDs16: ["180F"], localName: "Someone’s AirPods"
        ))
        #expect(d.matched == false)
        #expect(d.isCameraFlag == false)
    }

    // MARK: - Merge

    @Test func mergeKeepsTheStrongerTierAndUnionsEvidence() {
        let name = DetectionEngine.classify(.init(localName: "Spectacles"))
        let company = DetectionEngine.classify(.init(manufacturerData: Data([0xC2, 0x03])))
        let merged = name.merged(with: company)
        #expect(merged.bestTier == .manufacturer)
        #expect(merged.evidence.count == 2)
        #expect(merged.evidence.first?.tier == .manufacturer)   // sorted strongest-first
    }

    @Test func mergeNeverFlipsDisplayGlassesIntoACamera() {
        let display = DetectionEngine.classify(.init(localName: "Even G1_7_L_a"))
        let camera = DetectionEngine.classify(.init(manufacturerData: Data([0x53, 0x0D])))
        #expect(display.merged(with: camera).category == .displayGlasses)
    }

    @Test func mergeUpgradesAHeadsetGuessWhenAGlassesSignalArrives() {
        // A device seen first as bare 0x058E (headset), then with a Ray-Ban name.
        let headset = DetectionEngine.classify(.init(manufacturerData: mfg(0x058E)))
        #expect(headset.category == .headset)
        let named = DetectionEngine.classify(.init(localName: "Ray-Ban Meta 9C"))
        #expect(headset.merged(with: named).category == .cameraGlasses)
        // …and the reverse order resolves the same way.
        #expect(named.merged(with: headset).category == .cameraGlasses)
    }

    @Test func mergedEvidenceOnlyKeepsTheWinningCategorysRows() {
        let headset = DetectionEngine.classify(.init(manufacturerData: mfg(0x058E)))
        let named = DetectionEngine.classify(.init(localName: "Oakley Meta 1A"))
        let merged = headset.merged(with: named)
        #expect(merged.evidence.allSatisfy { $0.category == .cameraGlasses })
    }

    @Test func tierIsAlwaysConsistentWithTheMatchKind() {
        for rule in DetectionRuleTable.current.rules {
            #expect(rule.tier == rule.match.tier)
        }
    }
}
