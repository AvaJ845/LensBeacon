import Foundation

/// CSV rendering for the harness's two export shapes: the raw packet log
/// (re-runnable offline against any future classifier revision) and the
/// per-device summary computed by `SessionAnalyzer`. Same escaping discipline
/// as the product app's own `SightingsStore.exportCSV` — an advertised name is
/// attacker-controlled input the moment it lands in a spreadsheet cell.
enum HarnessCSVExporter {
    static func rawPackets(_ packets: [PacketRecord], sessionID: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rows = [
            "session_id,timestamp_iso8601,peripheral_id,rssi,company_id,tier,manufacturer_data_hex,service_uuids,local_name,connectable,tx_power"
        ]
        for p in packets.sorted(by: { $0.timestamp < $1.timestamp }) {
            let tier = PacketClassifier.classify(p)
            let fields: [String] = [
                sessionID,
                iso.string(from: p.timestamp),
                p.peripheralID,
                String(p.rssi),
                p.companyID.map { String(format: "0x%04X", $0) } ?? "",
                tier.rawValue,
                p.manufacturerDataHex ?? "",
                p.serviceUUIDs.joined(separator: ";"),
                p.localName ?? "",
                p.isConnectable ? "yes" : "no",
                p.txPower.map(String.init) ?? "",
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func deviceSummaries(_ summaries: [SessionAnalyzer.DeviceSummary], sessionID: String) -> String {
        let iso = ISO8601DateFormatter()
        var rows = [
            "session_id,peripheral_id,packet_count,confirmed_count,company_id_only_count,mean_interval_seconds,median_interval_seconds,max_interval_seconds,mean_rssi,min_rssi,max_rssi,first_seen_iso8601,last_seen_iso8601"
        ]
        for s in summaries {
            let fields: [String] = [
                sessionID, s.peripheralID, String(s.packetCount), String(s.confirmedCount), String(s.companyIDOnlyCount),
                s.meanIntervalSeconds.map { String(format: "%.2f", $0) } ?? "",
                s.medianIntervalSeconds.map { String(format: "%.2f", $0) } ?? "",
                s.maxIntervalSeconds.map { String(format: "%.2f", $0) } ?? "",
                s.meanRSSI.map { String(format: "%.1f", $0) } ?? "",
                s.minRSSI.map(String.init) ?? "",
                s.maxRSSI.map(String.init) ?? "",
                iso.string(from: s.firstSeen), iso.string(from: s.lastSeen),
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        var value = value
        if let first = value.first, "=+-@\t\r".contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
