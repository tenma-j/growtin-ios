import GrowtinCore
import StoreKit
import SwiftUI

enum LegalLinks {
    /// Contrat de licence standard d'Apple (utilisable tant que Growtin' n'a pas ses propres conditions).
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://github.com/tenma-j/growtin-ios/blob/main/docs/legal/confidentialite.md")!
}

/// Écran d'abonnement : formules, prix localisés, conditions de renouvellement, restauration, liens légaux.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?

    private var store: SubscriptionStore { model.subscription }
    private var selected: SubscriptionOffer? { store.offers.first { $0.id == selectedID } ?? store.offers.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GT.Spacing.l) {
                    header
                    benefits
                    if store.status.isActive {
                        activeState
                    } else if !store.isAvailable {
                        Label("Les abonnements seront bientôt disponibles.", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if store.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        offersList
                    }
                    if let message = store.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    legal
                }
                .padding(GT.Spacing.l)
            }
            .background(Color.gtBackground)
            .safeAreaInset(edge: .bottom) {
                if store.isAvailable, !store.status.isActive, let selected {
                    VStack(spacing: GT.Spacing.xs) {
                        PrimaryButton(title: selected.freeTrial != nil ? "Commencer l'essai gratuit" : "S'abonner — \(selected.priceLine)",
                                      isEnabled: !store.isPurchasing) {
                            Task { if await store.purchase(selected) { dismiss() } }
                        }
                        Button("Restaurer mes achats") { Task { await store.restore() } }
                            .font(.footnote.weight(.semibold))
                            .disabled(store.isPurchasing)
                    }
                    .padding(.horizontal, GT.Spacing.l)
                    .padding(.top, GT.Spacing.s)
                    .padding(.bottom, GT.Spacing.s)
                    .background(Color.gtBackground)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await store.loadOffers() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.gtGrowth)
                .accessibilityHidden(true)
            Text("Growtin' Premium").font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text("Plus d'accompagnement au quotidien, avec la même rigueur.").font(.title3).foregroundStyle(.secondary)
        }
    }

    private var benefits: some View {
        GTCard {
            ForEach(PremiumBenefits.current) { benefit in
                HStack(alignment: .top, spacing: GT.Spacing.s) {
                    Image(systemName: benefit.symbol).foregroundStyle(Color.gtGrowth).frame(width: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.title).font(.subheadline.weight(.semibold))
                        Text(benefit.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Label(PremiumBenefits.alwaysFree, systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var offersList: some View {
        VStack(spacing: GT.Spacing.s) {
            ForEach(store.offers) { offer in
                let isSelected = (selected?.id == offer.id)
                Button { selectedID = offer.id } label: {
                    HStack(alignment: .top) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.gtGrowth : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(offer.title).font(.headline)
                                if let monthly = store.offers.first(where: { $0.period.months == 1 }),
                                   let saving = offer.savings(comparedTo: monthly) {
                                    Text("−\(saving) %")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.gtGrowth.opacity(0.15), in: .capsule)
                                        .foregroundStyle(Color.gtGrowth)
                                }
                            }
                            Text(offer.priceLine).font(.subheadline.monospacedDigit())
                            if let trial = offer.freeTrial {
                                Text("Essai gratuit de \(trial.durationLabel)").font(.caption).foregroundStyle(Color.gtGrowth)
                            }
                        }
                        Spacer()
                    }
                    .padding(GT.Spacing.m)
                    .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: GT.Radius.card).strokeBorder(isSelected ? Color.gtInk : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            if let selected {
                Text(selected.renewalTerms).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var activeState: some View {
        GTCard {
            Label("Tu es abonné à Premium", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.gtGrowth)
            Text(store.status.summary { $0.formatted(date: .long, time: .omitted) }).font(.subheadline)
        }
    }

    private var legal: some View {
        HStack(spacing: GT.Spacing.m) {
            Link("Conditions d'utilisation", destination: LegalLinks.terms)
            Link("Confidentialité", destination: LegalLinks.privacy)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }
}

/// Section « Abonnement » des réglages.
struct SubscriptionSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var showingPaywall = false
    @State private var showingManage = false

    var body: some View {
        let store = model.subscription
        Section {
            LabeledContent("Formule", value: store.status.summary { $0.formatted(date: .abbreviated, time: .omitted) })
            if store.status.isActive {
                Button("Gérer mon abonnement", systemImage: "creditcard") { showingManage = true }
            } else {
                Button("Découvrir Premium", systemImage: "sparkles") { showingPaywall = true }
            }
            Button("Restaurer mes achats", systemImage: "arrow.clockwise") { Task { await store.restore() } }
                .disabled(!store.isAvailable || store.isPurchasing)
            if let message = store.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Abonnement")
        } footer: {
            Text(PremiumBenefits.alwaysFree)
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .manageSubscriptionsSheet(isPresented: $showingManage)
    }
}
