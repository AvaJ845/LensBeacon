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

    init(context: ModelContext = ModelContext(HarnessStore.container)) {
        self.context = context
        scanner.onStateChange = { [weak self] state in self?.state = state }
        scanner.onPacket = { [weak self] packet in self?.ingest(packet) }
    }

    func start() { scanner.start() }
    func stop() { scanner.stop() }

    func startSession(environment: HarnessEnvironment, notes: String, deviceStates: [DeviceState]) {
        let session = HarnessSession(environment: environment)
        session.notes = notes
        for state in deviceStates { state.session = session }
        session.deviceStates = deviceStates
        context.insert(session)
        try? context.save()
        activeSession = session
        packetCount = 0
        uniquePeripheralCount = 0
        seenPeripherals.removeAll()
    }

    func endSession() {
        activeSession?.endedAt = Date()
        try? context.save()
        activeSession = nil
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
        packetCount += 1
        if seenPeripherals.insert(packet.peripheralID).inserted { uniquePeripheralCount += 1 }
        scheduleSave()
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
