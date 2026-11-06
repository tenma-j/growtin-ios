import Foundation

public struct SafetyAlert: Hashable, Sendable, Identifiable {
    public enum Level: Int, Sendable, Comparable {
        /// Information utile, sans urgence.
        case information = 0
        /// Un avis médical est recommandé.
        case consultDoctor = 1
        /// Une aide immédiate est recommandée.
        case seekHelpNow = 2

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let id: String
    public let level: Level
    public let title: String
    public let message: String
}

/// Repère des signes justifiant un avis médical, **par des règles déterministes exécutées sur l'appareil**.
/// Ce dispositif ne pose aucun diagnostic : il oriente vers un professionnel de santé.
/// Il est volontairement indépendant de l'IA, afin de fonctionner hors ligne et sans abonnement.
public struct SafetyScreener: Sendable {
    public init() {}

    public static let distressAlert = SafetyAlert(
        id: "distress", level: .seekHelpNow,
        title: "Tu n'es pas seul·e",
        message: "Si tu traverses un moment difficile ou as des idées suicidaires, appelle le 3114 (numéro national de prévention du suicide, gratuit, 24 h/24) ou le 112 en cas d'urgence. Hors de France, contacte les urgences locales.")

    static let patchesAlert = SafetyAlert(
        id: "patches", level: .consultDoctor,
        title: "Consulte un dermatologue",
        message: "Des plaques sans cheveux peuvent correspondre à des affections qui nécessitent un examen médical, comme une pelade. Un dermatologue pourra poser un diagnostic.")

    static let inflammationAlert = SafetyAlert(
        id: "inflammation", level: .consultDoctor,
        title: "Un avis médical est recommandé",
        message: "Douleur, brûlure, rougeurs, squames ou boutons sur le cuir chevelu doivent être examinés par un médecin ou un dermatologue. Évite les massages tant que la zone est irritée.")

    static let suddenSheddingAlert = SafetyAlert(
        id: "sudden-shedding", level: .consultDoctor,
        title: "Une chute brutale mérite un avis médical",
        message: "Une chute soudaine ou très abondante peut avoir de nombreuses causes (stress, maladie, carence, médicament). Un médecin pourra en rechercher l'origine, éventuellement avec une prise de sang.")

    static let bodyHairAlert = SafetyAlert(
        id: "body-hair", level: .consultDoctor,
        title: "Parles-en à un médecin",
        message: "La perte de sourcils, de cils ou de poils sur d'autres zones justifie un examen médical.")

    static let systemicAlert = SafetyAlert(
        id: "systemic", level: .consultDoctor,
        title: "Parles-en à un médecin",
        message: "Une fatigue inhabituelle, une perte de poids ou d'autres symptômes associés à la chute justifient une consultation.")

    static let sideEffectAlert = SafetyAlert(
        id: "side-effect", level: .consultDoctor,
        title: "Effet indésirable possible",
        message: "Si tu penses ressentir un effet indésirable d'un traitement, contacte le médecin qui l'a prescrit ou ton pharmacien. N'arrête ni ne modifie un traitement sans leur avis.")

    static let pregnancyTreatmentAlert = SafetyAlert(
        id: "pregnancy-treatment", level: .consultDoctor,
        title: "Grossesse ou allaitement et traitement",
        message: "Certains traitements de la chute de cheveux sont déconseillés pendant la grossesse ou l'allaitement. Parles-en rapidement à ton médecin, sans modifier ton traitement de toi-même.")

    static let postpartumInfo = SafetyAlert(
        id: "postpartum", level: .information,
        title: "Chute après un accouchement",
        message: "Une chute plus importante dans les mois qui suivent un accouchement est fréquente et généralement temporaire. Consulte si elle se prolonge au-delà d'un an ou s'accompagne d'autres symptômes.")

    /// Alertes issues du profil déclaré.
    public func assess(profile: UserProfile) -> [SafetyAlert] {
        var alerts: [SafetyAlert] = []
        let symptoms = profile.health.symptoms
        if symptoms.contains(.patches) { alerts.append(Self.patchesAlert) }
        if symptoms.contains(.painOrBurning) || symptoms.contains(.rednessOrScaling) { alerts.append(Self.inflammationAlert) }
        if symptoms.contains(.suddenHeavyShedding) { alerts.append(Self.suddenSheddingAlert) }
        if symptoms.contains(.eyebrowOrLashLoss) { alerts.append(Self.bodyHairAlert) }
        if symptoms.contains(.otherBodySymptoms) { alerts.append(Self.systemicAlert) }

        let sensitiveTreatments: Set<DeclaredTreatment> = [.finasteride, .dutasteride, .oralMinoxidil, .topicalMinoxidil, .spironolactone]
        if profile.isPregnantOrBreastfeeding, !profile.health.treatments.isDisjoint(with: sensitiveTreatments) {
            alerts.append(Self.pregnancyTreatmentAlert)
        }
        if profile.health.pregnancy == .postpartumUnder12Months || profile.triggers.contains(.postpartum) {
            alerts.append(Self.postpartumInfo)
        }
        return Self.sorted(alerts)
    }

    /// Alertes issues d'un texte libre (journal, message au coach).
    public func assess(text: String) -> [SafetyAlert] {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return [] }
        var alerts: [SafetyAlert] = []
        for rule in Self.textRules where rule.keywords.contains(where: { normalized.contains($0) }) {
            alerts.append(rule.alert)
        }
        return Self.sorted(alerts)
    }

    struct TextRule {
        let alert: SafetyAlert
        let keywords: [String]
    }

    static let textRules: [TextRule] = [
        TextRule(alert: distressAlert, keywords: [
            "suicid", "envie de mourir", "me tuer", "en finir", "plus envie de vivre", "me faire du mal", "mettre fin a mes jours"
        ]),
        TextRule(alert: patchesAlert, keywords: ["plaque", "pelade", "zone sans cheveux", "zone lisse", "trou dans les cheveux"]),
        TextRule(alert: inflammationAlert, keywords: [
            "douleur", "douloureu", "brulure", "ca brule", "me brule", "rougeur", "pus", "croute", "squame",
            "inflamm", "suintement", "infection", "boutons sur le cuir chevelu"
        ]),
        TextRule(alert: suddenSheddingAlert, keywords: [
            "par poignee", "touffe", "chute brutale", "chute massive", "enormement de cheveux", "beaucoup plus que d'habitude"
        ]),
        TextRule(alert: bodyHairAlert, keywords: ["sourcil", "mes cils", "perte de cils"]),
        TextRule(alert: sideEffectAlert, keywords: [
            "effet secondaire", "effets secondaires", "effet indesirable", "effets indesirables", "libido", "erection",
            "palpitation", "gonflement", "oedeme", "vertige"
        ])
    ]

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
    }

    static func sorted(_ alerts: [SafetyAlert]) -> [SafetyAlert] {
        var seen = Set<String>()
        return alerts.filter { seen.insert($0.id).inserted }.sorted { $0.level > $1.level }
    }
}
