import Testing
import Foundation

/// Real bug, confirmed against an actual field capture: negative numbers we
/// generate ourselves (RSSI is always negative in dBm) were being prefixed
/// with `'` by the formula-injection defusal, turning a numeric column into
/// text in a spreadsheet. That defusal must apply only to genuinely free-text,
/// device-controlled fields (the advertised local name), never to a field
/// this exporter formats itself.
struct HarnessCSVExporterTests {

    @Test func negativeRSSIInRawPacketsIsNeverQuotedOrPrefixed() {
        let packet = PacketRecord(peripheralID: "p", timestamp: Date(), rssi: -49)
        let csv = HarnessCSVExporter.rawPackets([packet], sessionID: "s")
        let dataRow = csv.split(separator: "\n")[1]
        #expect(dataRow.contains(",-49,"))
        #expect(!dataRow.contains("'-49"))
    }

    @Test func negativeRSSIStatsInDeviceSummaryAreNeverQuotedOrPrefixed() {
        let now = Date()
        let packets = [-50.0, -55.0].map { PacketRecord(peripheralID: "p", timestamp: now, rssi: Int($0)) }
        let summaries = SessionAnalyzer.summarize(packets)
        let csv = HarnessCSVExporter.deviceSummaries(summaries, sessionID: "s")
        #expect(!csv.contains("'-"))
        #expect(csv.contains("-52.5")) // mean of -50 and -55
    }

    @Test func aDeviceNameStartingWithAFormulaCharacterIsStillDefused() {
        let packet = PacketRecord(peripheralID: "p", timestamp: Date(), rssi: -50, localName: "=cmd|'/bin/bash'")
        let csv = HarnessCSVExporter.rawPackets([packet], sessionID: "s")
        #expect(csv.contains("'=cmd"))
    }

    @Test func headerRowIsPresentEvenWithNoPackets() {
        #expect(HarnessCSVExporter.rawPackets([], sessionID: "s").hasPrefix("session_id,timestamp_iso8601"))
        #expect(HarnessCSVExporter.deviceSummaries([], sessionID: "s").hasPrefix("session_id,peripheral_id"))
        #expect(HarnessCSVExporter.events([], sessionID: "s").hasPrefix("session_id,timestamp_iso8601"))
    }

    @Test func eventsExportInChronologicalOrderRegardlessOfInputOrder() {
        let now = Date()
        let events = [
            SessionEventRecord(kind: .metaAIQuery, at: now.addingTimeInterval(10)),
            SessionEventRecord(kind: .photoCapture, at: now),
        ]
        let csv = HarnessCSVExporter.events(events, sessionID: "s")
        let rows = csv.split(separator: "\n").dropFirst()
        #expect(rows.first?.contains("photoCapture") == true)
        #expect(rows.last?.contains("metaAIQuery") == true)
    }
}
