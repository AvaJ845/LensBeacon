import Testing
import Foundation

/// `ActivationSignal.isLikelyCliff` is a hypothesis, not a confirmation — these
/// pin the one distinction that actually matters (held strong then vanished, vs
/// already fading before it vanished) and the two guards against noise (too few
/// samples, too short a window).
struct ActivationSignalTests {

    @Test func heldStrongThenGoneIsACliff() {
        let history = [-52.0, -50.0, -55.0, -51.0, -53.0, -50.0]
        #expect(ActivationSignal.isLikelyCliff(history: history, sampleInterval: 0.5))
    }

    @Test func gradualDeclineIntoFarIsNotACliff() {
        // Fading through the bands before it actually stops being seen — a
        // walk-away, not a "just connected" moment.
        let history = [-55.0, -62.0, -70.0, -78.0, -85.0, -90.0]
        #expect(!ActivationSignal.isLikelyCliff(history: history, sampleInterval: 0.5))
    }

    @Test func tooFewSamplesNeverCounts() {
        let history = [-50.0, -51.0, -52.0]
        #expect(!ActivationSignal.isLikelyCliff(history: history, sampleInterval: 0.5, minSamples: 6))
    }

    @Test func tooShortAWindowNeverCounts() {
        // 6 samples at a fast interval that doesn't add up to minDuration.
        let history = Array(repeating: -50.0, count: 6)
        #expect(!ActivationSignal.isLikelyCliff(
            history: history, sampleInterval: 0.1, minDuration: 3
        ))
    }

    @Test func thresholdIsInclusive() {
        let history = Array(repeating: -60.0, count: 6)
        #expect(ActivationSignal.isLikelyCliff(history: history, sampleInterval: 0.5, strongThreshold: -60))
    }

    @Test func oneWeakSampleInTheRecentWindowBreaksTheCliff() {
        var history = Array(repeating: -50.0, count: 5)
        history.append(-80.0) // the very last reading before it vanished was weak
        #expect(!ActivationSignal.isLikelyCliff(history: history, sampleInterval: 0.5))
    }
}
