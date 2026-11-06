import Foundation
import Observation

/// Minuteur de séance, testable, basé sur Swift Concurrency.
@MainActor
@Observable
final class SessionClock {
    enum State: Equatable { case idle, running, paused, finished }

    let totalSeconds: Int
    private(set) var elapsed = 0
    private(set) var state: State = .idle
    private var task: Task<Void, Never>?
    var onFinish: (() -> Void)?

    init(totalSeconds: Int) {
        self.totalSeconds = max(1, totalSeconds)
    }

    var remaining: Int { totalSeconds - elapsed }
    var fraction: Double { Double(elapsed) / Double(totalSeconds) }

    var remainingLabel: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    func start() {
        guard state != .running, state != .finished else { return }
        state = .running
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.state == .running else { return }
                self.tick()
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        task?.cancel()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func tick() {
        guard state == .running else { return }
        elapsed = min(elapsed + 1, totalSeconds)
        if elapsed >= totalSeconds {
            state = .finished
            task?.cancel()
            onFinish?()
        }
    }
}
