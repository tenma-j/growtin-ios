import Foundation
import Testing
@testable import GrowtinCore

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

@Suite("Feuille de route et photos")
struct RoadmapTests {
    let start = DayKey(year: 2026, month: 1, day: 1)

    @Test("Statut des étapes selon l'avancement")
    func milestoneStatus() {
        let today = start.adding(days: 40, calendar: paris)
        let milestones = Roadmap.milestones(programStart: start, today: today, calendar: paris)
        #expect(milestones.count == 6)
        #expect(milestones[0].status == .past)
        #expect(milestones[2].status == .current) // 30 jours
        #expect(milestones[3].status == .upcoming)
        #expect(Roadmap.nextMilestone(programStart: start, today: today, calendar: paris)?.dayOffset == 90)
    }

    @Test("Aucune étape ne promet de résultat")
    func milestonesMakeNoPromises() {
        for milestone in Roadmap.milestones(programStart: start, today: start, calendar: paris) {
            let text = (milestone.title + milestone.detail).lowercased()
            #expect(!text.contains("repousse"))
            #expect(!text.contains("%"))
        }
    }

    @Test("Calendrier des photos")
    func photoSchedule() {
        #expect(PhotoSchedule.nextDue(lastPhoto: nil, frequency: .everyFourWeeks, today: start, calendar: paris) == start)
        let next = PhotoSchedule.nextDue(lastPhoto: start, frequency: .everyFourWeeks, today: start, calendar: paris)
        #expect(start.days(until: next, calendar: paris) == 28)
        #expect(!PhotoSchedule.isDue(lastPhoto: start, frequency: .everyFourWeeks, today: start.adding(days: 10, calendar: paris), calendar: paris))
        let upcoming = PhotoSchedule.upcoming(lastPhoto: start, frequency: .everyFourWeeks, today: start,
                                              through: start.adding(days: 90, calendar: paris), calendar: paris)
        #expect(upcoming.count == 3)
    }
}

@Suite("Prévisions d'habitudes")
struct ForecasterTests {
    let today = DayKey(year: 2026, month: 6, day: 30)
    let forecaster = HabitForecaster()

    func series(days: Int, value: (Int) -> Double) -> [DayKey: Double] {
        Dictionary(uniqueKeysWithValues: (0..<days).map { offset in
            (today.adding(days: -offset, calendar: paris), value(offset))
        })
    }

    @Test("Données insuffisantes en dessous de 14 jours")
    func insufficientData() {
        let result = forecaster.project(metricName: "Régularité", observations: series(days: 10) { _ in 0.5 },
                                        today: today, horizonDays: 30, valueRange: 0...1, calendar: paris)
        guard case .insufficientData = result else { Issue.record("Une prévision ne devrait pas être produite"); return }
    }

    @Test("Données constantes : pas de tendance calculable")
    func flatSeriesIsStillAProjection() {
        let result = forecaster.project(metricName: "Régularité", observations: series(days: 20) { _ in 0.6 },
                                        today: today, horizonDays: 30, valueRange: 0...1, calendar: paris)
        guard case .projection(let projection) = result else { Issue.record("Projection attendue"); return }
        #expect(abs(projection.projectedLevel - 0.6) < 0.0001)
        #expect(abs(projection.upperBound - projection.lowerBound) < 0.0001)
    }

    @Test("Tendance croissante, bornes physiques et objectif")
    func risingTrend() {
        // Sommeil : +0,05 h par jour, aujourd'hui 7 h.
        let result = forecaster.project(metricName: "Sommeil", observations: series(days: 21) { 7 - 0.05 * Double($0) },
                                        today: today, horizonDays: 30, valueRange: 0...12, target: 7.5, calendar: paris)
        guard case .projection(let projection) = result else { Issue.record("Projection attendue"); return }
        #expect(abs(projection.currentLevel - 7) < 0.001)
        #expect(abs(projection.projectedLevel - 8.5) < 0.001)
        #expect(abs(projection.weeklyChange - 0.35) < 0.001)
        #expect(projection.daysToTarget == 10)
        #expect(projection.assumptions.contains { $0.contains("pas sur l'évolution de tes cheveux") })
    }

    @Test("La projection reste dans les bornes")
    func clamped() {
        let result = forecaster.project(metricName: "Régularité", observations: series(days: 20) { 1 - 0.04 * Double($0) },
                                        today: today, horizonDays: 90, valueRange: 0...1, calendar: paris)
        guard case .projection(let projection) = result else { Issue.record("Projection attendue"); return }
        #expect(projection.projectedLevel == 1)
        #expect(projection.upperBound <= 1)
    }

    @Test("Les jours sans donnée ne bloquent pas si la période est couverte")
    func sparseData() {
        let sparse = series(days: 30) { Double($0 % 2) }.filter { $0.key.day % 2 == 0 }
        let result = forecaster.project(metricName: "x", observations: sparse, today: today, horizonDays: 7,
                                        valueRange: 0...1, calendar: paris)
        if sparse.count >= 14 {
            guard case .projection = result else { Issue.record("Projection attendue"); return }
        } else {
            guard case .insufficientData = result else { Issue.record("Données insuffisantes attendues"); return }
        }
    }
}

@Suite("Signaux d'alerte")
struct SafetyTests {
    let screener = SafetyScreener()

    @Test("Détresse détectée en priorité, avec le 3114")
    func distress() throws {
        let alerts = screener.assess(text: "J'en ai marre, j'ai plus envie de vivre avec ces cheveux, et j'ai des plaques")
        let first = try #require(alerts.first)
        #expect(first.level == .seekHelpNow)
        #expect(first.message.contains("3114"))
        #expect(alerts.contains { $0.id == "patches" })
    }

    @Test("Insensible aux accents et à la casse")
    func normalization() {
        #expect(screener.assess(text: "Grosse BRÛLURE sur le cuir chevelu").contains { $0.id == "inflammation" })
        #expect(screener.assess(text: "je perds mes cheveux par poignées").contains { $0.id == "sudden-shedding" })
        #expect(screener.assess(text: "Effets indésirables depuis le début").contains { $0.id == "side-effect" })
    }

    @Test("Aucun faux positif sur un texte banal")
    func noFalsePositive() {
        #expect(screener.assess(text: "Bonne journée, bien dormi, salade de lentilles à midi.").isEmpty)
        #expect(screener.assess(text: "").isEmpty)
    }

    @Test("Profil : grossesse et traitement déclaré")
    func pregnancyAndTreatment() {
        var profile = UserProfile(sex: .female)
        profile.health.pregnancy = .pregnant
        profile.health.treatments = [.topicalMinoxidil]
        #expect(screener.assess(profile: profile).contains { $0.id == "pregnancy-treatment" })
    }

    @Test("Profil : symptômes déclarés et ordre par gravité")
    func profileSymptoms() {
        var profile = UserProfile()
        profile.triggers = [.postpartum]
        profile.health.symptoms = [.patches, .painOrBurning]
        let alerts = screener.assess(profile: profile)
        #expect(alerts.map(\.id).prefix(2).sorted() == ["inflammation", "patches"])
        #expect(alerts.last?.level == .information)
    }

    @Test("Le message de grossesse ne demande jamais d'arrêter un traitement")
    func neverStopTreatment() {
        let all = [SafetyScreener.pregnancyTreatmentAlert, SafetyScreener.sideEffectAlert]
        for alert in all {
            #expect(alert.message.contains("sans") || alert.message.contains("N'arrête"))
        }
    }
}

@Suite("Accueil")
struct GreetingTests {
    @Test func greetingByHour() {
        let morning = paris.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8))!
        let evening = paris.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 20))!
        #expect(Greeting.text(name: "Jordan", date: morning, calendar: paris) == "Bonjour, Jordan")
        #expect(Greeting.text(name: nil, date: evening, calendar: paris) == "Bonsoir")
    }
}
