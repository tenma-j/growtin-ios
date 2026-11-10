import GrowtinCore
import SwiftUI

struct RecipeDetailView: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe
    @State private var servings: Int
    @State private var showingPlanSheet = false
    @State private var checkedSteps: Set<Int> = []

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    private var store: NutritionStore { model.nutrition }
    private var factor: Double { Double(servings) / Double(max(recipe.servings, 1)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GT.Spacing.l) {
                RecipePhoto(recipe: recipe, maxPixelSize: 1400)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: GT.Spacing.l) {
                    header
                    if let facts = store.facts(for: recipe) {
                        highlights(facts)
                    }
                    ingredientsSection
                    stepsSection
                    if !recipe.substitutions.isEmpty {
                        GTCard {
                            Text("Substitutions").font(.headline)
                            ForEach(recipe.substitutions, id: \.self) {
                                Label($0, systemImage: "arrow.left.arrow.right").font(.subheadline)
                            }
                        }
                    }
                    if let facts = store.facts(for: recipe) {
                        nutritionTable(facts)
                    }
                    sourcesSection
                }
                .padding(.horizontal, GT.Spacing.m)
            }
            .padding(.bottom, GT.Spacing.xl)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.gtBackground)
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(store.isFavorite(recipe) ? "Retirer des favoris" : "Ajouter aux favoris",
                       systemImage: store.isFavorite(recipe) ? "heart.fill" : "heart") {
                    store.toggleFavorite(recipe)
                }
                .sensoryFeedback(.selection, trigger: store.isFavorite(recipe))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Ajouter au planning", systemImage: "calendar.badge.plus") { showingPlanSheet = true }
            }
        }
        .sheet(isPresented: $showingPlanSheet) {
            AddToPlanSheet(recipe: recipe, servings: servings)
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.s) {
            Text(recipe.meal.label).gtEyebrowStyle()
            Text(recipe.title)
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(recipe.summary)
                .font(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: GT.Spacing.m) {
                Label("\(recipe.prepMinutes) min de préparation", systemImage: "clock")
                if recipe.cookMinutes > 0 {
                    Label("\(recipe.cookMinutes) min de cuisson", systemImage: "flame")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let tags = store.tags(for: recipe) {
                FlowLayout {
                    Text(recipe.difficulty.label).modifier(TagStyle())
                    ForEach(tags.labels, id: \.self) { Text($0).modifier(TagStyle()) }
                }
            }
        }
    }

    @ViewBuilder
    private func highlights(_ facts: NutritionFacts) -> some View {
        let nutrients = facts.highlights.filter { $0.role != nil }
        if !nutrients.isEmpty {
            GTCard {
                Text("Ce que cette recette apporte").font(.headline)
                Text("Par portion, au moins 15 % de la valeur de référence journalière (30 % pour les protéines).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(nutrients) { nutrient in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(nutrient.label).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let percent = facts.percentOfReference(nutrient) {
                                Text("\(percent.formatted(.percent.precision(.fractionLength(0)))) de la VNR")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.gtGrowth)
                            }
                        }
                        if let role = nutrient.role {
                            Text(role).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Une alimentation équilibrée aide à prévenir certaines carences. Elle ne constitue pas un traitement de la chute de cheveux.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ingredientsSection: some View {
        GTCard {
            HStack {
                Text("Ingrédients").font(.headline)
                Spacer()
                Stepper("\(servings) portion\(servings > 1 ? "s" : "")", value: $servings, in: 1...12)
                    .font(.subheadline)
                    .fixedSize()
            }
            ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, item in
                if let ingredient = store.ingredient(item.ingredientID) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(QuantityFormatter.format(item.amount * factor, unit: item.unit))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(minWidth: 90, alignment: .leading)
                        Text(ingredient.name).font(.subheadline)
                        Spacer(minLength: 0)
                        if !ingredient.allergens.isEmpty {
                            Image(systemName: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(Color.gtRegularity)
                                .accessibilityLabel("Allergènes : \(ingredient.allergens.map(\.label).joined(separator: ", "))")
                        }
                    }
                }
            }
            let allergens = Set(store.ingredients(of: recipe).flatMap(\.allergens))
            if !allergens.isEmpty {
                Label("Allergènes : \(DietaryRestriction.allCases.filter { allergens.contains($0) }.map { $0.label.lowercased() }.joined(separator: ", "))",
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Color.gtRegularity)
            }
        }
    }

    private var stepsSection: some View {
        GTCard {
            Text("Préparation").font(.headline)
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                Button {
                    if checkedSteps.contains(index) { checkedSteps.remove(index) } else { checkedSteps.insert(index) }
                } label: {
                    HStack(alignment: .top, spacing: GT.Spacing.s) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(checkedSteps.contains(index) ? Color.gtGrowth : Color.gtSurfaceRaised, in: .circle)
                            .foregroundStyle(checkedSteps.contains(index) ? Color.white : Color.primary)
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(checkedSteps.contains(index) ? Color.secondary : Color.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(checkedSteps.contains(index) ? "Étape terminée" : "")
            }
        }
    }

    private func nutritionTable(_ facts: NutritionFacts) -> some View {
        GTCard {
            Text("Valeurs nutritionnelles par portion").font(.headline)
            Text("Environ \(Int(facts.gramsPerServing.rounded())) g par portion")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Nutrient.macros + Nutrient.micros) { nutrient in
                HStack {
                    Text(nutrient.label)
                        .font(.subheadline)
                        .padding(.leading, nutrient == .sugars || nutrient == .saturatedFat ? GT.Spacing.m : 0)
                    Spacer()
                    if let amount = facts.amount(nutrient) {
                        Text(format(amount, nutrient))
                            .font(.subheadline.monospacedDigit())
                        if let percent = facts.percentOfReference(nutrient) {
                            Text(percent.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        } else {
                            Color.clear.frame(width: 44, height: 1)
                        }
                    } else {
                        Text("Donnée insuffisante")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if nutrient == .salt { Divider() }
            }
            Text("Pourcentages : part des valeurs de référence d'un adulte (règlement UE 1169/2011). Valeurs estimées à partir de la table Ciqual 2020 de l'ANSES ; elles varient selon les produits utilisés.\(facts.containsComputedEnergy ? " L'énergie de certains aliments est calculée à partir de leurs macronutriments." : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.s) {
            Text("Sources").font(.headline)
            ForEach(model.library.references(for: ["anses-ciqual-2020", "eu-1169-2011", "eu-432-2012"])) { source in
                SourceRow(source: source)
            }
            if let credit = recipe.photoCredit {
                Link(destination: credit.url) {
                    Label("Photo : \(credit.source), domaine public (\(credit.license.uppercased())). Présentation à titre indicatif.",
                          systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    private func format(_ amount: Double, _ nutrient: Nutrient) -> String {
        let digits = amount >= 10 || nutrient == .energyKcal ? 0 : 1
        return "\(amount.formatted(.number.precision(.fractionLength(digits)))) \(nutrient.unit)"
    }
}

private struct TagStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .padding(.horizontal, GT.Spacing.s)
            .padding(.vertical, GT.Spacing.xxs + 2)
            .foregroundStyle(Color.gtGrowth)
            .background(Color.gtGrowth.opacity(0.12), in: .capsule)
    }
}

extension NutritionStore {
    func ingredients(of recipe: Recipe) -> [Ingredient] { database?.ingredients(of: recipe) ?? [] }
}

struct AddToPlanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var date = Date.now
    @State private var meal: MealType
    @State private var servings: Int

    init(recipe: Recipe, servings: Int) {
        self.recipe = recipe
        _meal = State(initialValue: recipe.meal)
        _servings = State(initialValue: servings)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Jour", selection: $date, in: Date.now..., displayedComponents: .date)
                Picker("Repas", selection: $meal) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                Stepper("\(servings) portion\(servings > 1 ? "s" : "")", value: $servings, in: 1...12)
            }
            .navigationTitle("Ajouter au planning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter", systemImage: "checkmark") {
                        model.nutrition.plan(recipe, on: DayKey(date), meal: meal, servings: servings)
                        dismiss()
                    }
                }
            }
        }
    }
}
