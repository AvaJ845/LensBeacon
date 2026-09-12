import Foundation

/// CSV rendering for the harness's two export shapes: the raw packet log
/// (re-runnable offline against any future classifier revision) and the
/// per-device summary computed by `SessionAnalyzer`.
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
                csvField(sessionID),
                csvField(iso.string(from: p.timestamp)),
                csvField(p.peripheralID),
                csvField(String(p.rssi)),
                csvField(p.companyID.map { String(format: "0x%04X", $0) } ?? ""),
                csvField(tier.rawValue),
                csvField(p.manufacturerDataHex ?? ""),
                csvField(p.serviceUUIDs.joined(separator: ";")),
                escapeFreeText(p.localName ?? ""),
                csvField(p.isConnectable ? "yes" : "no"),
                csvField(p.txPower.map(String.init) ?? ""),
            ]
            rows.append(fields.joined(separator: ","))
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
                csvField(sessionID), csvField(s.peripheralID),
                csvField(String(s.packetCount)), csvField(String(s.confirmedCount)), csvField(String(s.companyIDOnlyCount)),
                csvField(s.meanIntervalSeconds.map { String(format: "%.2f", $0) } ?? ""),
                csvField(s.medianIntervalSeconds.map { String(format: "%.2f", $0) } ?? ""),
                csvField(s.maxIntervalSeconds.map { String(format: "%.2f", $0) } ?? ""),
                csvField(s.meanRSSI.map { String(format: "%.1f", $0) } ?? ""),
                csvField(s.minRSSI.map(String.init) ?? ""),
                csvField(s.maxRSSI.map(String.init) ?? ""),
                csvField(iso.string(from: s.firstSeen)), csvField(iso.string(from: s.lastSeen)),
            ]
            rows.append(fields.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// Plain CSV quoting — commas/quotes/newlines only. **Never** applied with
    /// formula-injection defusal to a field we generated ourselves (a count,
    /// an RSSI reading, an interval, a UUID, an ISO-8601 date): those can
    /// legitimately start with `-` (every RSSI value in dBm does) and must
    /// never be silently rewritten into a quoted string — that turns a numeric
    /// column into text in Excel/Numbers/Sheets, breaking sorting and
    /// charting. Confirmed as a real bug against exported field data: every
    /// RSSI column came back prefixed with `'` (`'-49.0`) from the version of
    /// this function that ran the formula-injection check over every field.
    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Formula-injection defusal *and* CSV quoting — for the one field that's
    /// actually free text controlled by the broadcasting device (its
    /// advertised name). Same defense as `SightingsStore.csvEscape`.
    private static func escapeFreeText(_ value: String) -> String {
        var value = value
        if let first = value.first, "=+-@\t\r".contains(first) { value = "'" + value }
        return csvField(value)
    }
}
