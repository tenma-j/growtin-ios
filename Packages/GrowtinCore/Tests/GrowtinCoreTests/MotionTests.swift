import Foundation
import Testing
@testable import GrowtinCore

@Suite("Personnage 3D : mouvements")
struct MotionTests {
    let library = try! MotionLibrary.bundled()

    @Test("Quaternions : rotations d'Euler dans l'ordre X, Y, Z")
    func quaternions() {
        let q = Quat(eulerXYZ: Vec3(-90, 0, 0))            // flexion de hanche : la jambe part vers l'avant
        let v = q.rotate(Vec3(0, -1, 0))
        #expect(abs(v.y) < 1e-9 && abs(v.z - 1) < 1e-9)
        let abduct = Quat(eulerXYZ: Vec3(0, 0, 90)).rotate(Vec3(0, -1, 0)) // bras gauche sur le côté
        #expect(abs(abduct.x - 1) < 1e-9)
        let mid = Quat.slerp(.identity, Quat(axis: Vec3(0, 1, 0), degrees: 90), 0.5)
        let r = mid.rotate(Vec3(0, 0, 1))
        #expect(abs(r.x - sin(.pi / 4)) < 1e-9 && abs(r.z - cos(.pi / 4)) < 1e-9)
    }

    @Test("Miroir automatique pour le côté droit")
    func mirroring() {
        let pose = library.resolve(.inline(PoseSpec(base: nil, bones: ["upperarm01": [-10, 20, 30]], root: nil, ground: nil)))
        let left = pose.rotations["upperarm01.L"]!, right = pose.rotations["upperarm01.R"]!
        #expect(left == Quat(eulerXYZ: Vec3(-10, 20, 30)))
        #expect(right == Quat(eulerXYZ: Vec3(-10, -20, -30)))
    }

    @Test("La bibliothèque est cohérente : os, régions, temps (pour chaque corps)", arguments: MotionLibrary.bodies)
    func libraryIsConsistent(body: String) throws {
        let library = try MotionLibrary.bundled(body: body)
        #expect(library.motions.count >= 40)
        #expect(Set(library.motions.keys) == Set(self.library.motions.keys), "\(body) : mêmes mouvements pour chaque corps")
        let bones = Set(library.bones), regions = Set(library.regions)
        for (id, motion) in library.motions {
            if let clip = motion.clip {
                #expect(clip.fps > 0 && clip.frames.count >= 10, "\(id) : capture trop courte")
                #expect(clip.frames.allSatisfy { $0.count == clip.bones.count * 4 }, "\(id) : images incomplètes")
                for bone in clip.bones where bone != "root" { #expect(bones.contains(bone), "\(id) : os \(bone)") }
                let q = clip.pose(at: clip.frames.count / 2).rootRotation
                #expect(abs(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w - 1) < 1e-6)
            } else {
                #expect(motion.keys.first?.t == 0, "\(id)")
                #expect(zip(motion.keys, motion.keys.dropFirst()).allSatisfy { $0.t < $1.t }, "\(id) : temps croissants")
            }
            for region in motion.muscles { #expect(regions.contains(region), "\(id) : \(region)") }
            for prop in motion.props {
                if let anchor = prop.anchor { #expect(bones.contains(anchor), "\(id) : ancre \(anchor)") }
                #expect(["chair", "table", "wall", "mat", "door", "bed", "pillow", "towel"].contains(prop.kind), "\(id) : \(prop.kind)")
                // Serviette : trois sommets de la peau (main gauche, pied, main droite).
                if prop.kind == "towel" { #expect(prop.vertices?.count == 3 && prop.vertices?.allSatisfy({ $0 >= 0 }) == true, "\(id) : sommets de la serviette") }
            }
            for key in motion.keys {
                let pose = library.resolve(key.pose)
                for name in pose.rotations.keys {
                    let central = name.hasSuffix(".L") || name.hasSuffix(".R") ? String(name.dropLast(2)) : name
                    #expect(bones.contains(name) || bones.contains(name + ".L") || bones.contains(central), "\(id) : os \(name)")
                }
            }
        }
    }

    @Test("Chaque étape d'exercice a une animation existante (pour chaque corps)", arguments: MotionLibrary.bodies)
    func everyStepHasMotion(body: String) throws {
        let library = try MotionLibrary.bundled(body: body)
        let regions = Set(library.regions)
        for exercise in ExerciseLibrary.all {
            for step in exercise.steps {
                #expect(library.motion(step.motion) != nil, "\(exercise.id) / \(step.title) → \(step.motion)")
                for region in step.focus ?? [] { #expect(regions.contains(region), "\(exercise.id) / \(step.title) : \(region)") }
            }
        }
    }

    @Test("Pieds posés : squats, cercles de hanches et guerrier gardent les pieds au même endroit", arguments: MotionLibrary.bodies)
    func plantedFeet(body: String) throws {
        // Chaque corps a sa propre version des mouvements, calculée sur son squelette.
        let library = try MotionLibrary.bundled(body: body)
        struct Meta: Decodable {
            struct Body: Decodable { let joints: [SkeletonJoint] }
            let bodies: [String: Body]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Growtin/Resources/Mannequin/mannequin.json")
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: url))
        let skeleton = Skeleton(joints: try #require(meta.bodies[body]).joints)
        let feet = ["foot.L", "foot.R"].compactMap { skeleton.index[$0] }
        #expect(feet.count == 2)
        for id in ["chair-squat", "half-squat-arms", "hip-circles", "warrior-two", "gentle-lunge"] {
            let motion = try #require(library.motion(id))
            let first = skeleton.worldTransforms(library.resolve(motion.keys[0].pose)).positions
            for key in motion.keys {
                let p = skeleton.worldTransforms(library.resolve(key.pose)).positions
                let slides = feet.map { f in ((p[f].x - first[f].x) * (p[f].x - first[f].x) + (p[f].z - first[f].z) * (p[f].z - first[f].z)).squareRoot() }
                // Fentes : un pied avance, l'autre reste posé. Ailleurs : les deux pieds restent posés.
                let slide = id == "gentle-lunge" ? slides.min() ?? 0 : slides.max() ?? 0
                #expect(slide < 0.015, "\(body) / \(id) à \(key.t) s : un pied glisse de \(Int(slide * 1000)) mm")
            }
        }
    }

    @Test("Articulation d'appoint : la moitié de la rotation de son os")
    func halfJoint() {
        let skeleton = Skeleton(joints: [
            SkeletonJoint(name: "root", parent: nil, head: [0, 1, 0]),
            SkeletonJoint(name: "upperarm01.L", parent: "root", head: [0.2, 1, 0]),
            SkeletonJoint(name: "upperarm01-half.L", parent: "root", head: [0.2, 1, 0], half: "upperarm01.L"),
        ])
        #expect(skeleton.halfSource == [nil, nil, 1])
        // Bras levé sur le côté à 90° : l'appoint est à 45°, à mi-chemin entre le bras et le tronc.
        let pose = ResolvedPose(rotations: ["upperarm01.L": Quat(eulerXYZ: Vec3(0, 0, 90))], rootRotation: .identity,
                                rootOffset: .zero, ground: false)
        let down = skeleton.worldTransforms(pose).rotations[2].rotate(Vec3(0, -1, 0))
        #expect(abs(down.x - sin(.pi / 4)) < 1e-9 && abs(down.y + cos(.pi / 4)) < 1e-9)
    }

    @Test("Articulations d'appoint des personnages : épaules, coudes, hanches, genoux", arguments: MotionLibrary.bodies)
    func bundledHalfJoints(body: String) throws {
        struct Meta: Decodable {
            struct Body: Decodable { let joints: [SkeletonJoint] }
            let bodies: [String: Body]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Growtin/Resources/Mannequin/mannequin.json")
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: url))
        let skeleton = Skeleton(joints: try #require(meta.bodies[body]).joints)
        let halves = skeleton.joints.filter { $0.half != nil }
        #expect(Set(halves.compactMap(\.half)) == Set(["upperarm01", "lowerarm01", "upperleg01", "lowerleg01"].flatMap { [$0 + ".L", $0 + ".R"] }))
        for joint in halves {
            let source = try #require(skeleton.index[joint.half!])
            // Même point et même parent que l'os doublé ; absent des poses (il suit son os).
            #expect(joint.parent == skeleton.joints[source].parent, "\(joint.name)")
            #expect(joint.position == skeleton.joints[source].position, "\(joint.name)")
            #expect(!library.bones.contains(joint.name), "\(joint.name)")
        }
    }

    @Test("Cinématique et mise au sol sur un squelette simple")
    func kinematicsAndGrounding() {
        let skeleton = Skeleton(joints: [
            SkeletonJoint(name: "root", parent: nil, head: [0, 1, 0]),
            SkeletonJoint(name: "upperleg01.L", parent: "root", head: [0.1, 1, 0]),
            SkeletonJoint(name: "lowerleg01.L", parent: "upperleg01.L", head: [0.1, 0.5, 0]),
        ])
        // Un sommet au pied : 1 m sous la racine, porté par le genou.
        let foot = SkinSample(position: Vec3(0.1, 0, 0), bones: [2], weights: [1])
        let standing = ResolvedPose(rotations: [:], rootRotation: .identity, rootOffset: .zero, ground: true)
        #expect(abs(Grounding.lift(for: standing, skeleton: skeleton, samples: [foot])) < 1e-9)
        // Hanche fléchie à 90° : toute la jambe est à l'horizontale, le pied à 1 m du sol → il faut redescendre d'1 m.
        let flexed = ResolvedPose(rotations: ["upperleg01.L": Quat(eulerXYZ: Vec3(-90, 0, 0))], rootRotation: .identity,
                                  rootOffset: .zero, ground: true)
        let (_, positions) = skeleton.worldTransforms(flexed)
        #expect(abs(positions[2].z - 0.5) < 1e-9 && abs(positions[2].y - 1) < 1e-9)
        #expect(abs(Grounding.lift(for: flexed, skeleton: skeleton, samples: [foot]) - (-1.0)) < 1e-9)
        #expect(Easing.value(0.5, "inOut") == 0.5 && Easing.value(0.25, "linear") == 0.25)
    }

    @Test("Cadrage : corps entier sol compris, ou zone du corps de plus près")
    func cameraFraming() throws {
        // Corps allongé le long de X à 60 cm du sol : tête, bassin, pieds.
        let lying = [[Vec3(-0.8, 0.6, 0), Vec3(0, 0.6, 0), Vec3(0.9, 0.62, 0.1)]]
        let whole = try #require(CameraFraming.shot(keyPositions: lying, joints: nil, yaw: 0, pitch: 30, margin: nil, aspect: 1))
        // Cadre entier : boîte élargie de 20 cm, sol compris (x de −1 à 1,1 ; y de 0 à 0,82 ; z de −0,2 à 0,3).
        let half = tan(15 * Double.pi / 180)
        #expect(abs(whole.target.x - 0.05) < 1e-9 && abs(whole.target.y - 0.41 * 0.95) < 1e-9 && abs(whole.target.z - 0.05) < 1e-9)
        #expect(abs(whole.distance - (2.1 / 2 / half * 1.06 + 0.25)) < 1e-9)
        #expect(abs(whole.eye.y - (whole.target.y + whole.distance * 0.5)) < 1e-9)

        // Cadrage resserré sur les pieds : la caméra vise la zone et s'en approche, sans descendre sous sa distance minimale.
        let feet = try #require(CameraFraming.shot(keyPositions: lying, joints: [2], yaw: 0, pitch: 30, margin: 0.3, aspect: 1))
        #expect(abs(feet.target.x - 0.9) < 1e-9 && abs(feet.target.y - 0.62) < 1e-9 && abs(feet.target.z - 0.1) < 1e-9)
        #expect(feet.distance < whole.distance * 0.6 && feet.distance >= CameraFraming.minimumDistance)
        #expect(feet.eye.y > feet.target.y + 0.4, "la caméra reste au-dessus de la zone, donc du matelas")
        let close = try #require(CameraFraming.shot(keyPositions: lying, joints: [2], yaw: 0, pitch: 30, margin: 0.01, aspect: 1))
        #expect(close.distance == CameraFraming.minimumDistance)
        // Vue tournée : le personnage tourne de `yaw` autour de la verticale, la caméra reste en face.
        let turned = try #require(CameraFraming.shot(keyPositions: lying, joints: [2], yaw: 90, pitch: 30, margin: 0.3, aspect: 1))
        #expect(abs(turned.target.x - 0.1) < 1e-9 && abs(turned.target.z + 0.9) < 1e-9)
        #expect(CameraFraming.shot(keyPositions: [], joints: nil, yaw: 0, pitch: nil, margin: nil, aspect: 1) == nil)
        #expect(CameraFraming.shot(keyPositions: lying, joints: [7], yaw: 0, pitch: nil, margin: nil, aspect: 1) == nil)
    }

    @Test("Serviette : deux brins et un passage à plat sous le pied, bande sans vrille")
    func towelPath() throws {
        let left = Vec3(0.3, 0.9, 0.4), right = Vec3(-0.25, 0.9, 0.4), foot = Vec3(0.05, 0.02, 0.2)
        let segments = try #require(TowelPath.segments(leftHand: left, foot: foot, rightHand: right,
                                                       under: [[0.06, 0], [-0.05, 0.01]], thickness: 0.006))
        #expect(segments.count == 3)
        // Brin gauche du sol à la main gauche, passage sous le pied posé au sol, brin droit du sol à la main droite.
        #expect(segments[0].to == left && segments[2].to == right)
        #expect(segments[0].from == segments[1].from && segments[1].to == segments[2].from)
        #expect(abs(segments[1].from.y - 0.003) < 1e-12 && abs(segments[1].to.y - 0.003) < 1e-12)
        #expect(abs(segments[1].from.x - 0.11) < 1e-12 && abs(segments[1].to.x - 0.0) < 1e-12 && abs(segments[1].to.z - 0.21) < 1e-12)
        func dot(_ a: Vec3, _ b: Vec3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
        for segment in segments {
            let d = (segment.to - segment.from) * (1 / segment.length)
            // Repère orthonormé direct : largeur, direction, épaisseur.
            #expect(abs(segment.side.length - 1) < 1e-9 && abs(segment.normal.length - 1) < 1e-9)
            #expect(abs(dot(segment.side, d)) < 1e-9 && abs(dot(segment.normal, d)) < 1e-9 && abs(dot(segment.side, segment.normal)) < 1e-9)
            let cross = Vec3(segment.side.y * d.z - segment.side.z * d.y, segment.side.z * d.x - segment.side.x * d.z,
                             segment.side.x * d.y - segment.side.y * d.x)
            #expect((cross - segment.normal).length < 1e-9)
        }
        // Sous le pied, la bande est à plat : épaisseur verticale, largeur dans l'axe du pied.
        #expect(abs(abs(segments[1].normal.y) - 1) < 1e-9 && abs(segments[1].side.y) < 1e-12)
        #expect(TowelPath.segments(leftHand: left, foot: foot, rightHand: right, under: [[0.06, 0]], thickness: 0.006) == nil)
        #expect(TowelPath.segments(leftHand: left, foot: foot, rightHand: right, under: [[0, 0], [0, 0]], thickness: 0.006) == nil)
    }
}
