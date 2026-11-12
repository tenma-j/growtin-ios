import Foundation
import GrowtinCore
import SceneKit
import simd

/// Morphologie du personnage 3D, choisie d'après le profil.
enum MannequinBody: String, CaseIterable, Identifiable {
    case female, male

    var id: String { rawValue }
    var label: String { self == .female ? "Femme" : "Homme" }

    init(sex: BiologicalSex?) {
        self = sex == .male ? .male : .female
    }
}

/// Corps et vêtements d'un personnage, lus depuis Resources/Mannequin (générés par scripts/mannequin).
/// Corps issus des ressources MakeHuman, dans le domaine public (CC0 1.0).
final class MannequinAsset {
    struct Meta: Decodable {
        struct Mesh: Decodable {
            let material: Int
            let vertexCount: Int
            let indexCount: Int
        }
        struct Body: Decodable {
            let joints: [SkeletonJoint]
            let meshes: [Mesh]
        }
        let bodies: [String: Body]
    }

    /// Matériaux : 0 peau, 1 tissu, 2 liseré de couleur.
    struct Mesh {
        let material: Int
        let geometry: SCNGeometry
        let boneIndices: SCNGeometrySource
        let boneWeights: SCNGeometrySource
    }

    enum LoadError: Error { case missing, corrupt }

    let skeleton: Skeleton
    let meshes: [Mesh]
    /// Sommets du corps échantillonnés pour poser le personnage au sol.
    let samples: [SkinSample]

    private static var cache: [MannequinBody: MannequinAsset] = [:]
    private static let lock = NSLock()

    static func load(_ body: MannequinBody) throws -> MannequinAsset {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[body] { return cached }
        let asset = try MannequinAsset(body: body)
        cache[body] = asset
        return asset
    }

    private init(body: MannequinBody) throws {
        guard let metaURL = Bundle.main.url(forResource: "mannequin", withExtension: "json"),
              let binURL = Bundle.main.url(forResource: "mannequin-\(body.rawValue)", withExtension: "bin") else {
            throw LoadError.missing
        }
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: metaURL))
        guard let info = meta.bodies[body.rawValue] else { throw LoadError.corrupt }
        let data = try Data(contentsOf: binURL)
        guard data.count >= 8, data.prefix(4) == Data("GTM4".utf8) else { throw LoadError.corrupt }
        skeleton = Skeleton(joints: info.joints)

        var offset = 8
        func readUInt32() -> Int {
            defer { offset += 4 }
            return Int(data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        }
        func slice(_ length: Int) throws -> Data {
            guard offset + length <= data.count else { throw LoadError.corrupt }
            defer { offset += length }
            return data.subdata(in: offset..<(offset + length))
        }

        var meshes: [Mesh] = []
        var samples: [SkinSample] = []
        for _ in info.meshes {
            let material = readUInt32(), n = readUInt32(), m = readUInt32()
            let positions = try slice(n * 12), normals = try slice(n * 12)
            let boneIndexData = try slice(n * 8), weights = try slice(n * 16), indices = try slice(m * 4)

            let vertexSource = SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                                                 componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
            let normalSource = SCNGeometrySource(data: normals, semantic: .normal, vectorCount: n, usesFloatComponents: true,
                                                 componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
            let element = SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: m / 3, bytesPerIndex: 4)
            let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
            let boneIndices = SCNGeometrySource(data: boneIndexData, semantic: .boneIndices, vectorCount: n, usesFloatComponents: false,
                                                componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
            let boneWeights = SCNGeometrySource(data: weights, semantic: .boneWeights, vectorCount: n, usesFloatComponents: true,
                                                componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            meshes.append(Mesh(material: material, geometry: geometry, boneIndices: boneIndices, boneWeights: boneWeights))

            // Mise au sol : un sommet sur 7, sur toute la surface (peau et tissu font partie du même corps).
            do {
                positions.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                    boneIndexData.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                        weights.withUnsafeBytes { (w: UnsafeRawBufferPointer) in
                            let pf = p.bindMemory(to: Float.self), bi = b.bindMemory(to: UInt16.self), wf = w.bindMemory(to: Float.self)
                            for i in stride(from: 0, to: n, by: 7) {
                                samples.append(SkinSample(position: Vec3(Double(pf[i * 3]), Double(pf[i * 3 + 1]), Double(pf[i * 3 + 2])),
                                                          bones: (0..<4).map { Int(bi[i * 4 + $0]) },
                                                          weights: (0..<4).map { Double(wf[i * 4 + $0]) }))
                            }
                        }
                    }
                }
            }
        }
        self.meshes = meshes
        self.samples = samples
    }
}
