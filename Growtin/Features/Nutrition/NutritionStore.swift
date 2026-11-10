import Foundation
import GrowtinCore
import ImageIO
import Observation
import OSLog
import SwiftData
import UIKit

/// État de la nutrition enregistré sur l'appareil : favoris, planning et liste de courses cochée.
struct NutritionState: Codable, Equatable {
    var favorites: Set<String> = []
    var plan: [PlannedMeal] = []
    var checkedShoppingItems: Set<String> = []
}

@Model
final class NutritionStateRecord {
    var payload: Data
    var updatedAt: Date

    init(payload: Data, updatedAt: Date = .now) {
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@MainActor
@Observable
final class NutritionStore {
    let database: NutritionDatabase?
    private(set) var state = NutritionState()
    private let context: ModelContext
    private let logger = Logger(subsystem: "app.growtin", category: "Nutrition")

    init(context: ModelContext) {
        self.context = context
        do {
            database = try NutritionDatabase.bundled()
        } catch {
            Logger(subsystem: "app.growtin", category: "Nutrition").fault("Base nutritionnelle illisible : \(String(describing: error))")
            database = nil
        }
    }

    func load() {
        guard let record = try? context.fetch(FetchDescriptor<NutritionStateRecord>()).first,
              let decoded = try? JSONDecoder().decode(NutritionState.self, from: record.payload) else { return }
        state = decoded
    }

    // MARK: - Recettes

    var allRecipes: [Recipe] { database?.recipes ?? [] }

    func recipe(id: String) -> Recipe? { database?.recipe(id: id) }

    /// Recettes compatibles avec le profil (régime et allergies déclarés).
    func eligibleRecipes(for profile: UserProfile?) -> [Recipe] {
        guard let database else { return [] }
        guard let profile else { return database.recipes }
        return RecipeFilter.eligible(database.recipes, diet: profile.diet, restrictions: profile.health.restrictions, in: database)
    }

    func recipeOfTheDay(for profile: UserProfile?, day: DayKey) -> Recipe? {
        MealPlanner.recipeOfTheDay(eligibleRecipes(for: profile), day: day)
    }

    func facts(for recipe: Recipe) -> NutritionFacts? {
        database.map { NutritionCalculator.facts(for: recipe, in: $0) }
    }

    func tags(for recipe: Recipe) -> RecipeTags? {
        database.map { RecipeFilter.tags(for: recipe, in: $0) }
    }

    func ingredient(_ id: String) -> Ingredient? { database?.ingredients[id] }

    // MARK: - Favoris

    func isFavorite(_ recipe: Recipe) -> Bool { state.favorites.contains(recipe.id) }

    func toggleFavorite(_ recipe: Recipe) {
        mutate { state in
            if state.favorites.contains(recipe.id) { state.favorites.remove(recipe.id) } else { state.favorites.insert(recipe.id) }
        }
    }

    // MARK: - Planning

    /// Lundi de la semaine en cours.
    static func weekStart(for day: DayKey, calendar: Calendar = .current) -> DayKey {
        let weekday = calendar.component(.weekday, from: day.date(calendar: calendar)) // 1 = dimanche
        let offset = (weekday + 5) % 7
        return day.adding(days: -offset, calendar: calendar)
    }

    func meals(on day: DayKey) -> [PlannedMeal] {
        state.plan.filter { $0.day == day }.sorted { MealType.allCases.firstIndex(of: $0.meal)! < MealType.allCases.firstIndex(of: $1.meal)! }
    }

    func generateWeek(startingOn start: DayKey, profile: UserProfile?) {
        let recipes = eligibleRecipes(for: profile)
        let days = Set((0..<7).map { start.adding(days: $0) })
        mutate { state in
            state.plan.removeAll { days.contains($0.day) }
            state.plan.append(contentsOf: MealPlanner.weekPlan(recipes, startingOn: start))
            state.checkedShoppingItems = []
        }
    }

    func plan(_ recipe: Recipe, on day: DayKey, meal: MealType, servings: Int) {
        mutate { state in
            state.plan.removeAll { $0.day == day && $0.meal == meal }
            state.plan.append(PlannedMeal(day: day, meal: meal, recipeID: recipe.id, servings: servings))
        }
    }

    func remove(_ meal: PlannedMeal) {
        mutate { $0.plan.removeAll { $0.id == meal.id } }
    }

    func clearWeek(startingOn start: DayKey) {
        let days = Set((0..<7).map { start.adding(days: $0) })
        mutate { state in
            state.plan.removeAll { days.contains($0.day) }
            state.checkedShoppingItems = []
        }
    }

    // MARK: - Liste de courses

    func shoppingList(weekStart: DayKey) -> [ShoppingItem] {
        guard let database else { return [] }
        let days = Set((0..<7).map { weekStart.adding(days: $0) })
        return ShoppingListBuilder.build(state.plan.filter { days.contains($0.day) }, in: database)
    }

    func isChecked(_ item: ShoppingItem) -> Bool { state.checkedShoppingItems.contains(item.id) }

    func toggleChecked(_ item: ShoppingItem) {
        mutate { state in
            if state.checkedShoppingItems.contains(item.id) { state.checkedShoppingItems.remove(item.id) }
            else { state.checkedShoppingItems.insert(item.id) }
        }
    }

    func reset() {
        state = NutritionState()
    }

    // MARK: - Privé

    private func mutate(_ change: (inout NutritionState) -> Void) {
        var copy = state
        change(&copy)
        do {
            let payload = try JSONEncoder().encode(copy)
            if let record = try context.fetch(FetchDescriptor<NutritionStateRecord>()).first {
                record.payload = payload
                record.updatedAt = .now
            } else {
                context.insert(NutritionStateRecord(payload: payload))
            }
            try context.save()
            state = copy
        } catch {
            context.rollback()
            logger.error("Enregistrement nutrition impossible : \(String(describing: error), privacy: .private)")
        }
    }
}

/// Chargement des photos de recettes embarquées, avec réduction et cache.
@MainActor
enum RecipeImageLoader {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for recipe: Recipe, maxPixelSize: Int) -> UIImage? {
        let key = "\(recipe.photo)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let name = (recipe.photo as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }
}
