import Foundation
import ActivityKit

/// The Live Activity shown while a background scan is running (an Unlock feature).
///
/// Its whole job is to be a calm, honest status line on the Lock Screen and in the
/// Dynamic Island: "LensBeacon is scanning — N nearby". It is not an alarm. The
/// content state carries only counts and the strongest band, mirroring
/// `DashboardSnapshot`; no device identity ever reaches ActivityKit (whose payloads
/// can be delivered via push in other apps — LensBeacon never uses push, but the
/// data minimalism holds regardless).
struct ScanActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// Number of currently-flagged camera glasses, excluding "mine".
        var flaggedCount: Int
        /// Strongest confidence among them, if any.
        var strongestConfidence: ConfidenceLevel?
        /// Nearest proximity band among them, if any.
        var nearestBand: ProximityBand?
        /// Last time the app refreshed this state.
        var updatedAt: Date

        var headline: String {
            switch flaggedCount {
            case 0:  return "Nothing nearby"
            case 1:  return "1 nearby"
            default: return "\(flaggedCount) nearby"
            }
        }
    }

    /// Fixed for the life of the activity.
    var startedAt: Date
}
