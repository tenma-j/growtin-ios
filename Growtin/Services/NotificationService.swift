import Foundation
import GrowtinCore
import UserNotifications

enum NotificationAuthorization: Equatable {
    case notDetermined, denied, authorized
}

/// Abstraction des rappels locaux, remplaçable en test et dans les aperçus.
@MainActor
protocol NotificationScheduling: AnyObject {
    func authorizationStatus() async -> NotificationAuthorization
    /// Demande l'autorisation. N'est appelé qu'au moment où l'utilisateur active un rappel.
    func requestAuthorization() async -> Bool
    func syncDailyReminders(for items: [RoutineItem]) async
    func removeAll() async
}

/// Rappels quotidiens locaux. Aucun serveur n'intervient : les rappels sont programmés sur l'appareil.
@MainActor
final class NotificationService: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()
    private static let prefix = "routine."

    func authorizationStatus() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func syncDailyReminders(for items: [RoutineItem]) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard await authorizationStatus() == .authorized else { return }
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            // Ton volontairement neutre et bienveillant : jamais culpabilisant ni anxiogène.
            content.body = "C'est le moment prévu pour cette habitude, si tu le souhaites."
            content.sound = .default
            content.threadIdentifier = "routine"
            var components = DateComponents()
            components.hour = item.minuteOfDay / 60
            components.minute = item.minuteOfDay % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: Self.prefix + item.id.uuidString, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func removeAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

/// Implémentation inerte pour les aperçus SwiftUI et les tests. Clairement non fonctionnelle.
@MainActor
final class PreviewNotificationService: NotificationScheduling {
    func authorizationStatus() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async -> Bool { true }
    func syncDailyReminders(for items: [RoutineItem]) async {}
    func removeAll() async {}
}
