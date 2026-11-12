import Foundation

// MARK: - Mathématiques (sans dépendance, testables partout)

public struct Vec3: Hashable, Sendable {
    public var x, y, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vec3(0, 0, 0)
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
}

/// Quaternion unitaire (x, y, z, w).
public struct Quat: Hashable, Sendable {
    public var x, y, z, w: Double
    public init(x: Double, y: Double, z: Double, w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
    public static let identity = Quat(x: 0, y: 0, z: 0, w: 1)

    public init(axis: Vec3, degrees: Double) {
        let l = max(axis.length, 1e-12)
        let half = degrees * .pi / 360
        let s = sin(half) / l
        self.init(x: axis.x * s, y: axis.y * s, z: axis.z * s, w: cos(half))
    }

    /// Rotation d'Euler appliquée dans l'ordre X, puis Y, puis Z (R = Rz · Ry · Rx), en degrés.
    public init(eulerXYZ e: Vec3) {
        self = Quat(axis: Vec3(0, 0, 1), degrees: e.z) * Quat(axis: Vec3(0, 1, 0), degrees: e.y) * Quat(axis: Vec3(1, 0, 0), degrees: e.x)
    }

    public static func * (a: Quat, b: Quat) -> Quat {
        Quat(x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
             y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
             w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }

    public func rotate(_ v: Vec3) -> Vec3 {
        let u = Vec3(x, y, z)
        let t = Vec3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x) * 2
        let c = Vec3(u.y * t.z - u.z * t.y, u.z * t.x - u.x * t.z, u.x * t.y - u.y * t.x)
        return v + t * w + c
    }

    public var normalized: Quat {
        let l = (x * x + y * y + z * z + w * w).squareRoot()
        return Quat(x: x / l, y: y / l, z: z / l, w: w / l)
    }

    /// Interpolation sphérique.
    public static func slerp(_ a: Quat, _ b0: Quat, _ t: Double) -> Quat {
        var b = b0
        var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
        if dot < 0 { b = Quat(x: -b.x, y: -b.y, z: -b.z, w: -b.w); dot = -dot }
        if dot > 0.9995 {
            return Quat(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t, w: a.w + (b.w - a.w) * t).normalized
        }
        let theta = acos(min(dot, 1))
        let s = sin(theta)
        let wa = sin((1 - t) * theta) / s, wb = sin(t * theta) / s
        return Quat(x: a.x * wa + b.x * wb, y: a.y * wa + b.y * wb, z: a.z * wa + b.z * wb, w: a.w * wa + b.w * wb)
    }
}

// MARK: - Bibliothèque de mouvements (motions.json, généré par scripts/mannequin/motions.py)

/// Pose écrite dans motions.json : angles par os, éventuelle pose de base, rotations et décalage de la racine.
public struct PoseSpec: Decodable, Sendable {
    public indirect enum Reference: Decodable, Sendable {
        case named(String)
        case inline(PoseSpec)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let name = try? container.decode(String.self) {
                self = .named(name)
            } else {
                self = .inline(try container.decode(PoseSpec.self))
            }
        }
    }

    public struct RootSpec: Decodable, Sendable {
        /// Rotations successives autour des axes du monde, par exemple [["x", -90], ["y", 90]].
        public var rot: [[RotationStep]]?
        public var offset: [Double]?
    }

    public enum RotationStep: Decodable, Sendable {
        case axis(String)
        case degrees(Double)

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .axis(s) } else { self = .degrees(try c.decode(Double.self)) }
        }
    }

    public var base: Reference?
    public var bones: [String: [Double]]?
    public var root: RootSpec?
    public var ground: Bool?
}

public struct Keyframe: Decodable, Sendable {
    public let t: Double
    public let pose: PoseSpec.Reference
    public let ease: String?
}

/// Accessoire de scène (chaise, table, mur, tapis), placé par rapport à une articulation d'une image clé.
public struct MotionProp: Decodable, Sendable, Hashable {
    public let kind: String
    /// Articulation de référence (position après mise au sol) ; absente : origine du personnage.
    public let anchor: String?
    /// Image clé utilisée pour l'ancrage.
    public let key: Int?
    public let offset: [Double]
    public let yaw: Double?
    /// Posé au sol (y = 0) quelle que soit la hauteur de l'ancre.
    public let floor: Bool?
}

/// Mouvement issu d'une capture réelle : rotations locales des os, image par image (quaternions x, y, z, w).
public struct MotionClip: Decodable, Sendable {
    public let fps: Double
    /// Os animés ; « root » porte l'orientation du bassin. Les autres os gardent la pose de référence.
    public let bones: [String]
    /// Une ligne par image : 4 valeurs par os, dans l'ordre de `bones`.
    public let frames: [[Double]]
    /// Source (fichier CMU et extrait), pour mémoire.
    public let source: String?

    public var duration: Double { Double(frames.count) / fps }

    /// Pose d'une image : rotations locales et orientation de la racine.
    public func pose(at index: Int) -> ResolvedPose {
        let row = frames[min(max(index, 0), frames.count - 1)]
        var rotations: [String: Quat] = [:]
        var root = Quat.identity
        for (i, bone) in bones.enumerated() where row.count >= i * 4 + 4 {
            let q = Quat(x: row[i * 4], y: row[i * 4 + 1], z: row[i * 4 + 2], w: row[i * 4 + 3]).normalized
            if bone == "root" { root = q } else { rotations[bone] = q }
        }
        return ResolvedPose(rotations: rotations, rootRotation: root, rootOffset: .zero, ground: true)
    }
}

public struct Motion: Decodable, Sendable {
    public struct Camera: Decodable, Sendable {
        public let yaw: Double
        public let pitch: Double?
    }

    /// Poses clés (mouvements construits) ; vide quand le mouvement vient d'une capture.
    public let keys: [Keyframe]
    public let clip: MotionClip?
    public let muscles: [String]
    public let camera: Camera
    public let props: [MotionProp]

    enum CodingKeys: String, CodingKey { case keys, clip, muscles, camera, props }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = try c.decodeIfPresent([Keyframe].self, forKey: .keys) ?? []
        clip = try c.decodeIfPresent(MotionClip.self, forKey: .clip)
        muscles = try c.decodeIfPresent([String].self, forKey: .muscles) ?? []
        camera = try c.decodeIfPresent(Camera.self, forKey: .camera) ?? Camera(yaw: 30, pitch: 8)
        props = try c.decodeIfPresent([MotionProp].self, forKey: .props) ?? []
    }

    /// Durée d'un cycle complet.
    public var duration: Double { clip?.duration ?? keys.last?.t ?? 0 }
}

/// Pose résolue : rotation locale de chaque os (repère du parent), orientation et décalage de la racine.
public struct ResolvedPose: Sendable {
    public var rotations: [String: Quat]
    public var rootRotation: Quat
    public var rootOffset: Vec3
    public var ground: Bool
}

public struct MotionLibrary: Decodable, Sendable {
    public let version: Int
    /// Hauteur du bassin du squelette sur lequel les décalages de la racine ont été calculés (mètres) :
    /// l'app les met à l'échelle de chaque corps pour que les pieds restent posés au même endroit.
    public let referenceHeight: Double?
    /// Noms des articulations du mannequin et des régions musculaires (contrôle de cohérence).
    public let bones: [String]
    public let regions: [String]
    public let poses: [String: PoseSpec]
    public let motions: [String: Motion]

    public static func bundled() throws -> MotionLibrary {
        guard let url = Bundle.module.url(forResource: "motions", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(MotionLibrary.self, from: Data(contentsOf: url))
    }

    public func motion(_ id: String) -> Motion? { motions[id] }

    /// Résout une pose : fusion avec sa base, miroir automatique pour les clés sans côté.
    public func resolve(_ reference: PoseSpec.Reference) -> ResolvedPose {
        var angles: [String: Vec3] = [:]
        var rootSteps: [(String, Double)] = []
        var offset = Vec3.zero
        var ground = true
        func apply(_ ref: PoseSpec.Reference, depth: Int) {
            guard depth < 16 else { return }
            let spec: PoseSpec
            switch ref {
            case .named(let name):
                guard let found = poses[name] else { return }
                spec = found
            case .inline(let inline):
                spec = inline
            }
            if let base = spec.base { apply(base, depth: depth + 1) }
            // Clés sans côté d'abord, puis clés latéralisées : une valeur propre à un côté l'emporte toujours.
            let ordered = (spec.bones ?? [:]).sorted { lhs, rhs in
                let l = lhs.key.hasSuffix(".L") || lhs.key.hasSuffix(".R"), r = rhs.key.hasSuffix(".L") || rhs.key.hasSuffix(".R")
                return l == r ? lhs.key < rhs.key : !l
            }
            for (bone, value) in ordered where value.count == 3 {
                let v = Vec3(value[0], value[1], value[2])
                if bone.hasSuffix(".L") || bone.hasSuffix(".R") {
                    angles[bone] = v
                } else {
                    angles[bone] = v
                    angles[bone + ".L"] = v
                    angles[bone + ".R"] = Vec3(v.x, -v.y, -v.z)
                }
            }
            if let root = spec.root {
                if let rot = root.rot {
                    rootSteps = rot.compactMap { step in
                        guard step.count == 2, case .axis(let axis) = step[0], case .degrees(let deg) = step[1] else { return nil }
                        return (axis, deg)
                    }
                }
                if let o = root.offset, o.count == 3 { offset = Vec3(o[0], o[1], o[2]) }
            }
            if let g = spec.ground { ground = g }
        }
        apply(reference, depth: 0)
        var root = Quat.identity
        for (axis, deg) in rootSteps {
            let a: Vec3 = axis == "x" ? Vec3(1, 0, 0) : axis == "y" ? Vec3(0, 1, 0) : Vec3(0, 0, 1)
            root = Quat(axis: a, degrees: deg) * root
        }
        return ResolvedPose(rotations: angles.mapValues { Quat(eulerXYZ: $0) }, rootRotation: root, rootOffset: offset, ground: ground)
    }
}

// MARK: - Squelette, cinématique directe et mise au sol

public struct SkeletonJoint: Decodable, Sendable {
    public let name: String
    public let parent: String?
    public let head: [Double]
    public var position: Vec3 { Vec3(head[0], head[1], head[2]) }
}

public struct Skeleton: Sendable {
    public let joints: [SkeletonJoint]
    public let parentIndex: [Int?]
    public let index: [String: Int]

    public init(joints: [SkeletonJoint]) {
        self.joints = joints
        var idx: [String: Int] = [:]
        for (i, j) in joints.enumerated() { idx[j.name] = i }
        index = idx
        parentIndex = joints.map { $0.parent.flatMap { idx[$0] } }
    }

    /// Rotations et positions monde de chaque articulation (les parents précèdent toujours leurs enfants).
    public func worldTransforms(_ pose: ResolvedPose, rootLift: Double = 0) -> (rotations: [Quat], positions: [Vec3]) {
        var R = [Quat](repeating: .identity, count: joints.count)
        var P = [Vec3](repeating: .zero, count: joints.count)
        for (i, joint) in joints.enumerated() {
            var local = pose.rotations[joint.name] ?? .identity
            if let p = parentIndex[i] {
                R[i] = R[p] * local
                P[i] = P[p] + R[p].rotate(joint.position - joints[p].position)
            } else {
                local = pose.rootRotation * local
                R[i] = local
                P[i] = joint.position + pose.rootOffset + Vec3(0, rootLift, 0)
            }
        }
        return (R, P)
    }
}

/// Sommet échantillonné pour la mise au sol : position de référence et jusqu'à 4 influences d'os.
public struct SkinSample: Sendable {
    public let position: Vec3
    public let bones: [Int]
    public let weights: [Double]
    public init(position: Vec3, bones: [Int], weights: [Double]) {
        self.position = position; self.bones = bones; self.weights = weights
    }
}

public enum Grounding {
    /// Hauteur dont il faut remonter la racine pour que le point le plus bas de la peau touche le sol (y = 0).
    public static func lift(for pose: ResolvedPose, skeleton: Skeleton, samples: [SkinSample], stride: Int = 1) -> Double {
        guard pose.ground, !samples.isEmpty else { return 0 }
        let (R, P) = skeleton.worldTransforms(pose)
        var lowest = Double.infinity
        for s in Swift.stride(from: 0, to: samples.count, by: max(stride, 1)).map({ samples[$0] }) {
            var y = 0.0
            for (b, w) in zip(s.bones, s.weights) where w > 0 {
                let rel = s.position - skeleton.joints[b].position
                y += w * (R[b].rotate(rel).y + P[b].y)
            }
            lowest = min(lowest, y)
        }
        return lowest.isFinite ? -lowest : 0
    }
}

/// Courbe d'accélération entre deux images clés.
public enum Easing {
    public static func value(_ t: Double, _ name: String?) -> Double {
        switch name {
        case "linear": return t
        case "in": return t * t
        case "out": return 1 - (1 - t) * (1 - t)
        default: return t * t * (3 - 2 * t)
        }
    }
}
