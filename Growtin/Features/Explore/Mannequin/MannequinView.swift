import GrowtinCore
import SceneKit
import SwiftUI

/// Vue SceneKit qui affiche le personnage 3D et joue un mouvement en boucle.
struct MannequinSceneView: UIViewRepresentable {
    let motion: String
    var focus: [String]?
    let figure: MannequinBody

    func makeCoordinator() -> MannequinStage { MannequinStage() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: nil)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.delegate = context.coordinator
        view.isPlaying = true
        view.isAccessibilityElement = false
        context.coordinator.setBody(figure)
        context.coordinator.play(motion, focus: focus)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.setBody(figure)
        context.coordinator.play(motion, focus: focus)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: MannequinStage) {
        view.isPlaying = false
        view.delegate = nil
    }
}

/// Carte du personnage 3D : fond sombre, choix femme / homme, rappel des muscles travaillés.
struct MannequinCard: View {
    @Environment(AppModel.self) private var model
    let motion: String
    var focus: [String]?
    var caption: String?
    var height: CGFloat = 320
    @AppStorage("mannequin.figure") private var storedFigure = ""

    private var figure: MannequinBody {
        MannequinBody(rawValue: storedFigure) ?? MannequinBody(sex: model.profile?.sex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RadialGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.19), Color(red: 0.04, green: 0.04, blue: 0.05)],
                           center: UnitPoint(x: 0.5, y: 0.42), startRadius: 8, endRadius: 360)
            MannequinSceneView(motion: motion, focus: focus, figure: figure)
            Menu {
                Picker("Personnage", selection: Binding(get: { figure.rawValue }, set: { storedFigure = $0 })) {
                    ForEach(MannequinBody.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                Image(systemName: "person.2.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .glassEffect(.regular, in: .circle)
            }
            .padding(GT.Spacing.s)
            .accessibilityLabel("Choisir le personnage : femme ou homme")
            if let caption {
                VStack {
                    Spacer()
                    HStack(spacing: GT.Spacing.xs) {
                        Circle().fill(Color(red: 0.98, green: 0.45, blue: 0.12)).frame(width: 8, height: 8)
                        Text(caption).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, GT.Spacing.s)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(GT.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(.rect(cornerRadius: GT.Radius.card))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Animation 3D du mouvement")
    }
}

/// Libellés des zones du corps mises en valeur.
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
