import GrowtinCore
import SwiftUI

/// Point d'entrée « Lecture Growtin' » d'une photo : bouton, résultat enregistré, feuille de consentement.
struct PhotoReadingSection: View {
    @Environment(AppModel.self) private var model
    let entry: PhotoEntry
    /// Photo de référence imposée (écran de comparaison). Sinon, la précédente de la même zone.
    var reference: PhotoEntry?
    @State private var showingSheet = false

    private var current: PhotoEntry { model.photo(id: entry.id) ?? entry }
    private var previous: PhotoEntry? { reference ?? PhotoTimeline.previous(of: current, in: model.photos) }
    /// Une lecture comparée ne s'affiche ici que si elle porte sur la même paire de photos.
    private var reading: PhotoReading? {
        guard let reading = current.reading else { return nil }
        if let reference { return reading.comparedWith == reference.id ? reading : nil }
        return reading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.s) {
            if let reading {
                PhotoReadingCard(reading: reading, reference: reading.comparedWith.flatMap(model.photo(id:)))
            }
            if model.coach.service.isAvailable {
                Button(reading == nil ? (reference == nil ? "Lire cette photo avec Growtin'" : "Lire l'évolution avec Growtin'") : "Relire avec Growtin'",
                       systemImage: "eye") { showingSheet = true }
                    .gtProminentButton()
                    .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingSheet) {
            PhotoReadingConsentSheet(entry: current, previous: previous)
        }
        .task {
            if DemoLaunch.screen == "photoReadingConsent", reference == nil { showingSheet = true }
        }
    }
}

/// Consentement explicite, à chaque lecture : ce qui part, où, ce qui est gardé, et les limites.
struct PhotoReadingConsentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: PhotoEntry
    let previous: PhotoEntry?
    @State private var compare = true
    @State private var isReading = false
    @State private var error: CoachError?
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GT.Spacing.l) {
                    StepHeader(eyebrow: "Lecture de photo", title: "Un regard neutre sur ta photo",
                               subtitle: "Growtin' décrit ce qui est visible pour t'aider à mieux regarder tes photos. Ce n'est pas un examen médical.")
                    GTCard {
                        line("photo.on.rectangle", "Ce qui est envoyé",
                             compare && previous != nil
                             ? "Cette photo et celle du \(previous!.takenAt.formatted(date: .abbreviated, time: .omitted)), réduites et sans métadonnées (ni lieu, ni appareil), avec leurs conditions de prise de vue."
                             : "Cette photo, réduite et sans métadonnées (ni lieu, ni appareil), avec ses conditions de prise de vue.")
                        line("server.rack", "Comment",
                             "Via le serveur sécurisé de Growtin' dans l'Union européenne, vers le modèle d'IA Claude d'Anthropic. Selon les conditions d'Anthropic, les données envoyées via son API ne servent pas à entraîner ses modèles.")
                        line("iphone", "Ce qui est conservé",
                             "Le serveur n'enregistre pas la photo : elle est oubliée dès la lecture terminée. Le résultat reste sur ton iPhone.")
                        line("stethoscope", "Ses limites",
                             "Pas de diagnostic, de stade ni de pourcentage. Seul un médecin ou un dermatologue peut évaluer une chute de cheveux.")
                    }
                    if previous != nil {
                        Toggle("Comparer avec la photo précédente de cette zone", isOn: $compare)
                    }
                    if let quota = model.coach.quota, !quota.premium {
                        Label("Compte comme une question du Coach : \(quota.remaining) restante\(quota.remaining > 1 ? "s" : "") aujourd'hui.",
                              systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Color.gtAlert)
                        if case .quotaReached = error, model.subscription.isAvailable, !model.subscription.status.isActive {
                            Button("Passer à Premium : 40 lectures ou questions par jour", systemImage: "sparkles") { showingPaywall = true }
                                .gtProminentButton()
                        }
                    }
                }
                .padding(GT.Spacing.l)
            }
            .background(Color.gtBackground)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: isReading ? "Lecture en cours…" : "J'accepte, lire la photo", isEnabled: !isReading) {
                    Task { await read() }
                }
                .padding(.horizontal, GT.Spacing.l)
                .padding(.vertical, GT.Spacing.s)
                .background(Color.gtBackground)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .interactiveDismissDisabled(isReading)
        }
    }

    private func read() async {
        error = nil
        isReading = true
        defer { isReading = false }
        do {
            _ = try await model.readPhoto(entry, comparedWith: compare ? previous : nil)
            dismiss()
        } catch let coachError as CoachError {
            error = coachError
        } catch {
            self.error = .server("La lecture de la photo a échoué. Réessaie plus tard.")
        }
    }

    private func line(_ symbol: String, _ title: String, _ detail: String) -> some View {
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

/// Résultat d'une lecture, toujours accompagné du rappel médical.
struct PhotoReadingCard: View {
    let reading: PhotoReading
    let reference: PhotoEntry?

    var body: some View {
        GTCard {
            HStack {
                Label("Lecture Growtin'", systemImage: "eye").font(.headline)
                Spacer()
                Text(reading.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            if reading.seeProfessionalSoon {
                Label(PhotoReading.urgentAdvice, systemImage: "cross.case")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.gtAlert)
                    .padding(GT.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gtAlert.opacity(0.1), in: .rect(cornerRadius: GT.Radius.control))
            }
            block("Conditions de la photo") { Text(reading.conditions) }
            block("Ce qui est visible") { bullets(reading.observations) }
            if let comparison = reading.comparison {
                block(reference.map { "Par rapport au \($0.takenAt.formatted(date: .abbreviated, time: .omitted))" } ?? "Par rapport à la photo précédente") {
                    Text(comparison)
                }
            }
            if !reading.nextPhotoTips.isEmpty {
                block("Pour la prochaine photo") { bullets(reading.nextPhotoTips) }
            }
            Label(PhotoReading.disclaimer, systemImage: "stethoscope")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func block(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
            Text(title).gtEyebrowStyle()
            content().font(.subheadline)
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: GT.Spacing.xs) {
                    Text("•").foregroundStyle(Color.gtGrowth)
                    Text(item)
                }
            }
        }
    }
}
