import Foundation

public enum MealType: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .breakfast: "Petit-déjeuner"
        case .lunch: "Déjeuner"
        case .dinner: "Dîner"
        case .snack: "Collation"
        }
    }

    public var pluralLabel: String {
        switch self {
        case .breakfast: "Petits-déjeuners"
        case .lunch: "Déjeuners"
        case .dinner: "Dîners"
        case .snack: "Collations"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: "cup.and.saucer"
        case .lunch: "fork.knife"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }
}

public enum Difficulty: String, Codable, Sendable {
    case easy, medium

    public var label: String {
        switch self {
        case .easy: "Facile"
        case .medium: "Intermédiaire"
        }
    }
}

public enum IngredientKind: String, Codable, Sendable {
    case plant, dairy, egg, fish, shellfish, meat, honey
}

public struct Ingredient: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let ciqualCode: Int
    public let kind: IngredientKind
    public let allergens: [DietaryRestriction]
    public let aisle: String
}

public struct RecipeIngredient: Codable, Hashable, Sendable {
    public let ingredientID: String
    /// Quantité affichée pour le nombre de portions de la recette.
    public let amount: Double
    public let unit: String
    /// Poids en grammes pour l'ensemble de la recette (calcul nutritionnel).
    public let grams: Double
}

public struct PhotoCredit: Codable, Hashable, Sendable {
    public let title: String?
    public let source: String
    public let license: String
    public let url: URL
}

public struct Recipe: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let meal: MealType
    public let servings: Int
    public let prepMinutes: Int
    public let cookMinutes: Int
    public let difficulty: Difficulty
    public let summary: String
    public let ingredients: [RecipeIngredient]
    public let steps: [String]
    public let substitutions: [String]
    /// Nom du fichier image embarqué dans l'application.
    public let photo: String
    public let photoCredit: PhotoCredit?

    public var totalMinutes: Int { prepMinutes + cookMinutes }
}

/// Nutriments suivis. Les valeurs de référence (VNR et apports de référence) sont celles
/// de l'annexe XIII du règlement (UE) n° 1169/2011, utilisées pour l'étiquetage.
public enum Nutrient: String, Codable, Sendable, CaseIterable, Identifiable {
    case energyKcal, protein, carbohydrates, sugars, fat, saturatedFat, fiber, salt
    case iron, zinc, vitaminC, vitaminD, vitaminB12, folate, calcium, magnesium, selenium
    case ala, epa, dha

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .energyKcal: "Énergie"
        case .protein: "Protéines"
        case .carbohydrates: "Glucides"
        case .sugars: "dont sucres"
        case .fat: "Lipides"
        case .saturatedFat: "dont acides gras saturés"
        case .fiber: "Fibres"
        case .salt: "Sel"
        case .iron: "Fer"
        case .zinc: "Zinc"
        case .vitaminC: "Vitamine C"
        case .vitaminD: "Vitamine D"
        case .vitaminB12: "Vitamine B12"
        case .folate: "Folates (B9)"
        case .calcium: "Calcium"
        case .magnesium: "Magnésium"
        case .selenium: "Sélénium"
        case .ala: "Oméga-3 ALA"
        case .epa: "Oméga-3 EPA"
        case .dha: "Oméga-3 DHA"
        }
    }

    public var unit: String {
        switch self {
        case .energyKcal: "kcal"
        case .protein, .carbohydrates, .sugars, .fat, .saturatedFat, .fiber, .salt, .ala, .epa, .dha: "g"
        case .iron, .zinc, .vitaminC, .calcium, .magnesium: "mg"
        case .vitaminD, .vitaminB12, .folate, .selenium: "µg"
        }
    }

    /// Valeur de référence journalière pour un adulte (règlement UE 1169/2011, annexe XIII), si elle existe.
    public var referenceValue: Double? {
        switch self {
        case .energyKcal: 2000
        case .protein: 50
        case .carbohydrates: 260
        case .sugars: 90
        case .fat: 70
        case .saturatedFat: 20
        case .salt: 6
        case .iron: 14
        case .zinc: 10
        case .vitaminC: 80
        case .vitaminD: 5
        case .vitaminB12: 2.5
        case .folate: 200
        case .calcium: 800
        case .magnesium: 375
        case .selenium: 55
        case .fiber, .ala, .epa, .dha: nil
        }
    }

    /// Rôle nutritionnel, formulé à partir des allégations autorisées (règlement UE 432/2012).
    /// Aucune formulation ne présente un nutriment comme un traitement de la chute de cheveux.
    public var role: String? {
        switch self {
        case .protein: "Les protéines contribuent au maintien de la masse musculaire. Le cheveu est principalement constitué de kératine, une protéine."
        case .iron: "Le fer contribue au transport normal de l'oxygène dans l'organisme. Une carence en fer fait partie des causes de chute étudiées : seule une prise de sang permet de la confirmer."
        case .zinc: "Le zinc contribue au maintien de cheveux normaux."
        case .vitaminC: "La vitamine C accroît l'absorption du fer."
        case .vitaminD: "La vitamine D contribue au fonctionnement normal du système immunitaire."
        case .vitaminB12: "La vitamine B12 contribue à réduire la fatigue."
        case .folate: "Les folates contribuent à la formation normale du sang."
        case .calcium: "Le calcium est nécessaire au maintien d'une ossature normale."
        case .magnesium: "Le magnésium contribue à réduire la fatigue."
        default: nil
        }
    }

    /// Nutriments présentés dans le tableau d'une recette.
    public static let macros: [Nutrient] = [.energyKcal, .protein, .carbohydrates, .sugars, .fat, .saturatedFat, .fiber, .salt]
    public static let micros: [Nutrient] = [.iron, .zinc, .vitaminC, .vitaminD, .vitaminB12, .folate, .calcium, .magnesium]
}

public struct Food: Codable, Hashable, Sendable {
    public let code: Int
    public let name: String
    public let energyComputed: Bool
    public let nutrientsPer100g: [String: Double?]

    public func value(_ nutrient: Nutrient) -> Double? {
        nutrientsPer100g[nutrient.rawValue] ?? nil
    }
}
