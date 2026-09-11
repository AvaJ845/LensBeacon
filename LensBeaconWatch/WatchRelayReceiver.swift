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

    private func store(_ context: [String: Any]) {
        guard let data = context["dashboardSnapshot"] as? Data,
              let snapshot = try? JSONDecoder.iso.decode(DashboardSnapshot.self, from: data)
        else { return }
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

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.store(applicationContext) }
    }
}
