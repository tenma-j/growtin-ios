import Foundation

/// Lancement en mode démonstration, utilisé par la chaîne de compilation cloud pour produire des captures d'écran.
/// Exemple : `-demoScreen today`. Ce mode n'existe que dans les versions de développement (DEBUG) :
/// dans la version publiée, `screen` vaut toujours `nil`.
enum DemoLaunch {
    #if DEBUG
    static let screen: String? = value(for: "-demoScreen")
    static let onboardingStep: Int? = value(for: "-demoStep").flatMap(Int.init)
    #else
    static let screen: String? = nil
    static let onboardingStep: Int? = nil
    #endif

    static var isActive: Bool { screen != nil }

    static var initialTab: AppTab {
        switch screen {
        case "progress", "photoSession", "photoCapture", "photoTimeline", "photoCompare": .progress
        case "coach": .coach
        case "nutrition", "recipe", "mealPlan", "shopping": .nutrition
        case "explore", "exercise", "article", "exerciseSession": .explore
        default: .today
        }
    }

    private static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
