import Foundation

/// Fichier binaire d'un personnage, écrit par `scripts/mannequin/export.py` : un maillage par matière (0 peau, 1 tissu,
/// 2 liseré), découpés dans la même surface.
///
/// Format GTM5 (petit-boutiste) : `GTM5`, nombre de maillages, influences par sommet (uint32) ; puis pour chaque
/// maillage : matière, nombre de sommets, nombre d'indices (uint32), positions et normales (float32 ×3), os
/// (uint16 × influences), poids (float32 × influences), indices de triangles (uint32). GTM4 : 4 influences, sans le champ.
public struct MannequinFile: Sendable {
    public struct Mesh: Sendable {
        public let material: Int
        /// Plage de ses sommets dans la surface entière (les maillages sont mis bout à bout).
        public let vertexRange: Range<Int>
        /// Triangles, en indices locaux au maillage.
        public let indices: [UInt32]
        public var vertexCount: Int { vertexRange.count }
    }

    public enum ParseError: Error, Equatable {
        case badHeader, truncated, badIndex
    }

    public let influences: Int
    public let meshes: [Mesh]
    /// Tous les maillages bout à bout, prêts à être déformés.
    public let surface: DeformableSurface

    public init(data: Data) throws {
        var reader = Reader(data: data)
        let magic = try reader.bytes(4)
        let meshCount = try reader.uint32()
        let influences: Int
        switch magic {
        case Array("GTM5".utf8): influences = try reader.uint32()
        case Array("GTM4".utf8): influences = 4
        default: throw ParseError.badHeader
        }
        guard (1...16).contains(influences), (1...16).contains(meshCount) else { throw ParseError.badHeader }

        var meshes: [Mesh] = []
        var rest: [Float] = [], normals: [Float] = [], bones: [Int32] = [], weights: [Float] = [], triangles: [Int32] = []
        for _ in 0..<meshCount {
            let material = try reader.uint32(), vertexCount = try reader.uint32(), indexCount = try reader.uint32()
            guard indexCount % 3 == 0 else { throw ParseError.badIndex }
            let base = rest.count / 3
            rest += try reader.floats(vertexCount * 3)
            normals += try reader.floats(vertexCount * 3)
            bones += try reader.uint16s(vertexCount * influences).map { Int32($0) }
            weights += try reader.floats(vertexCount * influences)
            let indices = try reader.uint32s(indexCount)
            guard indices.allSatisfy({ Int($0) < vertexCount }) else { throw ParseError.badIndex }
            triangles += indices.map { Int32(Int($0) + base) }
            meshes.append(Mesh(material: material, vertexRange: base..<(base + vertexCount), indices: indices))
        }
        self.influences = influences
        self.meshes = meshes
        surface = DeformableSurface(rest: rest, restNormals: normals, bones: bones, weights: weights,
                                    influences: influences, triangles: triangles)
    }

    /// Sommets échantillonnés pour poser le personnage au sol : un sur `stride` dans chaque maillage.
    public func groundingSamples(stride step: Int = 7) -> [SkinSample] {
        var samples: [SkinSample] = []
        let k = influences
        for mesh in meshes {
            for i in Swift.stride(from: mesh.vertexRange.lowerBound, to: mesh.vertexRange.upperBound, by: max(step, 1)) {
                var sampleBones: [Int] = [], sampleWeights: [Double] = []
                for j in (i * k)..<((i + 1) * k) where surface.weights[j] > 0 {
                    sampleBones.append(Int(surface.bones[j]))
                    sampleWeights.append(Double(surface.weights[j]))
                }
                samples.append(SkinSample(position: Vec3(Double(surface.rest[i * 3]), Double(surface.rest[i * 3 + 1]), Double(surface.rest[i * 3 + 2])),
                                          bones: sampleBones, weights: sampleWeights))
            }
        }
        return samples
    }

    /// Lecture séquentielle des valeurs du fichier.
    private struct Reader {
        let data: Data
        var offset = 0

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            try take(count) { Array($0) }
        }

        mutating func uint32() throws -> Int {
            try take(4) { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        }

        mutating func floats(_ count: Int) throws -> [Float] { try array(count, of: Float.self) }
        mutating func uint16s(_ count: Int) throws -> [UInt16] { try array(count, of: UInt16.self) }
        mutating func uint32s(_ count: Int) throws -> [UInt32] { try array(count, of: UInt32.self) }

        private mutating func array<T>(_ count: Int, of type: T.Type) throws -> [T] {
            try take(count * MemoryLayout<T>.stride) { raw in
                [T](unsafeUninitializedCapacity: count) { buffer, initialized in
                    UnsafeMutableRawBufferPointer(buffer).copyMemory(from: raw)
                    initialized = count
                }
            }
        }

        private mutating func take<R>(_ count: Int, _ body: (UnsafeRawBufferPointer) -> R) throws -> R {
            guard count >= 0, offset + count <= data.count else { throw ParseError.truncated }
            defer { offset += count }
            return data.withUnsafeBytes { raw in body(UnsafeRawBufferPointer(rebasing: raw[offset..<(offset + count)])) }
        }
    }
}
