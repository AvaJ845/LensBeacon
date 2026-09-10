import Testing

/// The RSSI smoother keeps the proximity band from strobing as CoreBluetooth
/// delivers several noisy readings a second. Untested before this pass.
struct RSSISmootherTests {

    @Test func convergesTowardSteadyInput() {
        var s = RSSISmoother(initialRSSI: -90)
        for _ in 0..<50 { s.add(-50) }
        #expect(s.value > -55)          // effectively settled at the input
        #expect(s.band == .near)
    }

    @Test func ignoresTheUnknownSentinelAndAbsurdValues() {
        var s = RSSISmoother(initialRSSI: -60)
        let before = s.value
        s.add(127)      // CoreBluetooth "no reading"
        s.add(0)        // not negative — meaningless
        s.add(-200)     // below the noise floor
        #expect(s.value == before)
    }

    @Test func bandThresholdsMatchTheDocumentedCutoffs() {
        #expect(ProximityBand.band(forSmoothedRSSI: -40) == .near)
        #expect(ProximityBand.band(forSmoothedRSSI: -55) == .near)
        #expect(ProximityBand.band(forSmoothedRSSI: -56) == .nearby)
        #expect(ProximityBand.band(forSmoothedRSSI: -75) == .nearby)
        #expect(ProximityBand.band(forSmoothedRSSI: -76) == .far)
    }

    @Test func aLightWindowStillTracksARealApproach() {
        var s = RSSISmoother(initialRSSI: -85)      // across the room
        for _ in 0..<10 { s.add(-45) }              // walked up close
        #expect(s.band == .near)
    }
}
