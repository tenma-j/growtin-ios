import Foundation

/// Une habitude dans la routine de l'utilisateur.
public struct RoutineItem: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// Identifiant du modèle Growtin', ou `nil` pour une habitude créée par l'utilisateur.
    public let templateID: String?
    public var title: String
    public var detail: String
    public var symbol: String
    public var minuteOfDay: Int
    public var reminderEnabled: Bool
    /// Raison personnalisée et transparente pour laquelle cette habitude est proposée.
    public var reason: String?
    public let addedOn: DayKey
    /// Jour à partir duquel l'habitude ne fait plus partie de la routine (exclu du calcul de régularité).
    public var removedOn: DayKey?

    public init(id: UUID = UUID(), templateID: String?, title: String, detail: String, symbol: String,
                minuteOfDay: Int, reminderEnabled: Bool = false, reason: String? = nil,
                addedOn: DayKey, removedOn: DayKey? = nil) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.minuteOfDay = max(0, min(minuteOfDay, 24 * 60 - 1))
        self.reminderEnabled = reminderEnabled
        self.reason = reason
        self.addedOn = addedOn
        self.removedOn = removedOn
    }

    public init(template: HabitTemplate, reason: String?, addedOn: DayKey) {
        self.init(templateID: template.id, title: template.title, detail: template.detail, symbol: template.symbol,
                  minuteOfDay: template.slot.defaultMinuteOfDay, reason: reason, addedOn: addedOn)
    }

    public var template: HabitTemplate? { templateID.flatMap(HabitCatalog.template(id:)) }
    public var kind: HabitKind { template?.kind ?? .check }
    public var slot: DaySlot { DaySlot.slot(forMinuteOfDay: minuteOfDay) }
    public var isActive: Bool { removedOn == nil }

    /// L'habitude fait-elle partie de la routine ce jour-là ?
    public func isScheduled(on day: DayKey) -> Bool {
        guard day >= addedOn else { return false }
        if let removedOn { return day < removedOn }
        return true
    }

    public var timeLabel: String { String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60) }
}

/// Construit la routine initiale à partir des réponses de l'onboarding.
///
/// Principes :
/// - une routine courte (au plus `maximumItems` habitudes plus le bilan du jour), pour rester réaliste ;
/// - chaque habitude est justifiée par une raison qui cite la réponse de l'utilisateur ;
/// - aucune habitude n'est présentée comme un traitement de l'alopécie.
public struct RoutineEngine: Sendable {
    public static let maximumItems = 5

    public init() {}

    struct Candidate {
        let template: HabitTemplate
        let priority: Int
        let reason: String
    }

    public func initialRoutine(for profile: UserProfile, startingOn day: DayKey) -> [RoutineItem] {
        let chosen = candidates(for: profile)
            .sorted { $0.priority > $1.priority }
            .prefix(Self.maximumItems)

        var items = chosen.map { RoutineItem(template: $0.template, reason: $0.reason, addedOn: day) }
        items.append(RoutineItem(
            template: HabitCatalog.checkIn,
            reason: "Facultatif : quelques secondes pour garder une trace de ta journée. Tu peux le retirer à tout moment.",
            addedOn: day))
        return items.sorted { $0.minuteOfDay < $1.minuteOfDay }
    }

    func candidates(for profile: UserProfile) -> [Candidate] {
        var result: [Candidate] = []
        let hours = Self.format(hours: profile.sleepHours)

        // Traitement déclaré : simple rappel, jamais une recommandation.
        let medications: Set<DeclaredTreatment> = [.topicalMinoxidil, .oralMinoxidil, .finasteride, .dutasteride, .spironolactone]
        if !profile.health.treatments.isDisjoint(with: medications) {
            result.append(Candidate(
                template: HabitCatalog.prescribedTreatment, priority: 100,
                reason: "Tu as indiqué suivre un traitement prescrit. Ce rappel t'aide à le suivre tel que ton médecin l'a défini. Growtin' ne le modifie jamais."))
        }

        // Coiffures serrées : seul cas où une habitude prévient un type précis de chute.
        if profile.wearsTightHairstyles || profile.triggers.contains(.hairstyleTension) {
            result.append(Candidate(
                template: HabitCatalog.looseHairstyle, priority: 90,
                reason: "Tu as indiqué porter des coiffures serrées. Une tension répétée sur les racines peut provoquer une alopécie de traction, qui est évitable."))
        }

        // Sommeil.
        if profile.sleepHours < 7 {
            result.append(Candidate(
                template: HabitCatalog.windDown, priority: 80,
                reason: "Tu as indiqué dormir environ \(hours) par nuit. Améliorer la régularité et la durée de ton sommeil pourrait être bénéfique pour ton bien-être général. En revanche, cela ne constitue pas un traitement démontré contre l'alopécie androgénétique."))
        } else if profile.sleepQuality == .poor || profile.goals.contains(.sleepBetter) {
            result.append(Candidate(
                template: HabitCatalog.windDown, priority: 55,
                reason: "Tu as indiqué vouloir mieux dormir. Un horaire de coucher régulier est l'un des leviers les plus simples pour ton bien-être. Ce n'est pas un traitement de la chute de cheveux."))
        }

        // Stress.
        if profile.stress >= .high || profile.triggers.contains(.stress) || profile.goals.contains(.reduceStress) {
            let detail = profile.stress >= .high
                ? "Tu as indiqué un niveau de stress \(profile.stress.label.lowercased())."
                : "Tu as cité le stress parmi tes préoccupations."
            result.append(Candidate(
                template: HabitCatalog.breathing, priority: profile.stress >= .high ? 75 : 50,
                reason: "\(detail) Un stress intense fait partie des déclencheurs connus d'une chute temporaire (effluvium télogène). La respiration lente aide à gérer le stress ressenti, sans effet démontré sur les cheveux."))
        }

        // Nutrition de base.
        let proteinReason: String
        switch profile.mealRegularity {
        case .oftenSkip, .sometimesSkip:
            proteinReason = "Tu as indiqué sauter des repas. Commencer la journée avec une source de protéines aide à couvrir tes apports de référence, sans être un traitement de la chute."
        case .regular:
            if let grams = profile.proteinReferenceGrams {
                proteinReason = "Ta référence protéique générale est d'environ \(grams) g par jour (0,83 g par kg selon l'EFSA). Un petit-déjeuner protéiné aide à l'atteindre. Au-delà de tes besoins, plus de protéines n'apporte pas de bénéfice démontré sur les cheveux."
            } else {
                proteinReason = "Répartir les protéines sur la journée aide à couvrir tes apports de référence. Au-delà de tes besoins, plus de protéines n'apporte pas de bénéfice démontré sur les cheveux."
            }
        }
        result.append(Candidate(template: HabitCatalog.proteinBreakfast, priority: profile.mealRegularity == .regular ? 45 : 65, reason: proteinReason))

        if profile.diet.excludesMeat || profile.health.knownDeficiencies.contains(.iron) {
            let reason = profile.health.knownDeficiencies.contains(.iron)
                ? "Tu as indiqué une carence en fer connue. L'alimentation complète le suivi de ton médecin, qui reste seul juge d'une éventuelle supplémentation."
                : "Avec une alimentation \(profile.diet.label.lowercased()), associer fer végétal et vitamine C améliore l'absorption du fer."
            result.append(Candidate(template: HabitCatalog.ironVitaminC, priority: 70, reason: reason))
        }

        if profile.goals.contains(.eatBetter) || profile.diet == .vegan {
            let allergic = !profile.health.restrictions.isDisjoint(with: [.nuts, .peanuts])
            if !allergic {
                result.append(Candidate(
                    template: HabitCatalog.seedsHandful, priority: 40,
                    reason: "Les graines et oléagineux apportent du zinc et du sélénium, qui contribuent au maintien de cheveux normaux. Inutile d'en faire plus : un excès de sélénium peut lui-même faire chuter les cheveux."))
            }
        }

        // Activité.
        if profile.activity <= .light {
            result.append(Candidate(
                template: HabitCatalog.walk, priority: 60,
                reason: "Tu as indiqué une activité \(profile.activity == .sedentary ? "plutôt sédentaire" : "légère"). L'OMS recommande au moins 150 minutes d'activité modérée par semaine pour la santé générale. Aucun effet direct sur la repousse n'est démontré."))
        }

        if profile.usesHeatStyling {
            result.append(Candidate(
                template: HabitCatalog.gentleCare, priority: 35,
                reason: "Tu as indiqué utiliser des appareils chauffants. Limiter la chaleur réduit la casse de la fibre, sans agir sur la chute à la racine."))
        }

        // Massage : preuves limitées, proposé seulement sans signe d'irritation du cuir chevelu.
        let irritated = !profile.health.symptoms.isDisjoint(with: [.painOrBurning, .rednessOrScaling])
        if !irritated {
            result.append(Candidate(
                template: HabitCatalog.scalpMassage, priority: 30,
                reason: "Un moment de détente que beaucoup apprécient. Les preuves d'un effet sur les cheveux sont limitées (une petite étude de 9 personnes) : considère-le comme un geste de bien-être."))
        }

        return result
    }

    static func format(hours: Double) -> String {
        let rounded = (hours * 2).rounded() / 2
        if rounded == rounded.rounded() { return "\(Int(rounded)) heures" }
        return "\(Int(rounded)) h 30"
    }
}
