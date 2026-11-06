import Foundation

public enum DaySlot: String, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case morning, afternoon, evening

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .morning: "Matin"
        case .afternoon: "Après-midi"
        case .evening: "Soir"
        }
    }

    public var symbol: String {
        switch self {
        case .morning: "sunrise"
        case .afternoon: "sun.max"
        case .evening: "moon"
        }
    }

    /// Heure par défaut, en minutes depuis minuit.
    public var defaultMinuteOfDay: Int {
        switch self {
        case .morning: 8 * 60
        case .afternoon: 14 * 60
        case .evening: 21 * 60 + 30
        }
    }

    public static func slot(forMinuteOfDay minute: Int) -> DaySlot {
        switch minute {
        case ..<(12 * 60): .morning
        case ..<(18 * 60): .afternoon
        default: .evening
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// Façon dont une habitude se réalise dans l'application.
public enum HabitKind: String, Codable, Sendable {
    /// Simple case à cocher.
    case check
    /// Ouvre une séance de respiration guidée.
    case guidedBreathing
    /// Ouvre une séance de massage du cuir chevelu guidée.
    case guidedScalpMassage
    /// Ouvre le bilan du jour.
    case checkIn
}

/// Modèle d'habitude proposé par Growtin'. Les habitudes personnalisées de l'utilisateur n'ont pas de modèle.
public struct HabitTemplate: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let slot: DaySlot
    public let durationMinutes: Int?
    public let kind: HabitKind
    public let evidenceCardID: String?

    public init(id: String, title: String, detail: String, symbol: String, slot: DaySlot,
                durationMinutes: Int?, kind: HabitKind, evidenceCardID: String?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.slot = slot
        self.durationMinutes = durationMinutes
        self.kind = kind
        self.evidenceCardID = evidenceCardID
    }

    public var evidenceCard: EvidenceCard? { evidenceCardID.flatMap(EvidenceCatalog.card(id:)) }
}

public enum HabitCatalog {
    public static let proteinBreakfast = HabitTemplate(
        id: "protein-breakfast", title: "Petit-déjeuner avec des protéines",
        detail: "Œufs, yaourt, skyr, fromage blanc, tofu ou oléagineux.",
        symbol: "fork.knife", slot: .morning, durationMinutes: nil, kind: .check, evidenceCardID: EvidenceCatalog.proteinAtMeals.id)

    public static let ironVitaminC = HabitTemplate(
        id: "iron-vitamin-c", title: "Fer + vitamine C au déjeuner",
        detail: "Lentilles, pois chiches ou épinards, avec un agrume, un kiwi ou un poivron.",
        symbol: "leaf", slot: .afternoon, durationMinutes: nil, kind: .check, evidenceCardID: EvidenceCatalog.ironAndVitaminC.id)

    public static let seedsHandful = HabitTemplate(
        id: "seeds-handful", title: "Une poignée de graines ou d'oléagineux",
        detail: "Graines de courge, noix, amandes. Pas plus d'une à deux noix du Brésil par jour.",
        symbol: "circle.grid.3x3", slot: .afternoon, durationMinutes: nil, kind: .check, evidenceCardID: EvidenceCatalog.zincSeleniumFoods.id)

    public static let walk = HabitTemplate(
        id: "daily-walk", title: "Marche de 20 minutes",
        detail: "À ton rythme, idéalement à la lumière du jour.",
        symbol: "figure.walk", slot: .afternoon, durationMinutes: 20, kind: .check, evidenceCardID: EvidenceCatalog.dailyWalk.id)

    public static let breathing = HabitTemplate(
        id: "slow-breathing", title: "Respiration lente",
        detail: "Séance guidée : 5 secondes d'inspiration, 5 secondes d'expiration.",
        symbol: "wind", slot: .afternoon, durationMinutes: 3, kind: .guidedBreathing, evidenceCardID: EvidenceCatalog.slowBreathing.id)

    public static let scalpMassage = HabitTemplate(
        id: "scalp-massage", title: "Massage du cuir chevelu",
        detail: "Séance guidée de 4 minutes, du bout des doigts, sans frotter.",
        symbol: "hand.raised", slot: .evening, durationMinutes: 4, kind: .guidedScalpMassage, evidenceCardID: EvidenceCatalog.scalpMassage.id)

    public static let looseHairstyle = HabitTemplate(
        id: "loose-hairstyle", title: "Coiffure sans tension",
        detail: "Attache lâche, alterne les coiffures, évite de tirer sur les tempes.",
        symbol: "comb", slot: .morning, durationMinutes: nil, kind: .check, evidenceCardID: EvidenceCatalog.looseHairstyles.id)

    public static let gentleCare = HabitTemplate(
        id: "gentle-care", title: "Séchage doux",
        detail: "Température tiède ou à l'air libre, protection thermique si tu utilises un lisseur.",
        symbol: "wind.snow", slot: .morning, durationMinutes: nil, kind: .check, evidenceCardID: EvidenceCatalog.gentleHairCare.id)

    public static let windDown = HabitTemplate(
        id: "wind-down", title: "Coucher à heure régulière",
        detail: "Écrans rangés 30 minutes avant, même heure de coucher chaque soir.",
        symbol: "bed.double", slot: .evening, durationMinutes: nil, kind: .check, evidenceCardID: EvidenceCatalog.regularSleep.id)

    public static let prescribedTreatment = HabitTemplate(
        id: "prescribed-treatment", title: "Mon traitement prescrit",
        detail: "Selon la prescription de ton médecin. Growtin' ne modifie jamais un traitement.",
        symbol: "pills", slot: .morning, durationMinutes: nil, kind: .check, evidenceCardID: EvidenceCatalog.prescribedTreatmentReminder.id)

    public static let checkIn = HabitTemplate(
        id: "daily-check-in", title: "Bilan du jour",
        detail: "30 secondes : sommeil, stress et observations.",
        symbol: "square.and.pencil", slot: .evening, durationMinutes: 1, kind: .checkIn, evidenceCardID: EvidenceCatalog.dailyCheckIn.id)

    public static let all: [HabitTemplate] = [
        proteinBreakfast, looseHairstyle, gentleCare, prescribedTreatment, ironVitaminC, seedsHandful, walk,
        breathing, scalpMassage, windDown, checkIn
    ]

    public static func template(id: String) -> HabitTemplate? { all.first { $0.id == id } }
}
