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

/// Maillage, squelette et poids d'un corps, lus depuis Resources/Mannequin (générés par scripts/mannequin).
/// Corps issus des ressources MakeHuman, dans le domaine public (CC0 1.0).
final class MannequinAsset {
    struct Meta: Decodable {
        struct Body: Decodable {
            let joints: [SkeletonJoint]
            let vertexCount: Int
            let indexCount: Int
        }
        let regions: [String]
        let bodies: [String: Body]
    }

    enum LoadError: Error { case missing, corrupt }

    let skeleton: Skeleton
    let regions: [String]
    /// Géométrie de base (positions, normales, couleur, régions et tissu en coordonnées de texture).
    let geometry: SCNGeometry
    let boneIndices: SCNGeometrySource
    let boneWeights: SCNGeometrySource
    /// Sommets échantillonnés pour poser le personnage au sol.
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
        let n = info.vertexCount, m = info.indexCount
        let header = 12
        let sizes = [n * 12, n * 12, n * 8, n * 16, n * 4, m * 4]
        guard data.count >= header + sizes.reduce(0, +), data.prefix(4) == Data("GTM3".utf8) else { throw LoadError.corrupt }

        var offset = header
        func slice(_ length: Int) -> Data {
            defer { offset += length }
            return data.subdata(in: offset..<(offset + length))
        }
        let positions = slice(sizes[0]), normals = slice(sizes[1]), indices16 = slice(sizes[2])
        let weights = slice(sizes[3]), attributes = slice(sizes[4]), indices = slice(sizes[5])

        skeleton = Skeleton(joints: info.joints)
        regions = meta.regions

        // Régions (deux dominantes) et part de tissu, transmises au shader comme coordonnées de texture.
        var regionCoords = [Float](repeating: 0, count: n * 2)
        var blendCoords = [Float](repeating: 0, count: n * 2)
        attributes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<n {
                regionCoords[i * 2] = Float(bytes[i * 4])
                regionCoords[i * 2 + 1] = Float(bytes[i * 4 + 1])
                blendCoords[i * 2] = Float(bytes[i * 4 + 2]) / 255
                blendCoords[i * 2 + 1] = Float(bytes[i * 4 + 3]) / 255
            }
        }
        let white = Data(repeating: 255, count: n * 4)

        let vertexSource = SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                                             componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let normalSource = SCNGeometrySource(data: normals, semantic: .normal, vectorCount: n, usesFloatComponents: true,
                                             componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let colorSource = SCNGeometrySource(data: white, semantic: .color, vectorCount: n, usesFloatComponents: false,
                                            componentsPerVector: 4, bytesPerComponent: 1, dataOffset: 0, dataStride: 4)
        let regionSource = SCNGeometrySource(data: regionCoords.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord,
                                             vectorCount: n, usesFloatComponents: true, componentsPerVector: 2,
                                             bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        let blendSource = SCNGeometrySource(data: blendCoords.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord,
                                            vectorCount: n, usesFloatComponents: true, componentsPerVector: 2,
                                            bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        let element = SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: m / 3, bytesPerIndex: 4)
        geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource, regionSource, blendSource], elements: [element])

        boneIndices = SCNGeometrySource(data: indices16, semantic: .boneIndices, vectorCount: n, usesFloatComponents: false,
                                        componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
        boneWeights = SCNGeometrySource(data: weights, semantic: .boneWeights, vectorCount: n, usesFloatComponents: true,
                                        componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)

        // Échantillon de sommets pour la mise au sol (1 sur 7).
        var samples: [SkinSample] = []
        positions.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            indices16.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                weights.withUnsafeBytes { (w: UnsafeRawBufferPointer) in
                    let pf = p.bindMemory(to: Float.self), bi = b.bindMemory(to: UInt16.self), wf = w.bindMemory(to: Float.self)
                    for i in stride(from: 0, to: n, by: 7) {
                        let position = Vec3(Double(pf[i * 3]), Double(pf[i * 3 + 1]), Double(pf[i * 3 + 2]))
                        samples.append(SkinSample(position: position,
                                                  bones: (0..<4).map { Int(bi[i * 4 + $0]) },
                                                  weights: (0..<4).map { Double(wf[i * 4 + $0]) }))
                    }
                }
            }
        }
        self.samples = samples
    }

    /// Masque binaire des régions à mettre en valeur (bit i = région i).
    func mask(for regionNames: [String]) -> Float {
        var mask = 0
        for name in regionNames {
            if let index = regions.firstIndex(of: name) { mask |= 1 << index }
        }
        return Float(mask)
    }
}
