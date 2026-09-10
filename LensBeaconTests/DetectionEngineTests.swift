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

    @Test func snapCompanyID() {
        let d = DetectionEngine.classify(.init(manufacturerData: mfg(0x03C2)))
        #expect(d.bestTier == .manufacturer)
        #expect(d.evidence.first?.matchedValue == "0x03C2")
        #expect(d.evidence.first?.rawBytes == "C2 03")
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

    // MARK: - Tier 3 — names

    @Test func spectaclesNameIsTier3() {
        let d = DetectionEngine.classify(.init(localName: "Spectacles 4F"))
        #expect(d.category == .cameraGlasses)
        #expect(d.bestTier == .name)
    }

    @Test func evenRealitiesRegexMatchesBothArmsAndIsDisplayGlasses() {
        for name in ["G1_7_L_a1b2", "G1_12_R_ffee", "G1_0_L_0"] {
            let d = DetectionEngine.classify(.init(localName: name))
            #expect(d.category == .displayGlasses, "\(name) should be display glasses")
            #expect(d.isCameraFlag == false)
            #expect(d.productKey == "even-realities")
        }
        // Near-misses must not match.
        for name in ["G1_L_abc", "XG1_7_L_a", "G2_7_L_a"] {
            #expect(DetectionEngine.classify(.init(localName: name)).matched == false, "\(name) should not match")
        }
    }

    @Test func displayGlassesWinsEvenIfAWeakerCameraRuleAlsoFires() {
        // Name matches the G1 regex AND (hypothetically) a camera name — display wins.
        let d = DetectionEngine.classify(.init(localName: "G1_7_L_Spectacles"))
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
        #expect(DetectionEngine.classify(.init(localName: "G1_7_L_x")).canNotifyInBackground == false)
        #expect(DetectionEngine.classify(.init(localName: "Meta Quest 3")).canNotifyInBackground == false)
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
        let display = DetectionEngine.classify(.init(localName: "G1_7_L_a"))
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
