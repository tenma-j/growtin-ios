# Catalogue des ingrédients de Growtin'.
# clé: (nom affiché, code Ciqual 2020, nature, allergènes, rayon)
# nature : plant | dairy | egg | fish | shellfish | meat | honey
# allergènes : valeurs de DietaryRestriction (gluten, lactose, nuts, peanuts, eggs, fish, shellfish, soy, sesame)

FRUITS = "Fruits et légumes"
FRAIS = "Crèmerie et œufs"
EPICERIE = "Épicerie"
POISSON = "Poissonnerie"
BOUCHERIE = "Boucherie"
BOULANGERIE = "Boulangerie"
HERBES = "Herbes et épices"

INGREDIENTS = {
    # Œufs et produits laitiers
    "oeuf": ("Œuf", 22000, "egg", ["eggs"], FRAIS),
    "yaourt-grec": ("Yaourt à la grecque nature", 19860, "dairy", ["lactose"], FRAIS),
    "fromage-blanc": ("Fromage blanc nature 3 %", 19646, "dairy", ["lactose"], FRAIS),
    "lait": ("Lait demi-écrémé", 19041, "dairy", ["lactose"], FRAIS),
    "feta": ("Feta AOP", 12066, "dairy", ["lactose"], FRAIS),
    "parmesan": ("Parmesan", 12120, "dairy", ["lactose"], FRAIS),
    "beurre": ("Beurre doux", 16400, "dairy", ["lactose"], FRAIS),
    "boisson-amande": ("Boisson à l'amande non sucrée", 18107, "plant", ["nuts"], EPICERIE),
    "boisson-soja": ("Boisson au soja enrichie en calcium", 18901, "plant", ["soy"], EPICERIE),
    "tofu": ("Tofu nature", 20904, "plant", ["soy"], FRAIS),

    # Céréales, pains, féculents
    "flocons-avoine": ("Flocons d'avoine", 9311, "plant", ["gluten"], EPICERIE),
    "muesli": ("Muesli nature", 32004, "plant", ["gluten", "nuts"], EPICERIE),
    "pain-complet": ("Pain complet", 7110, "plant", ["gluten"], BOULANGERIE),
    "pain-seigle": ("Pain de seigle", 7125, "plant", ["gluten"], BOULANGERIE),
    "pates-completes": ("Pâtes complètes", 9870, "plant", ["gluten"], EPICERIE),
    "nouilles": ("Nouilles de blé", 9863, "plant", ["gluten", "eggs"], EPICERIE),
    "riz-complet": ("Riz complet", 9102, "plant", [], EPICERIE),
    "riz-basmati": ("Riz blanc", 9100, "plant", [], EPICERIE),
    "quinoa": ("Quinoa", 9340, "plant", [], EPICERIE),
    "pomme-de-terre": ("Pomme de terre", 4008, "plant", [], FRUITS),
    "patate-douce": ("Patate douce", 4101, "plant", [], FRUITS),
    "tortilla": ("Tortilla de blé", 7815, "plant", ["gluten"], EPICERIE),

    # Légumineuses
    "lentilles-corail": ("Lentilles corail", 20535, "plant", [], EPICERIE),
    "lentilles-vertes": ("Lentilles vertes", 20585, "plant", [], EPICERIE),
    "pois-chiches": ("Pois chiches cuits (conserve, égouttés)", 20532, "plant", [], EPICERIE),
    "haricots-rouges": ("Haricots rouges cuits (conserve, égouttés)", 20524, "plant", [], EPICERIE),

    # Poissons, viandes
    "saumon": ("Pavé de saumon", 26036, "fish", ["fish"], POISSON),
    "thon": ("Thon au naturel (conserve)", 26039, "fish", ["fish"], EPICERIE),
    "crevettes": ("Crevettes décortiquées", 10021, "shellfish", ["shellfish"], POISSON),
    "poulet-filet": ("Filet de poulet", 36017, "meat", [], BOUCHERIE),
    "poulet-ailes": ("Ailes de poulet", 36023, "meat", [], BOUCHERIE),

    # Fruits
    "banane": ("Banane", 13005, "plant", [], FRUITS),
    "fraises": ("Fraises", 13014, "plant", [], FRUITS),
    "framboises": ("Framboises", 13015, "plant", [], FRUITS),
    "myrtilles": ("Myrtilles", 13028, "plant", [], FRUITS),
    "fruits-rouges": ("Fruits rouges", 13997, "plant", [], FRUITS),
    "cerises": ("Cerises", 13008, "plant", [], FRUITS),
    "kiwi": ("Kiwi", 13021, "plant", [], FRUITS),
    "mangue": ("Mangue", 13025, "plant", [], FRUITS),
    "pomme": ("Pomme", 13039, "plant", [], FRUITS),
    "avocat": ("Avocat", 13004, "plant", [], FRUITS),
    "citron": ("Jus de citron", 2028, "plant", [], FRUITS),
    "dattes": ("Dattes sèches", 13011, "plant", [], EPICERIE),

    # Légumes
    "epinards": ("Épinards frais", 20059, "plant", [], FRUITS),
    "pousses-epinards": ("Jeunes pousses d'épinards", 20270, "plant", [], FRUITS),
    "tomate": ("Tomate", 20047, "plant", [], FRUITS),
    "tomates-cerises": ("Tomates cerises", 20172, "plant", [], FRUITS),
    "tomates-pulpe": ("Pulpe de tomate (conserve)", 20169, "plant", [], EPICERIE),
    "concentre-tomate": ("Concentré de tomate", 20068, "plant", [], EPICERIE),
    "concombre": ("Concombre", 20019, "plant", [], FRUITS),
    "oignon": ("Oignon jaune", 20239, "plant", [], FRUITS),
    "oignon-rouge": ("Oignon rouge", 20238, "plant", [], FRUITS),
    "ail": ("Ail", 11000, "plant", [], FRUITS),
    "carotte": ("Carotte", 20009, "plant", [], FRUITS),
    "courgette": ("Courgette", 20020, "plant", [], FRUITS),
    "poivron-rouge": ("Poivron rouge", 20087, "plant", [], FRUITS),
    "brocoli": ("Brocoli", 20057, "plant", [], FRUITS),
    "chou-kale": ("Chou kale", 20218, "plant", [], FRUITS),
    "champignons": ("Champignons de Paris", 20056, "plant", [], FRUITS),
    "potiron": ("Potiron", 20044, "plant", [], FRUITS),
    "petits-pois": ("Petits pois surgelés", 20084, "plant", [], FRUITS),
    "mais": ("Maïs doux (conserve)", 20066, "plant", [], EPICERIE),
    "laitue": ("Laitue", 20031, "plant", [], FRUITS),
    "roquette": ("Roquette", 20217, "plant", [], FRUITS),
    "mache": ("Mâche", 20099, "plant", [], FRUITS),
    "betterave": ("Betterave cuite", 20003, "plant", [], FRUITS),
    "radis": ("Radis", 20045, "plant", [], FRUITS),
    "olives-noires": ("Olives noires", 13032, "plant", [], EPICERIE),

    # Oléagineux et graines
    "noix": ("Cerneaux de noix", 15005, "plant", ["nuts"], EPICERIE),
    "noisettes": ("Noisettes", 15004, "plant", ["nuts"], EPICERIE),
    "amandes": ("Amandes", 15000, "plant", ["nuts"], EPICERIE),
    "noix-pecan": ("Noix de pécan", 15026, "plant", ["nuts"], EPICERIE),
    "graines-tournesol": ("Graines de tournesol", 15011, "plant", [], EPICERIE),
    "graines-chia": ("Graines de chia", 15047, "plant", [], EPICERIE),
    "graines-lin": ("Graines de lin", 15034, "plant", [], EPICERIE),
    "sesame": ("Graines de sésame", 15010, "plant", ["sesame"], EPICERIE),
    "beurre-cacahuete": ("Beurre de cacahuète", 15202, "plant", ["peanuts"], EPICERIE),

    # Matières grasses, condiments
    "huile-olive": ("Huile d'olive vierge extra", 17270, "plant", [], EPICERIE),
    "huile-colza": ("Huile de colza", 17130, "plant", [], EPICERIE),
    "huile-sesame": ("Huile de sésame", 17400, "plant", ["sesame"], EPICERIE),
    "sauce-soja": ("Sauce soja", 11104, "plant", ["soy", "gluten"], EPICERIE),
    "lait-coco": ("Lait de coco", 18041, "plant", [], EPICERIE),
    "moutarde": ("Moutarde", 11013, "plant", [], EPICERIE),
    "vinaigre-cidre": ("Vinaigre de cidre", 11090, "plant", [], EPICERIE),
    "miel": ("Miel", 31008, "honey", [], EPICERIE),
    "cacao": ("Cacao non sucré en poudre", 18100, "plant", [], EPICERIE),
    "bouillon-legumes": ("Bouillon de légumes", 25948, "plant", [], EPICERIE),

    # Herbes et épices
    "persil": ("Persil frais", 11014, "plant", [], HERBES),
    "coriandre": ("Coriandre fraîche", 11094, "plant", [], HERBES),
    "basilic": ("Basilic frais", 11033, "plant", [], HERBES),
    "aneth": ("Aneth frais", 11093, "plant", [], HERBES),
    "ciboulette": ("Ciboulette", 11003, "plant", [], HERBES),
    "menthe": ("Menthe fraîche", 11027, "plant", [], HERBES),
    "romarin": ("Romarin frais", 11068, "plant", [], HERBES),
    "thym": ("Thym frais", 11070, "plant", [], HERBES),
    "gingembre": ("Gingembre frais", 11074, "plant", [], HERBES),
    "curcuma": ("Curcuma en poudre", 11089, "plant", [], HERBES),
    "cumin": ("Cumin", 11042, "plant", [], HERBES),
    "paprika": ("Paprika", 11049, "plant", [], HERBES),
    "curry": ("Curry en poudre", 11005, "plant", [], HERBES),
    "cannelle": ("Cannelle", 11025, "plant", [], HERBES),
    "poivre": ("Poivre noir", 11015, "plant", [], HERBES),
    "sel": ("Sel iodé", 11058, "plant", [], HERBES),
}
