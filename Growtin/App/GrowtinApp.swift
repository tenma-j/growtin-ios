import SwiftData
import SwiftUI

@main
struct GrowtinApp: App {
    private let container: ModelContainer?
    @State private var model: AppModel?

    init() {
        do {
            let container = try GrowtinSchema.makeContainer()
            self.container = container
            _model = State(initialValue: AppModel(container: container, notifications: NotificationService()))
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
