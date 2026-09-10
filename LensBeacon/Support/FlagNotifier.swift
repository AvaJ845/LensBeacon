import Foundation
import UserNotifications
import os

/// Posts the single kind of local notification LensBeacon sends: "a likely/strong
/// camera-glasses flag appeared while you weren't looking" (an Unlock feature,
/// gated on the user turning alerts on).
///
/// - Local notifications only. No push, no server, no token.
/// - The body says *what matched*, never a made-up identity or location.
/// - Rate-limited by the coordinator (`alertedKeys`) so one device alerts once.
@MainActor
final class FlagNotifier: NSObject, UNUserNotificationCenterDelegate {

    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "notifier")

    private static let categoryID = "FLAG"
    private enum Action { static let mine = "MARK_MINE"; static let evidence = "SHOW_EVIDENCE" }

    /// Registers the flag-notification category and its two actions. Call once at
    /// launch, alongside setting the delegate.
    func registerCategories() {
        let mine = UNNotificationAction(identifier: Action.mine, title: "This is mine", options: [])
        let evidence = UNNotificationAction(identifier: Action.evidence, title: "Show evidence", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.categoryID, actions: [evidence, mine],
            intentIdentifiers: [], options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Requests permission the first time background alerts are switched on.
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    func notify(about sighting: Sighting) {
        let content = UNMutableNotificationContent()
        content.title = "\(sighting.title) nearby"
        content.body = sighting.evidence.first.map {
            "\($0.adType.label) matched: \($0.matchedValue) · \($0.tier.title). Tap to see the full evidence."
        } ?? "A device matching camera glasses is nearby."
        content.sound = .default
        content.interruptionLevel = .active   // not time-sensitive, not critical
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [
            "peripheralKey": sighting.peripheralKey,
            "productKey": sighting.productKey ?? "",
        ]

        let request = UNNotificationRequest(
            identifier: "flag-\(sighting.peripheralKey)",
            content: content,
            trigger: nil                       // deliver now
        )
        UNUserNotificationCenter.current().add(request) { [log] error in
            if let error { log.error("notify failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Route a tapped notification to the sightings tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let peripheralKey = info["peripheralKey"] as? String
        let productKey = (info["productKey"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let action = response.actionIdentifier
        Task { @MainActor in
            switch action {
            case Action.mine:
                Router.shared.pendingMineKey = productKey
            default:               // SHOW_EVIDENCE, default tap
                Router.shared.pendingSightingKey = peripheralKey
            }
        }
        completionHandler()
    }

    /// Show the banner even with the app foregrounded — the user asked to be told.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Minimal cross-cutting routing state for notification / widget / deep-link taps.
@MainActor
@Observable
final class Router {
    static let shared = Router()
    var pendingSightingKey: String?
    /// A device the user chose "This is mine" on from a notification action.
    var pendingMineKey: String?
    var selectedTab: RootView.Screen = .dashboard

    /// A screen to present once at launch. Set only by the `-screen <name>`
    /// launch argument (QA / App Store screenshot capture); never used in normal
    /// operation. Consumed and cleared by the presenting view.
    enum LaunchScreen: String { case settings, unlock, privacy, sightingDetail }
    var launchScreen: LaunchScreen?

    private init() {}

    /// Applies `-screen <name>` if present. `sightings` / `detail` also switch tab.
    func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let i = arguments.firstIndex(of: "-screen"), i + 1 < arguments.count else { return }
        switch arguments[i + 1] {
        case "sightings":     selectedTab = .sightings
        case "detail":        selectedTab = .sightings; launchScreen = .sightingDetail
        case "settings":      launchScreen = .settings
        case "unlock":        launchScreen = .unlock
        case "privacy":       launchScreen = .privacy
        default:              break
        }
    }
}
