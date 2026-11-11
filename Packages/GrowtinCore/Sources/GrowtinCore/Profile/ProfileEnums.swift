import Foundation

/// Protocole commun aux choix proposés dans l'onboarding : un libellé localisé et un ordre stable.
public protocol LabeledOption: CaseIterable, Codable, Hashable, Sendable, Identifiable where AllCases: RandomAccessCollection {
    var label: String { get }
}

extension LabeledOption where Self: RawRepresentable, RawValue == String {
    public var id: String { rawValue }
}

// MARK: - Profil général

public enum BiologicalSex: String, LabeledOption {
    case male, female, unspecified

    public var label: String {
        switch self {
        case .male: "Homme"
        case .female: "Femme"
        case .unspecified: "Je préfère ne pas répondre"
        }
    }
}

public enum HairLossDuration: String, LabeledOption {
    case lessThan3Months, threeTo6Months, sixMonthsTo2Years, twoTo5Years, moreThan5Years, unsure

    public var label: String {
        switch self {
        case .lessThan3Months: "Moins de 3 mois"
        case .threeTo6Months: "3 à 6 mois"
        case .sixMonthsTo2Years: "6 mois à 2 ans"
        case .twoTo5Years: "2 à 5 ans"
        case .moreThan5Years: "Plus de 5 ans"
        case .unsure: "Je ne sais pas"
        }
    }
}

public enum PerceivedTrigger: String, LabeledOption {
    case stress, postpartum, diet, genetics, illnessOrTreatment, hairstyleTension, other, unknown

    public var label: String {
        switch self {
        case .stress: "Stress"
        case .postpartum: "Post-partum"
        case .diet: "Alimentation"
        case .genetics: "Génétique / hérédité"
        case .illnessOrTreatment: "Maladie / traitement récent"
        case .hairstyleTension: "Coiffures serrées"
        case .other: "Autre"
        case .unknown: "Je ne sais pas"
        }
    }

    public var symbol: String {
        switch self {
        case .stress: "brain.head.profile"
        case .postpartum: "figure.and.child.holdinghands"
        case .diet: "fork.knife"
        case .genetics: "person.2"
        case .illnessOrTreatment: "cross.case"
        case .hairstyleTension: "comb"
        case .other: "ellipsis.circle"
        case .unknown: "questionmark.circle"
        }
    }
}

public enum FamilyHistory: String, LabeledOption {
    case none, fatherSide, motherSide, bothSides, unknown

    public var label: String {
        switch self {
        case .none: "Aucun antécédent connu"
        case .fatherSide: "Côté paternel"
        case .motherSide: "Côté maternel"
        case .bothSides: "Des deux côtés"
        case .unknown: "Je ne sais pas"
        }
    }
}

public enum ScalpZone: String, LabeledOption {
    case frontalHairline, leftTemple, rightTemple, top, vertex, centralPart, diffuse

    public var label: String {
        switch self {
        case .frontalHairline: "Ligne frontale"
        case .leftTemple: "Tempe gauche"
        case .rightTemple: "Tempe droite"
        case .top: "Dessus du crâne"
        case .vertex: "Vertex (sommet)"
        case .centralPart: "Raie centrale"
        case .diffuse: "Chute diffuse"
        }
    }
}

public enum PersonalGoal: String, LabeledOption {
    case understand, buildHabits, trackEvolution, eatBetter, reduceStress, sleepBetter, prepareConsultation

    public var label: String {
        switch self {
        case .understand: "Comprendre ma situation"
        case .buildHabits: "Adopter de meilleures habitudes"
        case .trackEvolution: "Suivre mon évolution en photos"
        case .eatBetter: "Mieux manger"
        case .reduceStress: "Mieux gérer mon stress"
        case .sleepBetter: "Mieux dormir"
        case .prepareConsultation: "Préparer une consultation"
        }
    }

    public var symbol: String {
        switch self {
        case .understand: "book"
        case .buildHabits: "checklist"
        case .trackEvolution: "camera"
        case .eatBetter: "leaf"
        case .reduceStress: "wind"
        case .sleepBetter: "moon.zzz"
        case .prepareConsultation: "stethoscope"
        }
    }
}

// MARK: - Habitudes

public enum SleepQuality: String, LabeledOption {
    case poor, fair, good

    public var label: String {
        switch self {
        case .poor: "Mauvaise"
        case .fair: "Moyenne"
        case .good: "Bonne"
        }
    }
}

public enum StressLevel: String, LabeledOption, Comparable {
    case low, moderate, high, veryHigh

    public var label: String {
        switch self {
        case .low: "Faible"
        case .moderate: "Modéré"
        case .high: "Élevé"
        case .veryHigh: "Très élevé"
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public enum DietPattern: String, LabeledOption {
    case omnivore, flexitarian, pescatarian, vegetarian, vegan

    public var label: String {
        switch self {
        case .omnivore: "Omnivore"
        case .flexitarian: "Flexitarien"
        case .pescatarian: "Pescétarien"
        case .vegetarian: "Végétarien"
        case .vegan: "Végétalien"
        }
    }

    public var excludesMeat: Bool { self == .pescatarian || self == .vegetarian || self == .vegan }
}

public enum MealRegularity: String, LabeledOption {
    case regular, sometimesSkip, oftenSkip

    public var label: String {
        switch self {
        case .regular: "Repas réguliers"
        case .sometimesSkip: "Je saute parfois un repas"
        case .oftenSkip: "Je saute souvent des repas"
        }
    }
}

public enum ActivityLevel: String, LabeledOption, Comparable {
    case sedentary, light, moderate, active

    public var label: String {
        switch self {
        case .sedentary: "Sédentaire"
        case .light: "Légère (marche occasionnelle)"
        case .moderate: "Modérée (2 à 3 fois par semaine)"
        case .active: "Active (4 fois ou plus)"
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public enum WashFrequency: String, LabeledOption {
    case daily, everyOtherDay, twiceAWeek, weekly, lessOften

    public var label: String {
        switch self {
        case .daily: "Tous les jours"
        case .everyOtherDay: "Un jour sur deux"
        case .twiceAWeek: "2 fois par semaine"
        case .weekly: "1 fois par semaine"
        case .lessOften: "Moins souvent"
        }
    }
}

public enum HairProduct: String, LabeledOption {
    case gentleShampoo, antiDandruffShampoo, conditioner, oils, stylingProducts, supplements, other, none

    public var label: String {
        switch self {
        case .gentleShampoo: "Shampoing doux"
        case .antiDandruffShampoo: "Shampoing antipelliculaire"
        case .conditioner: "Après-shampoing / masque"
        case .oils: "Huiles"
        case .stylingProducts: "Produits coiffants"
        case .supplements: "Compléments alimentaires"
        case .other: "Autre"
        case .none: "Aucun"
        }
    }
}

// MARK: - Informations de santé facultatives

public enum KnownDiagnosis: String, LabeledOption {
    case none, androgeneticAlopecia, telogenEffluvium, alopeciaAreata, other

    public var label: String {
        switch self {
        case .none: "Aucun diagnostic posé"
        case .androgeneticAlopecia: "Alopécie androgénétique"
        case .telogenEffluvium: "Effluvium télogène"
        case .alopeciaAreata: "Pelade (alopecia areata)"
        case .other: "Autre diagnostic"
        }
    }
}

/// Traitements déclarés par l'utilisateur. L'application ne recommande, ne dose et n'interrompt jamais un traitement :
/// cette information sert uniquement à personnaliser le contenu éducatif et les rappels que l'utilisateur choisit.
public enum DeclaredTreatment: String, LabeledOption {
    case topicalMinoxidil, oralMinoxidil, finasteride, dutasteride, spironolactone, prp, lowLevelLight, transplant, other

    public var label: String {
        switch self {
        case .topicalMinoxidil: "Minoxidil local"
        case .oralMinoxidil: "Minoxidil oral"
        case .finasteride: "Finastéride"
        case .dutasteride: "Dutastéride"
        case .spironolactone: "Spironolactone"
        case .prp: "PRP"
        case .lowLevelLight: "Lumière / laser basse intensité"
        case .transplant: "Greffe capillaire"
        case .other: "Autre"
        }
    }
}

public enum KnownDeficiency: String, LabeledOption {
    case iron, vitaminD, zinc, vitaminB12, thyroid

    public var label: String {
        switch self {
        case .iron: "Fer / ferritine basse"
        case .vitaminD: "Vitamine D"
        case .zinc: "Zinc"
        case .vitaminB12: "Vitamine B12"
        case .thyroid: "Trouble thyroïdien"
        }
    }
}

public enum DietaryRestriction: String, LabeledOption {
    case gluten, lactose, nuts, peanuts, eggs, fish, shellfish, soy, sesame

    public var label: String {
        switch self {
        case .gluten: "Gluten"
        case .lactose: "Lactose"
        case .nuts: "Fruits à coque"
        case .peanuts: "Arachides"
        case .eggs: "Œufs"
        case .fish: "Poisson"
        case .shellfish: "Crustacés / mollusques"
        case .soy: "Soja"
        case .sesame: "Sésame"
        }
    }
}

public enum PregnancyStatus: String, LabeledOption {
    case notApplicable, pregnant, breastfeeding, postpartumUnder12Months

    public var label: String {
        switch self {
        case .notApplicable: "Non concernée"
        case .pregnant: "Enceinte"
        case .breastfeeding: "Allaitement"
        case .postpartumUnder12Months: "Accouchement il y a moins de 12 mois"
        }
    }
}

/// Signes qui justifient un avis médical. Ils ne sont jamais interprétés comme un diagnostic.
public enum ReportedSymptom: String, LabeledOption {
    case suddenHeavyShedding, patches, painOrBurning, rednessOrScaling, eyebrowOrLashLoss, otherBodySymptoms

    public var label: String {
        switch self {
        case .suddenHeavyShedding: "Chute brutale ou très abondante"
        case .patches: "Plaques sans cheveux"
        case .painOrBurning: "Douleur, brûlure ou démangeaisons intenses"
        case .rednessOrScaling: "Rougeurs, squames ou boutons"
        case .eyebrowOrLashLoss: "Perte de sourcils ou de cils"
        case .otherBodySymptoms: "Fatigue inhabituelle, perte de poids ou autres symptômes"
        }
    }
}

// MARK: - Suivi

public enum PhotoFrequency: String, LabeledOption {
    case everyTwoWeeks, everyFourWeeks, everyEightWeeks

    public var label: String {
        switch self {
        case .everyTwoWeeks: "Toutes les 2 semaines"
        case .everyFourWeeks: "Toutes les 4 semaines (recommandé)"
        case .everyEightWeeks: "Toutes les 8 semaines"
        }
    }

    public var days: Int {
        switch self {
        case .everyTwoWeeks: 14
        case .everyFourWeeks: 28
        case .everyEightWeeks: 56
        }
    }
}
