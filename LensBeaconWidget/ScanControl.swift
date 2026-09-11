import WidgetKit
import SwiftUI
import AppIntents

/// A Control Center / Lock Screen control (iOS 18) that opens LensBeacon and starts a
/// scan. A one-purpose utility like this is exactly what controls are for — the
/// fastest possible "is there a camera near me right now?" from anywhere in the OS.
struct ScanControl: ControlWidget {
    static let kind = "com.avaresearch.lensbeacon.scanControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartScanIntent()) {
                Label("Scan for camera glasses", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .displayName("Scan for camera glasses")
        .description("Open LensBeacon and start listening for nearby camera-glasses signatures.")
    }
}
