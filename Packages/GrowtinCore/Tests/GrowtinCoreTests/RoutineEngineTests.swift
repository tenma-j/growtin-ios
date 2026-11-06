import Foundation
import Testing
@testable import GrowtinCore

@Suite("Moteur de routine")
struct RoutineEngineTests {
    let day = DayKey(year: 2026, month: 11, day: 6)
    let engine = RoutineEngine()

    @Test("La routine reste courte et contient toujours le bilan du jour")
    func routineIsShortAndContainsCheckIn() {
        var profile = UserProfile()
        profile.sleepHours = 5
        profile.stress = .veryHigh
        profile.activity = .sedentary
        profile.diet = .vegan
        profile.wearsTightHairstyles = true
        profile.usesHeatStyling = true
        profile.goals = [.eatBetter, .reduceStress]
        profile.health.treatments = [.topicalMinoxidil]

        let items = engine.initialRoutine(for: profile, startingOn: day)
        #expect(items.count == RoutineEngine.maximumItems + 1)
        #expect(items.contains { $0.templateID == HabitCatalog.checkIn.id })
        #expect(items.map(\.minuteOfDay) == items.map(\.minuteOfDay).sorted())
    }

    @Test("La raison du sommeil cite la réponse et précise l'absence d'effet démontré")
    func sleepReasonIsTransparent() throws {
        var profile = UserProfile()
        profile.sleepHours = 6
        let items = engine.initialRoutine(for: profile, startingOn: day)
        let sleep = try #require(items.first { $0.templateID == HabitCatalog.windDown.id })
        let reason = try #require(sleep.reason)
        #expect(reason.contains("environ 6 heures"))
        #expect(reason.contains("ne constitue pas un traitement démontré"))
    }

    @Test("Le rappel de traitement n'apparaît que si un traitement médicamenteux est déclaré")
    func treatmentReminderOnlyWhenDeclared() {
        let without = engine.initialRoutine(for: UserProfile(), startingOn: day)
        #expect(!without.contains { $0.templateID == HabitCatalog.prescribedTreatment.id })

        var profile = UserProfile()
        profile.health.treatments = [.transplant]
        #expect(!engine.initialRoutine(for: profile, startingOn: day).contains { $0.templateID == HabitCatalog.prescribedTreatment.id })

        profile.health.treatments = [.finasteride]
        #expect(engine.initialRoutine(for: profile, startingOn: day).contains { $0.templateID == HabitCatalog.prescribedTreatment.id })
    }

    @Test("Pas de massage proposé si le cuir chevelu est irrité")
    func noMassageWhenIrritated() {
        var profile = UserProfile()
        profile.health.symptoms = [.rednessOrScaling]
        let candidates = engine.candidates(for: profile)
        #expect(!candidates.contains { $0.template.id == HabitCatalog.scalpMassage.id })
    }

    @Test("Pas d'oléagineux proposés en cas d'allergie aux fruits à coque")
    func noSeedsWhenNutAllergy() {
        var profile = UserProfile()
        profile.goals = [.eatBetter]
        profile.health.restrictions = [.nuts]
        #expect(!engine.candidates(for: profile).contains { $0.template.id == HabitCatalog.seedsHandful.id })
    }

    @Test("Aucune raison ne promet une repousse")
    func noReasonPromisesRegrowth() {
        var profile = UserProfile()
        profile.sleepHours = 5
        profile.stress = .veryHigh
        profile.activity = .sedentary
        profile.diet = .vegetarian
        profile.wearsTightHairstyles = true
        profile.usesHeatStyling = true
        profile.goals = Set(PersonalGoal.allCases)
        profile.health.treatments = [.finasteride]
        profile.weightKg = 75
        let forbidden = ["fait repousser", "stoppe la chute", "garanti", "guérir", "guérit", "+%"]
        for candidate in engine.candidates(for: profile) {
            for word in forbidden {
                #expect(!candidate.reason.lowercased().contains(word), "« \(word) » dans : \(candidate.reason)")
            }
        }
    }

    @Test("Repère protéique EFSA calculé uniquement avec un poids d'adulte")
    func proteinReference() {
        var profile = UserProfile()
        #expect(profile.proteinReferenceGrams == nil)
        profile.weightKg = 75
        #expect(profile.proteinReferenceGrams == 62)
        profile.age = 16
        #expect(profile.proteinReferenceGrams == nil)
    }

    @Test("Formatage des heures de sommeil")
    func hoursFormatting() {
        #expect(RoutineEngine.format(hours: 6) == "6 heures")
        #expect(RoutineEngine.format(hours: 6.5) == "6 h 30")
        #expect(RoutineEngine.format(hours: 6.9) == "7 heures")
    }
}

@Suite("Fiches de preuve et sources")
struct EvidenceTests {
    @Test("La base documentaire embarquée se charge")
    func libraryLoads() throws {
        let library = try SourceLibrary.bundled()
        #expect(library.sources.count >= 25)
    }

    @Test("Chaque source citée par une fiche existe dans la base vérifiée")
    func everyCitedSourceExists() throws {
        let library = try SourceLibrary.bundled()
        for card in EvidenceCatalog.all {
            for id in card.sourceIDs {
                #expect(library[id] != nil, "Source inconnue \(id) dans la fiche \(card.id)")
            }
        }
    }

    @Test("Chaque fiche avec un niveau de preuve a au moins une source")
    func cardsWithEvidenceHaveSources() {
        for card in EvidenceCatalog.all where card.evidence != .insufficient {
            #expect(!card.sourceIDs.isEmpty, "\(card.id) n'a pas de source")
        }
    }

    @Test("Chaque modèle d'habitude pointe vers une fiche existante")
    func templatesPointToCards() {
        for template in HabitCatalog.all {
            #expect(template.evidenceCard != nil, "\(template.id)")
        }
    }

    @Test("Les sources ont une URL https et une date de vérification")
    func sourcesAreWellFormed() throws {
        for source in try SourceLibrary.bundled().sources.values {
            #expect(source.url.scheme == "https", "\(source.id)")
            #expect(DayKey(string: source.verifiedOn) != nil, "\(source.id)")
            #expect(!source.verification.isEmpty)
        }
    }
}
