import Foundation
import Testing
@testable import GrowtinCore

@Suite("Explorer : exercices et bibliothèque")
struct ExploreTests {
    let library = try! SourceLibrary.bundled()

    @Test("Chaque exercice est complet et sourcé")
    func exercisesAreComplete() {
        #expect(ExerciseLibrary.all.count >= 7)
        #expect(Set(ExerciseLibrary.all.map(\.id)).count == ExerciseLibrary.all.count)
        for exercise in ExerciseLibrary.all {
            #expect(!exercise.steps.isEmpty && exercise.totalSeconds >= 120, "\(exercise.id)")
            #expect(!exercise.precautions.isEmpty, "\(exercise.id)")
            #expect(!exercise.hairNote.isEmpty)
            for id in exercise.sourceIDs { #expect(library[id] != nil, "\(exercise.id) → \(id)") }
            if exercise.evidence != .insufficient { #expect(!exercise.sourceIDs.isEmpty, "\(exercise.id)") }
            if let habit = exercise.habitTemplateID { #expect(HabitCatalog.template(id: habit) != nil) }
        }
    }

    @Test("Aucun exercice ne revendique d'effet sur les cheveux")
    func exercisesMakeNoHairClaims() {
        for exercise in ExerciseLibrary.all {
            let text = (exercise.summary + exercise.benefits).lowercased()
            #expect(!text.contains("cheveu"), "\(exercise.id) : les bénéfices ne doivent pas parler de cheveux")
            #expect(!exercise.hairNote.lowercased().contains("favorise la pousse"))
        }
    }

    @Test("Recommandations d'activité : raisons tirées du profil et des bilans")
    func exerciseRecommendations() {
        let today = DayKey(year: 2026, month: 11, day: 11)
        var stressed = UserProfile(age: 30)
        stressed.stress = .low
        stressed.sleepHours = 8
        stressed.sleepQuality = .good
        stressed.activity = .moderate
        let checkIns = (0..<5).map { DailyCheckIn(day: today.adding(days: -$0), sleepHours: 6, stress: 4) }
        let picks = ExerciseRecommender.recommend(profile: stressed, checkIns: checkIns, today: today)
        #expect(picks.count == 3)
        #expect(picks[0].exercise.id == "relaxation-progressive")
        #expect(picks[0].reason.contains("4/5"))
        #expect(picks.contains { $0.exercise.id == "scan-corporel" && $0.reason.contains("6 h") })

        var calm = UserProfile(age: 30)
        calm.stress = .low
        calm.sleepHours = 8
        calm.sleepQuality = .good
        calm.activity = .sedentary
        let calmPicks = ExerciseRecommender.recommend(profile: calm, checkIns: [], today: today)
        #expect(calmPicks.first?.exercise.id == "marche-active")
        #expect(Set(calmPicks.map(\.id)).count == calmPicks.count)
        #expect(ExerciseRecommender.format(6.5) == "6,5")
    }

    @Test("Chaque article cite des sources existantes")
    func articlesAreSourced() {
        #expect(ArticleLibrary.all.count >= 10)
        for article in ArticleLibrary.all {
            #expect(!article.sourceIDs.isEmpty, "\(article.id)")
            for id in article.sourceIDs { #expect(library[id] != nil, "\(article.id) → \(id)") }
            #expect(!article.keyPoints.isEmpty && !article.sections.isEmpty)
            #expect(article.readMinutes >= 1)
        }
        for category in ArticleCategory.allCases {
            #expect(ArticleLibrary.all.contains { $0.category == category })
        }
    }

    @Test("Les articles ne donnent ni dosage ni consigne d'arrêt de traitement")
    func articlesAreSafe() {
        let dosage = try! Regex(#"\d+\s?(mg|µg|g)\s?(par|/)\s?(jour|j)"#)
        for article in ArticleLibrary.all {
            let text = (article.keyPoints + article.sections.flatMap(\.paragraphs)).joined(separator: " ").lowercased()
            #expect(text.firstMatch(of: dosage) == nil, "\(article.id) contient un dosage")
            #expect(!text.contains("arrête ton traitement"))
            #expect(!text.contains("guérit"))
            if article.category == .treatments {
                #expect(text.contains("médecin"), "\(article.id) doit renvoyer vers un médecin")
            }
        }
    }
}
