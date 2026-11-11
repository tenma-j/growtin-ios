import GrowtinCore
import SwiftUI

enum ExploreRoute: Hashable {
    case exercise(String)
    case article(String)
    case evidence
    case sources
}

struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [ExploreRoute] = []
    @State private var session: GuidedSession?

    enum GuidedSession: String, Identifiable {
        case breathing, massage
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !recommendations.isEmpty {
                    Section {
                        ForEach(recommendations) { recommendation in
                            NavigationLink(value: ExploreRoute.exercise(recommendation.exercise.id)) {
                                VStack(alignment: .leading, spacing: GT.Spacing.xs) {
                                    ExerciseRow(exercise: recommendation.exercise)
                                    Label(recommendation.reason, systemImage: "person.crop.circle.badge.checkmark")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Pour toi")
                    } footer: {
                        Text("Choisies d'après ton profil et tes derniers bilans du jour.")
                    }
                }

                Section {
                    ForEach(ExerciseLibrary.all) { exercise in
                        NavigationLink(value: ExploreRoute.exercise(exercise.id)) {
                            ExerciseRow(exercise: exercise)
                        }
                    }
                    sessionRow(title: "Respiration lente", detail: "3 min · gestion du stress",
                               symbol: "wind", card: EvidenceCatalog.slowBreathing) { session = .breathing }
                    sessionRow(title: "Massage du cuir chevelu", detail: "4 min · détente",
                               symbol: "hand.raised", card: EvidenceCatalog.scalpMassage) { session = .massage }
                } header: {
                    Text("Toutes les séances")
                } footer: {
                    Text("Des séances pour bouger et se détendre. Leurs bénéfices concernent la santé générale : aucune n'a d'effet démontré sur la repousse des cheveux.")
                }

                ForEach(ArticleCategory.allCases) { category in
                    Section(category.label) {
                        ForEach(ArticleLibrary.all.filter { $0.category == category }) { article in
                            NavigationLink(value: ExploreRoute.article(article.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(article.title).font(.body.weight(.medium))
                                    Text("\(article.readMinutes) min de lecture · \(article.subtitle)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                Section("Transparence") {
                    NavigationLink(value: ExploreRoute.evidence) {
                        Label("Fiches de preuve", systemImage: "checkmark.seal")
                    }
                    NavigationLink(value: ExploreRoute.sources) {
                        Label("Sources scientifiques", systemImage: "books.vertical")
                    }
                }

                Section {
                    NavigationLink(value: ExploreRoute.article("signes-a-faire-examiner")) {
                        Label("Quand consulter un médecin", systemImage: "stethoscope")
                            .foregroundStyle(Color.gtAlert)
                    }
                }
            }
            .navigationTitle("Explorer")
            .navigationDestination(for: ExploreRoute.self) { route in
                switch route {
                case .exercise(let id):
                    if let exercise = ExerciseLibrary.exercise(id: id) { ExerciseDetailView(exercise: exercise) }
                case .article(let id):
                    if let article = ArticleLibrary.article(id: id) { ArticleView(article: article) }
                case .evidence:
                    EvidenceLibraryView()
                case .sources:
                    SourcesListView()
                }
            }
            .fullScreenCover(item: $session) { session in
                switch session {
                case .breathing:
                    BreathingSessionView(minutes: 3) { markRoutine(kind: .guidedBreathing) }
                case .massage:
                    ScalpMassageSessionView { markRoutine(kind: .guidedScalpMassage) }
                }
            }
            .task { openDemoScreenIfNeeded() }
        }
    }

    private var recommendations: [ExerciseRecommendation] {
        guard let profile = model.profile else { return [] }
        return ExerciseRecommender.recommend(profile: profile, checkIns: Array(model.checkIns.values), today: DayKey(.now))
    }

    private func sessionRow(title: String, detail: String, symbol: String, card: EvidenceCard,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: GT.Spacing.m) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.gtGrowth.opacity(0.12), in: .circle)
                    .foregroundStyle(Color.gtGrowth)
                VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                    EvidenceBadge(level: card.evidence)
                }
                Spacer()
                Image(systemName: "play.fill").foregroundStyle(.secondary)
            }
            .padding(.vertical, GT.Spacing.xxs)
        }
    }

    /// Une séance réalisée depuis Explorer coche l'habitude correspondante si elle fait partie de la routine.
    private func markRoutine(kind: HabitKind) {
        guard let item = model.activeRoutine.first(where: { $0.kind == kind }) else { return }
        model.setCompleted(true, item: item, on: DayKey(.now))
    }

    private func openDemoScreenIfNeeded() {
        switch DemoLaunch.screen {
        case "exercise", "exerciseSession": path = [.exercise("renforcement-poids-du-corps")]
        case "article": path = [.article("alopecie-androgenetique")]
        default: break
        }
    }
}

struct EvidenceLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: EvidenceCard?

    var body: some View {
        List {
            ForEach(RecommendationCategory.allCases, id: \.self) { category in
                let cards = EvidenceCatalog.all.filter { $0.category == category }
                if !cards.isEmpty {
                    Section(category.label) {
                        ForEach(cards) { card in
                            Button { selected = card } label: {
                                VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                                    Text(card.title).foregroundStyle(.primary)
                                    EvidenceBadge(level: card.evidence)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fiches de preuve")
        .sheet(item: $selected) { card in
            EvidenceSheet(card: card, library: model.library)
        }
    }
}

struct SourcesListView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var sources: [SourceReference] {
        let all = model.library.sorted
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.authorsOrOrg.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(sources) { SourceRow(source: $0) }
            } footer: {
                Text("Growtin' et son futur assistant ne citent que des références de cette base. Chaque référence indique sa date de vérification et la méthode utilisée.")
            }
        }
        .navigationTitle("Sources")
        .searchable(text: $query, prompt: "Titre ou auteur")
        .overlay {
            if sources.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
