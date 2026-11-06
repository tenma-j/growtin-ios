import GrowtinCore
import SwiftUI

extension EvidenceLevel {
    var tint: Color {
        switch self {
        case .strong: .gtGrowth
        case .moderate: .teal
        case .limited: .gtRegularity
        case .generalHealthOnly: .blue
        case .insufficient: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .strong: "checkmark.seal.fill"
        case .moderate: "checkmark.seal"
        case .limited: "exclamationmark.triangle"
        case .generalHealthOnly: "heart"
        case .insufficient: "questionmark.circle"
        }
    }
}

struct EvidenceBadge: View {
    let level: EvidenceLevel

    var body: some View {
        Label(level.label, systemImage: level.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, GT.Spacing.xs + 2)
            .padding(.vertical, GT.Spacing.xxs + 1)
            .foregroundStyle(level.tint)
            .background(level.tint.opacity(0.12), in: .capsule)
            .accessibilityLabel("Niveau de preuve : \(level.label)")
    }
}

/// Fiche de preuve complète : explication, bénéfice, niveau de preuve, limites et sources vérifiées.
struct EvidenceSheet: View {
    let card: EvidenceCard
    var personalReason: String?
    let library: SourceLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: GT.Spacing.s) {
                        Label(card.category.label, systemImage: card.category.symbol)
                            .gtEyebrowStyle()
                        Text(card.title)
                            .font(.title2.weight(.bold))
                        EvidenceBadge(level: card.evidence)
                    }
                    .padding(.vertical, GT.Spacing.xs)
                }

                if let personalReason {
                    Section("Pourquoi pour toi") {
                        Text(personalReason)
                    }
                }

                Section("Explication") { Text(card.explanation) }

                Section("Bénéfice attendu") {
                    Label(card.expectedBenefit, systemImage: "arrow.up.right")
                        .foregroundStyle(Color.gtGrowth)
                }

                Section {
                    Text(card.limits)
                } header: {
                    Text("Limites et incertitudes")
                } footer: {
                    Text(card.evidence.explanation)
                }

                Section("Sources") {
                    let sources = library.references(for: card.sourceIDs)
                    if sources.isEmpty {
                        Text("Aucune source scientifique n'est citée pour ce conseil : il s'agit d'un outil de suivi, sans effet de santé revendiqué.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sources) { source in
                            SourceRow(source: source)
                        }
                    }
                }

                Section {
                    Text(WellnessNotice.short)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

struct SourceRow: View {
    let source: SourceReference

    var body: some View {
        Link(destination: source.url) {
            VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                Text(source.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(source.shortCitation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: GT.Spacing.xs) {
                    Text(source.type.label)
                    if let published = source.published { Text("· Publié : \(published)") }
                    Text("· Vérifié le \(source.verifiedOn)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text(source.keyFinding)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .padding(.vertical, GT.Spacing.xxs)
        }
        .accessibilityHint("Ouvre la source dans le navigateur")
    }
}

/// Bandeau d'orientation vers un professionnel de santé.
struct SafetyBanner: View {
    let alert: SafetyAlert

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.xs) {
            Label(alert.title, systemImage: alert.level == .information ? "info.circle" : "stethoscope")
                .font(.headline)
                .foregroundStyle(alert.level == .information ? Color.primary : Color.gtAlert)
            Text(alert.message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if alert.level == .seekHelpNow {
                HStack {
                    Link(destination: URL(string: "tel:3114")!) {
                        Label("Appeler le 3114", systemImage: "phone.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.gtAlert)
                    Link(destination: URL(string: "tel:112")!) {
                        Text("112")
                    }
                    .buttonStyle(.glass)
                }
                .padding(.top, GT.Spacing.xxs)
            }
        }
        .padding(GT.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((alert.level == .information ? Color.gtSurface : Color.gtAlert.opacity(0.1)),
                    in: .rect(cornerRadius: GT.Radius.card))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Fiche de preuve") {
    EvidenceSheet(card: EvidenceCatalog.scalpMassage,
                  personalReason: "Un moment de détente que beaucoup apprécient.",
                  library: (try? SourceLibrary.bundled()) ?? (try! SourceLibrary(sources: [])))
}
