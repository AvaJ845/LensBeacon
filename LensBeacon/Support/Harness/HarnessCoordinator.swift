#if DEBUG
import Foundation
import Observation
import SwiftData

/// The one object the harness UI talks to. Owns the promiscuous scanner and the
/// active tagged session, and persists every packet while a session is open —
/// nothing is captured before a session starts, since an untagged packet log
/// has no ground truth and is exactly the "uninterpretable" case `HARNESS.md`
/// warns about.
@MainActor
@Observable
final class HarnessCoordinator {
    private(set) var state: HarnessScanner.State = .idle
    private(set) var packetCount = 0
    private(set) var uniquePeripheralCount = 0
    private(set) var activeSession: HarnessSession?

    private let scanner = HarnessScanner()
    private let context: ModelContext
    private var seenPeripherals: Set<String> = []
    private var saveScheduled = false

    // `packetCount`/`uniquePeripheralCount` above are `@Observable` — updating
    // them straight from `ingest()` (called on every single BLE packet, tens
    // of times a second in a busy promiscuous scan) forced a full SwiftUI
    // re-render on every packet and visibly stressed the main thread for the
    // whole session. Every other scanner in this app (`ScanCoordinator`,
    // `WatchScanModel`, `CaptureLog`) throttles its published state to a
    // ~500ms tick for exactly this reason; these two counters are updated the
    // same way now, from the cheap plain vars below.
    private var rawPacketCount = 0
    private var rawUniquePeripheralCount = 0
    private var displayTick: Task<Void, Never>?
    private let displayInterval: Duration = .milliseconds(500)

    init(context: ModelContext = ModelContext(HarnessStore.container)) {
        self.context = context
        scanner.onStateChange = { [weak self] state in self?.state = state }
        scanner.onPacket = { [weak self] packet in self?.ingest(packet) }
    }

    func start() { scanner.start() }
    func stop() { scanner.stop(); displayTick?.cancel(); displayTick = nil }

    func startSession(environment: HarnessEnvironment, notes: String, deviceStates: [DeviceState]) {
        let session = HarnessSession(environment: environment)
        session.notes = notes
        for state in deviceStates { state.session = session }
        session.deviceStates = deviceStates
        context.insert(session)
        try? context.save()
        activeSession = session
        rawPacketCount = 0
        rawUniquePeripheralCount = 0
        packetCount = 0
        uniquePeripheralCount = 0
        seenPeripherals.removeAll()
        ensureDisplayTick()
    }

    func endSession() {
        displayTick?.cancel()
        displayTick = nil
        // Flush the counters one last time so the final numbers shown (and
        // the session's persisted `packetCount`) reflect every packet, not
        // whatever the last 500ms tick happened to catch.
        packetCount = rawPacketCount
        uniquePeripheralCount = rawUniquePeripheralCount
        activeSession?.endedAt = Date()
        try? context.save()
        activeSession = nil
    }

    /// Records a momentary action against the running session, timestamped
    /// now. Rare and operator-triggered (a tap, not a packet), so this saves
    /// immediately rather than joining the debounced packet-save path —
    /// there's no volume concern, and losing an event to a crash before the
    /// next debounce window would defeat the point of marking it at all.
    func markEvent(_ kind: SessionEventKind) {
        guard let session = activeSession else { return }
        let event = SessionEvent(kind: kind)
        event.session = session
        context.insert(event)
        try? context.save()
    }

    private func ingest(_ packet: HarnessAdvertisement) {
        guard let session = activeSession else { return }
        let raw = RawPacket(
            timestamp: packet.timestamp, peripheralID: packet.peripheralID, rssi: packet.rssi,
            manufacturerDataHex: packet.manufacturerDataHex, companyID: packet.companyID,
            serviceUUIDs: packet.serviceUUIDs, localName: packet.localName,
            isConnectable: packet.isConnectable, txPower: packet.txPower
        )
        raw.session = session
        context.insert(raw)
        rawPacketCount += 1
        session.packetCount = rawPacketCount
        if seenPeripherals.insert(packet.peripheralID).inserted { rawUniquePeripheralCount += 1 }
        scheduleSave()
    }

    /// Copies the cheap plain counters into the `@Observable` properties the
    /// UI reads, at most twice a second — never directly from `ingest()`.
    private func ensureDisplayTick() {
        guard displayTick == nil else { return }
        displayTick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.displayInterval ?? .milliseconds(500))
                guard let self, self.activeSession != nil else { return }
                self.packetCount = self.rawPacketCount
                self.uniquePeripheralCount = self.rawUniquePeripheralCount
            }
        }
    }

    /// Debounced, like `SightingsStore.scheduleSave()` — a busy scan touches
    /// this many times a second, and tens of thousands of rows per session (per
    /// the harness spec) makes a save-per-insert a real bottleneck.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            self.saveScheduled = false
            try? self.context.save()
        }
    }
}
#endif
