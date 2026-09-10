import Foundation
import Observation
import os

/// The durable Sightings log.
///
/// Design constraints:
///  - **On-device only.** A single JSON file in the App Group container, written
///    with `.completeUntilFirstUserAuthentication` data protection so it is
///    encrypted at rest and unreadable before first unlock after a reboot.
///  - **Bounded.** One record per device; a hard cap on record count; age-based
///    pruning (7 days on the free tier, unlimited with Unlock).
///  - **Not backed up in a way that leaks.** The file is marked
///    `isExcludedFromBackup` — the log is ephemeral local telemetry, not user
///    documents, and BLE identifiers rotate anyway, so there is nothing to preserve
///    across a restore.
@MainActor
@Observable
final class SightingsStore {

    private(set) var sightings: [Sighting] = []

    /// Free tier keeps a week; Unlock keeps everything. Set by `UnlockStore`.
    var retention: RetentionPolicy = .days(7)

    enum RetentionPolicy: Equatable {
        case days(Int)
        case unlimited

        var cutoff: Date? {
            switch self {
            case .days(let d): return Calendar.current.date(byAdding: .day, value: -d, to: Date())
            case .unlimited:   return nil
            }
        }
    }

    static let maxRecords = 2_000

    private let fileURL = SharedContainer.sightingsFileURL
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "sightings")
    private var saveTask: Task<Void, Never>?

    init() {
        load()
    }

    // MARK: - Ingest

    /// Records or updates a device from a live classification. Returns the resulting
    /// record so callers can react (e.g. fire a "new flag" notification).
    @discardableResult
    func record(
        peripheralKey: String,
        classification: ConfidenceEngine.Classification,
        rssi: Double,
        proximity: ProximityBand,
        at date: Date = Date()
    ) -> Sighting {
        if let idx = sightings.firstIndex(where: { $0.peripheralKey == peripheralKey }) {
            sightings[idx].update(with: classification, rssi: rssi, proximity: proximity, at: date)
            let updated = sightings[idx]
            scheduleSave()
            return updated
        } else {
            let new = Sighting.make(
                peripheralKey: peripheralKey, classification: classification,
                rssi: rssi, proximity: proximity, at: date
            )
            sightings.insert(new, at: 0)
            enforceCap()
            scheduleSave()
            return new
        }
    }

    // MARK: - Queries

    enum Filter: String, CaseIterable, Identifiable {
        case glasses = "Glasses"
        case all = "All"
        case mine = "Mine"
        var id: String { rawValue }
    }

    func filtered(_ filter: Filter, mine: MineRegistry) -> [Sighting] {
        let visible = sightings.filter { withinRetention($0) }
        switch filter {
        case .all:
            return visible.sorted { $0.lastSeen > $1.lastSeen }
        case .glasses:
            return visible.filter { $0.category == .cameraGlasses }
                .sorted { $0.lastSeen > $1.lastSeen }
        case .mine:
            return visible.filter { mine.contains($0.peripheralKey) }
                .sorted { $0.lastSeen > $1.lastSeen }
        }
    }

    func withinRetention(_ sighting: Sighting) -> Bool {
        guard let cutoff = retention.cutoff else { return true }
        return sighting.lastSeen >= cutoff
    }

    // MARK: - CSV export (Unlock feature)

    /// Renders the *currently visible* log as CSV. The header spells out every column
    /// so the user sees exactly what they are exporting — no hidden fields, no
    /// identifiers beyond the app's own opaque key.
    func exportCSV(mine: MineRegistry) -> String {
        let iso = ISO8601DateFormatter()
        var rows = ["local_key,first_seen,last_seen,category,confidence,product,vendor,marked_mine,evidence"]
        for s in sightings.filter({ withinRetention($0) }).sorted(by: { $0.lastSeen > $1.lastSeen }) {
            let fields: [String] = [
                s.peripheralKey,
                iso.string(from: s.firstSeen),
                iso.string(from: s.lastSeen),
                s.category.rawValue,
                s.confidence?.title ?? "",
                s.productName ?? "",
                s.vendor ?? "",
                mine.contains(s.peripheralKey) ? "yes" : "no",
                s.evidenceBullets.joined(separator: "; "),
            ]
            rows.append(fields.map(Self.csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Maintenance

    func pruneNow() {
        let before = sightings.count
        sightings.removeAll { !withinRetention($0) }
        if sightings.count != before { scheduleSave() }
    }

    func clearAll() {
        sightings.removeAll()
        scheduleSave()
    }

    private func enforceCap() {
        guard sightings.count > Self.maxRecords else { return }
        // Drop the least-recently-seen records first.
        sightings.sort { $0.lastSeen > $1.lastSeen }
        sightings.removeLast(sightings.count - Self.maxRecords)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            sightings = try JSONDecoder.iso.decode([Sighting].self, from: data)
        } catch {
            log.error("sightings decode failed, starting fresh: \(error.localizedDescription, privacy: .public)")
            sightings = []
        }
    }

    /// Debounced write — a busy scan can touch the log many times a second.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snapshot = sightings
        do {
            let data = try JSONEncoder.iso.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            excludeFromBackup()
        } catch {
            log.error("sightings save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func excludeFromBackup() {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
