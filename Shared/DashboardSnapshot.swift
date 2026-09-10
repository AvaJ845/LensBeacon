import Foundation

/// A tiny, Codable picture of "what is nearby right now", written by the app into
/// the App Group so the Home Screen widget and the Live Activity can render without
/// running a scan of their own (extensions get no `bluetooth-central` background
/// time, and starting a second `CBCentralManager` there would be wasteful and
/// confusing).
///
/// It carries counts and bands only — never a device identifier, never anything
/// that could correlate a person across time. Even the per-item `productName` is the
/// matched signature's product family, not a name pulled from the air.
struct DashboardSnapshot: Codable, Equatable, Sendable {

    struct Item: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var productName: String
        var confidence: ConfidenceLevel
        var proximity: ProximityBand
    }

    /// When the app last wrote this. The widget shows relative age so a stale
    /// snapshot cannot masquerade as a live reading.
    var updatedAt: Date
    /// Whether a scan was actually running when this was written.
    var isScanning: Bool
    /// Currently-flagged camera glasses, strongest first, excluding "mine".
    var flagged: [Item]

    var strongestConfidence: ConfidenceLevel? { flagged.map(\.confidence).max() }
    var nearestBand: ProximityBand? { flagged.map(\.proximity).max() }

    static let empty = DashboardSnapshot(updatedAt: .distantPast, isScanning: false, flagged: [])

    // MARK: - App Group persistence

    static func load() -> DashboardSnapshot {
        guard let data = SharedContainer.defaults.data(forKey: SharedContainer.Key.dashboardSnapshot),
              let snapshot = try? JSONDecoder.iso.decode(DashboardSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder.iso.encode(self) else { return }
        SharedContainer.defaults.set(data, forKey: SharedContainer.Key.dashboardSnapshot)
    }
}

extension JSONEncoder {
    /// Shared ISO-8601 encoder so the app and both extensions round-trip identically.
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
