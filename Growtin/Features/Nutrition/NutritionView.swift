import GrowtinCore
import SwiftUI

enum NutritionRoute: Hashable {
    case recipe(String)
    case mealPlan
    case shoppingList
}

struct NutritionView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [NutritionRoute] = []
    @State private var query = ""
    @State private var mealFilter: MealType?
    @State private var favoritesOnly = false
    @State private var ignoreProfile = false
    @State private var today = DayKey(.now)

    private var store: NutritionStore { model.nutrition }

    private var baseRecipes: [Recipe] {
        ignoreProfile ? store.allRecipes : store.eligibleRecipes(for: model.profile)
    }

    private var filtered: [Recipe] {
        var recipes = baseRecipes
        if let mealFilter { recipes = recipes.filter { $0.meal == mealFilter } }
        if favoritesOnly { recipes = recipes.filter { store.isFavorite($0) } }
        if let database = store.database { recipes = RecipeFilter.search(recipes, query: query, in: database) }
        return recipes
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: GT.Spacing.l) {
                    if store.database == nil {
                        ContentUnavailableView("Recettes indisponibles", systemImage: "exclamationmark.triangle",
                                               description: Text("La bibliothèque de recettes n'a pas pu être chargée."))
                    } else {
                        if query.isEmpty, let recipe = store.recipeOfTheDay(for: model.profile, day: today) {
                            NavigationLink(value: NutritionRoute.recipe(recipe.id)) {
                                RecipeHeroCard(recipe: recipe, eyebrow: "Recette du jour")
                            }
                            .buttonStyle(.plain)
                        }
                        planShortcuts
                        filters
                        personalizationNote
                        recipeGrid
                        FootnoteText(text: "Valeurs nutritionnelles estimées à partir de la table Ciqual 2020 (ANSES). Photos : rawpixel, domaine public (CC0), présentation à titre indicatif. Aucun aliment ne fait repousser les cheveux : une alimentation variée aide surtout à éviter les carences.")
                    }
                }
                .padding(.horizontal, GT.Spacing.m)
                .padding(.bottom, GT.Spacing.xl)
            }
            .background(Color.gtBackground)
            .navigationTitle("Nutrition")
            .searchable(text: $query, prompt: "Recette ou ingrédient")
            .navigationDestination(for: NutritionRoute.self) { route in
                switch route {
                case .recipe(let id):
                    if let recipe = store.recipe(id: id) {
                        RecipeDetailView(recipe: recipe)
                    } else {
                        ContentUnavailableView("Recette introuvable", systemImage: "fork.knife")
                    }
                case .mealPlan:
                    MealPlanView()
                case .shoppingList:
                    ShoppingListView(weekStart: NutritionStore.weekStart(for: today))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = DayKey(.now) }
            .task { openDemoScreenIfNeeded() }
        }
    }

    private var planShortcuts: some View {
        HStack(spacing: GT.Spacing.s) {
            NavigationLink(value: NutritionRoute.mealPlan) {
                shortcut(title: "Ma semaine", detail: "Planning des repas", symbol: "calendar")
            }
            NavigationLink(value: NutritionRoute.shoppingList) {
                shortcut(title: "Courses", detail: "Liste automatique", symbol: "cart")
            }
        }
        .buttonStyle(.plain)
    }

    private func shortcut(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: GT.Spacing.s) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.gtGrowth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(GT.Spacing.m)
        .frame(maxWidth: .infinity)
        .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.card))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GT.Spacing.xs) {
                ChoiceChip(title: "Tout", isSelected: mealFilter == nil && !favoritesOnly) {
                    mealFilter = nil
                    favoritesOnly = false
                }
                ForEach(MealType.allCases) { meal in
                    ChoiceChip(title: meal.pluralLabel, systemImage: meal.symbol, isSelected: mealFilter == meal) {
                        mealFilter = mealFilter == meal ? nil : meal
                    }
                }
                ChoiceChip(title: "Favoris", systemImage: "heart", isSelected: favoritesOnly) { favoritesOnly.toggle() }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var personalizationNote: some View {
        if let profile = model.profile {
            let hidden = store.allRecipes.count - store.eligibleRecipes(for: profile).count
            if hidden > 0 {
                HStack(alignment: .top) {
                    Label(ignoreProfile ? "Toutes les recettes sont affichées."
                                        : "\(hidden) recette\(hidden > 1 ? "s" : "") masquée\(hidden > 1 ? "s" : "") selon ton régime et tes allergies.",
                          systemImage: "person.crop.circle.badge.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(ignoreProfile ? "Filtrer" : "Tout afficher") { ignoreProfile.toggle() }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var recipeGrid: some View {
        let recipes = filtered
        if recipes.isEmpty {
            ContentUnavailableView {
                Label(favoritesOnly ? "Aucun favori" : "Aucune recette", systemImage: favoritesOnly ? "heart" : "magnifyingglass")
            } description: {
                Text(favoritesOnly ? "Touche le cœur d'une recette pour la retrouver ici." : "Essaie un autre mot ou un autre filtre.")
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: GT.Spacing.s), GridItem(.flexible(), spacing: GT.Spacing.s)],
                      spacing: GT.Spacing.m) {
                ForEach(recipes) { recipe in
                    NavigationLink(value: NutritionRoute.recipe(recipe.id)) {
                        RecipeCard(recipe: recipe, isFavorite: store.isFavorite(recipe),
                                   kcal: store.facts(for: recipe)?.amount(.energyKcal))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Navigation automatique pour les captures d'écran du mode démonstration.
    private func openDemoScreenIfNeeded() {
        switch DemoLaunch.screen {
        case "recipe":
            if let recipe = store.recipeOfTheDay(for: model.profile, day: today) { path = [.recipe(recipe.id)] }
        case "mealPlan":
            store.generateWeek(startingOn: NutritionStore.weekStart(for: today), profile: model.profile)
            path = [.mealPlan]
        case "shopping":
            store.generateWeek(startingOn: NutritionStore.weekStart(for: today), profile: model.profile)
            path = [.shoppingList]
        default:
            break
        }
    }
}

/// Photo d'une recette (embarquée), réduite à la taille d'affichage.
struct RecipePhoto: View {
    let recipe: Recipe
    var maxPixelSize = 700
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.gtSurfaceRaised
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: recipe.id) { image = RecipeImageLoader.image(for: recipe, maxPixelSize: maxPixelSize) }
        .accessibilityHidden(true)
    }
}

struct RecipeHeroCard: View {
    let recipe: Recipe
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .overlay { RecipePhoto(recipe: recipe, maxPixelSize: 1200) }
                .clipped()
            VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                Text(eyebrow).gtEyebrowStyle()
                Text(recipe.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(recipe.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                RecipeMeta(recipe: recipe)
                    .padding(.top, GT.Spacing.xxs)
            }
            .padding(GT.Spacing.m)
        }
        .background(Color.gtSurface)
        .clipShape(.rect(cornerRadius: GT.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

struct RecipeCard: View {
    let recipe: Recipe
    let isFavorite: Bool
    let kcal: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .overlay { RecipePhoto(recipe: recipe, maxPixelSize: 500) }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .glassEffect(.regular, in: .circle)
                            .padding(6)
                            .accessibilityLabel("Favori")
                    }
                }
            VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                Text(recipe.meal.label).gtEyebrowStyle()
                Text(recipe.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                HStack(spacing: GT.Spacing.xs) {
                    Label("\(recipe.totalMinutes) min", systemImage: "clock")
                    if let kcal { Text("· \(Int(kcal.rounded())) kcal") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            .padding(GT.Spacing.s)
        }
        .background(Color.gtSurface)
        .clipShape(.rect(cornerRadius: GT.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

struct RecipeMeta: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: GT.Spacing.m) {
            Label("\(recipe.totalMinutes) min", systemImage: "clock")
            Label(recipe.difficulty.label, systemImage: "chart.bar")
            Label("\(recipe.servings) portion\(recipe.servings > 1 ? "s" : "")", systemImage: "person.2")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
