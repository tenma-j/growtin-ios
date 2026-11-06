import Foundation

/// Niveau de preuve affiché à côté de chaque recommandation.
public enum EvidenceLevel: String, Codable, Sendable, CaseIterable, Comparable {
    /// Recommandé par des recommandations cliniques ou des méta-analyses de bonne qualité.
    case strong
    /// Plusieurs études cohérentes, mais de qualité ou de taille limitée.
    case moderate
    /// Études peu nombreuses, petits effectifs ou résultats contradictoires.
    case limited
    /// Bénéfice démontré pour le bien-être ou la santé générale, mais pas d'effet capillaire démontré.
    case generalHealthOnly
    /// Aucune source fiable disponible.
    case insufficient

    public var label: String {
        switch self {
        case .strong: "Preuves solides"
        case .moderate: "Preuves modérées"
        case .limited: "Preuves limitées"
        case .generalHealthOnly: "Bien-être général"
        case .insufficient: "Preuves insuffisantes"
        }
    }

    public var explanation: String {
        switch self {
        case .strong: "Appuyé par des recommandations cliniques ou des méta-analyses de qualité."
        case .moderate: "Plusieurs études vont dans le même sens, mais avec des limites."
        case .limited: "Peu d'études, de petite taille : le bénéfice reste incertain."
        case .generalHealthOnly: "Bénéfique pour la santé générale. Aucun effet démontré sur la chute de cheveux."
        case .insufficient: "Aucune source fiable ne permet de conclure."
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    /// `strong` est le niveau le plus élevé.
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank > rhs.rank }
}

public enum SourceType: String, Codable, Sendable {
    case guideline, systematicReview = "systematic_review", metaAnalysis = "meta_analysis", rct, cohort, review
    case caseSeries = "case_series", publicHealthPage = "public_health_page", regulation, consensus
    case uncontrolledTrial = "uncontrolled_trial", originalStudy = "original_study"

    public var label: String {
        switch self {
        case .guideline: "Recommandation clinique"
        case .systematicReview: "Revue systématique"
        case .metaAnalysis: "Méta-analyse"
        case .rct: "Essai contrôlé randomisé"
        case .cohort: "Étude de cohorte"
        case .review: "Revue de littérature"
        case .caseSeries: "Série de cas"
        case .publicHealthPage: "Organisme de santé"
        case .regulation: "Texte réglementaire"
        case .consensus: "Consensus d'experts"
        case .uncontrolledTrial: "Étude sans groupe témoin"
        case .originalStudy: "Étude originale"
        }
    }
}

/// Une référence vérifiée manuellement. L'application et l'IA ne peuvent citer **que** ces références.
public struct SourceReference: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let authorsOrOrg: String
    public let publisherOrJournal: String
    /// `nil` pour les pages d'organismes qui n'affichent pas de date.
    public let year: Int?
    public let published: String?
    public let pmid: String?
    public let doi: String?
    public let url: URL
    public let type: SourceType
    public let keyFinding: String
    /// Date de la dernière vérification humaine ou outillée du lien et du contenu (AAAA-MM-JJ).
    public let verifiedOn: String
    /// Méthode de vérification utilisée (transparence sur la fiabilité du contrôle).
    public let verification: String

    enum CodingKeys: String, CodingKey {
        case id, title, year, published, pmid, doi, url, type, verification
        case authorsOrOrg = "authors_or_org"
        case publisherOrJournal = "publisher_or_journal"
        case keyFinding = "key_finding"
        case verifiedOn = "verified_on"
    }

    public init(id: String, title: String, authorsOrOrg: String, publisherOrJournal: String, year: Int?, published: String?,
                pmid: String?, doi: String?, url: URL, type: SourceType, keyFinding: String, verifiedOn: String,
                verification: String) {
        self.id = id
        self.title = title
        self.authorsOrOrg = authorsOrOrg
        self.publisherOrJournal = publisherOrJournal
        self.year = year
        self.published = published
        self.pmid = pmid
        self.doi = doi
        self.url = url
        self.type = type
        self.keyFinding = keyFinding
        self.verifiedOn = verifiedOn
        self.verification = verification
    }

    /// Citation courte, par exemple « Trost et al. — J Am Acad Dermatol, 2006 ».
    public var shortCitation: String {
        guard let year else { return "\(authorsOrOrg) — \(publisherOrJournal)" }
        return "\(authorsOrOrg) — \(publisherOrJournal), \(year)"
    }
}

public enum SourceLibraryError: Error, Equatable {
    case resourceMissing
    case duplicateID(String)
}

/// Base documentaire embarquée dans l'application (fichier `sources.json`).
public struct SourceLibrary: Sendable {
    public let sources: [String: SourceReference]

    public init(sources: [SourceReference]) throws {
        var map: [String: SourceReference] = [:]
        for source in sources {
            guard map[source.id] == nil else { throw SourceLibraryError.duplicateID(source.id) }
            map[source.id] = source
        }
        self.sources = map
    }

    public static func bundled() throws -> SourceLibrary {
        guard let url = Bundle.module.url(forResource: "sources", withExtension: "json") else {
            throw SourceLibraryError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try SourceLibrary(sources: JSONDecoder().decode([SourceReference].self, from: data))
    }

    public subscript(id: String) -> SourceReference? { sources[id] }

    public func references(for ids: [String]) -> [SourceReference] { ids.compactMap { sources[$0] } }

    public var sorted: [SourceReference] { sources.values.sorted { ($0.year ?? 0, $0.title) > ($1.year ?? 0, $1.title) } }
}

public enum RecommendationCategory: String, Codable, Sendable, CaseIterable {
    case nutrition, sleep, stress, activity, hairCare, medical, tracking

    public var label: String {
        switch self {
        case .nutrition: "Nutrition"
        case .sleep: "Sommeil"
        case .stress: "Stress"
        case .activity: "Activité physique"
        case .hairCare: "Soins capillaires"
        case .medical: "Santé"
        case .tracking: "Suivi"
        }
    }

    public var symbol: String {
        switch self {
        case .nutrition: "leaf"
        case .sleep: "moon.stars"
        case .stress: "wind"
        case .activity: "figure.walk"
        case .hairCare: "comb"
        case .medical: "stethoscope"
        case .tracking: "camera.viewfinder"
        }
    }
}

/// Fiche de preuve : tout ce que l'utilisateur doit savoir sur une recommandation.
public struct EvidenceCard: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let category: RecommendationCategory
    public let explanation: String
    public let expectedBenefit: String
    public let evidence: EvidenceLevel
    /// Précise ce qui n'est **pas** démontré, en particulier vis-à-vis de la chute de cheveux.
    public let limits: String
    public let sourceIDs: [String]

    public init(id: String, title: String, category: RecommendationCategory, explanation: String,
                expectedBenefit: String, evidence: EvidenceLevel, limits: String, sourceIDs: [String]) {
        self.id = id
        self.title = title
        self.category = category
        self.explanation = explanation
        self.expectedBenefit = expectedBenefit
        self.evidence = evidence
        self.limits = limits
        self.sourceIDs = sourceIDs
    }
}
