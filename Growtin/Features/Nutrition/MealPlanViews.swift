import GrowtinCore
import SwiftUI

/// Planning des repas de la semaine en cours (du lundi au dimanche).
struct MealPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var weekStart = NutritionStore.weekStart(for: DayKey(.now))
    @State private var confirmingRegeneration = false

    private var store: NutritionStore { model.nutrition }
    private var days: [DayKey] { (0..<7).map { weekStart.adding(days: $0) } }
    private var hasMeals: Bool { days.contains { !store.meals(on: $0).isEmpty } }

    var body: some View {
        List {
            Section {
                HStack {
                    Button("Semaine précédente", systemImage: "chevron.left") { weekStart = weekStart.adding(days: -7) }
                        .labelStyle(.iconOnly)
                    Spacer()
                    Text(weekLabel).font(.headline)
                    Spacer()
                    Button("Semaine suivante", systemImage: "chevron.right") { weekStart = weekStart.adding(days: 7) }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                Button(hasMeals ? "Proposer une nouvelle semaine" : "Proposer des menus pour la semaine", systemImage: "wand.and.stars") {
                    if hasMeals { confirmingRegeneration = true } else { generate() }
                }
            } footer: {
                Text("Les menus respectent ton régime et tes allergies, et varient d'un repas à l'autre. Tu peux remplacer chaque recette depuis sa fiche.")
            }

            ForEach(days, id: \.self) { day in
                Section(day.date().formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized) {
                    let meals = store.meals(on: day)
                    if meals.isEmpty {
                        Text("Rien de prévu").foregroundStyle(.secondary)
                    }
                    ForEach(meals) { planned in
                        if let recipe = store.recipe(id: planned.recipeID) {
                            NavigationLink(value: NutritionRoute.recipe(recipe.id)) {
                                HStack(spacing: GT.Spacing.s) {
                                    RecipePhoto(recipe: recipe, maxPixelSize: 200)
                                        .frame(width: 52, height: 52)
                                        .clipShape(.rect(cornerRadius: GT.Radius.small))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(planned.meal.label).font(.caption).foregroundStyle(.secondary)
                                        Text(recipe.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                        Text("\(planned.servings) portion\(planned.servings > 1 ? "s" : "") · \(recipe.totalMinutes) min")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Retirer", systemImage: "trash", role: .destructive) { store.remove(planned) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ma semaine")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: NutritionRoute.shoppingList) {
                    Label("Liste de courses", systemImage: "cart")
                }
            }
        }
        .confirmationDialog("Remplacer les menus de cette semaine ?", isPresented: $confirmingRegeneration, titleVisibility: .visible) {
            Button("Proposer une nouvelle semaine", role: .destructive) { generate() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var weekLabel: String {
        let end = weekStart.adding(days: 6)
        return "\(weekStart.date().formatted(.dateTime.day().month(.abbreviated))) – \(end.date().formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func generate() {
        store.generateWeek(startingOn: weekStart, profile: model.profile)
    }
}

/// Liste de courses générée à partir du planning de la semaine.
struct ShoppingListView: View {
    @Environment(AppModel.self) private var model
    let weekStart: DayKey

    private var store: NutritionStore { model.nutrition }

    var body: some View {
        let items = store.shoppingList(weekStart: weekStart)
        let aisles = Dictionary(grouping: items, by: \.aisle).sorted { $0.key < $1.key }
        List {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Liste vide", systemImage: "cart")
                } description: {
                    Text("Ajoute des recettes à ton planning de la semaine : la liste se remplit automatiquement.")
                } actions: {
                    Button("Proposer des menus") { store.generateWeek(startingOn: weekStart, profile: model.profile) }
                        .gtProminentButton()
                }
            }
            ForEach(aisles, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.value) { item in
                        Button {
                            store.toggleChecked(item)
                        } label: {
                            HStack {
                                Image(systemName: store.isChecked(item) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.isChecked(item) ? Color.gtGrowth : Color.secondary)
                                    .font(.title3)
                                Text(item.name)
                                    .strikethrough(store.isChecked(item))
                                    .foregroundStyle(store.isChecked(item) ? Color.secondary : Color.primary)
                                Spacer()
                                Text(item.quantities.joined(separator: " + "))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(store.isChecked(item) ? "Acheté" : "À acheter")
                        .sensoryFeedback(.selection, trigger: store.isChecked(item))
                    }
                }
            }
        }
        .navigationTitle("Courses")
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(aisles), subject: Text("Liste de courses Growtin'")) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func shareText(_ aisles: [(key: String, value: [ShoppingItem])]) -> String {
        aisles.map { group in
            "\(group.key)\n" + group.value.map { "• \($0.name) — \($0.quantities.joined(separator: " + "))" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
