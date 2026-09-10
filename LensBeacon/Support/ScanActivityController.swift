import Foundation
import ActivityKit
import os

/// Starts, updates and ends the "LensBeacon is scanning" Live Activity.
///
/// The Live Activity is a *status* surface, not an alert: it exists so that a
/// background scan is always visible and dismissible from the Lock Screen, which is
/// both good citizenship and what App Review expects from a background-Bluetooth
/// app. All updates are local (`activity.update`) — LensBeacon holds no push token
/// and starts no push channel.
@MainActor
final class ScanActivityController {

    // `Activity` is not `Sendable` and its mutating methods are `nonisolated async`,
    // so the region checker flags passing it into the detached update Task. In
    // practice ActivityKit is safe to drive from any context, and every access here
    // is already funnelled through this `@MainActor` type, so we opt this one
    // reference out of isolation checking rather than contort the call sites.
    private nonisolated(unsafe) var activity: Activity<ScanActivityAttributes>?
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "liveactivity")

    var isActive: Bool { activity != nil }

    func startIfPossible() {
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.debug("Live Activities disabled by user")
            return
        }
        let attributes = ScanActivityAttributes(startedAt: Date())
        let initial = ScanActivityAttributes.ContentState(
            flaggedCount: 0, strongestTier: nil, nearestBand: nil, updatedAt: Date()
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initial, staleDate: nil),
                pushType: nil            // explicitly no push
            )
        } catch {
            log.error("Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether a Live Activity we started is still live (not ended by the user or the
    /// system). Lets the coordinator notice a swipe-dismiss and reconcile.
    var isRunning: Bool {
        guard let activity else { return false }
        return activity.activityState == .active || activity.activityState == .stale
    }

    func update(with snapshot: DashboardSnapshot) {
        guard activity != nil else { return }
        let state = ScanActivityAttributes.ContentState(
            flaggedCount: snapshot.flagged.count,
            strongestTier: snapshot.strongestTier,
            nearestBand: snapshot.nearestBand,
            updatedAt: snapshot.updatedAt
        )
        // The ActivityKit call happens in a `nonisolated` context (`pushUpdate`), so
        // the non-`Sendable` `Activity` never crosses an isolation boundary. Only the
        // `Sendable` content state does.
        Task { await pushUpdate(state) }
    }

    func end() {
        guard activity != nil else { return }
        Task { await pushEnd() }
    }

    private nonisolated func pushUpdate(_ state: ScanActivityAttributes.ContentState) async {
        guard let activity else { return }
        await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(120)))
    }

    private nonisolated func pushEnd() async {
        guard let activity else { return }
        self.activity = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
