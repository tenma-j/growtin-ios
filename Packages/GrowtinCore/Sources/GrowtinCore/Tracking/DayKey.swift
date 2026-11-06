import Foundation

/// Un jour calendaire, indépendant de l'heure et du fuseau horaire. Format de stockage : `AAAA-MM-JJ`.
public struct DayKey: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year!, month: components.month!, day: components.day!)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Midi du jour concerné : évite les ambiguïtés lors des changements d'heure.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        DayKey(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar))!, calendar: calendar)
    }

    public func days(until other: DayKey, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(calendar: calendar), to: other.date(calendar: calendar)).day!
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Jours de `start` à `end` inclus.
    public static func range(from start: DayKey, through end: DayKey, calendar: Calendar = .current) -> [DayKey] {
        guard start <= end else { return [] }
        var result: [DayKey] = []
        var current = start
        while current <= end {
            result.append(current)
            current = current.adding(days: 1, calendar: calendar)
        }
        return result
    }
}
