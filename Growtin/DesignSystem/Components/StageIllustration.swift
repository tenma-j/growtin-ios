import GrowtinCore
import SwiftUI

/// Schéma vu du dessus (front en haut) d'un stade de Norwood ou de Ludwig.
/// Illustration purement indicative, destinée à l'auto-évaluation de l'utilisateur.
struct StageIllustration: View {
    let scale: HairStageScale
    let stage: Int

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
                .insetBy(dx: size.width * 0.14, dy: size.height * 0.06)
            let head = Path(ellipseIn: rect)
            context.fill(head, with: .color(Color.secondary.opacity(0.18)))
            context.drawLayer { layer in
                layer.fill(head, with: .color(Color.primary.opacity(0.85)))
                layer.blendMode = .destinationOut
                for cutout in cutouts(in: rect) {
                    layer.fill(cutout.path, with: .color(Color.black.opacity(cutout.opacity)))
                }
            }
            context.stroke(head, with: .color(Color.secondary.opacity(0.35)), lineWidth: 1)
        }
        .aspectRatio(0.8, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private struct Cutout {
        let path: Path
        var opacity: Double = 1
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func cutouts(in rect: CGRect) -> [Cutout] {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        switch scale {
        case .ludwig:
            // Raréfaction diffuse le long de la raie, ligne frontale conservée.
            let widths: [CGFloat] = [0.14, 0.3, 0.5]
            let opacities: [Double] = [0.45, 0.6, 0.75]
            let index = max(0, min(stage - 1, 2))
            let width = w * widths[index]
            let area = CGRect(x: rect.midX - width / 2, y: y + h * 0.14, width: width, height: h * 0.62)
            return [Cutout(path: Path(ellipseIn: area), opacity: opacities[index])]
        case .norwood:
            let templeRadius: [CGFloat] = [0, 0.1, 0.17, 0.21, 0.25, 0, 0]
            let crownRadius: [CGFloat] = [0, 0, 0, 0.12, 0.17, 0, 0]
            let index = max(0, min(stage - 1, 6))
            var result: [Cutout] = []
            let t = w * templeRadius[index]
            if t > 0 {
                result.append(Cutout(path: circle(CGPoint(x: x + w * 0.2, y: y + h * 0.1), t)))
                result.append(Cutout(path: circle(CGPoint(x: x + w * 0.8, y: y + h * 0.1), t)))
            }
            if index >= 3 && index <= 4 {
                result.append(Cutout(path: Path(ellipseIn: CGRect(x: rect.midX - w * 0.18, y: y - h * 0.02,
                                                                  width: w * 0.36, height: h * (index == 3 ? 0.14 : 0.2)))))
            }
            let c = w * crownRadius[index]
            if c > 0 { result.append(Cutout(path: circle(CGPoint(x: rect.midX, y: y + h * 0.62), c))) }
            if index == 5 {
                result.append(Cutout(path: Path(ellipseIn: CGRect(x: x + w * 0.16, y: y - h * 0.04, width: w * 0.68, height: h * 0.78))))
            } else if index == 6 {
                result.append(Cutout(path: Path(ellipseIn: CGRect(x: x + w * 0.1, y: y - h * 0.06, width: w * 0.8, height: h * 0.88))))
            }
            return result
        }
    }
}

#Preview("Stades") {
    VStack {
        HStack {
            ForEach(1...7, id: \.self) { StageIllustration(scale: .norwood, stage: $0).frame(width: 44) }
        }
        HStack {
            ForEach(1...3, id: \.self) { StageIllustration(scale: .ludwig, stage: $0).frame(width: 44) }
        }
    }
    .padding()
}
