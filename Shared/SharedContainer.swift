import Foundation
import os

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
        /// User has switched scanning off from the Dashboard or the Live Activity's
        /// "Stop" button. Honoured across scene changes and relaunches.
        static let scanningPaused = "scanningPaused"
        /// Appearance override — "system" / "light" / "dark".
        static let appearance = "appAppearance"
        /// Quiet hours (Unlock feature) — mute new-flag alerts on a daily schedule.
        /// Time-based only; see `QuietHours`.
        static let quietHoursEnabled = "quietHoursEnabled"
        static let quietHoursStartMinutes = "quietHoursStartMinutes"
        static let quietHoursEndMinutes = "quietHoursEndMinutes"
        /// Minimum `ProximityBand` a flag must reach before it may raise a
        /// background alert (Unlock feature) — a `ProximityBand.rawValue`.
        /// Absent (and `.far`, the permissive default) means "alert at any
        /// distance," identical to behaviour before this setting existed, so
        /// nobody's alerts change just from updating the app.
        static let alertMinProximityBand = "alertMinProximityBand"
    }

    /// WidgetKit kind for the Home Screen widget. Shared so the app can target it in
    /// `WidgetCenter.reloadTimelines` without importing the extension.
    static let widgetKind = "NearbyLenses"

    private static let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "container")
    /// Best-effort one-shot log guard; a race only costs a duplicate log line.
    nonisolated(unsafe) private static var didWarnAboutFallback = false

    /// App Group suite when the entitlement is honoured; otherwise the process
    /// defaults, so the app still runs in an unsigned simulator. A fallback in a
    /// *signed* build means the app and its extensions are reading different stores —
    /// that must not pass silently, so it is logged once.
    static var defaults: UserDefaults {
        if let suite = UserDefaults(suiteName: appGroupID) { return suite }
        if !didWarnAboutFallback {
            didWarnAboutFallback = true
            log.error("App Group \(appGroupID, privacy: .public) unavailable — falling back to standard defaults. Widget/Live Activity will not see app data.")
        }
        return .standard
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

    static var quietHours: QuietHours {
        get {
            let d = defaults
            guard d.object(forKey: Key.quietHoursStartMinutes) != nil else { return .disabled }
            return QuietHours(
                startMinutes: d.integer(forKey: Key.quietHoursStartMinutes),
                endMinutes: d.integer(forKey: Key.quietHoursEndMinutes),
                isEnabled: d.bool(forKey: Key.quietHoursEnabled)
            )
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Key.quietHoursEnabled)
            defaults.set(newValue.startMinutes, forKey: Key.quietHoursStartMinutes)
            defaults.set(newValue.endMinutes, forKey: Key.quietHoursEndMinutes)
        }
    }

    /// A band, never a distance — matching `ProximityBand`'s own rule against
    /// showing a number of metres. `.far` (the permissive default) means every
    /// flag is alert-eligible regardless of signal strength, same as before
    /// this setting existed.
    static var alertMinProximity: ProximityBand {
        get {
            guard let raw = defaults.object(forKey: Key.alertMinProximityBand) as? Int,
                  let band = ProximityBand(rawValue: raw)
            else { return .far }
            return band
        }
        set { defaults.set(newValue.rawValue, forKey: Key.alertMinProximityBand) }
    }
}
