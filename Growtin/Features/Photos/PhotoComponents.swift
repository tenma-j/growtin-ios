import GrowtinCore
import SwiftUI

/// Miniature d'une photo de suivi, chargée depuis le stockage local.
struct PhotoThumbnail: View {
    @Environment(AppModel.self) private var model
    let entry: PhotoEntry
    var size: CGFloat = 72
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.gtSurfaceRaised
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size * 4 / 3)
        .clipShape(.rect(cornerRadius: GT.Radius.small))
        .task(id: entry.id) { image = model.photoStore.thumbnail(fileName: entry.fileName) }
        .accessibilityLabel("Photo \(entry.zone.label) du \(entry.takenAt.formatted(date: .long, time: .omitted))")
    }
}

/// Image pleine résolution, avec indicateur de chargement.
struct StoredPhotoView: View {
    @Environment(AppModel.self) private var model
    let entry: PhotoEntry
    var contentMode: ContentMode = .fit
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                ProgressView()
            }
        }
        .task(id: entry.id) { image = model.photoStore.image(fileName: entry.fileName) }
    }
}

/// Repères de cadrage dessinés par-dessus l'aperçu de la caméra.
struct FramingGuide: View {
    let zone: PhotoZone

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let stroke = StrokeStyle(lineWidth: 2, dash: [8, 6])
            let color = GraphicsContext.Shading.color(.white.opacity(0.85))
            switch zone {
            case .frontalHairline:
                let face = CGRect(x: w * 0.2, y: h * 0.18, width: w * 0.6, height: h * 0.55)
                context.stroke(Path(ellipseIn: face), with: color, style: stroke)
                var line = Path()
                line.move(to: CGPoint(x: w * 0.25, y: h * 0.36))
                line.addLine(to: CGPoint(x: w * 0.75, y: h * 0.36))
                context.stroke(line, with: color, style: StrokeStyle(lineWidth: 2))
            case .leftTemple, .rightTemple:
                let isLeft = zone == .leftTemple
                let head = CGRect(x: w * (isLeft ? 0.22 : 0.18), y: h * 0.18, width: w * 0.6, height: h * 0.55)
                context.stroke(Path(ellipseIn: head), with: color, style: stroke)
                let templeX = isLeft ? head.minX + head.width * 0.28 : head.maxX - head.width * 0.28
                context.stroke(Path(ellipseIn: CGRect(x: templeX - w * 0.09, y: h * 0.3, width: w * 0.18, height: w * 0.18)),
                               with: color, style: StrokeStyle(lineWidth: 2))
            case .top, .vertex, .centralPart:
                let radius = min(w, h) * 0.34
                let center = CGPoint(x: w / 2, y: h * 0.45)
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                               with: color, style: stroke)
                var cross = Path()
                cross.move(to: CGPoint(x: center.x - 14, y: center.y))
                cross.addLine(to: CGPoint(x: center.x + 14, y: center.y))
                cross.move(to: CGPoint(x: center.x, y: center.y - 14))
                cross.addLine(to: CGPoint(x: center.x, y: center.y + 14))
                context.stroke(cross, with: color, style: StrokeStyle(lineWidth: 2))
                if zone == .centralPart {
                    var part = Path()
                    part.move(to: CGPoint(x: center.x, y: center.y - radius))
                    part.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                    context.stroke(part, with: color, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Pastille d'état (lumière, angle) sur l'écran de capture.
struct StatusPill: View {
    let text: String
    let systemImage: String
    let isOK: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, GT.Spacing.s)
            .padding(.vertical, GT.Spacing.xs)
            .foregroundStyle(isOK ? Color.gtGrowth : Color.gtRegularity)
            .glassEffect(.regular, in: .capsule)
    }
}

extension QualityAssessment.Level {
    var tint: Color {
        switch self {
        case .good: .gtGrowth
        case .acceptable: .gtRegularity
        case .poor: .gtAlert
        }
    }

    var symbol: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .acceptable: "exclamationmark.circle"
        case .poor: "xmark.circle"
        }
    }
}

extension ComparabilityReport.Level {
    var tint: Color {
        switch self {
        case .high: .gtGrowth
        case .medium: .gtRegularity
        case .low: .gtAlert
        }
    }
}

/// Carte de comparabilité entre deux photos.
struct ComparabilityCard: View {
    let report: ComparabilityReport

    var body: some View {
        GTCard {
            Label(report.level.label, systemImage: report.level == .high ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(report.level.tint)
            Text("\(report.daysApart) jours d'écart")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(report.reasons, id: \.self) { reason in
                Label(reason, systemImage: "info.circle")
                    .font(.footnote)
            }
            Text(ComparabilityReport.disclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
