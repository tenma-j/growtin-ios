import GrowtinCore
import SwiftUI

struct RoutineRow: View {
    let item: RoutineItem
    let isCompleted: Bool
    let onToggle: () -> Void
    let onStart: () -> Void
    let onInfo: (() -> Void)?

    var body: some View {
        HStack(spacing: GT.Spacing.s) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isCompleted ? Color.gtGrowth : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: isCompleted) { _, new in new }
            .accessibilityLabel(isCompleted ? "Marquer comme non réalisée" : "Marquer comme réalisée")

            Button(action: onStart) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(isCompleted, color: .secondary)
                        .foregroundStyle(isCompleted ? Color.secondary : Color.primary)
                    Text(item.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: GT.Spacing.xs) {
                        Label(item.timeLabel, systemImage: "clock")
                        if let minutes = item.template?.durationMinutes {
                            Text("· \(minutes) min")
                        }
                        if item.reminderEnabled {
                            Image(systemName: "bell.fill").accessibilityLabel("Rappel activé")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint)

            if item.kind == .guidedBreathing || item.kind == .guidedScalpMassage {
                Button("Démarrer", systemImage: "play.fill", action: onStart)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Démarrer la séance \(item.title)")
            }
            if let onInfo {
                Button("Pourquoi cette habitude ?", systemImage: "info.circle", action: onInfo)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 44)
            }
        }
        .padding(.horizontal, GT.Spacing.s)
        .padding(.vertical, GT.Spacing.xs)
    }

    private var hint: String {
        switch item.kind {
        case .guidedBreathing, .guidedScalpMassage: "Ouvre la séance guidée"
        case .checkIn: "Ouvre le bilan du jour"
        case .check: isCompleted ? "Marque l'habitude comme non réalisée" : "Marque l'habitude comme réalisée"
        }
    }
}

struct RegularityCard: View {
    @Environment(AppModel.self) private var model
    let today: DayKey

    var body: some View {
        let calculator = model.consistency
        let progress = calculator.progress(on: today)
        let weekly = calculator.consistency(endingOn: today, days: 7)
        let activeDays = calculator.activeDays(endingOn: today, days: 7)
        GTCard {
            HStack(spacing: GT.Spacing.l) {
                ProgressRing(progress: progress.ratio, lineWidth: 10, label: "Habitudes réalisées aujourd'hui")
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: GT.Spacing.xs) {
                    Text("Aujourd'hui").gtEyebrowStyle()
                    Text("\(progress.completed) sur \(progress.scheduled) habitudes")
                        .font(.headline)
                    if let weekly {
                        Text("Régularité sur 7 jours : \(weekly.formatted(.percent.precision(.fractionLength(0))))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(activeDays) jour\(activeDays > 1 ? "s" : "") actif\(activeDays > 1 ? "s" : "") cette semaine")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(WellnessNotice.regularity)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CheckInCard: View {
    let checkIn: DailyCheckIn?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: GT.Spacing.m) {
                Image(systemName: checkIn == nil ? "square.and.pencil" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(checkIn == nil ? Color.primary : Color.gtGrowth)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(checkIn == nil ? "Bilan du jour" : "Bilan du jour enregistré")
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(GT.Spacing.m)
            .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.card))
            .contentShape(.rect(cornerRadius: GT.Radius.card))
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        guard let checkIn else { return "30 secondes, facultatif : sommeil, stress et observations." }
        var parts: [String] = []
        if let hours = checkIn.sleepHours { parts.append("\(hours.formatted()) h de sommeil") }
        if let stress = checkIn.stress { parts.append("stress \(stress)/5") }
        if let shedding = checkIn.shedding { parts.append(shedding.label.lowercased()) }
        return parts.isEmpty ? "Note enregistrée. Touche pour modifier." : parts.joined(separator: " · ")
    }
}

struct NextStepsCard: View {
    @Environment(AppModel.self) private var model
    let today: DayKey
    let onStartPhotos: () -> Void

    var body: some View {
        let start = model.programStart
        let next = Roadmap.nextMilestone(programStart: start, today: today)
        let photoDue = PhotoSchedule.nextDue(lastPhoto: model.lastPhotoDay, frequency: model.profile?.photoFrequency ?? .everyFourWeeks, today: today)
        GTCard {
            Text("Prochaines étapes").gtEyebrowStyle()
            if let next {
                StepLine(symbol: next.symbol, title: next.title, detail: "\(relative(next.day)) · \(next.detail)")
            }
            if photoDue <= today {
                Button(action: onStartPhotos) {
                    StepLine(symbol: "camera.viewfinder",
                             title: model.photos.isEmpty ? "Photos de référence" : "Série de photos conseillée",
                             detail: "Quelques minutes, dans les mêmes conditions que la dernière fois. Touche pour commencer.")
                }
                .buttonStyle(.plain)
            } else {
                StepLine(symbol: "camera.viewfinder", title: "Prochaine série de photos",
                         detail: "\(relative(photoDue)) · un rythme espacé rend les comparaisons plus fiables.")
            }
        }
    }

    private func relative(_ day: DayKey) -> String {
        let days = today.days(until: day)
        switch days {
        case 0: return "Aujourd'hui"
        case 1: return "Demain"
        default: return "Dans \(days) jours"
        }
    }
}

private struct StepLine: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: GT.Spacing.s) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Color.gtGrowth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
