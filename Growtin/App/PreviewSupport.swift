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
            #if DEBUG
            model.seedDemo(days: 28)
            #else
            model.completeOnboarding(with: DemoData.profile(start: .now))
            #endif
        }
        return model
    }

    #if DEBUG
    /// Remplit le modèle avec un historique fictif de `days` jours (pour les aperçus et les captures).
    func seedDemo(days: Int, calendar: Calendar = .current) {
        let today = DayKey(.now, calendar: calendar)
        let start = today.adding(days: -(days - 1), calendar: calendar)
        let profile = DemoData.profile(start: start.date(calendar: calendar))
        let routine = RoutineEngine().initialRoutine(for: profile, startingOn: start)

        // Générateur déterministe : les captures sont identiques d'une exécution à l'autre.
        var seed: UInt64 = 42
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }

        let sheddingOptions: [SheddingPerception] = [.usual, .usual, .less, .more, .notObserved]
        var completions: [HabitCompletion] = []
        var checkIns: [DailyCheckIn] = []
        for (offset, day) in DayKey.range(from: start, through: today.adding(days: -1, calendar: calendar), calendar: calendar).enumerated() {
            let progress = Double(offset) / Double(max(days - 1, 1))
            for item in routine where random() < 0.45 + 0.4 * progress {
                completions.append(HabitCompletion(itemID: item.id, day: day))
            }
            if random() < 0.8 {
                checkIns.append(DailyCheckIn(
                    day: day,
                    sleepHours: ((6 + 1.1 * progress + (random() - 0.5)) * 2).rounded() / 2,
                    stress: max(1, min(5, Int((4 - 1.5 * progress + random()).rounded()))),
                    shedding: sheddingOptions[Int(random() * 5) % 5]))
            }
        }
        // Aujourd'hui : deux habitudes déjà cochées.
        for item in routine.prefix(2) { completions.append(HabitCompletion(itemID: item.id, day: today)) }

        importDemoData(profile: profile, routine: routine, completions: completions, checkIns: checkIns)
    }
    #endif
}

enum DemoData {
    static func profile(start: Date) -> UserProfile {
        var profile = UserProfile(firstName: "Alex", sex: .male, age: 28)
        profile.hairLossDuration = .sixMonthsTo2Years
        profile.triggers = [.stress, .genetics]
        profile.familyHistory = .fatherSide
        profile.stage = SelfAssessedStage(scale: .norwood, stage: 2)
        profile.zones = [.leftTemple, .rightTemple, .frontalHairline]
        profile.goals = [.buildHabits, .trackEvolution, .reduceStress]
        profile.sleepHours = 6
        profile.stress = .high
        profile.activity = .light
        profile.weightKg = 75
        profile.heightCm = 180
        profile.consents.wellnessDisclaimerAcceptedAt = start
        profile.programStartDate = start
        return profile
    }
}
