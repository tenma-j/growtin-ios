import Foundation
import Testing
@testable import GrowtinCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

@Suite("Jours calendaires")
struct DayKeyTests {
    @Test("Aller-retour texte")
    func stringRoundTrip() {
        let day = DayKey(year: 2026, month: 3, day: 9)
        #expect(day.description == "2026-03-09")
        #expect(DayKey(string: "2026-03-09") == day)
        #expect(DayKey(string: "2026-13-01") == nil)
    }

    @Test("Ajout de jours à travers un changement d'heure et un changement d'année")
    func addingDays() {
        let beforeDST = DayKey(year: 2026, month: 3, day: 28)
        #expect(beforeDST.adding(days: 2, calendar: utc) == DayKey(year: 2026, month: 3, day: 30))
        #expect(DayKey(year: 2026, month: 12, day: 31).adding(days: 1, calendar: utc) == DayKey(year: 2027, month: 1, day: 1))
        #expect(DayKey(year: 2026, month: 1, day: 1).days(until: DayKey(year: 2026, month: 12, day: 31), calendar: utc) == 364)
    }
}

@Suite("Régularité")
struct ConsistencyTests {
    let start = DayKey(year: 2026, month: 11, day: 1)

    func item(added: DayKey, removed: DayKey? = nil) -> RoutineItem {
        RoutineItem(templateID: nil, title: "Test", detail: "", symbol: "circle", minuteOfDay: 600, addedOn: added, removedOn: removed)
    }

    @Test("Ratio du jour et régularité sur une période")
    func ratios() {
        let a = item(added: start)
        let b = item(added: start)
        let completions = [
            HabitCompletion(itemID: a.id, day: start),
            HabitCompletion(itemID: b.id, day: start),
            HabitCompletion(itemID: a.id, day: start.adding(days: 1, calendar: utc))
        ]
        let calculator = ConsistencyCalculator(items: [a, b], completions: completions)
        #expect(calculator.progress(on: start).ratio == 1)
        #expect(calculator.progress(on: start.adding(days: 1, calendar: utc)).ratio == 0.5)
        // 3 réalisées sur 6 prévues en 3 jours.
        #expect(calculator.consistency(endingOn: start.adding(days: 2, calendar: utc), days: 3, calendar: utc) == 0.5)
        #expect(calculator.activeDays(endingOn: start.adding(days: 2, calendar: utc), days: 3, calendar: utc) == 2)
    }

    @Test("Une habitude ajoutée ou retirée ne fausse pas l'historique")
    func addedAndRemovedItems() {
        let later = item(added: start.adding(days: 2, calendar: utc))
        let removed = item(added: start, removed: start.adding(days: 1, calendar: utc))
        let calculator = ConsistencyCalculator(items: [later, removed], completions: [])
        #expect(calculator.progress(on: start).scheduled == 1)
        #expect(calculator.progress(on: start.adding(days: 1, calendar: utc)).scheduled == 0)
        #expect(calculator.progress(on: start.adding(days: 1, calendar: utc)).ratio == nil)
        #expect(calculator.progress(on: start.adding(days: 2, calendar: utc)).scheduled == 1)
    }

    @Test("Pas de régularité sans habitude prévue")
    func emptyRoutine() {
        let calculator = ConsistencyCalculator(items: [], completions: [])
        #expect(calculator.consistency(endingOn: start, days: 7, calendar: utc) == nil)
    }

    @Test("Une réalisation d'une habitude retirée n'est pas comptée")
    func completionOfUnscheduledItemIgnored() {
        let removed = item(added: start, removed: start)
        let calculator = ConsistencyCalculator(items: [removed], completions: [HabitCompletion(itemID: removed.id, day: start)])
        #expect(calculator.progress(on: start).completed == 0)
    }

    @Test("Le bilan du jour borne ses valeurs")
    func checkInClamping() {
        let checkIn = DailyCheckIn(day: start, sleepHours: 30, stress: 9)
        #expect(checkIn.sleepHours == 16)
        #expect(checkIn.stress == 5)
        #expect(DailyCheckIn(day: start, note: "   ").isEmpty)
    }
}
