import Foundation
import GrowtinCore
import Observation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case aboutYou       // « Parlons de toi » (anciennement 3e écran de la web app)
    case history        // « Depuis quand ? » (anciennement 2e écran)
    case stage
    case zones
    case goals
    case sleepStress
    case nutritionActivity
    case hairCare
    case health
    case tracking
    case summary

    var id: Int { rawValue }
}

/// Brouillon des réponses. Les champs indispensables sont optionnels tant que l'utilisateur n'a pas choisi.
@MainActor
@Observable
final class OnboardingModel {
    enum Mode: Equatable {
        case firstLaunch
        case edit(UserProfile)
    }

    let mode: Mode
    let steps: [OnboardingStep]
    private(set) var stepIndex = 0
    private(set) var isMovingForward = true

    var disclaimerAccepted = false
    var draft: UserProfile
    var sex: BiologicalSex?
    var duration: HairLossDuration?
    var shareBodyMeasures = false
    var regenerateRoutineOnSave = true

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .firstLaunch:
            draft = UserProfile()
            steps = OnboardingStep.allCases
        case .edit(let profile):
            draft = profile
            steps = OnboardingStep.allCases.filter { $0 != .welcome }
            sex = profile.sex
            duration = profile.hairLossDuration
            shareBodyMeasures = profile.weightKg != nil || profile.heightCm != nil
            disclaimerAccepted = true
        }
    }

    var step: OnboardingStep { steps[stepIndex] }
    var isFirstStep: Bool { stepIndex == 0 }
    var isLastStep: Bool { stepIndex == steps.count - 1 }
    var progress: Double { Double(stepIndex + 1) / Double(steps.count) }

    var canContinue: Bool {
        switch step {
        case .welcome: disclaimerAccepted
        case .aboutYou: sex != nil
        case .history: duration != nil
        default: true
        }
    }

    var continueTitle: String {
        switch step {
        case .welcome: "Commencer"
        case .health: hasHealthAnswers ? "Continuer" : "Passer cette étape"
        case .summary: mode == .firstLaunch ? "Démarrer mon programme" : "Enregistrer"
        default: "Continuer"
        }
    }

    private var hasHealthAnswers: Bool {
        draft.health != HealthDetails()
    }

    func next() {
        guard canContinue, !isLastStep else { return }
        if step == .aboutYou, let sex {
            // L'échelle proposée suit le sexe déclaré ; elle reste modifiable sur l'écran suivant.
            if draft.stage.scale != HairStageScale.preferred(for: sex) && draft.stage.stage == nil {
                draft.stage = SelfAssessedStage(scale: .preferred(for: sex), stage: nil)
            }
        }
        isMovingForward = true
        stepIndex += 1
    }

    func back() {
        guard !isFirstStep else { return }
        isMovingForward = false
        stepIndex -= 1
    }

    /// Profil final, nettoyé des informations non pertinentes.
    func buildProfile(now: Date = .now) -> UserProfile {
        var profile = draft
        profile.sex = sex ?? .unspecified
        profile.hairLossDuration = duration ?? .unsure
        if !shareBodyMeasures {
            profile.heightCm = nil
            profile.weightKg = nil
        }
        if profile.sex == .male {
            profile.health.pregnancy = nil
        }
        profile.firstName = profile.displayName
        if profile.consents.wellnessDisclaimerAcceptedAt == nil {
            profile.consents.wellnessDisclaimerAcceptedAt = now
        }
        return profile
    }

    /// Aperçu du programme affiché sur le dernier écran.
    var previewRoutine: [RoutineItem] {
        RoutineEngine().initialRoutine(for: buildProfile(), startingOn: DayKey(.now))
    }

    var previewAlerts: [SafetyAlert] {
        SafetyScreener().assess(profile: buildProfile())
    }
}
