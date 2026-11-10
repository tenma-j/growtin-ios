"""Construit les données nutritionnelles de Growtin' à partir de la table Ciqual 2020 (ANSES).

Usage : python3 -I scripts/nutrition/build.py <chemin/Table Ciqual 2020.xls>
Sorties : Packages/GrowtinCore/Sources/GrowtinCore/Resources/{ciqual-subset,ingredients,recipes}.json
"""
import json, os, sys, hashlib
import xlrd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ingredients import INGREDIENTS  # noqa: E402
from recipes import RECIPES  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "Packages/GrowtinCore/Sources/GrowtinCore/Resources")
PHOTOS = os.path.join(ROOT, "Growtin/Resources/RecipePhotos")

COLUMNS = {  # clé -> index de colonne dans la table Ciqual 2020
    "energyKcal": 10, "protein": 14, "carbohydrates": 16, "fat": 17, "sugars": 18, "fiber": 26,
    "saturatedFat": 31, "ala": 44, "epa": 46, "dha": 47, "salt": 49, "calcium": 50, "iron": 53,
    "magnesium": 55, "selenium": 59, "zinc": 61, "vitaminD": 64, "vitaminC": 68, "folate": 74, "vitaminB12": 75,
}
ENERGY_FALLBACK = 12  # Énergie, N x facteur Jones, avec fibres (kcal/100 g)

def parse(value):
    if isinstance(value, float):
        return value
    text = str(value).strip().replace(",", ".")
    if text in ("", "-"):
        return None
    if text.lower() == "traces":
        return 0.0
    if text.startswith("<"):
        return 0.0  # valeur inférieure au seuil de quantification : comptée comme nulle
    try:
        return float(text)
    except ValueError:
        return None

def main(path):
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    sheet = xlrd.open_workbook(path).sheet_by_index(0)
    table = {}
    for i in range(1, sheet.nrows):
        row = sheet.row_values(i)
        table[int(row[6])] = row

    errors = []
    foods = {}
    for key, (name, code, kind, allergens, aisle) in INGREDIENTS.items():
        row = table.get(code)
        if row is None:
            errors.append(f"Code Ciqual introuvable : {code} ({key})")
            continue
        nutrients = {k: parse(row[c]) for k, c in COLUMNS.items()}
        energy_computed = False
        if nutrients["energyKcal"] is None:
            nutrients["energyKcal"] = parse(row[ENERGY_FALLBACK])
        if nutrients["energyKcal"] is None and None not in (nutrients["protein"], nutrients["carbohydrates"], nutrients["fat"]):
            # Coefficients du règlement (UE) 1169/2011, annexe XIV.
            nutrients["energyKcal"] = round(4 * nutrients["protein"] + 4 * nutrients["carbohydrates"]
                                            + 9 * nutrients["fat"] + 2 * (nutrients["fiber"] or 0), 1)
            energy_computed = True
        foods[code] = {"code": code, "name": row[7], "energyComputed": energy_computed, "nutrientsPer100g": nutrients}

    used = set()
    recipes_out = []
    for r in RECIPES:
        photo = f"recipe-{r['id']}.jpg"
        if not os.path.exists(os.path.join(PHOTOS, photo)):
            errors.append(f"Photo manquante : {photo}")
        items = []
        for key, amount, unit, grams in r["ingredients"]:
            if key not in INGREDIENTS:
                errors.append(f"Ingrédient inconnu : {key} ({r['id']})")
                continue
            used.add(key)
            items.append({"ingredientID": key, "amount": amount, "unit": unit, "grams": grams})
        recipes_out.append({
            "id": r["id"], "title": r["title"], "meal": r["meal"], "servings": r["servings"],
            "prepMinutes": r["prep"], "cookMinutes": r["cook"], "difficulty": r["difficulty"],
            "summary": r["summary"], "ingredients": items, "steps": r["steps"], "substitutions": r["substitutions"],
            "photo": photo,
        })

    credits = json.load(open(os.path.join(HERE, "photo_credits.json")))
    for r in recipes_out:
        c = credits.get(r["id"])
        if c is None:
            errors.append(f"Crédit photo manquant : {r['id']}")
            continue
        r["photoCredit"] = {"title": c["title"], "source": c["source"], "license": c["license"], "url": c["landing"]}

    ingredients_out = [
        {"id": k, "name": v[0], "ciqualCode": v[1], "kind": v[2], "allergens": v[3], "aisle": v[4]}
        for k, v in INGREDIENTS.items() if k in used
    ]
    subset = {
        "source": "Table de composition nutritionnelle des aliments Ciqual 2020, ANSES (licence ouverte Etalab)",
        "sourceURL": "https://ciqual.anses.fr/",
        "sha256": digest,
        "foods": sorted((foods[INGREDIENTS[k][1]] for k in used if INGREDIENTS[k][1] in foods), key=lambda f: f["code"]),
    }
    if errors:
        print("\n".join(errors))
        sys.exit(1)
    json.dump(subset, open(os.path.join(OUT, "ciqual-subset.json"), "w"), ensure_ascii=False, indent=1)
    json.dump(ingredients_out, open(os.path.join(OUT, "ingredients.json"), "w"), ensure_ascii=False, indent=1)
    json.dump(recipes_out, open(os.path.join(OUT, "recipes.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{len(recipes_out)} recettes, {len(ingredients_out)} ingrédients, {len(subset['foods'])} aliments Ciqual")
    missing = {k: [f["name"] for f in subset["foods"] if f["nutrientsPer100g"][k] is None] for k in COLUMNS}
    for k, names in missing.items():
        if names:
            print(f"  valeurs manquantes {k}: {len(names)}")

if __name__ == "__main__":
    main(sys.argv[1])
