import Synchronization

final class TestClock: Clock, @unchecked Sendable {
    typealias Duration = Swift.Duration
    typealias Instant = ContinuousClock.Instant

    private let _now: Mutex<Instant>

    var now: Instant { _now.withLock { $0 } }

    init(now: Instant = ContinuousClock.now) {
        self._now = .init(now)
    }

    func advance(by duration: Duration) {
        _now.withLock { $0 = $0.advanced(by: duration) }
    }

    var minimumResolution: Duration { .nanoseconds(1) }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
    }
}
