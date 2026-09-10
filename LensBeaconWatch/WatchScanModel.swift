import Foundation
import Observation
import os

/// The one object the watch UI talks to.
///
/// It is a deliberately thin cousin of the iPhone's `ScanCoordinator`: it owns the
/// same central-role `BluetoothScanner`, runs each advertisement through the same
/// `ConfidenceEngine`, and keeps a live map of what is in range — but it has no
/// durable log, no Live Activity, no notifications and no background story. The
/// watch is a glance, not a record.
@MainActor
@Observable
final class WatchScanModel {

    private(set) var state: BluetoothScanner.State = .idle

    /// Camera-glasses flags in range right now, strongest + nearest first.
    private(set) var flags: [WatchSighting] = []

    var isScanning: Bool { state == .scanning }

    /// Headline confidence / proximity for the top-of-screen summary.
    var strongestConfidence: ConfidenceLevel? { flags.compactMap(\.confidence).max() }
    var nearestBand: ProximityBand? { flags.map(\.proximity).max() }

    private let scanner = BluetoothScanner()
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon.watch", category: "scan")

    private var live: [String: WatchSighting] = [:]
    private let staleInterval: TimeInterval = 20
    private var housekeeping: Task<Void, Never>?

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
        startHousekeeping()
    }

    /// Fixed glance state for App Store screenshots — enabled only by `-demo-data`,
    /// never present on a normal launch. Every entry is classified by the real
    /// `ConfidenceEngine`, so the bands and evidence shown are exactly what a live
    /// scan would produce for those advertisements.
    private func loadDemo() {
        state = .scanning
        let now = Date()
        let ads: [(ConfidenceEngine.Advertisement, String, Double)] = [
            (.init(companyIdentifier: 0x03A3, serviceUUIDs: ["FDF0"], localName: "Ray-Ban Meta", isConnectable: true), "d1", -49),
            (.init(companyIdentifier: 0x03A3, serviceUUIDs: [], localName: "Oakley Vanguard", isConnectable: true), "d2", -64),
            (.init(companyIdentifier: 0x0819, serviceUUIDs: ["FE60"], localName: nil, isConnectable: true), "d3", -86),
        ]
        for (ad, key, rssi) in ads {
            var smoother = RSSISmoother(initialRSSI: rssi); smoother.add(rssi)
            live[key] = WatchSighting(
                peripheralKey: key,
                classification: ConfidenceEngine.classify(ad),
                smoother: smoother,
                firstSeen: now, lastSeen: now
            )
        }
        recompute()
    }

    func stop() {
        scanner.stopScanning()
        housekeeping?.cancel()
    }

    // MARK: - Ingest

    private func ingest(_ event: ScanEvent) {
        let classification = ConfidenceEngine.classify(event.advertisement)

        if var existing = live[event.peripheralKey] {
            existing.smoother.add(event.rssi)
            if let incoming = classification.confidence,
               (existing.confidence ?? .possible) < incoming || existing.confidence == nil {
                existing.classification = classification
            }
            existing.lastSeen = event.timestamp
            live[event.peripheralKey] = existing
        } else {
            var smoother = RSSISmoother(initialRSSI: event.rssi)
            smoother.add(event.rssi)
            live[event.peripheralKey] = WatchSighting(
                peripheralKey: event.peripheralKey,
                classification: classification,
                smoother: smoother,
                firstSeen: event.timestamp,
                lastSeen: event.timestamp
            )
        }
        recompute()
    }

    private func startHousekeeping() {
        housekeeping?.cancel()
        housekeeping = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.evictStale()
            }
        }
    }

    private func evictStale() {
        let now = Date()
        let before = live.count
        live = live.filter { now.timeIntervalSince($0.value.lastSeen) < staleInterval }
        if live.count != before { recompute() }
    }

    private func recompute() {
        flags = live.values
            .filter { $0.isCameraFlag }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return (lhs.confidence ?? .possible) > (rhs.confidence ?? .possible)
                }
                return lhs.proximity > rhs.proximity
            }
    }
}

/// A device currently (or very recently) in range — the watch's unit of display.
struct WatchSighting: Identifiable, Equatable {
    var id: String { peripheralKey }
    let peripheralKey: String

    var classification: ConfidenceEngine.Classification
    var smoother: RSSISmoother
    var firstSeen: Date
    var lastSeen: Date

    var proximity: ProximityBand { smoother.band }
    var confidence: ConfidenceLevel? { classification.confidence }
    var isCameraFlag: Bool { classification.isCameraFlag }

    var title: String {
        classification.productName
            ?? classification.vendor.map { "\($0) device" }
            ?? "Camera glasses"
    }

    var evidenceBullets: [String] {
        classification.evidence.flatMap(\.bullets)
    }
}
