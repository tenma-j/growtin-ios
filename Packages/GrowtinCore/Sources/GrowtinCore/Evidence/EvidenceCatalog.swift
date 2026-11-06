import Foundation

/// Fiches de preuve rédigées à partir de la base documentaire vérifiée.
/// Règle éditoriale : chaque fiche distingue le bénéfice général et l'effet capillaire, et n'affirme jamais une repousse.
public enum EvidenceCatalog {
    public static let proteinAtMeals = EvidenceCard(
        id: "protein-at-meals",
        title: "Une source de protéines à chaque repas",
        category: .nutrition,
        explanation: "Le cheveu est principalement constitué de kératine, une protéine. Des apports protéiques insuffisants et prolongés font partie des causes nutritionnelles de chute décrites dans la littérature.",
        expectedBenefit: "Couvrir tes besoins protéiques de référence et éviter un déficit.",
        evidence: .moderate,
        limits: "Chez une personne sans déficit, manger davantage de protéines n'a pas montré d'effet sur la chute ni sur l'alopécie androgénétique.",
        sourceIDs: ["guo-katta-2017-diet", "efsa-protein-drv"]
    )

    public static let ironAndVitaminC = EvidenceCard(
        id: "iron-vitamin-c",
        title: "Associer fer et vitamine C",
        category: .nutrition,
        explanation: "Le fer non héminique (légumineuses, céréales, légumes verts) est mieux absorbé avec une source de vitamine C. Une carence en fer est fréquemment étudiée en lien avec certaines chutes diffuses.",
        expectedBenefit: "Couvrir tes apports en fer, en particulier avec une alimentation sans viande.",
        evidence: .limited,
        limits: "Le lien entre fer bas sans anémie et chute de cheveux reste débattu. Une supplémentation ne doit se faire qu'après une prise de sang et sur avis médical : un excès de fer est nocif.",
        sourceIDs: ["trost-2006-iron", "almohanna-2019-vitamins"]
    )

    public static let zincSeleniumFoods = EvidenceCard(
        id: "zinc-selenium-foods",
        title: "Zinc et sélénium par l'alimentation",
        category: .nutrition,
        explanation: "Le zinc et le sélénium contribuent au maintien de cheveux normaux (allégations autorisées dans l'Union européenne). On les trouve dans les graines, les fruits de mer, les œufs, les légumineuses et le poisson.",
        expectedBenefit: "Atteindre tes apports de référence sans compléments.",
        evidence: .limited,
        limits: "Aucun bénéfice démontré chez une personne sans carence. Un excès de sélénium, notamment via les compléments ou une consommation excessive de noix du Brésil, peut lui-même provoquer une chute de cheveux.",
        sourceIDs: ["eu-432-2012", "almohanna-2019-vitamins", "macfarquhar-2010-selenium"]
    )

    public static let noUnprescribedSupplements = EvidenceCard(
        id: "no-unprescribed-supplements",
        title: "Pas de compléments à haute dose sans avis médical",
        category: .nutrition,
        explanation: "Les compléments « spécial cheveux » contiennent souvent de fortes doses de biotine, de zinc ou de sélénium.",
        expectedBenefit: "Éviter des effets indésirables et des résultats d'analyses faussés.",
        evidence: .moderate,
        limits: "La biotine n'a pas montré de bénéfice sans carence et peut fausser certains dosages biologiques (dont la thyroïde et la troponine).",
        sourceIDs: ["patel-2017-biotin", "macfarquhar-2010-selenium", "guo-katta-2017-diet"]
    )

    public static let regularSleep = EvidenceCard(
        id: "regular-sleep",
        title: "Un horaire de coucher régulier",
        category: .sleep,
        explanation: "Les sociétés savantes du sommeil recommandent au moins 7 heures de sommeil par nuit chez l'adulte. Un horaire régulier aide à les atteindre.",
        expectedBenefit: "Meilleure récupération et meilleur bien-être général.",
        evidence: .generalHealthOnly,
        limits: "Améliorer son sommeil ne constitue pas un traitement démontré de l'alopécie androgénétique.",
        sourceIDs: ["watson-2015-sleep"]
    )

    public static let slowBreathing = EvidenceCard(
        id: "slow-breathing",
        title: "Respiration lente guidée",
        category: .stress,
        explanation: "Ralentir sa respiration (autour de 6 cycles par minute) est associé à une réduction du stress ressenti et à des effets sur le système nerveux autonome. Un stress important fait partie des déclencheurs connus de l'effluvium télogène, une chute temporaire.",
        expectedBenefit: "Un moment de détente et une meilleure gestion du stress perçu.",
        evidence: .generalHealthOnly,
        limits: "Aucune étude ne montre qu'un exercice de respiration réduit la chute de cheveux ou ralentit une alopécie androgénétique.",
        sourceIDs: ["zaccaro-2018-breathing", "telogen-effluvium-review"]
    )

    public static let dailyWalk = EvidenceCard(
        id: "daily-walk",
        title: "Bouger chaque jour",
        category: .activity,
        explanation: "L'OMS recommande 150 à 300 minutes d'activité modérée par semaine chez l'adulte, soit environ 20 à 40 minutes par jour.",
        expectedBenefit: "Bénéfices démontrés sur la santé cardiovasculaire, le sommeil, l'humeur et le stress.",
        evidence: .generalHealthOnly,
        limits: "L'activité physique n'a pas d'effet démontré sur la repousse ou la densité des cheveux.",
        sourceIDs: ["who-2020-activity"]
    )

    public static let scalpMassage = EvidenceCard(
        id: "scalp-massage",
        title: "Massage du cuir chevelu",
        category: .hairCare,
        explanation: "Une petite étude japonaise a observé une augmentation de l'épaisseur du cheveu après 24 semaines de massage quotidien standardisé de 4 minutes, réalisé avec un appareil.",
        expectedBenefit: "Un moment de détente. Un éventuel effet sur l'épaisseur du cheveu reste à confirmer.",
        evidence: .limited,
        limits: "L'étude ne portait que sur 9 hommes en bonne santé, sans groupe témoin, et ne mesurait ni la chute ni la repousse. Ce n'est pas un traitement de l'alopécie. Masse doucement et arrête en cas de douleur ou d'irritation.",
        sourceIDs: ["koyama-2016-massage"]
    )

    public static let looseHairstyles = EvidenceCard(
        id: "loose-hairstyles",
        title: "Des coiffures sans tension",
        category: .hairCare,
        explanation: "Les coiffures qui tirent sur les racines (queues-de-cheval serrées, tresses, extensions) peuvent provoquer une alopécie de traction, en particulier sur la ligne frontale et les tempes.",
        expectedBenefit: "Réduire le risque d'alopécie de traction, qui peut devenir définitive si la tension persiste.",
        evidence: .moderate,
        limits: "Cela prévient un type précis de chute. Cela n'a pas d'effet sur l'alopécie androgénétique.",
        sourceIDs: ["aad-traction-alopecia"]
    )

    public static let gentleHairCare = EvidenceCard(
        id: "gentle-hair-care",
        title: "Limiter la chaleur et les gestes agressifs",
        category: .hairCare,
        explanation: "La chaleur intense (lisseur, sèche-cheveux très chaud), le brossage énergique et certains traitements chimiques fragilisent la fibre et favorisent la casse.",
        expectedBenefit: "Moins de casse, des cheveux moins abîmés.",
        evidence: .moderate,
        limits: "La casse n'est pas une chute depuis la racine : cela n'agit pas sur l'alopécie androgénétique.",
        sourceIDs: ["aad-hair-care-habits"]
    )

    public static let prescribedTreatmentReminder = EvidenceCard(
        id: "prescribed-treatment-reminder",
        title: "Rappel de ton traitement prescrit",
        category: .medical,
        explanation: "Tu as indiqué suivre un traitement. Ce rappel t'aide simplement à respecter ce que ton médecin a prescrit.",
        expectedBenefit: "Une meilleure régularité, telle que définie avec ton médecin.",
        evidence: .strong,
        limits: "Growtin' ne recommande, ne dose et ne modifie aucun traitement. Pour toute question ou effet indésirable, contacte ton médecin ou ton pharmacien.",
        sourceIDs: ["kanti-2018-s3"]
    )

    public static let dailyCheckIn = EvidenceCard(
        id: "daily-check-in",
        title: "Bilan du jour",
        category: .tracking,
        explanation: "Noter ton sommeil, ton stress et tes observations en quelques secondes permet de repérer des tendances dans le temps et de préparer une éventuelle consultation.",
        expectedBenefit: "Un historique clair de tes habitudes.",
        evidence: .insufficient,
        limits: "Un journal est un outil d'observation : une association entre deux éléments ne prouve pas que l'un cause l'autre.",
        sourceIDs: []
    )

    public static let all: [EvidenceCard] = [
        proteinAtMeals, ironAndVitaminC, zincSeleniumFoods, noUnprescribedSupplements, regularSleep, slowBreathing,
        dailyWalk, scalpMassage, looseHairstyles, gentleHairCare, prescribedTreatmentReminder, dailyCheckIn
    ]

    public static func card(id: String) -> EvidenceCard? { all.first { $0.id == id } }
}
