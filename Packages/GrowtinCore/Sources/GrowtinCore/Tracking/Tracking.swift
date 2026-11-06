import Foundation

public struct HabitCompletion: Codable, Hashable, Sendable {
    public let itemID: UUID
    public let day: DayKey
    public let completedAt: Date

    public init(itemID: UUID, day: DayKey, completedAt: Date = Date()) {
        self.itemID = itemID
        self.day = day
        self.completedAt = completedAt
    }
}

public enum SheddingPerception: String, Codable, Sendable, CaseIterable, Identifiable {
    case less, usual, more, notObserved

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .less: "Moins que d'habitude"
        case .usual: "Comme d'habitude"
        case .more: "Plus que d'habitude"
        case .notObserved: "Pas observé"
        }
    }
}

/// Bilan du jour : chaque champ est facultatif, le bilan ne doit jamais devenir une contrainte.
public struct DailyCheckIn: Codable, Hashable, Sendable {
    public let day: DayKey
    public var sleepHours: Double?
    /// Stress ressenti, de 1 (très calme) à 5 (très stressé).
    public var stress: Int?
    public var shedding: SheddingPerception?
    public var note: String

    public init(day: DayKey, sleepHours: Double? = nil, stress: Int? = nil, shedding: SheddingPerception? = nil, note: String = "") {
        self.day = day
        self.sleepHours = sleepHours.map { max(0, min($0, 16)) }
        self.stress = stress.map { max(1, min($0, 5)) }
        self.shedding = shedding
        self.note = note
    }

    public var isEmpty: Bool {
        sleepHours == nil && stress == nil && shedding == nil && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct DayProgress: Hashable, Sendable {
    public let day: DayKey
    public let scheduled: Int
    public let completed: Int

    /// `nil` quand aucune habitude n'était prévue ce jour-là.
    public var ratio: Double? { scheduled == 0 ? nil : Double(completed) / Double(scheduled) }
}

/// Indicateur de régularité : la part des habitudes **choisies par l'utilisateur** qui ont été réalisées.
/// Ce n'est en aucun cas un indicateur de santé capillaire.
public struct ConsistencyCalculator: Sendable {
    public let items: [RoutineItem]
    private let completedByDay: [DayKey: Set<UUID>]

    public init(items: [RoutineItem], completions: [HabitCompletion]) {
        self.items = items
        self.completedByDay = Dictionary(grouping: completions, by: \.day).mapValues { Set($0.map(\.itemID)) }
    }

    public func progress(on day: DayKey) -> DayProgress {
        let scheduled = items.filter { $0.isScheduled(on: day) }
        let done = completedByDay[day] ?? []
        let completed = scheduled.filter { done.contains($0.id) }.count
        return DayProgress(day: day, scheduled: scheduled.count, completed: completed)
    }

    public func isCompleted(_ item: RoutineItem, on day: DayKey) -> Bool {
        completedByDay[day]?.contains(item.id) ?? false
    }

    public func series(endingOn end: DayKey, days: Int, calendar: Calendar = .current) -> [DayProgress] {
        guard days > 0 else { return [] }
        let start = end.adding(days: -(days - 1), calendar: calendar)
        return DayKey.range(from: start, through: end, calendar: calendar).map(progress(on:))
    }

    /// Régularité sur une période : total réalisé ÷ total prévu. `nil` si rien n'était prévu.
    public func consistency(endingOn end: DayKey, days: Int, calendar: Calendar = .current) -> Double? {
        let series = series(endingOn: end, days: days, calendar: calendar)
        let scheduled = series.reduce(0) { $0 + $1.scheduled }
        guard scheduled > 0 else { return nil }
        return Double(series.reduce(0) { $0 + $1.completed }) / Double(scheduled)
    }

    /// Nombre de jours actifs (au moins une habitude réalisée) sur la période. Volontairement préféré
    /// à une « série » qui se remet à zéro et culpabilise après un jour manqué.
    public func activeDays(endingOn end: DayKey, days: Int, calendar: Calendar = .current) -> Int {
        series(endingOn: end, days: days, calendar: calendar).filter { $0.completed > 0 }.count
    }
}
