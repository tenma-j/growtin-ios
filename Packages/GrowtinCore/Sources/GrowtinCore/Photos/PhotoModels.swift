import Foundation

/// Zones photographiables pour le suivi.
public enum PhotoZone: String, LabeledOption {
    case frontalHairline, leftTemple, rightTemple, top, vertex, centralPart

    public var label: String {
        switch self {
        case .frontalHairline: "Ligne frontale"
        case .leftTemple: "Tempe gauche"
        case .rightTemple: "Tempe droite"
        case .top: "Dessus du crâne"
        case .vertex: "Vertex (sommet)"
        case .centralPart: "Raie centrale"
        }
    }

    public var symbol: String {
        switch self {
        case .frontalHairline: "person.crop.circle"
        case .leftTemple: "arrow.left.circle"
        case .rightTemple: "arrow.right.circle"
        case .top: "circle.dashed"
        case .vertex: "smallcircle.filled.circle"
        case .centralPart: "line.diagonal"
        }
    }

    /// Consigne de prise de vue affichée sur l'écran de capture.
    public var instruction: String {
        switch self {
        case .frontalHairline:
            "Face à la caméra, cheveux dégagés du front, tête droite. Aligne tes sourcils sur la ligne du guide."
        case .leftTemple:
            "Tourne la tête vers la droite pour présenter ta tempe gauche, cheveux dégagés vers l'arrière."
        case .rightTemple:
            "Tourne la tête vers la gauche pour présenter ta tempe droite, cheveux dégagés vers l'arrière."
        case .top:
            "Penche légèrement la tête vers l'avant. Idéalement, demande à quelqu'un de prendre la photo au-dessus de ta tête."
        case .vertex:
            "Photo du sommet du crâne, vue de dessus. Demande à quelqu'un, ou utilise un miroir et la caméra arrière."
        case .centralPart:
            "Fais ta raie au milieu, puis photographie-la de dessus, à environ 20 cm."
        }
    }

    /// Caméra conseillée lorsque l'utilisateur se photographie seul.
    public var preferredCamera: CameraPosition {
        switch self {
        case .frontalHairline, .leftTemple, .rightTemple: .front
        case .top, .vertex, .centralPart: .back
        }
    }

    /// Zones proposées par défaut, à partir des zones déclarées dans l'onboarding.
    public static func suggested(for zones: Set<ScalpZone>) -> [PhotoZone] {
        var result = Set<PhotoZone>()
        for zone in zones {
            switch zone {
            case .frontalHairline: result.insert(.frontalHairline)
            case .leftTemple: result.insert(.leftTemple)
            case .rightTemple: result.insert(.rightTemple)
            case .top: result.insert(.top)
            case .vertex: result.insert(.vertex)
            case .centralPart: result.insert(.centralPart)
            case .diffuse: result.formUnion([.top, .centralPart])
            }
        }
        if result.isEmpty { result = [.frontalHairline, .leftTemple, .rightTemple, .vertex] }
        return allCases.filter(result.contains)
    }
}

public enum CameraPosition: String, Codable, Sendable {
    case front, back, library

    public var label: String {
        switch self {
        case .front: "Caméra avant"
        case .back: "Caméra arrière"
        case .library: "Importée de Photos"
        }
    }
}

public enum LightingSource: String, LabeledOption {
    case window, ceiling, bathroom, outdoor, other

    public var label: String {
        switch self {
        case .window: "Lumière d'une fenêtre"
        case .ceiling: "Plafonnier"
        case .bathroom: "Lumière de salle de bain"
        case .outdoor: "Extérieur"
        case .other: "Autre"
        }
    }
}

/// Conditions déclarées au moment de la photo : elles influencent fortement l'aspect des cheveux.
public struct CaptureConditions: Codable, Hashable, Sendable {
    public var dryHair: Bool
    public var usualStyling: Bool
    public var noProduct: Bool
    public var lighting: LightingSource

    public init(dryHair: Bool = true, usualStyling: Bool = true, noProduct: Bool = true, lighting: LightingSource = .window) {
        self.dryHair = dryHair
        self.usualStyling = usualStyling
        self.noProduct = noProduct
        self.lighting = lighting
    }
}

/// Informations de cadrage mesurées à la prise de vue (toutes facultatives).
public struct FramingInfo: Codable, Hashable, Sendable {
    /// Centre et largeur du visage détecté, en coordonnées normalisées (0…1).
    public var faceCenterX: Double?
    public var faceCenterY: Double?
    public var faceWidth: Double?
    /// Inclinaison de l'appareil, en degrés.
    public var devicePitch: Double?
    public var deviceRoll: Double?

    public init(faceCenterX: Double? = nil, faceCenterY: Double? = nil, faceWidth: Double? = nil,
                devicePitch: Double? = nil, deviceRoll: Double? = nil) {
        self.faceCenterX = faceCenterX
        self.faceCenterY = faceCenterY
        self.faceWidth = faceWidth
        self.devicePitch = devicePitch
        self.deviceRoll = deviceRoll
    }
}

public struct PhotoEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let zone: PhotoZone
    public let day: DayKey
    public let takenAt: Date
    /// Nom du fichier image, stocké uniquement sur l'appareil.
    public let fileName: String
    public let camera: CameraPosition
    public var quality: ImageQuality?
    public var conditions: CaptureConditions
    public var framing: FramingInfo
    public var note: String
    /// Dernière lecture IA demandée par l'utilisateur, conservée uniquement sur l'appareil.
    public var reading: PhotoReading? = nil

    public init(id: UUID = UUID(), zone: PhotoZone, day: DayKey, takenAt: Date = Date(), fileName: String,
                camera: CameraPosition, quality: ImageQuality?, conditions: CaptureConditions,
                framing: FramingInfo = FramingInfo(), note: String = "") {
        self.id = id
        self.zone = zone
        self.day = day
        self.takenAt = takenAt
        self.fileName = fileName
        self.camera = camera
        self.quality = quality
        self.conditions = conditions
        self.framing = framing
        self.note = note
    }
}

/// Lecture d'une photo par l'IA : une description visuelle prudente, jamais un diagnostic.
public struct PhotoReading: Codable, Hashable, Sendable {
    public var conditions: String
    public var observations: [String]
    /// Différences d'aspect avec la photo précédente de la même zone (si elle a été envoyée).
    public var comparison: String?
    public var nextPhotoTips: [String]
    /// Un aspect inhabituel du cuir chevelu est visible : un avis médical rapide est conseillé.
    public var seeProfessionalSoon: Bool
    public var comparedWith: UUID?
    public var createdAt: Date

    public init(conditions: String, observations: [String], comparison: String?, nextPhotoTips: [String],
                seeProfessionalSoon: Bool, comparedWith: UUID? = nil, createdAt: Date = Date()) {
        self.conditions = conditions
        self.observations = observations
        self.comparison = comparison
        self.nextPhotoTips = nextPhotoTips
        self.seeProfessionalSoon = seeProfessionalSoon
        self.comparedWith = comparedWith
        self.createdAt = createdAt
    }

    /// Rappel affiché sous chaque lecture, quel que soit son contenu.
    public static let disclaimer = "Cette lecture décrit une image, pas l'état de ta santé : la lumière, l'angle et le coiffage changent beaucoup l'aspect des cheveux. Seul un médecin ou un dermatologue peut évaluer une chute de cheveux. Si quelque chose t'inquiète, montre-lui tes photos."

    public static let urgentAdvice = "Un aspect inhabituel du cuir chevelu semble visible sur cette photo. Par prudence, prends rendez-vous avec un médecin ou un dermatologue pour le lui montrer."
}

extension CaptureConditions {
    /// Résumé transmis avec une photo à lire.
    public var summary: String {
        [dryHair ? "cheveux secs" : "cheveux mouillés",
         usualStyling ? "coiffage habituel" : "coiffage inhabituel",
         noProduct ? "sans produit" : "avec produit",
         lighting.label.lowercased()].joined(separator: ", ")
    }
}

extension PhotoTimeline {
    /// Photo précédente de la même zone (pour une lecture comparée), si elle existe.
    public static func previous(of entry: PhotoEntry, in photos: [PhotoEntry]) -> PhotoEntry? {
        self.photos(photos, zone: entry.zone).last { $0.takenAt < entry.takenAt }
    }
}

public enum PhotoTimeline {
    /// Photos d'une zone, de la plus ancienne à la plus récente.
    public static func photos(_ photos: [PhotoEntry], zone: PhotoZone) -> [PhotoEntry] {
        photos.filter { $0.zone == zone }.sorted { $0.takenAt < $1.takenAt }
    }

    public static func latest(_ photos: [PhotoEntry], zone: PhotoZone) -> PhotoEntry? {
        self.photos(photos, zone: zone).last
    }

    /// Jour de la dernière série de photos, toutes zones confondues.
    public static func lastSessionDay(_ photos: [PhotoEntry]) -> DayKey? {
        photos.map(\.day).max()
    }

    /// Paire proposée par défaut pour une comparaison : la première et la dernière photo de bonne qualité.
    public static func defaultComparison(_ photos: [PhotoEntry], zone: PhotoZone) -> (before: PhotoEntry, after: PhotoEntry)? {
        let list = self.photos(photos, zone: zone)
        let usable = list.filter { ($0.quality.map(ImageQualityAnalyzer.assess)?.level ?? .acceptable) != .poor }
        let candidates = usable.count >= 2 ? usable : list
        guard let first = candidates.first, let last = candidates.last, first.id != last.id else { return nil }
        return (first, last)
    }
}
