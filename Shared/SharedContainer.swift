import Foundation

/// The one folder and preference suite the app, the widget and the Live Activity
/// all read.
///
/// Everything here is device-local. Keys are product-name-free so a rename never
/// forces a data migration. Nothing in this type performs, schedules, or varies a
/// network request — there is no network code anywhere in LensBeacon.
enum SharedContainer {

    static let appGroupID = "group.com.avaresearch.lensbeacon"

    enum Key {
        /// Whether the user has completed onboarding. Gates the first-run flow.
        static let onboarded = "didCompleteOnboarding"
        /// Non-consumable "LensBeacon Unlock" owned. Written by `UnlockStore` from the
        /// StoreKit entitlement; read by the widget and Live Activity, which cannot
        /// query StoreKit themselves, to decide whether to render real content or a
        /// locked placeholder.
        static let unlocked = "lensBeaconUnlockOwned"
        /// Stable local IDs the user has marked as "mine" — suppressed from alerts.
        /// A sorted `[String]` of the app's own opaque device keys, never a MAC.
        static let mineDeviceKeys = "mineDeviceKeys"
        /// User preference: keep scanning in the background (Unlock feature).
        static let backgroundScanning = "backgroundScanningEnabled"
        /// User preference: post a local notification when a new strong/likely flag
        /// appears while backgrounded (Unlock feature).
        static let alertsEnabled = "flagAlertsEnabled"
        /// Snapshot the widget/Live Activity render from — see `DashboardSnapshot`.
        static let dashboardSnapshot = "dashboardSnapshot"
    }

    /// App Group suite when the entitlement is honoured; otherwise the process
    /// defaults, so the app still runs in an unsigned simulator.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Where the Sightings log is persisted. Falls back to Application Support when
    /// the App Group container is unavailable (unsigned simulator).
    static var sightingsFileURL: URL {
        if let container = containerURL {
            return container.appendingPathComponent("sightings.json")
        }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sightings.json")
    }

    // MARK: - Small typed conveniences

    static var isUnlocked: Bool {
        get { defaults.bool(forKey: Key.unlocked) }
        set { defaults.set(newValue, forKey: Key.unlocked) }
    }

    static var didCompleteOnboarding: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }
}
