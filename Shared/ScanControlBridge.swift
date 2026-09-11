import Foundation

/// A one-bit cross-process signal: "the scanning-paused preference just changed."
///
/// The Live Activity's "Stop" button and the Control Center control run as App
/// Intents, sometimes in a helper process, sometimes in the app while it is
/// backgrounded. They write `SharedContainer.Key.scanningPaused` and then post this
/// Darwin notification so the running app re-reads the flag and starts or stops the
/// radio immediately instead of waiting for the next scene activation.
///
/// No payload ever crosses — only the fact that *something* changed. The receiver
/// reads the actual value from the shared defaults.
enum ScanControlBridge {

    private static let rawName = "com.avaresearch.lensbeacon.scanControlChanged"

    /// Retained for the lifetime of the observer. Set once from the main actor at
    /// bootstrap; a race here is not reachable in practice.
    nonisolated(unsafe) private static var handler: (() -> Void)?

    static func startObserving(_ onChange: @escaping () -> Void) {
        handler = onChange
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            nil,
            { _, _, _, _, _ in ScanControlBridge.handler?() },
            rawName as CFString,
            nil,
            .deliverImmediately
        )
    }

    static func stopObserving() {
        handler = nil
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            CFNotificationName(rawName as CFString),
            nil
        )
    }

    /// Call *after* writing the new value to `SharedContainer.defaults`.
    static func postChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawName as CFString),
            nil,
            nil,
            true
        )
    }
}
