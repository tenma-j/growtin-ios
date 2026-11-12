import Foundation
import Testing
@testable import GrowtinCore

@Suite("Personnage 3D : fichiers des corps")
struct MannequinFileTests {
    /// Ressources de l'app (Growtin/Resources/Mannequin), lues depuis le dépôt.
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../../Growtin/Resources/Mannequin").standardized

    struct Meta: Decodable {
        struct Mesh: Decodable { let material: Int; let vertexCount: Int; let indexCount: Int }
        struct Body: Decodable { let joints: [SkeletonJoint]; let meshes: [Mesh] }
        let bodies: [String: Body]
    }

    static func load(_ body: String) throws -> (MannequinFile, Skeleton, Meta.Body) {
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: folder.appendingPathComponent("mannequin.json")))
        let info = try #require(meta.bodies[body])
        let file = try MannequinFile(data: Data(contentsOf: folder.appendingPathComponent("mannequin-\(body).bin")))
        return (file, Skeleton(joints: info.joints), info)
    }

    @Test("Les deux corps se lisent : maillages, os, poids", arguments: ["female", "male"])
    func bundledBodies(body: String) throws {
        let (file, skeleton, info) = try Self.load(body)
        #expect(file.influences == 8)
        #expect(file.meshes.map(\.material) == [0, 1, 2])
        #expect(file.meshes.map(\.vertexCount) == info.meshes.map(\.vertexCount))
        #expect(file.meshes.map(\.indices.count) == info.meshes.map(\.indexCount))
        let surface = file.surface
        #expect(surface.bones.allSatisfy { $0 >= 0 && Int($0) < skeleton.joints.count })
        for i in 0..<surface.vertexCount {
            let total = surface.weights[(i * 8)..<((i + 1) * 8)].reduce(0, +)
            #expect(abs(total - 1) < 1e-3, "sommet \(i) : poids \(total)")
        }
        // Les lignes de la tenue dédoublent des sommets : soudés pour l'éclairage.
        #expect(surface.weldCount < surface.vertexCount)
        #expect(!file.groundingSamples().isEmpty)
    }

    @Test("Bras levés au-dessus de la tête : surface et normales valides", arguments: ["female", "male"])
    func raisedArms(body: String) throws {
        let (file, skeleton, _) = try Self.load(body)
        let deformer = try #require(SurfaceDeformer(surface: file.surface, skeleton: skeleton))
        // Pose de référence : la surface ne bouge pas.
        let head = skeleton.joints[0].position
        let rootPosition = SIMD3(Float(head.x), Float(head.y), Float(head.z))
        deformer.deform(rotations: Array(repeating: SIMD4(0, 0, 0, 1), count: skeleton.joints.count), root: rootPosition)
        #expect(zip(deformer.positions, file.surface.rest).allSatisfy { abs($0 - $1) < 1e-5 })

        let library = try MotionLibrary.bundled(body: body)
        let motion = try #require(library.motion("arm-raise"))
        let pose = library.resolve(motion.keys[2].pose)
        let rotations = skeleton.localRotations(pose).map { SIMD4(Float($0.x), Float($0.y), Float($0.z), Float($0.w)) }
        deformer.deform(rotations: rotations, root: rootPosition)
        #expect(deformer.positions.allSatisfy { $0.isFinite })
        for i in 0..<file.surface.vertexCount {
            let x = deformer.normals[i * 3], y = deformer.normals[i * 3 + 1], z = deformer.normals[i * 3 + 2]
            #expect(abs(x * x + y * y + z * z - 1) < 1e-3, "sommet \(i)")
        }
        // Mains jointes au-dessus de la tête : les poignets sont plus hauts que le sommet du crâne au repos.
        let top = stride(from: 1, to: file.surface.rest.count, by: 3).map { file.surface.rest[$0] }.max() ?? 0
        let raised = stride(from: 1, to: deformer.positions.count, by: 3).map { deformer.positions[$0] }.max() ?? 0
        #expect(raised > top + 0.1)
    }

    @Test("Format GTM4 (4 influences) et fichier tronqué")
    func formats() throws {
        func u32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        func f32(_ v: Float) -> [UInt8] { withUnsafeBytes(of: v.bitPattern.littleEndian) { Array($0) } }
        func u16(_ v: UInt16) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        var bytes = Array("GTM4".utf8) + u32(1) + u32(0) + u32(3) + u32(3)
        for p in [[0, 0, 0], [1, 0, 0], [0, 1, 0]] as [[Float]] { bytes += p.flatMap(f32) }
        for _ in 0..<3 { bytes += [0, 0, 1].flatMap(f32) }
        for _ in 0..<3 { bytes += [0, 0, 0, 0].flatMap(u16) }
        for _ in 0..<3 { bytes += [1, 0, 0, 0].flatMap(f32) }
        bytes += [0, 1, 2].flatMap(u32)
        let file = try MannequinFile(data: Data(bytes))
        #expect(file.influences == 4 && file.meshes.count == 1 && file.surface.vertexCount == 3)
        #expect(file.meshes[0].indices == [0, 1, 2])
        #expect(throws: MannequinFile.ParseError.truncated) { try MannequinFile(data: Data(bytes.dropLast(2))) }
        #expect(throws: MannequinFile.ParseError.badHeader) { try MannequinFile(data: Data(Array("XXXX".utf8) + u32(1))) }
        var badIndex = bytes
        badIndex.replaceSubrange((badIndex.count - 4)..<badIndex.count, with: u32(7))
        #expect(throws: MannequinFile.ParseError.badIndex) { try MannequinFile(data: Data(badIndex)) }
    }
}
