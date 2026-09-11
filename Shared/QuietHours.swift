import Foundation

/// A daily time window in which new-flag alerts are muted (LensBeacon Unlock).
/// Deliberately **time-based only** — never a place. A location-aware "quiet at
/// home" would be a real feature almost anywhere else; here it would be the one
/// exception to "no location, ever," so it is not on the table.
struct QuietHours: Equatable, Sendable {
    /// Minutes since local midnight, 0...1439.
    var startMinutes: Int
    var endMinutes: Int
    var isEnabled: Bool

    static let disabled = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60, isEnabled: false)

    func isActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return Self.window(nowMinutes, start: startMinutes, end: endMinutes)
    }

    /// Pure so the midnight wraparound (e.g. 22:00–07:00) is trivially testable
    /// without waiting for the clock to actually cross it.
    static func window(_ minute: Int, start: Int, end: Int) -> Bool {
        guard start != end else { return false }   // zero-length window mutes nothing
        if start < end {
            return minute >= start && minute < end
        }
        return minute >= start || minute < end       // wraps past midnight
    }
}
