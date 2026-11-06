import Foundation
import GrowtinCore
import SwiftData

extension AppModel {
    /// Modèle en mémoire pour les aperçus SwiftUI. Données d'exemple clairement fictives, jamais utilisées en production.
    static func preview(withProfile: Bool = false) -> AppModel {
        let container = try! GrowtinSchema.makeContainer(inMemory: true)
        let model = AppModel(container: container, notifications: PreviewNotificationService())
        model.load()
        if withProfile {
            var profile = UserProfile(firstName: "Alex", sex: .male, age: 28)
            profile.sleepHours = 6
            profile.stress = .high
            profile.activity = .light
            profile.goals = [.buildHabits, .trackEvolution]
            model.completeOnboarding(with: profile)
        }
        return model
    }
}
