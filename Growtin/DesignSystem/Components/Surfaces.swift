import SwiftUI

/// Carte de contenu opaque. Le verre n'est pas utilisé ici, afin de préserver la lisibilité du contenu.
struct GTCard<Content: View>: View {
    var padding: CGFloat = GT.Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.s) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.card))
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: GT.Spacing.s)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Bouton d'action principal : Liquid Glass « prominent », pleine largeur.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, GT.Spacing.xxs)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

/// Petite note de bas d'écran (avertissement de bien-être, précisions).
struct FootnoteText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, GT.Spacing.m)
    }
}

enum WellnessNotice {
    static let short = "Growtin' est une application de bien-être. Elle ne pose aucun diagnostic et ne remplace pas l'avis d'un médecin ou d'un dermatologue."
    static let regularity = "La régularité mesure les habitudes que tu as choisies. Ce n'est pas un indicateur de santé capillaire."
}

/// Écran clairement identifié comme non encore développé : aucun bouton factice.
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let description: String
    let plannedFeatures: [String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: GT.Spacing.l) {
                    ContentUnavailableView {
                        Label(title, systemImage: systemImage)
                    } description: {
                        Text(description)
                    }
                    GTCard {
                        Text("En cours de développement")
                            .gtEyebrowStyle()
                        ForEach(plannedFeatures, id: \.self) { feature in
                            Label(feature, systemImage: "circle.dashed")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color.gtBackground)
            .navigationTitle(title)
        }
    }
}

#Preview("Carte et bouton") {
    VStack(spacing: 20) {
        GTCard {
            SectionHeader(title: "Ma routine", subtitle: "3 habitudes aujourd'hui")
            Text("Contenu de la carte")
        }
        PrimaryButton(title: "Continuer") {}
        FootnoteText(text: WellnessNotice.short)
    }
    .padding()
    .background(Color.gtBackground)
}
