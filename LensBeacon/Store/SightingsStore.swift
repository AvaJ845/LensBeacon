import Foundation
import Observation
import os

/// The durable Sightings log — **glasses only**.
///
/// It records the camera and display glasses LensBeacon has recognised, each with
/// its evidence. It does *not* persist the anonymous phones / watches / tags it also
/// hears: after 15 minutes their rotating identifiers mean nothing, a wall of
/// "Unrecognised device" rows is not something the user can act on, and "logs every
/// Bluetooth device around you" is not the posture a calm awareness tool wants. The
/// live "also broadcasting nearby" list on the Dashboard still shows everything in
/// range for the moment it is there, for anyone who wants to sanity-check the scan.
///
/// Design constraints:
///  - **On-device only.** A single JSON file in the App Group container, written
///    with `.completeFileProtection` so it is encrypted at rest and unreadable while
///    the device is locked.
///  - **Bounded.** One record per device key; a hard cap on record count; age-based
///    pruning (7 days on the free tier, unlimited with Unlock).
///  - **Not backed up.** Marked `isExcludedFromBackup` — local telemetry, and BLE
///    identifiers rotate anyway, so there is nothing to preserve across a restore.
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

    /// On-disk envelope. Bumped when `Sighting`'s Codable shape changes — a mismatch
    /// starts the log fresh rather than throwing a decode error mid-launch.
    private struct Persisted: Codable {
        var schemaVersion: Int
        var sightings: [Sighting]
    }
    private static let schemaVersion = 3

    private let fileURL: URL
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "sightings")
    private var saveTask: Task<Void, Never>?
    private var saveScheduled = false
    /// Bytes written on the last successful save. Tracked in memory so the Settings
    /// "Data" readout does not need a file-attribute API (a required-reason API).
    private(set) var approximateByteCount = 0

    /// `fileURL` is injectable so tests can point at a scratch file instead of the
    /// App Group container.
    init(fileURL: URL = SharedContainer.sightingsFileURL) {
        self.fileURL = fileURL
        load()
    }

    // MARK: - Ingest

    /// Records or updates a device from a live detection. Returns the resulting
    /// record so callers can react (e.g. fire a "new flag" notification).
    ///
    /// **Only recognised camera / display glasses are persisted.** A headset or an
    /// unmatched device produces an ephemeral `Sighting` that is returned but never
    /// stored.
    @discardableResult
    func record(
        peripheralKey: String,
        detection: Detection,
        rssi: Double,
        proximity: ProximityBand,
        at date: Date = Date()
    ) -> Sighting {
        guard detection.category.isGlasses else {
            return Sighting.make(peripheralKey: peripheralKey, detection: detection,
                                 rssi: rssi, proximity: proximity, at: date)
        }
        if let idx = sightings.firstIndex(where: { $0.peripheralKey == peripheralKey }) {
            sightings[idx].update(with: detection, rssi: rssi, proximity: proximity, at: date)
            let updated = sightings[idx]
            scheduleSave()
            return updated
        } else {
            let new = Sighting.make(
                peripheralKey: peripheralKey, detection: detection,
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
        case all = "All"
        case mine = "Mine"
        var id: String { rawValue }
    }

    func filtered(_ filter: Filter, mine: MineRegistry) -> [Sighting] {
        let visible = sightings.filter { withinRetention($0) && $0.detection.category.isGlasses }
        switch filter {
        case .all:
            return visible.sorted { $0.lastSeen > $1.lastSeen }
        case .mine:
            return visible.filter { mine.contains(productKey: $0.productKey) }
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
        var rows = ["local_key,first_seen,last_seen,category,tier,product,vendor,product_key,marked_mine,evidence"]
        for s in sightings.filter({ withinRetention($0) }).sorted(by: { $0.lastSeen > $1.lastSeen }) {
            let evidence = s.evidence
                .map { "\($0.adType.label) \($0.matchedValue) [\($0.tier.shortTitle)]" }
                .joined(separator: "; ")
            let fields: [String] = [
                s.peripheralKey,
                iso.string(from: s.firstSeen),
                iso.string(from: s.lastSeen),
                s.category.rawValue,
                s.tier?.shortTitle ?? "",
                s.detection.productName ?? "",
                s.detection.vendor ?? "",
                s.productKey ?? "",
                mine.contains(productKey: s.productKey) ? "yes" : "no",
                evidence,
            ]
            rows.append(fields.map(Self.csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        // Defuse spreadsheet formula injection: a field a device controls (its
        // advertised name flows into `productName` / the evidence bullets) that
        // begins with =, +, -, @, or a control char is executed as a formula by
        // Excel / Numbers / Sheets. Prefix a single quote so it stays literal text.
        var value = value
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Maintenance

    func pruneNow() {
        let before = sightings.count
        sightings.removeAll { !withinRetention($0) }
        if sightings.count != before { scheduleSave() }
    }

    /// Wipes the log **synchronously and completely**: cancels any pending debounced
    /// write, empties memory, and deletes the file from disk now. Unlike a normal
    /// `scheduleSave()`, nothing survives the app being killed in the next two
    /// seconds. Used by the Settings data controls.
    func wipe() {
        saveTask?.cancel()
        saveScheduled = false
        sightings.removeAll()
        approximateByteCount = 0
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            log.error("sightings wipe failed to remove file: \(error.localizedDescription, privacy: .public)")
            // Fall back to overwriting with an empty array so nothing is recoverable.
            saveNow()
        }
    }

    /// Retained for callers that expect the old name; a full synchronous wipe.
    func clearAll() { wipe() }

    private func enforceCap() {
        guard sightings.count > Self.maxRecords else { return }
        // Drop the least-recently-seen records first.
        sightings.sort { $0.lastSeen > $1.lastSeen }
        sightings.removeLast(sightings.count - Self.maxRecords)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }

        // Current schema — the fast path.
        if let stored = try? JSONDecoder.iso.decode(Persisted.self, from: data),
           stored.schemaVersion == Self.schemaVersion {
            sightings = stored.sightings
            approximateByteCount = data.count
            return
        }

        // Older or partly-incompatible file: keep every record that still decodes
        // rather than wiping the user's history on an update. Anything that doesn't
        // parse is dropped, and the file is rewritten in the current shape.
        let recovered = recoverRecords(from: data)
        log.notice("sightings migrated: kept \(recovered.count) record(s) across a schema change")
        sightings = recovered
        if !recovered.isEmpty { saveNow() }
    }

    /// A record that decodes to `nil` instead of throwing when its shape no longer
    /// matches — so one incompatible row doesn't lose the whole file.
    private struct FailableSighting: Decodable {
        let value: Sighting?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(Sighting.self)
        }
    }

    /// Decode the record array element-by-element, tolerating individual failures.
    /// Two on-disk shapes have existed: `{schemaVersion, sightings:[…]}` and a bare `[…]`.
    private func recoverRecords(from data: Data) -> [Sighting] {
        struct LenientEnvelope: Decodable { var sightings: [FailableSighting] }
        if let env = try? JSONDecoder.iso.decode(LenientEnvelope.self, from: data) {
            return env.sightings.compactMap(\.value)
        }
        if let bare = try? JSONDecoder.iso.decode([FailableSighting].self, from: data) {
            return bare.compactMap(\.value)
        }
        return []
    }

    /// Debounced write. A busy scan can touch the log many times a second; rather
    /// than cancel-and-recreate a `Task` on every touch (constant task churn), the
    /// first touch in a quiet period schedules a single flush and later touches
    /// within the window are no-ops.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.saveScheduled = false
            self.saveNow()
        }
    }

    func saveNow() {
        let snapshot = Persisted(schemaVersion: Self.schemaVersion, sightings: sightings)
        do {
            let data = try JSONEncoder.iso.encode(snapshot)
            // `.completeFileProtection` — a presence log is more sensitive than most
            // caches, so it is unreadable while the device is locked. A background
            // write that lands during a lock throws; the data stays in memory and the
            // next touch (or foreground) reschedules the flush.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            approximateByteCount = data.count
            excludeFromBackup()
        } catch {
            log.error("sightings save deferred (device locked?): \(error.localizedDescription, privacy: .public)")
            scheduleSave()
        }
    }

    private func excludeFromBackup() {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
