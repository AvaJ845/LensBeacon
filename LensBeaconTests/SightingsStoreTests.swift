import Testing
import Foundation

/// The durable log persists user data. These cover its retention window, its hard
/// record cap, its CSV escaping, and that "clear" actually clears.
@MainActor
struct SightingsStoreTests {

    private func makeStore() -> (SightingsStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lb-test-\(UUID().uuidString).json")
        return (SightingsStore(fileURL: url), url)
    }

    /// A Tier 1 camera detection via the real engine (Luxottica company ID).
    private func metaGlasses(name: String = "Ray-Ban Meta") -> Detection {
        DetectionEngine.classify(.init(manufacturerData: Data([0x53, 0x0D]), localName: name))
    }

    @Test func sevenDayRetentionHidesOlderRecordsButKeepsThemForUnlock() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let old = Date().addingTimeInterval(-8 * 86_400)
        let fresh = Date().addingTimeInterval(-1 * 86_400)
        store.record(peripheralKey: "old", detection: metaGlasses(), rssi: -60, proximity: .nearby, at: old)
        store.record(peripheralKey: "new", detection: metaGlasses(), rssi: -50, proximity: .near, at: fresh)

        store.retention = .days(7)
        #expect(store.filtered(.all, mine: MineRegistry()).map(\.peripheralKey) == ["new"])

        store.retention = .unlimited
        #expect(store.filtered(.all, mine: MineRegistry()).count == 2)
    }

    @Test func enforcesTheHardRecordCap() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        for i in 0...(SightingsStore.maxRecords + 25) {
            store.record(peripheralKey: "dev-\(i)", detection: metaGlasses(),
                         rssi: -70, proximity: .far, at: Date())
        }
        #expect(store.sightings.count == SightingsStore.maxRecords)
    }

    @Test func csvHasALabelledHeaderAndNoFieldCanStartAFormula() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // A hostile advertised name reaches the evidence column via a name-tier match.
        store.record(peripheralKey: "evil",
                     detection: DetectionEngine.classify(.init(localName: "=cmd|'/c calc' Spectacles")),
                     rssi: -50, proximity: .near, at: Date())

        let csv = store.exportCSV(mine: MineRegistry())
        #expect(csv.hasPrefix("local_key,first_seen,last_seen,category,tier,product,vendor,product_key,marked_mine,evidence"))
        #expect(csv.contains("Spectacles"))   // the match is recorded…
        // …but no field begins a spreadsheet formula: not at the start of a line,
        // not right after a delimiter, not just inside an opening quote.
        #expect(!csv.contains(",="))
        #expect(!csv.contains("\n="))
        #expect(!csv.contains("\"="))
    }

    @Test func sessionReportListsEachDeviceWithItsTierAndTheHonestyLine() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(peripheralKey: "a", detection: metaGlasses(), rssi: -50, proximity: .near, at: Date())
        let mine = MineRegistry()

        let report = store.sessionReport(filter: .all, mine: mine)
        #expect(report.hasPrefix("LensBeacon — Session Report"))
        #expect(report.contains("1 recognised device:"))
        #expect(report.contains("Ray-Ban / Oakley Meta"))
        #expect(report.contains("High confidence"))
        #expect(report.contains(Copy.notAccusation))
    }

    @Test func sessionReportSaysSoWhenThereIsNothingToReport() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let report = store.sessionReport(filter: .all, mine: MineRegistry())
        #expect(report.contains("No recognised camera or display glasses in this period."))
    }

    /// The share sheet must only ever contain what the current tab is showing —
    /// switching to "Mine" and sharing must never smuggle in someone else's
    /// nearby glasses that aren't even visible in that filtered list.
    @Test func sessionReportOnTheMineFilterOnlyIncludesDevicesMarkedMine() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let snapDetection = DetectionEngine.classify(.init(localName: "Spectacles"))
        store.record(peripheralKey: "meta", detection: metaGlasses(), rssi: -50, proximity: .near, at: Date())
        store.record(peripheralKey: "snap", detection: snapDetection, rssi: -55, proximity: .near, at: Date())

        let mine = MineRegistry()
        mine.setMine(true, productKey: metaGlasses().productKey)

        let allReport = store.sessionReport(filter: .all, mine: mine)
        #expect(allReport.contains("2 recognised devices:"))
        #expect(allReport.contains("Ray-Ban / Oakley Meta"))
        #expect(allReport.contains("Spectacles"))

        let mineReport = store.sessionReport(filter: .mine, mine: mine)
        #expect(mineReport.contains("1 recognised device:"))
        #expect(mineReport.contains("Ray-Ban / Oakley Meta"))
        #expect(!mineReport.contains("Spectacles"))
    }

    @Test func wipeEmptiesMemoryAndDeletesTheFile() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        store.record(peripheralKey: "d", detection: metaGlasses(), rssi: -60, proximity: .nearby, at: Date())
        store.saveNow()
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.wipe()
        #expect(store.sightings.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func strongestTierIsStickyAcrossReSightings() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let strong = metaGlasses()                                  // Tier 1
        let weak = DetectionEngine.classify(.init(localName: "Spectacles"))  // Tier 3
        store.record(peripheralKey: "d", detection: strong, rssi: -50, proximity: .near, at: Date())
        store.record(peripheralKey: "d", detection: weak, rssi: -80, proximity: .far, at: Date())
        #expect(store.sightings.first?.tier == .manufacturer)
    }

    @Test func unmatchedDevicesAreNeverPersisted() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        // An anonymous phone — no rule matches.
        let anon = DetectionEngine.classify(.init(manufacturerData: Data([0xE0, 0x00])))
        store.record(peripheralKey: "phone", detection: anon, rssi: -55, proximity: .nearby, at: Date())
        #expect(store.sightings.isEmpty)

        store.record(peripheralKey: "cam", detection: metaGlasses(), rssi: -50, proximity: .near, at: Date())
        #expect(store.sightings.count == 1)
    }

    @Test func loadPreservesRecordsThatStillParseAndDropsThoseThatDont() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lb-migrate-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        // Hand-write a file with one valid record shape and one garbage element.
        let (seed, _) = { () -> (SightingsStore, URL) in (SightingsStore(fileURL: url), url) }()
        seed.record(peripheralKey: "good", detection: metaGlasses(), rssi: -50, proximity: .near, at: Date())
        seed.saveNow()
        var raw = String(data: try! Data(contentsOf: url), encoding: .utf8)!
        raw = raw.replacingOccurrences(of: "\"sightings\":[", with: "\"sightings\":[{\"broken\":true},")
        raw = raw.replacingOccurrences(of: "\"schemaVersion\":3", with: "\"schemaVersion\":1")
        try! raw.data(using: .utf8)!.write(to: url)

        let reloaded = SightingsStore(fileURL: url)
        #expect(reloaded.sightings.map(\.peripheralKey) == ["good"])
    }

    @Test func allShowsGlassesAndMineKeysOnProduct() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let mine = MineRegistry()

        store.record(peripheralKey: "cam", detection: metaGlasses(), rssi: -50, proximity: .near, at: Date())
        store.record(peripheralKey: "disp",
                     detection: DetectionEngine.classify(.init(localName: "Even G1_7_L_a1")),
                     rssi: -60, proximity: .nearby, at: Date())

        #expect(store.filtered(.all, mine: mine).count == 2)

        mine.setMine(true, productKey: "meta-glasses")
        #expect(store.filtered(.mine, mine: mine).map(\.peripheralKey) == ["cam"])
    }
}
