import Foundation
import GrowtinCore
import Metal
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
    private var asset: MannequinAsset?

    /// Corps déformé sur le processeur, normales recalculées sur la surface déformée (voir `SurfaceDeformer`) :
    /// chaque maillage lit ses positions et normales dans deux tampons Metal réécrits à chaque image.
    /// Le skinning de SceneKit se contentait de tourner les normales avec les os : épaule bras levés, l'éclairage
    /// faisait apparaître une tache blanche.
    private struct DeformedMesh {
        let range: Range<Int>
        let positions: MTLBuffer
        let normals: MTLBuffer
    }
    private var deformer: SurfaceDeformer?
    private var deformedMeshes: [DeformedMesh] = []
    /// Repli sans Metal : skinning SceneKit, un nœud par articulation.
    private var boneNodes: [SCNNode] = []
    private var jointCount = 0

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
    /// Articulations d'appoint (indice, os doublé) : recalculées à chaque image, la moitié de la rotation de l'os.
    private var halfPairs: [(joint: Int, source: Int)] = []
    private let transitionDuration = 0.5
    /// Serviette tenue à deux mains et coincée sous un pied : trois tronçons de bande (brin gauche, passage à plat
    /// sous la voûte du pied, brin droit), recalculés à chaque image d'après trois sommets de la peau déformée
    /// (main gauche, dessous du pied, main droite) ; voir `TowelPath`.
    private struct Towel {
        let bands: [SCNNode]
        let vertices: [Int]
        let under: [[Double]]
        let thickness: Double
    }
    private var towel: Towel?
    /// Décor en place (accessoires et points d'ancrage) : gardé tel quel si le mouvement suivant demande le même.
    private var builtProps: (props: [MotionProp], anchors: [Vec3])?
    /// Le dernier cadrage était resserré sur une zone du corps : la caméra en revient aussi doucement qu'elle y va.
    private var wasTight = false

    private(set) var currentBody: MannequinBody?
    private(set) var currentMotion: String?
    private var aspect: Float = 1
    private var framing: (motion: Motion, keyPositions: [[Vec3]])?
    private var requestedMotion: String?
    private var appliedMotion: String?
    /// Le premier cadrage est immédiat (pas de caméra qui part du sol) ; les suivants sont animés.
    private var hasFramed = false

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
        // Position d'attente, en face du personnage, avant le premier cadrage.
        cameraNode.simdPosition = SIMD3(0, 1.05, 5.6)
        cameraNode.simdLook(at: SIMD3(0, 0.9, 0))
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

        let materials = [Self.skinMaterial(), Self.fabricMaterial(), Self.accentMaterial()]
        func material(_ index: Int) -> SCNMaterial { materials[min(max(index, 0), materials.count - 1)] }
        var newMeshNodes: [SCNNode] = []
        var nodes: [SCNNode] = []
        var newDeformer: SurfaceDeformer?
        var newDeformed: [DeformedMesh] = []

        if let device = MTLCreateSystemDefaultDevice(), let cpu = SurfaceDeformer(surface: asset.file.surface, skeleton: asset.skeleton) {
            for mesh in asset.meshes {
                let length = max(mesh.vertexRange.count, 1) * 12
                guard let positions = device.makeBuffer(length: length, options: .storageModeShared),
                      let normals = device.makeBuffer(length: length, options: .storageModeShared) else { break }
                // Pose de référence jusqu'à la première image.
                cpu.copy(vertices: mesh.vertexRange, positions: positions.contents(), normals: normals.contents())
                newDeformed.append(DeformedMesh(range: mesh.vertexRange, positions: positions, normals: normals))
            }
            if newDeformed.count == asset.meshes.count {
                newDeformer = cpu
                for (mesh, buffers) in zip(asset.meshes, newDeformed) {
                    let count = mesh.vertexRange.count
                    let geometry = SCNGeometry(sources: [
                        SCNGeometrySource(buffer: buffers.positions, vertexFormat: .float3, semantic: .vertex, vertexCount: count,
                                          dataOffset: 0, dataStride: 12),
                        SCNGeometrySource(buffer: buffers.normals, vertexFormat: .float3, semantic: .normal, vertexCount: count,
                                          dataOffset: 0, dataStride: 12),
                    ], elements: [mesh.element])
                    geometry.materials = [material(mesh.material)]
                    // Boîte englobante fixe et large : la surface change à chaque image (allongé, assis, bras levés).
                    geometry.boundingBox = (min: SCNVector3(x: -1.6, y: -0.4, z: -1.6), max: SCNVector3(x: 1.6, y: 2.6, z: 1.6))
                    let node = SCNNode(geometry: geometry)
                    node.castsShadow = true
                    container.addChildNode(node)
                    newMeshNodes.append(node)
                }
            } else {
                newDeformed = []
            }
        }

        if newDeformer == nil {
            // Repli : squelette SceneKit, un nœud par articulation, orientations neutres dans la pose de référence.
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
            for mesh in asset.meshes {
                let skinned = asset.skinnedGeometry(for: mesh)
                skinned.geometry.materials = [material(mesh.material)]
                let node = SCNNode(geometry: skinned.geometry)
                node.castsShadow = true
                let skinner = SCNSkinner(baseGeometry: skinned.geometry, bones: nodes, boneInverseBindTransforms: inverseBinds,
                                         boneWeights: skinned.boneWeights, boneIndices: skinned.boneIndices)
                skinner.skeleton = nodes.first
                node.skinner = skinner
                container.addChildNode(node)
                newMeshNodes.append(node)
            }
        }

        // Aucun appel à SceneKit sous le verrou (le fil de rendu le prend en tenant déjà la scène).
        let rootPosition = asset.skeleton.joints.first.map { SIMD3(Float($0.position.x), Float($0.position.y), Float($0.position.z)) } ?? .zero
        let pairs = asset.skeleton.halfSource.enumerated().compactMap { i, s in s.map { (joint: i, source: $0) } }
        let count = asset.skeleton.joints.count
        lock.lock()
        self.asset = asset
        meshNodes = newMeshNodes
        boneNodes = nodes
        deformer = newDeformer
        deformedMeshes = newDeformed
        jointCount = count
        halfPairs = pairs
        lastRotations = Array(repeating: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), count: count)
        lastRoot = rootPosition
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
        // Chaque corps a sa propre version des mouvements (mains jointes, pieds posés au bon endroit).
        guard let asset, let body = currentBody, let library = MotionCatalog.library(for: body),
              let motion = library.motion(motionID) ?? library.motion("breathe-stand") else { return }
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
            let rotations = skeleton.localRotations(pose).map { q in
                simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
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
                if pose.ground { lift = Grounding.lift(for: pose, skeleton: skeleton, samples: asset.samples) + (motion.support ?? 0) }
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
        frameCamera(animated: hasFramed)
        hasFramed = true
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
        guard keys.count > 1, jointCount == keys[0].rotations.count else { return }
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
        // Appoints exacts à chaque image : la moitié de la rotation interpolée de leur os.
        for pair in halfPairs where pair.joint < rotations.count && pair.source < rotations.count {
            rotations[pair.joint] = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), rotations[pair.source], 0.5)
        }
        if let deformer {
            deformer.deform(rotations: rotations.map(\.vector), root: root)
            for mesh in deformedMeshes {
                deformer.copy(vertices: mesh.range, positions: mesh.positions.contents(), normals: mesh.normals.contents())
            }
            if let towel {
                let p = deformer.positions
                func point(_ i: Int) -> Vec3 { Vec3(Double(p[i * 3]), Double(p[i * 3 + 1]), Double(p[i * 3 + 2])) }
                func float(_ v: Vec3) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)) }
                // Cachée pendant la transition depuis le mouvement précédent : les mains n'en tiennent pas encore les bouts.
                let segments: [TowelPath.Segment]? = fromRotations == nil
                    ? TowelPath.segments(leftHand: point(towel.vertices[0]), foot: point(towel.vertices[1]),
                                         rightHand: point(towel.vertices[2]), under: towel.under, thickness: towel.thickness)
                    : nil
                for (i, node) in towel.bands.enumerated() {
                    guard let segments, i < segments.count else { node.isHidden = true; continue }
                    let segment = segments[i]
                    let from = float(segment.from), to = float(segment.to)
                    // Bande de longueur 1 le long de Y : étirée du point de départ au point d'arrivée, largeur selon X.
                    node.simdTransform = simd_float4x4(columns: (
                        SIMD4<Float>(float(segment.side), 0), SIMD4<Float>(to - from, 0),
                        SIMD4<Float>(float(segment.normal), 0), SIMD4<Float>((from + to) / 2, 1)))
                    node.isHidden = false
                }
            }
        } else {
            for (node, q) in zip(boneNodes, rotations) { node.simdOrientation = q }
            boneNodes.first?.simdPosition = root
        }
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

    /// Bande de longueur 1 le long de Y (de y = −0,5 à y = 0,5), largeur selon X, épaisseur selon Z ;
    /// la section peut changer d'un bout à l'autre (serviette resserrée dans le poing).
    private static func band(from start: (width: Float, thickness: Float), to end: (width: Float, thickness: Float),
                             material: SCNMaterial) -> SCNGeometry {
        let b = SIMD2<Float>(start.width / 2, start.thickness / 2), t = SIMD2<Float>(end.width / 2, end.thickness / 2)
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(-b.x, -0.5, -b.y), SIMD3<Float>(b.x, -0.5, -b.y), SIMD3<Float>(b.x, -0.5, b.y), SIMD3<Float>(-b.x, -0.5, b.y),
            SIMD3<Float>(-t.x, 0.5, -t.y), SIMD3<Float>(t.x, 0.5, -t.y), SIMD3<Float>(t.x, 0.5, t.y), SIMD3<Float>(-t.x, 0.5, t.y),
        ]
        // Six faces, sommets dans le sens direct vus de l'extérieur ; normales à plat (sommets non partagés).
        let faces: [[Int]] = [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for face in faces {
            let p = face.map { corners[$0] }
            let n = simd_normalize(simd_cross(p[1] - p[0], p[2] - p[0]))
            let base = Int32(positions.count)
            for v in p {
                positions.append(SCNVector3(x: v.x, y: v.y, z: v.z))
                normals.append(SCNVector3(x: n.x, y: n.y, z: n.z))
            }
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }

    /// Point d'ancrage d'un accessoire : articulation d'une image clé, plus son décalage.
    private static func anchorPoint(of prop: MotionProp, skeleton: Skeleton, keyPositions: [[Vec3]]) -> Vec3 {
        let keyIndex = min(max(prop.key ?? 0, 0), max(keyPositions.count - 1, 0))
        var anchor = Vec3.zero
        if let name = prop.anchor, let index = skeleton.index[name], keyIndex < keyPositions.count, index < keyPositions[keyIndex].count {
            anchor = keyPositions[keyIndex][index]
        }
        var a = anchor + (prop.offset.count == 3 ? Vec3(prop.offset[0], prop.offset[1], prop.offset[2]) : Vec3.zero)
        if prop.floor == true { a.y = 0 }
        return a
    }

    private func buildProps(_ props: [MotionProp], keyPositions: [[Vec3]]) {
        // Même décor au même endroit (étapes du scan corporel, toutes dans le même lit) : il reste en place,
        // sans disparaître ni réapparaître en fondu.
        var anchors: [Vec3] = []
        if let skeleton = asset?.skeleton {
            anchors = props.map { Self.anchorPoint(of: $0, skeleton: skeleton, keyPositions: keyPositions) }
            if let built = builtProps, built.props == props, built.anchors.count == anchors.count,
               zip(built.anchors, anchors).allSatisfy({ ($0 - $1).length < 0.004 }) {
                return
            }
        }
        builtProps = nil
        propsNode.childNodes.forEach { $0.removeFromParentNode() }
        lock.lock(); let oldTowel = towel; towel = nil; let canDeform = deformer != nil; lock.unlock()
        oldTowel?.bands.forEach { $0.removeFromParentNode() }
        guard let asset else { return }
        builtProps = (props: props, anchors: anchors)
        let wood = Self.pbr(UIColor(red: 0.62, green: 0.47, blue: 0.33, alpha: 1), roughness: 0.65)
        let dark = Self.pbr(UIColor(red: 0.18, green: 0.18, blue: 0.2, alpha: 1), roughness: 0.5, metalness: 0.4)
        let wall = Self.pbr(UIColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1), roughness: 0.95)
        let mat = Self.pbr(UIColor(red: 0.35, green: 0.56, blue: 0.46, alpha: 1), roughness: 0.92)
        let linen = Self.pbr(UIColor(red: 0.93, green: 0.925, blue: 0.91, alpha: 1), roughness: 0.95)
        let pillowCloth = Self.pbr(UIColor(red: 0.97, green: 0.965, blue: 0.95, alpha: 1), roughness: 0.95)
        let throwCloth = Self.pbr(UIColor(red: 0.55, green: 0.66, blue: 0.6, alpha: 1), roughness: 0.95)

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
            case "bed":
                // Lit le long de X, tête vers −X : sommier en bois, matelas épais aux bords arrondis, tête de lit,
                // plaid replié au pied. Posé au sol, le matelas est à 50 cm ; sinon il arrive sous l'ancre.
                let mattressTop = prop.floor == true ? Float(0.5) : top
                let frameTop = mattressTop - 0.19
                for x: Float in [-0.92, 0.92] {
                    for z: Float in [-0.64, 0.64] { box(0.06, 0.1, 0.06, SIMD3(x, 0.05, z), dark, chamfer: 0.01) }
                }
                box(2.0, max(frameTop - 0.1, 0.05), 1.46, SIMD3(0, (frameTop + 0.1) / 2, 0), wood, chamfer: 0.02)
                box(1.96, 0.2, 1.42, SIMD3(0, mattressTop - 0.1, 0), linen, chamfer: 0.06)
                box(0.07, mattressTop + 0.45, 1.46, SIMD3(-1.03, (mattressTop + 0.45) / 2, 0), wood, chamfer: 0.025)
                box(0.42, 0.05, 1.38, SIMD3(0.7, mattressTop + 0.02, 0), throwCloth, chamfer: 0.025)
            case "pillow":
                box(0.34, 0.1, 0.56, SIMD3(0, top - 0.05, 0), pillowCloth, chamfer: 0.045)
            case "door":
                // Montants juste à l'extérieur des avant-bras, quelle que soit la carrure du personnage.
                var half: Float = 0.5
                if let wrist = asset.skeleton.index["wrist.L"], keyIndex < keyPositions.count {
                    half = Float(abs(keyPositions[keyIndex][wrist].x - a.x)) + 0.08
                }
                for x in [-half, half] { box(0.07, 2.05, 0.12, SIMD3(x, 1.025, 0), wall, chamfer: 0.006) }
                box(2 * half + 0.07, 0.07, 0.12, SIMD3(0, 2.085, 0), wall, chamfer: 0.006)
            case "towel":
                guard let ids = prop.vertices, ids.count == 3, canDeform,
                      ids.allSatisfy({ $0 >= 0 && $0 < asset.file.surface.rest.count / 3 }),
                      let under = prop.under, under.count == 2, under.allSatisfy({ $0.count == 2 }) else { continue }
                let cloth = Self.pbr(UIColor(red: 0.42, green: 0.63, blue: 0.78, alpha: 1), roughness: 0.95)
                let flat = (width: Float(prop.width ?? TowelPath.defaultWidth), thickness: Float(prop.thickness ?? TowelPath.defaultThickness))
                let grip = (width: Float(TowelPath.gripWidth), thickness: Float(TowelPath.gripThickness))
                // Brin gauche (du sol au poing), passage à plat sous le pied, brin droit (du sol au poing).
                let geometries = [Self.band(from: flat, to: grip, material: cloth), Self.band(from: flat, to: flat, material: cloth),
                                  Self.band(from: flat, to: grip, material: cloth)]
                let bands = geometries.map { geometry -> SCNNode in
                    let n = SCNNode(geometry: geometry)
                    n.castsShadow = true
                    n.isHidden = true
                    container.addChildNode(n)
                    return n
                }
                let held = Towel(bands: bands, vertices: ids, under: under, thickness: Double(flat.thickness))
                lock.lock(); towel = held; lock.unlock()
                continue
            default:
                continue
            }
            // Apparition en fondu ; l'opacité finale est fixée tout de suite, même si le rendu prend du retard.
            node.opacity = 0
            propsNode.addChildNode(node)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            node.opacity = 1
            SCNTransaction.commit()
        }
    }

    /// Cadre la caméra sur l'ensemble des poses du mouvement, sous l'angle choisi pour ce mouvement ; ou, si le
    /// mouvement le demande (`camera.frame`), sur une zone du corps dont elle se rapproche doucement.
    private func frameCamera(animated: Bool) {
        guard let framing else { return }
        let camera = framing.motion.camera
        var joints: [Int]?
        if let names = camera.frame, let skeleton = asset?.skeleton {
            let found = names.compactMap { skeleton.index[$0] }
            if !found.isEmpty { joints = found }
        }
        guard let shot = CameraFraming.shot(keyPositions: framing.keyPositions, joints: joints, yaw: camera.yaw, pitch: camera.pitch,
                                            margin: camera.margin, aspect: Double(aspect)) else { return }
        let rot = simd_quatf(angle: Float(camera.yaw * .pi / 180), axis: SIMD3<Float>(0, 1, 0))
        let target = SIMD3<Float>(Float(shot.target.x), Float(shot.target.y), Float(shot.target.z))
        let eye = SIMD3<Float>(Float(shot.eye.x), Float(shot.eye.y), Float(shot.eye.z))
        let tight = joints != nil
        let gentle = tight || wasTight
        wasTight = tight

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? (gentle ? 1.2 : 0.6) : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.simdOrientation = rot
        turntable.simdOrientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        cameraNode.simdPosition = eye
        cameraNode.simdLook(at: target)
        SCNTransaction.commit()
    }
}
