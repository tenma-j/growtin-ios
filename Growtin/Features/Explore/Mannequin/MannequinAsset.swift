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
        struct Body: Decodable {
            let joints: [SkeletonJoint]
        }
        let bodies: [String: Body]
    }

    /// Un maillage par matière : 0 peau, 1 tissu, 2 liseré de couleur.
    struct Mesh {
        let material: Int
        /// Plage de ses sommets dans la surface déformée (`file.surface`).
        let vertexRange: Range<Int>
        let element: SCNGeometryElement
    }

    enum LoadError: Error { case missing, corrupt }

    let skeleton: Skeleton
    let file: MannequinFile
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
        let skeleton = Skeleton(joints: info.joints)
        let file = try MannequinFile(data: Data(contentsOf: binURL))
        let jointCount = skeleton.joints.count
        guard file.surface.bones.allSatisfy({ Int($0) < jointCount }) else { throw LoadError.corrupt }
        self.skeleton = skeleton
        self.file = file
        meshes = file.meshes.map { mesh in
            let indices = mesh.indices.withUnsafeBytes { Data($0) }
            return Mesh(material: mesh.material, vertexRange: mesh.vertexRange,
                        element: SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: mesh.indices.count / 3,
                                                    bytesPerIndex: 4))
        }
        samples = file.groundingSamples()
    }

    /// Repli sans Metal : géométrie de référence et skinning SceneKit (4 influences au plus par sommet, les plus fortes).
    func skinnedGeometry(for mesh: Mesh) -> (geometry: SCNGeometry, boneIndices: SCNGeometrySource, boneWeights: SCNGeometrySource) {
        let surface = file.surface, range = mesh.vertexRange, k = file.influences
        let positions = surface.rest[(range.lowerBound * 3)..<(range.upperBound * 3)].withUnsafeBytes { Data($0) }
        let normals = surface.restNormals[(range.lowerBound * 3)..<(range.upperBound * 3)].withUnsafeBytes { Data($0) }
        var bones: [UInt16] = [], weights: [Float] = []
        bones.reserveCapacity(range.count * 4)
        weights.reserveCapacity(range.count * 4)
        for i in range {
            // Les influences sont rangées de la plus forte à la plus faible.
            let used = min(k, 4)
            let total = (0..<used).reduce(Float(0)) { $0 + surface.weights[i * k + $1] }
            for j in 0..<4 {
                bones.append(j < used ? UInt16(surface.bones[i * k + j]) : 0)
                weights.append(j < used && total > 0 ? surface.weights[i * k + j] / total : 0)
            }
        }
        let n = range.count
        let geometry = SCNGeometry(sources: [
            SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: normals, semantic: .normal, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
        ], elements: [mesh.element])
        let boneIndices = SCNGeometrySource(data: bones.withUnsafeBytes { Data($0) }, semantic: .boneIndices, vectorCount: n,
                                            usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 2,
                                            dataOffset: 0, dataStride: 8)
        let boneWeights = SCNGeometrySource(data: weights.withUnsafeBytes { Data($0) }, semantic: .boneWeights, vectorCount: n,
                                            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                            dataOffset: 0, dataStride: 16)
        return (geometry, boneIndices, boneWeights)
    }
}
