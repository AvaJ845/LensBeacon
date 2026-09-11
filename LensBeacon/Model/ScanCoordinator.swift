import Foundation
import Observation
import UIKit
import WidgetKit
import os

/// The one object the UI talks to. It owns the scanner, runs every discovery event
/// through the confidence engine, maintains the live "what's nearby now" map, writes
/// through to the durable log and the shared snapshot, and drives the Live Activity.
///
/// `@MainActor`-isolated: all observable state mutates here, and the scanner delivers
/// its `Sendable` events by hopping onto this actor. There are no locks and no shared
/// mutable state outside the actor, which is what keeps the scan-callback path free of
/// the races the Distinguished Engineer review specifically looked for.
///
/// **Energy discipline.** CoreBluetooth delivers several advertisements a second per
/// device in a crowd. The hot path (`ingest`) does the minimum — smooth the RSSI,
/// merge the classification, stamp `lastSeen` — into a *private* working map. A
/// single ~2 Hz display loop publishes that to the observable state, prunes stale
/// devices, and (at most once a second, only on a real change) rewrites the shared
/// snapshot and nudges WidgetKit. The durable log is written at most once per second
/// per device, except on a first sighting or a confidence upgrade, which persist
/// immediately. Nothing polls while a scan isn't running.
@MainActor
@Observable
final class ScanCoordinator {

    // MARK: - Observable state

    private(set) var state: BluetoothScanner.State = .idle
    /// Currently in range, keyed by opaque peripheral key. Published from the display
    /// loop, not mutated on every advertisement.
    private(set) var live: [String: LiveSighting] = [:]
    private(set) var lastEventAt: Date?

    /// Camera-glasses flags worth surfacing prominently: Tier 1 (manufacturer ID) or
    /// Tier 2 (service UUID), not marked "mine". A bare name match is *not* enough —
    /// it would flood the Dashboard and train users to ignore it.
    private(set) var flags: [LiveSighting] = []

    /// Camera matches carried by a Tier 3 signal only (advertised name). Shown as a
    /// quiet badge; never raises a background notification.
    private(set) var weakSignals: [LiveSighting] = []

    /// Display glasses with no camera (Even Realities) in range now — surfaced so the
    /// user knows what they are, never counted as a camera.
    private(set) var displayGlasses: [LiveSighting] = []

    /// Headsets in range now (Quest, Vision Pro) — camera-capable but worn openly.
    /// Listed for awareness, never flagged, never an alert.
    private(set) var headsets: [LiveSighting] = []

    /// Everything in range now, for the Dashboard's expandable list.
    private(set) var allInRange: [LiveSighting] = []

    /// The user has switched scanning off from the Dashboard or the Live Activity.
    /// Persisted so it survives a scene change and a relaunch — a listening tool the
    /// user silenced stays silent until they say otherwise.
    private(set) var isPaused: Bool = SharedContainer.defaults.bool(forKey: SharedContainer.Key.scanningPaused)

    var isScanning: Bool { state == .scanning }

    // MARK: - Dependencies

    private let scanner = BluetoothScanner()
    private unowned let sightings: SightingsStore
    private unowned let mine: MineRegistry
    private let activity = ScanActivityController()
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "coordinator")

    /// Called when a *new* likely/strong flag appears and background alerts are on.
    var onNewFlag: ((Sighting) -> Void)?

    // MARK: - Working state (never observed directly)

    /// The map the hot path mutates. Copied into `live` by the display loop only when
    /// it has actually changed.
    private var working: [String: LiveSighting] = [:]
    /// Set whenever `working` changes; lets an idle tick skip all recomputation.
    private var workingDirty = false
    /// Last time each device was written to the durable log, for per-device throttling.
    private var lastLoggedAt: [String: Date] = [:]
    /// Last time each device's advertisement was *classified*. Re-classifying a device
    /// seen milliseconds ago is wasted work — a burst of packets from one device only
    /// needs its RSSI folded in.
    private var lastClassifiedAt: [String: Date] = [:]
    /// Peripheral keys we have already alerted on this session.
    private var alertedKeys: Set<String> = []
    /// The flagged-item payload of the last snapshot we wrote, to suppress no-op writes.
    private var lastSnapshotItems: [DashboardSnapshot.Item] = []
    private var lastSnapshotAt: Date = .distantPast

    // MARK: - Tuning

    /// A device unseen for this long drops off the Dashboard. Wide enough to ride out
    /// a few missed advertisement intervals without the list flickering.
    private let staleInterval: TimeInterval = 20
    /// How often the display loop publishes and prunes.
    private let displayInterval: Duration = .milliseconds(500)
    /// Minimum gap between snapshot writes / durable-log writes for one device.
    private let throttleInterval: TimeInterval = 1

    private var displayLoop: Task<Void, Never>?

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
    /// relaunch can restore into it, and starts listening for a pause toggle sent
    /// from the Live Activity's "Stop" button (a cross-process Darwin notification).
    func bootstrap() {
        scanner.bootstrap()
        // The Live Activity's "Stop" button runs in this process but on the App
        // Intents path; it writes the pref and posts a Darwin notification so we pick
        // the change up whether we are foreground or background.
        ScanControlBridge.startObserving { [weak self] in
            Task { @MainActor in self?.syncPauseFromDefaults() }
        }
    }

    /// Releases the scanner and every task/observer. The coordinator is app-lifetime
    /// today, so this is belt-and-braces against a future where it can be recreated
    /// (Distinguished Engineer review DE-5).
    func teardown() {
        displayLoop?.cancel(); displayLoop = nil
        ScanControlBridge.stopObserving()
        scanner.teardown()
    }

    func startScanning() {
        guard !isPaused else { return }
        let background = SharedContainer.defaults.bool(forKey: SharedContainer.Key.backgroundScanning)
            && SharedContainer.isUnlocked
        scanner.startScanning(background: background)
        if background { activity.startIfPossible() }
        ensureDisplayLoop()
        writeSnapshot(force: true)
    }

    func stopScanning() {
        scanner.stopScanning()
        activity.end()
        writeSnapshot(force: true)
    }

    /// The Dashboard / Live Activity "pause scanning" switch.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        SharedContainer.defaults.set(paused, forKey: SharedContainer.Key.scanningPaused)
        if paused {
            scanner.stopScanning()
            activity.end()
            working.removeAll()
            live.removeAll()
            flags.removeAll(); weakSignals.removeAll(); displayGlasses.removeAll()
            headsets.removeAll(); allInRange.removeAll()
            displayLoop?.cancel(); displayLoop = nil
            writeSnapshot(force: true)
        } else {
            startScanning()
        }
    }

    private func syncPauseFromDefaults() {
        let stored = SharedContainer.defaults.bool(forKey: SharedContainer.Key.scanningPaused)
        if stored != isPaused { setPaused(stored) }
    }

    /// Foreground/background transition from the scene phase.
    func applyScenePhase(active: Bool) {
        mine.reload()
        syncPauseFromDefaults()
        guard !isPaused else { scanner.stopScanning(); activity.end(); return }

        if active {
            scanner.startScanning(background: false)
            ensureDisplayLoop()
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
        writeSnapshot(force: true)
    }

    // MARK: - Ingest (hot path — keep it cheap)

    /// Sub-second burst of packets from one device — fold in RSSI, skip re-classifying.
    private let reclassifyInterval: TimeInterval = 0.3

    private func ingest(_ event: ScanEvent) {
        guard !isPaused else { return }
        lastEventAt = event.timestamp
        let key = event.peripheralKey

        // Cheap fast-path: same device seen a moment ago. Its classification will not
        // have changed; just keep the smoother and liveness current.
        if var existing = working[key],
           event.timestamp.timeIntervalSince(lastClassifiedAt[key] ?? .distantPast) < reclassifyInterval {
            existing.smoother.add(event.rssi)
            existing.lastSeen = event.timestamp
            existing.lastAdvertisement = event.advertisement
            working[key] = existing
            workingDirty = true
            return
        }
        lastClassifiedAt[key] = event.timestamp

        let detection = DetectionEngine.classify(event.advertisement)
        let previousTier: DetectionTier?

        if var existing = working[key] {
            previousTier = existing.detection.bestTier
            existing.smoother.add(event.rssi)
            existing.detection = existing.detection.merged(with: detection)
            existing.lastSeen = event.timestamp
            existing.lastAdvertisement = event.advertisement
            existing.isMine = mine.contains(productKey: existing.detection.productKey)
            working[key] = existing
        } else {
            previousTier = nil
            var smoother = RSSISmoother(initialRSSI: event.rssi)
            smoother.add(event.rssi)
            working[key] = LiveSighting(
                peripheralKey: key,
                detection: detection,
                smoother: smoother,
                firstSeen: event.timestamp,
                lastSeen: event.timestamp,
                isMine: mine.contains(productKey: detection.productKey),
                lastAdvertisement: event.advertisement
            )
        }

        guard let current = working[key] else { return }

        // Persist on a first sighting or a tier upgrade immediately; otherwise at
        // most once a second per device.
        let upgraded = (current.detection.bestTier ?? .name) > (previousTier ?? .name)
        let firstSighting = lastLoggedAt[key] == nil
        let throttleElapsed = event.timestamp.timeIntervalSince(
            lastLoggedAt[key] ?? .distantPast
        ) >= throttleInterval

        // Only recognised camera / display glasses are logged. Headsets and the
        // anonymous devices we also hear stay in the live view only.
        if current.detection.category.isGlasses, firstSighting || upgraded || throttleElapsed {
            lastLoggedAt[key] = event.timestamp
            let record = sightings.record(
                peripheralKey: key,
                detection: current.detection,
                rssi: event.rssi,
                proximity: current.proximity,
                at: event.timestamp
            )
            maybeAlert(for: record, key: key, isMine: current.isMine)
        }

        workingDirty = true
        ensureDisplayLoop()
    }

    /// Background notification gate — Tier 1 / Tier 2 camera detections only. A bare
    /// name match (Tier 3) is logged and badged in-app but never interrupts.
    private func maybeAlert(for record: Sighting, key: String, isMine: Bool) {
        guard !isMine,
              record.detection.canNotifyInBackground,
              !alertedKeys.contains(key),
              SharedContainer.defaults.bool(forKey: SharedContainer.Key.alertsEnabled),
              SharedContainer.isUnlocked,
              !SharedContainer.quietHours.isActive()
        else { return }
        alertedKeys.insert(key)
        onNewFlag?(record)
    }

    // MARK: - Display loop (publish + prune + snapshot)

    private func ensureDisplayLoop() {
        guard displayLoop == nil else { return }
        displayLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.displayInterval ?? .milliseconds(500))
                guard let self else { return }
                let keepRunning = self.tick()
                if !keepRunning { self.displayLoop = nil; return }
            }
        }
    }

    /// One pass. Returns whether the loop should keep spinning.
    @discardableResult
    private func tick() -> Bool {
        let now = Date()
        let fresh = working.filter { now.timeIntervalSince($0.value.lastSeen) < staleInterval }
        if fresh.count != working.count {
            working = fresh
            lastLoggedAt = lastLoggedAt.filter { working[$0.key] != nil }
            lastClassifiedAt = lastClassifiedAt.filter { working[$0.key] != nil }
            alertedKeys = alertedKeys.filter { working[$0] != nil }
            workingDirty = true
        }

        // Nothing has changed since the last publish — skip the recomputation, but
        // still let a snapshot that was throttled a moment ago flush.
        guard workingDirty else {
            writeSnapshot(force: false)
            return !working.isEmpty || state == .scanning
        }
        workingDirty = false

        if working != live { live = working }

        let cameraFlags = working.values.filter { $0.isCameraFlag && !$0.isMine }
        let nextFlags = cameraFlags
            .filter { ($0.tier ?? .name) >= .serviceUUID }
            .sorted(by: Self.rank)
        let nextWeak = cameraFlags
            .filter { ($0.tier ?? .name) == .name }
            .sorted(by: Self.rank)
        let nextDisplay = working.values
            .filter { $0.isDisplayGlasses && !$0.isMine }
            .sorted(by: Self.rank)
        let nextHeadsets = working.values
            .filter { $0.detection.isHeadset && !$0.isMine }
            .sorted(by: Self.rank)
        let nextAll = working.values.sorted { $0.lastSeen > $1.lastSeen }

        if nextFlags != flags { flags = nextFlags }
        if nextWeak != weakSignals { weakSignals = nextWeak }
        if nextDisplay != displayGlasses { displayGlasses = nextDisplay }
        if nextHeadsets != headsets { headsets = nextHeadsets }
        if nextAll != allInRange { allInRange = nextAll }

        writeSnapshot(force: false)

        return !working.isEmpty || state == .scanning
    }

    private static func rank(_ lhs: LiveSighting, _ rhs: LiveSighting) -> Bool {
        if lhs.tier != rhs.tier {
            return (lhs.tier ?? .name) > (rhs.tier ?? .name)
        }
        return lhs.proximity > rhs.proximity
    }

    // MARK: - Shared snapshot

    private func writeSnapshot(force: Bool) {
        let items = flags.prefix(5).map { flag in
            DashboardSnapshot.Item(
                id: flag.peripheralKey,
                productName: flag.title,
                tier: flag.tier ?? .name,
                proximity: flag.proximity
            )
        }
        let itemsArray = Array(items)
        let changed = itemsArray != lastSnapshotItems
        let elapsed = Date().timeIntervalSince(lastSnapshotAt) >= throttleInterval

        guard force || (changed && elapsed) else { return }

        lastSnapshotItems = itemsArray
        lastSnapshotAt = Date()

        let snapshot = DashboardSnapshot(
            updatedAt: Date(),
            isScanning: isScanning,
            flagged: itemsArray
        )
        snapshot.save()
        activity.update(with: snapshot)
        if changed || force {
            WidgetCenter.shared.reloadTimelines(ofKind: SharedContainer.widgetKind)
        }
        // Relay-only: never a second scan. Rides this same ≤1Hz debounced write —
        // no new timer, no watch-side scanning (Unlock feature).
        WatchRelay.shared.send(snapshot)
    }
}
