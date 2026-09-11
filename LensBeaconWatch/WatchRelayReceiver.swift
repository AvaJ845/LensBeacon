import Foundation
import WatchConnectivity
import WidgetKit
import os

/// Receives the relayed `DashboardSnapshot` over WatchConnectivity and stores it
/// for the complication to read. See `LensBeacon/Support/WatchRelay.swift` on the
/// phone side for why `updateApplicationContext` is the right primitive here — this
/// side just has to store whatever arrives and ask the complication to redraw.
@MainActor
final class WatchRelayReceiver: NSObject {
    static let shared = WatchRelayReceiver()

    private let log = Logger(subsystem: "com.avaresearch.lensbeacon.watch", category: "watch-relay")

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func store(_ data: Data) {
        guard let snapshot = try? JSONDecoder.iso.decode(DashboardSnapshot.self, from: data) else { return }
        snapshot.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "LensBeaconComplication")
    }
}

extension WatchRelayReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error {
            log.debug("watch WCSession activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Extracts the one `Sendable` value (`Data`) before hopping to the main actor —
    /// `applicationContext` itself is `[String: Any]`, which strict concurrency
    /// correctly refuses to send across the actor boundary as a whole.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["dashboardSnapshot"] as? Data else { return }
        Task { @MainActor in self.store(data) }
    }
}
