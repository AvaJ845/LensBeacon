import WidgetKit
import SwiftUI

/// The extension bundles the Home Screen widget and the scan Live Activity. Both are
/// read-only mirrors of `DashboardSnapshot` — the extension runs no Bluetooth scan of
/// its own and makes no network call (there is none to make).
@main
struct LensBeaconWidgetBundle: WidgetBundle {
    var body: some Widget {
        NearbyLensesWidget()
        ScanLiveActivity()
    }
}
