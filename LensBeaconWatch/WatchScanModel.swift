import Foundation
import Observation
import os

/// The one object the watch UI talks to.
///
/// It is a deliberately thin cousin of the iPhone's `ScanCoordinator`: it owns the
/// same central-role `BluetoothScanner`, runs each advertisement through the same
/// `DetectionEngine`, and keeps a live map of what is in range — but it has no
/// durable log, no Live Activity, no notifications and no background story. The
/// watch is a glance, not a record.
@MainActor
@Observable
final class WatchScanModel {

    private(set) var state: BluetoothScanner.State = .idle

    /// Camera-glasses flags in range right now, strongest + nearest first.
    private(set) var flags: [WatchSighting] = []

    var isScanning: Bool { state == .scanning }

    /// Headline tier / proximity for the top-of-screen summary.
    var strongestTier: DetectionTier? { flags.compactMap(\.tier).max() }
    var nearestBand: ProximityBand? { flags.map(\.proximity).max() }

    private let scanner = BluetoothScanner()
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon.watch", category: "scan")

    /// Mutated on every advertisement (cheap); published to `flags` by the tick loop.
    private var working: [String: WatchSighting] = [:]
    private var workingDirty = false
    private let staleInterval: TimeInterval = 20
    private var tickLoop: Task<Void, Never>?

    init() {
        scanner.onEvent = { [weak self] event in
            Task { @MainActor in self?.ingest(event) }
        }
        scanner.onStateChange = { [weak self] state in
            Task { @MainActor in self?.state = state }
        }
    }

    func start() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo-scanning") {   // real empty-scan UI, no radio needed
            state = .scanning
            return
        }
        if args.contains("-demo-data") {
            loadDemo()
            return
        }
        scanner.bootstrap()
        scanner.startScanning(background: false)
        ensureTickLoop()
    }

    /// Fixed glance state for App Store screenshots — enabled only by `-demo-data`,
    /// never present on a normal launch. Every entry is classified by the real
    /// `DetectionEngine`, so the bands and evidence shown are exactly what a live
    /// scan would produce for those advertisements.
    private func loadDemo() {
        state = .scanning
        let now = Date()
        func mfg(_ c: UInt16) -> Data { Data([UInt8(c & 0xFF), UInt8(c >> 8)]) }
        let ads: [(AdvertisementFields, String, Double)] = [
            (.init(manufacturerData: mfg(0x0D53), localName: "Ray-Ban Meta"), "d1", -49),
            (.init(serviceUUIDs16: ["FD5F"]), "d2", -64),
            (.init(localName: "Spectacles 7C"), "d3", -86),
        ]
        for (ad, key, rssi) in ads {
            var smoother = RSSISmoother(initialRSSI: rssi); smoother.add(rssi)
            working[key] = WatchSighting(
                peripheralKey: key,
                detection: DetectionEngine.classify(ad),
                smoother: smoother,
                firstSeen: now, lastSeen: now
            )
        }
        publish()
    }

    func stop() {
        scanner.stopScanning()
        tickLoop?.cancel(); tickLoop = nil
    }

    // MARK: - Ingest (hot path — cheap)

    private func ingest(_ event: ScanEvent) {
        let detection = DetectionEngine.classify(event.advertisement)

        if var existing = working[event.peripheralKey] {
            existing.smoother.add(event.rssi)
            existing.detection = existing.detection.merged(with: detection)
            existing.lastSeen = event.timestamp
            working[event.peripheralKey] = existing
        } else {
            var smoother = RSSISmoother(initialRSSI: event.rssi)
            smoother.add(event.rssi)
            working[event.peripheralKey] = WatchSighting(
                peripheralKey: event.peripheralKey,
                detection: detection,
                smoother: smoother,
                firstSeen: event.timestamp,
                lastSeen: event.timestamp
            )
        }
        workingDirty = true
        ensureTickLoop()
    }

    // MARK: - Publish loop (~2 Hz, exits when idle)

    private func ensureTickLoop() {
        guard tickLoop == nil else { return }
        tickLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.tick() else { self?.tickLoop = nil; return }
            }
        }
    }

    /// One pass: prune stale, republish if anything changed. Returns whether to spin on.
    private func tick() -> Bool {
        let now = Date()
        let fresh = working.filter { now.timeIntervalSince($0.value.lastSeen) < staleInterval }
        if fresh.count != working.count { working = fresh; workingDirty = true }

        if workingDirty { workingDirty = false; publish() }
        return !working.isEmpty || state == .scanning
    }

    private func publish() {
        flags = working.values
            .filter { $0.isCameraFlag }
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return (lhs.tier ?? .name) > (rhs.tier ?? .name) }
                return lhs.proximity > rhs.proximity
            }
    }
}

/// A device currently (or very recently) in range — the watch's unit of display.
struct WatchSighting: Identifiable, Equatable {
    var id: String { peripheralKey }
    let peripheralKey: String

    var detection: Detection
    var smoother: RSSISmoother
    var firstSeen: Date
    var lastSeen: Date

    var proximity: ProximityBand { smoother.band }
    var tier: DetectionTier? { detection.bestTier }
    var isCameraFlag: Bool { detection.isCameraFlag }

    var title: String { detection.displayTitle(fallback: "Camera glasses") }

    var evidence: [DetectionEvidence] { detection.evidence }
}
