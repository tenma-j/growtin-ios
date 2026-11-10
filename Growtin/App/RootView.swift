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
            await model.startOnlineServices()
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
                CoachView()
            }
            Tab("Nutrition", systemImage: "leaf", value: .nutrition) {
                NutritionView()
            }
            Tab("Explorer", systemImage: "square.grid.2x2", value: .explore) {
                ExploreView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
