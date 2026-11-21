import Foundation
import Observation
import UIKit
import UserNotifications

/// Minuteur de séance, basé sur l'heure réelle : si l'app passe en arrière-plan ou que le téléphone se verrouille,
/// le temps continue de s'écouler et l'affichage se recale au retour. Pendant une séance en cours, l'écran ne se met
/// pas en veille. Si le téléphone est verrouillé, une notification discrète (vibration, sans son) signale chaque
/// changement d'étape.
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
    private var background: NSObjectProtocol?
    var onFinish: (() -> Void)?
    /// Changements d'étape annoncés quand l'app n'est pas à l'écran.
    let alerts: [StepAlert]

    init(totalSeconds: Int, alerts: [StepAlert] = []) {
        self.totalSeconds = max(1, totalSeconds)
        self.alerts = alerts
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
                MainActor.assumeIsolated {
                    StepAlert.cancelAll()
                    self?.refresh()
                }
            }
        }
        if background == nil {
            background = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleAlerts() }
            }
        }
        if !alerts.isEmpty { StepAlert.requestPermissionIfNeeded() }
    }

    /// Programme les notifications des étapes restantes, à partir du temps réellement écoulé.
    private func scheduleAlerts() {
        guard state == .running, !alerts.isEmpty else { return }
        let seconds = banked + (resumedAt.map { Date().timeIntervalSince($0) } ?? 0)
        StepAlert.schedule(alerts.filter { Double($0.at) > seconds + 1 }, elapsed: seconds)
    }

    func pause() {
        guard state == .running else { return }
        refresh()
        banked += resumedAt.map { Date().timeIntervalSince($0) } ?? 0
        resumedAt = nil
        state = .paused
        task?.cancel()
        StepAlert.cancelAll()
    }

    func stop() {
        task?.cancel()
        task = nil
        for observer in [foreground, background].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
        foreground = nil
        background = nil
        StepAlert.cancelAll()
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

/// Notification locale d'un changement d'étape, livrée seulement quand l'app n'est pas à l'écran.
/// Le son est un fichier silencieux : l'iPhone vibre brièvement sans jouer de sonnerie.
struct StepAlert: Equatable {
    /// Secondes écoulées depuis le début de la séance.
    let at: Int
    let title: String
    let body: String

    private static let prefix = "session-step."

    /// Une alerte par début d'étape (sauf la première) et une à la fin de la séance.
    static func forSteps(_ steps: [(title: String, seconds: Int)]) -> [StepAlert] {
        var out: [StepAlert] = []
        var at = 0
        for (index, step) in steps.enumerated() {
            if index > 0 {
                out.append(StepAlert(at: at, title: "Étape \(index + 1) sur \(steps.count) : \(step.title)", body: "Passe à l'étape suivante."))
            }
            at += step.seconds
        }
        out.append(StepAlert(at: at, title: "Séance terminée", body: "Bravo, c'est fini pour aujourd'hui."))
        return out
    }

    /// Les opérations sur le centre de notifications s'enchaînent dans l'ordre d'appel : une annulation ne peut pas
    /// effacer des alertes programmées juste après elle.
    @MainActor private static var queue: Task<Void, Never>?

    @MainActor private static func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    @MainActor static func requestPermissionIfNeeded() {
        enqueue {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    @MainActor static func schedule(_ alerts: [StepAlert], elapsed: TimeInterval) {
        cancelAll()
        enqueue {
            let center = UNUserNotificationCenter.current()
            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                content.sound = UNNotificationSound(named: UNNotificationSoundName("step-tick.wav"))
                content.threadIdentifier = "session"
                content.interruptionLevel = .active
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, Double(alert.at) - elapsed), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: prefix + String(alert.at), content: content, trigger: trigger))
            }
        }
    }

    @MainActor static func cancelAll() {
        enqueue {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
    }
}
