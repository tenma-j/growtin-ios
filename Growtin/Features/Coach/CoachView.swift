import GrowtinCore
import SwiftUI

struct CoachView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var selectedSource: SourceReference?
    @State private var confirmingClear = false
    @State private var showingPaywall = false
    @FocusState private var inputFocused: Bool

    private var coach: CoachStore { model.coach }
    private var hasConsent: Bool { model.profile?.consents.coachConsentAt != nil }

    var body: some View {
        NavigationStack {
            Group {
                if !coach.service.isAvailable {
                    ContentUnavailableView {
                        Label("Le Coach arrive bientôt", systemImage: "sparkles")
                    } description: {
                        Text("Le serveur du Coach n'est pas encore relié à l'application. En attendant, la bibliothèque de l'onglet Explorer répond aux questions les plus fréquentes, avec ses sources.")
                    }
                } else if !hasConsent {
                    CoachConsentView()
                } else {
                    conversation
                }
            }
            .background(Color.gtBackground)
            .navigationTitle("Coach")
            .toolbar {
                if hasConsent && !coach.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Options", systemImage: "ellipsis") {
                            Button("Effacer la conversation", systemImage: "trash", role: .destructive) { confirmingClear = true }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .confirmationDialog("Effacer la conversation ?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { coach.clearConversation() }
            } message: {
                Text("Les messages sont supprimés de cet iPhone. Le serveur n'en conserve aucun.")
            }
            .sheet(item: $selectedSource) { source in
                NavigationStack {
                    List { SourceRow(source: source) }
                        .navigationTitle("Source")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fermer", systemImage: "xmark") { selectedSource = nil }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GT.Spacing.m) {
                    Label("Le Coach donne des informations éducatives sourcées. Il ne pose pas de diagnostic et ne remplace pas un médecin.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if coach.messages.isEmpty {
                        starters
                    }
                    ForEach(coach.messages) { message in
                        CoachBubble(message: message, library: model.library) { selectedSource = $0 }
                            .id(message.id)
                    }
                    if coach.isSending {
                        HStack(spacing: GT.Spacing.xs) {
                            ProgressView()
                            Text("Le Coach réfléchit…").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .id("typing")
                    }
                    ForEach(coach.alerts) { SafetyBanner(alert: $0) }
                    if let error = coach.error {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Color.gtAlert)
                        if case .quotaReached = error, model.subscription.isAvailable, !model.subscription.status.isActive {
                            Button("Passer à Premium : 40 questions par jour", systemImage: "sparkles") { showingPaywall = true }
                                .gtProminentButton()
                        }
                    }
                }
                .padding(GT.Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: coach.messages.count) { _, _ in
                withAnimation { proxy.scrollTo(coach.messages.last?.id, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.s) {
            Text("Pose ta question").font(.title3.weight(.semibold))
            Text(model.profile?.consents.aiPersonalization == true
                 ? "Le Coach tient compte de ton profil et de tes derniers bilans."
                 : "La personnalisation est désactivée : le Coach ne voit que tes questions. Tu peux l'activer dans les réglages.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(CoachSuggestions.starters, id: \.self) { suggestion in
                Button {
                    submit(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .padding(GT.Spacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.control))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: GT.Spacing.xxs) {
            if let quota = coach.quota {
                Text(quota.premium ? "\(quota.remaining) questions restantes aujourd'hui"
                                   : "\(quota.remaining) question\(quota.remaining > 1 ? "s" : "") gratuite\(quota.remaining > 1 ? "s" : "") restante\(quota.remaining > 1 ? "s" : "") aujourd'hui")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: GT.Spacing.s) {
                TextField("Écris ta question…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, GT.Spacing.m)
                    .padding(.vertical, GT.Spacing.s)
                    .glassEffect(.regular, in: .rect(cornerRadius: GT.Radius.card))
                Button("Envoyer", systemImage: "arrow.up") { submit(draft) }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .gtProminentButton()
                    .buttonBorderShape(.circle)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.isSending)
            }
        }
        .padding(.horizontal, GT.Spacing.m)
        .padding(.bottom, GT.Spacing.s)
    }

    private func submit(_ text: String) {
        draft = ""
        let personalization = model.profile?.consents.aiPersonalization == true
        Task { await coach.send(text, personalization: personalization) { model.coachContext() } }
    }
}

private struct CoachBubble: View {
    let message: CoachMessage
    let library: SourceLibrary
    let onSource: (SourceReference) -> Void

    var body: some View {
        let isUser = message.role == .user
        VStack(alignment: isUser ? .trailing : .leading, spacing: GT.Spacing.xs) {
            Text(CoachText.plain(message.content))
                .font(.body)
                .foregroundStyle(isUser ? Color.gtOnInk : Color.primary)
                .padding(GT.Spacing.m)
                .background(isUser ? Color.gtInk : Color.gtSurface, in: .rect(cornerRadius: GT.Radius.card))
                .textSelection(.enabled)
            let sources = library.references(for: message.citations)
            if !sources.isEmpty {
                FlowLayout {
                    ForEach(sources) { source in
                        Button { onSource(source) } label: {
                            Label(source.shortCitation, systemImage: "book.closed")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, GT.Spacing.s)
                                .padding(.vertical, GT.Spacing.xxs + 2)
                                .background(Color.gtGrowth.opacity(0.12), in: .capsule)
                                .foregroundStyle(Color.gtGrowth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Affiche la source")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, GT.Spacing.xl)
    }
}

/// Consentement explicite avant le premier envoi.
struct CoachConsentView: View {
    @Environment(AppModel.self) private var model
    @State private var personalization = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GT.Spacing.l) {
                StepHeader(eyebrow: "Coach", title: "Avant de commencer",
                           subtitle: "Le Coach répond à tes questions en s'appuyant uniquement sur la base de sources vérifiées de Growtin'.")
                GTCard {
                    consentLine("lock.shield", "Ce qui est envoyé",
                                "Tes questions, et seulement si tu l'autorises ci-dessous, un résumé de ton profil et de tes derniers bilans. Jamais ton prénom ni ton âge exact. Tes photos ne sont envoyées que si tu demandes leur lecture, photo par photo.")
                    consentLine("server.rack", "Comment",
                                "Via un serveur sécurisé hébergé dans l'Union européenne, qui transmet ta question au modèle d'IA Claude, développé par Anthropic. Selon les conditions d'Anthropic, les données envoyées via son API ne servent pas à entraîner ses modèles.")
                    consentLine("iphone", "Ce qui est conservé",
                                "La conversation reste sur ton iPhone. Le serveur ne garde que le nombre de questions posées, pour les limites quotidiennes.")
                    consentLine("stethoscope", "Ses limites",
                                "Le Coach ne pose pas de diagnostic, ne prescrit rien et ne remplace pas un médecin.")
                }
                Toggle(isOn: $personalization) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personnaliser avec mon profil et mes bilans").font(.body.weight(.medium))
                        Text("Facultatif. Modifiable à tout moment dans les réglages.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                PrimaryButton(title: "J'accepte et je commence") {
                    model.acceptCoachConsent(personalization: personalization)
                }
            }
            .padding(GT.Spacing.l)
        }
        .onAppear { personalization = model.profile?.consents.aiPersonalization ?? false }
    }

    private func consentLine(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: GT.Spacing.s) {
            Image(systemName: symbol).foregroundStyle(Color.gtGrowth).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
