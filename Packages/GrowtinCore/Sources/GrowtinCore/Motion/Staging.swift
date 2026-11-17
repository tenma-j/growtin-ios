import Foundation

/// Cadrage de la caméra sur un mouvement : calcul pur, partagé par l'app et les tests
/// (les planches de contrôle, scripts/mannequin/review.py, refont le même calcul).
public enum CameraFraming {
    public struct Shot: Equatable, Sendable {
        /// Point visé, dans le repère tourné de `yaw` autour de la verticale.
        public let target: Vec3
        /// Distance de la caméra au point visé.
        public let distance: Double
        /// Élévation de la caméra (degrés).
        public let pitch: Double

        /// Position de la caméra, dans le même repère que `target`.
        public var eye: Vec3 {
            let p = pitch * .pi / 180
            return target + Vec3(0, sin(p), cos(p)) * distance
        }
    }

    /// Marge par défaut autour des articulations (mètres).
    public static let defaultMargin = 0.2
    /// Cadrage resserré : la caméra ne s'approche jamais à moins de cette distance du point visé.
    public static let minimumDistance = 1.0

    /// Cadre l'ensemble des positions clés (une liste d'articulations par image clé).
    /// - `joints` : indices des articulations à cadrer (cadrage resserré) ; `nil` : toutes, sol compris.
    /// - `aspect` : largeur / hauteur de la vue ; `fieldOfView` : champ vertical (degrés).
    public static func shot(keyPositions: [[Vec3]], joints: [Int]?, yaw: Double, pitch: Double?, margin: Double?,
                            aspect: Double, fieldOfView: Double = 30) -> Shot? {
        let a = yaw * .pi / 180
        let c = cos(a), s = sin(a)
        let big = Double.greatestFiniteMagnitude
        var lo = Vec3(big, big, big)
        var hi = Vec3(-big, -big, -big)
        var found = false
        for positions in keyPositions {
            let indices = joints ?? Array(positions.indices)
            for i in indices where i >= 0 && i < positions.count {
                let p = positions[i]
                // Même rotation que le personnage : autour de la verticale, de `yaw` degrés.
                let v = Vec3(p.x * c + p.z * s, p.y, p.z * c - p.x * s)
                lo = Vec3(min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z))
                hi = Vec3(max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z))
                found = true
            }
        }
        guard found else { return nil }
        let m = margin ?? defaultMargin
        lo = lo - Vec3(m, m, m)
        hi = hi + Vec3(m, m, m)
        let tight = joints != nil
        if !tight { lo.y = 0 }
        let center = (lo + hi) * 0.5
        let width = hi.x - lo.x, height = hi.y - lo.y, depth = hi.z - lo.z
        let pitchDegrees = max(pitch ?? 8, 6)
        let p = pitchDegrees * .pi / 180
        let vfov = fieldOfView * .pi / 180
        let hfov = 2 * atan(tan(vfov / 2) * max(aspect, 0.1))
        if tight {
            // Vue plongeante : la hauteur à l'écran mêle la hauteur et la profondeur de la zone.
            let seen = height * cos(p) + depth * sin(p)
            let along = depth * cos(p) + height * sin(p)
            let distance = max(seen / 2 / tan(vfov / 2), width / 2 / tan(hfov / 2)) * 1.06 + along / 2
            return Shot(target: center, distance: max(distance, minimumDistance), pitch: pitchDegrees)
        }
        let distance = max(height / 2 / tan(vfov / 2), width / 2 / tan(hfov / 2)) * 1.06 + depth / 2
        return Shot(target: Vec3(center.x, center.y * 0.95, center.z), distance: distance, pitch: pitchDegrees)
    }
}

/// Serviette coincée sous un pied et tenue à deux mains : trois tronçons de bande (brin gauche, passage à plat
/// sous la voûte du pied, brin droit). Calcul pur : l'app et les planches de contrôle dessinent la même chose.
public enum TowelPath {
    /// Tronçon de bande : du point `from` au point `to`, largeur le long de `side`, épaisseur le long de `normal`
    /// (`side`, direction du tronçon et `normal` forment un repère direct).
    public struct Segment: Equatable, Sendable {
        public let from: Vec3
        public let to: Vec3
        public let side: Vec3
        public let normal: Vec3
        public var length: Double { (to - from).length }
    }

    /// Bande à plat (largeur, épaisseur) et bande resserrée dans le poing, en mètres.
    public static let defaultWidth = 0.05
    public static let defaultThickness = 0.006
    public static let gripWidth = 0.022
    public static let gripThickness = 0.012

    /// Point tenu dans le creux du poing : à `depth` mètres de la paume, à l'opposé du dos de la main
    /// (`palm` et `back` : deux sommets de la peau déformée, face à face de part et d'autre de la main).
    public static func grip(palm: Vec3, back: Vec3, depth: Double) -> Vec3 {
        let out = palm - back
        guard out.length > 1e-6 else { return palm }
        return palm + out * (depth / out.length)
    }

    /// - `leftHand`, `rightHand` : points tenus (voir `grip`) ; `foot` : sommet de la peau déformée ; `under` : décalages [x, z] depuis `foot`.
    /// - Renvoie [brin gauche (du sol vers la main), passage sous le pied, brin droit (du sol vers la main)],
    ///   ou `nil` si les points sont confondus.
    public static func segments(leftHand: Vec3, foot: Vec3, rightHand: Vec3, under: [[Double]], thickness: Double) -> [Segment]? {
        guard under.count == 2, under[0].count == 2, under[1].count == 2 else { return nil }
        let y = thickness / 2
        let a = Vec3(foot.x + under[0][0], y, foot.z + under[0][1])
        let b = Vec3(foot.x + under[1][0], y, foot.z + under[1][1])
        let across = b - a
        guard across.length > 0.005 else { return nil }
        let u = across * (1 / across.length)
        // Largeur de la bande sous le pied : horizontale, perpendiculaire au passage (dans l'axe du pied).
        let side = Vec3(-u.z, 0, u.x)
        func segment(_ from: Vec3, _ to: Vec3) -> Segment? {
            let d = to - from
            let l = d.length
            guard l > 0.01 else { return nil }
            let dir = d * (1 / l)
            let dot = side.x * dir.x + side.y * dir.y + side.z * dir.z
            let s = side - dir * dot
            guard s.length > 0.05 else { return nil }
            let sn = s * (1 / s.length)
            let n = Vec3(sn.y * dir.z - sn.z * dir.y, sn.z * dir.x - sn.x * dir.z, sn.x * dir.y - sn.y * dir.x)
            return Segment(from: from, to: to, side: sn, normal: n)
        }
        guard let left = segment(a, leftHand), let middle = segment(a, b), let right = segment(b, rightHand) else { return nil }
        return [left, middle, right]
    }
}
