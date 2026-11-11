import Foundation

public enum NutritionDatabaseError: Error, Equatable {
    case resourceMissing(String)
    case unknownIngredient(recipe: String, ingredient: String)
    case unknownFood(ingredient: String, code: Int)
}

/// Recettes, ingrédients et extrait de la table Ciqual 2020 embarqués dans l'application.
public struct NutritionDatabase: Sendable {
    public let recipes: [Recipe]
    public let ingredients: [String: Ingredient]
    public let foods: [Int: Food]
    public let sourceLabel: String

    struct Subset: Decodable {
        let source: String
        let foods: [Food]
    }

    public init(recipes: [Recipe], ingredients: [Ingredient], foods: [Food], sourceLabel: String) throws {
        self.recipes = recipes
        self.ingredients = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.id, $0) })
        self.foods = Dictionary(uniqueKeysWithValues: foods.map { ($0.code, $0) })
        self.sourceLabel = sourceLabel
        for recipe in recipes {
            for item in recipe.ingredients {
                guard let ingredient = self.ingredients[item.ingredientID] else {
                    throw NutritionDatabaseError.unknownIngredient(recipe: recipe.id, ingredient: item.ingredientID)
                }
                guard self.foods[ingredient.ciqualCode] != nil else {
                    throw NutritionDatabaseError.unknownFood(ingredient: ingredient.id, code: ingredient.ciqualCode)
                }
            }
        }
    }

    public static func bundled() throws -> NutritionDatabase {
        func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
                throw NutritionDatabaseError.resourceMissing(name)
            }
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        }
        let subset = try load("ciqual-subset", as: Subset.self)
        return try NutritionDatabase(recipes: try load("recipes", as: [Recipe].self),
                                     ingredients: try load("ingredients", as: [Ingredient].self),
                                     foods: subset.foods, sourceLabel: subset.source)
    }

    public func recipe(id: String) -> Recipe? { recipes.first { $0.id == id } }

    public func ingredients(of recipe: Recipe) -> [Ingredient] {
        recipe.ingredients.compactMap { ingredients[$0.ingredientID] }
    }
}

// MARK: - Calcul nutritionnel

public struct NutrientAmount: Hashable, Sendable {
    public let amount: Double
    /// Part du poids de la recette pour laquelle la table fournit une valeur (0…1).
    public let coverage: Double

    /// En dessous de 70 % de couverture, la valeur n'est pas affichée : elle serait trompeuse.
    public var isReliable: Bool { coverage >= 0.7 }
}

public struct NutritionFacts: Hashable, Sendable {
    public let values: [Nutrient: NutrientAmount]
    public let gramsPerServing: Double
    /// Au moins un aliment a une énergie recalculée à partir des macronutriments.
    public let containsComputedEnergy: Bool

    public func amount(_ nutrient: Nutrient) -> Double? {
        guard let value = values[nutrient], value.isReliable else { return nil }
        return value.amount
    }

    /// Part de la valeur de référence journalière apportée par une portion.
    public func percentOfReference(_ nutrient: Nutrient) -> Double? {
        guard let amount = amount(nutrient), let reference = nutrient.referenceValue else { return nil }
        return amount / reference
    }

    /// Micronutriments dont une portion apporte au moins 15 % de la valeur de référence
    /// (seuil de « quantité significative » de l'étiquetage européen).
    public var highlights: [Nutrient] {
        ([.protein] + Nutrient.micros).filter { nutrient in
            guard let percent = percentOfReference(nutrient) else { return false }
            return nutrient == .protein ? percent >= 0.3 : percent >= 0.15
        }
    }
}

public enum NutritionCalculator {
    public static func facts(for recipe: Recipe, in database: NutritionDatabase) -> NutritionFacts {
        let servings = Double(max(recipe.servings, 1))
        let totalGrams = recipe.ingredients.reduce(0) { $0 + $1.grams }
        var values: [Nutrient: NutrientAmount] = [:]
        var computedEnergy = false
        for nutrient in Nutrient.allCases {
            var total = 0.0
            var coveredGrams = 0.0
            for item in recipe.ingredients {
                guard let ingredient = database.ingredients[item.ingredientID],
                      let food = database.foods[ingredient.ciqualCode] else { continue }
                if let per100 = food.value(nutrient) {
                    total += per100 * item.grams / 100
                    coveredGrams += item.grams
                    if nutrient == .energyKcal, food.energyComputed { computedEnergy = true }
                }
            }
            values[nutrient] = NutrientAmount(amount: total / servings, coverage: totalGrams > 0 ? coveredGrams / totalGrams : 0)
        }
        return NutritionFacts(values: values, gramsPerServing: totalGrams / servings, containsComputedEnergy: computedEnergy)
    }
}

// MARK: - Personnalisation

public struct RecipeTags: Hashable, Sendable {
    public let isVegetarian: Bool
    public let isVegan: Bool
    public let isPescatarian: Bool
    public let allergens: Set<DietaryRestriction>

    public var labels: [String] {
        var result: [String] = []
        if isVegan { result.append("Végétalien") } else if isVegetarian { result.append("Végétarien") }
        if !allergens.contains(.gluten) { result.append("Sans gluten") }
        if !allergens.contains(.lactose) { result.append("Sans lactose") }
        return result
    }
}

public enum RecipeFilter {
    public static func tags(for recipe: Recipe, in database: NutritionDatabase) -> RecipeTags {
        let items = database.ingredients(of: recipe)
        let kinds = Set(items.map(\.kind))
        let animal: Set<IngredientKind> = [.dairy, .egg, .fish, .shellfish, .meat, .honey]
        return RecipeTags(
            isVegetarian: kinds.isDisjoint(with: [.fish, .shellfish, .meat]),
            isVegan: kinds.isDisjoint(with: animal),
            isPescatarian: !kinds.contains(.meat),
            allergens: Set(items.flatMap(\.allergens)))
    }

    /// Recettes compatibles avec le régime et les restrictions déclarés.
    public static func eligible(_ recipes: [Recipe], diet: DietPattern, restrictions: Set<DietaryRestriction>,
                                in database: NutritionDatabase) -> [Recipe] {
        recipes.filter { recipe in
            let tags = tags(for: recipe, in: database)
            let dietOK: Bool
            switch diet {
            case .omnivore, .flexitarian: dietOK = true
            case .pescatarian: dietOK = tags.isPescatarian
            case .vegetarian: dietOK = tags.isVegetarian
            case .vegan: dietOK = tags.isVegan
            }
            return dietOK && tags.allergens.isDisjoint(with: restrictions)
        }
    }

    public static func search(_ recipes: [Recipe], query: String, in database: NutritionDatabase) -> [Recipe] {
        let words = normalize(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return recipes }
        return recipes.filter { recipe in
            let haystack = normalize(([recipe.title, recipe.summary, recipe.meal.label]
                                      + database.ingredients(of: recipe).map(\.name)).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "œ", with: "oe")
            .lowercased()
    }
}

// MARK: - Recette du jour et planning

public enum MealPlanner {
    /// Recette du jour : déterministe pour une date donnée, variée d'un jour à l'autre.
    public static func recipeOfTheDay(_ recipes: [Recipe], day: DayKey, calendar: Calendar = .current) -> Recipe? {
        let candidates = recipes.filter { $0.meal == .lunch || $0.meal == .dinner }.sorted { $0.id < $1.id }
        guard !candidates.isEmpty else { return recipes.first }
        let ordinal = DayKey(year: 2000, month: 1, day: 1).days(until: day, calendar: calendar)
        return candidates[((ordinal % candidates.count) + candidates.count) % candidates.count]
    }

    /// Semaine de menus : une recette différente par repas tant que la bibliothèque le permet.
    public static func weekPlan(_ recipes: [Recipe], startingOn start: DayKey, meals: [MealType] = [.breakfast, .lunch, .dinner],
                                calendar: Calendar = .current) -> [PlannedMeal] {
        var plan: [PlannedMeal] = []
        let weekSeed = UInt64(truncatingIfNeeded: abs(DayKey(year: 2000, month: 1, day: 1).days(until: start, calendar: calendar) / 7) + 1)
        for meal in meals {
            var pool = shuffled(recipes.filter { $0.meal == meal }.sorted { $0.id < $1.id }, seed: weekSeed &* 31 &+ UInt64(meal.hashValueStable))
            guard !pool.isEmpty else { continue }
            let original = pool
            for offset in 0..<7 {
                if pool.isEmpty { pool = original }
                let recipe = pool.removeFirst()
                plan.append(PlannedMeal(day: start.adding(days: offset, calendar: calendar), meal: meal, recipeID: recipe.id, servings: 1))
            }
        }
        return plan.sorted { ($0.day, $0.meal.order) < ($1.day, $1.meal.order) }
    }

    static func shuffled<T>(_ items: [T], seed: UInt64) -> [T] {
        var state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        var result = items
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let j = Int((state >> 33) % UInt64(i + 1))
            result.swapAt(i, j)
        }
        return result
    }
}

public struct PlannedMeal: Codable, Hashable, Sendable, Identifiable {
    public let day: DayKey
    public let meal: MealType
    public var recipeID: String
    public var servings: Int

    public init(day: DayKey, meal: MealType, recipeID: String, servings: Int) {
        self.day = day
        self.meal = meal
        self.recipeID = recipeID
        self.servings = max(1, servings)
    }

    public var id: String { "\(day)-\(meal.rawValue)" }
}

extension MealType {
    var order: Int { MealType.allCases.firstIndex(of: self)! }
    /// Valeur stable d'une exécution à l'autre (contrairement à `hashValue`).
    var hashValueStable: Int { order + 1 }
}

// MARK: - Liste de courses

public struct ShoppingItem: Hashable, Sendable, Identifiable {
    public let ingredientID: String
    public let name: String
    public let aisle: String
    public let quantities: [String]
    public var id: String { ingredientID }
}

public enum ShoppingListBuilder {
    /// Regroupe les ingrédients des repas prévus, quantités ajustées au nombre de portions.
    public static func build(_ meals: [PlannedMeal], in database: NutritionDatabase) -> [ShoppingItem] {
        var totals: [String: [String: Double]] = [:]
        for planned in meals {
            guard let recipe = database.recipe(id: planned.recipeID) else { continue }
            let factor = Double(planned.servings) / Double(max(recipe.servings, 1))
            for item in recipe.ingredients {
                totals[item.ingredientID, default: [:]][QuantityFormatter.singular(item.unit), default: 0] += item.amount * factor
            }
        }
        return totals.compactMap { id, units in
            guard let ingredient = database.ingredients[id] else { return nil }
            let quantities = units.sorted { $0.key < $1.key }.map { QuantityFormatter.format($0.value, unit: $0.key) }
            return ShoppingItem(ingredientID: id, name: ingredient.name, aisle: ingredient.aisle, quantities: quantities)
        }
        .sorted { ($0.aisle, $0.name) < ($1.aisle, $1.name) }
    }
}

public enum QuantityFormatter {
    /// Mots d'unité qui prennent un « s » au pluriel.
    static let pluralizable: Set<String> = [
        "pièce", "tranche", "grande", "petite", "gousse", "brin", "feuille", "filet", "pavé", "botte", "poignée", "pincée", "litre"
    ]

    /// Unité ramenée au singulier (« gousses » → « gousse »), pour additionner les quantités.
    public static func singular(_ unit: String) -> String {
        unit.split(separator: " ").map { word -> String in
            let text = String(word)
            if text.hasSuffix("s"), pluralizable.contains(String(text.dropLast())) { return String(text.dropLast()) }
            return text
        }.joined(separator: " ")
    }

    static func agree(_ unit: String, plural: Bool) -> String {
        let base = singular(unit)
        guard plural else { return base }
        return base.split(separator: " ").map { word -> String in
            pluralizable.contains(String(word)) ? String(word) + "s" : String(word)
        }.joined(separator: " ")
    }

    /// « 1,5 » devient « 1 ½ », les grammes sont arrondis et les unités s'accordent en nombre.
    /// Valeur nutritionnelle lisible : « 4,1 mg », « 23 g ».
    public static func nutrient(_ amount: Double, unit: String) -> String {
        let text = amount >= 10 ? String(Int(amount.rounded())) : String(format: "%.1f", amount).replacingOccurrences(of: ".", with: ",")
        return "\(text.hasSuffix(",0") ? String(text.dropLast(2)) : text) \(unit)"
    }

    public static func format(_ amount: Double, unit: String) -> String {
        if unit == "g" || unit == "ml" {
            let rounded = amount >= 100 ? (amount / 10).rounded() * 10 : max(1, amount.rounded())
            return "\(Int(rounded)) \(unit)"
        }
        let rounded = max(0.25, (amount * 4).rounded() / 4)
        let whole = Int(rounded)
        let fraction = rounded - Double(whole)
        let fractionText: String
        switch fraction {
        case 0.25: fractionText = "¼"
        case 0.5: fractionText = "½"
        case 0.75: fractionText = "¾"
        default: fractionText = ""
        }
        let number: String
        if whole == 0 {
            number = fractionText
        } else if fractionText.isEmpty {
            number = "\(whole)"
        } else {
            number = "\(whole) \(fractionText)"
        }
        return "\(number) \(agree(unit, plural: rounded >= 2))"
    }
}

// MARK: - Recettes recommandées

/// Une recette proposée, le nutriment qui la justifie et la raison affichée.
public struct RecipeRecommendation: Hashable, Sendable, Identifiable {
    public let recipe: Recipe
    public let focus: Nutrient
    public let reason: String
    public var id: String { recipe.id }
}

/// Propose des recettes riches en nutriments utiles au profil déclaré (régime, carences connues).
/// Les raisons restent factuelles : apport par portion d'après Ciqual, jamais d'effet promis sur les cheveux.
public enum RecipeRecommender {
    struct Focus {
        let nutrient: Nutrient
        let context: String
    }

    static func focuses(for profile: UserProfile) -> [Focus] {
        var result: [Focus] = []
        let deficiencies = profile.health.knownDeficiencies
        if deficiencies.contains(.iron) { result.append(Focus(nutrient: .iron, context: "Tu as indiqué un manque de fer : associe ce plat à une source de vitamine C, et garde le suivi de ta carence avec ton médecin.")) }
        if deficiencies.contains(.vitaminD) { result.append(Focus(nutrient: .vitaminD, context: "Tu as indiqué un manque de vitamine D : l'alimentation en apporte peu, ton médecin te dira si un complément est utile.")) }
        if deficiencies.contains(.zinc) { result.append(Focus(nutrient: .zinc, context: "Tu as indiqué un manque de zinc.")) }
        if deficiencies.contains(.vitaminB12) { result.append(Focus(nutrient: .vitaminB12, context: "Tu as indiqué un manque de vitamine B12 : parles-en à ton médecin pour son suivi.")) }
        switch profile.diet {
        case .vegan:
            result.append(Focus(nutrient: .iron, context: "En alimentation végétalienne, le fer des végétaux est moins bien absorbé : vise des sources variées, avec de la vitamine C au même repas."))
            result.append(Focus(nutrient: .zinc, context: "Le zinc est plus difficile à couvrir sans produits animaux."))
        case .vegetarian:
            result.append(Focus(nutrient: .iron, context: "Sans viande ni poisson, le fer demande un peu plus d'attention."))
            result.append(Focus(nutrient: .zinc, context: "Sans viande ni poisson, le zinc demande un peu plus d'attention."))
        case .pescatarian, .flexitarian, .omnivore:
            break
        }
        // Repères généraux, toujours présents en dernier : protéines et fer sont les plus discutés dans les revues sur la chute.
        result.append(Focus(nutrient: .protein, context: "Un apport suffisant en protéines fait partie d'une alimentation équilibrée."))
        result.append(Focus(nutrient: .iron, context: "Le fer fait partie des nutriments les plus étudiés quand on s'intéresse à la chute des cheveux."))
        var seen = Set<Nutrient>()
        return result.filter { seen.insert($0.nutrient).inserted }
    }

    public static func recommend(profile: UserProfile, database: NutritionDatabase, limit: Int = 4) -> [RecipeRecommendation] {
        let eligible = RecipeFilter.eligible(database.recipes, diet: profile.diet, restrictions: profile.health.restrictions, in: database)
            .filter { $0.meal != .snack }
        let facts = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, NutritionCalculator.facts(for: $0, in: database)) })
        var picks: [RecipeRecommendation] = []
        var usedMeals: [MealType: Int] = [:]
        for focus in focuses(for: profile) {
            let threshold = focus.nutrient == .protein ? 0.3 : 0.15
            let ranked = eligible
                .filter { recipe in !picks.contains { $0.recipe.id == recipe.id } }
                .compactMap { recipe -> (Recipe, Double)? in
                    guard let percent = facts[recipe.id]?.percentOfReference(focus.nutrient), percent >= threshold else { return nil }
                    return (recipe, percent)
                }
                .sorted { lhs, rhs in
                    // Varie les repas : une recette d'un repas déjà proposé passe après les autres.
                    let l = usedMeals[lhs.0.meal, default: 0], r = usedMeals[rhs.0.meal, default: 0]
                    return l != r ? l < r : lhs.1 > rhs.1
                }
            for (recipe, percent) in ranked.prefix(2) where picks.count < limit {
                let amount = facts[recipe.id]?.amount(focus.nutrient) ?? 0
                let label = focus.nutrient.label.prefix(1).lowercased() + focus.nutrient.label.dropFirst()
                // Formulation factuelle (« apporte… ») : les allégations « source de » ou « riche en » sont réglementées (règlement (CE) 1924/2006).
                let reason = "Apporte \(QuantityFormatter.nutrient(amount, unit: focus.nutrient.unit)) de \(label) par portion, soit \(Int((percent * 100).rounded())) % de la valeur de référence. \(focus.context)"
                picks.append(RecipeRecommendation(recipe: recipe, focus: focus.nutrient, reason: reason))
                usedMeals[recipe.meal, default: 0] += 1
            }
            if picks.count >= limit { break }
        }
        return picks
    }
}
