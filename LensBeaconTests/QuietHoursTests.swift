import Testing
import Foundation

/// Quiet hours is time-only muting for new-flag alerts. The one subtle bit —
/// windows that wrap past midnight — gets its own coverage; everything else
/// about it is a straight comparison.
struct QuietHoursTests {

    @Test func disabledNeverActive() {
        let q = QuietHours(startMinutes: 0, endMinutes: 1439, isEnabled: false)
        #expect(!q.window(atMinute: 0))
    }

    @Test func sameDayWindow() {
        // 09:00–17:00
        #expect(!QuietHours.window(480, start: 540, end: 1020))   // 08:00, before
        #expect(QuietHours.window(600, start: 540, end: 1020))    // 10:00, inside
        #expect(!QuietHours.window(1020, start: 540, end: 1020))  // 17:00, end is exclusive
    }

    @Test func overnightWraparoundWindow() {
        // 22:00–07:00
        #expect(QuietHours.window(23 * 60, start: 22 * 60, end: 7 * 60))   // 23:00
        #expect(QuietHours.window(0, start: 22 * 60, end: 7 * 60))         // 00:00
        #expect(QuietHours.window(6 * 60 + 59, start: 22 * 60, end: 7 * 60)) // 06:59
        #expect(!QuietHours.window(7 * 60, start: 22 * 60, end: 7 * 60))   // 07:00, end is exclusive
        #expect(!QuietHours.window(12 * 60, start: 22 * 60, end: 7 * 60))  // noon, well outside
    }

    @Test func zeroLengthWindowNeverMutes() {
        #expect(!QuietHours.window(500, start: 500, end: 500))
    }

    @Test func isActiveRespectsTheEnabledFlagAtAGivenInstant() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 1; comps.hour = 23; comps.minute = 0
        let elevenPM = Calendar.current.date(from: comps)!

        let enabled = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60, isEnabled: true)
        #expect(enabled.isActive(at: elevenPM))

        let disabled = QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60, isEnabled: false)
        #expect(!disabled.isActive(at: elevenPM))
    }
}

private extension QuietHours {
    /// Test-only convenience so `disabledNeverActive` reads naturally.
    func window(atMinute minute: Int) -> Bool {
        isEnabled && Self.window(minute, start: startMinutes, end: endMinutes)
    }
}
