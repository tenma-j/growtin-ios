import Foundation
import Observation
import UIKit

/// Minuteur de séance, basé sur l'heure réelle : si l'app passe en arrière-plan ou que le téléphone se verrouille,
/// le temps continue de s'écouler et l'affichage se recale au retour. Pendant une séance en cours, l'écran ne se met
/// pas en veille.
@MainActor
@Observable
final class SessionClock {
    enum State: Equatable { case idle, running, paused, finished }

    let totalSeconds: Int
    private(set) var elapsed = 0
    private(set) var state: State = .idle {
        didSet { UIApplication.shared.isIdleTimerDisabled = state == .running }
    }
    /// Secondes déjà écoulées avant la reprise en cours, et heure de cette reprise.
    private var banked: TimeInterval = 0
    private var resumedAt: Date?
    private var task: Task<Void, Never>?
    private var foreground: NSObjectProtocol?
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
        resumedAt = Date()
        state = .running
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, self.state == .running else { return }
                self.refresh()
            }
        }
        if foreground == nil {
            foreground = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        refresh()
        banked += resumedAt.map { Date().timeIntervalSince($0) } ?? 0
        resumedAt = nil
        state = .paused
        task?.cancel()
    }

    func stop() {
        task?.cancel()
        task = nil
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
        foreground = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Recale le temps écoulé sur l'heure réelle.
    func refresh(now: Date = Date()) {
        guard state == .running else { return }
        let seconds = banked + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
        let value = min(Int(seconds), totalSeconds)
        if value != elapsed { elapsed = value }
        if elapsed >= totalSeconds {
            state = .finished
            task?.cancel()
            onFinish?()
        }
    }
}
