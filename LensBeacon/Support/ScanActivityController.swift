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

    /// A plain, fully main-actor-isolated property — every read and write happens on
    /// this actor, with the compiler actually enforcing that (unlike a
    /// `nonisolated(unsafe)` escape hatch). The only value that ever crosses off the
    /// actor is a `SendableActivity`-boxed copy, handed to a `Task` for the async
    /// `update`/`end` call and never read back.
    private var activity: Activity<ScanActivityAttributes>?
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
        guard let activity else { return }
        let state = ScanActivityAttributes.ContentState(
            flaggedCount: snapshot.flagged.count,
            strongestTier: snapshot.strongestTier,
            nearestBand: snapshot.nearestBand,
            updatedAt: snapshot.updatedAt
        )
        let boxed = SendableActivity(activity)
        Task { await boxed.value.update(.init(state: state, staleDate: Date().addingTimeInterval(120))) }
    }

    func end() {
        guard let activity else { return }
        // Cleared synchronously, on the main actor, before the async teardown
        // starts — a `startIfPossible()` that runs while the old activity is still
        // winding down must see `nil` and be free to request a new Live Activity
        // immediately, not wait on or race the previous one's teardown.
        self.activity = nil
        let boxed = SendableActivity(activity)
        Task { await boxed.value.end(nil, dismissalPolicy: .immediate) }
    }
}

/// `Activity` isn't `Sendable` in the SDK, but ActivityKit documents its instance
/// methods (`update`, `end`) as safe to call from any context — there is no shared
/// mutable state inside it for concurrent access to corrupt. This wrapper asserts
/// exactly that, once, in one place, so no property in this file needs its own
/// `nonisolated(unsafe)` escape hatch: the boxed value is handed off for a single
/// fire-and-forget async call and never read back from the isolated side.
private struct SendableActivity<Attributes: ActivityAttributes>: @unchecked Sendable {
    let value: Activity<Attributes>
    init(_ value: Activity<Attributes>) { self.value = value }
}
