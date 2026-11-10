import Foundation

/// Échelle de stade **choisie par l'utilisateur lui-même**. L'application ne classe jamais automatiquement
/// une alopécie : cette valeur est une auto-évaluation utilisée pour adapter le contenu éducatif.
public enum HairStageScale: String, Codable, Sendable, CaseIterable {
    /// Échelle de Hamilton-Norwood (calvitie masculine), stades 1 à 7.
    case norwood
    /// Échelle de Ludwig (perte de densité féminine), stades 1 à 3.
    case ludwig

    public var name: String {
        switch self {
        case .norwood: "Échelle de Norwood"
        case .ludwig: "Échelle de Ludwig"
        }
    }

    public var stages: ClosedRange<Int> {
        switch self {
        case .norwood: 1...7
        case .ludwig: 1...3
        }
    }

    public static func preferred(for sex: BiologicalSex) -> HairStageScale {
        sex == .female ? .ludwig : .norwood
    }
}

public struct SelfAssessedStage: Codable, Hashable, Sendable {
    public var scale: HairStageScale
    /// `nil` signifie « Je ne sais pas ».
    public var stage: Int?

    public init(scale: HairStageScale, stage: Int?) {
        self.scale = scale
        if let stage, scale.stages.contains(stage) {
            self.stage = stage
        } else {
            self.stage = nil
        }
    }
}

public struct HealthDetails: Codable, Hashable, Sendable {
    public var diagnosis: KnownDiagnosis?
    public var treatments: Set<DeclaredTreatment>
    public var hasRecentBloodTest: Bool?
    public var knownDeficiencies: Set<KnownDeficiency>
    public var restrictions: Set<DietaryRestriction>
    public var pregnancy: PregnancyStatus?
    public var symptoms: Set<ReportedSymptom>

    public init(
        diagnosis: KnownDiagnosis? = nil,
        treatments: Set<DeclaredTreatment> = [],
        hasRecentBloodTest: Bool? = nil,
        knownDeficiencies: Set<KnownDeficiency> = [],
        restrictions: Set<DietaryRestriction> = [],
        pregnancy: PregnancyStatus? = nil,
        symptoms: Set<ReportedSymptom> = []
    ) {
        self.diagnosis = diagnosis
        self.treatments = treatments
        self.hasRecentBloodTest = hasRecentBloodTest
        self.knownDeficiencies = knownDeficiencies
        self.restrictions = restrictions
        self.pregnancy = pregnancy
        self.symptoms = symptoms
    }
}

public struct Consents: Codable, Hashable, Sendable {
    /// Date à laquelle l'utilisateur a reconnu que Growtin' est une application de bien-être.
    public var wellnessDisclaimerAcceptedAt: Date?
    /// Autorise l'assistant IA à utiliser l'historique de l'utilisateur. Désactivé par défaut.
    public var aiPersonalization: Bool
    /// Autorise l'utilisation anonymisée pour améliorer les modèles. Toujours désactivé par défaut, jamais requis.
    public var modelImprovement: Bool
    /// Date à laquelle l'utilisateur a accepté que ses questions au Coach soient envoyées au serveur et au fournisseur d'IA.
    public var coachConsentAt: Date?

    public init(wellnessDisclaimerAcceptedAt: Date? = nil, aiPersonalization: Bool = false, modelImprovement: Bool = false,
                coachConsentAt: Date? = nil) {
        self.wellnessDisclaimerAcceptedAt = wellnessDisclaimerAcceptedAt
        self.aiPersonalization = aiPersonalization
        self.modelImprovement = modelImprovement
        self.coachConsentAt = coachConsentAt
    }
}

/// Toutes les réponses de l'onboarding, modifiables ensuite depuis le profil.
public struct UserProfile: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var firstName: String?
    public var sex: BiologicalSex
    public var age: Int
    public var heightCm: Int?
    public var weightKg: Int?

    public var hairLossDuration: HairLossDuration
    public var triggers: Set<PerceivedTrigger>
    public var familyHistory: FamilyHistory
    public var stage: SelfAssessedStage
    public var zones: Set<ScalpZone>
    public var goals: Set<PersonalGoal>

    public var sleepHours: Double
    public var sleepQuality: SleepQuality
    public var stress: StressLevel
    public var diet: DietPattern
    public var mealRegularity: MealRegularity
    public var activity: ActivityLevel

    public var washFrequency: WashFrequency
    public var wearsTightHairstyles: Bool
    public var usesHeatStyling: Bool
    public var products: Set<HairProduct>

    public var health: HealthDetails
    public var photoFrequency: PhotoFrequency
    public var consents: Consents
    public var programStartDate: Date

    public init(
        firstName: String? = nil,
        sex: BiologicalSex = .unspecified,
        age: Int = 30,
        heightCm: Int? = nil,
        weightKg: Int? = nil,
        hairLossDuration: HairLossDuration = .unsure,
        triggers: Set<PerceivedTrigger> = [],
        familyHistory: FamilyHistory = .unknown,
        stage: SelfAssessedStage = SelfAssessedStage(scale: .norwood, stage: nil),
        zones: Set<ScalpZone> = [],
        goals: Set<PersonalGoal> = [],
        sleepHours: Double = 7,
        sleepQuality: SleepQuality = .fair,
        stress: StressLevel = .moderate,
        diet: DietPattern = .omnivore,
        mealRegularity: MealRegularity = .regular,
        activity: ActivityLevel = .light,
        washFrequency: WashFrequency = .everyOtherDay,
        wearsTightHairstyles: Bool = false,
        usesHeatStyling: Bool = false,
        products: Set<HairProduct> = [],
        health: HealthDetails = HealthDetails(),
        photoFrequency: PhotoFrequency = .everyFourWeeks,
        consents: Consents = Consents(),
        programStartDate: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.firstName = firstName
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.hairLossDuration = hairLossDuration
        self.triggers = triggers
        self.familyHistory = familyHistory
        self.stage = stage
        self.zones = zones
        self.goals = goals
        self.sleepHours = sleepHours
        self.sleepQuality = sleepQuality
        self.stress = stress
        self.diet = diet
        self.mealRegularity = mealRegularity
        self.activity = activity
        self.washFrequency = washFrequency
        self.wearsTightHairstyles = wearsTightHairstyles
        self.usesHeatStyling = usesHeatStyling
        self.products = products
        self.health = health
        self.photoFrequency = photoFrequency
        self.consents = consents
        self.programStartDate = programStartDate
    }

    /// Prénom à afficher, nettoyé. `nil` si l'utilisateur n'en a pas donné.
    public var displayName: String? {
        guard let trimmed = firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public var isPregnantOrBreastfeeding: Bool {
        health.pregnancy == .pregnant || health.pregnancy == .breastfeeding
    }

    /// Repère protéique de l'EFSA (0,83 g/kg/jour pour un adulte), uniquement si le poids a été fourni.
    /// Ce n'est pas un besoin « capillaire » : c'est la référence générale de la population adulte.
    public var proteinReferenceGrams: Int? {
        guard let weightKg, weightKg > 0, age >= 18 else { return nil }
        return Int((Double(weightKg) * 0.83).rounded())
    }
}
