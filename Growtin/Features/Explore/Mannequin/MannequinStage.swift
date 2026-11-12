import Foundation
import GrowtinCore
import SceneKit
import simd
import UIKit

/// Studio 3D du personnage : corps et vêtements articulés, sol et fond lumineux, ombres douces, accessoires, caméra.
/// L'animation est calculée image par image : poses clés interpolées, ou captures réelles rejouées.
final class MannequinStage: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let turntable = SCNNode()          // rotation libre au doigt
    private let container = SCNNode()          // angle de vue propre au mouvement
    private let propsNode = SCNNode()
    private var meshNodes: [SCNNode] = []
    private var boneNodes: [SCNNode] = []
    private var asset: MannequinAsset?
    private let library: MotionLibrary?

    // État d'animation, partagé avec le fil de rendu.
    private struct Key {
        let time: Double
        let rotations: [simd_quatf]
        let rootPosition: SIMD3<Float>
        let ease: String?
    }
    private let lock = NSLock()
    private var keys: [Key] = []
    private var duration: Double = 1
    private var startTime: TimeInterval?
    private var fromRotations: [simd_quatf]?
    private var fromRoot: SIMD3<Float>?
    private var transitionStart: TimeInterval?
    private var lastRotations: [simd_quatf] = []
    private var lastRoot: SIMD3<Float> = .zero
    private let transitionDuration = 0.5

    private(set) var currentBody: MannequinBody?
    private(set) var currentMotion: String?
    private var aspect: Float = 1
    private var framing: (motion: Motion, keyPositions: [[Vec3]])?
    private var requestedMotion: String?
    private var appliedMotion: String?

    /// Studio lumineux : fond uni, sol mat éclairé qui se fond dans le fond au loin (brouillard de la même couleur).
    /// Un peu plus tamisé quand l'app est en apparence sombre.
    static func backdrop(dark: Bool) -> UIColor {
        dark ? UIColor(red: 0.80, green: 0.812, blue: 0.806, alpha: 1) : UIColor(red: 0.905, green: 0.918, blue: 0.91, alpha: 1)
    }
    /// Teinte du sol calculée pour qu'une fois éclairé il ait la couleur du fond : pas de ligne d'horizon visible.
    private static func floorColor(dark: Bool) -> UIColor {
        dark ? UIColor(red: 0.752, green: 0.764, blue: 0.758, alpha: 1) : UIColor(red: 0.85, green: 0.862, blue: 0.856, alpha: 1)
    }
    private let floorMaterial = MannequinStage.pbr(MannequinStage.floorColor(dark: false), roughness: 1)
    private var isDark: Bool?

    override init() {
        library = MotionCatalog.library
        super.init()
        scene.fogStartDistance = 5
        scene.fogEndDistance = 14
        scene.rootNode.addChildNode(turntable)
        turntable.addChildNode(container)
        container.addChildNode(propsNode)
        setUpLights()
        setUpFloor()
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.05
        camera.zFar = 40
        camera.screenSpaceAmbientOcclusionIntensity = 1.1
        camera.screenSpaceAmbientOcclusionRadius = 0.12
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        setDark(false)
    }

    /// Studio clair (mode clair) ou sombre (mode sombre).
    func setDark(_ dark: Bool) {
        guard dark != isDark else { return }
        isDark = dark
        let backdrop = Self.backdrop(dark: dark)
        scene.background.contents = backdrop
        scene.fogColor = backdrop
        floorMaterial.diffuse.contents = Self.floorColor(dark: dark)
    }

    // MARK: - Corps

    func setBody(_ body: MannequinBody) {
        guard body != currentBody, let asset = try? MannequinAsset.load(body) else { return }
        currentBody = body
        meshNodes.forEach { $0.removeFromParentNode() }
        boneNodes.first?.removeFromParentNode()

        // Squelette : un nœud par articulation, orientations neutres dans la pose de référence.
        var nodes: [SCNNode] = []
        for (i, joint) in asset.skeleton.joints.enumerated() {
            let node = SCNNode()
            node.name = joint.name
            if let p = asset.skeleton.parentIndex[i] {
                let d = joint.position - asset.skeleton.joints[p].position
                node.simdPosition = SIMD3(Float(d.x), Float(d.y), Float(d.z))
                nodes[p].addChildNode(node)
            } else {
                let h = joint.position
                node.simdPosition = SIMD3(Float(h.x), Float(h.y), Float(h.z))
                container.addChildNode(node)
            }
            nodes.append(node)
        }
        let inverseBinds: [NSValue] = asset.skeleton.joints.map { joint in
            let h = joint.position
            return NSValue(scnMatrix4: SCNMatrix4MakeTranslation(Float(-h.x), Float(-h.y), Float(-h.z)))
        }
        let materials = [Self.skinMaterial(), Self.fabricMaterial(), Self.accentMaterial()]
        var newMeshNodes: [SCNNode] = []
        for mesh in asset.meshes {
            let geometry = mesh.geometry.copy() as! SCNGeometry
            geometry.materials = [materials[min(mesh.material, materials.count - 1)]]
            let node = SCNNode(geometry: geometry)
            node.castsShadow = true
            let skinner = SCNSkinner(baseGeometry: geometry, bones: nodes, boneInverseBindTransforms: inverseBinds,
                                     boneWeights: mesh.boneWeights, boneIndices: mesh.boneIndices)
            skinner.skeleton = nodes.first
            node.skinner = skinner
            container.addChildNode(node)
            newMeshNodes.append(node)
        }

        lock.lock()
        self.asset = asset
        meshNodes = newMeshNodes
        boneNodes = nodes
        lastRotations = Array(repeating: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), count: nodes.count)
        lastRoot = nodes.first?.simdPosition ?? .zero
        lock.unlock()

        if let motion = requestedMotion {
            appliedMotion = nil
            play(motion)
        }
    }

    // MARK: - Mouvement

    /// Joue un mouvement en boucle, avec une transition douce depuis la pose actuelle.
    func play(_ motionID: String) {
        requestedMotion = motionID
        guard motionID != appliedMotion else { return }
        guard let asset, let library, let motion = library.motion(motionID) ?? library.motion("breathe-stand") else { return }
        appliedMotion = motionID
        currentMotion = motionID

        let skeleton = asset.skeleton
        let rootBind = skeleton.joints[0].position
        // Décalages de la racine calculés sur le squelette de référence : mis à l'échelle de ce corps.
        let scale = library.referenceHeight.map { rootBind.y / max($0, 0.1) } ?? 1
        func scaled(_ pose: ResolvedPose) -> ResolvedPose {
            var pose = pose
            pose.rootOffset = pose.rootOffset * scale
            return pose
        }
        func key(_ pose: ResolvedPose, time: Double, lift: Double, ease: String?) -> Key {
            let rotations = skeleton.joints.enumerated().map { (i, joint) -> simd_quatf in
                var q = pose.rotations[joint.name] ?? .identity
                if skeleton.parentIndex[i] == nil { q = pose.rootRotation * q }
                return simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
            }
            let root = rootBind + pose.rootOffset
            return Key(time: time, rotations: rotations,
                       rootPosition: SIMD3(Float(root.x), Float(root.y + lift), Float(root.z)), ease: ease)
        }

        var computed: [Key] = []
        var jointPositions: [[Vec3]] = []
        if let clip = motion.clip {
            // Capture réelle : une image clé par image, posée au sol (calculée une image sur deux, puis interpolée).
            let count = clip.frames.count
            var lifts = [Double](repeating: 0, count: count)
            for i in stride(from: 0, to: count, by: 2) {
                lifts[i] = Grounding.lift(for: clip.pose(at: i), skeleton: skeleton, samples: asset.samples, stride: 2)
            }
            for i in stride(from: 1, to: count, by: 2) {
                lifts[i] = i + 1 < count ? (lifts[i - 1] + lifts[i + 1]) / 2 : lifts[i - 1]
            }
            for i in 0..<count {
                let pose = clip.pose(at: i)
                computed.append(key(pose, time: Double(i) / clip.fps, lift: lifts[i], ease: "linear"))
                if i % 6 == 0 { jointPositions.append(skeleton.worldTransforms(pose, rootLift: lifts[i]).positions) }
            }
            if count > 0 {
                computed.append(key(clip.pose(at: 0), time: Double(count) / clip.fps, lift: lifts[0], ease: "linear"))
            }
        } else {
            var lift = 0.0
            for frame in motion.keys {
                let pose = scaled(library.resolve(frame.pose))
                if pose.ground { lift = Grounding.lift(for: pose, skeleton: skeleton, samples: asset.samples) }
                computed.append(key(pose, time: frame.t, lift: lift, ease: frame.ease))
                jointPositions.append(skeleton.worldTransforms(pose, rootLift: lift).positions)
            }
        }

        lock.lock()
        fromRotations = lastRotations
        fromRoot = lastRoot
        transitionStart = nil
        startTime = nil
        keys = computed
        duration = max(motion.duration, 0.1)
        lock.unlock()

        buildProps(motion.props, keyPositions: jointPositions)
        framing = (motion, jointPositions)
        frameCamera(animated: true)
    }

    /// Rotation libre du personnage au doigt (en radians).
    func spin(by angle: Float) {
        turntable.simdOrientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0)) * turntable.simdOrientation
    }

    /// Revient à l'angle de vue d'origine.
    func resetSpin() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        turntable.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        SCNTransaction.commit()
    }

    /// Appelé quand la vue change de taille.
    func setAspect(_ value: Float) {
        guard value.isFinite, value > 0, abs(value - aspect) > 0.01 else { return }
        aspect = value
        frameCamera(animated: false)
    }

    // MARK: - Rendu image par image

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard keys.count > 1, boneNodes.count == keys[0].rotations.count else { return }
        if startTime == nil {
            startTime = time
            transitionStart = time
            if fromRotations == nil { fromRotations = lastRotations; fromRoot = lastRoot }
        }
        let t = (time - startTime!).truncatingRemainder(dividingBy: duration)

        var k = 0
        while k + 1 < keys.count && keys[k + 1].time <= t { k += 1 }
        let a = keys[k], b = keys[min(k + 1, keys.count - 1)]
        let span = b.time - a.time
        let u = span > 0 ? Float(Easing.value((t - a.time) / span, b.ease)) : 0

        var rotations = zip(a.rotations, b.rotations).map { simd_slerp($0, $1, u) }
        var root = simd_mix(a.rootPosition, b.rootPosition, SIMD3(repeating: u))

        if let from = fromRotations, let fromRoot, let start = transitionStart {
            let blend = Float(min(1, (time - start) / transitionDuration))
            let s = blend * blend * (3 - 2 * blend)
            if blend >= 1 {
                fromRotations = nil
            } else if from.count == rotations.count {
                rotations = zip(from, rotations).map { simd_slerp($0, $1, s) }
                root = simd_mix(fromRoot, root, SIMD3(repeating: s))
            }
        }
        for (node, q) in zip(boneNodes, rotations) { node.simdOrientation = q }
        boneNodes.first?.simdPosition = root
        lastRotations = rotations
        lastRoot = root
    }

    // MARK: - Matières

    private static func pbr(_ color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    /// Peau de mannequin : gris clair satiné.
    static func skinMaterial() -> SCNMaterial {
        pbr(UIColor(red: 0.75, green: 0.745, blue: 0.735, alpha: 1), roughness: 0.55)
    }

    /// Tissu technique sombre, mat.
    static func fabricMaterial() -> SCNMaterial {
        pbr(UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1), roughness: 0.82)
    }

    /// Liseré vert Growtin'.
    static func accentMaterial() -> SCNMaterial {
        pbr(UIColor(red: 0.08, green: 0.53, blue: 0.31, alpha: 1), roughness: 0.6)
    }

    // MARK: - Studio

    private func setUpLights() {
        func light(_ type: SCNLight.LightType, intensity: CGFloat, color: UIColor = .white, euler: SIMD3<Float>, shadow: Bool = false) {
            let l = SCNLight()
            l.type = type
            l.intensity = intensity
            l.color = color
            if shadow {
                l.castsShadow = true
                l.shadowMode = .deferred
                l.shadowColor = UIColor.black.withAlphaComponent(0.4)
                l.shadowRadius = 12
                l.shadowSampleCount = 16
                l.shadowMapSize = CGSize(width: 2048, height: 2048)
                l.orthographicScale = 3
                l.automaticallyAdjustsShadowProjection = true
            }
            let node = SCNNode()
            node.light = l
            node.simdEulerAngles = euler
            scene.rootNode.addChildNode(node)
        }
        light(.directional, intensity: 920, color: UIColor(red: 1, green: 0.98, blue: 0.95, alpha: 1),
              euler: SIMD3(-0.95, -0.55, 0), shadow: true)                                         // principale, en hauteur
        light(.directional, intensity: 380, color: UIColor(red: 0.88, green: 0.92, blue: 1, alpha: 1), euler: SIMD3(-0.3, 1.1, 0))
        light(.directional, intensity: 300, euler: SIMD3(-0.25, 2.9, 0))                          // contre-jour discret
        light(.ambient, intensity: 260, color: UIColor(white: 0.85, alpha: 1), euler: .zero)
    }

    private func setUpFloor() {
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.materials = [floorMaterial]
        let node = SCNNode(geometry: floor)
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
    }

    private func buildProps(_ props: [MotionProp], keyPositions: [[Vec3]]) {
        propsNode.childNodes.forEach { $0.removeFromParentNode() }
        guard let asset else { return }
        let wood = Self.pbr(UIColor(red: 0.62, green: 0.47, blue: 0.33, alpha: 1), roughness: 0.65)
        let dark = Self.pbr(UIColor(red: 0.18, green: 0.18, blue: 0.2, alpha: 1), roughness: 0.5, metalness: 0.4)
        let wall = Self.pbr(UIColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1), roughness: 0.95)
        let mat = Self.pbr(UIColor(red: 0.35, green: 0.56, blue: 0.46, alpha: 1), roughness: 0.92)

        for prop in props {
            let keyIndex = min(max(prop.key ?? 0, 0), max(keyPositions.count - 1, 0))
            var anchor = Vec3.zero
            if let name = prop.anchor, let index = asset.skeleton.index[name], keyIndex < keyPositions.count {
                anchor = keyPositions[keyIndex][index]
            }
            let o = prop.offset.count == 3 ? Vec3(prop.offset[0], prop.offset[1], prop.offset[2]) : .zero
            var a = anchor + o
            if prop.floor == true { a.y = 0 }
            let node = SCNNode()
            node.simdPosition = SIMD3(Float(a.x), 0, Float(a.z))
            node.simdEulerAngles = SIMD3(0, Float((prop.yaw ?? 0) * .pi / 180), 0)
            let top = Float(max(a.y, 0.05))
            func box(_ w: Float, _ h: Float, _ l: Float, _ at: SIMD3<Float>, _ material: SCNMaterial, chamfer: Float = 0.008) {
                let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: CGFloat(chamfer))
                g.materials = [material]
                let n = SCNNode(geometry: g)
                n.simdPosition = at
                n.castsShadow = true
                node.addChildNode(n)
            }
            switch prop.kind {
            case "chair":
                box(0.44, 0.035, 0.42, SIMD3(0, top - 0.018, 0), wood, chamfer: 0.012)
                box(0.44, 0.30, 0.025, SIMD3(0, top + 0.30, -0.2), wood, chamfer: 0.01)
                for x: Float in [-0.19, 0.19] {
                    for z: Float in [-0.18, 0.18] { box(0.026, top - 0.035, 0.026, SIMD3(x, (top - 0.035) / 2, z), dark, chamfer: 0.004) }
                    box(0.026, 0.32, 0.026, SIMD3(x, top + 0.14, -0.2), dark, chamfer: 0.004)
                }
            case "table":
                box(1.0, 0.035, 0.64, SIMD3(0, top - 0.018, 0.1), wood, chamfer: 0.01)
                for x: Float in [-0.45, 0.45] {
                    for z: Float in [-0.18, 0.38] { box(0.04, top - 0.035, 0.04, SIMD3(x, (top - 0.035) / 2, z), dark, chamfer: 0.004) }
                }
            case "wall":
                box(0.08, 2.4, 3.0, SIMD3(0.04, 1.2, 0), wall, chamfer: 0)
            case "mat":
                box(1.85, 0.012, 0.64, SIMD3(0, 0.006, 0), mat, chamfer: 0.005)
            case "door":
                // Montants juste à l'extérieur des avant-bras, quelle que soit la carrure du personnage.
                var half: Float = 0.5
                if let wrist = asset.skeleton.index["wrist.L"], keyIndex < keyPositions.count {
                    half = Float(abs(keyPositions[keyIndex][wrist].x - a.x)) + 0.08
                }
                for x in [-half, half] { box(0.07, 2.05, 0.12, SIMD3(x, 1.025, 0), wall, chamfer: 0.006) }
                box(2 * half + 0.07, 0.07, 0.12, SIMD3(0, 2.085, 0), wall, chamfer: 0.006)
            default:
                continue
            }
            node.opacity = 0
            propsNode.addChildNode(node)
            node.runAction(.fadeIn(duration: 0.4))
        }
    }

    /// Cadre la caméra sur l'ensemble des poses du mouvement, sous l'angle choisi pour ce mouvement.
    private func frameCamera(animated: Bool) {
        guard let framing else { return }
        let motion = framing.motion
        let yaw = Float(motion.camera.yaw * .pi / 180)
        let pitch = Float(max(motion.camera.pitch ?? 8, 6) * .pi / 180)
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let rot = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        for positions in framing.keyPositions {
            for p in positions {
                let v = rot.act(SIMD3(Float(p.x), Float(p.y), Float(p.z)))
                lo = simd_min(lo, v); hi = simd_max(hi, v)
            }
        }
        guard lo.x.isFinite else { return }
        let margin: Float = 0.2
        lo -= margin; hi += margin
        lo.y = 0
        let center = (lo + hi) / 2
        let width = hi.x - lo.x, height = hi.y - lo.y, depth = hi.z - lo.z
        let vfov = Float(30 * Double.pi / 180)
        let hfov = 2 * atan(tan(vfov / 2) * aspect)
        let distance = max(height / 2 / tan(vfov / 2), width / 2 / tan(hfov / 2)) * 1.06 + depth / 2
        let target = SIMD3(center.x, center.y * 0.95, center.z)
        let eye = target + SIMD3(0, sin(pitch), cos(pitch)) * distance

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.simdOrientation = rot
        turntable.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        cameraNode.simdPosition = eye
        cameraNode.simdLook(at: target)
        SCNTransaction.commit()
    }
}
