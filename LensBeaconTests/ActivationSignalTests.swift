import Testing
import Foundation

/// `ActivationSignal.isLikelyCliff` is a hypothesis, not a confirmation — these
/// pin the one distinction that actually matters (held strong then vanished, vs
/// already fading before it vanished) and the guards against noise (too few
/// samples, too short a real-world window). Samples are timestamped rather than
/// assumed to be evenly spaced, since real advertisement packets aren't.
struct ActivationSignalTests {

    private func samples(_ rssi: [Double], startingAt start: Date = Date(), spacing: TimeInterval = 0.7) -> [ActivationSignal.Sample] {
        rssi.enumerated().map { i, v in
            ActivationSignal.Sample(rssi: v, at: start.addingTimeInterval(Double(i) * spacing))
        }
    }

    @Test func heldStrongThenGoneIsACliff() {
        let history = samples([-52, -50, -55, -51, -53, -50])
        #expect(ActivationSignal.isLikelyCliff(history: history))
    }

    @Test func gradualDeclineIntoFarIsNotACliff() {
        // Fading through the bands before it actually stops being seen — a
        // walk-away, not a "just connected" moment.
        let history = samples([-55, -62, -70, -78, -85, -90])
        #expect(!ActivationSignal.isLikelyCliff(history: history))
    }

    @Test func tooFewSamplesNeverCounts() {
        let history = samples([-50, -51, -52])
        #expect(!ActivationSignal.isLikelyCliff(history: history, minSamples: 6))
    }

    @Test func tooShortARealWorldWindowNeverCounts() {
        // 6 samples, but they all arrived within a fraction of a second — a burst
        // of packets, not a trend held over any meaningful duration.
        let history = samples(Array(repeating: -50, count: 6), spacing: 0.05)
        #expect(!ActivationSignal.isLikelyCliff(history: history, minDuration: 3))
    }

    @Test func irregularRealPacketTimingStillMeasuresActualElapsedTime() {
        // Six samples spanning well over minDuration, but arriving irregularly —
        // exactly what real advertisement packets look like. Duration comes from
        // the actual first/last timestamps, not an assumed fixed interval.
        let start = Date()
        let history = [
            ActivationSignal.Sample(rssi: -50, at: start),
            ActivationSignal.Sample(rssi: -52, at: start.addingTimeInterval(0.2)),
            ActivationSignal.Sample(rssi: -51, at: start.addingTimeInterval(0.9)),
            ActivationSignal.Sample(rssi: -53, at: start.addingTimeInterval(2.5)),
            ActivationSignal.Sample(rssi: -50, at: start.addingTimeInterval(3.1)),
            ActivationSignal.Sample(rssi: -52, at: start.addingTimeInterval(4.0)),
        ]
        #expect(ActivationSignal.isLikelyCliff(history: history, minDuration: 3))
    }

    @Test func thresholdIsInclusive() {
        let history = samples(Array(repeating: -60, count: 6))
        #expect(ActivationSignal.isLikelyCliff(history: history, strongThreshold: -60))
    }

    @Test func oneWeakSampleInTheRecentWindowBreaksTheCliff() {
        var rssi = Array(repeating: -50.0, count: 5)
        rssi.append(-80) // the very last reading before it vanished was weak
        #expect(!ActivationSignal.isLikelyCliff(history: samples(rssi)))
    }
}
