import Foundation

public enum CoachRole: String, Codable, Sendable {
    case user, assistant
}

public struct CoachMessage: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let role: CoachRole
    public let content: String
    public let citations: [String]
    public let createdAt: Date
    /// Réponse fabriquée localement (démonstration, détresse) : jamais envoyée au serveur comme historique du modèle.
    public let isLocal: Bool

    public init(id: UUID = UUID(), role: CoachRole, content: String, citations: [String] = [], createdAt: Date = Date(), isLocal: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.citations = citations
        self.createdAt = createdAt
        self.isLocal = isLocal
    }
}

public struct CoachQuota: Codable, Hashable, Sendable {
    public let used: Int
    public let limit: Int
    public let premium: Bool

    public init(used: Int, limit: Int, premium: Bool) {
        self.used = used
        self.limit = limit
        self.premium = premium
    }

    public var remaining: Int { max(0, limit - used) }
}

/// Segment d'une réponse : du texte ou une citation `[S:identifiant]`.
public enum CoachSegment: Hashable, Sendable {
    case text(String)
    case citation(String)
}

public enum CoachText {
    /// Découpe une réponse en texte et citations, pour afficher les sources comme des pastilles.
    public static func segments(_ text: String) -> [CoachSegment] {
        var result: [CoachSegment] = []
        var rest = Substring(text)
        while let start = rest.range(of: "[S:") {
            guard let end = rest[start.upperBound...].firstIndex(of: "]") else { break }
            let id = String(rest[start.upperBound..<end])
            let isValidID = !id.isEmpty && id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
            let before = String(rest[..<start.lowerBound])
            if isValidID {
                if !before.isEmpty { result.append(.text(before)) }
                result.append(.citation(id))
            } else {
                result.append(.text(before + String(rest[start.lowerBound...end])))
            }
            rest = rest[rest.index(after: end)...]
        }
        if !rest.isEmpty { result.append(.text(String(rest))) }
        return result
    }

    /// Texte sans les marqueurs de citation (lecture vocale, partage).
    public static func plain(_ text: String) -> String {
        segments(text).compactMap { segment in
            if case .text(let value) = segment { return value }
            return nil
        }
        .joined()
        .replacingOccurrences(of: " .", with: ".")
        .replacingOccurrences(of: "  ", with: " ")
    }
}

/// Construit le contexte transmis au Coach. Uniquement si l'utilisateur a activé la personnalisation,
/// et seulement des informations utiles, sans identifiant ni prénom.
public enum CoachContextBuilder {
    public static func build(profile: UserProfile, routine: [RoutineItem], consistency7Days: Double?,
                             checkIns: [DailyCheckIn], photoCount: Int, today: DayKey) -> String {
        var lines: [String] = []
        let ageRange = "\(profile.age / 10 * 10)-\(profile.age / 10 * 10 + 9) ans"
        lines.append("Profil : \(profile.sex.label.lowercased()), \(ageRange).")
        if let stage = profile.stage.stage {
            lines.append("Stade auto-évalué : \(profile.stage.scale.name), stade \(stage) (auto-évaluation, pas un diagnostic).")
        }
        lines.append("Chute depuis : \(profile.hairLossDuration.label.lowercased()). Antécédents familiaux : \(profile.familyHistory.label.lowercased()).")
        if !profile.triggers.isEmpty {
            lines.append("Déclencheurs perçus : \(labels(profile.triggers)).")
        }
        if !profile.zones.isEmpty { lines.append("Zones concernées : \(labels(profile.zones)).") }
        if !profile.goals.isEmpty { lines.append("Objectifs : \(labels(profile.goals)).") }
        lines.append("Sommeil habituel : \(profile.sleepHours.formatted()) h, qualité \(profile.sleepQuality.label.lowercased()). Stress : \(profile.stress.label.lowercased()).")
        lines.append("Alimentation : \(profile.diet.label.lowercased()), \(profile.mealRegularity.label.lowercased()). Activité : \(profile.activity.label.lowercased()).")
        if !profile.health.restrictions.isEmpty { lines.append("Allergies ou aliments évités : \(labels(profile.health.restrictions)).") }
        if let diagnosis = profile.health.diagnosis, diagnosis != .none { lines.append("Diagnostic déclaré : \(diagnosis.label).") }
        if !profile.health.treatments.isEmpty { lines.append("Traitements déclarés : \(labels(profile.health.treatments)).") }
        if !profile.health.knownDeficiencies.isEmpty { lines.append("Carences déclarées : \(labels(profile.health.knownDeficiencies)).") }
        if let pregnancy = profile.health.pregnancy, pregnancy != .notApplicable { lines.append("Situation : \(pregnancy.label.lowercased()).") }
        if !profile.health.symptoms.isEmpty { lines.append("Signes déclarés : \(labels(profile.health.symptoms)).") }

        let active = routine.filter(\.isActive).map(\.title)
        if !active.isEmpty { lines.append("Routine choisie : \(active.joined(separator: ", ")).") }
        if let consistency7Days {
            lines.append("Régularité des 7 derniers jours : \(Int((consistency7Days * 100).rounded())) %.")
        }
        lines.append("Photos de suivi enregistrées : \(photoCount).")

        let recent = checkIns.filter { $0.day <= today }.sorted { $0.day > $1.day }.prefix(7)
        if !recent.isEmpty {
            lines.append("Derniers bilans du jour :")
            for checkIn in recent {
                var parts: [String] = []
                if let hours = checkIn.sleepHours { parts.append("sommeil \(hours.formatted()) h") }
                if let stress = checkIn.stress { parts.append("stress \(stress)/5") }
                if let shedding = checkIn.shedding { parts.append("chute perçue : \(shedding.label.lowercased())") }
                let note = checkIn.note.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty { parts.append("note : « \(String(note.prefix(200))) »") }
                if !parts.isEmpty { lines.append("- \(checkIn.day) : \(parts.joined(separator: ", "))") }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func labels<T: LabeledOption>(_ values: Set<T>) -> String {
        T.allCases.filter(values.contains).map { $0.label.lowercased() }.joined(separator: ", ")
    }
}

public enum CoachSuggestions {
    public static let starters: [String] = [
        "Qu'est-ce qui peut provoquer une chute de cheveux ?",
        "Mon alimentation couvre-t-elle mes besoins ?",
        "Comment mieux gérer mon stress au quotidien ?",
        "Que disent les études sur le minoxidil ?",
        "Quand devrais-je consulter un dermatologue ?"
    ]
}
