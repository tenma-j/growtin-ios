import Foundation
import Testing
@testable import GrowtinCore

@Suite("Personnage 3D : déformation de la surface")
struct SurfaceDeformerTests {
    /// Tube le long de x (rayon 0,2, de 0 à 2), deux os : racine en 0, coude en x = 1, mélange entre 0,75 et 1,25.
    /// `split` : les sommets de l'anneau du milieu sont dédoublés (comme une ligne de la tenue entre deux matières).
    static func tube(split: Bool = false) -> (surface: DeformableSurface, skeleton: Skeleton) {
        let rings = 9, segments = 8, middle = 4
        var rest: [Float] = [], normals: [Float] = [], bones: [Int32] = [], weights: [Float] = []
        func add(ring r: Int, segment s: Int) {
            let x = Float(r) * 0.25, a = Float(s) / Float(segments) * 2 * Float.pi
            rest += [x, 0.2 * cos(a), 0.2 * sin(a)]
            normals += [0, cos(a), sin(a)]
            let w = min(max((1.25 - x) / 0.5, 0), 1)
            bones += [0, 1, 0, 0]
            weights += [w, 1 - w, 0, 0]
        }
        for r in 0..<rings { for s in 0..<segments { add(ring: r, segment: s) } }
        let copies = rings * segments
        if split { for s in 0..<segments { add(ring: middle, segment: s) } }
        func index(_ r: Int, _ s: Int, upper: Bool) -> Int32 {
            // Côté « haut » de la ligne : la copie dédoublée de l'anneau du milieu.
            Int32(split && upper && r == middle ? copies + s % segments : r * segments + s % segments)
        }
        var triangles: [Int32] = []
        for r in 0..<(rings - 1) {
            let upper = r >= middle
            for s in 0..<segments {
                let a = index(r, s, upper: upper), b = index(r, s + 1, upper: upper)
                let c = index(r + 1, s, upper: upper), d = index(r + 1, s + 1, upper: upper)
                triangles += [a, b, c, b, d, c]
            }
        }
        let skeleton = Skeleton(joints: [SkeletonJoint(name: "root", parent: nil, head: [0, 0, 0]),
                                         SkeletonJoint(name: "elbow", parent: "root", head: [1, 0, 0])])
        return (DeformableSurface(rest: rest, restNormals: normals, bones: bones, weights: weights, influences: 4, triangles: triangles), skeleton)
    }

    static let identity = SIMD4<Float>(0, 0, 0, 1)

    static func vector(_ values: [Float], _ i: Int) -> SIMD3<Float> { SIMD3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2]) }

    static func angle(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let c = (a * b).sum() / (((a * a).sum() * (b * b).sum()).squareRoot())
        return acos(min(max(c, -1), 1)) * 180 / .pi
    }

    @Test("Pose de référence : surface inchangée, normales de la surface")
    func restPose() {
        let (surface, skeleton) = Self.tube()
        let deformer = SurfaceDeformer(surface: surface, skeleton: skeleton)!
        deformer.deform(rotations: [Self.identity, Self.identity], root: .zero)
        for i in 0..<surface.vertexCount {
            #expect(abs(deformer.positions[i * 3] - surface.rest[i * 3]) < 1e-6)
            #expect(abs(deformer.positions[i * 3 + 1] - surface.rest[i * 3 + 1]) < 1e-6)
            #expect(abs(deformer.positions[i * 3 + 2] - surface.rest[i * 3 + 2]) < 1e-6)
        }
        // Anneaux intérieurs : la normale des triangles voisins est exactement radiale.
        for i in 8..<(7 * 8) {
            #expect(Self.angle(Self.vector(deformer.normals, i), Self.vector(surface.restNormals, i)) < 0.01, "sommet \(i)")
        }
    }

    @Test("Coude plié à 90° : partie rigide tournée, normales qui suivent la surface")
    func bentElbow() {
        let (surface, skeleton) = Self.tube()
        let deformer = SurfaceDeformer(surface: surface, skeleton: skeleton)!
        let s = Float(0.5).squareRoot()
        deformer.deform(rotations: [Self.identity, SIMD4(0, 0, s, s)], root: .zero)
        // Au-delà de 1,25 : entièrement sur l'os du coude, tourné de 90° autour de z autour du point (1, 0, 0).
        for i in (5 * 8)..<(9 * 8) {
            let p = Self.vector(surface.rest, i)
            let expected = SIMD3<Float>(1 - p.y, p.x - 1, p.z)
            let got = Self.vector(deformer.positions, i)
            #expect(((got - expected) * (got - expected)).sum().squareRoot() < 1e-5, "sommet \(i)")
        }
        for i in (6 * 8)..<(8 * 8) {
            let n = Self.vector(surface.restNormals, i)
            #expect(Self.angle(Self.vector(deformer.normals, i), SIMD3(-n.y, n.x, n.z)) < 0.01, "sommet \(i)")
        }
        for i in 0..<surface.vertexCount {
            let n = Self.vector(deformer.normals, i)
            #expect(abs((n * n).sum() - 1) < 1e-4 && n.x.isFinite)
        }
    }

    @Test("Sommets dédoublés le long d'une ligne de la tenue : même normale des deux côtés")
    func weldedSeam() {
        let (whole, skeleton) = Self.tube()
        let (cut, _) = Self.tube(split: true)
        #expect(cut.vertexCount == whole.vertexCount + 8)
        #expect(cut.weldCount == whole.vertexCount)
        let s = Float(0.5).squareRoot()
        let pose = [Self.identity, SIMD4<Float>(0, 0, s, s)]
        let a = SurfaceDeformer(surface: whole, skeleton: skeleton)!, b = SurfaceDeformer(surface: cut, skeleton: skeleton)!
        a.deform(rotations: pose, root: .zero)
        b.deform(rotations: pose, root: .zero)
        for i in 0..<whole.vertexCount {
            #expect(Self.angle(Self.vector(a.normals, i), Self.vector(b.normals, i)) < 0.01, "sommet \(i)")
        }
        for s in 0..<8 {
            #expect(Self.angle(Self.vector(b.normals, 4 * 8 + s), Self.vector(b.normals, whole.vertexCount + s)) < 0.001)
        }
    }

    @Test("Même cinématique que le squelette du moteur de mouvements (racine tournée et déplacée)")
    func matchesSkeleton() {
        let skeleton = Skeleton(joints: [SkeletonJoint(name: "root", parent: nil, head: [0, 1, 0]),
                                         SkeletonJoint(name: "spine", parent: "root", head: [0, 1.5, 0]),
                                         SkeletonJoint(name: "arm", parent: "spine", head: [0.3, 1.8, 0.1])])
        // Un sommet par os, entièrement sur cet os ; deux triangles pour une surface valide.
        let points: [[Float]] = [[0.1, 0.9, 0.05], [-0.1, 1.6, 0.1], [0.6, 1.75, 0.2], [0.2, 1.2, -0.1]]
        let surface = DeformableSurface(rest: points.flatMap { $0 }, restNormals: [Float](repeating: 0, count: 12),
                                        bones: [0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1, 2, 0, 0],
                                        weights: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0.4, 0.6, 0, 0],
                                        influences: 4, triangles: [0, 1, 2, 0, 2, 3])
        let pose = ResolvedPose(rotations: ["spine": Quat(eulerXYZ: Vec3(20, -35, 10)), "arm": Quat(eulerXYZ: Vec3(-60, 15, 80))],
                                rootRotation: Quat(eulerXYZ: Vec3(0, 40, -12)), rootOffset: Vec3(0.2, -0.1, 0.3), ground: false)
        let lift = 0.05
        let (R, P) = skeleton.worldTransforms(pose, rootLift: lift)
        func float4(_ q: Quat) -> SIMD4<Float> { SIMD4(Float(q.x), Float(q.y), Float(q.z), Float(q.w)) }
        let rotations = [float4(pose.rootRotation), float4(pose.rotations["spine"]!), float4(pose.rotations["arm"]!)]
        let root = skeleton.joints[0].position + pose.rootOffset + Vec3(0, lift, 0)
        let deformer = SurfaceDeformer(surface: surface, skeleton: skeleton)!
        deformer.deform(rotations: rotations, root: SIMD3(Float(root.x), Float(root.y), Float(root.z)))
        func expected(_ point: [Float], _ bone: Int) -> Vec3 {
            R[bone].rotate(Vec3(Double(point[0]), Double(point[1]), Double(point[2])) - skeleton.joints[bone].position) + P[bone]
        }
        let targets = [expected(points[0], 0), expected(points[1], 1), expected(points[2], 2),
                       expected(points[3], 1) * 0.4 + expected(points[3], 2) * 0.6]
        for (i, target) in targets.enumerated() {
            #expect(abs(Double(deformer.positions[i * 3]) - target.x) < 1e-5, "sommet \(i)")
            #expect(abs(Double(deformer.positions[i * 3 + 1]) - target.y) < 1e-5, "sommet \(i)")
            #expect(abs(Double(deformer.positions[i * 3 + 2]) - target.z) < 1e-5, "sommet \(i)")
        }
    }

    @Test("Copie d'une plage de sommets vers des tampons serrés")
    func copyRange() {
        let (surface, skeleton) = Self.tube()
        let deformer = SurfaceDeformer(surface: surface, skeleton: skeleton)!
        deformer.deform(rotations: [Self.identity, SIMD4(0, 0.3, 0, 0.95)], root: SIMD3(0, 0.1, 0))
        var positions = [Float](repeating: -1, count: 10 * 3), normals = [Float](repeating: -1, count: 10 * 3)
        positions.withUnsafeMutableBytes { p in
            normals.withUnsafeMutableBytes { n in deformer.copy(vertices: 30..<40, positions: p.baseAddress!, normals: n.baseAddress!) }
        }
        #expect(positions == Array(deformer.positions[90..<120]))
        #expect(normals == Array(deformer.normals[90..<120]))
    }
}
