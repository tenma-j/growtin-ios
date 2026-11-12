"""Corps du mannequin de Growtin' à partir des ressources MakeHuman (licence CC0 1.0).

Source : https://github.com/makehumancommunity/makehuman (dossier makehuman/data : maillage de base,
cibles de morphologie, squelette « default » et ses poids). Ces ressources sont dans le domaine public (CC0).

Module utilisé par export.py (point d'entrée du pipeline).
"""
import json, os, struct, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "Growtin/Resources/Mannequin")

# Morphologies retenues (valeurs MakeHuman entre 0 et 1)
PROFILES = {
    "male":   dict(gender=1.0, age=0.5, muscle=0.86, weight=0.5, proportions=1.0),
    "female": dict(gender=0.0, age=0.5, muscle=0.7, weight=0.48, proportions=1.0),
}

def load_obj(path):
    verts, faces, groups, group = [], [], [], None
    for line in open(path):
        if line.startswith("v "):
            verts.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("g "):
            group = line.split()[1]
        elif line.startswith("f "):
            faces.append([int(tok.split("/")[0]) - 1 for tok in line.split()[1:]])
            groups.append(group)
    return np.array(verts), faces, groups

def load_target(path):
    idx, delta = [], []
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split()
        idx.append(int(parts[0])); delta.append([float(x) for x in parts[1:4]])
    return np.array(idx, int), np.array(delta)

def tri_vals(v, low, mid, high):
    """Répartition MakeHuman d'une valeur 0…1 entre trois niveaux (min / moyen / max)."""
    hi = max(0.0, v * 2 - 1); lo = max(0.0, 1 - v * 2)
    return {low: lo, mid: 1 - hi - lo, high: hi}

def morph(data, p):
    base, faces, groups = load_obj(os.path.join(data, "3dobjs/base.obj"))
    verts = base.copy()
    T = os.path.join(data, "targets/macrodetails")
    genders = {"male": p["gender"], "female": 1 - p["gender"]}
    ages = {"young": 1.0}  # 25 ans
    muscles = tri_vals(p["muscle"], "minmuscle", "averagemuscle", "maxmuscle")
    weights = tri_vals(p["weight"], "minweight", "averageweight", "maxweight")
    def apply(path, w):
        if w <= 1e-6 or not os.path.exists(path):
            return
        i, d = load_target(path)
        if len(i):
            verts[i] += w * d
    for g, gw in genders.items():
        for a, aw in ages.items():
            for race in ("african", "asian", "caucasian"):
                apply(f"{T}/{race}-{g}-{a}.target", gw * aw / 3)
            for m, mw in muscles.items():
                for wt, ww in weights.items():
                    apply(f"{T}/universal-{g}-{a}-{m}-{wt}.target", gw * aw * mw * ww)
                    ideal = max(0.0, p["proportions"] * 2 - 1)
                    apply(f"{T}/proportions/{g}-{a}-{m}-{wt}-idealproportions.target", gw * aw * mw * ww * ideal)
    return base, verts, faces, groups

# ─── Squelette simplifié ───
FACE_PREFIXES = ("eye", "jaw", "levator", "oculi", "orbicularis", "oris", "risorius", "special", "temporalis", "tongue")

def kept_bone(name, bones):
    """Os conservé pour l'animation ; les autres transmettent leur influence à cet os."""
    if name.startswith(FACE_PREFIXES):
        return "head"
    if name.startswith("breast"):
        return "spine02"
    if name.startswith("metacarpal"):
        return "wrist" + name[-2:]
    if name.startswith("toe"):
        return "toes" + name[-2:]
    return name

def skeleton(data, verts):
    sk = json.load(open(os.path.join(data, "rigs/default.mhskel")))
    joint = {k: verts[v].mean(0) for k, v in sk["joints"].items()}
    bones = {}
    for name, b in sk["bones"].items():
        if kept_bone(name, sk["bones"]) != name:
            continue
        parent = b["parent"]
        while parent is not None and kept_bone(parent, sk["bones"]) != parent:
            parent = sk["bones"][parent]["parent"]
        bones[name] = dict(parent=parent, head=joint[b["head"]], tail=joint[b["tail"]])
    for side in (".L", ".R"):
        heads = [joint[sk["bones"][f"toe{i}-1{side}"]["head"]] for i in range(1, 6)]
        tails = [joint[sk["bones"][f"toe{i}-1{side}"]["tail"]] for i in range(1, 6)]
        bones["toes" + side] = dict(parent="foot" + side, head=np.mean(heads, 0), tail=np.mean(tails, 0))
    # Ordre parent avant enfant
    order, seen = [], set()
    def visit(n):
        if n in seen: return
        p = bones[n]["parent"]
        if p: visit(p)
        seen.add(n); order.append(n)
    for n in bones: visit(n)
    weights_raw = json.load(open(os.path.join(data, "rigs/default_weights.mhw")))["weights"]
    return order, bones, sk, weights_raw

def skin(order, bones, sk, weights_raw, nverts):
    index = {n: i for i, n in enumerate(order)}
    W = np.zeros((nverts, len(order)))
    for bone, pairs in weights_raw.items():
        k = kept_bone(bone, sk["bones"])
        if k not in index:
            continue
        for v, w in pairs:
            W[v, index[k]] += w
    top = np.argsort(-W, axis=1)[:, :4]
    tw = np.take_along_axis(W, top, 1)
    s = tw.sum(1, keepdims=True)
    tw = np.where(s > 0, tw / np.maximum(s, 1e-9), 0)
    top[s[:, 0] == 0] = index["root"]; tw[s[:, 0] == 0, 0] = 1
    return top.astype(np.uint16), tw.astype(np.float32), W
