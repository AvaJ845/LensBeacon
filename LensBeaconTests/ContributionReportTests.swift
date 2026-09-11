import Testing
import Foundation

/// "Suggest what this is" is the one place raw advertisement fields reach outside
/// the app (via the system Share Sheet the user drives) — these pin the report
/// text so a future change can't silently drop a field or leak something it
/// shouldn't (a location, an identifier that isn't already shown on screen).
struct ContributionReportTests {

    private func mfg(_ company: UInt16, trailing: [UInt8] = [0xAA]) -> Data {
        Data([UInt8(company & 0xFF), UInt8(company >> 8)] + trailing)
    }

    @Test func unmatchedDeviceReportsEveryFieldAndSaysUnmatched() {
        let fields = AdvertisementFields(
            manufacturerData: mfg(0x1234),
            serviceUUIDs16: ["FE9F", "180F"],
            localName: "Mystery Gadget",
            isConnectable: true
        )
        let detection = DetectionEngine.classify(fields)
        let text = ContributionReport.text(for: fields, detection: detection, guess: nil)

        #expect(text.contains("Mystery Gadget"))
        #expect(text.contains("0x1234"))
        // Sorted, not insertion order — Set has no stable order of its own.
        #expect(text.contains("180F, FE9F"))
        #expect(text.contains("Connectable: yes"))
        #expect(text.contains("unmatched"))
        #expect(!text.contains("What the reporter believes"))
    }

    @Test func noNameAndNoManufacturerDataRenderAsNone() {
        let fields = AdvertisementFields(serviceUUIDs16: ["180F"])
        let detection = DetectionEngine.classify(fields)
        let text = ContributionReport.text(for: fields, detection: detection, guess: nil)

        #expect(text.contains("Advertised name: (none)"))
        #expect(text.contains("Manufacturer ID: (none)"))
        #expect(text.contains("Connectable: no"))
    }

    @Test func recognisedDeviceReportsItsTitleAndTier() {
        // 0x0D53 → Luxottica → a real camera-glasses match.
        let fields = AdvertisementFields(manufacturerData: Data([0x53, 0x0D, 0xAA]))
        let detection = DetectionEngine.classify(fields)
        let text = ContributionReport.text(for: fields, detection: detection, guess: nil)

        #expect(text.contains(detection.displayTitle()))
        #expect(text.contains("High confidence"))
    }

    @Test func guessIsIncludedWhenProvided() {
        let fields = AdvertisementFields(localName: "Odd Name")
        let detection = DetectionEngine.classify(fields)
        let text = ContributionReport.text(for: fields, detection: detection, guess: .snapSpectacles)

        #expect(text.contains("What the reporter believes this is: Snap Spectacles"))
    }

    @Test func neverLeaksActualLocationOrContactData() {
        // The report is allowed to *reassure* the reader that no location/identity
        // is included (and does) — it must never actually carry any.
        let fields = AdvertisementFields(localName: "Anything")
        let detection = DetectionEngine.classify(fields)
        let text = ContributionReport.text(for: fields, detection: detection, guess: .notSure)

        #expect(text.contains("nothing about the reporter's phone, identity, or location is included"))
        for word in ["GPS", "latitude", "longitude", "@", "contact"] {
            #expect(!text.localizedCaseInsensitiveContains(word), "unexpectedly mentions \(word)")
        }
    }
}
