import AppIntents
import Foundation

/// App Intents that start or stop scanning from *outside* the app's own UI — the
/// Live Activity's "Stop" button, a Control Center control, the Action button, Siri.
///
/// They never do Bluetooth work themselves. Each one writes the shared
/// `scanningPaused` preference and posts a Darwin notification; the running app (or
/// the app on next launch) reads the flag and starts or stops the radio. Turning
/// scanning back *on* opens the app, because a foreground scan needs the app process
/// and background scanning is an opt-in Unlock feature.

/// Stop scanning. Safe to run while the app is backgrounded — no app launch.
struct PauseScanIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop scanning for camera glasses"
    static let description = IntentDescription("Stops LensBeacon listening for nearby camera-glasses signatures.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        SharedContainer.defaults.set(true, forKey: SharedContainer.Key.scanningPaused)
        ScanControlBridge.postChanged()
        return .result()
    }
}

/// Start scanning. Opens LensBeacon, which begins an on-device scan immediately.
struct StartScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan for camera glasses"
    static let description = IntentDescription("Opens LensBeacon and starts listening for nearby camera-glasses signatures.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedContainer.defaults.set(false, forKey: SharedContainer.Key.scanningPaused)
        ScanControlBridge.postChanged()
        return .result()
    }
}
