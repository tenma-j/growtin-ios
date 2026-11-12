import GrowtinCore
import SceneKit
import SwiftUI

/// SCNView qui signale ses changements de taille et fait tourner le personnage au doigt (glissement horizontal).
final class MannequinSCNView: SCNView, UIGestureRecognizerDelegate {
    var onResize: ((CGSize) -> Void)?
    var onSpin: ((Float) -> Void)?
    var onReset: (() -> Void)?

    func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onResize?(bounds.size)
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let dx = pan.translation(in: self).x
        pan.setTranslation(.zero, in: self)
        onSpin?(Float(dx / max(bounds.width, 1)) * .pi * 1.5)
    }

    @objc private func handleDoubleTap() { onReset?() }

    /// Seuls les glissements horizontaux font tourner le personnage : le défilement vertical de la page reste libre.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.view === self else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let v = pan.velocity(in: self)
        return abs(v.x) > abs(v.y) * 1.2
    }
}

/// Vue SceneKit qui affiche le personnage 3D et joue un mouvement en boucle.
struct MannequinSceneView: UIViewRepresentable {
    let motion: String
    let figure: MannequinBody
    let dark: Bool

    func makeCoordinator() -> MannequinStage { MannequinStage() }

    func makeUIView(context: Context) -> MannequinSCNView {
        let stage = context.coordinator
        let view = MannequinSCNView(frame: .zero, options: nil)
        view.backgroundColor = MannequinStage.backdrop(dark: dark)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        view.scene = stage.scene
        view.pointOfView = stage.cameraNode
        view.delegate = stage
        view.isPlaying = true
        view.isAccessibilityElement = false
        view.installGestures()
        view.onResize = { [weak stage] size in
            guard size.height > 0 else { return }
            stage?.setAspect(Float(size.width / size.height))
        }
        view.onSpin = { [weak stage] angle in stage?.spin(by: angle) }
        view.onReset = { [weak stage] in stage?.resetSpin() }
        stage.setDark(dark)
        stage.setBody(figure)
        stage.play(motion)
        return view
    }

    func updateUIView(_ view: MannequinSCNView, context: Context) {
        view.backgroundColor = MannequinStage.backdrop(dark: dark)
        context.coordinator.setDark(dark)
        context.coordinator.setBody(figure)
        context.coordinator.play(motion)
    }

    static func dismantleUIView(_ view: MannequinSCNView, coordinator: MannequinStage) {
        view.onResize = nil
        view.onSpin = nil
        view.onReset = nil
        view.isPlaying = false
        view.delegate = nil
    }
}

/// Carte du personnage 3D : studio lumineux, choix femme / homme, rappel des zones travaillées.
struct MannequinCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let motion: String
    var caption: String?
    var height: CGFloat = 320
    @AppStorage("mannequin.figure") private var storedFigure = ""

    private var figure: MannequinBody {
        MannequinBody(rawValue: storedFigure) ?? MannequinBody(sex: model.profile?.sex)
    }

    var body: some View {
        let dark = colorScheme == .dark
        ZStack(alignment: .topTrailing) {
            Color(uiColor: MannequinStage.backdrop(dark: dark))
            MannequinSceneView(motion: motion, figure: figure, dark: dark)
            Menu {
                Picker("Personnage", selection: Binding(get: { figure.rawValue }, set: { storedFigure = $0 })) {
                    ForEach(MannequinBody.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                Image(systemName: "person.2.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(9)
                    .glassEffect(.regular, in: .circle)
            }
            .padding(GT.Spacing.s)
            .environment(\.colorScheme, .light)
            .accessibilityLabel("Choisir le personnage : femme ou homme")
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: GT.Spacing.xs) {
                    if let caption {
                        HStack(spacing: GT.Spacing.xs) {
                            Circle().fill(Color.gtGrowth).frame(width: 7, height: 7)
                            Text(caption).font(.caption.weight(.medium)).foregroundStyle(.primary.opacity(0.85))
                        }
                        .padding(.horizontal, GT.Spacing.s)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "rotate.3d")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .glassEffect(.regular, in: .circle)
                        .accessibilityHidden(true)
                }
                .padding(GT.Spacing.s)
            }
            .environment(\.colorScheme, .light)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(.rect(cornerRadius: GT.Radius.card))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Animation 3D du mouvement. Fais glisser horizontalement pour tourner le personnage.")
    }
}

/// Libellés des zones du corps sollicitées.
enum BodyRegionLabel {
    static func text(_ regions: [String]) -> String? {
        let names: [String: String] = [
            "neck": "nuque", "shoulders": "épaules", "chest": "poitrine", "upperBack": "haut du dos", "lowerBack": "bas du dos",
            "abs": "abdominaux", "biceps": "biceps", "triceps": "triceps", "forearms": "avant-bras", "hands": "mains",
            "glutes": "fessiers", "quads": "cuisses (avant)", "hamstrings": "ischio-jambiers", "calves": "mollets",
            "shins": "chevilles", "feet": "pieds", "head": "visage et tête",
        ]
        let labels = regions.compactMap { names[$0] }
        guard !labels.isEmpty else { return nil }
        return "Zones sollicitées : " + labels.prefix(3).joined(separator: ", ")
    }
}
