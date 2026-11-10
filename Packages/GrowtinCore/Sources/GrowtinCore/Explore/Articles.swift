import Foundation

public enum ArticleCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case understand, causes, treatments, everyday

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .understand: "Comprendre"
        case .causes: "Causes et signes"
        case .treatments: "Traitements"
        case .everyday: "Au quotidien"
        }
    }

    public var symbol: String {
        switch self {
        case .understand: "book"
        case .causes: "magnifyingglass"
        case .treatments: "cross.case"
        case .everyday: "sun.max"
        }
    }
}

public struct ArticleSection: Codable, Hashable, Sendable {
    public let heading: String
    public let paragraphs: [String]

    public init(_ heading: String, _ paragraphs: [String]) {
        self.heading = heading
        self.paragraphs = paragraphs
    }
}

/// Article éducatif. Règles éditoriales : chaque affirmation de santé s'appuie sur une source de la base vérifiée,
/// aucun article ne prescrit, ne dose ni ne recommande d'arrêter un traitement.
public struct Article: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: ArticleCategory
    public let keyPoints: [String]
    public let sections: [ArticleSection]
    public let sourceIDs: [String]
    public let reviewedOn: String

    /// Temps de lecture estimé (200 mots par minute).
    public var readMinutes: Int {
        let words = (keyPoints + sections.flatMap { [$0.heading] + $0.paragraphs })
            .reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
        return max(1, Int((Double(words) / 200).rounded(.up)))
    }
}

public enum ArticleLibrary {
    static let reviewed = "2026-11-10"
    static let consult = "Ces informations sont éducatives. Pour un diagnostic ou un traitement, consulte un médecin ou un dermatologue."

    public static let all: [Article] = [
        Article(
            id: "cycle-du-cheveu", title: "Le cycle de vie du cheveu",
            subtitle: "Pourquoi perdre des cheveux chaque jour est normal, et pourquoi les changements se jugent sur plusieurs mois.",
            category: .understand,
            keyPoints: [
                "Chaque cheveu suit un cycle : une longue phase de croissance, une courte phase de transition, puis une phase de repos avant de tomber.",
                "Les cheveux ne sont pas tous dans la même phase : on en perd un peu chaque jour, et ils sont remplacés.",
                "Un changement visible prend des mois : c'est pour cela que Growtin' espace les photos de suivi."
            ],
            sections: [
                ArticleSection("Trois phases", [
                    "La phase anagène est la phase de croissance active. Elle peut durer plusieurs années et détermine en grande partie la longueur que peut atteindre un cheveu.",
                    "La phase catagène est une courte phase de transition pendant laquelle le follicule se rétracte.",
                    "La phase télogène est une phase de repos : le cheveu ne pousse plus, puis il tombe et laisse place à un nouveau cheveu."
                ]),
                ArticleSection("Ce que cela implique pour ton suivi", [
                    "Comme chaque cheveu a son propre rythme, une perte quotidienne de cheveux est normale.",
                    "Quand un événement perturbe le cycle (maladie, stress intense, accouchement), la chute qui en résulte apparaît souvent avec plusieurs semaines de décalage.",
                    "Comparer deux photos prises à quelques jours d'intervalle n'a donc pas de sens : les différences viennent surtout de la lumière et du coiffage."
                ])
            ],
            sourceIDs: ["hair-cycle-review", "telogen-effluvium-review"], reviewedOn: reviewed),

        Article(
            id: "alopecie-androgenetique", title: "L'alopécie androgénétique",
            subtitle: "La cause de chute la plus fréquente, chez les hommes comme chez les femmes.",
            category: .understand,
            keyPoints: [
                "C'est la cause la plus fréquente de perte de cheveux dans le monde, chez les hommes comme chez les femmes.",
                "Elle est héréditaire et progresse lentement, avec une sensibilité des follicules aux hormones androgènes.",
                "Il existe des traitements à l'efficacité démontrée : un dermatologue peut t'aider à choisir."
            ],
            sections: [
                ArticleSection("À quoi la reconnaître", [
                    "Chez l'homme, elle se manifeste souvent par un recul de la ligne frontale ou une zone plus clairsemée au sommet du crâne. L'échelle de Hamilton-Norwood décrit ces stades.",
                    "Chez la femme, elle prend plutôt la forme d'un affinement diffus et d'un élargissement de la raie, décrits par l'échelle de Ludwig.",
                    "Elle peut commencer dès l'adolescence, mais apparaît le plus souvent plus tard."
                ]),
                ArticleSection("Ce qui se passe", [
                    "Sous l'effet des androgènes et d'une prédisposition génétique, certains follicules produisent des cheveux de plus en plus fins et courts : on parle de miniaturisation.",
                    "Ce processus est lent et propre à chaque personne : l'hygiène de vie n'en est pas la cause, et ne permet pas de l'inverser à elle seule."
                ]),
                ArticleSection("Que faire", [
                    "Selon l'Académie américaine de dermatologie, un traitement fonctionne mieux lorsqu'il est commencé tôt.",
                    "Les recommandations européennes (guideline S3) aident les dermatologues à choisir un traitement efficace et sûr selon le sexe et la situation.",
                    consult
                ])
            ],
            sourceIDs: ["aad-aga", "kanti-2018-s3", "norwood-1975", "ludwig-1977"], reviewedOn: reviewed),

        Article(
            id: "effluvium-telogene", title: "La chute temporaire : l'effluvium télogène",
            subtitle: "Une chute diffuse, souvent brutale, mais généralement réversible.",
            category: .causes,
            keyPoints: [
                "Une chute diffuse peut survenir après un stress physique ou psychologique, une maladie, un changement hormonal ou certains médicaments.",
                "Après un accouchement, une chute plus importante est fréquente et généralement temporaire.",
                "Elle régresse en général une fois le déclencheur disparu : un médecin peut en rechercher l'origine."
            ],
            sections: [
                ArticleSection("Comment elle se manifeste", [
                    "De nombreux cheveux entrent en même temps en phase de repos, puis tombent : la chute est diffuse, sur l'ensemble du cuir chevelu, sans plaque.",
                    "Elle apparaît souvent quelques semaines après l'événement déclencheur, ce qui rend le lien difficile à faire."
                ]),
                ArticleSection("Après un accouchement", [
                    "La baisse des œstrogènes après la naissance provoque souvent une chute marquée. Selon l'Académie américaine de dermatologie, la plupart des femmes retrouvent une pousse normale vers le premier anniversaire de leur enfant."
                ]),
                ArticleSection("Quand consulter", [
                    "Une chute brutale ou qui se prolonge mérite un avis médical : le médecin peut rechercher une cause (carence, trouble thyroïdien, médicament) et proposer une prise de sang.",
                    consult
                ])
            ],
            sourceIDs: ["telogen-effluvium-review", "aad-postpartum", "nhs-hair-loss"], reviewedOn: reviewed),

        Article(
            id: "signes-a-faire-examiner", title: "Pelade et signes à faire examiner",
            subtitle: "Certaines chutes nécessitent un examen médical rapide.",
            category: .causes,
            keyPoints: [
                "Des plaques rondes ou ovales sans cheveux peuvent correspondre à une pelade, qui n'est pas contagieuse.",
                "Une chute soudaine, des plaques, une perte par touffes ou des démangeaisons et brûlures du cuir chevelu justifient une consultation.",
                "Growtin' ne pose aucun diagnostic : en cas de doute, consulte."
            ],
            sections: [
                ArticleSection("La pelade", [
                    "La pelade (alopecia areata) provoque une perte de cheveux, le plus souvent sur le cuir chevelu ou la barbe, qui commence en général par une plaque ronde ou ovale.",
                    "Elle peut débuter à tout âge. Les cheveux repoussent parfois spontanément, mais une plaque apparue brutalement doit être examinée par un dermatologue."
                ]),
                ArticleSection("Les signes qui doivent t'alerter", [
                    "Une chute soudaine ou par touffes.",
                    "Des plaques sans cheveux.",
                    "Des démangeaisons, une brûlure, des rougeurs ou des squames sur le cuir chevelu.",
                    "Une perte de sourcils, de cils ou de poils, ou d'autres symptômes associés comme une fatigue inhabituelle."
                ]),
                ArticleSection("Avant un centre capillaire", [
                    "Le service de santé britannique (NHS) conseille de voir d'abord un médecin avant de s'adresser à un centre capillaire commercial, et de lui dire si la chute affecte ton moral.",
                    consult
                ])
            ],
            sourceIDs: ["aad-alopecia-areata", "nhs-hair-loss"], reviewedOn: reviewed),

        Article(
            id: "alimentation-et-carences", title: "Alimentation, carences et compléments",
            subtitle: "Ce que l'alimentation peut faire, et ce qu'elle ne peut pas faire.",
            category: .everyday,
            keyPoints: [
                "Des carences (protéines, fer, zinc, certaines vitamines) font partie des causes de chute décrites dans la littérature.",
                "Chez une personne sans carence, les compléments « spécial cheveux » n'ont pas montré de bénéfice.",
                "Un excès de certains nutriments, comme le sélénium, peut lui-même provoquer une chute."
            ],
            sections: [
                ArticleSection("Les carences", [
                    "Un apport insuffisant et prolongé en protéines ou en certains micronutriments peut contribuer à une chute. Le fer est le plus étudié : son rôle en l'absence d'anémie reste débattu.",
                    "Seule une prise de sang, prescrite par un médecin, permet d'identifier une carence. C'est elle qui guide une éventuelle supplémentation."
                ]),
                ArticleSection("Les compléments", [
                    "La biotine est très présente dans les compléments capillaires. Les études ne montrent pas de bénéfice sans carence, et la biotine peut fausser certaines analyses de sang.",
                    "Le zinc, le sélénium et la biotine font l'objet d'allégations autorisées dans l'Union européenne (« contribue au maintien de cheveux normaux »). Cela ne signifie pas qu'ils traitent une alopécie.",
                    "Un épisode d'intoxication au sélénium par un complément mal dosé a provoqué des chutes de cheveux : plus n'est pas mieux."
                ]),
                ArticleSection("Au quotidien", [
                    "Une alimentation variée, avec une source de protéines à chaque repas, des légumineuses, des légumes, des fruits et des oléagineux, couvre les besoins de la plupart des personnes.",
                    "Les recettes de Growtin' indiquent leurs apports, sans jamais les présenter comme un traitement."
                ])
            ],
            sourceIDs: ["guo-katta-2017-diet", "almohanna-2019-vitamins", "trost-2006-iron", "patel-2017-biotin", "macfarquhar-2010-selenium", "eu-432-2012"],
            reviewedOn: reviewed),

        Article(
            id: "traitements-medicaux", title: "Les traitements médicaux validés",
            subtitle: "Minoxidil, finastéride : ce que disent les études. À discuter avec un médecin.",
            category: .treatments,
            keyPoints: [
                "Le minoxidil et le finastéride sont les traitements les mieux étudiés de l'alopécie androgénétique.",
                "Ils ont des effets indésirables possibles et des contre-indications : ils se discutent avec un médecin.",
                "Growtin' ne prescrit, ne dose et ne modifie aucun traitement."
            ],
            sections: [
                ArticleSection("Le minoxidil", [
                    "Le minoxidil en application locale a montré son efficacité chez l'homme et chez la femme dans des essais contrôlés.",
                    "Chez la femme, une revue Cochrane rapporte qu'environ deux fois plus de femmes constatent une repousse modérée à importante qu'avec un placebo, avec des preuves de qualité modérée."
                ]),
                ArticleSection("Le finastéride", [
                    "Chez l'homme, le finastéride améliore l'aspect des cheveux et le nombre de cheveux par rapport au placebo, selon une revue systématique de douze essais.",
                    "Cette même revue relève une augmentation des troubles de l'érection. Tout effet indésirable doit être signalé au médecin, sans arrêter ni modifier le traitement de soi-même."
                ]),
                ArticleSection("Choisir avec un professionnel", [
                    "Les recommandations européennes guident le choix du traitement selon le sexe, l'âge, le stade et les antécédents. Certains traitements sont déconseillés pendant la grossesse ou chez les femmes qui pourraient être enceintes.",
                    "Les effets d'un traitement s'évaluent sur plusieurs mois : la régularité compte, et un suivi médical est nécessaire.",
                    consult
                ])
            ],
            sourceIDs: ["minoxidil-review", "cochrane-2016-fphl", "mella-2010-finasteride", "kanti-2018-s3"], reviewedOn: reviewed),

        Article(
            id: "autres-approches", title: "Laser, PRP et autres approches",
            subtitle: "Des pistes étudiées, avec des preuves encore limitées.",
            category: .treatments,
            keyPoints: [
                "Le laser basse intensité a montré un effet sur la densité dans plusieurs essais, mais ces essais sont hétérogènes.",
                "Le PRP (plasma riche en plaquettes) repose sur de petits essais aux protocoles variés.",
                "Le massage du cuir chevelu n'a été étudié que sur un très petit nombre de personnes."
            ],
            sections: [
                ArticleSection("Le laser basse intensité", [
                    "Une méta-analyse d'essais en double aveugle rapporte une augmentation de la densité par rapport à des appareils factices. Les essais inclus sont toutefois hétérogènes.",
                    "Une méta-analyse en réseau le classe parmi les approches étudiées, en soulignant une qualité de preuve globalement faible."
                ]),
                ArticleSection("Le PRP", [
                    "Le PRP consiste à injecter dans le cuir chevelu un concentré préparé à partir du sang du patient. Une méta-analyse de neuf petits essais montre une augmentation de la densité, sans différence significative sur le nombre ni le diamètre des cheveux."
                ]),
                ArticleSection("Le massage du cuir chevelu", [
                    "Une étude japonaise a observé une augmentation de l'épaisseur du cheveu après 24 semaines de massage quotidien avec un appareil, chez seulement 9 hommes sans chute et sans groupe témoin. C'est un moment de détente, pas un traitement.",
                    consult
                ])
            ],
            sourceIDs: ["lllt-review", "prp-review", "gupta-2018-nma", "koyama-2016-massage"], reviewedOn: reviewed),

        Article(
            id: "soins-et-coiffures", title: "Soins et coiffures : ce qui abîme vraiment",
            subtitle: "Distinguer la casse de la chute, et éviter l'alopécie de traction.",
            category: .everyday,
            keyPoints: [
                "Les coiffures qui tirent sur les racines peuvent provoquer une alopécie de traction.",
                "La chaleur, le brossage excessif et les traitements chimiques rapprochés abîment la fibre.",
                "La casse n'est pas une chute depuis la racine : elle n'agit pas sur l'alopécie androgénétique."
            ],
            sections: [
                ArticleSection("L'alopécie de traction", [
                    "Une tension prolongée ou répétée sur les cheveux (queues-de-cheval serrées, tresses, extensions) peut provoquer une perte de cheveux, notamment sur la ligne frontale et les tempes. Elle peut devenir durable si la tension persiste.",
                    "Alterner les coiffures et attacher les cheveux sans serrer permet de la prévenir."
                ]),
                ArticleSection("Les gestes qui fragilisent", [
                    "Les cheveux n'ont pas besoin de cent coups de brosse par jour : brosse-les simplement pour les coiffer.",
                    "Espace les colorations, permanentes et lissages chimiques, et protège tes cheveux du soleil.",
                    "Si de meilleurs soins ne suffisent pas, l'Académie américaine de dermatologie conseille de consulter un dermatologue."
                ])
            ],
            sourceIDs: ["aad-traction-alopecia", "aad-hair-care-habits", "billero-miteva-2018-traction"], reviewedOn: reviewed),

        Article(
            id: "idees-recues", title: "Idées reçues",
            subtitle: "Ce que disent vraiment les sources.",
            category: .understand,
            keyPoints: [
                "Beaucoup de conseils répandus n'ont pas de preuve solide.",
                "Méfie-toi des promesses de repousse rapide ou garantie.",
                "En cas de doute, demande l'avis d'un dermatologue."
            ],
            sections: [
                ArticleSection("« La calvitie ne touche que les hommes »", [
                    "Faux. L'alopécie androgénétique touche aussi les femmes, souvent sous forme d'affinement diffus et d'élargissement de la raie."
                ]),
                ArticleSection("« Les compléments à la biotine font repousser les cheveux »", [
                    "Pas sans carence. Les études ne montrent pas de bénéfice chez les personnes qui ne manquent pas de biotine, et elle peut fausser certaines analyses."
                ]),
                ArticleSection("« Plus de vitamines et de minéraux, c'est mieux »", [
                    "Non. Un excès de sélénium, par exemple, peut lui-même provoquer une chute de cheveux."
                ]),
                ArticleSection("« Masser son cuir chevelu fait repousser les cheveux »", [
                    "Non démontré. La seule étude citée portait sur 9 hommes sans chute et mesurait l'épaisseur du cheveu, pas la repousse."
                ]),
                ArticleSection("« Il faut cent coups de brosse par jour »", [
                    "Faux. Brosser excessivement peut abîmer la fibre ; il suffit de brosser pour coiffer."
                ]),
                ArticleSection("« Le stress rend chauve »", [
                    "Nuancé. Un stress intense peut déclencher une chute temporaire (effluvium télogène), généralement réversible. Il ne provoque pas l'alopécie androgénétique."
                ])
            ],
            sourceIDs: ["aad-aga", "patel-2017-biotin", "macfarquhar-2010-selenium", "koyama-2016-massage", "aad-hair-care-habits", "telogen-effluvium-review"],
            reviewedOn: reviewed),

        Article(
            id: "sommeil-stress-activite", title: "Sommeil, stress et activité : ce qu'on sait",
            subtitle: "Des leviers utiles pour ton bien-être, à ne pas confondre avec un traitement.",
            category: .everyday,
            keyPoints: [
                "Les adultes ont besoin d'au moins 7 heures de sommeil par nuit pour leur santé.",
                "L'OMS recommande 150 à 300 minutes d'activité modérée par semaine.",
                "Un stress intense peut déclencher une chute temporaire, mais ces habitudes ne traitent pas l'alopécie androgénétique."
            ],
            sections: [
                ArticleSection("Le sommeil", [
                    "Selon le consensus des sociétés savantes américaines du sommeil, un adulte devrait dormir au moins 7 heures par nuit de façon régulière pour préserver sa santé."
                ]),
                ArticleSection("L'activité physique", [
                    "L'OMS recommande au moins 150 à 300 minutes d'activité d'intensité modérée par semaine, et de limiter le temps passé assis."
                ]),
                ArticleSection("Le stress", [
                    "Des techniques de respiration lente sont associées à une réduction du stress ressenti.",
                    "Un stress intense fait partie des déclencheurs de l'effluvium télogène, une chute temporaire. Mieux gérer son stress est bon pour le bien-être, sans effet démontré sur l'alopécie androgénétique."
                ])
            ],
            sourceIDs: ["watson-2015-sleep", "who-2020-activity", "zaccaro-2018-breathing", "telogen-effluvium-review"], reviewedOn: reviewed)
    ]

    public static func article(id: String) -> Article? { all.first { $0.id == id } }
}
