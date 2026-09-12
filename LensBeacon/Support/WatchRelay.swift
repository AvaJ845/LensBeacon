import Foundation
import WatchConnectivity
import os

/// Relays the same `DashboardSnapshot` already written for the Home Screen widget
/// to a paired Apple Watch's complication (LensBeacon Unlock). This is a relay,
/// never a second scanner: the watch never scans on its own to feed this, so it
/// costs nothing beyond a snapshot the phone already produces for the widget.
///
/// `updateApplicationContext` — not `sendMessage` or `transferUserInfo` — is the
/// deliberate choice: it's OS-coalesced and latest-value-wins, and it never queues
/// or retries if the watch is unreachable. That matches this data exactly, since
/// only the current state is ever meaningful, never a history of past ones.
@MainActor
final class WatchRelay: NSObject {
    static let shared = WatchRelay()

    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "watch-relay")
    private var didActivate = false
    /// `WCSession.activate()` is always asynchronous — activation is never
    /// complete by the time it returns, only by the time the delegate's
    /// `activationDidCompleteWith` fires. Without this, the very first `send`
    /// after a cold launch would check `activationState` a moment too early,
    /// find it not yet `.activated`, and silently drop that snapshot. This holds
    /// just the latest one until activation actually completes.
    private var pendingSnapshot: DashboardSnapshot?

    private override init() { super.init() }

    func send(_ snapshot: DashboardSnapshot) {
        guard SharedContainer.isUnlocked, WCSession.isSupported() else { return }

        let session = WCSession.default
        if !didActivate {
            session.delegate = self
            session.activate()
            didActivate = true
        }
        guard session.activationState == .activated else {
            pendingSnapshot = snapshot
            return
        }
        transmit(snapshot, via: session)
    }

    private func transmit(_ snapshot: DashboardSnapshot, via session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        guard let data = try? JSONEncoder.iso.encode(snapshot) else { return }

        do {
            try session.updateApplicationContext(["dashboardSnapshot": data])
        } catch {
            log.debug("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchRelay: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in
            guard let pending = self.pendingSnapshot else { return }
            self.pendingSnapshot = nil
            self.transmit(pending, via: WCSession.default)
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
