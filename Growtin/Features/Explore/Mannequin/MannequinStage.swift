import Foundation
import GrowtinCore
import SceneKit
import simd
import UIKit

/// Scène 3D du personnage : corps articulé, lumières, ombre au sol, accessoires et caméra.
/// L'animation est calculée image par image (interpolation sphérique entre les poses de motions.json).
final class MannequinStage: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let container = SCNNode()          // tourne selon l'angle de vue du mouvement
    private let propsNode = SCNNode()
    private var bodyNode: SCNNode?
    private var boneNodes: [SCNNode] = []
    private var asset: MannequinAsset?
    private var material: SCNMaterial?
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
    private var paused = false
    private let transitionDuration = 0.45

    private(set) var currentBody: MannequinBody?
    private(set) var currentMotion: String?

    override init() {
        library = MotionCatalog.library
        super.init()
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(container)
        container.addChildNode(propsNode)
        setUpLights()
        setUpFloor()
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.05
        camera.zFar = 30
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Corps

    func setBody(_ body: MannequinBody) {
        guard body != currentBody, let asset = try? MannequinAsset.load(body) else { return }
        currentBody = body
        bodyNode?.removeFromParentNode()
        boneNodes.forEach { $0.removeFromParentNode() }

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

        let geometry = asset.geometry.copy() as! SCNGeometry
        let material = Self.makeMaterial()
        geometry.materials = [material]
        let mesh = SCNNode(geometry: geometry)
        mesh.name = "mannequin"
        mesh.castsShadow = true
        let skinner = SCNSkinner(baseGeometry: geometry, bones: nodes, boneInverseBindTransforms: inverseBinds,
                                 boneWeights: asset.boneWeights, boneIndices: asset.boneIndices)
        skinner.skeleton = nodes.first
        mesh.skinner = skinner
        container.addChildNode(mesh)

        lock.lock()
        self.asset = asset
        self.material = material
        boneNodes = nodes
        bodyNode = mesh
        lastRotations = Array(repeating: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), count: nodes.count)
        lastRoot = nodes.first?.simdPosition ?? .zero
        lock.unlock()

        if let motion = requestedMotion {
            appliedMotion = nil
            play(motion, focus: requestedFocus)
        }
    }

    // MARK: - Mouvement

    private var requestedMotion: String?
    private var requestedFocus: [String]?
    private var appliedMotion: String?
    private var appliedFocus: [String]?

    /// Joue un mouvement en boucle, avec une transition douce depuis la pose actuelle.
    func play(_ motionID: String, focus: [String]? = nil) {
        requestedMotion = motionID
        requestedFocus = focus
        guard motionID != appliedMotion || focus != appliedFocus else { return }
        guard let asset, let library, let motion = library.motion(motionID) ?? library.motion("breathe-stand") else { return }
        appliedMotion = motionID
        appliedFocus = focus
        currentMotion = motionID

        // Poses clés : rotations locales, racine posée au sol.
        var lift = 0.0
        var computed: [Key] = []
        var jointPositions: [[Vec3]] = []
        for key in motion.keys {
            let pose = library.resolve(key.pose)
            if pose.ground { lift = Grounding.lift(for: pose, skeleton: asset.skeleton, samples: asset.samples) }
            let rotations = asset.skeleton.joints.enumerated().map { (i, joint) -> simd_quatf in
                var q = pose.rotations[joint.name] ?? .identity
                if asset.skeleton.parentIndex[i] == nil { q = pose.rootRotation * q }
                return simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
            }
            let rootJoint = asset.skeleton.joints[0].position + pose.rootOffset
            computed.append(Key(time: key.t, rotations: rotations,
                                rootPosition: SIMD3(Float(rootJoint.x), Float(rootJoint.y + lift), Float(rootJoint.z)),
                                ease: key.ease))
            jointPositions.append(asset.skeleton.worldTransforms(pose, rootLift: lift).positions)
        }

        lock.lock()
        fromRotations = lastRotations
        fromRoot = lastRoot
        transitionStart = nil
        startTime = nil
        keys = computed
        duration = max(motion.duration, 0.1)
        lock.unlock()

        // Mise en valeur des muscles travaillés.
        let regions = focus ?? motion.muscles
        material?.setValue(NSNumber(value: asset.mask(for: regions)), forKey: "highlightMask")

        buildProps(motion.props, keyPositions: jointPositions)
        frameCamera(motion: motion, keyPositions: jointPositions)
    }

    func setPaused(_ value: Bool) {
        lock.lock(); paused = value; lock.unlock()
    }

    // MARK: - Rendu image par image

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard !keys.isEmpty, boneNodes.count == keys[0].rotations.count else { return }
        if paused {
            startTime = nil
            return
        }
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

    // MARK: - Mise en scène

    private static func makeMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        // Deux images blanches neutres : elles obligent SceneKit à transmettre les deux jeux de coordonnées
        // de texture (régions musculaires et part de tissu) au shader, sans changer la couleur.
        let white = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        m.diffuse.contents = white
        m.diffuse.mappingChannel = 0
        m.multiply.contents = white
        m.multiply.mappingChannel = 1
        m.roughness.contents = 0.55
        m.metalness.contents = 0.0
        m.isDoubleSided = false
        // Couleur calculée par sommet : peau gris clair, tenue sombre, muscles travaillés en orange (dégradé doux).
        m.shaderModifiers = [
            .geometry: """
            #pragma arguments
            float highlightMask;
            #pragma body
            float2 regions = _geometry.texcoords[0];
            float2 mixes = _geometry.texcoords[1];
            int mask = int(highlightMask + 0.5);
            float selA = float((mask >> int(regions.x + 0.5)) & 1);
            float selB = float((mask >> int(regions.y + 0.5)) & 1);
            float hi = mix(selA, selB, mixes.x);
            float fabric = smoothstep(0.3, 0.7, mixes.y);
            float3 skin = float3(0.62, 0.635, 0.66);
            float3 hot = float3(0.95, 0.20, 0.03);
            float3 cloth = float3(0.016, 0.016, 0.02);
            float3 clothHot = float3(0.10, 0.03, 0.01);
            float3 color = mix(mix(skin, hot, hi), mix(cloth, clothHot, hi), fabric);
            _geometry.color = float4(color, 1.0);
            """,
            .surface: """
            #pragma body
            float rim = pow(1.0 - saturate(dot(_surface.normal, _surface.view)), 3.0);
            _surface.emission.rgb += float3(0.30, 0.45, 1.0) * rim * 0.55;
            """
        ]
        m.setValue(NSNumber(value: 0), forKey: "highlightMask")
        return m
    }

    private func setUpLights() {
        func light(_ type: SCNLight.LightType, intensity: CGFloat, color: UIColor = .white, euler: SIMD3<Float>, shadow: Bool = false) {
            let l = SCNLight()
            l.type = type
            l.intensity = intensity
            l.color = color
            if shadow {
                l.castsShadow = true
                l.shadowMode = .deferred
                l.shadowColor = UIColor.black.withAlphaComponent(0.45)
                l.shadowRadius = 10
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
        light(.directional, intensity: 1150, euler: SIMD3(-0.95, -0.55, 0), shadow: true)          // principale, en hauteur
        light(.directional, intensity: 380, color: UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1), euler: SIMD3(-0.3, 1.1, 0))
        light(.directional, intensity: 650, color: UIColor(red: 0.55, green: 0.7, blue: 1, alpha: 1), euler: SIMD3(-0.25, 2.9, 0)) // contre-jour
        light(.ambient, intensity: 260, color: UIColor(white: 0.85, alpha: 1), euler: .zero)
    }

    private func setUpFloor() {
        let floor = SCNFloor()
        floor.reflectivity = 0
        let m = SCNMaterial()
        m.lightingModel = .shadowOnly
        floor.materials = [m]
        let node = SCNNode(geometry: floor)
        scene.rootNode.addChildNode(node)
    }

    private func buildProps(_ props: [MotionProp], keyPositions: [[Vec3]]) {
        propsNode.childNodes.forEach { $0.removeFromParentNode() }
        guard let asset else { return }
        let matte = SCNMaterial()
        matte.lightingModel = .physicallyBased
        matte.diffuse.contents = UIColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1)
        matte.roughness.contents = 0.7
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = UIColor(red: 0.16, green: 0.42, blue: 0.30, alpha: 1)
        mat.roughness.contents = 0.9

        for prop in props {
            let keyIndex = min(max(prop.key ?? 0, 0), keyPositions.count - 1)
            var anchor = Vec3.zero
            if let name = prop.anchor, let index = asset.skeleton.index[name], keyIndex >= 0 {
                anchor = keyPositions[keyIndex][index]
            }
            let o = prop.offset.count == 3 ? Vec3(prop.offset[0], prop.offset[1], prop.offset[2]) : .zero
            var a = anchor + o
            if prop.floor == true { a.y = 0 }
            let node = SCNNode()
            node.simdPosition = SIMD3(Float(a.x), 0, Float(a.z))
            node.simdEulerAngles = SIMD3(0, Float((prop.yaw ?? 0) * .pi / 180), 0)
            let top = Float(max(a.y, 0.05))
            func box(_ w: Float, _ h: Float, _ l: Float, _ at: SIMD3<Float>, _ material: SCNMaterial, chamfer: Float = 0.006) {
                let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: CGFloat(chamfer))
                g.materials = [material]
                let n = SCNNode(geometry: g)
                n.simdPosition = at
                n.castsShadow = true
                node.addChildNode(n)
            }
            switch prop.kind {
            case "chair":
                box(0.44, 0.04, 0.42, SIMD3(0, top - 0.02, 0), matte)
                box(0.44, 0.44, 0.03, SIMD3(0, top + 0.24, -0.2), matte)
                for x: Float in [-0.19, 0.19] {
                    for z: Float in [-0.18, 0.18] { box(0.035, top - 0.04, 0.035, SIMD3(x, (top - 0.04) / 2, z), matte, chamfer: 0.004) }
                }
            case "table":
                box(1.0, 0.04, 0.64, SIMD3(0, top - 0.02, 0.1), matte)
                for x: Float in [-0.45, 0.45] {
                    for z: Float in [-0.18, 0.38] { box(0.05, top - 0.04, 0.05, SIMD3(x, (top - 0.04) / 2, z), matte, chamfer: 0.004) }
                }
            case "wall":
                box(0.06, 2.2, 2.4, SIMD3(0.03, 1.1, 0), matte, chamfer: 0)
            case "mat":
                box(1.9, 0.008, 0.62, SIMD3(0, 0.004, 0), mat, chamfer: 0.003)
            default:
                continue
            }
            node.opacity = 0
            propsNode.addChildNode(node)
            node.runAction(.fadeIn(duration: 0.4))
        }
    }

    /// Cadre la caméra sur l'ensemble des poses du mouvement, sous l'angle choisi pour ce mouvement.
    private func frameCamera(motion: Motion, keyPositions: [[Vec3]]) {
        let yaw = Float(motion.camera.yaw * .pi / 180)
        let pitch = Float((motion.camera.pitch ?? 8) * .pi / 180)
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let rot = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        for positions in keyPositions {
            for p in positions {
                let v = rot.act(SIMD3(Float(p.x), Float(p.y), Float(p.z)))
                lo = simd_min(lo, v); hi = simd_max(hi, v)
            }
        }
        guard lo.x.isFinite else { return }
        let margin: Float = 0.16
        lo -= margin; hi += margin
        lo.y = 0
        let center = (lo + hi) / 2
        let width = hi.x - lo.x, height = hi.y - lo.y
        let fov = Float(30 * Double.pi / 180)
        let fit = max(height, width * 0.75) // l'écran est plus large que haut : on cadre surtout la hauteur
        let distance = fit / (2 * tan(fov / 2)) * 1.12 + (hi.z - lo.z) / 2
        let target = SIMD3(center.x, center.y, center.z)
        let eye = target + SIMD3(0, sin(pitch), cos(pitch)) * distance

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.6
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.simdOrientation = rot
        cameraNode.simdPosition = eye
        cameraNode.simdLook(at: target)
        SCNTransaction.commit()
    }
}
