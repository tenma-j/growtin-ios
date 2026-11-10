import GrowtinCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editingProfile = false
    @State private var confirmingDeletion = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = model.profile {
                    Section("Mon profil") {
                        LabeledContent("Prénom", value: profile.displayName ?? "Non renseigné")
                        LabeledContent("Programme commencé le",
                                       value: profile.programStartDate.formatted(date: .long, time: .omitted))
                        if let stage = profile.stage.stage {
                            LabeledContent(profile.stage.scale.name, value: "Stade \(stage) (auto-évaluation)")
                        }
                        Button("Modifier mes réponses", systemImage: "square.and.pencil") { editingProfile = true }
                    }

                    Section {
                        Picker("Photos de suivi", selection: Binding(
                            get: { profile.photoFrequency },
                            set: { model.updatePhotoFrequency($0) })) {
                            ForEach(PhotoFrequency.allCases) { Text($0.label).tag($0) }
                        }
                    } header: {
                        Text("Suivi")
                    } footer: {
                        Text("Un rythme espacé limite les variations trompeuses dues à la lumière, à l'angle ou au coiffage.")
                    }

                    Section {
                        Toggle("Personnaliser l'assistant avec mon historique", isOn: Binding(
                            get: { profile.consents.aiPersonalization },
                            set: { model.setAIPersonalization($0) }))
                        if profile.consents.coachConsentAt != nil {
                            Button("Retirer mon accord pour le Coach", role: .destructive) { model.revokeCoachConsent() }
                        }
                        NavigationLink("Comment mes données sont utilisées") { PrivacyExplanationView() }
                    } header: {
                        Text("Confidentialité")
                    } footer: {
                        Text("Tes données restent sur cet iPhone. Seules tes questions au Coach (et, si tu l'as autorisé, un résumé de ton profil) sont envoyées, au moment où tu les poses.")
                    }
                }

                SubscriptionSettingsSection()

                Section("À propos") {
                    NavigationLink("Sources scientifiques") { SourcesListView() }
                    Text(WellnessNotice.short)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }

                Section {
                    Button("Supprimer toutes mes données", systemImage: "trash", role: .destructive) {
                        confirmingDeletion = true
                    }
                } footer: {
                    Text("Supprime définitivement ton profil, ta routine, ton historique, tes bilans, tes photos, ta conversation avec le Coach et tes rappels, ainsi que ton compte serveur anonyme.")
                }
            }
            .navigationTitle("Profil et réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé", systemImage: "checkmark") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $editingProfile) {
                if let profile = model.profile {
                    OnboardingFlowView(mode: .edit(profile))
                }
            }
            .confirmationDialog("Supprimer toutes tes données ?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Supprimer définitivement", role: .destructive) {
                    Task {
                        await model.deleteAllData()
                        dismiss()
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action est irréversible.")
            }
        }
    }
}

struct PrivacyExplanationView: View {
    var body: some View {
        List {
            Section("Où sont tes données") {
                Text("Tes réponses, ta routine, ton historique et tes bilans sont enregistrés uniquement sur cet iPhone, dans un fichier chiffré par iOS tant que l'appareil est verrouillé.")
            }
            Section("Ce que Growtin' ne fait jamais") {
                Label("Revendre tes données de santé", systemImage: "xmark.circle")
                Label("Utiliser tes données pour la publicité", systemImage: "xmark.circle")
                Label("Entraîner des modèles d'IA sans ton consentement explicite", systemImage: "xmark.circle")
                Label("Accéder à Apple Santé ou à tes photos sans ton autorisation", systemImage: "xmark.circle")
                Label("Envoyer tes photos à un serveur ou à une IA", systemImage: "xmark.circle")
            }
            Section("Le Coach") {
                Text("Quand tu poses une question, elle est transmise à un serveur hébergé dans l'Union européenne (Supabase), puis au modèle d'IA Claude d'Anthropic. Si tu as activé la personnalisation, un résumé de ton profil et de tes derniers bilans l'accompagne, sans ton prénom, ton âge exact ni tes photos.")
                Text("La conversation reste sur ton iPhone. Le serveur ne conserve qu'un identifiant anonyme et le nombre de questions posées. « Supprimer toutes mes données » efface aussi ce compte serveur.")
            }
            Section("Prochaines versions") {
                Text("Lorsque la sauvegarde et la synchronisation seront disponibles, Growtin' te demandera ton accord avant tout envoi et te permettra d'exporter toutes tes données.")
            }
        }
        .navigationTitle("Tes données")
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
