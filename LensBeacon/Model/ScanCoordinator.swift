import Foundation
import Observation
import UIKit
import os

/// The one object the UI talks to. It owns the scanner, runs every discovery event
/// through the confidence engine, maintains the live "what's nearby now" map, writes
/// through to the durable log and the shared snapshot, and drives the Live Activity.
///
/// `@MainActor`-isolated: all observable state mutates here, and the scanner delivers
/// its `Sendable` events by hopping onto this actor. There are no locks and no shared
/// mutable state outside the actor, which is what keeps the scan-callback path free of
/// the races the Distinguished Engineer review specifically looked for.
@MainActor
@Observable
final class ScanCoordinator {

    // MARK: - Observable state

    private(set) var state: BluetoothScanner.State = .idle
    /// Currently in range, keyed by opaque peripheral key.
    private(set) var live: [String: LiveSighting] = [:]
    private(set) var lastEventAt: Date?

    /// Camera-glasses flags in range now, excluding "mine", strongest + nearest first.
    var flags: [LiveSighting] {
        live.values
            .filter { $0.isCameraFlag && !$0.isMine }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return (lhs.confidence ?? .possible) > (rhs.confidence ?? .possible)
                }
                return lhs.proximity > rhs.proximity
            }
    }

    /// Everything in range now (glasses, headsets, and — behind the "show all"
    /// toggle — ordinary devices), for the Dashboard's expandable list.
    var allInRange: [LiveSighting] {
        live.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    var isScanning: Bool { state == .scanning }

    // MARK: - Dependencies

    private let scanner = BluetoothScanner()
    private unowned let sightings: SightingsStore
    private unowned let mine: MineRegistry
    private let activity = ScanActivityController()
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "coordinator")

    /// Called when a *new* likely/strong flag appears and background alerts are on.
    var onNewFlag: ((Sighting) -> Void)?

    // MARK: - Tuning

    /// A device unseen for this long drops off the Dashboard. Wide enough to ride out
    /// a few missed advertisement intervals without the list flickering.
    private let staleInterval: TimeInterval = 20
    private var housekeeping: Task<Void, Never>?
    /// Peripheral keys we have already alerted on this session, so a device that
    /// stays in range does not re-notify every housekeeping tick.
    private var alertedKeys: Set<String> = []

    init(sightings: SightingsStore, mine: MineRegistry) {
        self.sightings = sightings
        self.mine = mine

        scanner.onEvent = { [weak self] event in
            Task { @MainActor in self?.ingest(event) }
        }
        scanner.onStateChange = { [weak self] state in
            Task { @MainActor in self?.state = state }
        }
    }

    // MARK: - Lifecycle

    /// Call once at launch. Creates the central manager so a CoreBluetooth background
    /// relaunch can restore into it.
    func bootstrap() {
        scanner.bootstrap()
        startHousekeeping()
    }

    func startScanning() {
        let background = SharedContainer.defaults.bool(forKey: SharedContainer.Key.backgroundScanning)
            && SharedContainer.isUnlocked
        scanner.startScanning(background: background)
        if background { activity.startIfPossible() }
        writeSnapshot()
    }

    func stopScanning() {
        scanner.stopScanning()
        activity.end()
        writeSnapshot()
    }

    /// Foreground/background transition from the scene phase.
    func applyScenePhase(active: Bool) {
        mine.reload()
        if active {
            // Coming forward: always scan while the app is open.
            scanner.startScanning(background: false)
        } else {
            let keepGoing = SharedContainer.defaults.bool(forKey: SharedContainer.Key.backgroundScanning)
                && SharedContainer.isUnlocked
            if keepGoing {
                scanner.startScanning(background: true)
                activity.startIfPossible()
            } else {
                scanner.stopScanning()
                activity.end()
            }
        }
        writeSnapshot()
    }

    // MARK: - Ingest

    private func ingest(_ event: ScanEvent) {
        lastEventAt = event.timestamp
        let classification = ConfidenceEngine.classify(event.advertisement)

        // Ordinary, unmatched devices are logged (the Sightings log is "everything
        // seen") but never held in the live Dashboard map beyond the "show all" view.
        let isMine = mine.contains(event.peripheralKey)

        if var existing = live[event.peripheralKey] {
            existing.smoother.add(event.rssi)
            existing.classification = mergeClassification(existing.classification, classification)
            existing.lastSeen = event.timestamp
            existing.isMine = isMine
            live[event.peripheralKey] = existing
        } else {
            var smoother = RSSISmoother(initialRSSI: event.rssi)
            smoother.add(event.rssi)
            live[event.peripheralKey] = LiveSighting(
                peripheralKey: event.peripheralKey,
                classification: classification,
                smoother: smoother,
                firstSeen: event.timestamp,
                lastSeen: event.timestamp,
                isMine: isMine
            )
        }

        let band = live[event.peripheralKey]?.proximity ?? .far
        let record = sightings.record(
            peripheralKey: event.peripheralKey,
            classification: live[event.peripheralKey]?.classification ?? classification,
            rssi: event.rssi,
            proximity: band,
            at: event.timestamp
        )

        maybeAlert(for: record, key: event.peripheralKey, isMine: isMine)
        writeSnapshot()
    }

    /// Keeps the strongest classification a device has shown this session, so a
    /// momentarily degraded advertisement does not downgrade a confirmed flag.
    private func mergeClassification(
        _ current: ConfidenceEngine.Classification,
        _ incoming: ConfidenceEngine.Classification
    ) -> ConfidenceEngine.Classification {
        switch (current.confidence, incoming.confidence) {
        case (nil, _): return incoming.category == nil ? current : incoming
        case let (.some(a), .some(b)): return b >= a ? incoming : current
        case (.some, nil): return current
        }
    }

    private func maybeAlert(for record: Sighting, key: String, isMine: Bool) {
        guard !isMine,
              record.isCameraFlag,
              let confidence = record.confidence, confidence >= .likely,
              !alertedKeys.contains(key),
              SharedContainer.defaults.bool(forKey: SharedContainer.Key.alertsEnabled),
              SharedContainer.isUnlocked
        else { return }
        alertedKeys.insert(key)
        onNewFlag?(record)
    }

    // MARK: - Housekeeping

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
        // A device that left is eligible to re-alert if it comes back later.
        if live.count != before {
            alertedKeys = alertedKeys.filter { live[$0] != nil }
            writeSnapshot()
        }
    }

    // MARK: - Shared snapshot

    private func writeSnapshot() {
        let items = flags.prefix(5).map { flag in
            DashboardSnapshot.Item(
                id: flag.peripheralKey,
                productName: flag.title,
                confidence: flag.confidence ?? .possible,
                proximity: flag.proximity
            )
        }
        let snapshot = DashboardSnapshot(
            updatedAt: Date(),
            isScanning: isScanning,
            flagged: Array(items)
        )
        snapshot.save()
        activity.update(with: snapshot)
    }
}
