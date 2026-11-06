import GrowtinCore
import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: OnboardingModel

    init(mode: OnboardingModel.Mode) {
        _model = State(initialValue: OnboardingModel(mode: mode))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                stepContent
                    .id(model.step)
                    .transition(stepTransition)
                    .padding(.horizontal, GT.Spacing.l)
                    .padding(.top, GT.Spacing.l)
                    .padding(.bottom, GT.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.gtBackground)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: model.continueTitle, isEnabled: model.canContinue) { advance() }
                .padding(.horizontal, GT.Spacing.l)
                .padding(.bottom, GT.Spacing.s)
        }
        .animation(GT.Motion.adaptive(GT.Motion.standard, reduceMotion: reduceMotion), value: model.stepIndex)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: model.isMovingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: model.isMovingForward ? .leading : .trailing).combined(with: .opacity))
    }

    private var topBar: some View {
        HStack(spacing: GT.Spacing.s) {
            if model.isFirstStep {
                if case .edit = model.mode {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            } else {
                Button("Retour", systemImage: "chevron.left") { model.back() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
            ProgressView(value: model.progress)
                .tint(.gtInk)
                .accessibilityLabel("Progression")
                .accessibilityValue("Étape \(model.stepIndex + 1) sur \(model.steps.count)")
        }
        .padding(.horizontal, GT.Spacing.l)
        .padding(.top, GT.Spacing.xs)
        .frame(height: 52)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: WelcomeStep(model: model)
        case .aboutYou: AboutYouStep(model: model)
        case .history: HistoryStep(model: model)
        case .stage: StageStep(model: model)
        case .zones: ZonesStep(model: model)
        case .goals: GoalsStep(model: model)
        case .sleepStress: SleepStressStep(model: model)
        case .nutritionActivity: NutritionActivityStep(model: model)
        case .hairCare: HairCareStep(model: model)
        case .health: HealthStep(model: model)
        case .tracking: TrackingStep(model: model)
        case .summary: SummaryStep(model: model)
        }
    }

    private func advance() {
        guard model.isLastStep else {
            model.next()
            return
        }
        let profile = model.buildProfile()
        switch model.mode {
        case .firstLaunch:
            appModel.completeOnboarding(with: profile)
        case .edit:
            appModel.updateProfile(profile, regenerateRoutine: model.regenerateRoutineOnSave)
            dismiss()
        }
    }
}

/// En-tête commun : titre, explication et raison pour laquelle la question est posée.
struct StepHeader: View {
    var eyebrow: String?
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.xs) {
            if let eyebrow {
                Text(eyebrow).gtEyebrowStyle()
            }
            Text(title)
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, GT.Spacing.s)
    }
}

/// Message rappelant pourquoi une donnée est demandée et comment elle est utilisée.
struct PrivacyNote: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "lock")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

#Preview("Onboarding") {
    OnboardingFlowView(mode: .firstLaunch)
        .environment(AppModel.preview())
}
