import Foundation

/// Scénario de prévision portant **uniquement sur des habitudes mesurables** (régularité, heures de sommeil…).
/// Aucune prévision biologique (repousse, densité, évolution de l'alopécie) n'est calculée par Growtin'.
public struct HabitProjection: Hashable, Sendable {
    public let metricName: String
    public let currentLevel: Double
    public let projectedLevel: Double
    /// Intervalle de prédiction à 95 % autour de la valeur projetée.
    public let lowerBound: Double
    public let upperBound: Double
    public let horizonDays: Int
    /// Variation moyenne par semaine sur la période observée.
    public let weeklyChange: Double
    /// Jours estimés avant d'atteindre l'objectif, si la tendance actuelle se maintient et que l'objectif est atteignable.
    public let daysToTarget: Int?
    public let observedDays: Int
    public let assumptions: [String]
}

public enum ForecastResult: Hashable, Sendable {
    case insufficientData(reason: String)
    case projection(HabitProjection)

    public static let insufficientDataTitle = "Données insuffisantes pour établir une prévision fiable"
}

public struct HabitForecaster: Sendable {
    /// Nombre minimal de jours renseignés pour calculer une tendance.
    public let minimumObservations: Int
    /// Étendue minimale de la période observée, en jours.
    public let minimumSpanDays: Int

    public init(minimumObservations: Int = 14, minimumSpanDays: Int = 14) {
        self.minimumObservations = minimumObservations
        self.minimumSpanDays = minimumSpanDays
    }

    /// - Parameters:
    ///   - observations: valeurs par jour (les jours sans donnée sont simplement absents).
    ///   - valueRange: bornes physiques de la mesure (par exemple 0…1 pour une régularité).
    ///   - target: objectif optionnel de l'utilisateur.
    public func project(metricName: String, observations: [DayKey: Double], today: DayKey, horizonDays: Int,
                        valueRange: ClosedRange<Double>, target: Double? = nil,
                        calendar: Calendar = .current) -> ForecastResult {
        let points = observations
            .filter { $0.key <= today }
            .map { (x: Double($0.key.days(until: today, calendar: calendar)) * -1, y: $0.value) }
            .sorted { $0.x < $1.x }

        guard points.count >= minimumObservations else {
            return .insufficientData(reason: "Il faut au moins \(minimumObservations) jours renseignés (actuellement \(points.count)).")
        }
        guard let first = points.first, let last = points.last, last.x - first.x >= Double(minimumSpanDays - 1) else {
            return .insufficientData(reason: "Les données doivent couvrir au moins \(minimumSpanDays) jours.")
        }

        let n = Double(points.count)
        let meanX = points.reduce(0) { $0 + $1.x } / n
        let meanY = points.reduce(0) { $0 + $1.y } / n
        let sxx = points.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        guard sxx > 0 else { return .insufficientData(reason: "Les données ne varient pas dans le temps.") }
        let sxy = points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        let residualVariance = points.reduce(0) { sum, point in
            let error = point.y - (intercept + slope * point.x)
            return sum + error * error
        } / max(n - 2, 1)
        let residualSE = residualVariance.squareRoot()

        let clamp: (Double) -> Double = { min(max($0, valueRange.lowerBound), valueRange.upperBound) }
        let current = clamp(intercept)
        let x0 = Double(horizonDays)
        let projected = clamp(intercept + slope * x0)
        let margin = 1.96 * residualSE * (1 + 1 / n + (x0 - meanX) * (x0 - meanX) / sxx).squareRoot()

        var daysToTarget: Int?
        if let target, slope != 0 {
            let crossing = (target - intercept) / slope
            if crossing > 0, crossing <= 365, valueRange.contains(target) {
                daysToTarget = Int(crossing.rounded(.up))
            } else if crossing <= 0, (slope > 0 ? current >= target : current <= target) {
                daysToTarget = 0
            }
        }

        let projection = HabitProjection(
            metricName: metricName,
            currentLevel: current,
            projectedLevel: projected,
            lowerBound: clamp(projected - margin),
            upperBound: clamp(projected + margin),
            horizonDays: horizonDays,
            weeklyChange: slope * 7,
            daysToTarget: daysToTarget,
            observedDays: points.count,
            assumptions: [
                "La tendance des \(points.count) derniers jours renseignés se poursuit à l'identique.",
                "La prévision porte uniquement sur cette habitude, pas sur l'évolution de tes cheveux.",
                "Plus l'horizon est lointain, plus l'incertitude est grande."
            ])
        return .projection(projection)
    }
}
