import SwiftUI

/// Ligne de choix unique, inversée lorsqu'elle est sélectionnée (style hérité de la web app).
struct ChoiceRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: GT.Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.medium))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(isSelected ? AnyShapeStyle(BackgroundStyle().opacity(0.75)) : AnyShapeStyle(.secondary))
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, GT.Spacing.m)
            .padding(.vertical, GT.Spacing.s + 2)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .foregroundStyle(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
            .background(isSelected ? Color.gtInk : Color.gtSurface, in: .rect(cornerRadius: GT.Radius.control))
            .contentShape(.rect(cornerRadius: GT.Radius.control))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Pastille de choix multiple.
struct ChoiceChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: GT.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(title)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, GT.Spacing.s + 2)
            .padding(.vertical, GT.Spacing.s)
            .foregroundStyle(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
            .background(isSelected ? Color.gtInk : Color.gtSurface, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Disposition en flux : les éléments passent à la ligne quand la largeur est atteinte.
struct FlowLayout: Layout {
    var spacing: CGFloat = GT.Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = fittedSize(of: subviews[index], maxWidth: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    /// Taille naturelle d'un élément, limitée à la largeur disponible (le texte passe alors à la ligne).
    private func fittedSize(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, natural.width > maxWidth else { return natural }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = fittedSize(of: subviews[index], maxWidth: width)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Grille de pastilles pour un ensemble d'options à choix multiple.
struct MultiChoiceChips<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Set<Option>
    let title: (Option) -> String
    var symbol: ((Option) -> String?)?
    /// Option qui désélectionne toutes les autres (« Aucun », « Je ne sais pas »).
    var exclusive: Option?

    var body: some View {
        FlowLayout {
            ForEach(options) { option in
                ChoiceChip(title: title(option), systemImage: symbol?(option), isSelected: selection.contains(option)) {
                    toggle(option)
                }
            }
        }
    }

    private func toggle(_ option: Option) {
        if selection.contains(option) {
            selection.remove(option)
        } else if option == exclusive {
            selection = [option]
        } else {
            if let exclusive { selection.remove(exclusive) }
            selection.insert(option)
        }
    }
}

/// Anneau de progression animé, accessible.
struct ProgressRing: View {
    /// Entre 0 et 1, ou `nil` lorsque la valeur n'est pas disponible.
    let progress: Double?
    var lineWidth: CGFloat = 10
    var tint: Color = .gtRegularity
    var label: String = "Régularité"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Color.gtSeparator.opacity(0.35), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(GT.Motion.adaptive(GT.Motion.standard, reduceMotion: reduceMotion), value: progress)
            Text(progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Non disponible")
    }
}

#Preview("Contrôles") {
    @Previewable @State var selection: Set<String> = ["Stress"]
    VStack(spacing: 16) {
        ChoiceRow(title: "6 mois à 2 ans", isSelected: true) {}
        ChoiceRow(title: "Plus de 5 ans", isSelected: false) {}
        ProgressRing(progress: 0.66).frame(width: 96, height: 96)
    }
    .padding()
    .background(Color.gtBackground)
}
