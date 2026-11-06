import Foundation

/// Étapes de suivi du programme. Ce sont des rendez-vous d'observation, **jamais des promesses de résultat**.
public struct Milestone: Hashable, Sendable, Identifiable {
    public enum Status: Sendable, Hashable { case past, current, upcoming }

    public let id: Int
    public let dayOffset: Int
    public let title: String
    public let detail: String
    public let symbol: String
    public let day: DayKey
    public let status: Status
}

public enum Roadmap {
    struct Definition {
        let dayOffset: Int
        let title: String
        let detail: String
        let symbol: String
    }

    static let definitions: [Definition] = [
        Definition(dayOffset: 0, title: "Point de départ",
                   detail: "Mise en place de ta routine et photos de référence de chaque zone.",
                   symbol: "flag"),
        Definition(dayOffset: 7, title: "Première semaine",
                   detail: "Premier bilan de régularité et ajustement des habitudes trop difficiles.",
                   symbol: "calendar"),
        Definition(dayOffset: 30, title: "Bilan du premier mois",
                   detail: "Habitudes qui s'installent, deuxième série de photos et révision des objectifs.",
                   symbol: "1.circle"),
        Definition(dayOffset: 90, title: "Bilan du troisième mois",
                   detail: "Bilan des habitudes, comparaison des photos disponibles et adaptation éventuelle de la routine.",
                   symbol: "3.circle"),
        Definition(dayOffset: 180, title: "Bilan des six mois",
                   detail: "Analyse rétrospective de tes observations, réévaluation des objectifs et préparation des prochaines étapes.",
                   symbol: "6.circle"),
        Definition(dayOffset: 365, title: "Bilan annuel",
                   detail: "Comparaison des photos sur un an et synthèse complète des habitudes suivies.",
                   symbol: "star.circle")
    ]

    /// Le cycle du cheveu est long : les changements visibles, quels qu'ils soient, s'observent sur plusieurs mois.
    public static let disclaimer = "Ces étapes sont des rendez-vous de suivi, pas des promesses de résultat. Le cycle de croissance du cheveu dure plusieurs mois : une comparaison de photos n'a de sens qu'à long terme et dans des conditions similaires."

    public static func milestones(programStart: DayKey, today: DayKey, calendar: Calendar = .current) -> [Milestone] {
        let elapsed = programStart.days(until: today, calendar: calendar)
        let currentIndex = definitions.lastIndex { $0.dayOffset <= elapsed } ?? 0
        return definitions.enumerated().map { index, definition in
            let status: Milestone.Status = index < currentIndex ? .past : (index == currentIndex ? .current : .upcoming)
            return Milestone(id: index, dayOffset: definition.dayOffset, title: definition.title, detail: definition.detail,
                             symbol: definition.symbol, day: programStart.adding(days: definition.dayOffset, calendar: calendar),
                             status: status)
        }
    }

    public static func nextMilestone(programStart: DayKey, today: DayKey, calendar: Calendar = .current) -> Milestone? {
        milestones(programStart: programStart, today: today, calendar: calendar).first { $0.day > today }
    }
}

public enum PhotoSchedule {
    /// Prochaine date de photo conseillée. Sans aucune photo, la photo de référence est attendue dès aujourd'hui.
    public static func nextDue(lastPhoto: DayKey?, frequency: PhotoFrequency, today: DayKey, calendar: Calendar = .current) -> DayKey {
        guard let lastPhoto else { return today }
        return lastPhoto.adding(days: frequency.days, calendar: calendar)
    }

    public static func isDue(lastPhoto: DayKey?, frequency: PhotoFrequency, today: DayKey, calendar: Calendar = .current) -> Bool {
        nextDue(lastPhoto: lastPhoto, frequency: frequency, today: today, calendar: calendar) <= today
    }

    /// Dates prévues entre `from` et `through` (incluses), pour les afficher sur le tableau prévisionnel.
    public static func upcoming(lastPhoto: DayKey?, frequency: PhotoFrequency, today: DayKey, through end: DayKey,
                                calendar: Calendar = .current) -> [DayKey] {
        var dates: [DayKey] = []
        var next = nextDue(lastPhoto: lastPhoto, frequency: frequency, today: today, calendar: calendar)
        if next < today { next = today }
        while next <= end {
            dates.append(next)
            next = next.adding(days: frequency.days, calendar: calendar)
        }
        return dates
    }
}
