final class TestClock: Clock, Sendable {
    typealias Duration = Swift.Duration
    typealias Instant = ContinuousClock.Instant

    private(set) nonisolated(unsafe) var now: Instant

    init(now: Instant = ContinuousClock.now) {
        self.now = now
    }

    func advance(by duration: Duration) {
        self.now = self.now.advanced(by: duration)
    }

    var minimumResolution: Duration {
        .nanoseconds(1)
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
    }
}
