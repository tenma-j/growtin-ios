import Foundation

public enum ExerciseCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case walking, cardio, strength, mobility, stretching, yoga, relaxation, breathing, scalpMassage

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .walking: "Marche"
        case .cardio: "Cardio léger"
        case .strength: "Renforcement"
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
        case .strength: "figure.strengthtraining.traditional"
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
    /// Points de technique (posture, rythme, respiration) affichés sous la consigne.
    public let cues: [String]
    /// Mouvement joué par le personnage 3D (identifiant de motions.json).
    public let motion: String
    /// Zones du corps mises en avant pendant l'étape ; à défaut, celles du mouvement.
    public let focus: [String]?

    public init(_ title: String, _ instruction: String, seconds: Int, symbol: String, cues: [String] = [],
                motion: String = "breathe-stand", focus: [String]? = nil) {
        self.title = title
        self.instruction = instruction
        self.seconds = seconds
        self.symbol = symbol
        self.cues = cues
        self.motion = motion
        self.focus = focus
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
    public static let all: [Exercise] = [
        Exercise(
            id: "marche-active", title: "Marche active de 20 minutes", category: .walking, level: .beginner,
            summary: "Une marche à allure soutenue, encadrée par un échauffement et un retour au calme. La base la plus simple pour atteindre les repères d'activité de l'OMS.",
            steps: [
                ExerciseStep("Échauffement", "Marche à allure de promenade. Laisse les bras se balancer naturellement.", seconds: 180, symbol: "figure.walk",
                             cues: ["Épaules basses, regard à l'horizon.", "Respire par le nez si c'est confortable."], motion: "walk"),
                ExerciseStep("Marche soutenue", "Accélère jusqu'à respirer plus vite tout en pouvant encore parler, sans pouvoir chanter.", seconds: 840, symbol: "figure.walk.motion",
                             cues: ["Raccourcis un peu la foulée et augmente la cadence plutôt que d'allonger le pas.", "Plie les coudes à 90° et balance les bras d'avant en arrière.", "Pose le talon, déroule le pied, pousse avec les orteils."], motion: "walk-fast"),
                ExerciseStep("Retour au calme", "Ralentis progressivement jusqu'à l'allure du début.", seconds: 180, symbol: "figure.walk",
                             cues: ["Expire plus longtemps que tu n'inspires.", "Termine par 3 grandes respirations à l'arrêt."], motion: "walk")
            ],
            benefits: "L'OMS recommande 150 à 300 minutes d'activité modérée par semaine : 20 minutes par jour en font déjà 140. Elle améliore la santé cardiovasculaire, le sommeil et l'humeur.",
            hairNote: "La marche est un des meilleurs leviers pour le sommeil et la gestion du stress, deux sujets qui comptent quand on s'inquiète pour ses cheveux. Elle n'a pas d'effet démontré sur la repousse.",
            precautions: ["Porte des chaussures confortables et bois de l'eau s'il fait chaud.", "Arrête-toi en cas de douleur thoracique, de vertige ou d'essoufflement inhabituel."],
            contraindications: ["Douleur à la marche ou blessure récente aux membres inférieurs : demande l'avis d'un professionnel de santé."],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: HabitCatalog.walk.id),

        Exercise(
            id: "marche-fractionnee", title: "Marche fractionnée de 25 minutes", category: .walking, level: .beginner,
            summary: "Quatre fois 3 minutes rapides et 2 minutes tranquilles. Plus stimulant qu'une marche continue, sans courir.",
            steps: [
                ExerciseStep("Échauffement", "Marche tranquille.", seconds: 180, symbol: "figure.walk",
                             cues: ["Fais quelques cercles d'épaules en marchant."], motion: "walk"),
                ExerciseStep("Rapide n° 1", "Marche aussi vite que possible sans courir.", seconds: 180, symbol: "figure.walk.motion",
                             cues: ["Tu dois avoir du mal à faire une phrase complète.", "Bras pliés et dynamiques."], motion: "walk-fast"),
                ExerciseStep("Récupération", "Ralentis franchement.", seconds: 120, symbol: "figure.walk", cues: ["Laisse ta respiration redescendre."], motion: "walk"),
                ExerciseStep("Rapide n° 2", "Reprends l'allure rapide.", seconds: 180, symbol: "figure.walk.motion", motion: "walk-fast"),
                ExerciseStep("Récupération", "Allure tranquille.", seconds: 120, symbol: "figure.walk", motion: "walk"),
                ExerciseStep("Rapide n° 3", "Allure rapide, si possible dans une petite montée.", seconds: 180, symbol: "figure.walk.motion", motion: "walk-fast"),
                ExerciseStep("Récupération", "Allure tranquille.", seconds: 120, symbol: "figure.walk", motion: "walk"),
                ExerciseStep("Rapide n° 4", "Dernière accélération : garde une bonne posture jusqu'au bout.", seconds: 180, symbol: "figure.walk.motion", motion: "walk-fast"),
                ExerciseStep("Retour au calme", "Marche lentement.", seconds: 120, symbol: "figure.cooldown", cues: ["Expire lentement par la bouche."], motion: "walk")
            ],
            benefits: "Alterner des phases plus intenses permet d'atteindre plus facilement une intensité modérée à soutenue ; l'OMS rappelle que toute activité compte.",
            hairNote: "Bon choix si tu veux progresser après la marche simple. Le bénéfice porte sur la forme et le sommeil, pas directement sur les cheveux.",
            precautions: ["Reste à une intensité où tu ne te sens jamais mal.", "Évite les heures chaudes en été."],
            contraindications: ["Maladie cardiaque ou respiratoire, hypertension non suivie : demande l'avis de ton médecin avant les phases rapides."],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: HabitCatalog.walk.id),

        Exercise(
            id: "renforcement-poids-du-corps", title: "Renforcement au poids du corps", category: .strength, level: .beginner,
            summary: "Quinze minutes sans matériel, en 2 tours de 5 exercices. L'OMS recommande ce type de séance au moins 2 fois par semaine.",
            steps: [
                ExerciseStep("Échauffement", "Marche sur place et fais de grands cercles de bras.", seconds: 120, symbol: "figure.walk", motion: "warmup-march"),
                ExerciseStep("Squat sur chaise", "Assieds-toi lentement sur une chaise puis relève-toi sans t'aider des mains. 10 répétitions.", seconds: 60, symbol: "figure.strengthtraining.functional",
                             cues: ["Descends en 3 secondes, remonte en 1.", "Genoux dans l'axe des pieds.", "Pousse dans les talons."], motion: "chair-squat"),
                ExerciseStep("Pompes inclinées", "Mains sur le bord d'une table ou d'un plan de travail, corps gainé. Plie les coudes puis repousse. 8 à 10 répétitions.", seconds: 60, symbol: "figure.strengthtraining.traditional",
                             cues: ["Le corps forme une planche de la tête aux talons.", "Coudes à 45° du corps, pas à l'horizontale."], motion: "incline-pushup"),
                ExerciseStep("Pont fessier", "Allongé sur le dos, genoux pliés, monte le bassin en serrant les fessiers, tiens 2 secondes, redescends. 12 répétitions.", seconds: 60, symbol: "figure.core.training",
                             cues: ["Expire en montant.", "Ne cambre pas : arrête la montée quand les cuisses et le buste sont alignés."], motion: "glute-bridge"),
                ExerciseStep("Rowing serviette", "Debout, coince une serviette sous un pied et tire les deux extrémités vers ton ventre en serrant les omoplates. 12 répétitions.", seconds: 60, symbol: "figure.rower",
                             cues: ["Dos droit, poitrine ouverte.", "Imagine pincer un crayon entre les omoplates."], motion: "towel-row"),
                ExerciseStep("Gainage sur les genoux", "Sur les avant-bras et les genoux, aligne dos et cuisses, rentre légèrement le ventre.", seconds: 30, symbol: "figure.core.training",
                             cues: ["Respire normalement, ne bloque pas.", "Si c'est facile, passe sur les pieds."], motion: "knee-plank"),
                ExerciseStep("Pause", "Bois une gorgée d'eau, marche un peu.", seconds: 60, symbol: "drop", motion: "breathe-stand", focus: []),
                ExerciseStep("Tour 2 : squats", "10 squats sur chaise.", seconds: 60, symbol: "figure.strengthtraining.functional", motion: "chair-squat"),
                ExerciseStep("Tour 2 : pompes", "8 à 10 pompes inclinées.", seconds: 60, symbol: "figure.strengthtraining.traditional", motion: "incline-pushup"),
                ExerciseStep("Tour 2 : pont", "12 ponts fessiers.", seconds: 60, symbol: "figure.core.training", motion: "glute-bridge"),
                ExerciseStep("Tour 2 : rowing", "12 rowings serviette.", seconds: 60, symbol: "figure.rower", motion: "towel-row"),
                ExerciseStep("Tour 2 : gainage", "Gainage sur les genoux.", seconds: 30, symbol: "figure.core.training", motion: "knee-plank"),
                ExerciseStep("Retour au calme", "Étire doucement les cuisses et la poitrine, respire lentement.", seconds: 120, symbol: "figure.cooldown", motion: "cooldown-stretch")
            ],
            benefits: "Le renforcement musculaire 2 fois par semaine fait partie des recommandations de l'OMS : il entretient la masse musculaire, l'équilibre et la santé métabolique.",
            hairNote: "Aucun lien démontré entre musculation au poids du corps et chute de cheveux. Si tu prends des compléments « pour sportifs », parles-en à ton médecin : certains contiennent des substances à éviter.",
            precautions: ["Le mouvement doit rester contrôlé, sans à-coups.", "Une gêne musculaire est normale, une douleur articulaire ne l'est pas : arrête."],
            contraindications: ["Douleur articulaire, opération récente ou grossesse : demande l'avis d'un professionnel de santé."],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: nil),

        Exercise(
            id: "cardio-leger", title: "Cardio doux sans sauts", category: .cardio, level: .beginner,
            summary: "Dix minutes de mouvements simples dans le salon, sans sauts ni matériel, pour faire monter le cœur en douceur.",
            steps: [
                ExerciseStep("Marche sur place", "Lève les genoux à hauteur confortable et balance les bras.", seconds: 120, symbol: "figure.walk", motion: "march"),
                ExerciseStep("Pas chassés", "Deux pas à droite, deux pas à gauche, genoux légèrement fléchis.", seconds: 60, symbol: "figure.step.training",
                             cues: ["Reste léger sur les pieds.", "Ajoute les bras en ouvrant et fermant."], motion: "side-steps"),
                ExerciseStep("Montées de genoux", "Alterne les genoux devant toi, dos droit, sans sauter.", seconds: 60, symbol: "figure.highintensity.intervaltraining",
                             cues: ["Touche le genou avec la main opposée pour travailler la coordination."], motion: "high-knees"),
                ExerciseStep("Récupération", "Marche sur place lentement.", seconds: 60, symbol: "figure.walk", motion: "walk"),
                ExerciseStep("Squats partiels", "Plie les genoux comme pour t'asseoir, puis remonte en levant les bras.", seconds: 60, symbol: "figure.strengthtraining.functional",
                             cues: ["Rythme : 2 secondes pour descendre, 2 pour monter."], motion: "half-squat-arms"),
                ExerciseStep("Boxe dans le vide", "Genoux souples, envoie des coups de poing alternés devant toi.", seconds: 60, symbol: "figure.boxing",
                             cues: ["Expire à chaque coup.", "Ne tends pas complètement les coudes."], motion: "shadow-boxing"),
                ExerciseStep("Montées de genoux", "Alterne les genoux, respiration régulière.", seconds: 60, symbol: "figure.highintensity.intervaltraining", motion: "high-knees"),
                ExerciseStep("Retour au calme", "Marche lentement, puis respire profondément.", seconds: 120, symbol: "figure.cooldown", motion: "walk")
            ],
            benefits: "Une activité modérée régulière contribue à la santé cardiovasculaire et au bien-être, et peut se pratiquer par tous les temps.",
            hairNote: "Une alternative à la marche les jours de pluie. Effet sur la forme et l'humeur, pas sur les cheveux.",
            precautions: ["Adapte l'intensité : tu dois pouvoir parler.", "Arrête en cas de douleur ou de malaise."],
            contraindications: ["Problème cardiaque, articulaire ou grossesse : demande d'abord l'avis de ton médecin."],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: nil),

        Exercise(
            id: "mobilite-matin", title: "Mobilité du matin", category: .mobility, level: .gentle,
            summary: "Huit minutes pour délier les épaules, le dos et les hanches au réveil.",
            steps: [
                ExerciseStep("Épaules", "Fais de grands cercles lents avec les épaules : 10 vers l'arrière, 10 vers l'avant.", seconds: 60, symbol: "figure.arms.open", motion: "shoulder-rolls"),
                ExerciseStep("Nuque", "Incline l'oreille vers l'épaule, 3 respirations de chaque côté, sans forcer ni faire de cercles complets.", seconds: 60, symbol: "figure.mind.and.body", motion: "neck-tilt"),
                ExerciseStep("Chat-vache", "À quatre pattes, arrondis le dos en expirant puis creuse-le en inspirant.", seconds: 90, symbol: "figure.flexibility",
                             cues: ["Commence le mouvement par le bassin, laisse la tête suivre.", "Une respiration complète par mouvement."], motion: "cat-cow"),
                ExerciseStep("Hanches", "Debout, mains sur les hanches, fais 8 cercles lents du bassin dans chaque sens.", seconds: 60, symbol: "figure.cooldown", motion: "hip-circles"),
                ExerciseStep("Fentes douces", "Avance un pied, plie légèrement les deux genoux, reviens. Alterne.", seconds: 90, symbol: "figure.strengthtraining.functional",
                             cues: ["Le genou avant reste au-dessus de la cheville."], motion: "gentle-lunge"),
                ExerciseStep("Chevilles", "Une main contre un mur, fais 10 cercles avec chaque cheville.", seconds: 60, symbol: "figure.stand", motion: "ankle-circles"),
                ExerciseStep("Grand étirement", "Monte les bras au-dessus de la tête et grandis-toi en respirant, puis penche-toi doucement à droite et à gauche.", seconds: 60, symbol: "figure.arms.open", motion: "overhead-stretch")
            ],
            benefits: "Des mouvements doux et réguliers aident à se sentir moins raide et à démarrer la journée en douceur.",
            hairNote: "Idéal à associer à ta photo de suivi ou à ton bilan du matin, pour ancrer une routine. Aucun effet direct sur les cheveux.",
            precautions: ["Mouvements lents, dans une amplitude confortable.", "Ne force jamais sur la nuque."],
            contraindications: ["Douleur cervicale ou lombaire importante : demande l'avis d'un kinésithérapeute ou d'un médecin."],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: nil),

        Exercise(
            id: "nuque-epaules", title: "Nuque et épaules détendues", category: .stretching, level: .gentle,
            summary: "Six minutes pour relâcher les tensions qui s'accumulent dans le haut du dos quand on est stressé ou longtemps devant un écran.",
            steps: [
                ExerciseStep("Haussements", "Monte les épaules vers les oreilles en inspirant, tiens 3 secondes, laisse-les tomber en expirant. 8 fois.", seconds: 60, symbol: "figure.arms.open", motion: "shrugs"),
                ExerciseStep("Rentrer le menton", "Recule le menton comme pour faire un double menton, tiens 3 secondes. 10 fois.", seconds: 60, symbol: "figure.stand",
                             cues: ["Le regard reste horizontal.", "Tu dois sentir un allongement à l'arrière de la nuque."], motion: "chin-tucks"),
                ExerciseStep("Étirement du trapèze", "Main droite sur la tête, incline doucement l'oreille droite vers l'épaule, épaule gauche basse. 30 secondes de chaque côté.", seconds: 75, symbol: "figure.mind.and.body",
                             cues: ["La main pèse, elle ne tire pas."], motion: "trap-stretch"),
                ExerciseStep("Ouverture de poitrine", "Dans l'encadrement d'une porte, avant-bras sur les montants, avance doucement le buste.", seconds: 60, symbol: "figure.arms.open", motion: "doorway-stretch"),
                ExerciseStep("Omoplates", "Bras le long du corps, serre les omoplates l'une vers l'autre 5 secondes, relâche. 8 fois.", seconds: 60, symbol: "figure.rower", motion: "scapular-squeeze"),
                ExerciseStep("Respiration", "Mains sur le bas des côtes, inspire 4 secondes en écartant les côtes, expire 6 secondes.", seconds: 45, symbol: "wind", motion: "rib-breathing")
            ],
            benefits: "Des pauses d'étirement et de mobilité aident à réduire la sensation de raideur et à faire une coupure.",
            hairNote: "Les tensions de la nuque n'abîment pas les cheveux. En revanche, si tu portes souvent des coiffures serrées, desserrer ta coiffure compte davantage pour ton cuir chevelu.",
            precautions: ["Aucun étirement ne doit déclencher de fourmillements dans les bras : arrête si c'est le cas."],
            contraindications: ["Douleur cervicale aiguë, traumatisme récent : demande l'avis d'un médecin ou d'un kinésithérapeute."],
            evidence: .insufficient, sourceIDs: ["aad-traction-alopecia"], habitTemplateID: nil),

        Exercise(
            id: "etirements-soir", title: "Étirements du soir", category: .stretching, level: .gentle,
            summary: "Dix minutes d'étirements lents, assis au bord du lit puis allongé, pour signaler au corps que la journée est terminée.",
            steps: [
                ExerciseStep("Respiration d'arrivée", "Assis au bord du lit, pieds à plat au sol, mains sur les cuisses. 5 respirations lentes, l'expiration plus longue que l'inspiration.", seconds: 60, symbol: "wind", motion: "bed-sit-breathe"),
                ExerciseStep("Nuque et épaules", "Toujours assis, incline la tête d'un côté puis de l'autre, en laissant l'épaule opposée descendre.", seconds: 90, symbol: "figure.mind.and.body",
                             cues: ["Pas de cercles complets avec la tête."], motion: "bed-neck"),
                ExerciseStep("Arrière des cuisses", "Au bord du lit, tends une jambe devant toi, talon au sol, pointe vers le haut. Penche le buste en avant, dos long, jusqu'à sentir l'étirement derrière la cuisse. 30 secondes, puis change de jambe.", seconds: 90, symbol: "figure.flexibility",
                             cues: ["Le mouvement part des hanches : le dos reste droit."], motion: "bed-hamstring"),
                ExerciseStep("Hanches", "Assis au bord du lit, pose la cheville droite sur le genou gauche, genou droit vers l'extérieur. Dos long, penche-toi légèrement en avant. 30 secondes, puis change de côté.", seconds: 90, symbol: "figure.cooldown",
                             cues: ["Tu dois sentir l'étirement dans la fesse, jamais dans le genou."], motion: "bed-figure4"),
                ExerciseStep("Torsion allongée", "Allongé sur le lit, genoux pliés, laisse-les tomber d'un côté, regard de l'autre. Change de côté.", seconds: 120, symbol: "figure.mind.and.body",
                             cues: ["Les épaules restent posées sur le matelas."], motion: "bed-twist"),
                ExerciseStep("Genoux vers la poitrine", "Sur le dos, ramène les genoux vers la poitrine, mains posées sur les genoux. Respire calmement en relâchant le bas du dos.", seconds: 120, symbol: "bed.double",
                             cues: ["Ferme les yeux.", "Laisse le poids de la tête dans l'oreiller."], motion: "bed-knees-chest")
            ],
            benefits: "Un moment calme et régulier avant le coucher fait partie des conseils d'hygiène du sommeil ; 7 heures ou plus par nuit sont recommandées chez l'adulte.",
            hairNote: "Mieux dormir est bénéfique pour ta santé générale et ton humeur ; aucun effet direct sur la repousse n'est démontré.",
            precautions: ["Un étirement ne doit jamais faire mal.", "Respire calmement, sans bloquer la respiration."],
            contraindications: ["Blessure récente ou opération : demande l'avis d'un professionnel de santé."],
            evidence: .generalHealthOnly, sourceIDs: ["watson-2015-sleep"], habitTemplateID: HabitCatalog.windDown.id),

        Exercise(
            id: "scan-corporel", title: "Scan corporel pour s'endormir", category: .relaxation, level: .gentle,
            summary: "Dix minutes, allongé dans ton lit, pour poser ton attention sur chaque partie du corps et laisser venir le sommeil.",
            steps: [
                ExerciseStep("Installation", "Allonge-toi sur le dos dans ton lit, tête sur l'oreiller, lumière éteinte, bras le long du corps.", seconds: 60, symbol: "bed.double", cues: ["Baisse la luminosité de l'écran au minimum."], motion: "bed-rest", focus: []),
                ExerciseStep("Respiration", "Inspire par le nez 4 secondes, expire par la bouche 6 secondes.", seconds: 90, symbol: "wind", motion: "bed-rest", focus: ["chest", "abs"]),
                ExerciseStep("Pieds et jambes", "Porte ton attention sur tes pieds, puis tes mollets, tes genoux, tes cuisses. Remarque le poids, la chaleur, sans rien changer.", seconds: 120, symbol: "figure.cooldown", motion: "bed-rest", focus: ["feet", "calves", "shins", "quads", "hamstrings"]),
                ExerciseStep("Ventre et poitrine", "Sens le ventre se soulever et redescendre. Laisse la respiration se faire seule.", seconds: 90, symbol: "figure.mind.and.body", motion: "bed-rest", focus: ["abs", "chest"]),
                ExerciseStep("Mains, bras, épaules", "Desserre les mains, relâche les coudes, laisse les épaules s'enfoncer dans le matelas.", seconds: 90, symbol: "hand.raised", motion: "bed-rest", focus: ["hands", "forearms", "biceps", "triceps", "shoulders"]),
                ExerciseStep("Visage", "Relâche la mâchoire, la langue, le front, l'espace entre les sourcils.", seconds: 75, symbol: "face.smiling",
                             cues: ["Les dents ne se touchent pas."], motion: "bed-rest", focus: ["head", "neck"]),
                ExerciseStep("Corps entier", "Sens le corps entier, lourd et posé. Si une pensée arrive, reviens simplement à la respiration.", seconds: 75, symbol: "moon.zzz", motion: "bed-rest", focus: [])
            ],
            benefits: "Les techniques de relaxation font partie des approches proposées pour mieux s'endormir ; viser au moins 7 heures de sommeil régulier est recommandé chez l'adulte.",
            hairNote: "Tu ne retrouves pas le sommeil en surveillant tes cheveux le soir : laisse le suivi photo au matin, et garde le soir pour décrocher.",
            precautions: ["Si l'exercice fait remonter de l'anxiété, ouvre les yeux et arrête-le : c'est normal."],
            contraindications: ["Insomnie qui dure plus de trois mois ou fatigue importante en journée : parles-en à un médecin."],
            evidence: .generalHealthOnly, sourceIDs: ["watson-2015-sleep"], habitTemplateID: HabitCatalog.windDown.id),

        Exercise(
            id: "yoga-doux", title: "Yoga doux", category: .yoga, level: .gentle,
            summary: "Douze minutes de postures simples rythmées par une respiration lente, accessibles aux débutants.",
            steps: [
                ExerciseStep("Posture de la montagne", "Debout sur le tapis, pieds parallèles largeur de bassin, épaules relâchées, paumes légèrement tournées vers l'avant. 5 respirations profondes.", seconds: 60, symbol: "figure.stand",
                             cues: ["Grandis-toi par le sommet du crâne, le poids réparti sur les deux pieds."], motion: "mountain"),
                ExerciseStep("Salutation des bras", "Inspire en levant les bras devant toi jusqu'au-dessus de la tête, paumes jointes ; expire en les redescendant. 6 fois.", seconds: 90, symbol: "figure.arms.open",
                             cues: ["Le mouvement dure le temps de la respiration, ni plus ni moins.", "Épaules loin des oreilles."], motion: "arm-raise"),
                ExerciseStep("Flexion avant douce", "Penche-toi vers l'avant, genoux fléchis, tête et bras relâchés. Remonte lentement en déroulant le dos.", seconds: 60, symbol: "figure.flexibility",
                             cues: ["Plie les genoux autant que nécessaire : le dos reste détendu."], motion: "forward-fold"),
                ExerciseStep("Guerrier II", "Écarte largement les pieds, tourne le pied gauche vers l'extérieur et plie le genou gauche au-dessus de la cheville. Bras à l'horizontale, regard au-dessus de la main avant. 3 respirations, puis change de côté.", seconds: 90, symbol: "figure.yoga",
                             cues: ["Le genou avant reste dans l'axe du pied, jamais au-delà des orteils.", "Jambe arrière tendue, pied arrière bien ancré au sol."], motion: "warrior-two"),
                ExerciseStep("Posture de l'arbre", "En équilibre sur la jambe gauche, pose la plante du pied droit contre l'intérieur du mollet ou de la cuisse, jamais sur le genou. Mains jointes devant la poitrine, puis bras au-dessus de la tête. Change de côté.", seconds: 90, symbol: "figure.yoga",
                             cues: ["Fixe un point devant toi pour garder l'équilibre.", "Si tu vacilles, garde la pointe du pied au sol contre la cheville."], motion: "tree-pose"),
                ExerciseStep("Chat-vache", "À quatre pattes, mains sous les épaules et genoux sous les hanches : arrondis le dos en expirant, puis creuse-le en inspirant.", seconds: 90, symbol: "figure.flexibility",
                             cues: ["Le mouvement part du bassin et se propage jusqu'à la tête."], motion: "cat-cow"),
                ExerciseStep("Posture de l'enfant", "Fesses vers les talons, bras allongés devant toi, front au sol ou sur un coussin.", seconds: 90, symbol: "figure.yoga",
                             cues: ["Respire dans le dos : sens les côtes s'écarter."], motion: "child-pose"),
                ExerciseStep("Méditation assise", "Assis en tailleur, dos droit, mains posées sur les genoux paumes vers le ciel. Respire lentement, l'expiration un peu plus longue que l'inspiration.", seconds: 120, symbol: "figure.mind.and.body",
                             cues: ["Assieds-toi sur un coussin si le dos s'arrondit."], motion: "seated-breathe")
            ],
            benefits: "Le yoga doux associe mouvement et respiration lente ; les respirations lentes sont associées à une sensation de calme et de détente.",
            hairNote: "Contrairement à une idée répandue, les postures tête en bas n'ont aucun effet démontré sur les cheveux. Le bénéfice attendu ici concerne le stress.",
            precautions: ["Utilise un tapis ou une surface confortable.", "Reste dans une amplitude sans douleur.",
                          "Pour l'arbre, place-toi près d'un mur si l'équilibre est difficile."],
            contraindications: ["Grossesse, problème de tension artérielle ou de dos : demande l'avis d'un professionnel de santé avant de pratiquer."],
            evidence: .generalHealthOnly, sourceIDs: ["zaccaro-2018-breathing"], habitTemplateID: nil),

        Exercise(
            id: "relaxation-progressive", title: "Relaxation musculaire progressive", category: .relaxation, level: .gentle,
            summary: "Contracter 5 secondes, relâcher 10 secondes, groupe de muscles par groupe de muscles, pour sentir la différence entre tension et détente.",
            steps: [
                ExerciseStep("Installation", "Assis ou allongé, ferme les yeux et respire lentement.", seconds: 60, symbol: "figure.mind.and.body", motion: "chair-breathe", focus: []),
                ExerciseStep("Mains et bras", "Serre les poings et contracte les bras 5 secondes, puis relâche d'un coup et observe pendant 10 secondes. Deux fois.", seconds: 90, symbol: "hand.raised",
                             cues: ["Contracte à environ 70 % de ta force, pas au maximum."], motion: "fists-clench"),
                ExerciseStep("Épaules", "Monte les épaules vers les oreilles, tiens 5 secondes, puis laisse-les tomber.", seconds: 90, symbol: "figure.arms.open", motion: "chair-shrugs"),
                ExerciseStep("Visage", "Plisse le front, ferme fort les yeux, serre les lèvres, puis relâche tout le visage.", seconds: 90, symbol: "face.smiling", motion: "chair-breathe", focus: ["head", "neck"]),
                ExerciseStep("Ventre", "Contracte le ventre 5 secondes, puis relâche en expirant longuement.", seconds: 90, symbol: "figure.core.training", motion: "abs-contract"),
                ExerciseStep("Jambes et pieds", "Tends les jambes et ramène les orteils vers toi, puis relâche.", seconds: 90, symbol: "figure.cooldown", motion: "legs-tense"),
                ExerciseStep("Détente globale", "Parcours le corps : s'il reste une zone tendue, contracte-la une dernière fois puis relâche.", seconds: 90, symbol: "bed.double", motion: "chair-breathe", focus: [])
            ],
            benefits: "Un exercice simple pour faire une vraie pause et relâcher les tensions ressenties, utilisable aussi au coucher.",
            hairNote: "Un stress intense peut déclencher une chute temporaire (effluvium télogène), souvent 2 à 3 mois après l'événement. Se détendre aide à mieux vivre le stress ; aucun effet direct sur les cheveux n'est démontré.",
            precautions: ["Contracte sans forcer, jamais jusqu'à la douleur.", "Arrête en cas de crampe."],
            contraindications: ["Douleurs musculaires ou articulaires importantes : adapte ou évite l'exercice."],
            evidence: .insufficient, sourceIDs: ["telogen-effluvium-review"], habitTemplateID: nil),

        Exercise(
            id: "pause-active-bureau", title: "Pause active au bureau", category: .mobility, level: .gentle,
            summary: "Cinq minutes, debout à côté de ton poste, pour couper une longue période assise. À refaire toutes les 1 à 2 heures.",
            steps: [
                ExerciseStep("Debout", "Lève-toi et marche quelques pas, va remplir ton verre d'eau.", seconds: 60, symbol: "figure.walk", motion: "walk"),
                ExerciseStep("Épaules", "10 cercles lents des épaules vers l'arrière.", seconds: 45, symbol: "figure.arms.open", motion: "shoulder-rolls"),
                ExerciseStep("Dos", "Mains sur les hanches, redresse-toi et regarde légèrement vers le plafond, puis arrondis le dos.", seconds: 45, symbol: "figure.stand", motion: "back-extension"),
                ExerciseStep("Mollets", "Monte sur la pointe des pieds en 1 seconde, redescends en 3 secondes. 15 fois.", seconds: 60, symbol: "figure.step.training", motion: "calf-raises"),
                ExerciseStep("Regard au loin", "Regarde un point éloigné par la fenêtre et respire : inspire 5 secondes, expire 5 secondes.", seconds: 90, symbol: "eye", motion: "look-far")
            ],
            benefits: "L'OMS recommande de limiter le temps passé assis et de le remplacer par une activité, même légère.",
            hairNote: "Un bon moment pour boire de l'eau et faire une vraie coupure. Aucun effet direct sur les cheveux.",
            precautions: ["Garde un appui à proximité si tu manques d'équilibre."],
            contraindications: [],
            evidence: .generalHealthOnly, sourceIDs: ["who-2020-activity"], habitTemplateID: nil)
    ]

    public static func exercise(id: String) -> Exercise? { all.first { $0.id == id } }
}

/// Une séance proposée, avec la raison qui la rend pertinente pour cette personne.
public struct ExerciseRecommendation: Hashable, Sendable, Identifiable {
    public let exercise: Exercise
    public let reason: String
    public var id: String { exercise.id }
}

/// Choisit les séances les plus utiles à partir du profil et des derniers bilans du jour.
public enum ExerciseRecommender {
    public static func recommend(profile: UserProfile, checkIns: [DailyCheckIn], today: DayKey, limit: Int = 3) -> [ExerciseRecommendation] {
        let recent = checkIns.filter { $0.day <= today && $0.day > today.adding(days: -7) }
        let stressValues = recent.compactMap(\.stress)
        let sleepValues = recent.compactMap(\.sleepHours)
        let averageStress = stressValues.isEmpty ? nil : Double(stressValues.reduce(0, +)) / Double(stressValues.count)
        let averageSleep = sleepValues.isEmpty ? nil : sleepValues.reduce(0, +) / Double(sleepValues.count)

        var picks: [(String, String, Int)] = []   // (id, raison, priorité)

        let stressed = (averageStress ?? 0) >= 3.5 || profile.stress >= .high || profile.goals.contains(.reduceStress)
        if stressed {
            let why = averageStress.map { "Ton stress moyen est de \(format($0))/5 sur tes derniers bilans" } ?? "Tu as indiqué un stress \(profile.stress.label.lowercased())"
            picks.append(("relaxation-progressive", "\(why) : cette séance aide à relâcher les tensions en 10 minutes.", 90))
            picks.append(("nuque-epaules", "Le stress se loge souvent dans la nuque et les épaules : 6 minutes pour les détendre.", 70))
        }

        let shortSleep = (averageSleep ?? profile.sleepHours) < 7
        if shortSleep || profile.sleepQuality == .poor || profile.goals.contains(.sleepBetter) {
            let hours = averageSleep ?? profile.sleepHours
            let why = hours < 7 ? "Tu dors environ \(format(hours)) h, en dessous des 7 h recommandées" : "Tu as indiqué un sommeil de qualité \(profile.sleepQuality.label.lowercased())"
            picks.append(("scan-corporel", "\(why) : un rituel au lit peut aider à décrocher.", 85))
            picks.append(("etirements-soir", "Un rituel calme chaque soir, à la même heure, aide à caler ton rythme de sommeil.", 60))
        }

        switch profile.activity {
        case .sedentary, .light:
            picks.append(("marche-active", "Tu as indiqué une activité \(profile.activity.label.lowercased()) : 20 minutes de marche par jour te rapprochent des 150 minutes hebdomadaires recommandées.", 80))
            picks.append(("pause-active-bureau", "Couper les longues périodes assises est recommandé, même par une activité légère.", 50))
        case .moderate, .active:
            picks.append(("renforcement-poids-du-corps", "Tu bouges déjà : l'OMS recommande d'y ajouter 2 séances de renforcement par semaine.", 75))
            picks.append(("marche-fractionnee", "Pour varier tes séances avec un peu plus d'intensité.", 40))
        }

        if picks.count < limit {
            picks.append(("mobilite-matin", "Huit minutes au réveil pour démarrer la journée en douceur.", 30))
            picks.append(("yoga-doux", "Mouvement et respiration lente, accessible aux débutants.", 20))
        }

        var seen = Set<String>()
        return picks.sorted { $0.2 > $1.2 }.compactMap { id, reason, _ in
            guard !seen.contains(id), let exercise = ExerciseLibrary.exercise(id: id) else { return nil }
            seen.insert(id)
            return ExerciseRecommendation(exercise: exercise, reason: reason)
        }.prefix(limit).map { $0 }
    }

    static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded).replacingOccurrences(of: ".", with: ",")
    }
}
