import GrowtinCore
import SwiftUI

struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @State private var session: GuidedSession?

    enum GuidedSession: String, Identifiable {
        case breathing, massage
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    sessionRow(title: "Respiration lente", detail: "3 minutes · gestion du stress",
                               symbol: "wind", card: EvidenceCatalog.slowBreathing) { session = .breathing }
                    sessionRow(title: "Massage du cuir chevelu", detail: "4 minutes · détente",
                               symbol: "hand.raised", card: EvidenceCatalog.scalpMassage) { session = .massage }
                } header: {
                    Text("Séances guidées")
                } footer: {
                    Text("Marche, mobilité, étirements et yoga arrivent dans une prochaine version, avec démonstrations visuelles et précautions.")
                }

                Section("Comprendre") {
                    NavigationLink {
                        EvidenceLibraryView()
                    } label: {
                        Label("Fiches de preuve", systemImage: "checkmark.seal")
                    }
                    NavigationLink {
                        SourcesListView()
                    } label: {
                        Label("Sources scientifiques", systemImage: "books.vertical")
                    }
                    Label("Bibliothèque éducative (cycle du cheveu, types d'alopécie, traitements, idées reçues) : prochaine version",
                          systemImage: "circle.dashed")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                Section {
                    Text("Consulte un médecin ou un dermatologue en cas de chute brutale, de plaques, de douleur, de rougeurs ou de tout symptôme inhabituel.")
                        .font(.subheadline)
                } header: {
                    Text("Quand consulter")
                }
            }
            .navigationTitle("Explorer")
            .fullScreenCover(item: $session) { session in
                switch session {
                case .breathing:
                    BreathingSessionView(minutes: 3) { markRoutine(kind: .guidedBreathing) }
                case .massage:
                    ScalpMassageSessionView { markRoutine(kind: .guidedScalpMassage) }
                }
            }
        }
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
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
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
