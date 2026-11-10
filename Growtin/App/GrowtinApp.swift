import SwiftData
import SwiftUI

@main
struct GrowtinApp: App {
    private let container: ModelContainer?
    @State private var model: AppModel?

    init() {
        do {
            if let screen = DemoLaunch.screen {
                // Mode démonstration : base en mémoire, aucune donnée réelle n'est lue ni écrite.
                let container = try GrowtinSchema.makeContainer(inMemory: true)
                self.container = container
                let model = AppModel(container: container, notifications: PreviewNotificationService(), photoStore: .temporary(),
                                     coachService: DemoCoachService(),
                                     purchaseService: DemoPurchaseService())
                model.load()
                #if DEBUG
                if screen != "onboarding" { model.seedDemo(days: 28) }
                if screen == "coach" { model.coach.seedDemo() }
                if screen == "coachConsent" { model.revokeCoachConsent() }
                #endif
                _model = State(initialValue: model)
                return
            }
            let container = try GrowtinSchema.makeContainer()
            self.container = container
            _model = State(initialValue: AppModel(container: container, notifications: NotificationService(), photoStore: PhotoStore(),
                                                          coachService: SupabaseCoachService(),
                                                          purchaseService: RevenueCatPurchaseService()))
        } catch {
            self.container = nil
            _model = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model, let container {
                RootView()
                    .environment(model)
                    .modelContainer(container)
                    .tint(.gtInk)
            } else {
                StorageFailureView()
            }
        }
    }
}

/// Affiché si la base locale ne peut pas être ouverte (stockage plein, fichier corrompu).
private struct StorageFailureView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Données inaccessibles", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Growtin' n'a pas pu ouvrir ses données sur cet appareil. Vérifie l'espace de stockage disponible, puis relance l'application.")
        }
    }
}
