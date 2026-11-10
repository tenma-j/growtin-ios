import GrowtinCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !model.isLoaded {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gtBackground)
            } else if model.profile == nil {
                OnboardingFlowView(mode: .firstLaunch)
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(GT.Motion.adaptive(GT.Motion.standard, reduceMotion: reduceMotion), value: model.profile == nil)
        .task {
            if !model.isLoaded { model.load() }
        }
        .alert("Un problème est survenu",
               isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } }),
               presenting: model.lastError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}

enum AppTab: Hashable {
    case today, progress, coach, nutrition, explore
}

struct MainTabView: View {
    @State private var selection: AppTab = DemoLaunch.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Aujourd'hui", systemImage: "sun.max", value: .today) {
                TodayView()
            }
            Tab("Progrès", systemImage: "chart.line.uptrend.xyaxis", value: .progress) {
                ProgressTabView()
            }
            Tab("Coach", systemImage: "sparkles", value: .coach) {
                ComingSoonView(
                    title: "Coach",
                    systemImage: "sparkles",
                    description: "Ton assistant personnel répondra à tes questions en s'appuyant uniquement sur des sources vérifiées.",
                    plannedFeatures: [
                        "Réponses sourcées, avec niveau de preuve",
                        "Explication de chaque recommandation",
                        "Bilans hebdomadaires et mensuels",
                        "Orientation vers un médecin si nécessaire"
                    ])
            }
            Tab("Nutrition", systemImage: "leaf", value: .nutrition) {
                ComingSoonView(
                    title: "Nutrition",
                    systemImage: "leaf",
                    description: "Recettes adaptées à tes préférences et restrictions, avec valeurs nutritionnelles calculées à partir de la table Ciqual de l'ANSES.",
                    plannedFeatures: [
                        "Recette du jour, petit-déjeuner, déjeuner, dîner et collations",
                        "Filtres, favoris et recherche",
                        "Planning de la semaine et liste de courses",
                        "Rôle nutritionnel des ingrédients, sans promesse de repousse"
                    ])
            }
            Tab("Explorer", systemImage: "square.grid.2x2", value: .explore) {
                ExploreView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
