import Foundation

/// Évalue si deux photos peuvent être comparées visuellement de façon pertinente.
/// Growtin' ne mesure ni densité, ni repousse, ni évolution : ce rapport porte uniquement sur les **conditions de prise de vue**.
public struct ComparabilityReport: Hashable, Sendable {
    public enum Level: Int, Sendable, Comparable {
        case low, medium, high
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        public var label: String {
            switch self {
            case .low: "Comparaison peu fiable"
            case .medium: "Comparaison à interpréter avec prudence"
            case .high: "Conditions comparables"
            }
        }
    }

    public let level: Level
    public let score: Int
    public let reasons: [String]
    public let daysApart: Int

    public static let disclaimer = "Comparaison visuelle uniquement. Growtin' ne mesure ni la densité, ni la repousse, ni l'évolution d'une alopécie. La lumière, l'angle, la longueur et le coiffage changent fortement l'aspect des cheveux. Pour une évaluation, consulte un dermatologue."
}

public enum ComparabilityAnalyzer {
    public static func compare(_ a: PhotoEntry, _ b: PhotoEntry, calendar: Calendar = .current) -> ComparabilityReport {
        let (before, after) = a.takenAt <= b.takenAt ? (a, b) : (b, a)
        let daysApart = before.day.days(until: after.day, calendar: calendar)
        var score = 100
        var reasons: [String] = []

        func penalize(_ points: Int, _ reason: String) {
            score -= points
            reasons.append(reason)
        }

        if before.zone != after.zone {
            return ComparabilityReport(level: .low, score: 0, reasons: ["Les deux photos ne montrent pas la même zone."], daysApart: daysApart)
        }
        if before.camera != after.camera {
            penalize(15, "Les photos n'ont pas été prises avec la même caméra.")
        }

        if let qa = before.quality, let qb = after.quality {
            if ImageQualityAnalyzer.assess(qa).level == .poor || ImageQualityAnalyzer.assess(qb).level == .poor {
                penalize(40, "Au moins une photo est floue, trop sombre ou trop claire.")
            }
            if abs(qa.brightness - qb.brightness) > 0.15 {
                penalize(25, "La luminosité est très différente entre les deux photos.")
            } else if abs(qa.brightness - qb.brightness) > 0.08 {
                penalize(10, "La luminosité diffère un peu entre les deux photos.")
            }
        } else {
            penalize(10, "La qualité d'au moins une photo n'a pas pu être analysée.")
        }

        let ca = before.conditions, cb = after.conditions
        if !ca.dryHair || !cb.dryHair {
            penalize(40, "Des cheveux mouillés paraissent nettement moins denses.")
        }
        if !ca.usualStyling || !cb.usualStyling {
            penalize(15, "Le coiffage n'était pas le même que d'habitude.")
        }
        if !ca.noProduct || !cb.noProduct {
            penalize(10, "Un produit coiffant modifie l'aspect des cheveux.")
        }
        if ca.lighting != cb.lighting {
            penalize(20, "La source de lumière n'était pas la même.")
        }

        let fa = before.framing, fb = after.framing
        if let xa = fa.faceCenterX, let ya = fa.faceCenterY, let xb = fb.faceCenterX, let yb = fb.faceCenterY {
            let distance = ((xa - xb) * (xa - xb) + (ya - yb) * (ya - yb)).squareRoot()
            if distance > 0.12 { penalize(15, "Le cadrage du visage est différent.") }
        }
        if let wa = fa.faceWidth, let wb = fb.faceWidth, min(wa, wb) > 0, max(wa, wb) / min(wa, wb) > 1.25 {
            penalize(15, "La distance à l'appareil n'était pas la même.")
        }
        if let pa = fa.devicePitch, let pb = fb.devicePitch, abs(pa - pb) > 12 {
            penalize(15, "L'appareil n'était pas incliné de la même façon.")
        } else if let ra = fa.deviceRoll, let rb = fb.deviceRoll, abs(ra - rb) > 12 {
            penalize(10, "L'appareil n'était pas tenu de la même façon.")
        }

        if daysApart < 28 {
            reasons.append("Moins de 4 semaines séparent ces photos : les différences visibles viennent surtout des conditions de prise de vue.")
        }

        score = max(0, score)
        let level: ComparabilityReport.Level = score >= 75 ? .high : (score >= 50 ? .medium : .low)
        return ComparabilityReport(level: level, score: score, reasons: reasons, daysApart: daysApart)
    }
}
