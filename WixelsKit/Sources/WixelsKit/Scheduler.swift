import Foundation

/// One shared scheduler for every widget. Interval widgets are coalesced onto one
/// base loop; idle-static widgets tick once at startup and on explicit refreshes.
@MainActor
public final class Scheduler {
    private struct Periodic {
        let ticker: any WidgetTicker
        let period: TimeInterval
        var last: Date
    }

    private var periodics: [Periodic] = []
    private var once: [any WidgetTicker] = []
    private var loop: Task<Void, Never>?
    private let loopInterval: Duration

    public init(loopInterval: Duration = .seconds(1)) {
        self.loopInterval = loopInterval
    }

    public func add(_ ticker: any WidgetTicker) {
        switch ticker.refresh {
        case .interval(let period):
            periodics.append(.init(ticker: ticker, period: period, last: .distantPast))
        case .idleStatic:
            once.append(ticker)
        }
    }

    /// Re-tick active idle-static widgets, for example after a palette change.
    public func refreshOnce() {
        for ticker in once where ticker.active {
            Task { await ticker.tick() }
        }
    }

    public func start() {
        guard loop == nil else { return }
        for ticker in once where ticker.active {
            Task { await ticker.tick() }
        }
        guard !periodics.isEmpty else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                guard let self else { return }
                for index in self.periodics.indices where
                    self.periodics[index].ticker.active &&
                    now.timeIntervalSince(self.periodics[index].last) >= self.periodics[index].period {
                    self.periodics[index].last = now
                    await self.periodics[index].ticker.tick()
                }
                try? await Task.sleep(for: self.loopInterval)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    deinit { loop?.cancel() }
}
