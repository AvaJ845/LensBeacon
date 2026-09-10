import Testing
import Foundation

struct ProximityBandTests {

    @Test func bandThresholds() {
        #expect(ProximityBand.band(forSmoothedRSSI: -40) == .near)
        #expect(ProximityBand.band(forSmoothedRSSI: -55) == .near)
        #expect(ProximityBand.band(forSmoothedRSSI: -56) == .nearby)
        #expect(ProximityBand.band(forSmoothedRSSI: -75) == .nearby)
        #expect(ProximityBand.band(forSmoothedRSSI: -76) == .far)
        #expect(ProximityBand.band(forSmoothedRSSI: -95) == .far)
    }

    @Test func smootherIgnoresSentinelValues() {
        var s = RSSISmoother(initialRSSI: -60)
        s.add(127)      // CoreBluetooth "no reading"
        s.add(0)
        s.add(-200)
        #expect(s.value == -60)
    }

    @Test func smootherConvergesTowardSteadySignal() {
        var s = RSSISmoother(initialRSSI: -80, alpha: 0.5)
        for _ in 0..<10 { s.add(-50) }
        #expect(abs(s.value - (-50)) < 1)   // converged close to -50
        #expect(s.band == .near)
    }

    @Test func smootherResistsASingleSpike() {
        var s = RSSISmoother(initialRSSI: -70, alpha: 0.25)
        s.add(-40)      // one close blip
        // One sample must not jump the band from nearby to near.
        #expect(s.band == .nearby)
    }
}
