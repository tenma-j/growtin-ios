/// Surface du personnage prête à être déformée sur le processeur : sommets de tous les maillages bout à bout
/// (peau, tissu, liseré), influences d'os et triangles. Les sommets de même position au repos (copies le long des
/// lignes de la tenue) sont « soudés » pour le calcul des normales : l'éclairage reste continu d'une matière à l'autre.
public struct DeformableSurface: Sendable {
    public let vertexCount: Int
    /// x, y, z par sommet.
    public let rest: [Float]
    public let restNormals: [Float]
    /// Nombre d'influences d'os par sommet.
    public let influences: Int
    /// `influences` os et poids par sommet (poids nuls pour les places inutilisées).
    public let bones: [Int32]
    public let weights: [Float]
    /// 3 indices de sommets (dans la surface entière) par triangle.
    public let triangles: [Int32]
    /// Pour chaque sommet, son groupe de soudure.
    public let weld: [Int32]
    public let weldCount: Int

    public init(rest: [Float], restNormals: [Float], bones: [Int32], weights: [Float], influences: Int, triangles: [Int32]) {
        let n = rest.count / 3
        precondition(rest.count == n * 3 && restNormals.count == rest.count, "positions et normales : 3 valeurs par sommet")
        precondition(influences > 0 && bones.count == n * influences && weights.count == n * influences, "influences par sommet")
        precondition(triangles.count % 3 == 0 && triangles.allSatisfy { $0 >= 0 && Int($0) < n }, "triangles invalides")
        vertexCount = n
        self.rest = rest
        self.restNormals = restNormals
        self.influences = influences
        self.bones = bones
        self.weights = weights
        self.triangles = triangles

        struct Key: Hashable { let x, y, z: UInt32 }
        var groups: [Key: Int32] = [:]
        groups.reserveCapacity(n)
        var weld = [Int32](repeating: 0, count: n)
        for i in 0..<n {
            let key = Key(x: rest[i * 3].bitPattern, y: rest[i * 3 + 1].bitPattern, z: rest[i * 3 + 2].bitPattern)
            if let group = groups[key] {
                weld[i] = group
            } else {
                let group = Int32(groups.count)
                groups[key] = group
                weld[i] = group
            }
        }
        self.weld = weld
        weldCount = groups.count
    }
}

/// Skinning linéaire sur le processeur, puis normales recalculées sur la surface déformée.
///
/// Le skinning du GPU se contente de tourner les normales de la pose de référence avec les os. Dans une pliure très
/// ouverte (épaule bras levés), la surface réelle s'oriente tout autrement (jusqu'à 90° d'écart) : taches claires ou
/// sombres sur l'épaule. Ici les normales viennent des triangles déformés eux-mêmes, donc l'éclairage suit la forme.
///
/// Les boucles sont écrites en scalaires sur des pointeurs : rapides même sans optimisation du compilateur (Debug).
public final class SurfaceDeformer {
    public let surface: DeformableSurface
    /// Positions et normales de la dernière déformation (x, y, z par sommet).
    public private(set) var positions: [Float]
    public private(set) var normals: [Float]

    private let parents: [Int32]
    private let heads: [Float]
    /// 12 valeurs par articulation : les trois colonnes de la rotation, puis la translation.
    private var world: [Float]
    private var skin: [Float]
    private var accumulated: [Float]

    /// `nil` si la surface désigne un os absent du squelette.
    public init?(surface: DeformableSurface, skeleton: Skeleton) {
        guard surface.bones.allSatisfy({ $0 >= 0 && Int($0) < skeleton.joints.count }) else { return nil }
        self.surface = surface
        positions = surface.rest
        normals = surface.restNormals
        parents = skeleton.parentIndex.map { Int32($0 ?? -1) }
        heads = skeleton.joints.flatMap { [Float($0.head[0]), Float($0.head[1]), Float($0.head[2])] }
        world = [Float](repeating: 0, count: skeleton.joints.count * 12)
        skin = world
        accumulated = [Float](repeating: 0, count: surface.weldCount * 3)
    }

    public var jointCount: Int { parents.count }

    /// Déforme la surface. `rotations` : rotation locale de chaque articulation (quaternion x, y, z, w ; celle de la
    /// racine inclut sa rotation globale). `root` : position de la racine dans le repère du corps.
    public func deform(rotations: [SIMD4<Float>], root: SIMD3<Float>) {
        precondition(rotations.count == jointCount, "une rotation par articulation")
        computeSkinMatrices(rotations, root)
        skinPositions()
        computeNormals()
    }

    /// Copie positions et normales d'une plage de sommets (x, y, z en Float32 serrés) vers deux tampons.
    public func copy(vertices range: Range<Int>, positions positionTarget: UnsafeMutableRawPointer, normals normalTarget: UnsafeMutableRawPointer) {
        precondition(range.lowerBound >= 0 && range.upperBound <= surface.vertexCount)
        guard !range.isEmpty else { return }
        positions.withUnsafeBytes { source in
            positionTarget.copyMemory(from: source.baseAddress! + range.lowerBound * 12, byteCount: range.count * 12)
        }
        normals.withUnsafeBytes { source in
            normalTarget.copyMemory(from: source.baseAddress! + range.lowerBound * 12, byteCount: range.count * 12)
        }
    }

    // MARK: - Étapes

    /// Cinématique directe (les parents précèdent leurs enfants), puis matrice de skinning de chaque articulation :
    /// transformation monde suivie de l'inverse de la pose de référence (une simple translation : repères alignés).
    private func computeSkinMatrices(_ rotations: [SIMD4<Float>], _ root: SIMD3<Float>) {
        let count = jointCount
        world.withUnsafeMutableBufferPointer { worldBuffer in
            skin.withUnsafeMutableBufferPointer { skinBuffer in
                heads.withUnsafeBufferPointer { headBuffer in
                    parents.withUnsafeBufferPointer { parentBuffer in
                        let W = worldBuffer.baseAddress!, S = skinBuffer.baseAddress!
                        let H = headBuffer.baseAddress!, P = parentBuffer.baseAddress!
                        var j = 0
                        while j < count {
                            let q = rotations[j]
                            var x = q.x, y = q.y, z = q.z, w = q.w
                            let norm = (x * x + y * y + z * z + w * w).squareRoot()
                            if norm > 1e-12 {
                                x /= norm; y /= norm; z /= norm; w /= norm
                            } else {
                                x = 0; y = 0; z = 0; w = 1
                            }
                            // Rotation locale, colonne par colonne.
                            let r00 = 1 - 2 * (y * y + z * z), r10 = 2 * (x * y + z * w), r20 = 2 * (x * z - y * w)
                            let r01 = 2 * (x * y - z * w), r11 = 1 - 2 * (x * x + z * z), r21 = 2 * (y * z + x * w)
                            let r02 = 2 * (x * z + y * w), r12 = 2 * (y * z - x * w), r22 = 1 - 2 * (x * x + y * y)
                            let o = j * 12
                            let p = Int(P[j])
                            if p < 0 {
                                W[o] = r00; W[o + 1] = r10; W[o + 2] = r20
                                W[o + 3] = r01; W[o + 4] = r11; W[o + 5] = r21
                                W[o + 6] = r02; W[o + 7] = r12; W[o + 8] = r22
                                W[o + 9] = root.x; W[o + 10] = root.y; W[o + 11] = root.z
                            } else {
                                let po = p * 12
                                let a00 = W[po], a10 = W[po + 1], a20 = W[po + 2]
                                let a01 = W[po + 3], a11 = W[po + 4], a21 = W[po + 5]
                                let a02 = W[po + 6], a12 = W[po + 7], a22 = W[po + 8]
                                W[o] = a00 * r00 + a01 * r10 + a02 * r20
                                W[o + 1] = a10 * r00 + a11 * r10 + a12 * r20
                                W[o + 2] = a20 * r00 + a21 * r10 + a22 * r20
                                W[o + 3] = a00 * r01 + a01 * r11 + a02 * r21
                                W[o + 4] = a10 * r01 + a11 * r11 + a12 * r21
                                W[o + 5] = a20 * r01 + a21 * r11 + a22 * r21
                                W[o + 6] = a00 * r02 + a01 * r12 + a02 * r22
                                W[o + 7] = a10 * r02 + a11 * r12 + a12 * r22
                                W[o + 8] = a20 * r02 + a21 * r12 + a22 * r22
                                let dx = H[j * 3] - H[p * 3], dy = H[j * 3 + 1] - H[p * 3 + 1], dz = H[j * 3 + 2] - H[p * 3 + 2]
                                W[o + 9] = a00 * dx + a01 * dy + a02 * dz + W[po + 9]
                                W[o + 10] = a10 * dx + a11 * dy + a12 * dz + W[po + 10]
                                W[o + 11] = a20 * dx + a21 * dy + a22 * dz + W[po + 11]
                            }
                            var k = 0
                            while k < 9 { S[o + k] = W[o + k]; k += 1 }
                            let hx = H[j * 3], hy = H[j * 3 + 1], hz = H[j * 3 + 2]
                            S[o + 9] = W[o + 9] - (W[o] * hx + W[o + 3] * hy + W[o + 6] * hz)
                            S[o + 10] = W[o + 10] - (W[o + 1] * hx + W[o + 4] * hy + W[o + 7] * hz)
                            S[o + 11] = W[o + 11] - (W[o + 2] * hx + W[o + 5] * hy + W[o + 8] * hz)
                            j += 1
                        }
                    }
                }
            }
        }
    }

    /// Skinning linéaire : somme pondérée des positions données par chaque os.
    private func skinPositions() {
        let n = surface.vertexCount, influences = surface.influences
        positions.withUnsafeMutableBufferPointer { out in
            surface.rest.withUnsafeBufferPointer { restBuffer in
                surface.bones.withUnsafeBufferPointer { boneBuffer in
                    surface.weights.withUnsafeBufferPointer { weightBuffer in
                        skin.withUnsafeBufferPointer { skinBuffer in
                            let X = out.baseAddress!, R = restBuffer.baseAddress!, B = boneBuffer.baseAddress!
                            let Wt = weightBuffer.baseAddress!, S = skinBuffer.baseAddress!
                            var i = 0
                            while i < n {
                                let px = R[i * 3], py = R[i * 3 + 1], pz = R[i * 3 + 2]
                                var ox: Float = 0, oy: Float = 0, oz: Float = 0
                                var k = i * influences
                                let end = k + influences
                                while k < end {
                                    let w = Wt[k]
                                    if w != 0 {
                                        let o = Int(B[k]) * 12
                                        ox += w * (S[o] * px + S[o + 3] * py + S[o + 6] * pz + S[o + 9])
                                        oy += w * (S[o + 1] * px + S[o + 4] * py + S[o + 7] * pz + S[o + 10])
                                        oz += w * (S[o + 2] * px + S[o + 5] * py + S[o + 8] * pz + S[o + 11])
                                    }
                                    k += 1
                                }
                                X[i * 3] = ox; X[i * 3 + 1] = oy; X[i * 3 + 2] = oz
                                i += 1
                            }
                        }
                    }
                }
            }
        }
    }

    /// Normales de la surface déformée : somme des normales des triangles voisins (pondérées par leur aire), par
    /// groupe de soudure. Un sommet isolé garde sa normale précédente.
    private func computeNormals() {
        let n = surface.vertexCount
        let triangleValues = surface.triangles.count
        accumulated.withUnsafeMutableBufferPointer { accumulatedBuffer in
            positions.withUnsafeBufferPointer { positionBuffer in
                surface.triangles.withUnsafeBufferPointer { triangleBuffer in
                    surface.weld.withUnsafeBufferPointer { weldBuffer in
                        normals.withUnsafeMutableBufferPointer { normalBuffer in
                            let A = accumulatedBuffer.baseAddress!, X = positionBuffer.baseAddress!
                            let T = triangleBuffer.baseAddress!, G = weldBuffer.baseAddress!, N = normalBuffer.baseAddress!
                            var i = 0
                            while i < accumulatedBuffer.count { A[i] = 0; i += 1 }
                            var t = 0
                            while t < triangleValues {
                                let a = Int(T[t]) * 3, b = Int(T[t + 1]) * 3, c = Int(T[t + 2]) * 3
                                let ax = X[a], ay = X[a + 1], az = X[a + 2]
                                let ux = X[b] - ax, uy = X[b + 1] - ay, uz = X[b + 2] - az
                                let vx = X[c] - ax, vy = X[c + 1] - ay, vz = X[c + 2] - az
                                let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
                                let ga = Int(G[a / 3]) * 3, gb = Int(G[b / 3]) * 3, gc = Int(G[c / 3]) * 3
                                A[ga] += nx; A[ga + 1] += ny; A[ga + 2] += nz
                                A[gb] += nx; A[gb + 1] += ny; A[gb + 2] += nz
                                A[gc] += nx; A[gc + 1] += ny; A[gc + 2] += nz
                                t += 3
                            }
                            i = 0
                            while i < n {
                                let g = Int(G[i]) * 3
                                let x = A[g], y = A[g + 1], z = A[g + 2]
                                let length = (x * x + y * y + z * z).squareRoot()
                                if length > 1e-12 {
                                    N[i * 3] = x / length; N[i * 3 + 1] = y / length; N[i * 3 + 2] = z / length
                                }
                                i += 1
                            }
                        }
                    }
                }
            }
        }
    }
}
