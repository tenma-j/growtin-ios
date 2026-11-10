import Foundation

public enum ExerciseCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case walking, cardio, mobility, stretching, yoga, relaxation, breathing, scalpMassage

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .walking: "Marche"
        case .cardio: "Cardio léger"
        case .mobility: "Mobilité"
        case .stretching: "Étirements"
        case .yoga: "Yoga doux"
        case .relaxation: "Relaxation"
        case .breathing: "Respiration"
        case .scalpMassage: "Cuir chevelu"
        }
    }

    public var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .cardio: "figure.mixed.cardio"
        case .mobility: "figure.flexibility"
        case .stretching: "figure.cooldown"
        case .yoga: "figure.yoga"
        case .relaxation: "figure.mind.and.body"
        case .breathing: "wind"
        case .scalpMassage: "hand.raised"
        }
    }
}

public enum ExerciseLevel: String, Codable, Sendable {
    case beginner, gentle

    public var label: String {
        switch self {
        case .beginner: "Débutant"
        case .gentle: "Très doux"
        }
    }
}

public struct ExerciseStep: Codable, Hashable, Sendable {
    public let title: String
    public let instruction: String
    public let seconds: Int
    /// Symbole SF illustrant le mouvement.
    public let symbol: String

    public init(_ title: String, _ instruction: String, seconds: Int, symbol: String) {
        self.title = title
        self.instruction = instruction
        self.seconds = seconds
        self.symbol = symbol
    }
}

/// Séance d'activité ou de bien-être. Les bénéfices annoncés concernent la santé générale :
/// aucune séance n'est présentée comme agissant sur la repousse ou la densité des cheveux.
public struct Exercise: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let category: ExerciseCategory
    public let level: ExerciseLevel
    public let summary: String
    public let steps: [ExerciseStep]
    public let benefits: String
    public let hairNote: String
    public let precautions: [String]
    public let contraindications: [String]
    public let evidence: EvidenceLevel
    public let sourceIDs: [String]
    /// Identifiant d'une habitude de la routine que cette séance permet de cocher.
    public let habitTemplateID: String?

    public var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
    public var durationMinutes: Int { max(1, Int((Double(totalSeconds) / 60).rounded())) }
}

public enum ExerciseLibrary {
    static let generalHairNote = "Bouger est bon pour la santé générale, le sommeil et le stress. Aucune étude ne montre qu'une activité physique fasse repousser les cheveux ou ralentisse une alopécie."

    public static let all: [Exercise] = [
        Exercise(
            id: "marche-active", title: "Marche active", category: .walking, level: .beginner,
            summary: "Vingt minutes de marche, avec un échauffement et un retour au calme.",
            steps: [
                ExerciseStep("Échauffement", "Marche à allure tranquille, épaules relâchées.", seconds: 180, symbol: "figure.walk"),
                ExerciseStep("Marche soutenue", "Accélère jusqu'à respirer plus vite tout en pouvant encore parler.", seconds: 840, symbol: "figure.walk.motion"),
                ExerciseStep("Retour au calme", "Ralentis progressivement et respire profondément.", seconds: 180, symbol: "figure.walk")
            ],
            benefits: "L'OMS recommande 150 à 300 minutes d'activité modérée par semaine : elle améliore la santé cardiovasculaire, le sommeil et l'humeur.",
            hairNote: generalHairNote,
            precautions: ["Porte des chaussures confortables.", "Bois de l'eau, surtout s'il fait chaud.", "Arrête-toi en cas de douleur thoracique, de vertige ou d'essoufflement inhabituel."],
            contraindications: ["Douleur à la marche ou blessure récente aux membres inférieurs : demande l'avis d'un professionnel de santé."],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: HabitCatalog.walk.id),

        Exercise(
            id: "cardio-leger", title: "Cardio léger sans matériel", category: .cardio, level: .beginner,
            summary: "Dix minutes de mouvements simples à faire chez soi, sans sauts.",
            steps: [
                ExerciseStep("Marche sur place", "Lève les genoux à hauteur confortable et balance les bras.", seconds: 120, symbol: "figure.walk"),
                ExerciseStep("Pas chassés", "Déplace-toi latéralement, deux pas à droite puis deux à gauche.", seconds: 60, symbol: "figure.step.training"),
                ExerciseStep("Montées de genoux", "Alterne les genoux devant toi, dos droit, sans sauter.", seconds: 60, symbol: "figure.highintensity.intervaltraining"),
                ExerciseStep("Récupération", "Marche sur place lentement.", seconds: 60, symbol: "figure.walk"),
                ExerciseStep("Squats partiels", "Plie légèrement les genoux comme pour t'asseoir, puis remonte.", seconds: 60, symbol: "figure.strengthtraining.functional"),
                ExerciseStep("Pas chassés", "Reprends les pas chassés à ton rythme.", seconds: 60, symbol: "figure.step.training"),
                ExerciseStep("Montées de genoux", "Alterne les genoux, respiration régulière.", seconds: 60, symbol: "figure.highintensity.intervaltraining"),
                ExerciseStep("Retour au calme", "Marche lentement, puis respire profondément.", seconds: 120, symbol: "figure.cooldown")
            ],
            benefits: "Une activité modérée régulière contribue à la santé cardiovasculaire et au bien-être.",
            hairNote: generalHairNote,
            precautions: ["Adapte l'intensité : tu dois pouvoir parler.", "Arrête en cas de douleur ou de malaise."],
            contraindications: ["Problème cardiaque, articulaire ou grossesse : demande d'abord l'avis de ton médecin."],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: nil),

        Exercise(
            id: "mobilite-matin", title: "Mobilité du matin", category: .mobility, level: .gentle,
            summary: "Huit minutes pour délier doucement les épaules, le dos et les hanches.",
            steps: [
                ExerciseStep("Épaules", "Fais de grands cercles lents avec les épaules, vers l'arrière puis vers l'avant.", seconds: 60, symbol: "figure.arms.open"),
                ExerciseStep("Nuque", "Incline doucement la tête d'un côté puis de l'autre, sans forcer ni faire de cercles complets.", seconds: 60, symbol: "figure.mind.and.body"),
                ExerciseStep("Chat-vache", "À quatre pattes, arrondis le dos en expirant puis creuse-le en inspirant.", seconds: 90, symbol: "figure.flexibility"),
                ExerciseStep("Hanches", "Debout, fais des cercles lents avec le bassin.", seconds: 60, symbol: "figure.cooldown"),
                ExerciseStep("Fentes douces", "Avance un pied, plie légèrement les genoux, reviens. Alterne.", seconds: 90, symbol: "figure.strengthtraining.functional"),
                ExerciseStep("Chevilles", "Sur une jambe, en te tenant à un mur, fais des cercles avec la cheville. Change de pied.", seconds: 60, symbol: "figure.stand"),
                ExerciseStep("Grand étirement", "Monte les bras au-dessus de la tête et grandis-toi en respirant.", seconds: 60, symbol: "figure.arms.open")
            ],
            benefits: "Des mouvements doux et réguliers aident à se sentir moins raide et à démarrer la journée en douceur.",
            hairNote: generalHairNote,
            precautions: ["Mouvements lents, dans une amplitude confortable.", "Ne force jamais sur la nuque."],
            contraindications: ["Douleur cervicale ou lombaire importante : demande l'avis d'un kinésithérapeute ou d'un médecin."],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: nil),

        Exercise(
            id: "etirements-soir", title: "Étirements du soir", category: .stretching, level: .gentle,
            summary: "Dix minutes d'étirements lents pour relâcher les tensions avant de dormir.",
            steps: [
                ExerciseStep("Respiration", "Assis, ferme les yeux et ralentis ta respiration.", seconds: 60, symbol: "wind"),
                ExerciseStep("Épaules et bras", "Passe un bras devant la poitrine et maintiens-le avec l'autre. Change de côté à mi-temps.", seconds: 90, symbol: "figure.arms.open"),
                ExerciseStep("Dos", "Assis, jambes allongées, penche-toi doucement vers l'avant sans forcer.", seconds: 90, symbol: "figure.flexibility"),
                ExerciseStep("Torsion", "Assis, tourne doucement le buste d'un côté, puis de l'autre.", seconds: 90, symbol: "figure.mind.and.body"),
                ExerciseStep("Hanches", "Allongé, ramène un genou contre la poitrine. Change de jambe à mi-temps.", seconds: 120, symbol: "figure.cooldown"),
                ExerciseStep("Posture de l'enfant", "À genoux, fesses sur les talons, allonge les bras devant toi et relâche.", seconds: 90, symbol: "figure.yoga"),
                ExerciseStep("Relâchement", "Allongé sur le dos, laisse le corps s'alourdir.", seconds: 60, symbol: "bed.double")
            ],
            benefits: "Un moment calme avant le coucher peut aider à se détendre.",
            hairNote: generalHairNote,
            precautions: ["Un étirement ne doit jamais faire mal.", "Respire calmement, sans bloquer la respiration."],
            contraindications: ["Blessure récente ou opération : demande l'avis d'un professionnel de santé."],
            evidence: .insufficient, sourceIDs: [], habitTemplateID: nil),

        Exercise(
            id: "yoga-doux", title: "Yoga doux", category: .yoga, level: .gentle,
            summary: "Douze minutes de postures simples, accessibles aux débutants.",
            steps: [
                ExerciseStep("Posture de la montagne", "Debout, pieds parallèles, épaules relâchées, respire profondément.", seconds: 60, symbol: "figure.stand"),
                ExerciseStep("Salutation des bras", "Inspire en levant les bras, expire en les redescendant.", seconds: 90, symbol: "figure.arms.open"),
                ExerciseStep("Flexion avant douce", "Penche-toi vers l'avant, genoux fléchis, tête relâchée.", seconds: 60, symbol: "figure.flexibility"),
                ExerciseStep("Chat-vache", "À quatre pattes, alterne dos rond et dos creux avec la respiration.", seconds: 120, symbol: "figure.flexibility"),
                ExerciseStep("Posture de l'enfant", "Fesses vers les talons, bras allongés, front au sol ou sur un coussin.", seconds: 120, symbol: "figure.yoga"),
                ExerciseStep("Torsion allongée", "Sur le dos, genoux pliés, laisse-les tomber d'un côté puis de l'autre.", seconds: 120, symbol: "figure.mind.and.body"),
                ExerciseStep("Relaxation", "Allongé sur le dos, bras le long du corps, respire calmement.", seconds: 150, symbol: "bed.double")
            ],
            benefits: "Le yoga doux associe mouvement et respiration lente, ce qui aide à se détendre.",
            hairNote: "Contrairement à une idée répandue, les postures tête en bas n'ont aucun effet démontré sur les cheveux. " + generalHairNote,
            precautions: ["Utilise un tapis ou une surface confortable.", "Reste dans une amplitude sans douleur."],
            contraindications: ["Grossesse, problème de tension artérielle ou de dos : demande l'avis d'un professionnel de santé avant de pratiquer."],
            evidence: .generalHealthOnly, sourceIDs: ["zaccaro-2018-breathing"], habitTemplateID: nil),

        Exercise(
            id: "relaxation-progressive", title: "Relaxation musculaire progressive", category: .relaxation, level: .gentle,
            summary: "Contracter puis relâcher chaque groupe de muscles pour ressentir la détente.",
            steps: [
                ExerciseStep("Installation", "Assis ou allongé, ferme les yeux et respire lentement.", seconds: 60, symbol: "figure.mind.and.body"),
                ExerciseStep("Mains et bras", "Serre les poings 5 secondes, puis relâche complètement. Recommence.", seconds: 90, symbol: "hand.raised"),
                ExerciseStep("Épaules", "Monte les épaules vers les oreilles, tiens 5 secondes, puis relâche.", seconds: 90, symbol: "figure.arms.open"),
                ExerciseStep("Visage", "Plisse le front et ferme fort les yeux, puis relâche tout le visage.", seconds: 90, symbol: "face.smiling"),
                ExerciseStep("Ventre", "Contracte le ventre 5 secondes, puis relâche en expirant.", seconds: 90, symbol: "figure.core.training"),
                ExerciseStep("Jambes et pieds", "Tends les jambes et ramène les orteils vers toi, puis relâche.", seconds: 90, symbol: "figure.cooldown"),
                ExerciseStep("Détente globale", "Ressens le corps entier relâché et respire calmement.", seconds: 90, symbol: "bed.double")
            ],
            benefits: "Un exercice simple pour prendre un moment de calme et relâcher les tensions ressenties.",
            hairNote: "Un stress intense peut déclencher une chute temporaire. Se détendre aide à mieux vivre le stress, sans effet démontré sur les cheveux.",
            precautions: ["Contracte sans forcer, jamais jusqu'à la douleur.", "Arrête en cas de crampe."],
            contraindications: ["Douleurs musculaires ou articulaires importantes : adapte ou évite l'exercice."],
            evidence: .insufficient, sourceIDs: [], habitTemplateID: nil),

        Exercise(
            id: "pause-active-bureau", title: "Pause active au bureau", category: .mobility, level: .gentle,
            summary: "Cinq minutes pour interrompre une longue période assise.",
            steps: [
                ExerciseStep("Debout", "Lève-toi et marche quelques pas.", seconds: 60, symbol: "figure.walk"),
                ExerciseStep("Épaules", "Cercles lents des épaules vers l'arrière.", seconds: 45, symbol: "figure.arms.open"),
                ExerciseStep("Dos", "Mains sur les hanches, redresse-toi et étire doucement le dos.", seconds: 45, symbol: "figure.stand"),
                ExerciseStep("Mollets", "Monte sur la pointe des pieds puis redescends lentement.", seconds: 60, symbol: "figure.step.training"),
                ExerciseStep("Respiration", "Inspire 5 secondes, expire 5 secondes.", seconds: 90, symbol: "wind")
            ],
            benefits: "L'OMS recommande de limiter le temps passé assis et de le remplacer par une activité, même légère.",
            hairNote: generalHairNote,
            precautions: ["Garde un appui à proximité si tu manques d'équilibre."],
            contraindications: [],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: nil)
    ]

    public static func exercise(id: String) -> Exercise? { all.first { $0.id == id } }
}
