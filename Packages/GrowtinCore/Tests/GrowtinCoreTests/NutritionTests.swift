import Foundation
import Testing
@testable import GrowtinCore

@Suite("Nutrition")
struct NutritionTests {
    let database: NutritionDatabase

    init() throws {
        database = try NutritionDatabase.bundled()
    }

    @Test("La base embarquée se charge et chaque recette est cohérente")
    func databaseIsConsistent() {
        #expect(database.recipes.count >= 35)
        for recipe in database.recipes {
            #expect(!recipe.steps.isEmpty, "\(recipe.id)")
            #expect(recipe.servings >= 1)
            #expect(recipe.ingredients.allSatisfy { $0.grams > 0 && $0.amount > 0 }, "\(recipe.id)")
            #expect(recipe.photoCredit?.license == "cc0", "\(recipe.id)")
        }
        for meal in MealType.allCases {
            #expect(database.recipes.contains { $0.meal == meal })
        }
    }

    @Test("Valeurs nutritionnelles plausibles par portion")
    func plausibleValues() throws {
        for recipe in database.recipes {
            let facts = NutritionCalculator.facts(for: recipe, in: database)
            let kcal = try #require(facts.amount(.energyKcal), "\(recipe.id) sans énergie fiable")
            #expect((80...1100).contains(kcal), "\(recipe.id) : \(kcal) kcal")
            let protein = try #require(facts.amount(.protein))
            #expect(protein >= 0 && protein < 90, "\(recipe.id) : \(protein) g de protéines")
        }
    }

    @Test("Calcul exact sur une recette connue")
    func exactComputation() throws {
        let recipe = try #require(database.recipe(id: "amandes-nature"))
        let facts = NutritionCalculator.facts(for: recipe, in: database)
        let almond = try #require(database.foods[15000])
        let apple = try #require(database.foods[13039])
        let expected = (almond.value(.protein) ?? 0) * 0.2 + (apple.value(.protein) ?? 0) * 1.5
        #expect(abs((facts.amount(.protein) ?? -1) - expected) < 0.0001)
    }

    @Test("Les rôles des nutriments ne promettent jamais de repousse")
    func rolesAreCompliant() {
        for nutrient in Nutrient.allCases {
            let role = nutrient.role?.lowercased() ?? ""
            #expect(!role.contains("repousse"))
            #expect(!role.contains("chute de cheveux") || role.contains("prise de sang"))
        }
    }

    @Test("Filtres : régime et allergies")
    func filters() {
        let vegan = RecipeFilter.eligible(database.recipes, diet: .vegan, restrictions: [], in: database)
        #expect(!vegan.isEmpty)
        for recipe in vegan {
            let kinds = Set(database.ingredients(of: recipe).map(\.kind))
            #expect(kinds == [.plant], "\(recipe.id)")
        }
        let noNuts = RecipeFilter.eligible(database.recipes, diet: .omnivore, restrictions: [.nuts, .peanuts], in: database)
        #expect(!noNuts.contains { $0.id == "melange-noix" || $0.id == "energy-balls-dattes-avoine" })
        let vegetarian = RecipeFilter.eligible(database.recipes, diet: .vegetarian, restrictions: [], in: database)
        #expect(!vegetarian.contains { $0.id == "saumon-grille-brocolis" })
        #expect(vegetarian.contains { $0.id == "shakshuka" })
    }

    @Test("Recherche insensible aux accents, y compris dans les ingrédients")
    func search() {
        let results = RecipeFilter.search(database.recipes, query: "epinards", in: database)
        #expect(results.contains { $0.id == "poelee-saumon-epinards" })
        #expect(RecipeFilter.search(database.recipes, query: "oeuf", in: database).contains { $0.id == "shakshuka" })
        #expect(RecipeFilter.search(database.recipes, query: "", in: database).count == database.recipes.count)
    }

    @Test("Recette du jour stable et variée")
    func recipeOfTheDay() {
        let day = DayKey(year: 2026, month: 11, day: 10)
        let a = MealPlanner.recipeOfTheDay(database.recipes, day: day)
        #expect(a == MealPlanner.recipeOfTheDay(database.recipes, day: day))
        #expect(a != MealPlanner.recipeOfTheDay(database.recipes, day: day.adding(days: 1)))
        #expect(a?.meal == .lunch || a?.meal == .dinner)
    }

    @Test("Planning de la semaine sans doublon et liste de courses")
    func weekPlanAndShopping() throws {
        let start = DayKey(year: 2026, month: 11, day: 9)
        let plan = MealPlanner.weekPlan(database.recipes, startingOn: start)
        #expect(plan.count == 21)
        let dinners = plan.filter { $0.meal == .dinner }.map(\.recipeID)
        #expect(Set(dinners).count == 7)
        #expect(plan == MealPlanner.weekPlan(database.recipes, startingOn: start))

        let list = ShoppingListBuilder.build(plan, in: database)
        #expect(!list.isEmpty)
        #expect(list.map(\.ingredientID).count == Set(list.map(\.ingredientID)).count)
    }

    @Test("Liste de courses : quantités ajustées aux portions et additionnées")
    func shoppingScaling() throws {
        let day = DayKey(year: 2026, month: 1, day: 1)
        let meals = [PlannedMeal(day: day, meal: .breakfast, recipeID: "amandes-nature", servings: 2),
                     PlannedMeal(day: day.adding(days: 1), meal: .breakfast, recipeID: "amandes-nature", servings: 1)]
        let list = ShoppingListBuilder.build(meals, in: database)
        let almonds = try #require(list.first { $0.ingredientID == "amandes" })
        #expect(almonds.quantities == ["60 g"])
        let apple = try #require(list.first { $0.ingredientID == "pomme" })
        #expect(apple.quantities == ["3 pièces"])
    }

    @Test("Formatage des quantités et accords")
    func quantities() {
        #expect(QuantityFormatter.format(0.5, unit: "pièce") == "½ pièce")
        #expect(QuantityFormatter.format(1.5, unit: "pièce") == "1 ½ pièce")
        #expect(QuantityFormatter.format(2, unit: "gousses") == "2 gousses")
        #expect(QuantityFormatter.format(1, unit: "gousses") == "1 gousse")
        #expect(QuantityFormatter.format(2, unit: "c. à soupe") == "2 c. à soupe")
        #expect(QuantityFormatter.format(1234, unit: "g") == "1230 g")
        #expect(QuantityFormatter.singular("grandes tranches") == "grande tranche")
    }
}
