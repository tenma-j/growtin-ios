import GrowtinCore
import SwiftUI

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: GT.Spacing.m) {
            Image(systemName: exercise.category.symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Color.gtGrowth.opacity(0.12), in: .circle)
                .foregroundStyle(Color.gtGrowth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                Text(exercise.title).font(.body.weight(.medium))
                Text("\(exercise.durationMinutes) min · \(exercise.category.label) · \(exercise.level.label)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                EvidenceBadge(level: exercise.evidence)
            }
        }
        .padding(.vertical, GT.Spacing.xxs)
    }
}

/// Point de technique : coche verte alignée sur la première ligne.
struct CueLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GT.Spacing.xs) {
            configuration.icon.foregroundStyle(Color.gtGrowth).font(.caption.weight(.bold))
            configuration.title
        }
    }
}

/// Bibliothèques de mouvements du personnage 3D (une par corps : homme, femme), chargées une seule fois.
enum MotionCatalog {
    private static let libraries: [MannequinBody: MotionLibrary] = {
        let all = (try? MotionLibrary.bundledBodies()) ?? [:]       // fichier lu une seule fois pour les deux corps
        var out: [MannequinBody: MotionLibrary] = [:]
        for body in MannequinBody.allCases { out[body] = all[body.rawValue] }
        return out
    }()

    static func library(for body: MannequinBody) -> MotionLibrary? { libraries[body] ?? libraries[.male] }
    static var library: MotionLibrary? { library(for: .male) }

    static func caption(for step: ExerciseStep) -> String? {
        BodyRegionLabel.text(step.focus ?? library?.motion(step.motion)?.muscles ?? [])
    }
}

struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    @State private var showingSession = false
    @State private var selectedStep: Int

    init(exercise: Exercise) {
        self.exercise = exercise
        _selectedStep = State(initialValue: exercise.featuredStepIndex)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GT.Spacing.l) {
                let preview = exercise.steps[min(selectedStep, exercise.steps.count - 1)]
                MannequinCard(motion: preview.motion,
                              caption: "\(min(selectedStep, exercise.steps.count - 1) + 1). \(preview.title)", height: 360)
                    .padding(.top, GT.Spacing.s)

                VStack(alignment: .leading, spacing: GT.Spacing.xs) {
                    Text(exercise.category.label).gtEyebrowStyle()
                    Text(exercise.title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text(exercise.summary).foregroundStyle(.secondary)
                    HStack(spacing: GT.Spacing.m) {
                        Label("\(exercise.durationMinutes) min", systemImage: "clock")
                        Label(exercise.level.label, systemImage: "chart.bar")
                        Label("\(exercise.steps.count) étapes", systemImage: "list.number")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                GTCard {
                    HStack {
                        Text("Déroulé").font(.headline)
                        Spacer()
                        Text("Touche une étape pour voir le mouvement").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(exercise.steps.enumerated()), id: \.offset) { index, step in
                        Button {
                            withAnimation(.snappy) { selectedStep = index }
                        } label: {
                            HStack(alignment: .top, spacing: GT.Spacing.s) {
                                Image(systemName: step.symbol)
                                    .frame(width: 28)
                                    .foregroundStyle(Color.gtGrowth)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("\(index + 1). \(step.title)").font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(SessionTime.label(step.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Text(step.instruction).font(.footnote).foregroundStyle(.secondary)
                                    ForEach(step.cues, id: \.self) { cue in
                                        Label(cue, systemImage: "checkmark")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .labelStyle(CueLabelStyle())
                                    }
                                }
                            }
                            .padding(GT.Spacing.xs)
                            .background(index == selectedStep ? Color.gtGrowth.opacity(0.1) : .clear, in: .rect(cornerRadius: GT.Radius.small))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Affiche ce mouvement en 3D")
                        .accessibilityAddTraits(index == selectedStep ? .isSelected : [])
                    }
                }

                GTCard {
                    HStack {
                        Text("Bénéfices").font(.headline)
                        Spacer()
                        EvidenceBadge(level: exercise.evidence)
                    }
                    Text(exercise.benefits).font(.subheadline)
                    Label(exercise.hairNote, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(model.library.references(for: exercise.sourceIDs)) { SourceRow(source: $0) }
                }

                GTCard {
                    Text("Précautions").font(.headline)
                    ForEach(exercise.precautions, id: \.self) {
                        Label($0, systemImage: "exclamationmark.circle").font(.subheadline)
                    }
                    if !exercise.contraindications.isEmpty {
                        Text("Contre-indications").font(.headline).padding(.top, GT.Spacing.xs)
                        ForEach(exercise.contraindications, id: \.self) {
                            Label($0, systemImage: "stethoscope").font(.subheadline).foregroundStyle(Color.gtAlert)
                        }
                    }
                }
            }
            .padding(.horizontal, GT.Spacing.m)
            .padding(.bottom, GT.Spacing.xl)
        }
        .background(Color.gtBackground)
        .navigationTitle(exercise.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Commencer la séance", systemImage: "play.fill") { showingSession = true }
                .padding(.horizontal, GT.Spacing.m)
                .padding(.bottom, GT.Spacing.s)
        }
        .fullScreenCover(isPresented: $showingSession) {
            ExerciseSessionView(exercise: exercise) { markHabit() }
        }
        .task {
            switch DemoLaunch.screen {
            case "exerciseSession": showingSession = true
            case "exercise": selectedStep = 1
            case "exerciseFloor":
                UserDefaults.standard.set(MannequinBody.female.rawValue, forKey: "mannequin.figure")
                selectedStep = 3
            case "exerciseStep":
                if let figure = DemoLaunch.figure { UserDefaults.standard.set(figure, forKey: "mannequin.figure") }
                selectedStep = min(DemoLaunch.onboardingStep ?? 0, exercise.steps.count - 1)
            default: break
            }
        }
    }

    private func markHabit() {
        guard let templateID = exercise.habitTemplateID,
              let item = model.activeRoutine.first(where: { $0.templateID == templateID }) else { return }
        model.setCompleted(true, item: item, on: DayKey(.now))
    }
}

enum SessionTime {
    static func label(_ seconds: Int) -> String {
        seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) min" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Séance guidée étape par étape, avec minuteur.
struct ExerciseSessionView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    private let onComplete: () -> Void
    @State private var clock: SessionClock

    init(exercise: Exercise, onComplete: @escaping () -> Void) {
        self.exercise = exercise
        self.onComplete = onComplete
        _clock = State(initialValue: SessionClock(totalSeconds: exercise.totalSeconds))
    }

    /// Étape en cours et secondes restantes dans cette étape.
    private var current: (index: Int, remaining: Int) {
        var elapsed = clock.elapsed
        for (index, step) in exercise.steps.enumerated() {
            if elapsed < step.seconds { return (index, step.seconds - elapsed) }
            elapsed -= step.seconds
        }
        return (exercise.steps.count - 1, 0)
    }

    var body: some View {
        let state = current
        let step = exercise.steps[state.index]
        SessionScaffold(
            eyebrow: "\(exercise.title) · étape \(state.index + 1) sur \(exercise.steps.count)",
            title: step.title,
            subtitle: step.instruction,
            clock: clock,
            precautions: exercise.precautions.first ?? "Arrête en cas de douleur ou de malaise.",
            onClose: { dismiss() }
        ) {
            VStack(spacing: GT.Spacing.m) {
                MannequinCard(motion: step.motion, caption: MotionCatalog.caption(for: step), height: 270)
                if !step.cues.isEmpty {
                    VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                        ForEach(step.cues, id: \.self) { cue in
                            Label(cue, systemImage: "checkmark").font(.footnote).labelStyle(CueLabelStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(GT.Spacing.s)
                    .background(Color.gtGrowth.opacity(0.08), in: .rect(cornerRadius: GT.Radius.control))
                }
                Text(SessionTime.label(state.remaining))
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                HStack(spacing: GT.Spacing.xxs) {
                    ForEach(exercise.steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index <= state.index && clock.state != .idle ? Color.gtInk : Color.gtSeparator.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
                Text("Temps total restant : \(clock.remainingLabel)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: state.index)
            .accessibilityElement(children: .combine)
        }
        .onAppear { clock.onFinish = onComplete }
        .onDisappear { clock.stop() }
    }
}

struct ArticleView: View {
    @Environment(AppModel.self) private var model
    let article: Article

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GT.Spacing.l) {
                VStack(alignment: .leading, spacing: GT.Spacing.xs) {
                    Label(article.category.label, systemImage: article.category.symbol).gtEyebrowStyle()
                    Text(article.title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text(article.subtitle).font(.title3).foregroundStyle(.secondary)
                    Text("\(article.readMinutes) min de lecture · relu le \(article.reviewedOn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GTCard {
                    Text("L'essentiel").font(.headline)
                    ForEach(article.keyPoints, id: \.self) { point in
                        Label(point, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                ForEach(article.sections, id: \.heading) { section in
                    VStack(alignment: .leading, spacing: GT.Spacing.s) {
                        Text(section.heading).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        ForEach(section.paragraphs, id: \.self) { paragraph in
                            Text(paragraph).font(.body)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: GT.Spacing.s) {
                    Text("Sources").font(.headline)
                    ForEach(model.library.references(for: article.sourceIDs)) { SourceRow(source: $0) }
                }
                FootnoteText(text: WellnessNotice.short)
            }
            .padding(.horizontal, GT.Spacing.m)
            .padding(.bottom, GT.Spacing.xl)
        }
        .background(Color.gtBackground)
        .navigationBarTitleDisplayMode(.inline)
    }
}
