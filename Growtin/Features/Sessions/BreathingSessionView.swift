import GrowtinCore
import SwiftUI

/// Respiration lente guidée : 5 secondes d'inspiration, 5 secondes d'expiration (6 cycles par minute).
struct BreathingSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock: SessionClock
    private let onComplete: () -> Void
    private static let phaseSeconds = 5

    init(minutes: Int, onComplete: @escaping () -> Void) {
        _clock = State(initialValue: SessionClock(totalSeconds: minutes * 60))
        self.onComplete = onComplete
    }

    private var isInhaling: Bool { (clock.elapsed / Self.phaseSeconds) % 2 == 0 }
    /// Le cercle grandit pendant l'inspiration et se contracte pendant l'expiration.
    private var expanded: Bool { clock.state == .running && isInhaling }

    var body: some View {
        SessionScaffold(
            eyebrow: "Respiration lente",
            title: "\(clock.totalSeconds / 60) minutes",
            subtitle: "Suis le cercle : 5 secondes d'inspiration par le nez, 5 secondes d'expiration.",
            clock: clock,
            precautions: "Si tu ressens un vertige ou une gêne, reprends une respiration normale. Cet exercice aide à gérer le stress ressenti ; il n'a pas d'effet démontré sur la chute de cheveux.",
            onClose: { dismiss() }
        ) {
            ZStack {
                Circle()
                    .fill(Color.gtGrowth.opacity(0.12))
                Circle()
                    .fill(Color.gtInk)
                    .scaleEffect(reduceMotion ? 0.7 : (expanded ? 1 : 0.55))
                    .animation(reduceMotion ? nil : .easeInOut(duration: Double(Self.phaseSeconds)), value: expanded)
                VStack(spacing: GT.Spacing.xs) {
                    Text(clock.remainingLabel)
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                    if clock.state == .running {
                        Text(isInhaling ? "Inspire" : "Expire")
                            .font(.headline)
                    }
                }
                .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .frame(width: 240, height: 240)
            .sensoryFeedback(.impact(weight: .light), trigger: isInhaling) { _, _ in clock.state == .running }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(clock.state == .running ? (isInhaling ? "Inspire" : "Expire") : "Séance de respiration")
            .accessibilityValue("\(clock.remaining) secondes restantes")
        }
        .onAppear { clock.onFinish = onComplete }
        .onDisappear { clock.stop() }
    }
}

/// Mise en page commune aux séances guidées.
struct SessionScaffold<Visual: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let clock: SessionClock
    let precautions: String
    let onClose: () -> Void
    @ViewBuilder var visual: Visual

    var body: some View {
        VStack(spacing: GT.Spacing.l) {
            HStack {
                Spacer()
                Button("Fermer", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
            VStack(spacing: GT.Spacing.xs) {
                Text(eyebrow).gtEyebrowStyle()
                Text(title).font(.largeTitle.weight(.bold))
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: GT.Spacing.m)
            visual
            Spacer(minLength: GT.Spacing.m)
            if clock.state == .finished {
                Label("Séance terminée et enregistrée", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.gtGrowth)
                PrimaryButton(title: "Fermer", action: onClose)
            } else {
                Text(precautions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(title: clock.state == .running ? "Pause" : (clock.state == .paused ? "Reprendre" : "Démarrer la séance"),
                              systemImage: clock.state == .running ? "pause.fill" : "play.fill") {
                    clock.state == .running ? clock.pause() : clock.start()
                }
            }
        }
        .padding(GT.Spacing.l)
        .background(Color.gtBackground)
        .sensoryFeedback(.success, trigger: clock.state) { _, new in new == .finished }
    }
}

#Preview("Respiration") {
    BreathingSessionView(minutes: 3) {}
}
