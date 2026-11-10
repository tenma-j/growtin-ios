import Foundation

/// Image en niveaux de gris (0…255), généralement réduite à environ 512 px de large avant analyse.
public struct GrayImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 2, height > 2, pixels.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// Mesures techniques d'une photo. Elles décrivent **la qualité de la prise de vue**, jamais l'état des cheveux.
public struct ImageQuality: Codable, Hashable, Sendable {
    /// Variance du laplacien : plus elle est élevée, plus l'image est nette.
    public let sharpness: Double
    /// Luminosité moyenne, de 0 (noir) à 1 (blanc).
    public let brightness: Double
    /// Part des pixels presque blancs (surexposition).
    public let clippedHighlights: Double
    /// Part des pixels presque noirs (sous-exposition).
    public let clippedShadows: Double

    public init(sharpness: Double, brightness: Double, clippedHighlights: Double, clippedShadows: Double) {
        self.sharpness = sharpness
        self.brightness = brightness
        self.clippedHighlights = clippedHighlights
        self.clippedShadows = clippedShadows
    }
}

public struct QualityIssue: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case blurry, slightlyBlurry, tooDark, tooBright, overexposed, underexposed }

    public let kind: Kind
    public let message: String
    public var id: String { kind.rawValue }
}

public struct QualityAssessment: Hashable, Sendable {
    public enum Level: Int, Sendable, Comparable {
        case poor, acceptable, good
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        public var label: String {
            switch self {
            case .poor: "À reprendre"
            case .acceptable: "Utilisable"
            case .good: "Bonne qualité"
            }
        }
    }

    public let level: Level
    public let issues: [QualityIssue]
}

public enum ImageQualityAnalyzer {
    /// Seuils initiaux, à calibrer sur des photos réelles avant le lancement (images d'environ 512 px de large).
    public enum Thresholds {
        public static let blurry = 40.0
        public static let slightlyBlurry = 90.0
        public static let tooDark = 0.22
        public static let tooBright = 0.82
        public static let clipping = 0.12
    }

    public static func analyze(_ image: GrayImage) -> ImageQuality {
        let w = image.width, h = image.height
        let p = image.pixels
        var sum = 0.0, sumSquares = 0.0, count = 0.0
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let i = row + x
                let laplacian = Double(p[i - w]) + Double(p[i + w]) + Double(p[i - 1]) + Double(p[i + 1]) - 4 * Double(p[i])
                sum += laplacian
                sumSquares += laplacian * laplacian
                count += 1
            }
        }
        let mean = sum / count
        let variance = max(0, sumSquares / count - mean * mean)

        var total = 0.0, highlights = 0.0, shadows = 0.0
        for value in p {
            total += Double(value)
            if value >= 250 { highlights += 1 }
            if value <= 5 { shadows += 1 }
        }
        let n = Double(p.count)
        return ImageQuality(sharpness: variance, brightness: total / n / 255,
                            clippedHighlights: highlights / n, clippedShadows: shadows / n)
    }

    public static func assess(_ quality: ImageQuality) -> QualityAssessment {
        var issues: [QualityIssue] = []
        if quality.sharpness < Thresholds.blurry {
            issues.append(QualityIssue(kind: .blurry, message: "La photo est floue. Tiens l'appareil stable et laisse la mise au point se faire."))
        } else if quality.sharpness < Thresholds.slightlyBlurry {
            issues.append(QualityIssue(kind: .slightlyBlurry, message: "La photo manque un peu de netteté."))
        }
        if quality.brightness < Thresholds.tooDark {
            issues.append(QualityIssue(kind: .tooDark, message: "La photo est trop sombre. Rapproche-toi d'une source de lumière."))
        } else if quality.brightness > Thresholds.tooBright {
            issues.append(QualityIssue(kind: .tooBright, message: "La photo est trop claire. Évite la lumière directe."))
        }
        if quality.clippedHighlights > Thresholds.clipping {
            issues.append(QualityIssue(kind: .overexposed, message: "Des zones sont brûlées par la lumière : le cuir chevelu paraîtra plus visible qu'en réalité."))
        }
        if quality.clippedShadows > Thresholds.clipping {
            issues.append(QualityIssue(kind: .underexposed, message: "Des zones sont trop sombres pour être comparées."))
        }

        let level: QualityAssessment.Level
        if issues.contains(where: { $0.kind == .blurry || $0.kind == .tooDark || $0.kind == .tooBright }) {
            level = .poor
        } else if issues.isEmpty {
            level = .good
        } else {
            level = .acceptable
        }
        return QualityAssessment(level: level, issues: issues)
    }
}
