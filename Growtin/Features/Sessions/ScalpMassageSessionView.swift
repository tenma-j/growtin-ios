import GrowtinCore
import SwiftUI

/// Massage du cuir chevelu guidé, 4 zones × 1 minute.
struct ScalpMassageSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var clock: SessionClock
    private let onComplete: () -> Void

    static let secondsPerZone = 60

    struct Zone {
        let name: String
        let instruction: String
    }

    static let zones: [Zone] = [
        Zone(name: "Zone frontale", instruction: "Petits cercles au niveau de la ligne frontale, du bout des doigts, sans frotter."),
        Zone(name: "Tempes", instruction: "Cercles lents des deux côtés, pression légère."),
        Zone(name: "Sommet", instruction: "Doigts écartés, mobilise doucement la peau du sommet du crâne."),
        Zone(name: "Arrière du crâne", instruction: "Remonte de la nuque vers l'arrière de la tête par petites pressions.")
    ]

    init(onComplete: @escaping () -> Void) {
        _clock = State(initialValue: SessionClock(totalSeconds: Self.zones.count * Self.secondsPerZone))
        self.onComplete = onComplete
    }

    private var zoneIndex: Int { min(clock.elapsed / Self.secondsPerZone, Self.zones.count - 1) }
    private var zone: Zone { Self.zones[zoneIndex] }

    var body: some View {
        SessionScaffold(
            eyebrow: "Massage du cuir chevelu",
            title: zone.name,
            subtitle: zone.instruction,
            clock: clock,
            precautions: "À éviter sur un cuir chevelu irrité, douloureux ou lésé. Arrête en cas de douleur. Preuves limitées : à considérer comme un moment de détente, pas comme un traitement.",
            onClose: { dismiss() }
        ) {
            VStack(spacing: GT.Spacing.l) {
                ZStack {
                    Circle().stroke(Color.gtSeparator.opacity(0.35), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: clock.fraction)
                        .stroke(Color.gtGrowth, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: clock.elapsed)
                    VStack(spacing: GT.Spacing.xxs) {
                        Text(clock.remainingLabel)
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                        Text("Zone \(zoneIndex + 1) / \(Self.zones.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220, height: 220)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zone \(zoneIndex + 1) sur \(Self.zones.count), \(zone.name)")
                .accessibilityValue("\(clock.remaining) secondes restantes")

                HStack(spacing: GT.Spacing.xs) {
                    ForEach(Self.zones.indices, id: \.self) { index in
                        Capsule()
                            .fill(index <= zoneIndex && clock.state != .idle ? Color.gtInk : Color.gtSeparator.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: zoneIndex)
        }
        .onAppear { clock.onFinish = onComplete }
        .onDisappear { clock.stop() }
    }
}

#Preview("Massage") {
    ScalpMassageSessionView {}
}
