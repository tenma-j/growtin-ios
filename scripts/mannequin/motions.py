"""Bibliothèque de mouvements du mannequin (source unique, écrite en JSON pour l'app et les tests).

Conventions (pose de référence : debout, bras le long du corps, paumes vers les cuisses ; regard vers +Z,
gauche du personnage vers +X, haut vers +Y). Angles en degrés, relatifs au parent, ordre X → Y → Z.
Valeurs données pour le côté gauche ; une clé sans côté s'applique aux deux côtés (miroir : [x, -y, -z]).
  upperleg01 : X < 0 flexion de hanche · Z > 0 écart · Y > 0 rotation externe
  lowerleg01 : X > 0 flexion du genou · foot : X > 0 pointe vers le bas · toes : X < 0 orteils relevés
  upperarm01 : X < 0 bras vers l'avant · Z > 0 bras sur le côté · Y > 0 rotation externe
  lowerarm01 : X < 0 flexion du coude · doigts et poignet : Z < 0 flexion (vers la paume)
  colonne, cou, tête : X > 0 vers l'avant · Z > 0 inclinaison à droite · Y > 0 rotation à gauche
  clavicle : Z > 0 hausser l'épaule · Y > 0 serrer l'omoplate vers l'arrière
Racine : rotations successives autour des axes du monde, puis décalage ; chaque image clé est posée au sol.
Les poses où un pied ou une main doit rester en place (pas chassés, fentes, squats, mains sur les genoux…)
sont écrites par objectifs et résolues par cinématique inverse (ik.py), séparément pour chaque corps
(homme, femme) : la bibliothèque contient une version de chaque mouvement par corps.
Bras levés : la clavicule et l'omoplate participent au mouvement (rythme scapulo-huméral), ce qui évite
l'épaule écrasée du skinning linéaire.
Usage : python3 scripts/mannequin/motions.py
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from ik import IK, with_bones  # noqa: E402

# Zones du corps nommées dans les légendes (« Zones sollicitées »).
REGIONS = ["head", "neck", "shoulders", "chest", "upperBack", "lowerBack", "abs", "biceps", "triceps", "forearms", "hands",
           "glutes", "quads", "hamstrings", "calves", "shins", "feet"]
ROOT = os.path.abspath(os.path.join(HERE, "../.."))
OUT = os.path.join(ROOT, "Packages/GrowtinCore/Sources/GrowtinCore/Resources/motions.json")
MANNEQUIN = os.path.join(ROOT, "Growtin/Resources/Mannequin/mannequin.json")

def P(base=None, root=None, ground=True, **bones):
    """Pose. Les noms d'os s'écrivent avec _L / _R pour un seul côté (upperleg01_L)."""
    d = {"bones": {}}
    for k, v in bones.items():
        name = k[:-2] + "." + k[-1] if k.endswith(("_L", "_R")) else k
        d["bones"][name] = [float(x) for x in v]
    if base is not None: d["base"] = base
    if root is not None: d["root"] = root
    if not ground: d["ground"] = False
    return d

def K(t, pose, ease="inOut"):
    return {"t": round(t, 3), "pose": pose, "ease": ease}

def S(name, side):
    return f"{name}_{side}"

def other(side):
    return "R" if side == "L" else "L"

def sided(side, value):
    """Valeur écrite pour le côté gauche, convertie pour le côté demandé (miroir pour la droite)."""
    return list(value) if side == "L" else [value[0], -value[1], -value[2]]

FINGERS = [f"finger{f}-{p}" for f in range(2, 6) for p in (1, 2, 3)]
def fist(amount=1.0):
    d = {f: [0, 0, -70 * amount] for f in FINGERS}
    d["finger1-2"] = [0, 0, -30 * amount]; d["finger1-3"] = [0, 0, -40 * amount]
    return d

def open_hand(amount=1.0, side=None):
    """Doigts dépliés (1 = tendus ; la pose de référence a les doigts légèrement fléchis)."""
    d = {}
    for f in range(2, 6):
        for ph, a in ((1, 10), (2, 22), (3, 16)):
            d[f"finger{f}-{ph}"] = [0, 0, a * amount]
    if side is None:
        return d
    return {S(k, side): sided(side, v) for k, v in d.items()}

BREATH_IN = dict(spine01=[-3, 0, 0], spine02=[-2, 0, 0], neck01=[-1, 0, 0])

POSES = {
    # Debout, pieds parallèles largeur de bassin (jambes verticales, pieds à plat).
    "stand": P(upperleg01=[0, 0, -5], foot=[0, 0, 5]),
    "supine": P(root={"rot": [["x", -90], ["y", 90]]}, upperarm01=[0, 0, 10]),
    # Angles obtenus avec scripts/mannequin/solve_poses.py (mains sous les épaules, genoux sous les hanches).
    "quadruped": P(root={"rot": [["x", 78], ["y", 90]]}, upperleg01=[-73, 0, 2], lowerleg01=[83, 0, 0], foot=[65, 0, 0],
                   upperarm01=[-74, 0, 3], lowerarm01=[-4, 0, 0], lowerarm02=[0, -95, 0], wrist=[-28, 0, 74], neck01=[-6, 0, 0]),
    "crossLeggedLegs": P(upperleg01=[-127, 9, -85], lowerleg01=[121, 0, 0], foot=[0, 0, 0]),
    "chairLegs": P(upperleg01=[-88, 0, 4], lowerleg01=[88, 0, 0]),
}

META = json.load(open(MANNEQUIN))
BODY = globals().get("BODY") or os.environ.get("MANNEQUIN_BODY", "male")
ik = IK(META["bodies"][BODY]["joints"], POSES)
PALM = 0.018 if BODY == "male" else 0.016          # demi-épaisseur de la main : paumes jointes sans se traverser
SIDES = {n[:-2] for n in ik.names if n.endswith(".L")}

# ─── Contacts : une main posée sur le corps reste à sa surface ───
# Les objectifs des poignets sont donnés par rapport aux os ; la peau, elle, dépend du corps (cuisses, hanches, côtes
# plus ou moins larges). Une main placée par objectif qui s'enfonce dans le corps en est sortie le long de la normale
# de la peau, juste assez pour la toucher (maillage et skinning de l'app : Resources/Mannequin).
from motion_eval import Body, resolve, local_rotations  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402
from scipy.optimize import fsolve, least_squares  # noqa: E402
MESH = Body.from_resources(BODY, os.path.join(ROOT, "Growtin/Resources/Mannequin"))
CONTACT_GAP = 0.002                                     # jeu laissé entre la main et la peau (m)
TRANSIT_GAP = 0.03                                      # écart à la peau au milieu d'une transition qui la frôle

def _bone_weight(prefixes, side):
    ids = [i for i, n in enumerate(MESH.names) if n.startswith(prefixes) and n.endswith("." + side)]
    return (MESH.bw * np.isin(MESH.bi, ids)).sum(1)
HAND_VERTS = {s: np.where(_bone_weight(("finger", "wrist"), s) > 0.5)[0] for s in "LR"}
# Le reste du corps, sans le bras de cette main ni l'autre main (mains jointes : réglées à part).
BODY_VERTS = {s: np.where((_bone_weight(("finger", "wrist", "lowerarm", "upperarm"), s) < 0.05)
                          & (_bone_weight(("finger", "wrist"), "R" if s == "L" else "L") < 0.05))[0] for s in "LR"}

def posed_skin(pose):
    """Peau entière dans cette pose (positions, normales), comme dans l'app."""
    r = resolve(pose, POSES)
    R, Pj = MESH.rig.fk(local_rotations(r, MESH.names), np.asarray(r["root"]["offset"], float))
    return MESH.rig.skin(MESH.v, MESH.n, MESH.bi, MESH.bw, R, Pj)

def hand_push(pose, side, reach=0.08, skin=None, gap=CONTACT_GAP, depth_min=0.0015, count_min=3):
    """Déplacement qui sort la main du corps, à « gap » de la peau (None si elle ne s'y enfonce pas : moins de
    « count_min » sommets à plus de « depth_min » sous la peau)."""
    v, n = skin if skin is not None else posed_skin(pose)
    hv, bv, bn = v[HAND_VERTS[side]], v[BODY_VERTS[side]], n[BODY_VERTS[side]]
    near = np.all((bv > hv.min(0) - reach) & (bv < hv.max(0) + reach), axis=1)
    if not near.any():
        return None
    bv, bn = bv[near], bn[near]
    dist, j = cKDTree(bv).query(hv, distance_upper_bound=reach)
    ok = np.isfinite(dist); j = np.where(ok, j, 0)
    depth = -np.einsum("ij,ij->i", hv - bv[j], bn[j])                 # > 0 : sous la peau
    inside = ok & (depth > depth_min)
    if inside.sum() < count_min:
        return None
    out = bn[j[inside]].mean(0); out /= np.linalg.norm(out)
    return out * (depth[inside].max() + gap)

_settled = {}
def settle_hands(pose, gap=CONTACT_GAP):
    """Image clé d'un mouvement : chaque main qui s'enfonce dans le corps (buste penché après coup, main sur la tête,
    bras le long de cuisses larges…) est ramenée à sa surface, avec la même orientation et le coude du même côté."""
    key = f"{gap}:" + json.dumps(pose, sort_keys=True, default=lambda o: o.tolist() if hasattr(o, "tolist") else float(o))
    if key in _settled:
        return _settled[key]
    p = pose
    for side in "LR":
        push = hand_push(p, side, gap=gap)
        sgn = 1 if side == "L" else -1
        for _ in range(8):
            if push is None:
                break
            _, Pos = ik.fk(p)
            w = Pos[f"wrist.{side}"]
            fingers = Pos[f"finger3-1.{side}"] - w
            palm = sgn * np.cross(fingers, Pos[f"finger2-1.{side}"] - Pos[f"finger5-1.{side}"])
            s, e = Pos[f"upperarm01.{side}"], Pos[f"lowerarm01.{side}"]
            d = (w - s) / np.linalg.norm(w - s)
            pole = (e - s) - d * ((e - s) @ d)
            if np.linalg.norm(pole) < 1e-3:
                pole = np.array([sgn * 1.0, -1.0, -0.3])
            p = ik.place_hand(p, side, w + push, fingers, palm, pole)
            push = hand_push(p, side, gap=gap)
    _settled[key] = p
    return p

def support_bone(pose, side):
    """Os du corps qui porte la main dans cette pose (celui dont la peau est la plus proche de la paume)."""
    r = resolve(pose, POSES)
    R, Pj = MESH.rig.fk(local_rotations(r, MESH.names), np.asarray(r["root"]["offset"], float))
    h, b = HAND_VERTS[side], BODY_VERTS[side]
    hv, _ = MESH.rig.skin(MESH.v[h], MESH.n[h], MESH.bi[h], MESH.bw[h], R, Pj)
    bv, _ = MESH.rig.skin(MESH.v[b], MESH.n[b], MESH.bi[b], MESH.bw[b], R, Pj)
    dist, j = cKDTree(bv).query(hv)
    near = j[dist < dist.min() + 0.03]
    bones = MESH.bi[b[near], 0]
    name = MESH.names[int(np.bincount(bones).argmax())]
    return MESH.rig.halves.get(name, name)                 # articulation d'appoint : l'os qu'elle double

def keep_hands(pose, rest, sides="LR"):
    """Mains posées sur le corps dans « rest » (cuisses, hanches, côtes) : dans « pose » (buste penché, épaules
    haussées, bassin qui tourne…), elles restent au même endroit de cette partie du corps ; seuls les bras s'adaptent."""
    rest_p = rest if isinstance(rest, dict) else P(rest)
    R0, P0 = ik.fk(rest_p); R1, P1 = ik.fk(pose)
    kw = {}
    for side in sides:
        sgn = 1 if side == "L" else -1
        bone = support_bone(rest_p, side)
        move = R1[bone] @ R0[bone].T
        w = P0[f"wrist.{side}"]; f = P0[f"finger3-1.{side}"] - w
        n = sgn * np.cross(f, P0[f"finger2-1.{side}"] - P0[f"finger5-1.{side}"])
        e = P0[f"lowerarm01.{side}"] - P0[f"upperarm01.{side}"]
        kw.update({side: P1[bone] + move @ (w - P0[bone]), f"fingers_{side}": move @ f, f"palm_{side}": move @ n,
                   f"pole_{side}": tuple(move @ e)})
    return hands(pose, **kw)

def pinned_sides(pose):
    """Côtés dont la main a été placée par objectif (cherche aussi dans les poses de base)."""
    out = set()
    while isinstance(pose, dict):
        out |= set(pose.get("_pinned", []))
        pose = pose.get("base")
    return out

def flatten(pose):
    """Pose mise à plat (poses de base comprises), os latéralisés explicites."""
    from motion_eval import resolve
    r = resolve(pose, POSES)
    out = {}
    for k, v in r["bones"].items():
        if max(abs(float(x)) for x in v) < 0.05:
            continue                                              # rotation nulle : inutile de l'écrire
        if k.endswith((".L", ".R")):
            if k[:-2] in SIDES: out[k] = list(v)
        elif k not in SIDES:
            out[k] = list(v)
    p = {"bones": out, "root": {"rot": [list(x) for x in r["root"]["rot"]], "offset": list(r["root"]["offset"])}}
    if not r["ground"]: p["ground"] = False
    pins = pinned_sides(pose)
    if pins: p["_pinned"] = sorted(pins)
    return p

def rhythm_amount(elevation):
    """Part de l'élévation du bras prise par la ceinture scapulaire (0 sous 60°, maximale bras à la verticale)."""
    return float(np.clip((elevation - 60) / 108, 0, 1))

def add_rhythm(pose, side, amount):
    """Ajoute l'élévation de la clavicule et la rotation de l'omoplate (mêmes valeurs que les essais visuels)."""
    p = flatten(pose)
    for bone, deg in (("clavicle", 23.5), ("shoulder01", 22.0)):
        key = f"{bone}.{side}"
        cur = p["bones"].get(key, [0.0, 0.0, 0.0])
        add = sided(side, [0, 0, deg * amount])
        p["bones"][key] = [cur[0] + add[0], cur[1] + add[1], cur[2] + add[2]]
    return p

def arm_elevation(pose, side, target=None):
    """Angle (degrés) entre le bras (ou la direction épaule → objectif) et l'axe du buste vers le bas."""
    R, Pp = ik.fk(pose)
    a = Pp[f"upperarm01.{side}"]
    b = np.asarray(target, float) if target is not None else Pp[f"lowerarm01.{side}"]
    d = b - a; d /= np.linalg.norm(d) + 1e-9
    down = R["spine01"] @ np.array([0, -1.0, 0])
    return float(np.degrees(np.arccos(np.clip(d @ down, -1, 1))))

def shoulder_rhythm(pose):
    """Bras libres levés : la ceinture scapulaire participe, le bras garde son orientation dans l'espace."""
    pins = pinned_sides(pose)
    todo = {}
    for side in "LR":
        if side in pins:
            continue
        amt = rhythm_amount(arm_elevation(pose, side))
        if amt > 0.02:
            todo[side] = amt
    if not todo:
        return pose
    R0, _ = ik.fk(pose)
    p = pose
    for side, amt in todo.items():
        p = add_rhythm(p, side, amt)
    R1, _ = ik.fk(p)
    from ik import to_euler
    for side in todo:
        parent = ik.rig.parents[ik.rig.index[f"upperarm01.{side}"]]
        p["bones"][f"upperarm01.{side}"] = to_euler(R1[parent].T @ R0[f"upperarm01.{side}"])
    return p

def joints(pose):
    return ik.fk(pose)[1]

def legs(pose, L=None, R=None, pole_L=(0, 0, 1), pole_R=(0, 0, 1), **kw):
    """Place les chevilles (positions monde, avant mise au sol : le sol est à y = 0, cheville à plat à y ≈ 0,072)."""
    p = pose if isinstance(pose, dict) else P(pose)
    for side, target, pole in (("L", L, pole_L), ("R", R, pole_R)):
        if target is not None:
            opts = {k[:-2]: v for k, v in kw.items() if k.endswith("_" + side)}
            p = with_bones(p, ik.leg(p, side, target, pole, **opts))
    return p

def hands(pose, L=None, R=None, fingers_L=None, fingers_R=None, palm_L=None, palm_R=None, pole_L=(1, -1, -0.3), pole_R=(-1, -1, -0.3)):
    """Place les poignets (et oriente les mains si « fingers » et « palm » sont donnés).
    Si la main est au-dessus de l'épaule, la ceinture scapulaire monte d'abord (rythme scapulo-huméral).
    Une main qui s'enfoncerait dans le corps est ramenée à sa surface (voir hand_push)."""
    p = pose if isinstance(pose, dict) else P(pose)
    for side, target, fingers, palm, pole in (("L", L, fingers_L, palm_L, pole_L), ("R", R, fingers_R, palm_R, pole_R)):
        if target is None:
            continue
        amt = rhythm_amount(arm_elevation(p, side, target))
        if amt > 0.02:
            p = add_rhythm(p, side, amt)
        base, target = p, np.asarray(target, float)
        for _ in range(8):
            if fingers is not None:
                p = ik.place_hand(base, side, target, fingers, palm, pole)
            else:
                p = with_bones(base, ik.arm(base, side, target, pole))
            push = hand_push(p, side)
            if push is None:
                break
            target = target + push
        p["_pinned"] = sorted(set(p.get("_pinned", [])) | {side})
    return p

def aim_bone(p, side, bone, child, want):
    """Tourne « bone » pour que le segment vers « child » suive la direction « want »."""
    from ik import to_euler
    from rig import axis_angle
    R, Pos = ik.fk(p)
    u = Pos[f"{child}.{side}"] - Pos[f"{bone}.{side}"]; u /= np.linalg.norm(u)
    axis = np.cross(u, want); sn = np.linalg.norm(axis)
    if sn < 1e-6:
        return p
    delta = axis_angle(axis / sn, np.degrees(np.arctan2(sn, u @ want)))
    parent = ik.rig.parents[ik.rig.index[f"{bone}.{side}"]]
    return with_bones(p, {f"{bone}_{side}": to_euler(R[parent].T @ delta @ R[f"{bone}.{side}"])})

def hand_axes(pose, side):
    """Repère d'une main (monde) : direction des doigts, de l'auriculaire vers l'index, côté paume."""
    _, Pos = ik.fk(pose)
    w = Pos[f"wrist.{side}"]
    fingers = Pos[f"finger3-1.{side}"] - w; fingers /= np.linalg.norm(fingers)
    across = Pos[f"finger2-1.{side}"] - Pos[f"finger5-1.{side}"]
    across -= fingers * (across @ fingers); across /= np.linalg.norm(across)
    return fingers, across, np.cross(fingers, across) * (1 if side == "L" else -1)

def joined_hands(pose, sides=("L", "R"), thumb=(0.72, 0.68, -0.12)):
    """Mains jointes, paume contre paume : doigts tendus dans le plan de la paume et pouces le long des index.
    Doigts légèrement pliés ou pouces tournés vers l'autre main la traverseraient (doigts croisés en X).
    thumb : direction du pouce (part selon les doigts, vers l'index, vers la paume)."""
    aim = aim_bone
    p = pose
    for side in sides:
        fingers, across, palm = hand_axes(p, side)
        # Doigts : chaque phalange ramenée dans le plan de la paume (l'écart naturel entre les doigts est gardé).
        for f in range(2, 6):
            for bone, child in ((f"finger{f}-1", f"finger{f}-2"), (f"finger{f}-2", f"finger{f}-3")):
                R, Pos = ik.fk(p)
                u = Pos[f"{child}.{side}"] - Pos[f"{bone}.{side}"]
                p = aim(p, side, bone, child, (u - palm * (u @ palm)) / np.linalg.norm(u - palm * (u @ palm)))
        want = thumb[0] * fingers + thumb[1] * across + thumb[2] * palm; want /= np.linalg.norm(want)
        for bone, child in (("finger1-1", "finger1-2"), ("finger1-2", "finger1-3")):
            p = aim(p, side, bone, child, want)
        p = with_bones(p, {f"finger1-3_{side}": [0.0, 0.0, 0.0]})
    return p

def grip_thumbs(pose, sides=("L", "R")):
    """Poing fermé sur un objet (serviette) : le pouce se referme par-dessus les doigts au lieu de rester levé."""
    p = pose
    for side in sides:
        fingers, across, palm = hand_axes(p, side)
        want = 0.65 * fingers + 0.3 * across + 0.45 * palm; want /= np.linalg.norm(want)
        p = aim_bone(p, side, "finger1-1", "finger1-2", want)
        want = 0.3 * fingers - 0.8 * across + 0.12 * palm; want /= np.linalg.norm(want)
        p = aim_bone(p, side, "finger1-2", "finger1-3", want)
    return p

def flat_hands(pose, sides=("L", "R")):
    """Mains posées à plat (sol, table) : doigts tendus, pouce écarté dans le plan de la paume. Au repos, le pouce
    pointe vers la paume : il passerait sous la surface d'appui."""
    return joined_hands(pose, sides, thumb=(0.55, 0.83, -0.06))

STAND = joints(P("stand"))
ANK = {s: STAND[f"foot.{s}"].copy() for s in "LR"}      # chevilles au sol, pieds largeur de bassin
FLOOR_ANKLE = float(ANK["L"][1])
# Repères du corps (les objectifs suivent la morphologie : homme ou femme).
SH = STAND["upperarm01.L"]                               # épaule gauche
ARM = float(np.linalg.norm(STAND["lowerarm01.L"] - SH) + np.linalg.norm(STAND["wrist.L"] - STAND["lowerarm01.L"]))
S_LEG = float(STAND["upperleg01.L"][1] / 0.933)          # proportions des jambes par rapport au squelette masculin
S_HIP = float(STAND["upperleg01.L"][0] / 0.108)
UPPER_ARM_LEN = float(np.linalg.norm(STAND["lowerarm01.L"] - SH))
OVERHEAD = [float(SH[1] + 0.88 * ARM), float(STAND["head"][2])]                         # mains jointes au-dessus de la tête
CHEST = [float(STAND["spine01"][1] - 0.07), float(STAND["spine01"][2] + (0.27 if BODY == "male" else 0.23))]

def ankle(side, dx=0.0, dz=0.0, lift=0.0, x=None):
    a = ANK[side].copy()
    if x is not None: a[0] = x
    a[0] += dx; a[2] += dz; a[1] += lift
    return a

def mirror_pose(pose):
    """Pose symétrique (gauche ↔ droite) : la pose est d'abord mise à plat (poses de base comprises)."""
    from motion_eval import resolve
    r = resolve(pose, POSES)
    sides = {n[:-2] for n in ik.names if n.endswith(".L")}
    out = {}
    for k, v in r["bones"].items():
        if k.endswith((".L", ".R")):
            if k[:-2] not in sides:
                continue                                          # doublon créé par resolve pour un os central
            out[k[:-2] + (".R" if k.endswith(".L") else ".L")] = [v[0], -v[1], -v[2]]
        elif k not in sides:
            out[k] = [v[0], -v[1], -v[2]]                         # os central (colonne, cou, tête)
    o = r["root"]["offset"]
    p = {"bones": out, "root": {"rot": [[a, -d if a in ("y", "z") else d] for a, d in r["root"]["rot"]], "offset": [-o[0], o[1], o[2]]}}
    if not r["ground"]: p["ground"] = False
    pins = pinned_sides(pose)
    if pins: p["_pinned"] = sorted({"L": "R", "R": "L"}[x] for x in pins)
    return p

_hip = [float(STAND["upperleg01.L"][0] + 0.05), float(STAND["spine04"][1] - 0.03), float(STAND["spine04"][2] + 0.03)]
POSES["handsHips"] = hands(P("stand"), L=_hip, R=[-_hip[0], _hip[1], _hip[2]],
                           fingers_L=[-0.2, -0.45, 1], palm_L=[-1, 0, 0], fingers_R=[0.2, -0.45, 1], palm_R=[1, 0, 0],
                           pole_L=(1, 0.1, -0.6), pole_R=(-1, 0.1, -0.6))

# Mains posées sur le corps : objectifs pris un peu sous la peau, la mise en contact (hand_push) les ramène à sa surface.
# Assis en tailleur, mains posées sur les genoux, paumes vers le ciel.
_cl = joints(P("crossLeggedLegs"))
POSES["crossLegged"] = hands(P("crossLeggedLegs"),
                             L=_cl["lowerleg01.L"] + [-0.06, 0.0, 0.0], R=_cl["lowerleg01.R"] + [0.06, 0.0, 0.0],
                             fingers_L=[0.35, -0.1, 1], palm_L=[0, 1, 0], fingers_R=[-0.35, -0.1, 1], palm_R=[0, 1, 0],
                             pole_L=(1, -0.6, -0.4), pole_R=(-1, -0.6, -0.4))
# Assis sur une chaise, mains posées à plat sur les cuisses. Coudes vers l'arrière plutôt que sur les côtés et doigts un peu
# tournés vers l'intérieur : la main reste dans l'axe de l'avant-bras (poignet incliné de moins de 25°, au lieu de 48°).
_ch = joints(P("chairLegs"))
def _thigh(side, f):
    return _ch[f"upperleg01.{side}"] * (1 - f) + _ch[f"lowerleg01.{side}"] * f
POSES["chairSit"] = hands(P("chairLegs"),
                          L=_thigh("L", 0.55) + [0.0, 0.085, 0.0], R=_thigh("R", 0.55) + [0.0, 0.085, 0.0],
                          fingers_L=[-0.15, -0.15, 1], palm_L=[0, -1, 0], fingers_R=[0.15, -0.15, 1], palm_R=[0, -1, 0],
                          pole_L=(0.5, -0.3, -1), pole_R=(-0.5, -0.3, -1))

# ─── Assises : la peau touche le dessus de la chaise ou du matelas, sans s'y enfoncer ───
# La hauteur de l'assise est lue sur la peau de chaque corps (fesses et cuisses plus ou moins épaisses) : avec un
# écart fixe sous le bassin, la femme s'enfonçait de 13 mm dans la chaise et l'homme flottait à 13 mm.
SEAT_GAP = 0.0005                                       # jeu entre la peau et l'assise (m)
def seat_low(pose, front, back=None):
    """Hauteur au-dessus du sol du point le plus bas de la peau posée sur une assise : en arrière de « front » (z du
    bord avant), au-dessus des mollets. Le sol est celui de l'app (point le plus bas de son échantillon de peau)."""
    v = posed_skin(pose)[0]
    ground = float(v[MESH.sample, 1].min())
    on = (v[:, 2] < front) & (v[:, 1] > ground + 0.2)
    if back is not None: on &= v[:, 2] > back
    return float(v[on, 1].min()) - ground

def root_height(pose):
    """Hauteur du bassin (articulation racine) au-dessus du sol de l'app."""
    return float(joints(pose)["root"][1] - posed_skin(pose)[0][MESH.sample, 1].min())

def on_seat(build, front, top, lo=-0.03, hi=0.09):
    """Pose assise posée sur son assise : build(dy) construit la pose avec le bassin monté de dy ; dy est réglé pour
    que la peau touche le dessus de l'assise (hauteur « top », bord avant en z = « front »)."""
    for _ in range(18):
        dy = (lo + hi) / 2
        if seat_low(build(dy), front) > top + SEAT_GAP: hi = dy
        else: lo = dy
    return build(hi)

SEAT_Z = float(_ch["root"][2])                           # bassin assis (z) : repère des bords d'assise
CHAIR_BACK = 0.06                                        # centre de la chaise derrière le bassin (assise de 42 cm)
BED_EDGE = 0.12                                          # bord du matelas devant le bassin : assis au bord du lit
SEAT_TOP = seat_low("chairSit", SEAT_Z - CHAIR_BACK + 0.21) - SEAT_GAP      # dessus de l'assise, au-dessus du sol
SEAT_DROP = root_height("chairSit") - SEAT_TOP           # … et sous le bassin (ancre des accessoires)

MOTIONS = {}
def root_rotations(M):
    """Rotation de la racine en rotations successives autour des axes du monde, dans l'ordre d'axes le plus éloigné
    du blocage de cardan (axe du milieu loin de ±90°) : le corps à quatre pattes ou allongé est tourné de 90°."""
    from scipy.spatial.transform import Rotation
    best = None
    for order in ("xyz", "xzy", "yxz", "yzx", "zxy", "zyx"):
        ang = Rotation.from_matrix(M).as_euler(order, degrees=True)      # extrinsèque : axe 1, puis 2, puis 3
        if best is None or abs(ang[1]) < abs(best[1][1]):
            best = (order, ang)
    rot = [[a, float(v)] for a, v in zip(best[0], best[1])]
    from motion_eval import AX
    from rig import axis_angle
    R = np.eye(3)
    for axis, deg in rot: R = axis_angle(AX[axis], deg) @ R
    assert np.abs(R - M).max() < 1e-6
    return rot

def blend(a, b, u):
    """Pose intermédiaire telle que l'app l'interpole : rotations locales sphériques, décalage de la racine linéaire."""
    from scipy.spatial.transform import Rotation, Slerp
    from ik import to_euler
    ra, rb = resolve(a, POSES), resolve(b, POSES)
    la, lb = local_rotations(ra, MESH.names), local_rotations(rb, MESH.names)
    bones, root = {}, np.eye(3)
    for name in MESH.names:
        if name in MESH.rig.halves:
            continue
        m = Slerp([0, 1], Rotation.from_matrix([la.get(name, np.eye(3)), lb.get(name, np.eye(3))]))(u).as_matrix()
        if name == "root":
            root = m
        else:
            e = to_euler(m)
            if max(abs(x) for x in e) >= 0.05:
                bones[name] = e
    off = (1 - u) * np.asarray(ra["root"]["offset"], float) + u * np.asarray(rb["root"]["offset"], float)
    p = {"bones": bones, "root": {"rot": root_rotations(root), "offset": [float(c) for c in off]}}
    if not (ra["ground"] and rb["ground"]):
        p["ground"] = False
    return p

def hands_joined(pose):
    """Mains jointes (paume contre paume) : elles bougent ensemble, on ne les écarte pas l'une de l'autre."""
    _, Pos = ik.fk(pose)
    return np.linalg.norm(Pos["wrist.L"] - Pos["wrist.R"]) < 0.07

def crosses_body(a, b):
    """Entre deux images clés, une main traverse-t-elle le corps (au moins 20 sommets à plus de 5 mm sous la peau) ?
    Un simple frôlement ne compte pas."""
    if hands_joined(a) or hands_joined(b):
        return False
    for u in (0.25, 0.5, 0.75):
        m = blend(a, b, u); skin = posed_skin(m)
        if any(hand_push(m, side, skin=skin, depth_min=0.005, count_min=20) is not None for side in "LR"):
            return True
    return False

# Points de passage d'une transition : avancement (courbe « inOut » de l'app) et instant correspondant.
WAYPOINTS = [(p, float(np.real([r for r in np.roots([-2, 3, 0, -p]) if 0 <= np.real(r) <= 1 and abs(np.imag(r)) < 1e-9][0])))
             for p in (0.25, 0.5, 0.75)]

def contact_transitions(keys):
    """Transition où une main traverserait le corps (la main va attraper le talon, passe d'une cuisse à l'autre
    genou…) : trois points de passage sont ajoutés, mains écartées de la peau, sur la même courbe de vitesse
    (« in » au départ, linéaire, « out » à l'arrivée)."""
    out = [keys[0]]
    for a, b in zip(keys, keys[1:]):
        if b.get("ease", "inOut") == "inOut" and b["t"] > a["t"] and a["pose"] is not b["pose"] and crosses_body(a["pose"], b["pose"]):
            span = b["t"] - a["t"]
            for i, (progress, at) in enumerate(WAYPOINTS):
                pose = settle_hands(blend(a["pose"], b["pose"], progress), gap=TRANSIT_GAP)
                out.append(K(a["t"] + span * at, pose, "in" if i == 0 else "linear"))
            b = dict(b, ease="out")
        out.append(b)
    return out

def _ease(u, name):
    if name == "linear": return u
    if name == "in": return u * u
    if name == "out": return 1 - (1 - u) ** 2
    return u * u * (3 - 2 * u)

def _low(pose):
    """Point le plus bas de la peau (échantillon de l'app, avant mise au sol)."""
    r = resolve(pose, POSES)
    R, Pj = MESH.rig.fk(local_rotations(r, MESH.names), np.asarray(r["root"]["offset"], float))
    s = MESH.sample
    v, _ = MESH.rig.skin(MESH.v[s], MESH.n[s], MESH.bi[s], MESH.bw[s], R, Pj)
    return float(v[:, 1].min())

def pin_feet(pose, a, b):
    """Pied posé au même endroit aux deux bouts d'une transition : il y reste aussi entre les deux (la cheville est
    replacée par cinématique inverse, même orientation du pied, genou du même côté)."""
    _, Pa = ik.fk(a); _, Pb = ik.fk(b); Rw, Pw = ik.fk(pose)
    for s in "LR":
        fa, fb = Pa[f"foot.{s}"], Pb[f"foot.{s}"]
        if np.hypot(*(fa - fb)[[0, 2]]) > 0.015:
            continue
        cur = Pw[f"foot.{s}"]
        target = np.array([(fa[0] + fb[0]) / 2, cur[1], (fa[2] + fb[2]) / 2])
        hip, knee = Pw[f"upperleg01.{s}"], Pw[f"lowerleg01.{s}"]
        axis = cur - hip; axis /= np.linalg.norm(axis) + 1e-9
        pole = (knee - hip) - axis * np.dot(knee - hip, axis)
        if np.linalg.norm(pole) < 1e-4: pole = np.array([0, 0, 1.0])
        pose = legs(pose, **{s: target, f"pole_{s}": tuple(pole / np.linalg.norm(pole)), f"foot_rot_{s}": Rw[f"foot.{s}"]})
    return pose

GROUND_TOL = 0.004                                      # écart toléré au sol entre deux images clés (m)

def ground_transitions(keys):
    """L'app pose le corps au sol à chaque image clé et interpole entre deux clés : une transition où le point le
    plus bas ne suit pas cette interpolation (pieds qui s'enfoncent en descendant sur la chaise, corps qui flotte)
    reçoit des clés intermédiaires, chacune posée au sol, jusqu'à ce que l'écart reste sous GROUND_TOL."""
    out = [keys[0]]
    for a, b in zip(keys, keys[1:]):
        ra, rb = resolve(a["pose"], POSES), resolve(b["pose"], POSES)
        span = b["t"] - a["t"]
        if not (ra["ground"] and rb["ground"]) or span <= 0.05 or a["pose"] is b["pose"]:
            out.append(b); continue
        ease = b.get("ease", "inOut")
        la, lb = _low(a["pose"]), _low(b["pose"])
        def err(n):
            worst = 0.0
            for i in range(n):
                for f in (0.25, 0.5, 0.75):
                    u = (i + f) / n
                    e = _ease(u, ease)
                    # hauteur que l'app donnerait (clés voisines posées au sol, interpolation linéaire) contre la vraie
                    e0, e1 = _ease(i / n, ease), _ease((i + 1) / n, ease)
                    l0 = _low(blend(a["pose"], b["pose"], e0)) if 0 < i else la
                    l1 = _low(blend(a["pose"], b["pose"], e1)) if i + 1 < n else lb
                    w = (e - e0) / max(e1 - e0, 1e-9)
                    worst = max(worst, abs((l0 * (1 - w) + l1 * w) - _low(blend(a["pose"], b["pose"], e))))
            return worst
        n = 1
        while n < 12 and span / n > 0.08 and err(n) > GROUND_TOL:
            n = n + 1 if n < 4 else n * 2
        if n == 1:
            out.append(b); continue
        for i in range(1, n):
            # même courbe de vitesse : départ « in », milieu linéaire, arrivée « out » (pour une courbe « inOut »)
            sub = "in" if i == 1 and ease in ("inOut", "in") else "linear"
            out.append(K(a["t"] + span * i / n, pin_feet(blend(a["pose"], b["pose"], _ease(i / n, ease)), a["pose"], b["pose"]), sub))
        out.append(dict(b, ease="out" if ease in ("inOut", "out") else "linear"))
    return out

def placed(pose):
    """Pose dont les mains sont déjà placées exactement (mains jointes symétriques) : pas de mise en contact après coup,
    qui pousserait une main contre l'avant-bras de l'autre et romprait la symétrie."""
    pose["_placed"] = True
    return pose

def is_placed(pose):
    while isinstance(pose, dict):
        if pose.get("_placed"): return True
        pose = pose.get("base")
    return False

def motion(mid, keys, muscles=(), yaw=30, props=(), pitch=8, support=None):
    for k in keys:
        p = shoulder_rhythm(k["pose"] if isinstance(k["pose"], dict) else P(k["pose"]))
        k["pose"] = p if is_placed(p) else settle_hands(p)
    keys = ground_transitions(contact_transitions(keys))
    MOTIONS[mid] = {"keys": keys, "muscles": list(muscles), "camera": {"yaw": yaw, "pitch": pitch}, "props": list(props)}
    if support: MOTIONS[mid]["support"] = support

def close_up(mid, frame, margin=None):
    """Cadrage resserré d'un mouvement (`camera.frame`) : articulations à cadrer (un nom sans côté vaut pour les deux)
    et marge autour d'elles, en mètres."""
    names = [n for j in frame for n in ((f"{j}.L", f"{j}.R") if j in SIDES else (j,))]
    MOTIONS[mid]["camera"].update(frame=names, margin=margin)

def prop(kind, anchor=None, key=0, offset=(0, 0, 0), yaw=0, floor=False):
    return {"kind": kind, "anchor": anchor, "key": key, "offset": [float(x) for x in offset], "yaw": float(yaw), "floor": floor}

CHAIR = prop("chair", "root", 0, (0, -SEAT_DROP, -CHAIR_BACK))
MAT = prop("mat", "root", 0, (0, 0, 0), floor=True)

def breathe(base, cycle=5.0, extra=None):
    inhale = dict(BREATH_IN); inhale.update(extra or {})
    up = P(base, **inhale)
    pins = pinned_sides(POSES[base] if isinstance(base, str) else base)
    if pins:
        up = keep_hands(up, base, "".join(sorted(pins)))     # mains posées : elles ne bougent pas avec la poitrine
    return [K(0, base), K(cycle / 2, up), K(cycle, base)]

def circle_keys(n, period, build, ease="linear"):
    """n images clés régulières sur un tour (la dernière reprend la première)."""
    return [K(period * i / n, build(2 * np.pi * i / n), ease) for i in range(n + 1)]

# ─── Appuis fixes ───
def planted(t0, t1, build, n=6):
    """Clés rapprochées d'une transition dont les appuis (mains, pieds, genoux) sont résolus à chaque clé : l'app
    interpole des angles, un appui dériverait entre deux clés éloignées. build(s), s de 0 à 1 sur la courbe « inOut »."""
    return [K(t0 + (t1 - t0) * i / n, build(_ease(i / n, "inOut")), "linear") for i in range(1, n + 1)]

def fixed_hand(pose, side, wrist, fingers, palm, pole, flat=True):
    """Main d'appui : poignet et orientation imposés, sans rythme scapulaire ni mise en contact."""
    p = ik.place_hand(pose, side, wrist, fingers, palm, pole)
    if flat:
        p = flat_hands(p, (side,))
    p["_pinned"] = sorted(set(p.get("_pinned", [])) | {side})
    return p

def region(prefixes, side=None):
    ids = [i for i, n in enumerate(MESH.names) if n.startswith(prefixes) and (side is None or n.endswith("." + side))]
    return np.where((MESH.bw * np.isin(MESH.bi, ids)).sum(1) > 0.5)[0]

def low_of(pose, idx):
    """Point le plus bas d'une partie de la peau (avant mise au sol)."""
    return float(posed_skin(pose)[0][idx, 1].min())

# ─── Respiration ───
motion("breathe-stand", breathe("stand"), yaw=20)
# Mains sur les côtés du bas des côtes (pouces vers l'arrière, doigts vers l'avant) : elles suivent la cage thoracique,
# 4 secondes d'inspiration (les côtes s'écartent, les coudes s'ouvrent un peu), 6 secondes d'expiration.
_rib = [float(SH[0] * 0.8), float(STAND["spine02"][1] - 0.045), float(STAND["spine02"][2] + 0.03)]
ribs = hands(P("stand", **open_hand(0.6)), L=_rib, R=[-_rib[0], _rib[1], _rib[2]],
             fingers_L=[-0.5, -0.12, 0.86], palm_L=[-1, 0.05, -0.1], fingers_R=[0.5, -0.12, 0.86], palm_R=[1, 0.05, -0.1],
             pole_L=(1, -0.35, -0.7), pole_R=(-1, -0.35, -0.7))
def ribs_in():
    p = keep_hands(P(ribs, spine01=[-5, 0, 0], spine02=[-4, 0, 0], spine03=[-1, 0, 0], neck01=[-1, 0, 0], clavicle=[0, 2, 3]), ribs)
    J = joints(p); kw = {}
    for s, sg in (("L", 1), ("R", -1)):                     # les côtes s'écartent : les mains partent avec elles
        f, _, n = hand_axes(p, s)
        kw.update({s: J[f"wrist.{s}"] + [0.012 * sg, 0.004, 0.0], f"fingers_{s}": f, f"palm_{s}": n, f"pole_{s}": (sg, -0.3, -0.6)})
    return hands(p, **kw)
motion("rib-breathing", [K(0, ribs), K(4, ribs_in()), K(10, ribs)], muscles=("chest", "abs"), yaw=20)
# Regard au loin : inspire 5 secondes (le regard part d'un côté), expire 5 secondes ; puis de l'autre côté.
motion("look-far", [K(0, P("stand", head=[-5, 0, 0])), K(5, P("stand", head=[-6, 12, 0], **BREATH_IN)),
                    K(10, P("stand", head=[-5, 0, 0])), K(15, P("stand", head=[-6, -12, 0], **BREATH_IN)), K(20, P("stand", head=[-5, 0, 0]))], yaw=25)
# Assis sur la chaise (installation et détente globale de la relaxation) : inspiration 4 secondes, expiration 6. La
# poitrine se soulève franchement et les épaules montent un peu (avec la seule extension du haut du dos, le souffle ne
# se voyait pas), la tête reste droite ; mains posées sur les cuisses.
_chair_in = keep_hands(P("chairSit", spine01=[-6, 0, 0], spine02=[-4, 0, 0], spine03=[-2, 0, 0], clavicle=[0, 1, 5], neck01=[8, 0, 0],
                         head=[4, 0, 0]), "chairSit")
motion("chair-breathe", [K(0, "chairSit"), K(4, _chair_in), K(10, "chairSit")], yaw=30, props=(CHAIR,))
close_up("chair-breathe", ("head", "upperarm01", "upperleg01", "wrist"), 0.12)      # buste et cuisses : le souffle se voit
# Méditation assise : dos droit, dos des mains posé sur les genoux, paumes vers le ciel, doigts ouverts, coudes souples.
# Le bassin bascule vers l'avant (assis sur les ischions) : sans cela la pose de référence, cuisses repliées, se lit
# comme un buste penché en arrière ; le cou rend la bascule, le regard reste horizontal.
# Jambes croisées, la gauche devant : chaque cheville passe de l'autre côté du corps, le pied posé sur sa tranche.
# La jambe droite (derrière) est ouverte sur le côté, son pied rentré sous la cuisse gauche ; la jambe gauche passe
# devant elle, genou plus haut, son pied posé devant le tibia droit, sous son genou. Les deux tibias restent distincts :
# à leur croisement, le gauche est près de sa cheville, le droit près de son genou, et aucune jambe n'entre dans l'autre
# (`leg_overlap` : la cheville gauche avance jusqu'à SEAT_CLEAR de jeu). Chevilles placées par cinématique inverse ;
# la hauteur de chacune est réglée sur la peau pour que le pied touche le sol au niveau des fesses et des cuisses.
# Positions (x vers la gauche, z vers l'avant depuis le bassin) données pour le squelette masculin, mises à l'échelle
# des hanches (x) et des jambes (z) de chaque corps ; la jambe droite de l'homme, aux cuisses plus épaisses, est un peu
# plus ouverte (son genou se relevait d'un coup en passant au-dessus de la cuisse gauche).
from rig import axis_angle as _aa  # noqa: E402
SEATED_TILT = 9.0
SEAT_ANKLE = {"L": (-0.094, 0.415), "R": (0.001, 0.164) if BODY == "female" else (0.04, 0.164)}
SEAT_POLE = {"L": (1.0, 0.31, 0.3), "R": (-1.0, 0.0, 0.3) if BODY == "female" else (-1.0, -0.15, 0.3)}   # genoux : dehors, haut, avant
SEAT_YAW = {"L": 113.5, "R": 107.2}                    # pied tourné vers l'autre côté (degrés)
SEAT_ROLL = 55.0                                       # pied roulé sur sa tranche externe
SEAT_CLEAR = 0.004                                     # jeu minimal entre les deux jambes (m)
_seat_base = P(root={"rot": [["x", SEATED_TILT]]})
SEAT_SEAT = region(("pelvis", "root", "spine05", "upperleg"))   # fesses et arrière des cuisses
SEAT_FOOT = {s: region(("foot", "toes"), s) for s in "LR"}
def _seat_leg_verts(s):
    """Jambe « s » sans le haut de la cuisse (près de l'aine, les cuisses se touchent toujours) : genou, tibia, pied."""
    w = lambda pre: (MESH.bw * np.isin(MESH.bi, [i for i, n in enumerate(MESH.names) if n.startswith(pre) and n.endswith("." + s)])).sum(1)
    low, up = w(("lowerleg", "foot", "toes")), w(("upperleg",))
    ky, hy = float(MESH.v[low > 0.5, 1].max()), float(MESH.v[up > 0.5, 1].max())
    return np.where((low > 0.5) | ((up > 0.5) & (MESH.v[:, 1] < ky + 0.5 * (hy - ky))))[0]
SEAT_LEGV = {s: _seat_leg_verts(s) for s in "LR"}
def leg_overlap(pose):
    """Jambe dans jambe : profondeur max (m) d'un sommet d'une jambe sous la peau de l'autre (sommet le plus proche, le
    long de sa normale, à moins de 4 cm ; négatif : écart entre les jambes, -1 si elles sont loin l'une de l'autre)."""
    v, n = posed_skin(pose)
    worst = -1.0
    for a, b in (("L", "R"), ("R", "L")):
        A, B = SEAT_LEGV[a], SEAT_LEGV[b]
        d, j = cKDTree(v[B]).query(v[A], distance_upper_bound=0.04)
        ok = np.isfinite(d); jj = np.where(ok, j, 0)
        sd = np.where(ok, -np.einsum("ij,ij->i", v[A] - v[B][jj], n[B][jj]), -1.0)
        worst = max(worst, float(sd.max()))
    return worst
_SB = joints(_seat_base)
def seat_legs(fwd=0.0):
    """Jambes croisées posées ; fwd : cheville gauche avancée d'autant."""
    p = _seat_base
    for s in ("R", "L", "R", "L"):                     # deux passes : la cuisse de l'autre jambe, encore tendue, est plus basse
        sg = 1 if s == "L" else -1
        x, z = SEAT_ANKLE[s]
        x, z = x * S_HIP, _SB["root"][2] + z * S_LEG + (fwd if s == "L" else 0.0)
        rot = _aa([0, 1, 0], -sg * SEAT_YAW[s]) @ _aa([0, 0, 1], -sg * SEAT_ROLL)
        def one(y, p=p, s=s, x=x, z=z, rot=rot):
            return legs(p, **{s: [x, y, z], f"pole_{s}": SEAT_POLE[s], f"foot_rot_{s}": rot})
        def above(y, s=s, one=one):
            v = posed_skin(one(y))[0]
            return v[SEAT_FOOT[s], 1].min() >= v[SEAT_SEAT, 1].min()
        # Premier passage du pied au niveau des fesses en montant (plus haut, le genou qui se relève abaisse l'arrière
        # de la cuisse et le niveau des fesses saute), puis réglage fin.
        lo = _SB["root"][1] - 0.25
        while not above(lo + 0.01): lo += 0.01
        hi = lo + 0.01
        for _ in range(12):
            m = (lo + hi) / 2
            if above(m): hi = m
            else: lo = m
        p = one(hi)
    return p
SEAT_FWD = 0.0                                         # la cheville gauche avance jusqu'à ce que les tibias se dégagent
if leg_overlap(seat_legs(0.0)) > -SEAT_CLEAR:
    _lo, _hi = 0.0, 0.10
    for _ in range(12):
        _m = (_lo + _hi) / 2
        if leg_overlap(seat_legs(_m)) > -SEAT_CLEAR: _lo = _m
        else: _hi = _m
    SEAT_FWD = _hi
_seat_legs = seat_legs(SEAT_FWD)
_sv = posed_skin(_seat_legs)[0]
print("tailleur : cheville gauche avancée de", round(SEAT_FWD * 1000, 1), "mm ; écart entre les jambes",
      round(-leg_overlap(_seat_legs) * 1000, 1), "mm ; pieds / fesses",
      [round(1000 * float(_sv[SEAT_FOOT[s], 1].min() - _sv[SEAT_SEAT, 1].min()), 1) for s in "LR"], "mm")
# Mains : le dos de la main posé sur le genou (sur la cuisse, juste en retrait du genou), paume vers le ciel, doigts vers
# l'avant et l'extérieur ; coudes souples près du corps (pôle vers le bas et l'arrière) et épaules basses (clavicules
# abaissées de 5°). La hauteur du poignet est réglée sur la peau (CONTACT_GAP entre le dos de la main et la cuisse, sans
# enfoncement de la main ni de l'avant-bras). Posées sur le haut du genou, coudes écartés, les mains semblaient flotter à
# côté des genoux, bras en anses et épaules haussées. Vu un peu d'en haut (22°) : les paumes posées se voient.
SEAT_HAND_BACK = 0.07                                  # poignet en retrait du genou, le long de la cuisse (m)
SEAT_CLAV = -5.0                                       # épaules basses (degrés)
SEAT_HAND = {s: region(("wrist", "finger"), s) for s in "LR"}
SEAT_FORE = {s: region(("lowerarm",), s) for s in "LR"}
SEAT_LEGS_ALL = region(("upperleg", "lowerleg", "foot", "toes"))
def seat_hand_gap(p, s):
    """Main et avant-bras « s » face aux jambes : enfoncement (distance signée au sommet le plus proche) et distance de
    la main à la peau."""
    v, n = posed_skin(p)
    arm = np.concatenate([SEAT_HAND[s], SEAT_FORE[s]])
    d, j = cKDTree(v[SEAT_LEGS_ALL]).query(v[arm])
    side = np.einsum("ij,ij->i", v[arm] - v[SEAT_LEGS_ALL][j], n[SEAT_LEGS_ALL][j])
    return float(np.where(d < 0.04, side, 1.0).min()), float(d[: len(SEAT_HAND[s])].min())
def seated(breath=0.0):
    p = P(_seat_legs, spine01=[-3 * breath, 0, 0], spine02=[-2 * breath, 0, 0], clavicle=[0, 0, SEAT_CLAV + 2 * breath],
          neck01=[-SEATED_TILT * 0.6 - breath, 0, 0], head=[-SEATED_TILT * 0.4, 0, 0], **open_hand(0.75))
    J = joints(_seat_legs)
    for s, sg in (("L", 1), ("R", -1)):
        hip, knee = J[f"upperleg01.{s}"], J[f"lowerleg01.{s}"]
        thigh = (knee - hip) / np.linalg.norm(knee - hip)
        def place(h, s=s, sg=sg, q=p, knee=knee, thigh=thigh):
            w = knee - SEAT_HAND_BACK * thigh + [0.0, h, 0.0]      # poignet au-dessus de la cuisse, en retrait du genou
            return fixed_hand(q, s, w, [0.7 * sg, -0.1, 0.7], [0, 1, 0], (0.3 * sg, -1, -0.5), flat=False)
        lo, hi = 0.0, 0.14                               # la main descend quand h diminue
        for _ in range(14):
            m = (lo + hi) / 2
            pen, dist = seat_hand_gap(place(m), s)
            if pen < -0.0015 or dist < CONTACT_GAP: lo = m
            else: hi = m
        p = place(hi)
    return placed(p)
# Tapis centré sous le corps (fesses, genoux et pieds dessus).
_sv = posed_skin(seated())[0]; _sr = joints(seated())["root"]
_smid = (_sv.min(0) + _sv.max(0)) / 2 - _sr
assert np.ptp(_sv[:, 2]) < 0.6 and np.ptp(_sv[:, 0]) < 1.85, "tailleur plus grand que le tapis"
motion("seated-breathe", [K(0, seated()), K(3, seated(1)), K(6, seated())], yaw=15, pitch=22,
       props=(prop("mat", "root", 0, (float(_smid[0]), 0, float(_smid[2])), floor=True),))

# ─── Marche sur place, montées de genoux ───
def knee_lift(side, hip, knee, arm, elbow, back_arm=18, twist=5):
    """Genou « side » levé ; bras opposé vers l'avant, bras du même côté vers l'arrière, coudes pliés."""
    o = other(side)
    return P("stand", **{S("upperleg01", side): sided(side, [-hip, 0, -3]), S("lowerleg01", side): [knee, 0, 0],
                         S("foot", side): sided(side, [hip * 0.35, 0, 3]),
                         S("upperarm01", o): sided(o, [-arm, 0, 6]), S("lowerarm01", o): [-elbow, 0, 0],
                         S("upperarm01", side): sided(side, [back_arm, 0, 6]), S("lowerarm01", side): [-elbow * 0.8, 0, 0]},
             spine03=[0, twist if side == "L" else -twist, 0], **open_hand(0.4))
# Marche sur place : le pied ne glisse pas. Il se déroule (le talon monte, la pointe reste posée au même endroit), monte
# à la verticale de son appui, n'avance qu'une fois en l'air jusqu'à la position genou levé, puis redescend de même et
# se repose pointe d'abord. L'autre pied reste posé à plat ; les deux sont résolus par cinématique inverse à chaque clé
# (clés rapprochées : entre deux clés l'app interpole des angles, un appui dériverait).
MARCH_PEEL, MARCH_PEEL_PART = 22.0, 0.22                 # déroulé du pied (degrés) et part de la montée qu'il occupe
def march_foot(pose, side, w, top, top_pitch):
    """w : 0 pied posé à plat, 1 genou levé (cheville en « top », pointe inclinée de « top_pitch »)."""
    if w < 1e-6:
        return legs(pose, **{side: ankle(side)})
    toe = STAND[f"toes.{side}"]; a = ANK[side] - toe
    def heel_up(deg):                                    # la cheville tourne autour de la pointe du pied, qui reste posée
        c, sn = np.cos(np.radians(deg)), np.sin(np.radians(deg))
        return toe + [a[0], a[1] * c - a[2] * sn + 0.005 * deg / MARCH_PEEL, a[1] * sn + a[2] * c]   # 5 mm : la pliure des orteils
    if w < MARCH_PEEL_PART:
        th = MARCH_PEEL * (1 - np.cos(np.pi / 2 * w / MARCH_PEEL_PART))
        return legs(pose, **{side: heel_up(th), f"foot_pitch_{side}": th, f"toes_{side}": -th})
    g = float(np.sin(np.pi / 2 * (w - MARCH_PEEL_PART) / (1 - MARCH_PEEL_PART)))
    a0 = heel_up(MARCH_PEEL)
    return legs(pose, **{side: a0 + (top - a0) * [g * g, g, g * g], f"foot_pitch_{side}": MARCH_PEEL + (top_pitch - MARCH_PEEL) * g,
                         f"toes_{side}": -MARCH_PEEL * (1 - g) ** 2})
def stepping(mid, hip, knee, arm, elbow, period, muscles, yaw=30, back_arm=18, twist=5, n=24):
    top = {s: joints(knee_lift(s, hip, knee, arm, elbow))[f"foot.{s}"] for s in "LR"}
    def pose(phi):
        """phi : 0 genou gauche levé, 0,25 deux pieds posés, 0,5 genou droit levé, 0,75 deux pieds posés."""
        swing = float(np.cos(2 * np.pi * phi))           # 1 : bras droit devant, bras gauche derrière
        arms = {}
        for s, f in (("R", swing), ("L", -swing)):
            arms[S("upperarm01", s)] = sided(s, [(back_arm - arm) / 2 - (arm + back_arm) / 2 * f, 0, 6])
            arms[S("lowerarm01", s)] = [-elbow * (0.9 + 0.1 * f), 0, 0]
        p = P("stand", root={"offset": [-0.012 * S_HIP * swing, 0, 0]}, spine03=[0, twist * swing, 0], **arms, **open_hand(0.4))
        p = march_foot(p, "L", max(0.0, 1 - 4 * min(phi, 1 - phi)), top["L"], knee - 0.65 * hip)
        return march_foot(p, "R", max(0.0, 1 - 4 * abs(phi - 0.5)), top["R"], knee - 0.65 * hip)
    # Clés régulières, plus deux pendant chaque déroulé du pied (entre deux clés l'app interpole des angles : la pointe
    # posée s'enfoncerait de quelques millimètres).
    peel = [(1 - w * MARCH_PEEL_PART) / 4 for w in (0.35, 0.7)]
    phis = sorted({round(x, 4) for x in [i / n for i in range(n)] + [c + sg * x for x in peel for c, sg in ((0, 1), (0.5, -1), (0.5, 1), (1, -1))]})
    motion(mid, [K(period * phi, pose(phi), "linear") for phi in phis] + [K(period, pose(0.0), "linear")], muscles=muscles, yaw=yaw)
stepping("march", 52, 72, 34, 80, 1.3, ("quads", "calves", "abs"), yaw=50)
stepping("high-knees", 82, 96, 48, 90, 1.1, ("quads", "abs"), yaw=50)
# Récupération : marche sur place lente et calme. Le pied monte et redescend à la verticale de son appui (il ne glisse
# pas), l'autre reste posé ; les bras balancent à peine.
def slow_step(side, up=1.0, breath=0.0):
    """breath : 0 à 1, inspiration profonde pendant le pas (poitrine qui s'ouvre, tête un peu relevée, bras un peu écartés)."""
    o = other(side)
    if breath > 1e-6:
        b = breath
        p = P("stand", **{S("upperarm01", o): sided(o, [-13 * up - 3, 0, 6 + 9 * b]), S("lowerarm01", o): [-14 - 8 * up, 0, 0],
                          S("upperarm01", side): sided(side, [9 * up - 3, 0, 6 + 9 * b]), S("lowerarm01", side): [-14, 0, 0]},
              spine01=[-6 * b, 0, 0], spine02=[-4 * b, 0, 0], spine03=[-2 * b, (3 if side == "L" else -3) * up, 0],
              neck01=[-3 * b, 0, 0], clavicle=[0, 6 * b, 4 * b], **open_hand(0.4 + 0.2 * b))
    else:
        p = P("stand", **{S("upperarm01", o): sided(o, [-13 * up - 3, 0, 6]), S("lowerarm01", o): [-14 - 8 * up, 0, 0],
                          S("upperarm01", side): sided(side, [9 * up - 3, 0, 6]), S("lowerarm01", side): [-14, 0, 0]},
              spine03=[0, (3 if side == "L" else -3) * up, 0], **open_hand(0.4))
    if up < 0.01:
        return p
    return legs(p, **{side: ankle(side, lift=0.12 * S_LEG * up, dz=0.035 * S_LEG * up), f"foot_pitch_{side}": 24 * up, f"toes_{side}": -6 * up})
def slow_steps(t0, steps, period=2.6):
    """Pas tranquilles sur place à partir de la station debout (gauche, droite…) ; se termine pieds posés."""
    h, keys = period / 4, []
    for i in range(steps):
        side = "LR"[i % 2]; t = t0 + 2 * i * h
        keys += [K(t + 0.5 * h, slow_step(side, 0.55), "in"), K(t + h, slow_step(side, 1.0), "out"),
                 K(t + 1.5 * h, slow_step(side, 0.55), "in"), K(t + 2 * h, slow_step(side, 0.0), "out")]
    return keys
motion("march-slow", [K(0, slow_step("L", 0))] + slow_steps(0, 2), muscles=("quads", "calves"), yaw=50)
# Retour au calme : marche lente sur place, sans arrêt, en respirant profondément. Douze pas de 1,3 s (comme la
# récupération) ; une respiration toutes les deux enjambées (5,2 s : la poitrine s'ouvre, la tête se relève un peu, les bras
# s'écartent à peine, puis tout redescend). Les pieds montent et redescendent à la verticale de leur appui. Auparavant :
# quatre pas puis dix secondes immobile, un seul pas visible sur toute la boucle.
MB_STEPS, MB_PERIOD, MB_BREATH = 12, 2.6, 5.2
def march_breath(t):
    return float(0.5 - 0.5 * np.cos(2 * np.pi * t / MB_BREATH))
def march_breathe_keys():
    h, keys = MB_PERIOD / 4, [K(0, slow_step("L", 0))]
    for i in range(MB_STEPS):
        side = "LR"[i % 2]; t = 2 * i * h
        for f, up, ease in ((0.5, 0.55, "in"), (1.0, 1.0, "out"), (1.5, 0.55, "in"), (2.0, 0.0, "out")):
            keys.append(K(t + f * h, slow_step(side, up, march_breath(t + f * h)), ease))
    return keys
motion("march-breathe", march_breathe_keys(), muscles=("quads", "calves", "chest"), yaw=40)

# Pause : une gorgée d'eau, puis quelques pas tranquilles sur place. La main droite tient un verre (`"kind": "glass"`,
# cylindre que l'app et les planches posent contre la paume d'après trois sommets de la peau de la main : creux de la
# paume, bord de la paume côté index, dos de la main) : elle le porte aux lèvres, le verre et la tête basculent le
# temps de la gorgée, puis le verre revient devant le ventre, avant-bras à l'horizontale, et y reste pendant les pas.
# Le verre est placé par son centre et son axe ; la main s'en déduit (elle le tient par le côté, à mi-hauteur), sa
# distance à la paume et la fermeture de chaque doigt sont réglées sur la peau : les doigts l'entourent sans le traverser.
from motion_eval import glass_pose, glass_distance, GLASS_WIDTH, GLASS_HEIGHT  # noqa: E402
_head = region(("head",))
_hv = MESH.v[_head]; _front = _hv[_hv[:, 2] > ik.H["head"][2] + 0.04]
_chin = _front[np.argmin(_front[:, 1])]
_lip = _hv[np.abs(_hv[:, 1] - (_chin[1] + 0.045)) < 0.006]
MOUTH = np.array([0.0, _chin[1] + 0.045, _lip[:, 2].max()]) - ik.H["head"]          # dans le repère de la tête
def glass_vertices():
    """Sommets de la main droite qui portent le verre (partie rigide de la main : le métacarpe)."""
    v, n = MESH.v, MESH.n; s = "R"
    w = ik.H[f"wrist.{s}"]; f = ik.H[f"finger3-1.{s}"] - w
    palm = -np.cross(f, ik.H[f"finger2-1.{s}"] - ik.H[f"finger5-1.{s}"]); palm /= np.linalg.norm(palm)
    rigid = _bone_weight(("wrist",), s)[HAND_VERTS[s]] > 0.85
    inner = HAND_VERTS[s][((n[HAND_VERTS[s]] @ palm) > 0.5) & rigid]
    pick = lambda c: int(inner[np.argmin(np.linalg.norm(v[inner] - c, axis=1))])
    across = ik.H[f"finger2-1.{s}"] - ik.H[f"finger5-1.{s}"]; across -= f * (across @ f) / (f @ f); across /= np.linalg.norm(across)
    centre = pick(w + 0.66 * f + 0.012 * palm)
    index = pick(v[centre] + 0.028 * across)             # même hauteur le long des doigts : l'axe du verre est en travers de la paume
    outer = HAND_VERTS[s][((n[HAND_VERTS[s]] @ palm) < -0.5) & (_bone_weight(("wrist",), s)[HAND_VERTS[s]] > 0.9)]
    rel = v[outer] - v[centre]; off = rel - np.outer(rel @ palm, palm)
    return [centre, index, int(outer[np.argmin(np.linalg.norm(off, axis=1))])]
GLASS = dict(prop("glass", None, 0), vertices=glass_vertices(), width=GLASS_WIDTH, height=GLASS_HEIGHT, depth=GLASS_WIDTH / 2 + 0.004)
GLASS_CURL = {f: 0.2 for f in range(2, 6)}                 # fermeture de chaque doigt autour du verre
GLASS_THUMB = [1.0]                                        # pouce : 0 refermé contre le verre, 1 écarté de lui
GLASS_FINGER = {f: np.where(sum(_bone_weight((f"finger{f}-{p}",), "R") for p in (1, 2, 3)) > 0.5)[0] for f in range(1, 6)}
GLASS_PALM = np.setdiff1d(HAND_VERTS["R"], np.concatenate(list(GLASS_FINGER.values())))
def glass_frame(prop, v):
    c, a = glass_pose(prop, v); n = v[prop["vertices"][0]] - v[prop["vertices"][2]]
    n = n - a * (n @ a); n /= np.linalg.norm(n)
    return c, np.column_stack([a, n, np.cross(a, n)])
def glass_hand(pose, centre, axis, toward, pole=(-0.45, -1, 0.1)):
    """Main droite refermée sur le verre : « centre » et « axis » (du fond vers le bord) du verre, « toward » direction
    de la paume vers le verre. La main est d'abord orientée comme le verre le demande, puis le poignet est corrigé
    jusqu'à ce que le verre calculé sur la peau soit à sa place (au demi-millimètre)."""
    a = np.asarray(axis, float); a /= np.linalg.norm(a)
    n = np.asarray(toward, float); n = n - a * (n @ a); n /= np.linalg.norm(n)
    want = np.column_stack([a, n, np.cross(a, n)])
    c0, F0 = glass_frame(GLASS, MESH.v)
    turn = want @ F0.T
    f0, _, n0 = hand_axes(P(), "R")
    d = {f"finger{f}-{ph}_R": [0, 0, 70 * c] for f, c in GLASS_CURL.items() for ph in (1, 2, 3)}
    p = P(pose, **d)
    w = np.asarray(centre, float) + turn @ (ik.H["wrist.R"] - c0)
    for _ in range(5):
        q = ik.place_hand(p, "R", w, turn @ f0, turn @ n0, pole)
        # Le pouce part droit devant la paume et passe de l'autre côté du verre, en face des doigts ; « t » l'en écarte.
        fg, ac, pm = hand_axes(q, "R"); t = GLASS_THUMB[0]
        aim = pm + (0.15 - 0.9 * t) * fg + 0.1 * ac
        q = aim_bone(q, "R", "finger1-1", "finger1-2", aim / np.linalg.norm(aim))
        aim = pm + (0.55 - 0.9 * t) * fg + 0.05 * ac
        q = aim_bone(q, "R", "finger1-2", "finger1-3", aim / np.linalg.norm(aim))
        err = np.asarray(centre, float) - glass_pose(GLASS, posed_skin(q)[0])[0]
        if np.linalg.norm(err) < 3e-4: break
        w = w + err
    q["_pinned"] = sorted(set(q.get("_pinned", [])) | {"R"})
    return placed(q)
def glass_gap(pose, parts):
    v = posed_skin(pose)[0]
    return float(glass_distance(GLASS, v, v[parts]).min())
_sh_r = STAND["upperarm01.R"]
GLASS_REST = _sh_r + [0.01, -0.93 * UPPER_ARM_LEN, 0.86 * (ARM - UPPER_ARM_LEN) + 0.10]       # devant le ventre, coude au corps
_glass_stand = settle_hands(P("stand"))                    # la main gauche, au repos, reste à la surface de la cuisse
def drink(u, tip=0.0):
    """u : 0 verre tenu devant le ventre, 1 verre aux lèvres ; tip : le verre et la tête basculent pour boire."""
    p = P(_glass_stand, neck01=[-5 * tip, 0, 0], head=[-9 * tip, 0, 0])
    R, J = ik.fk(p)
    tilt = np.radians(12 * u + 38 * tip)                   # le bord du verre penche vers la bouche
    axis = np.array([0.0, np.cos(tilt), -np.sin(tilt)])
    r, h = GLASS["width"] / 2, GLASS["height"]
    back = np.array([0.0, 0, -1.0]); e = back - axis * (back @ axis); e /= np.linalg.norm(e)
    lips = J["head"] + R["head"] @ (MOUTH + [0.0, -0.012, 0.004])
    at_lips = lips - axis * h / 2 - e * r                  # le point du bord le plus proche du visage touche la lèvre
    c = GLASS_REST + (at_lips - GLASS_REST) * u + [0.0, 0.0, 0.10 * np.sin(np.pi * u)]     # le verre monte par l'avant du corps
    toward = np.array([1.0, 0.0, 0.25 - 0.45 * u])         # la main tient le verre par le côté droit
    return glass_hand(p, c, axis, toward, pole=(-0.5 - 0.55 * u, -1, 0.05))
# Prise réglée sur la peau : le verre s'écarte de la paume jusqu'à la dégager (1,5 mm de jeu), puis chaque doigt et le
# pouce se referment autour de lui jusqu'à 1,5 mm, pas plus.
GLASS_GAP = 0.0015
for _ in range(4):
    GLASS["depth"] = round(GLASS["depth"] + GLASS_GAP - min(glass_gap(drink(u), GLASS_PALM) for u in (0.0, 1.0)), 4)
for _f in range(2, 6):
    _lo, _hi = 0.2, 1.0
    for _ in range(7):
        _m = (_lo + _hi) / 2; GLASS_CURL[_f] = _m
        if min(glass_gap(drink(u), GLASS_FINGER[_f]) for u in (0.0, 1.0)) >= GLASS_GAP: _lo = _m
        else: _hi = _m
    GLASS_CURL[_f] = round(_lo, 3)
_lo, _hi = 0.0, 1.0
for _ in range(7):
    GLASS_THUMB[0] = (_lo + _hi) / 2
    if min(glass_gap(drink(u), GLASS_FINGER[1]) for u in (0.0, 1.0)) >= GLASS_GAP: _hi = GLASS_THUMB[0]
    else: _lo = GLASS_THUMB[0]
GLASS_THUMB[0] = round(_hi, 3)
print("verre : axe à", round(GLASS["depth"] * 1000, 1), "mm de la paume, fermeture des doigts", GLASS_CURL, "pouce", GLASS_THUMB[0],
      "écart verre / main", [round(glass_gap(drink(u, t), HAND_VERTS["R"]) * 1000, 1) for u, t in ((0, 0), (0.5, 0), (1, 0), (1, 1))])
_hold, _sip = drink(0), drink(1, 1)
GLASS_ARM = ("upperarm01.R", "lowerarm01.R", "lowerarm02.R", "wrist.R", "clavicle.R", "shoulder01.R") + tuple(
    f"finger{f}-{ph}.R" for f in range(1, 6) for ph in (1, 2, 3))
def glass_steps(keys):
    """Pas tranquilles, le verre tenu devant le ventre : le bras droit garde la pose de repos, le reste du corps marche."""
    hold = flatten(_hold)["bones"]; out = []
    for k in keys:
        q = flatten(settle_hands(k["pose"] if isinstance(k["pose"], dict) else P(k["pose"])))
        for b in GLASS_ARM:
            q["bones"].pop(b, None)
            if b in hold: q["bones"][b] = hold[b]
        q["_pinned"] = ["R"]
        out.append(dict(k, pose=placed(q)))
    return out
motion("water-break", [K(0, _hold)] + planted(0.3, 1.6, drink, n=7) + planted(1.6, 2.1, lambda s: drink(1, s), n=3) + [K(3.0, _sip)]
       + planted(3.0, 3.5, lambda s: drink(1, 1 - s), n=3) + planted(3.5, 4.8, lambda s: drink(1 - s), n=7)
       + glass_steps(slow_steps(4.8, 4)) + [K(10.6, _hold)], yaw=35, props=(GLASS,))

# ─── Marche (promenade, marche soutenue) ───
# Marche écrite par objectifs, sur place (le sol défile sous le corps à vitesse constante, comme sur un tapis roulant).
# Chaque pied suit le cycle réel : attaque du talon pointe relevée, pied à plat, talon qui se lève en roulant sur
# l'avant-pied, poussée des orteils, puis passage du pas en l'air. Le bassin est porté par la jambe d'appui presque
# tendue (il monte au passage à la verticale, redescend au double appui), se décale vers elle, tourne avec la jambe
# qui avance et s'incline un peu du côté du pied levé ; le buste tourne à l'opposé, la tête reste de face. Les bras
# balancent à l'opposé des jambes.
LEG_MAX = float(np.linalg.norm(ik.H["lowerleg01.L"] - ik.H["upperleg01.L"]) + np.linalg.norm(ik.H["foot.L"] - ik.H["lowerleg01.L"]))
LEG_STAND = float(np.linalg.norm(STAND["foot.L"] - STAND["upperleg01.L"])) / LEG_MAX      # jambe « tendue » debout
WALK_FOOT = {s: region(("foot", "toes"), s) for s in "LR"}
_sv = posed_skin(P("stand"))[0]
WALK_FLOOR = float(_sv[:, 1].min())
# Appui du talon : point du sol sous l'arrière du talon (le pied pivote dessus à l'attaque du pas).
WALK_HEEL = {s: np.array([ANK[s][0], WALK_FLOOR, float(_sv[WALK_FOOT[s], 2].min()) + 0.03]) for s in "LR"}
def walk_foot(side, phi, g):
    """Cheville, inclinaison du pied (> 0 pointe en bas) et flexion des orteils à la phase « phi » du pas de ce pied
    (0 : attaque du talon ; g["stance"] : les orteils quittent le sol)."""
    st, flat, off = g["stance"], g["flat"], g["heel_off"]
    x = ANK[side][0] * g["width"]
    def stance(f):
        zc = g["front"] - g["stride"] * f                 # le point d'appui recule avec le sol
        if f < flat:
            pitch, pivot = -g["strike"] * (1 - f / flat), WALK_HEEL[side]
        elif f < off:
            pitch, pivot = 0.0, None
        else:
            pitch, pivot = g["push"] * ((f - off) / (st - off)) ** 1.25, np.array([ANK[side][0], WALK_FLOOR, STAND[f"toes.{side}"][2]])
        a = ANK[side].copy()
        if pivot is not None:                              # la cheville tourne autour du talon, ou de la base des orteils
            r = a - pivot; c, sn = np.cos(np.radians(pitch)), np.sin(np.radians(pitch))
            a = pivot + [r[0], r[1] * c - r[2] * sn, r[1] * sn + r[2] * c]
        return np.array([x, a[1], a[2] + zc]), pitch
    if phi < st:
        a, pitch = stance(phi)
        return a, pitch, -max(pitch, 0.0)
    s = (phi - st) / (1 - st)
    (a0, p0), (a1, p1) = stance(st - 1e-6), stance(0.0)
    sm = s * s * (3 - 2 * s)
    v = -g["stride"] * (1 - st)                            # vitesse du sol, par unité de « s »
    m0, m1 = 0.25 * v, v                                   # la cheville repart doucement, et se pose à la vitesse du sol
    z = (2 * s ** 3 - 3 * s ** 2 + 1) * a0[2] + (s ** 3 - 2 * s ** 2 + s) * m0 + (-2 * s ** 3 + 3 * s ** 2) * a1[2] + (s ** 3 - s ** 2) * m1
    y = a0[1] + (a1[1] - a0[1]) * sm + g["clear"] * np.sin(np.pi * min(1.0, s / 0.85)) ** 2
    return np.array([x, y, z]), p0 + (p1 - p0) * sm, -p0 * max(0.0, 1 - 3 * s)
def walk_heights(p, phi, feet, g):
    """Hauteur du bassin que permet chaque jambe : celle qui porte le corps est presque tendue (un peu plus pliée juste
    après la pose du talon, quand elle amortit) ; la jambe en l'air compte à l'approche du sol. Au double appui, la
    plus courte des hauteurs l'emporte, sans à-coup (voir walk_pose)."""
    _, J = ik.fk(p); out = []
    for s, f in (("L", phi % 1.0), ("R", (phi + 0.5) % 1.0)):
        sw = (f - g["stance"]) / (1 - g["stance"])
        if 0 <= sw < 0.4:
            continue
        a = feet[s][0]; hip = J[f"upperleg01.{s}"]
        # au milieu de l'appui (f ≈ 0,25), la jambe se tend un peu plus que debout au repos (« extend ») : genou à 170–175°
        reach = min(LEG_STAND + g.get("extend", 0.0) * np.exp(-((f - 0.25) / 0.16) ** 2) - g["load"] * np.exp(-((f - 0.13) / 0.07) ** 2), 0.997) * LEG_MAX
        late = 4.0 * max(0.0, f - 0.5) ** 2 if sw < 0 else 0.6 * (1 - sw) ** 2
        out.append((s, float(a[1] + np.sqrt(max(reach ** 2 - (hip[0] - a[0]) ** 2 - (hip[2] - a[2]) ** 2, 1e-6)) - hip[1] + late)))
    return out
def walk_pose(phi, g, solve=True):
    """phi : phase du pas de la jambe gauche (0 : son talon se pose devant ; 0,5 : celui de la jambe droite)."""
    c = float(np.cos(2 * np.pi * phi))
    yaw = -g["pelvis"] * c                                # la hanche de la jambe qui avance part en avant
    roll = g["list"] * float(np.sin(2 * np.pi * (phi + 0.05)))      # le bassin descend du côté du pied levé
    twist = g["shoulders"] * c - yaw                      # épaules à l'opposé du bassin
    arms = {}
    for s, cs in (("R", c), ("L", -c)):                    # cs = 1 : bras en avant (à l'opposé de la jambe du même côté)
        fwd = (1 + cs) / 2
        arms[S("upperarm01", s)] = sided(s, [g["arm_mid"] - g["arm"] * cs, -g["arm_in"] * fwd, g["arm_out"]])
        arms[S("lowerarm01", s)] = [-(g["elbow"] + g["elbow_swing"] * fwd), 0, 0]
    p = P("stand", root={"rot": [["x", g["lean"]], ["z", roll], ["y", yaw]], "offset": [g["sway"] * S_HIP * float(np.sin(2 * np.pi * (phi - 0.05))), 0, 0]},
          spine05=[0, twist * 0.2, -roll * 0.3], spine04=[0, twist * 0.2, -roll * 0.3], spine03=[0, twist * 0.2, -roll * 0.2],
          spine02=[0, twist * 0.2, -roll * 0.2], spine01=[0, twist * 0.2, 0], neck01=[-g["lean"] * 0.6, -g["shoulders"] * c * 0.5, 0],
          head=[-g["lean"] * 0.4, -g["shoulders"] * c * 0.5, 0], **arms, **g["hands"])
    feet = {"L": walk_foot("L", phi % 1.0, g), "R": walk_foot("R", (phi + 0.5) % 1.0, g)}
    hs = [h for _, h in walk_heights(p, phi, feet, g)]
    if not solve:
        return dict(walk_heights(p, phi, feet, g))
    k = 100.0
    p["root"]["offset"][1] = float(-np.log(sum(np.exp(-k * (h - min(hs))) for h in hs)) / k + min(hs))
    for s in "LR":
        a, pitch, toes = feet[s]
        sw = ((phi + (0 if s == "L" else 0.5)) % 1.0 - g["stance"]) / (1 - g["stance"])
        for _ in range(3):
            q = legs(p, **{s: a, f"pole_{s}": (0, 0, 1), f"foot_pitch_{s}": pitch, f"toes_{s}": toes})
            gap = low_of(q, WALK_FOOT[s]) - WALK_FLOOR
            if sw < 0:
                a = a - [0, gap, 0]                              # pied d'appui : sa peau touche le sol, ni plus ni moins
            else:                                                # pied en l'air : il passe au-dessus du sol
                a = a + [0, max(0.0, 0.012 * min(1.0, sw / 0.12, (1 - sw) / 0.1) - gap), 0]
        p = legs(p, **{s: a, f"pole_{s}": (0, 0, 1), f"foot_pitch_{s}": pitch, f"toes_{s}": toes})
    return placed(p)
def walking(mid, period, n, muscles, **g):
    g = dict(dict(stance=0.62, flat=0.08, heel_off=0.32, width=0.75), **g)
    g["stride"] *= S_LEG; g["clear"] *= S_LEG
    # Le talon se pose devant à l'instant où la jambe arrière, tendue, a amené le bassin à la même hauteur : pas d'à-coup.
    lo, hi = 0.12 * S_LEG, 0.42 * S_LEG
    for _ in range(14):
        g["front"] = (lo + hi) / 2
        h = walk_pose(0.0, g, solve=False)
        if h["L"] > h["R"]: lo = g["front"]
        else: hi = g["front"]
    print(mid, ": talon posé à", round(g["front"] / S_LEG, 3), "de jambe devant la hanche")
    motion(mid, [K(period * i / n, walk_pose(i / n, g), "linear") for i in range(n)] + [K(period, walk_pose(0.0, g), "linear")],
           muscles=muscles, yaw=70)
# Promenade : pas tranquilles, bras souples qui balancent à l'opposé des jambes.
walking("walk", 1.2, 40, ("quads", "calves", "glutes"), stride=1.08, strike=14, push=36, clear=0.035, pelvis=6, list=2.5,
        shoulders=4, lean=2, sway=0.018, load=0.007, extend=0.012, arm_mid=3, arm=24, arm_in=6, arm_out=7, elbow=12, elbow_swing=16, hands=open_hand(0.3))
# Marche soutenue : cadence plus élevée, coudes pliés à 90°, bras qui balancent franchement d'avant en arrière
# (le poing monte à hauteur de poitrine devant, revient à la hanche derrière), buste à peine penché.
walking("walk-fast", 0.92, 36, ("quads", "calves", "glutes", "hamstrings"), stride=1.22, strike=18, push=42, clear=0.04, pelvis=8,
        list=3.5, shoulders=7, lean=4, sway=0.016, load=0.009, extend=0.012, stance=0.60, arm_mid=14, arm=44, arm_in=8, arm_out=10, elbow=80, elbow_swing=12,
        hands=fist(0.75))

# Boxe dans le vide : garde (pied gauche devant, genoux souples, poings au menton), direct du gauche, retour en garde,
# direct du droit avec rotation du buste, retour. Les pieds restent posés.
BOX_FEET = {"L": ankle("L", dx=0.03 * S_HIP, dz=0.17 * S_LEG), "R": ankle("R", dx=-0.06 * S_HIP, dz=-0.15 * S_LEG)}
BOX_GUARD = {"L": (0.06, -0.14, 0.17), "R": (-0.11, -0.14, 0.145)}       # poignets en garde, depuis la tête (repère du regard)
BOX_FLARE = {"L": 0.15, "R": 0.2}                        # écart des coudes en garde (pôle du coude, repère du buste)
BOX_TURN_FLARE = 0.3                                     # … et quand l'autre bras frappe
BOX_ELBOW_FWD = 0.35                                     # coudes en garde : un peu devant les côtes (pôle vers l'avant)
BOX_REACH = 0.94                                         # coude pas complètement tendu au bout du coup
def boxing(jab=0.0, cross=0.0):
    yaw = -14 - 5 * jab + 18 * cross                 # bassin tourné vers la droite en garde
    twist = -8 * jab + 26 * cross                    # rotation des épaules en plus de celle du bassin
    look = -(yaw + twist)
    p = P("stand", root={"rot": [["y", yaw]], "offset": [0, -0.06 * S_LEG, 0.02 * S_LEG * (jab + cross)]},
          spine04=[3, twist * 0.2, 0], spine03=[3, twist * 0.3, 0], spine02=[0, twist * 0.3, 0], spine01=[0, twist * 0.2, 0],
          neck01=[5, look * 0.35, 0], neck02=[0, look * 0.25, 0], head=[3, look * 0.4, 0], **fist(1.0))
    p = legs(p, L=BOX_FEET["L"], R=BOX_FEET["R"], pole_L=(0.1, 0, 1), pole_R=(-0.5, 0, 1), foot_yaw_L=-8, foot_yaw_R=-42)
    R, J = ik.fk(p); Rc = R["spine01"]; kw = {}
    for s, sg, u, other_u in (("L", 1, jab, cross), ("R", -1, cross, jab)):
        sh = J[f"upperarm01.{s}"]
        # Garde : les deux poings devant le menton, 6 à 10 cm devant le visage, dans le repère du regard (la tête
        # regarde droit devant, +Z) : pris dans celui du buste tourné, ils partaient tous deux vers la joue droite.
        guard = J["head"] + BOX_GUARD[s]
        reach = BOX_REACH * ARM
        hit = np.array([0.02 * sg, sh[1] + 0.01, sh[2] + np.sqrt(reach ** 2 - (sh[0] - 0.02 * sg) ** 2)])
        w = guard + (hit - guard) * u
        f = np.array([-0.15 * sg, 1, 0.25]); f = f / np.linalg.norm(f) * (1 - u) + (hit - sh) / reach * u
        n = np.array([-sg, 0, 0.2]); n = n / np.linalg.norm(n) * (1 - u) + np.array([-0.25 * sg, -1, 0]) * u
        # coude bas en garde, un peu écarté quand l'autre bras frappe (le buste tourne vers l'avant-bras), rentré pendant le coup
        flare = BOX_FLARE[s] + BOX_TURN_FLARE * other_u + (0.12 - BOX_FLARE[s]) * u
        kw.update({s: w, f"fingers_{s}": f, f"palm_{s}": n, f"pole_{s}": tuple(Rc @ [flare * sg, -1, BOX_ELBOW_FWD * (1 - u) - 0.1 * u])})
    return grip_thumbs(hands(p, **kw))
_guard = boxing()
_jab, _cross = boxing(jab=1), boxing(cross=1)
motion("shadow-boxing", [K(0, _guard), K(0.04, _guard)] + planted(0.04, 0.27, lambda s: boxing(jab=s), n=4) + [K(0.37, _jab)]
       + planted(0.37, 0.7, lambda s: boxing(jab=1 - s), n=4) + [K(1.1, _guard)] + planted(1.1, 1.36, lambda s: boxing(cross=s), n=4)
       + [K(1.46, _cross)] + planted(1.46, 1.84, lambda s: boxing(cross=1 - s), n=4) + [K(2.2, _guard)],
       muscles=("shoulders", "triceps", "abs"), yaw=35)

# Échauffement : marche sur place et grands cercles de bras vers l'arrière. Le bras monte par l'avant jusqu'à la
# verticale, puis redescend par le côté, un peu en arrière du plan des épaules (là où l'épaule le permet : il ne passe
# jamais tendu droit derrière le dos), et revient le long du corps.
WARM_TOP = {s: joints(P("stand", **{S("upperleg01", s): sided(s, [-48, 0, -3]), S("lowerleg01", s): [64.8, 0, 0]}))[f"foot.{s}"] for s in "LR"}
def reach_arm(pose, side, direction, reach=0.985, pole=None):
    """Bras tendu dans une direction (monde), main à « reach » × la longueur du bras de l'épaule. La ceinture scapulaire
    monte d'abord (rythme scapulo-huméral), puis la main est visée depuis l'épaule ainsi déplacée : visée depuis l'épaule
    au repos, elle serait trop près et le coude plierait."""
    d = np.asarray(direction, float); d = d / np.linalg.norm(d)
    p = pose if isinstance(pose, dict) else P(pose)
    down = ik.fk(p)[0]["spine01"] @ np.array([0, -1.0, 0])
    amt = rhythm_amount(float(np.degrees(np.arccos(np.clip(d @ down, -1, 1)))))
    if amt > 0.02:
        p = add_rhythm(p, side, amt)
    sg = 1 if side == "L" else -1
    p = with_bones(p, ik.arm(p, side, joints(p)[f"upperarm01.{side}"] + reach * ARM * d, pole or (0.2 * sg, -0.5, -1)))
    p["_pinned"] = sorted(set(p.get("_pinned", [])) | {side})
    return p
WARM_BACK = 22.0                                        # descente par le côté : degrés en arrière du plan des épaules
def warm_arm(theta, sg):
    """Direction du bras (de l'épaule vers la main) : theta = 0 le long du corps, 90° devant, 180° en haut, 270° sur le côté."""
    t = theta % (2 * np.pi)
    def ramp(a, b):                                       # 0 avant « a », 1 après « b » (degrés), sans à-coup
        u = float(np.clip((np.degrees(t) - a) / (b - a), 0, 1)); return u * u * (3 - 2 * u)
    side = ramp(140, 215) * (1 - ramp(325, 360))
    b = np.radians(WARM_BACK)
    h = (1 - side) * np.array([0.12 * sg, 0, 1.0]) + side * np.array([np.cos(b) * sg, 0, -np.sin(b)])
    h /= np.linalg.norm(h)
    return abs(np.sin(t)) * h + np.array([0.10 * sg * np.cos(t) ** 2, -np.cos(t), 0])
def warmup(theta):
    phase = (theta / (2 * np.pi)) * 2            # deux pas par cercle
    side = "L" if int(phase + 1e-9) % 2 == 0 else "R"
    w = 1 - abs(2 * (phase % 1.0) - 1)           # 0 → 1 → 0 sur chaque pas ; le pied monte et se repose sans glisser
    lift = max(0.0, -np.cos(theta))              # bras au-dessus de l'horizontale : la poitrine s'ouvre un peu
    p = P("stand", spine01=[-3 * lift, 0, 0], **open_hand(0.7))
    p = march_foot(p, side, 0.0 if w < 1e-6 else w, WARM_TOP[side], 33.6)
    p = legs(p, **{other(side): ankle(other(side))})
    for s, sg in (("L", 1), ("R", -1)):
        d = warm_arm(theta, sg); d /= np.linalg.norm(d)
        p = reach_arm(p, s, d, 0.985, (0.2 * sg, -0.5, -1))
    return p
motion("warmup-march", circle_keys(32, 3.2, warmup), muscles=("shoulders", "quads"), yaw=55)

# Pas chassés (« deux pas à droite, deux pas à gauche, genoux légèrement fléchis ») : les pieds se posent vraiment, le
# bassin suit, genoux fléchis tout du long (140–145°, un peu plus pieds écartés ; vus de trois quarts). Les bras restent détendus près du
# corps, coudes pliés : ils s'écartent à peine (une quinzaine de degrés) quand le pied s'écarte et reviennent quand
# l'autre le rejoint ; le buste penche à peine du côté où l'on va.
def side_steps():
    step, lift, soft = 0.30 * S_LEG, 0.07 * S_LEG, -0.045 * S_LEG
    def pose(fl, fr, cx, lifted=None, wide=0.0, lean=0.0, h=0.0):
        """wide : 0 pieds joints, 1 pieds écartés (bras un peu écartés, genoux un peu plus pliés) ; lean : buste penché
        (degrés) ; h : hauteur du pied levé."""
        p = P("stand", root={"rot": [["z", lean]], "offset": [cx, soft - 0.015 * S_LEG * wide, 0]}, spine03=[0, 0, -0.6 * lean], neck01=[0, 0, -0.4 * lean],
              upperarm01=[-8 - 2 * wide, 3 * wide, 6 + 9 * wide], lowerarm01=[-38 + 6 * wide, 0, 0], **open_hand(0.3))
        tl = ankle("L", x=fl, lift=h if lifted == "L" else 0)
        tr = ankle("R", x=fr, lift=h if lifted == "R" else 0)
        kw = {f"foot_pitch_{lifted}": 10.0 * h / lift} if lifted else {}
        return legs(p, L=tl, R=tr, pole_L=(0.2, 0, 1), pole_R=(-0.2, 0, 1), **kw)
    sm = lambda u: u * u * (3 - 2 * u)
    feet = {"L": float(ANK["L"][0]), "R": float(ANK["R"][0])}
    cx, t, w_prev, lean_prev = 0.0, 0.0, 0.1, 0.0
    keys = [K(0, pose(feet["L"], feet["R"], cx, wide=0.1))]
    # Deux pas vers la droite (−X, le pied droit mène), puis deux vers la gauche. Chaque pas est résolu en six clés : le
    # pied monte à la verticale de son appui, ne se déplace sur le côté qu'en l'air, se pose à la verticale ; le pied
    # d'appui est replacé à chaque clé (deux clés éloignées le laissaient glisser de 1 à 2 cm).
    for direction, lead in ((-1, "R"), (-1, "R"), (1, "L"), (1, "L")):
        for mover, w0, w1 in ((lead, 0.6, 1.0), (other(lead), 0.55, 0.1)):
            start = feet[mover]; end = start + direction * step; cx0, cx1 = cx, cx + direction * step / 2
            lean_mid, lean_end = 2.5 * direction, (1.5 * direction if mover == lead else 0.0)
            for i in range(1, 7):
                u = i / 6
                ux = sm(min(1.0, max(0.0, (u - 0.15) / 0.7)))
                h = lift * float(np.sin(np.pi * u)) if i < 6 else 0.0
                two = lambda a, b, c: a + (b - a) * sm(min(1.0, 2 * u)) if u <= 0.5 else b + (c - b) * sm(2 * u - 1)
                f = dict(feet); f[mover] = start + (end - start) * ux
                keys.append(K(t + 0.64 * u, pose(f["L"], f["R"], cx0 + (cx1 - cx0) * sm(u), mover if h > 1e-4 else None,
                                                 two(w_prev, w0, w1), two(lean_prev, lean_mid, lean_end), h), "linear"))
            feet[mover] = end; cx = cx1; t += 0.64; w_prev, lean_prev = w1, lean_end
    return keys
motion("side-steps", side_steps(), muscles=("quads", "glutes", "calves"), yaw=28)

# Squats partiels : on descend bras vers l'avant, on remonte en levant les bras au-dessus de la tête.
# Demi-squat : les genoux plient à 120–130° (pas jusqu'à l'angle droit), talons au sol, genoux au-dessus des pieds, dos long.
# Les deux bras sont placés ensemble, en miroir, par leur direction (épaule → main) : en haut, tendus au-dessus de la
# tête, écartés en V le long des oreilles (jamais devant le visage) ; en bas, à l'horizontale devant soi. Entre les deux,
# ils passent un peu en diagonale (plan de l'omoplate), à chaque clé : interpolés directement entre « en haut » et
# « devant », ils prenaient un chemin différent à gauche et à droite.
HS_DIRS = [np.array(d, float) / np.linalg.norm(d) for d in ((0.22, 1.0, 0.04), (0.35, 0.71, 0.61), (0.06, 0.0, 1.0))]
def hs_dir(v):
    """Direction du bras gauche : v = 0 en haut, 1 devant (arc de grand cercle par morceaux)."""
    a, b, w = (HS_DIRS[0], HS_DIRS[1], 2 * v) if v <= 0.5 else (HS_DIRS[1], HS_DIRS[2], 2 * v - 1)
    th = np.arccos(np.clip(a @ b, -1, 1))
    return (np.sin((1 - w) * th) * a + np.sin(w * th) * b) / np.sin(th)
def half_squat(u, v=None):
    """u : 0 debout, 1 en bas ; v : position des bras (0 en haut, 1 devant ; par défaut u)."""
    v = u if v is None else v
    p = P("stand", root={"rot": [["x", 17 * u]], "offset": [0, -0.088 * S_LEG * u, -0.07 * S_LEG * u]}, spine04=[3 * u, 0, 0], neck01=[-8 * u, 0, 0],
          **open_hand(0.8 - 0.3 * v))
    p = legs(p, L=ankle("L"), R=ankle("R"), pole_L=(0.15, 0, 1), pole_R=(-0.15, 0, 1))
    d = hs_dir(v)
    for s, sg in (("L", 1), ("R", -1)):
        p = reach_arm(p, s, d * [sg, 1, 1], 0.975, (0.25 * sg, -0.6, -1))
    return p
_top, _half = half_squat(0.0), half_squat(1.0)
motion("half-squat-arms", [K(0, _top)] + planted(0, 1.8, half_squat, n=6) + [K(2.3, _half)]
       + planted(2.3, 4.0, lambda s: half_squat(1 - s), n=6) + [K(4.6, _top)],
       muscles=("quads", "glutes", "shoulders"), yaw=60)

# Squat sur chaise : s'asseoir en 3 secondes, se relever en 1, sans les mains.
# Debout devant la chaise, pieds largeur de bassin. Les hanches partent vers l'arrière, le buste se penche, les bras
# montent devant pour l'équilibre ; les fesses descendent jusqu'à effleurer le dessus de l'assise (hauteur du bassin
# réglée sur la peau de chaque corps), bassin au-dessus du milieu de l'assise, cuisses au-dessus d'elle, tibias presque
# verticaux (genoux au-dessus des pieds). La chaise est posée d'après le corps : assise à 45 ou 46 cm, son milieu sous les
# hanches en bas du squat, son bord avant derrière les mollets du personnage debout. Pieds résolus à chaque clé.
SQUAT_SEAT = 0.46 if BODY == "male" else 0.45              # hauteur de l'assise (m) : chaise à la taille du corps
SQUAT_BACK, SQUAT_LEAN = 0.31 * S_LEG, 30.0                  # recul du bassin, inclinaison du buste en bas du squat
def chair_squat(s, depth=0.3 * S_LEG):
    """s : 0 debout, 1 fesses sur l'assise ; depth : descente du bassin en bas du squat."""
    a = s ** 0.8                                             # hanches en arrière et buste penché d'abord, puis on descend
    p = P("stand", root={"rot": [["x", SQUAT_LEAN * a]], "offset": [0, -depth * s ** 1.25, -SQUAT_BACK * a]},
          spine04=[4 * a, 0, 0], neck01=[-SQUAT_LEAN * 0.45 * a, 0, 0],
          upperarm01=[-78 * a, 0, 6 * a], lowerarm01=[-4 * a, 0, 0], **open_hand(0.6 * a))
    return legs(p, L=ankle("L"), R=ankle("R"), pole_L=(0.15, 0, 1), pole_R=(-0.15, 0, 1))
_sv = posed_skin("stand")[0]
_calf = float(_sv[(_sv[:, 1] > _sv[:, 1].min() + 0.05) & (_sv[:, 1] < _sv[:, 1].min() + SQUAT_SEAT + 0.01), 2].min())
# Bord avant de l'assise : milieu de l'assise sous les hanches, et au moins 1 cm derrière les mollets debout. Hanches
# plus hautes que les genoux, les cuisses descendent vers l'avant : si elles touchent le bord avant alors que les
# fesses restent en l'air (plus de 4 mm), la chaise recule centimètre par centimètre (les hanches restent à 10 cm au
# moins derrière le bord). La descente du bassin est réglée sur la peau à chaque essai : 1 mm au-dessus de l'assise.
_hip_z = float(joints(chair_squat(1))["upperleg01.L"][2])
SQUAT_FRONT = min(_hip_z + 0.21, _calf - 0.01)
while True:
    _lo, _hi = 0.15 * S_LEG, 0.6 * S_LEG
    for _ in range(20):
        SQUAT_DEPTH = (_lo + _hi) / 2
        if seat_low(chair_squat(1, SQUAT_DEPTH), SQUAT_FRONT, SQUAT_FRONT - 0.42) > SQUAT_SEAT + 2 * SEAT_GAP: _lo = SQUAT_DEPTH
        else: _hi = SQUAT_DEPTH
    SQUAT_DEPTH = _lo
    _buttocks = seat_low(chair_squat(1, SQUAT_DEPTH), _hip_z + 0.03, SQUAT_FRONT - 0.42) - SQUAT_SEAT
    if _buttocks <= 0.004 or SQUAT_FRONT - 0.01 < _hip_z + 0.10: break
    SQUAT_FRONT -= 0.01
print("squat sur chaise : assise", SQUAT_SEAT, "bord avant", round(SQUAT_FRONT, 3), "hanches", round(_hip_z, 3),
      "fesses à", round(_buttocks * 1000, 1), "mm de l'assise")
seat = chair_squat(1, SQUAT_DEPTH)
motion("chair-squat", [K(0, "stand")] + planted(0, 3, lambda s: chair_squat(s, SQUAT_DEPTH), n=12) + [K(3.3, seat)]
       + planted(3.3, 4.3, lambda s: chair_squat(1 - s, SQUAT_DEPTH), n=10) + [K(5.2, "stand")],
       muscles=("quads", "glutes"), yaw=70, props=(prop("chair", None, 0, (0, SQUAT_SEAT, SQUAT_FRONT - 0.21)),))

# ─── Renforcement ───
# Pompes inclinées : le corps, planche rigide, pivote sur l'avant des pieds ; les mains restent posées au bord du plateau.
TOE = STAND["toes.L"]
def plank(theta):
    heel = max(0.0, theta - 22)                         # talons décollés : la cheville ne plie pas au-delà de 22°
    p = P("stand", root={"rot": [["x", theta]]}, foot=[heel - theta, 0, 5], toes=[-heel, 0, 0], neck01=[-6, 0, 0], head=[-4, 0, 0])
    off = TOE - joints(p)["toes.L"]
    p["root"]["offset"] = [0.0, float(off[1]), float(off[2])]
    return p
PUSH_TOP, PUSH_LOW = 38.0, 46.5
_t = joints(plank(PUSH_TOP)); _a = np.radians(PUSH_TOP)
_dir = np.array([0, -np.sin(_a), np.cos(_a)]) - 0.14 * np.array([0, np.cos(_a), np.sin(_a)]); _dir /= np.linalg.norm(_dir)
PUSH_W = {}
for _s, _sg in (("L", 1), ("R", -1)):
    _w = _t[f"upperarm01.{_s}"] + 0.975 * ARM * _dir; _w[0] += 0.03 * _sg; PUSH_W[_s] = _w
def pushup(u):
    p = plank(PUSH_TOP + (PUSH_LOW - PUSH_TOP) * u)
    p = P(p, clavicle=[0, 10 * u, 0], **open_hand(0.8))
    for s, sg in (("L", 1), ("R", -1)):
        p = fixed_hand(p, s, PUSH_W[s], [-0.18 * sg, 0, 1], [0, -1, 0], (0.75 * sg, -0.45, -1))
    return p
push_top, push_low = pushup(0), pushup(1)
motion("incline-pushup", [K(0, push_top)] + planted(0, 1.8, pushup) + planted(1.8, 3.0, lambda s: pushup(1 - s)) + [K(3.6, push_top)],
       muscles=("chest", "triceps", "shoulders"), yaw=75)
# Table placée d'après la main : plateau sous la paume, bord juste derrière le talon de la main, centrée sur le corps.
_k0 = MOTIONS["incline-pushup"]["keys"][0]["pose"]
_v, _ = posed_skin(_k0); _w = joints(_k0)["wrist.L"]; _h = _v[HAND_VERTS["L"]]
MOTIONS["incline-pushup"]["props"] = [prop("table", "wrist.L", 0, (-_w[0], _h[:, 1].min() - _w[1], 0.22 + (_h[:, 2].min() - _w[2]) - 0.012))]

# Pont fessier : pieds à plat, bras au sol le long du corps ; tête et épaules ne bougent pas, le bassin monte
# jusqu'à l'alignement genoux-hanches-épaules.
TRUNK = region(("spine", "root", "pelvis", "clavicle", "shoulder", "upperleg"))
HEAD = region(("head", "neck"))
_bent = P("supine", upperleg01=[-50, 0, 2], lowerleg01=[100, 0, 0])
FLOOR_SUP = low_of(_bent, TRUNK)                             # sol sous le dos (avant mise au sol)
# Tête posée : le cou s'étend juste assez pour que l'arrière du crâne touche le sol.
_lo, _hi = -30.0, 10.0
for _ in range(14):
    _m = (_lo + _hi) / 2
    if low_of(P(_bent, neck01=[_m, 0, 0]), HEAD) > FLOOR_SUP: _hi = _m
    else: _lo = _m
BR_NECK = round((_lo + _hi) / 2, 1)
_s0 = joints(_bent)
BR_ANK = {s: np.array([_s0[f"upperleg01.{s}"][0] + 0.46 * S_LEG, FLOOR_SUP + FLOOR_ANKLE, _s0[f"upperleg01.{s}"][2] * 1.15]) for s in "LR"}
BR_W = (0.2, 0.65, 0.15)
def bridge(phi):
    p = P("supine", root={"rot": [["x", -90 - phi], ["y", 90]]}, spine02=[phi * BR_W[0], 0, 0], spine01=[phi * BR_W[1], 0, 0],
          neck01=[BR_NECK + phi * BR_W[2], 0, 0])
    off = _s0["neck01"] - joints(p)["neck01"]
    p["root"]["offset"] = [float(c) for c in off]
    if phi > 0.01:
        # le haut du dos reste posé, puis le cou ramène l'arrière du crâne au sol
        p["root"]["offset"][1] += FLOOR_SUP - low_of(p, TRUNK)
        lo, hi = BR_NECK - 25.0, BR_NECK + 35.0
        for _ in range(9):
            m = (lo + hi) / 2
            if low_of(P(p, neck01=[m, 0, 0]), HEAD) > FLOOR_SUP: hi = m
            else: lo = m
        p = P(p, neck01=[round((lo + hi) / 2, 1), 0, 0])
    p = legs(p, L=BR_ANK["L"], R=BR_ANK["R"], pole_L=(0, 1, 0), pole_R=(0, 1, 0), foot_yaw_L=90, foot_yaw_R=90)
    p = P(p, **open_hand(0.9)); J = joints(p)
    for s in "LR":
        sh = J[f"upperarm01.{s}"]; out = 1 if s == "R" else -1
        w = np.array([sh[0] + 0.95 * ARM * np.cos(np.radians(11)), FLOOR_SUP + 0.025, sh[2] + out * 0.95 * ARM * np.sin(np.radians(11))])
        p = fixed_hand(p, s, w, [1, 0, 0.12 * out], [0, -1, 0], (0, -0.5, out))
    return p
def bridge_line(phi):
    J = joints(bridge(phi)); a = J["upperleg01.L"] - J["spine01"]; b = J["lowerleg01.L"] - J["upperleg01.L"]
    return float(np.degrees(np.arctan2(b[1], b[0]) - np.arctan2(a[1], a[0])))
_lo, _hi = 10.0, 60.0
for _ in range(18):
    _m = (_lo + _hi) / 2
    if bridge_line(_m) > 0: _lo = _m
    else: _hi = _m
BRIDGE_TOP = (_lo + _hi) / 2
print("pont : angle du buste", round(BRIDGE_TOP, 1))
bridge_rest, bridge_up = bridge(0), bridge(BRIDGE_TOP)
motion("glute-bridge", [K(0, bridge_rest)] + planted(0, 1.5, lambda s: bridge(BRIDGE_TOP * s)) + [K(3.5, bridge_up)]
       + planted(3.5, 5.0, lambda s: bridge(BRIDGE_TOP * (1 - s))) + [K(5.6, bridge_rest)],
       muscles=("glutes", "hamstrings"), yaw=0, pitch=12, props=(MAT,))

# Rowing serviette : debout, un pied un peu avancé, posé sur la serviette, talons au sol, genoux souples (134–147°), buste à peine
# incliné (une vingtaine de degrés, depuis les hanches), dos long, poitrine ouverte, regard devant soi. La serviette passe à plat sous la voûte du pied avant ; chaque poing en tient un bout.
# Une serviette ne s'allonge pas : chaque poing reste à distance constante du point où son brin sort de sous le
# pied (il se déplace sur une sphère centrée sur ce point), des bras tendus vers l'avant jusqu'aux côtes basses,
# coudes en arrière, omoplates serrées.
from motion_eval import towel_segments, towel_grip, band_distance  # noqa: E402
ROW_LEAN = 17.0                                          # bassin ; avec la colonne, le buste penche de 22–24°
TOWEL_THICK = 0.005
ROW_TOWEL_W = 0.10                                       # largeur de la bande à plat : une serviette pliée en long
ROW_CX = -0.04 * S_HIP                                   # bassin un peu décalé vers la jambe arrière
ROW_STANCE = (0.02, 0.17, 0.13, 0.12)                    # pied avant (x, avancée), pied arrière (écart, recul) ; × S_HIP, S_LEG
# Pied avant presque sous le milieu du corps, pied arrière en retrait et sur le côté : les deux brins montent de part
# et d'autre du genou avant, et la cuisse de la jambe arrière reste derrière eux.
ROW_FEET = {"L": np.array([ROW_CX + ROW_STANCE[0] * S_HIP, FLOOR_ANKLE, ANK["L"][2] + ROW_STANCE[1] * S_LEG]),
            "R": np.array([ROW_CX - ROW_STANCE[2] * S_HIP, FLOOR_ANKLE, ANK["R"][2] - ROW_STANCE[3] * S_LEG])}
ROW_HIP = (0.045, -0.04)                                 # bassin : descente, recul (× S_LEG)
ROW_CURL = {f: 1.0 for f in range(2, 6)}                    # fermeture de chaque doigt autour de la serviette (1 : poing fermé)
def row_fist():
    d = {f"finger{f}-{p}": [0, 0, -70 * c] for f, c in ROW_CURL.items() for p in (1, 2, 3)}
    d["finger1-2"] = [0, 0, -30]; d["finger1-3"] = [0, 0, -40]
    return d
def row_body(u):
    p = P("stand", root={"rot": [["x", ROW_LEAN]], "offset": [ROW_CX, -ROW_HIP[0] * S_LEG, ROW_HIP[1] * S_LEG]},
          spine01=[-4 * u, 0, 0], neck01=[-10, 0, 0], head=[-5, 0, 0], clavicle=[0, 4 + 14 * u, -2 * u], **row_fist())
    return legs(p, L=ROW_FEET["L"], R=ROW_FEET["R"], pole_L=(0.0, 0, 1), pole_R=(-0.3, 0, 1))
FRONT_FOOT = region(("foot", "toes"), "L")
TOWEL_BACKS = []
def towel_vertices():
    """Sommets de la peau que la serviette relie : paume de chaque main, du côté de l'auriculaire, là où le brin entre
    dans le poing (et, juste en face, dos de la main : le bout du brin est tenu à quelques millimètres de la paume,
    dans le creux du poing), dessous de la voûte du pied avant."""
    v, n = MESH.v, MESH.n
    out, backs = [], []
    for s, sg in (("L", 1), ("R", -1)):
        w, f3 = ik.H[f"wrist.{s}"], ik.H[f"finger3-1.{s}"]
        f = f3 - w; palm = sg * np.cross(f, ik.H[f"finger2-1.{s}"] - ik.H[f"finger5-1.{s}"]); palm /= np.linalg.norm(palm)
        c = ik.H[f"finger5-1.{s}"] - 0.022 * f / np.linalg.norm(f) + 0.012 * palm
        idx = HAND_VERTS[s][((n[HAND_VERTS[s]] @ palm) > 0.5) & (_bone_weight(("wrist",), s)[HAND_VERTS[s]] > 0.85)]
        out.append(int(idx[np.argmin(np.linalg.norm(v[idx] - c, axis=1))]))
        # dos de la main : sommet de la même partie rigide (métacarpe), sur la droite qui traverse la main par la paume
        rigid = HAND_VERTS[s][(_bone_weight(("wrist",), s)[HAND_VERTS[s]] > 0.9) & ((n[HAND_VERTS[s]] @ palm) < -0.5)]
        rel = v[rigid] - v[out[-1]]; off = rel - np.outer(rel @ palm, palm)
        backs.append(int(rigid[np.argmin(np.linalg.norm(off, axis=1))]))
    TOWEL_BACKS[:] = backs
    a, t = ik.H["foot.L"], ik.H["toes.L"]
    c = np.array([(a[0] + t[0]) / 2, 0.0, a[2] + 0.45 * (t[2] - a[2])])
    idx = FRONT_FOOT[n[FRONT_FOOT, 1] < -0.6]
    i_foot = int(idx[np.argmin(np.linalg.norm(v[idx] - c, axis=1))])
    return [out[0], i_foot, out[1]]
TOWEL = dict(prop("towel", None, 0), vertices=towel_vertices(), width=ROW_TOWEL_W, thickness=TOWEL_THICK)
TOWEL.update(backs=list(TOWEL_BACKS), depth=0.009)
# Pied avant surélevé de l'épaisseur de la serviette : la voûte repose dessus, le pied arrière reste le point le plus bas.
for _ in range(4):
    _v = posed_skin(row_body(0))[0]; _f = _v[TOWEL["vertices"][1]]; _fv = _v[FRONT_FOOT]
    _zone = _fv[np.abs(_fv[:, 2] - _f[2]) < ROW_TOWEL_W / 2 + 0.005]
    ROW_FEET["L"][1] += TOWEL_THICK + _v[MESH.sample, 1].min() - _zone[:, 1].min()
# Points où la serviette sort de sous le pied : 12 mm à l'extérieur du contour du pied (jusqu'à 8 cm de haut), côté
# extérieur pour le brin de la main gauche, côté intérieur pour celui de la main droite.
_side = _zone[_zone[:, 1] < _zone[:, 1].min() + 0.08]
TOWEL["under"] = [[float(_side[:, 0].max() + 0.012 - _f[0]), 0.0], [float(_side[:, 0].min() - 0.012 - _f[0]), 0.0]]
def towel_points(pose):
    """Peau posée au sol (comme dans l'app) et tronçons de la serviette."""
    v = posed_skin(pose)[0]; v = v - [0, v[MESH.sample, 1].min(), 0]
    return v, towel_segments(TOWEL, v)
ROW_EXIT = [s[0] for s in towel_points(row_body(0))[1][::2]]          # sortie du brin gauche, du brin droit
ROW_HW, ROW_END = 0.10, (-0.12, 0.16)               # arrivée : demi-écart des poings, vers le ventre, sous les côtes
ROW_MID = (ROW_EXIT[0][0] + ROW_EXIT[1][0]) / 2      # poings placés de part et d'autre du pied avant
def grip_point(pose, s):
    """Bout du brin : dans le creux du poing, à `depth` de la paume (même calcul que l'app)."""
    v = posed_skin(pose)[0]; i = 0 if s == "L" else 1
    return towel_grip(v[TOWEL["vertices"][2 * i]], v[TOWEL["backs"][i]], TOWEL["depth"]) - [0, v[MESH.sample, 1].min(), 0]
def row_grips(u):
    """Position des creux des poings : sur la sphère centrée sur la sortie du brin, du départ bras tendus (u = 0)
    à l'arrivée contre les côtes basses (u = 1)."""
    J1 = joints(row_body(1)); J0 = joints(row_body(0)); out = {}
    for i, (s, sg) in enumerate((("L", 1), ("R", -1))):
        E = ROW_EXIT[i]
        b = np.array([ROW_MID + sg * ROW_HW, J1["spine03"][1] + ROW_END[0], J1["spine03"][2] + ROW_END[1]])
        L = np.linalg.norm(b - E)
        # départ : même longueur de brin, bras presque tendu, poing devant l'épaule
        sh = J0[f"upperarm01.{s}"]; x = ROW_MID + sg * (SH[0] + 0.02); reach = 0.96 * (ARM + ROW_FIST)
        r = np.sqrt(L ** 2 - (x - E[0]) ** 2)                            # cercle de la sphère dans le plan x
        lo, hi = 0.0, np.pi / 2                                         # angle depuis la verticale, vers l'avant
        for _ in range(40):
            m = (lo + hi) / 2
            a = np.array([x, E[1] + r * np.cos(m), E[2] + r * np.sin(m)])
            if np.linalg.norm(a - sh) < reach: lo = m
            else: hi = m
        da, db = (a - E) / L, (b - E) / L
        w = np.arccos(np.clip(da @ db, -1, 1))
        d = (np.sin((1 - u) * w) * da + np.sin(u * w) * db) / np.sin(w)
        out[s] = (E + L * d, E)
    return out
ROW_FIST = float(np.linalg.norm(MESH.v[TOWEL["vertices"][0]] - ik.H["wrist.L"]))     # du poignet au creux du poing
ROW_FINGER = {(s, f): np.where(sum(_bone_weight((f"finger{f}-{p}",), s) for p in (1, 2, 3)) > 0.5)[0] for s in "LR" for f in range(1, 6)}
ROW_PALM = {s: np.setdiff1d(HAND_VERTS[s], np.concatenate([ROW_FINGER[(s, f)] for f in range(1, 6)])) for s in "LR"}
def fist_gap(pose, parts):
    """Plus petit écart entre chaque brin et des parties de la main qui le tient (négatif : la bande traverse la peau)."""
    v, segs = towel_points(pose)
    return min(float(band_distance(segs[i], v[parts[s]])[0].min()) for i, s in ((0, "L"), (2, "R")))
def row(u):
    p = row_body(u); G = row_grips(u)
    for s, sg in (("L", 1), ("R", -1)):
        g, E = G[s]
        pole = (0.35 * sg, 0.25, -1)
        w = g - ROW_FIST * (g - joints(p)[f"upperarm01.{s}"]) / np.linalg.norm(g - joints(p)[f"upperarm01.{s}"])
        for _ in range(6):
            q = with_bones(p, ik.arm(p, s, w, pole)); J = joints(q)
            f = J[f"wrist.{s}"] - J[f"lowerarm01.{s}"]; f /= np.linalg.norm(f)      # poing dans l'axe de l'avant-bras…
            d = (E - g) / np.linalg.norm(E - g)                          # le brin sort du poing du côté de l'auriculaire
            # … à 20° près : le poignet s'incline pour que le brin sorte dans l'axe du creux du poing, en travers de la paume
            c = float(np.clip(d @ f, -1, 1)); e = d - f * c; e /= np.linalg.norm(e)
            a = float(np.clip(np.arcsin(c), -np.radians(20), np.radians(20)))
            f = np.cos(a) * f - np.sin(a) * e
            across = -(d - f * (d @ f)); across /= np.linalg.norm(across)
            q = fixed_hand(p, s, w, f, sg * np.cross(f, across), pole, flat=False)
            err = g - grip_point(q, s)
            if np.linalg.norm(err) < 2e-4: break
            w = w + err
        p = q
    return placed(grip_thumbs(p))
def towel_clearance(pose):
    """Plus petite distance entre les brins (bande réelle) et la peau : pied avant, tibias, genoux, cuisses, bras,
    autre main ; seul le poing qui tient le brin est exclu, sur ses 7 derniers centimètres."""
    v, segs = towel_points(pose); worst = 9.0
    for i, s in ((0, "L"), (2, "R")):
        d, along = band_distance(segs[i], v)
        held = np.zeros(len(v), bool)
        held[HAND_VERTS[s]] = along[HAND_VERTS[s]] > np.linalg.norm(segs[i][1] - segs[i][0]) - 0.07
        worst = min(worst, float(d[~held].min()))
    return worst
# Mains assez écartées pour que les brins passent à 6 mm au moins de la peau (genou et cuisse de la jambe avant).
ROW_US = np.linspace(0, 1, 11)
for _ in range(12):
    if min(towel_clearance(row(u)) for u in ROW_US) >= 0.006: break
    ROW_HW += 0.01
else:
    raise SystemExit(f"serviette : brins à moins de 6 mm de la peau, poings écartés de {ROW_HW:.2f} m de part et d'autre du pied")
# La serviette entre dans le poing sans traverser la peau : le bout du brin s'écarte de la paume jusqu'à la dégager
# (1,5 mm de jeu), puis chaque doigt se referme autour de la bande jusqu'à 1,5 mm d'elle, pas plus (l'auriculaire et
# l'annulaire l'entourent, les autres doigts ferment le poing). La prise est fixée au métacarpe : fermer plus ou
# moins les doigts ne la déplace pas.
ROW_GAP, _us = 0.0015, (0.0, 0.25, 0.5, 0.75, 1.0)
ROW_CURL.update({f: 0.2 for f in ROW_CURL})
for _ in range(4):
    TOWEL["depth"] = round(TOWEL["depth"] + ROW_GAP - min(fist_gap(row(u), ROW_PALM) for u in _us), 4)
_open = [row(u) for u in _us]
for _f in range(2, 6):
    _lo, _hi = 0.2, 1.0
    _fit = lambda c: min(fist_gap(P(q, **{f"finger{_f}-{p}": [0, 0, -70 * c] for p in (1, 2, 3)}), {s: ROW_FINGER[(s, _f)] for s in "LR"}) for q in _open)
    if _fit(1.0) >= ROW_GAP:
        _lo = 1.0
    else:
        for _ in range(7):
            _m = (_lo + _hi) / 2
            if _fit(_m) >= ROW_GAP: _lo = _m
            else: _hi = _m
    ROW_CURL[_f] = round(_lo, 3)
print("serviette : prise à", round(TOWEL["depth"] * 1000, 1), "mm de la paume, fermeture des doigts", ROW_CURL,
      "écart bande / main", [round(fist_gap(row(u), HAND_VERTS) * 1000, 1) for u in _us])
row_start, row_end = row(0), row(1)
print("serviette : demi-écart des poings", round(ROW_HW, 2), "dégagement", [round(towel_clearance(row(u)), 3) for u in (0, 0.5, 1)])
print("serviette : longueur des brins", [round(float(np.linalg.norm(row_grips(0)[s][0] - row_grips(0)[s][1])), 3) for s in "LR"],
      "pied avant surélevé de", round(float(ROW_FEET["L"][1] - FLOOR_ANKLE) * 1000, 1), "mm")
# Clés rapprochées : entre deux clés l'app interpole des angles, les poings s'écarteraient de leur sphère.
motion("towel-row", [K(0, row_start)] + planted(0, 1.5, row, n=10) + [K(2.3, row_end)] + planted(2.3, 3.6, lambda s: row(1 - s), n=10)
       + [K(4.0, row_start)], muscles=("upperBack", "biceps"), yaw=40, props=(TOWEL,))

# Gainage sur les genoux : épaules, hanches et genoux alignés (bassin légèrement rétroversé, ventre rentré), coudes sous
# les épaules, avant-bras et paumes à plat. L'inclinaison du corps et la hauteur des poignets sont résolues sur la peau :
# genoux, avant-bras et mains touchent le sol ensemble.
_KP_LEGS, _KP_FORE, _KP_HAND = region(("lowerleg", "upperleg")), region(("lowerarm",)), region(("finger", "wrist"))
FOREARM = float(np.linalg.norm(STAND["wrist.L"] - STAND["lowerarm01.L"]))
def knee_plank(x, breath=0.0, wrists=None):
    p = P("stand", root={"rot": [["x", float(x[0])], ["y", 90]]}, upperleg01=[6, 0, 0], lowerleg01=[70, 0, 0], foot=[30, 0, 0],
          spine05=[4, 0, 0], spine04=[2, 0, 0], spine01=[-2 * breath, 0, 0], neck01=[-8, 0, 0], **open_hand(1.0))
    floor = low_of(p, _KP_LEGS); J = joints(p)
    for s, sg in (("L", 1), ("R", -1)):
        sh = J[f"upperarm01.{s}"]
        w = wrists[s] if wrists else np.array([sh[0] + FOREARM, floor + float(x[1]), sh[2]])
        p = fixed_hand(p, s, w, [1, 0, 0], [0, -1, 0], (0, -1, -0.1 * sg))
    return p
def _kp_res(x):
    v = posed_skin(knee_plank(x))[0]; floor = v[_KP_LEGS, 1].min()
    return [(v[_KP_FORE, 1].min() - floor) * 100, (v[_KP_HAND, 1].min() - floor) * 100]
_kp = least_squares(_kp_res, [76.0, 0.03], x_scale=[1.0, 0.01], diff_step=[0.01, 0.05]).x
print("gainage : inclinaison, poignets", np.round(_kp, 3), "résidus", np.round(_kp_res(_kp), 2))
kplank = knee_plank(_kp)
_kw = {s: joints(kplank)[f"wrist.{s}"] for s in "LR"}
motion("knee-plank", [K(0, kplank), K(3, knee_plank(_kp, 1, _kw)), K(6, kplank)], muscles=("abs", "shoulders"), yaw=0, props=(MAT,))

# Mollets : montée sur la pointe des pieds. Les talons décollent en tournant autour de la base des orteils, qui restent
# à plat au même endroit ; le corps monte d'autant, d'un bloc (genoux tendus, bassin au-dessus de l'avant des pieds).
# Vu de près : des genoux au sol.
CALF_RISE = 34.0                                         # talons levés (degrés) : 8,2 cm (femme), 10,4 cm (homme)
CALF_PIVOT = 0.006 if BODY == "male" else 0.004          # pivot sous l'articulation des orteils, vers la peau de l'avant-pied (m)
def calf_raise(u):
    deg = CALF_RISE * u; c, sn = np.cos(np.radians(deg)), np.sin(np.radians(deg)); kw = {}; move = np.zeros(3)
    for s in "LR":
        toe = STAND[f"toes.{s}"] - [0, CALF_PIVOT, 0]; a = ANK[s] - toe
        t = toe + [a[0], a[1] * c - a[2] * sn + 0.005 * deg / MARCH_PEEL, a[1] * sn + a[2] * c]
        move = t - ANK[s]
        kw.update({s: t, f"foot_pitch_{s}": deg, f"toes_{s}": -deg})
    p = P("stand", root={"offset": [0.0, float(move[1]), float(move[2])]}, upperarm01=[-4 * u, 0, 4 * u], lowerarm01=[-8 * u, 0, 0])
    return legs(p, **kw)
_calf = calf_raise(1.0)
motion("calf-raises", [K(0, "stand")] + planted(0, 1.0, calf_raise, n=6) + [K(1.4, _calf)] + planted(1.4, 4.0, lambda s: calf_raise(1 - s), n=8)[:-1]
       + [K(4.0, "stand", "linear")],                         # dernière clé : la pose de départ (boucle fermée)
       muscles=("calves",), yaw=68, pitch=6)
close_up("calf-raises", ("wrist", "foot", "toes"), 0.05)

# Fentes douces : un pied avance et se pose, les deux genoux plient, retour ; puis l'autre jambe.
def lunge_keys(side, t0):
    o = other(side)
    def pose(front_dz, lift, cz, depth, rear_heel):
        front_dz, lift, cz, depth, rear_heel = (x * S_LEG for x in (front_dz, lift, cz, depth, rear_heel))
        p = P("handsHips", root={"offset": [0, -depth, cz]}, spine01=[-3, 0, 0])
        p = legs(p, **{side: ankle(side, dz=front_dz, lift=lift)}, **{f"pole_{side}": (0, 0, 1)})
        return legs(p, **{o: ankle(o, lift=rear_heel)}, **{f"pole_{o}": (0, -0.2, 1)},
                    **{f"foot_pitch_{o}": rear_heel * 420, f"toes_{o}": -rear_heel * 420})
    stand = pose(0, 0, 0, 0, 0)
    return [K(t0, stand), K(t0 + 0.6, pose(0.26, 0.07, 0.07, 0.01, 0.0)), K(t0 + 1.3, pose(0.52, 0, 0.2, 0.03, 0.03)),
            K(t0 + 2.3, pose(0.52, 0, 0.21, 0.13, 0.06)), K(t0 + 3.2, pose(0.52, 0, 0.21, 0.13, 0.06)),
            K(t0 + 4.0, pose(0.52, 0, 0.2, 0.03, 0.03)), K(t0 + 4.7, pose(0.26, 0.07, 0.07, 0.01, 0.0)), K(t0 + 5.4, stand)]
_l = lunge_keys("L", 0)
motion("gentle-lunge", _l + lunge_keys("R", 5.4)[1:], muscles=("quads", "glutes"), yaw=70)

# Étirement de la cuisse, debout : le genou plie, la main du même côté attrape le cou-de-pied et amène le talon vers la
# fesse, genoux côte à côte ; le pied d'appui reste posé, l'autre bras s'écarte un peu pour l'équilibre.
CHEST_IN = dict(spine01=[-3, 0, 0], spine02=[-2, 0, 0])      # inspiration sans bouger le regard
QUAD_HOLD = (0.28, 0.0)                                      # prise le long du pied (0 cheville, 1 orteils), décalage vers la pointe (m)
def quad_stretch(knee=150.0, hip=6.0, foot=38.0, u=1.0, grab=True, off=0.0, leg=None):
    """Côté gauche. knee, hip, foot : genou plié, cuisse en arrière (> 0) ou en avant, pointe tendue ; grab : main sur le pied ;
    off : main écartée du pied de cette distance, vers l'extérieur (elle s'en approche ou le lâche par le côté : le pied,
    qui redescend vers l'arrière, ne la rencontre pas) ; leg : angles de la jambe gauche à la place de knee, hip, foot."""
    p = P("stand", root={"offset": [-0.03 * S_HIP * u, 0, 0]}, upperleg01_L=[hip, 0, -3 * u], lowerleg01_L=[knee, 0, 0],
          foot_L=[foot, 0, 0], upperarm01_R=[0, 0, -14 * u], lowerarm01_R=[-10 * u, 0, 0], **open_hand(0.4, "R"))
    if leg is not None:
        p = P(p, **leg)
    p = legs(p, R=ankle("R"))
    if not grab:
        return P(p, upperarm01_L=[10 * u, 0, 20 * u], lowerarm01_L=[-12 * u, 0, 0])      # bras prêt, écarté du pied qui monte
    R, J = ik.fk(p); Rf = R["foot.L"]
    axis, top, inward = Rf @ [0, 0, 1.0], Rf @ [0, 1.0, 0], Rf @ [-1.0, 0, 0]
    mid = J["foot.L"] + QUAD_HOLD[0] * (J["toes.L"] - J["foot.L"])    # cou-de-pied, près de la cheville
    f = inward + 0.25 * axis; f /= np.linalg.norm(f)
    p = P(p, **{S(k, "L"): [x * 0.45 * max(0.0, 1 - off / 0.08) for x in v] for k, v in fist(1.0).items()})
    return hands(p, L=mid + top * (0.04 + 0.25 * off) - f * (0.12 + off) + axis * QUAD_HOLD[1], fingers_L=f, palm_L=-top, pole_L=(1, 0.1, -0.45))
QUAD_PEEL = (24.0, 0.02)                                     # talon levé (degrés), puis pied soulevé à la verticale (m)
_quad = quad_stretch()
_quad_r = mirror_pose(_quad)
def quad_foot(pitch, lift, u):
    """Pied gauche qui quitte le sol ou s'y pose : talon levé de « pitch » degrés autour de la base des orteils, qui
    restent à plat au même endroit, puis pied soulevé de « lift » mètres à la verticale, sans changer d'inclinaison."""
    toe = STAND["toes.L"]; a = ANK["L"] - toe; c, sn = np.cos(np.radians(pitch)), np.sin(np.radians(pitch))
    return legs(quad_stretch(0, 0, 0, u, False), L=toe + [a[0], a[1] * c - a[2] * sn + lift, a[1] * sn + a[2] * c],
                foot_pitch_L=pitch, toes_L=-pitch)
QUAD_BUMP = 32.0                                             # genou avancé à mi-chemin (degrés de cuisse vers l'avant)
QUAD_FLEX = 25.0                                             # pied moins tendu à mi-chemin (pas de pointe de « coup de pied »)
QUAD_GRIP = (0.78, 0.9)                                      # main ouverte à côté du pied, puis posée dessus (avancée « w »)
def quad_path(w):
    """Pied gauche entre « peel » (w = 0 : soulevé de 2 cm, talon levé) et le talon contre la fesse (w = 1 : la prise).
    Hanche, genou et pied passent d'une pose à l'autre, la cuisse avançant un peu en chemin (QUAD_BUMP) : le pied monte
    sous le corps, genou un peu devant (le genou plie surtout en fin de montée), sans passer loin derrière le corps. La
    main s'approche du cou-de-pied en fin de montée et le saisit ; au retour, elle le lâche près de la fesse et le pied
    redescend lentement par le même chemin, jusqu'à côté de l'autre. Lâché du talon haut (jambe repliée à 118°, cheville 38 cm en arrière), il
    décrivait un arc derrière le corps, comme un coup de pied, à 1,4 m/s ; entre deux clés éloignées, il passait
    derrière la jambe d'appui (jambes en ciseaux, vues de trois quarts arrière)."""
    g = lambda k: np.asarray(QUAD_FROM[k], float) * (1 - w) + np.asarray(QUAD_TO[k], float) * w
    wk = w ** 1.6                                            # le genou plie surtout en fin de montée : le pied reste sous le corps
    knee = np.asarray(QUAD_FROM["lowerleg01.L"], float) * (1 - wk) + np.asarray(QUAD_TO["lowerleg01.L"], float) * wk
    leg = dict(upperleg01_L=list(g("upperleg01.L") - [QUAD_BUMP * np.sin(np.pi * w), 0, 0]), lowerleg01_L=list(knee),
               foot_L=list(g("foot.L") - [QUAD_FLEX * np.sin(np.pi * w), 0, 0]), toes_L=list(g("toes.L")))
    u = 0.7 + 0.3 * w
    if w < QUAD_GRIP[0]:
        return quad_stretch(0, 0, 0, u, False, leg=leg)
    return quad_stretch(0, 0, 0, u, True, off=0.13 * max(0.0, (QUAD_GRIP[1] - w) / (QUAD_GRIP[1] - QUAD_GRIP[0])), leg=leg)
_qf = flatten(quad_foot(QUAD_PEEL[0], QUAD_PEEL[1], 0.7))["bones"]
QUAD_FROM = {k: _qf.get(k, [0.0, 0.0, 0.0]) for k in ("upperleg01.L", "lowerleg01.L", "foot.L", "toes.L")}
QUAD_TO = {"upperleg01.L": [6.0, 0.0, -3.0], "lowerleg01.L": [150.0, 0.0, 0.0], "foot.L": [38.0, 0.0, 0.0], "toes.L": [0.0, 0.0, 0.0]}
QUAD_PATH_N = 10
def quad_keys(t0, flip):
    f = mirror_pose if flip else (lambda p: p)
    # Le talon se lève à peine, orteils posés au même endroit ; le pied se soulève ensuite à la verticale, puis monte
    # en douceur jusqu'à la fesse, la main le saisissant en chemin (quad_path). Au retour, il redescend par le même
    # chemin, tenu jusqu'à mi-hauteur, ralentit et se pose à la verticale de son appui, à côté de l'autre pied, orteils
    # d'abord puis talon.
    half, heel = f(quad_foot(QUAD_PEEL[0] / 2, 0.0, 0.25)), f(quad_foot(QUAD_PEEL[0], 0.0, 0.5))
    peel = f(quad_foot(QUAD_PEEL[0], QUAD_PEEL[1], 0.7))
    ws = [0.5 * u + 0.5 * u * u * (3 - 2 * u) for u in (i / QUAD_PATH_N for i in range(1, QUAD_PATH_N))]
    path = [f(quad_path(w)) for w in ws]
    hold = f(_quad)
    # Montée en 2,6 s, descente en 2,6 s : le pied ne dépasse pas 0,8 m/s.
    return ([K(t0 + 0.2, half, "in"), K(t0 + 0.35, heel, "linear"), K(t0 + 0.5, peel, "linear")]
            + [K(t0 + 0.5 + 2.6 * (i + 1) / QUAD_PATH_N, q, "linear") for i, q in enumerate(path)]
            + [K(t0 + 3.1, hold, "out"), K(t0 + 5.3, hold)]
            + [K(t0 + 5.3 + 2.6 * (i + 1) / QUAD_PATH_N, q, "in" if i == 0 else "linear") for i, q in enumerate(path[::-1])]
            + [K(t0 + 8.05, peel, "linear"), K(t0 + 8.2, heel, "linear"), K(t0 + 8.35, half, "linear"), K(t0 + 8.55, "stand", "out")])
# Ouverture de la poitrine : omoplates serrées, bras tendus vers l'arrière et le bas, mains écartées paumes face à face
# Mains jointes derrière le dos, paume contre paume, bras tendus vers l'arrière et le bas (25° derrière la verticale,
# assez loin des fesses) ; omoplates serrées, épaules en arrière, poitrine soulevée (haut du dos en extension), tête
# droite : le cou rend l'extension du dos, le regard reste à l'horizontale. « breath » : inspiration, la poitrine monte
# encore un peu, la tête ne bouge pas.
CLASP_BACK = 25.0
CLASP_APART = [0.0]                                              # écart ajouté entre les poignets, réglé sur la peau plus bas
def chest_clasp(breath=0.0):
    ext = (3 + 2 * breath, 7 + 3 * breath)                           # extension du haut du dos (spine02, spine01)
    p = P("stand", clavicle=[0, 18, -3], spine02=[-ext[0], 0, 0], spine01=[-ext[1], 0, 0], neck01=[0.7 * sum(ext), 0, 0],
          head=[0.3 * sum(ext), 0, 0], **open_hand(1.0))
    J = joints(p); sh = (J["upperarm01.L"] + J["upperarm01.R"]) / 2
    a = np.radians(CLASP_BACK)
    l = np.sqrt((0.95 * ARM) ** 2 - float(J["upperarm01.L"][0]) ** 2)
    w = sh + l * np.array([0.0, -np.cos(a), -np.sin(a)])
    x = PALM + CLASP_APART[0]
    p = hands(p, L=w + [x, 0, 0], R=w - [x, 0, 0], fingers_L=[0, -1, -0.3], palm_L=[-1, 0, 0], fingers_R=[0, -1, -0.3],
              palm_R=[1, 0, 0], pole_L=(0.8, -0.2, -0.6), pole_R=(-0.8, -0.2, -0.6))
    p = joined_hands(p); p["_pinned"] = ["L", "R"]
    return p
def clasp_gap(p):
    """Écart signé entre les deux mains (négatif : elles s'interpénètrent)."""
    v, n = posed_skin(p)
    d, j = cKDTree(v[HAND_VERTS["R"]]).query(v[HAND_VERTS["L"]])
    sd = np.einsum("ij,ij->i", v[HAND_VERTS["L"]] - v[HAND_VERTS["R"]][j], n[HAND_VERTS["R"]][j])
    return float(np.where(d < 0.02, sd, d).min())
# Paumes l'une contre l'autre : écart des poignets réglé pour que les mains se touchent à 1 mm près, sans se traverser,
# à l'expiration comme à l'inspiration (les mains, les doigts et les pouces diffèrent d'un corps à l'autre).
_lo, _hi = -0.03, 0.04
for _ in range(14):
    CLASP_APART[0] = (_lo + _hi) / 2
    if min(clasp_gap(chest_clasp(b)) for b in (0.0, 1.0)) < 0.001: _lo = CLASP_APART[0]
    else: _hi = CLASP_APART[0]
CLASP_APART[0] = _hi
chest_open, _chest_in = chest_clasp(0.0), chest_clasp(1.0)
print("mains jointes dans le dos : écart des poignets", round(CLASP_APART[0] * 1000, 1), "mm, écart des mains",
      [round(clasp_gap(q) * 1000, 1) for q in (chest_open, _chest_in)], "mm")
_chest_way = P("stand", clavicle=[0, 8, 0], upperarm01=[12, 0, 32], lowerarm01=[-10, 0, 0], spine01=[-3, 0, 0])
# Vu presque de profil, un peu de l'arrière (105°), du côté gauche : le talon tenu contre la fesse se lit en entier des deux côtés (main sur le
# cou-de-pied), le profil montre la poitrine qui s'ouvre et les mains jointes derrière le dos.
motion("cooldown-stretch", [K(0, "stand")] + quad_keys(0, False) + quad_keys(8.55, True)
       + [K(18.0, _chest_way), K(18.8, chest_open), K(21.3, _chest_in), K(23.3, chest_open), K(24.1, _chest_way),
          K(24.9, "stand")], muscles=("quads", "chest"), yaw=105)

# ─── Mobilité, épaules, nuque ───
# Grands cercles d'épaules vers l'arrière : avant → haut → arrière → bas. Les bras restent pendants.
# Cercles amples (l'épaule décrit environ 9 cm de haut et 10 cm d'avant en arrière), vus de près : tête, épaules, haut
# du buste. « shoulder-rolls » tourne vers l'arrière ; « shoulder-rolls-both » fait deux cercles vers l'arrière puis
# deux vers l'avant.
def roll(theta):
    z = 9 + 17 * np.sin(theta)                # élévation
    y = -20 * np.cos(theta)                   # recul (> 0) ou avancée (< 0) de l'omoplate
    return P("stand", clavicle=[0, y, z], upperarm01=[0, -0.5 * y, -z + 3], lowerarm01=[-10, 0, 0], spine01=[0.12 * y, 0, 0],
             neck01=[-0.12 * y, 0, 0])
def both_ways(period, turns, n, build):
    """« turns » tours dans un sens puis autant dans l'autre (n clés par tour) ; le mouvement ralentit, s'arrête et
    repart en sens inverse sans à-coup."""
    span = period * turns; total = 2 * np.pi * turns; e = 0.12
    def angle(u):                                         # avancement 0 → 1 : départ et arrêt progressifs, vitesse constante entre
        v = 1 / (1 - e)
        if u < e: return v * u * u / (2 * e)
        if u > 1 - e: return 1 - v * (1 - u) ** 2 / (2 * e)
        return v * (u - e / 2)
    m = n * turns
    go = [K(span * i / m, build(total * angle(i / m)), "linear") for i in range(m + 1)]
    back = [K(span + span * i / m, build(total * angle(1 - i / m)), "linear") for i in range(1, m + 1)]
    return go + back
motion("shoulder-rolls", circle_keys(12, 4.2, roll), muscles=("shoulders", "upperBack"), yaw=50)
motion("shoulder-rolls-both", both_ways(4.2, 2, 12, roll), muscles=("shoulders", "upperBack"), yaw=50)
for _mid in ("shoulder-rolls", "shoulder-rolls-both"):
    close_up(_mid, ("head", "upperarm01", "lowerarm01"), 0.12)

shrug_up = dict(clavicle=[0, 0, 24], upperarm01=[0, 0, -22], lowerarm01=[-6, 0, 0])
# Haussements : les épaules montent en inspirant, tenues 3 secondes, puis tombent en expirant ; 8 fois dans l'étape
# de 60 secondes (boucle de 7,5 s).
motion("shrugs", [K(0, "stand"), K(1.2, P("stand", **shrug_up, neck01=[-2, 0, 0])), K(4.2, P("stand", **shrug_up)),
                  K(4.6, "stand", "out"), K(7.5, "stand")], muscles=("upperBack", "neck"), yaw=25)
_chair_shrug = keep_hands(P("chairSit", clavicle=[0, 0, 22]), "chairSit")
# Tempo de la consigne : épaules tenues 5 secondes vers les oreilles, puis elles tombent.
motion("chair-shrugs", [K(0, "chairSit"), K(1.2, _chair_shrug), K(6.2, _chair_shrug),
                        K(6.6, "chairSit", "out"), K(9.5, "chairSit")], muscles=("upperBack", "neck"), yaw=30, props=(CHAIR,))

def neck_tilt(base):
    tilt = lambda a: P(base, neck01=[0, 0, a * 0.35], neck02=[0, 0, a * 0.25], neck03=[0, 0, a * 0.2], head=[0, 0, a * 0.2])
    return [K(0, base), K(1.5, tilt(32)), K(3, tilt(32)), K(4.5, base), K(6, tilt(-32)), K(7.5, tilt(-32)), K(9, base)]
motion("neck-tilt", neck_tilt("stand"), muscles=("neck",), yaw=10)
# Menton rentré, vu de profil : la tête part d'une position un peu avancée (posture d'écran) et recule à l'horizontale,
# le bas du cou se redresse, le menton rentre (double menton) sans que le regard ne monte ni ne descende.
_chin0 = P("stand", neck01=[7, 0, 0], neck02=[3, 0, 0], head=[-10, 0, 0])
_chin1 = P("stand", neck01=[-15, 0, 0], neck02=[-7, 0, 0], neck03=[-2, 0, 0], head=[30, 0, 0], spine01=[-2, 0, 0])
motion("chin-tucks", [K(0, _chin0), K(1.2, _chin1), K(4.2, _chin1), K(5.2, _chin0), K(6.2, _chin0)], muscles=("neck",), yaw=90, pitch=4)
close_up("chin-tucks", ("head", "neck01", "upperarm01"), 0.17)       # tête, cou et épaules, de profil
_trap = P("stand", neck01=[0, 0, 12], neck02=[0, 0, 9], neck03=[0, 0, 7], head=[0, 0, 7], clavicle_L=[0, 0, -6], **open_hand(0.9, "R"))
_tr, _tp = ik.fk(_trap)
_hr = _tr["head"]
# Main droite posée sur le haut du crâne, doigts vers l'oreille gauche.
# Le sommet du crâne est lu sur la peau : l'objectif est pris juste dessous, la mise en contact pose la paume dessus.
_hd0 = region(("head",)); _hup = _hr @ [0, 1.0, 0]
_crown = float(((posed_skin(_trap)[0][_hd0] - _tp["head"]) @ _hup).max())
_tf = _hr @ [1, -0.5, 0]; _tf = _tf / np.linalg.norm(_tf)
trap = hands(_trap, R=_tp["head"] + _hup * (_crown - 0.012) - _tf * 0.075, fingers_R=_tf, palm_R=_hr @ [0.3, -1, 0], pole_R=(-1, 0.3, 0.2))
# Le bras monte par le côté, coude plié, avant de poser la main (et redescend de même).
_trap_way = hands(P("stand", **open_hand(0.9, "R")), R=[-float(SH[0] + 0.17), float(SH[1] + 0.12), float(SH[2] + 0.06)],
                  fingers_R=[0.5, 0.85, 0], palm_R=[0.85, -0.5, 0.1], pole_R=(-1, -0.4, 0.1))
_trap_off = hands(_trap, R=_tp["head"] + _hup * (_crown + 0.05) - _tf * 0.085, fingers_R=_tf, palm_R=_hr @ [0.3, -1, 0], pole_R=(-1, 0.3, 0.2))
# … puis s'écarte du crâne sur le côté avant de redescendre : en ligne droite vers l'épaule, elle frôlait la tempe.
_trap_out = hands(_trap, R=_tp["head"] + _hup * (_crown + 0.07) - _tf * 0.18, fingers_R=_tf, palm_R=_hr @ [0.3, -1, 0], pole_R=(-1, 0.3, 0.2))
def trap_keys(t0, flip):
    f = mirror_pose if flip else (lambda p: p)
    return [K(t0 + 0.8, f(_trap_way)), K(t0 + 1.3, f(_trap_out)), K(t0 + 1.65, f(_trap_off)), K(t0 + 2.0, f(trap)), K(t0 + 6.0, f(trap)),
            K(t0 + 6.35, f(_trap_off)), K(t0 + 6.7, f(_trap_out)), K(t0 + 7.2, f(_trap_way)), K(t0 + 8.0, "stand")]
motion("trap-stretch", [K(0, "stand")] + trap_keys(0, False) + trap_keys(8, True), muscles=("neck", "upperBack"), yaw=15)

# Ouverture de poitrine dans l'encadrement d'une porte : avant-bras sur les montants, le buste avance.
# Bras « en chandelier » : coudes à hauteur d'épaule, bras à l'horizontale sur les côtés, avant-bras à la verticale,
# posés à plat avec les paumes sur la face des montants. La porte est à la mesure de chaque corps : ses montants sont
# là où tombent les avant-bras (`width` : distance entre les axes des montants). Avant-bras et mains ne bougent plus ;
# le corps avance d'un bloc depuis les chevilles, pieds posés : les épaules passent de l'arrière à l'avant des coudes,
# les omoplates se serrent, la poitrine s'ouvre entre les montants (corps penché d'une dizaine de degrés en fin de
# course). Vue de face, un peu d'en haut : bras en chandelier (bras à l'horizontale, coudes à 90°, avant-bras
# verticaux), poitrine ouverte face à la caméra, les deux avant-bras visibles. Les avant-bras sont posés sur le bord
# intérieur de la face des montants qui regarde le personnage (`DOOR_EDGE`) : leur moitié côté passage dépasse du
# montant et se voit de face ; de trois quarts avant, le montant proche (12 cm de profondeur) cachait tout l'avant-bras,
# de profil les bras à l'horizontale, dirigés vers la caméra, se lisaient comme des bras levés à la verticale. Même
# cadrage pour les deux corps : de la tête et du bout des doigts jusqu'aux orteils.
UPPER_ARM = UPPER_ARM_LEN
DOOR_IN = 0.20 * S_LEG                                       # avancée du bassin
DOOR_RHYTHM = rhythm_amount(90.0)                            # bras à l'horizontale : la ceinture scapulaire suit un peu
_DOOR_ARM, _DOOR_HAND = region(("lowerarm",), "L"), region(("wrist", "finger"), "L")
def door_body(s):
    """s : 0 debout derrière la porte, 1 buste avancé ; épaules un peu enroulées au départ, omoplates serrées à la fin."""
    lean = DOOR_IN * s
    p = P("stand", root={"rot": [["x", 60 * lean]], "offset": [0, 0, lean]}, spine01=[-3 - lean * 40, 0, 0], clavicle=[0, -8 + 26 * s, 0],
          neck01=[-20 * lean, 0, 0], head=[-3, 0, 0], **open_hand(1.0))        # regard horizontal
    p = legs(p, L=ankle("L"), R=ankle("R"))
    for side in "LR":
        p = add_rhythm(p, side, DOOR_RHYTHM)
    return p
# Coude : à la hauteur de l'épaule, dans le plan des épaules à mi-course (en avant d'elles au départ, en arrière à la
# fin), aussi écarté que le bras le permet aux deux bouts de la course.
_dj = [joints(door_body(s))["upperarm01.L"] for s in (0.0, 0.5, 1.0)]
DOOR_ELBOW = np.array([0.0, float(_dj[1][1]) - 0.005, float(_dj[1][2])])
DOOR_ELBOW[0] = min(float(j[0] + np.sqrt(UPPER_ARM ** 2 - (j[1] - DOOR_ELBOW[1]) ** 2 - (j[2] - DOOR_ELBOW[2]) ** 2)) for j in _dj)
DOOR_DEPTH = [0.045, 0.035]                                  # de la face du montant à l'axe du coude, du poignet
def doorway(s, face=None):
    """face : profondeur (z) de la face des montants ; par défaut celle de la porte (DOOR_Z)."""
    face = DOOR_Z if face is None else face
    p = door_body(s)
    for side, sg in (("L", 1), ("R", -1)):
        elbow = np.array([sg * DOOR_ELBOW[0], DOOR_ELBOW[1], face - DOOR_DEPTH[0]])
        dz = DOOR_DEPTH[0] - DOOR_DEPTH[1]
        wrist = elbow + [0.0, float(np.sqrt(FOREARM ** 2 - dz ** 2)), dz]
        p = fixed_hand(p, side, wrist, [0, 1, 0], [0, 0, 1], tuple(elbow - joints(p)[f"upperarm01.{side}"]))
    return p
# Montants : l'axe de l'avant-bras est 1,5 cm à l'intérieur du bord du montant (7 cm de large) : l'avant-bras s'appuie
# sur le bord de la face par sa moitié extérieure, sa moitié intérieure dépasse dans le passage et se voit de face.
DOOR_EDGE = 0.015
DOOR_WIDTH = 2 * (float(DOOR_ELBOW[0]) + 0.035 + DOOR_EDGE)
# Avant-bras et paume réglés sur la peau : la partie posée sur le montant (au-delà de son bord intérieur) touche sa
# face (1 mm de jeu), sans la traverser.
_DOOR_IN = DOOR_WIDTH / 2 - 0.035
DOOR_Z = float(DOOR_ELBOW[2]) + DOOR_DEPTH[0]
for _ in range(5):
    _v = posed_skin(doorway(0.5))[0]
    _on = _v[:, 0] > _DOOR_IN
    DOOR_DEPTH[0] += float(_v[_DOOR_ARM[_on[_DOOR_ARM]], 2].max()) - DOOR_Z + 0.001
    DOOR_DEPTH[1] += float(_v[_DOOR_HAND[_on[_DOOR_HAND]], 2].max()) - DOOR_Z + 0.001
    DOOR_Z = float(DOOR_ELBOW[2]) + DOOR_DEPTH[0]
print("porte : entre les axes des montants", round(DOOR_WIDTH, 3), "coude", np.round(DOOR_ELBOW, 3), "profondeurs", np.round(DOOR_DEPTH, 3))
motion("doorway-stretch", [K(0, doorway(0.0))] + planted(0, 2, doorway, n=6) + [K(5, doorway(1.0))]
       + planted(5, 7, lambda s: doorway(1 - s), n=6) + [K(7.6, doorway(0.0))],
       muscles=("chest", "shoulders"), yaw=0, pitch=24,
       props=(dict(prop("door", "root", 0, (0, 0, DOOR_Z + 0.06 - float(STAND["root"][2])), floor=True), width=round(DOOR_WIDTH, 4)),))

# Cadrage : tout l'encadrement (linteau à 2,12 m) et le corps des orteils au bout des doigts, pour les deux corps. Vu de
# biais, le cadre de l'homme montre déjà le linteau à la marge minimale ; la marge de chaque corps est la plus petite
# qui le montre aussi (même calcul que l'app, CameraFraming) : personnage le plus grand possible, mêmes éléments à l'image.
from motion_eval import camera_shot  # noqa: E402
DOOR_TOP = 2.12
DOOR_FRAME = ("head", "finger3-3", "toes")
_door_keys = [[joints(k["pose"])[n] for n in ik.names] for k in MOTIONS["doorway-stretch"]["keys"]]
_door_ids = [ik.names.index(n) for j in DOOR_FRAME for n in (f"{j}.L", f"{j}.R") if n in ik.names] + \
            [ik.names.index(j) for j in DOOR_FRAME if j in ik.names]
_cam = MOTIONS["doorway-stretch"]["camera"]
for _m in np.arange(0.05, 0.6, 0.005):
    _c, _, _ext = camera_shot(_door_keys, _door_ids, _cam["yaw"], _cam["pitch"], _m)
    if _c[1] + _ext / 2 >= DOOR_TOP + 0.03: break
close_up("doorway-stretch", DOOR_FRAME, round(float(_m), 3))
print("porte : marge du cadrage", round(float(_m), 3))

squeeze = P("stand", clavicle=[0, 20, -2], upperarm01=[14, 14, 6], lowerarm01=[-20, 0, 0], spine01=[-5, 0, 0])
motion("scapular-squeeze", [K(0, "stand"), K(1, squeeze), K(5, squeeze), K(6, "stand")], muscles=("upperBack",), yaw=155)

# Cercles de hanches : le bassin dessine un cercle au-dessus des pieds, qui restent posés ; le haut du corps ne suit
# pas : la colonne se courbe à l'opposé (sur le côté, vers l'avant, vers l'arrière) juste assez pour que la tête reste
# à sa place, au-dessus des pieds, et le cou la garde droite. Deux tours dans un sens, deux dans l'autre.
HIP_R = 0.075 * S_LEG
HIP_SPINE = (("spine05", 0.3), ("spine04", 0.3), ("spine03", 0.25), ("spine02", 0.15))
_hip_head = STAND["head"]
def hip_circle(theta):
    ox, oz = HIP_R * np.cos(theta), HIP_R * np.sin(theta)
    def body(b):
        """b : courbure de la colonne (degrés) sur le côté et d'avant en arrière ; le bassin en prend le quart."""
        bones = {n: [b[1] * w, 0, b[0] * w] for n, w in HIP_SPINE}
        return P("handsHips", root={"rot": [["z", -0.25 * b[0]], ["x", 0.25 * b[1]]], "offset": [ox, -0.02 * S_LEG, oz]},
                 neck01=[-0.6 * b[1], 0, -0.6 * b[0]], head=[-0.65 * b[1], 0, -0.65 * b[0]], **bones)
    def miss(b):
        h = joints(body(b))["head"]
        return [(h[0] - _hip_head[0]) * 100, (h[2] - _hip_head[2]) * 100]
    b = fsolve(miss, [0.0, 0.0])
    # Les mains restent posées sur les hanches pendant que le bassin tourne.
    return keep_hands(legs(body(b), L=ankle("L"), R=ankle("R")), "handsHips")
motion("hip-circles", both_ways(4.8, 2, 12, hip_circle), muscles=("lowerBack", "abs", "glutes"), yaw=35)

# Cercles de cheville : main gauche à plat contre le mur, genou droit levé, la cheville dessine des cercles.
_ank_base = hands(P("stand", **open_hand(1.0, "L")), L=[float(SH[0] + 0.415), float(SH[1] - 0.02), -0.02], fingers_L=[0, 1, 0.1], palm_L=[1, 0, 0], pole_L=(0.2, -1, -0.4))
# La main reste à plat sur le mur. Un pied décolle (genou levé devant), la pointe dessine deux grands cercles, le pied
# se repose ; puis l'autre cheville. Le bassin se décale au-dessus du pied d'appui, qui ne bouge pas.
_aw = joints(_ank_base)["wrist.L"]; _af, _, _an = hand_axes(_ank_base, "L")
_ae = joints(_ank_base)["lowerarm01.L"] - joints(_ank_base)["upperarm01.L"]
_ank_top = {s: joints(P("stand", **{S("upperleg01", s): sided(s, [-42, 0, 2]), S("lowerleg01", s): [58, 0, 0]}))[f"foot.{s}"]
            + [(-0.035 if s == "L" else 0.035) * S_HIP, 0, 0] for s in "LR"}
def ankle_pose(side, up, theta=None):
    """up : 0 pieds posés, 1 genou levé ; theta : position de la pointe du pied sur son cercle."""
    sg = 1 if side == "L" else -1
    p = P("stand", root={"offset": [-sg * 0.035 * S_HIP * up, 0, 0]}, **open_hand(1.0, "L"))
    p = legs(p, **{other(side): ankle(other(side))})
    if up > 0.99:
        foot = [14, 0, 0] if theta is None else [14 + 24 * np.cos(theta), 30 * np.sin(theta), -12 * np.sin(theta)]
        p = P(p, **{S("upperleg01", side): sided(side, [-42, 0, 2]), S("lowerleg01", side): [58, 0, 0], S("foot", side): sided(side, foot)})
    else:
        # le pied décolle à la verticale puis avance : il ne glisse pas au sol
        a0, a1 = ankle(side), _ank_top[side]
        t = a0 + (a1 - a0) * [up ** 2, up, up ** 2]
        p = legs(p, **{side: t, f"foot_pitch_{side}": 30 * up})
    return fixed_hand(p, "L", _aw, _af, _an, tuple(_ae))
def ankle_keys(t0, side):
    lift = planted(t0, t0 + 0.8, lambda s: ankle_pose(side, s), n=3)
    turn = [K(t0 + 0.8 + 3.6 * i / 20, ankle_pose(side, 1, 2 * np.pi * i / 10), "linear") for i in range(1, 21)]
    return lift + [K(t0 + 1.0, ankle_pose(side, 1, 0.0))] + [dict(k, t=round(k["t"] + 0.2, 3)) for k in turn] \
        + planted(t0 + 4.8, t0 + 5.6, lambda s: ankle_pose(side, 1 - s), n=3)
_a0 = ankle_pose("R", 0)
_wall = float(posed_skin(_a0)[0][HAND_VERTS["L"], 0].max() - joints(_a0)["wrist.L"][0])         # mur au ras de la paume
# Corps entier, de trois quarts du côté du mur (35°) : la main posée à plat sur le mur se voit devant lui, et la jambe
# levée devant le corps. Cadrée des genoux au sol, l'image ne montrait ni la main ni le mur, qui semblait loin.
motion("ankle-circles", [K(0, _a0)] + ankle_keys(0, "R") + ankle_keys(5.6, "L"), muscles=("calves", "shins"), yaw=35, pitch=8,
       props=(prop("wall", "wrist.L", 0, (_wall, 0, -0.02), floor=True),))
close_up("ankle-circles", ("head", "wrist", "toes", "foot"), 0.12)          # de la tête aux orteils, main sur le mur comprise

# Inclinaison sur le côté : toute la colonne se courbe (bas du dos compris), bassin et jambes immobiles, pieds posés ;
# le buste (des hanches à la base du cou) s'incline d'environ 17° (SIDE_BEND : courbure totale de la colonne).
SIDE_SPLIT = (("spine05", 0.14), ("spine04", 0.2), ("spine03", 0.24), ("spine02", 0.22), ("spine01", 0.2))
SIDE_BEND = 27.0
side_bend = lambda a: P("stand", upperarm01=[0, 0, 168], lowerarm01=[-6, 0, 0], clavicle=[0, 0, 8], neck01=[0, 0, a * 0.08],
                        **{b: [0, 0, a * w] for b, w in SIDE_SPLIT}, **open_hand(0.9))
motion("overhead-stretch", [K(0, "stand"), K(2, side_bend(0)), K(4, side_bend(SIDE_BEND)), K(6, side_bend(0)), K(8, side_bend(-SIDE_BEND)), K(10, side_bend(0)), K(12, "stand")],
       muscles=("upperBack", "abs", "shoulders"), yaw=10)
# Les mains restent sur les hanches pendant que le haut du dos s'étire puis s'arrondit.
_ext = keep_hands(P("handsHips", spine04=[-5, 0, 0], spine03=[-5, 0, 0], spine02=[-4, 0, 0], neck01=[-8, 0, 0], head=[-8, 0, 0]), "handsHips")
_flex = keep_hands(P("handsHips", spine04=[8, 0, 0], spine03=[8, 0, 0], spine02=[8, 0, 0], neck01=[14, 0, 0], head=[10, 0, 0]), "handsHips")
motion("back-extension", [K(0, "handsHips"), K(2, _ext), K(4, "handsHips"), K(6, _flex),
                          K(8, "handsHips")], muscles=("lowerBack", "abs"), yaw=70)

# ─── Yoga (sur un tapis) ───
# Montagne : debout, grandi, paumes légèrement tournées vers l'avant.
mountain = P("stand", upperarm01=[0, 16, 5], lowerarm01=[-6, 0, 0], **open_hand(0.7))
motion("mountain", breathe(mountain, cycle=6), yaw=15, props=(MAT,))

# Salutation des bras : les bras montent devant soi jusqu'au-dessus de la tête, paumes jointes, puis redescendent.
arms_front_up = P(mountain, upperarm01=[-90, 0, 5], lowerarm01=[-4, 0, 0])
OVER_APART = 0.012                                         # poignets un peu écartés quand les bras sont tendus en haut
OVER_Z = OVERHEAD[1] + 0.035                              # un peu en avant du sommet du crâne : les bras passent devant les oreilles
def joined_up(p, x0, y, z, tilt=0.0, pole=0.0, apart=0.0):
    """Mains jointes en (x0, y, z), placées en miroir de part et d'autre, sans mise en contact séparée : elles restent
    jointes et symétriques. tilt : doigts inclinés vers l'avant ; pole : coudes vers le bas (< 0) ou sur les côtés (0) ;
    apart : écart ajouté entre les poignets (bras tendus au-dessus de la tête, les avant-bras se toucheraient avant les
    paumes : les mains se rejoignent alors par les doigts, en toit très fermé)."""
    for s, sg in (("L", 1), ("R", -1)):
        target = [x0 + sg * (PALM + apart), y, z]
        amt = rhythm_amount(arm_elevation(p, s, target))
        if amt > 0.02: p = add_rhythm(p, s, amt)
        p = ik.place_hand(p, s, target, [-sg * apart / 0.17, 1, tilt], [-sg, 0, 0], (sg, pole, -0.3))
    p = joined_hands(p); p["_pinned"] = ["L", "R"]
    return placed(p)
def overhead_y(pose, x0=0.0, reach=0.997):
    """Hauteur des poignets, mains jointes au-dessus de la tête, bras presque tendus (coude à 165–170°) le long des
    oreilles : mesurée depuis l'épaule une fois montée avec le bras (rythme scapulo-huméral), pas depuis l'épaule au repos
    (les mains arrivaient trop bas, coudes pliés à angle droit, bras en losange)."""
    y = OVERHEAD[0]
    for _ in range(4):
        t = [x0 + PALM, y, OVER_Z]
        sh = joints(add_rhythm(pose, "L", rhythm_amount(arm_elevation(pose, "L", t))))["upperarm01.L"]
        y = float(sh[1] + np.sqrt((reach * ARM) ** 2 - (sh[0] - t[0]) ** 2 - (sh[2] - t[2]) ** 2))
    return y
_up = P(mountain, spine01=[-2, 0, 0], neck01=[-2, 0, 0], head=[-2, 0, 0], **open_hand(1.0))
salute = joined_up(_up, 0.0, overhead_y(_up), OVER_Z, apart=OVER_APART)
# Entre l'horizontale et le haut, les bras passent devant (bras à 135°, dans le plan des épaules) : interpolés directement,
# ils s'ouvraient en V sur les côtés.
arms_front_high = P(mountain, upperarm01=[-135, 0, 4], lowerarm01=[-3, 0, 0], **open_hand(1.0))
# Montée et descente : les deux bras tendus, parallèles, dans le plan de chaque épaule (direction placée à chaque clé,
# `raise_arms`) ; interpolés en angles depuis les bras le long du corps, ils s'ouvraient en V et, vus de trois quarts,
# le bras proche semblait plié, main devant la poitrine. Montée qui part doucement et arrive lancée à 135°, puis les
# mains se joignent en haut ; descente symétrique, qui ralentit jusqu'aux bras le long du corps.
RAISE_TOP = 135.0
def raise_arms(theta):
    """Bras tendus devant soi, parallèles : theta = 0 le long du corps, 90 à l'horizontale, 135 en haut devant."""
    p = P(mountain, upperarm01=[-theta, 0, 5], lowerarm01=[-4, 0, 0], **open_hand(min(1.0, 0.7 + theta / 300)))
    t = np.radians(theta)
    for s, sg in (("L", 1), ("R", -1)):
        p = reach_arm(p, s, [0.03 * sg, -np.cos(t), np.sin(t)], 0.995, (0.3 * sg, -1, -0.4))
    return p
_RAISE_N = 8
_rise = [K(3.4 * i / _RAISE_N, raise_arms(RAISE_TOP * (1 - np.cos(np.pi / 2 * i / _RAISE_N))), "linear") for i in range(1, _RAISE_N + 1)]
_lower = [K(6.4 + 3.0 * i / _RAISE_N, raise_arms(RAISE_TOP * (1 - np.sin(np.pi / 2 * i / _RAISE_N))), "linear") for i in range(_RAISE_N)]
motion("arm-raise", [K(0, mountain)] + _rise + [K(4.2, salute, "out"), K(5.6, salute)] + [K(6.4, _lower[0].get("pose"), "in")] + _lower[1:]
       + [K(9.4, mountain, "out"), K(10.4, mountain)],
       muscles=("shoulders",), yaw=60, props=(MAT,))

# Flexion avant douce, en enroulant le dos : le menton descend vers la poitrine, le haut du dos s'arrondit, puis le bas
# du dos, et le bassin bascule en dernier (il recule un peu, genoux fléchis, pieds posés) ; tête et bras pendent,
# relâchés. Remontée en déroulant, dans l'ordre inverse : le bassin se redresse d'abord, la tête remonte en dernier.
def fold(s):
    """s : 0 debout, 1 flexion complète ; chaque étage du dos s'enroule à son tour."""
    def part(a, b):
        u = float(np.clip((s - a) / (b - a), 0, 1)); return u * u * (3 - 2 * u)
    h, up, low, u = part(0.0, 0.4), part(0.08, 0.6), part(0.25, 0.85), part(0.35, 1.0)
    p = P("stand", root={"rot": [["x", 62 * u]], "offset": [0, -0.07 * S_LEG * u, -0.11 * S_LEG * u]}, spine05=[7 * low, 0, 0], spine04=[11 * low, 0, 0],
          spine03=[13 * up, 0, 0], spine02=[12 * up, 0, 0], spine01=[10 * up, 0, 0], neck01=[18 * h, 0, 0], neck02=[12 * h, 0, 0], neck03=[8 * h, 0, 0],
          head=[14 * h, 0, 0], clavicle=[0, -8 * up, 0], **open_hand(0.5))
    p = legs(p, L=ankle("L"), R=ankle("R"), pole_L=(0.1, 0, 1), pole_R=(-0.1, 0, 1))
    J = joints(p)
    for sd, sg in (("L", 1), ("R", -1)):
        sh = J[f"upperarm01.{sd}"]
        w = [sh[0] + 0.02 * sg, max(sh[1] - 0.975 * ARM, 0.21), sh[2] + 0.01]              # bras à la verticale sous l'épaule ; doigts au ras du sol
        p = with_bones(p, ik.arm(p, sd, w, (sg, 0, -0.4)))
    return p
_fold = fold(1.0)
motion("forward-fold", [K(0, mountain)] + [K(3.2 * i / 10, fold(i / 10), "linear" if i > 1 else "in") for i in range(1, 10)] + [K(3.2, _fold, "out"), K(6, _fold)]
       + [K(6 + 3.4 * i / 10, fold(1 - i / 10), "linear" if i > 1 else "in") for i in range(1, 10)] + [K(9.4, mountain, "out"), K(10, mountain)],
       muscles=("hamstrings", "lowerBack"), yaw=70, props=(MAT,))

# Guerrier II : pieds très écartés, genou avant plié au-dessus de la cheville, bras à l'horizontale, regard sur la main avant.
# Le bassin descend aussi bas que le permet la jambe arrière tendue (WAR_BACK de sa longueur) ; il se décale vers la
# jambe avant jusqu'à ce que le genou avant soit au-dessus de la cheville (`war_root`). L'écart des pieds (WAR_STANCE)
# règle alors la cuisse avant : 12 à 15° sous l'horizontale. La tête tourne de 87° vers la main avant.
WAR_STANCE = 0.66                                            # demi-écart des chevilles (× S_LEG)
WAR_BACK = min(0.997, LEG_STAND + 0.004)                     # jambe arrière tendue (part de sa longueur ; debout : LEG_STAND)
WAR_LOOK = 87.0
WAR_TOE_IN = 12.0                                            # pied arrière (et les deux pieds au départ) : pointe un peu en dedans
WAR_ARM0 = 20.0                                              # bras écartés des cuisses jambes écartées (degrés)
WAR_LIFT = 0.025                                             # le pied avant se soulève de 2,5 cm pour tourner
def war_legs(root_dx, root_dy, bend, turn=None, lift=0.0):
    """turn : pied avant tourné vers l'extérieur (0 : pointe en dedans comme l'autre, 1 : à 90°) ; lift : pied avant
    soulevé (m) : il tourne en l'air, pas sur le sol."""
    turn = min(1, bend * 1.6) if turn is None else turn
    p = P("stand", root={"offset": [root_dx, root_dy, 0]},
          upperarm01=[0, 0, WAR_ARM0 + (86 - WAR_ARM0) * min(1, bend * 1.6)], lowerarm01=[-3, 0, 0], **open_hand(1.0),
          neck01=[0, 0.35 * WAR_LOOK * bend, 0], neck02=[0, 0.25 * WAR_LOOK * bend, 0], head=[0, 0.4 * WAR_LOOK * bend, 0])
    # écart symétrique : les pieds restent aux mêmes endroits quand on change de côté
    front = np.array([WAR_STANCE * S_LEG, FLOOR_ANKLE, ANK["L"][2]]); back = np.array([-WAR_STANCE * S_LEG, FLOOR_ANKLE, ANK["R"][2]])
    # genou avant tourné avec le pied (dans l'axe du pied tourné, au-dessus des orteils ; droit devant au départ)
    return legs(p, L=front + [0, lift, 0], R=back, pole_L=(turn, 0, 1 - turn), pole_R=(0, 0, 1),
                foot_yaw_L=-WAR_TOE_IN + (90 + WAR_TOE_IN) * turn, foot_yaw_R=WAR_TOE_IN)
def war_root_dy(dx):
    """Descente du bassin pour que la jambe arrière soit tendue à WAR_BACK de sa longueur."""
    J = joints(P("stand", root={"offset": [dx, 0.0, 0]}))
    back = np.array([-WAR_STANCE * S_LEG, FLOOR_ANKLE, ANK["R"][2]]); hip = J["upperleg01.R"]
    h = np.sqrt((WAR_BACK * LEG_MAX) ** 2 - (hip[0] - back[0]) ** 2 - (hip[2] - back[2]) ** 2)
    return float(back[1] + h - hip[1])
def war_root():
    """Décalage du bassin (x) qui met le genou avant au-dessus de la cheville, la jambe arrière restant tendue."""
    lo, hi = 0.0, 0.3 * S_LEG
    for _ in range(30):
        dx = (lo + hi) / 2
        J = joints(war_legs(dx, war_root_dy(dx), 1.0))
        if J["lowerleg01.L"][0] < J["foot.L"][0]: lo = dx
        else: hi = dx
    return dx
WAR_DX = war_root()
print("guerrier II : jambe arrière", round(WAR_BACK, 4), "(debout", round(LEG_STAND, 4), ") bassin décalé de", round(WAR_DX, 3))
def warrior(bend, turn=None, lift=0.0):
    """bend = 0 : jambes tendues, pieds écartés ; 1 : guerrier II (côté gauche devant)."""
    dx = WAR_DX * bend
    return war_legs(dx, war_root_dy(dx), bend, turn, lift)
def warrior_keys(t0, f):
    """Un côté : le pied avant se soulève, tourne vers l'extérieur en l'air et se repose ; le genou plie, pieds posés
    (clés rapprochées, `planted`) ; trois respirations ; retour dans l'ordre inverse. Le pied tournait auparavant sur le
    sol (il glissait de 12 à 34 mm) et le côté gauche finissait pied droit tourné : la boucle ne se refermait pas."""
    up = WAR_LIFT * S_LEG
    turn = [K(t0 + 0.5, f(warrior(0, 0, up))), K(t0 + 0.9, f(warrior(0, 0.5, up)), "linear"), K(t0 + 1.3, f(warrior(0, 1, up))),
            K(t0 + 1.7, f(warrior(0, 1, 0)))]
    back = [K(t0 + 9.6, f(warrior(0, 1, up))), K(t0 + 10.0, f(warrior(0, 0.5, up)), "linear"), K(t0 + 10.4, f(warrior(0, 0, up))),
            K(t0 + 10.7, w0)]                                   # pose de départ (bras du corps au repos, pas leur miroir) : la boucle se referme
    return (turn + planted(t0 + 1.7, t0 + 3.6, lambda u: f(warrior(u, 1)), n=6)
            + [K(t0 + 5.6, f(P(wl, **CHEST_IN))), K(t0 + 7.6, f(wl))]
            + planted(t0 + 7.6, t0 + 9.3, lambda u: f(warrior(1 - u, 1)), n=6) + back)
wl = warrior(1.0); wt = warrior(0.45); w0 = warrior(0.0)
wr, wrt, w0r = mirror_pose(wl), mirror_pose(wt), mirror_pose(w0)
motion("warrior-two", [K(0, w0)] + warrior_keys(0, lambda q: q) + warrior_keys(10.7, mirror_pose),
       muscles=("quads", "glutes", "shoulders"), yaw=6, props=(MAT,))

# Arbre : en équilibre sur la jambe gauche, plante du pied droit à plat contre l'intérieur du mollet, orteils vers le
# bas, tout le pied sous le genou (jamais sur le genou). Mains jointes devant la poitrine, puis au-dessus de la tête.
TREE_SHIFT = 0.075 * S_HIP
TREE_FOOT = np.array([[0, -1, 0], [0, 0, -1], [1, 0, 0]], float)      # orteils vers le bas, plante vers la jambe d'appui
_legL, _footR = region(("upperleg", "lowerleg", "foot", "toes"), "L"), region(("foot", "toes"), "R")
def foot_gap(pose):
    """Écart entre le pied droit et la jambe gauche (négatif : enfoncé)."""
    v, n = posed_skin(pose); fv = v[_footR]
    dist, j = cKDTree(v[_legL]).query(fv)
    depth = -np.einsum("ij,ij->i", fv - v[_legL][j], n[_legL][j])
    near = dist < 0.04
    return float(-depth[near].max()) if near.any() else float(dist.min())
def tree_legs(lifted, away=0.0):
    p = P(mountain, root={"offset": [TREE_SHIFT if lifted else 0.0, 0, 0]})
    p = legs(p, L=ankle("L"), R=None if lifted else ankle("R"))
    if not lifted:
        return p
    knee = joints(p)["lowerleg01.L"]
    def place(x):
        return legs(p, R=[x, knee[1] - 0.15 * S_LEG, knee[2] + 0.005], pole_R=(-1, -0.15, 0.4), foot_rot_R=TREE_FOOT)
    lo, hi = knee[0] - 0.20, knee[0]                                    # du plus écarté au plus enfoncé
    for _ in range(10):
        m = (lo + hi) / 2
        if foot_gap(place(m)) > -0.004: lo = m
        else: hi = m
    return place(lo - away)
_tree0, _tree1 = tree_legs(False), tree_legs(True)
TREE_TOP = overhead_y(P(_tree1, spine01=[-2, 0, 0]), float(joints(_tree1)["spine01"][0]))
def tree_arms(p, u):
    """u : 0 mains jointes devant la poitrine, 1 au-dessus de la tête ; les mains montent jointes devant le visage."""
    x0 = joints(p)["spine01"][0]
    y = CHEST[0] + (TREE_TOP - CHEST[0]) * u
    z = CHEST[1] + (OVER_Z - CHEST[1]) * u + 0.12 * np.sin(np.pi * u) ** 2
    p = P(p, **open_hand(1.0))
    if u > 0.5: p = P(p, spine01=[-2 * (2 * u - 1), 0, 0], neck01=[-2 * (2 * u - 1), 0, 0], head=[-2 * (2 * u - 1), 0, 0])
    # Les deux mains sont placées en miroir autour du sternum : elles restent jointes et symétriques pendant toute la montée.
    return joined_up(p, x0, y, z, 0.25 * (1 - u), -0.5 * (1 - u), apart=OVER_APART * u * u)
_prayer0 = tree_arms(_tree1, 0)
TREE_LIFT = 0.06 * S_LEG
def tree_shift(s, lift=0.0, arms=0.0):
    """Le poids passe sur la jambe gauche (s : 0 → 1), les deux pieds posés ; puis le pied droit se soulève à la
    verticale de son appui (« lift ») : il ne glisse pas au sol en partant vers le mollet. arms : mains vers la poitrine."""
    p = P(blend(_tree0, _prayer0, arms), root={"offset": [TREE_SHIFT * s, 0, 0]})
    return legs(p, L=ankle("L"), R=ankle("R", lift=lift))
def tree_keys(flip, t0):
    f = (lambda p: placed(mirror_pose(p)) if is_placed(p) else mirror_pose(p)) if flip else (lambda p: p)
    prayer, up = f(_prayer0), f(tree_arms(_tree1, 1))
    # Le pied arrive contre le mollet par le côté (et le quitte de même) : en ligne droite, il traverserait la jambe d'appui.
    near = P(blend(_tree0, _prayer0, 0.75), root={"offset": [TREE_SHIFT, 0, 0]})
    near = f(legs(near, L=ankle("L"), R=joints(tree_legs(True, away=0.07))["foot.R"], pole_R=(-1, -0.15, 0.4), foot_rot_R=TREE_FOOT))
    lifted = f(tree_shift(1, TREE_LIFT, 0.4))
    shift_in = planted(t0, t0 + 0.5, lambda s: f(tree_shift(s, 0.0, 0.2 * s)), n=4)
    put_down = planted(t0 + 10.95, t0 + 11.2, lambda s: f(tree_shift(1, TREE_LIFT * (1 - s), 0.4 - 0.2 * s)), n=2)
    shift_out = planted(t0 + 11.2, t0 + 11.6, lambda s: f(tree_shift(1 - s, 0.0, 0.2 * (1 - s))), n=4)
    rise = planted(t0 + 2.6, t0 + 4.2, lambda s: f(tree_arms(_tree1, s)), n=6)
    fall = planted(t0 + 7.8, t0 + 9.2, lambda s: f(tree_arms(_tree1, 1 - s)), n=6)
    return ([K(t0, f(_tree0))] + shift_in + [K(t0 + 0.85, lifted), K(t0 + 1.25, near), K(t0 + 1.7, prayer), K(t0 + 2.6, prayer)] + rise
            + [K(t0 + 6.0, P(up, **BREATH_IN)), K(t0 + 7.8, up)] + fall
            + [K(t0 + 10.2, prayer), K(t0 + 10.6, near), K(t0 + 10.95, lifted)] + put_down + shift_out)
motion("tree-pose", tree_keys(False, 0) + tree_keys(True, 11.6)[1:], muscles=("calves", "glutes", "abs"), yaw=12, props=(MAT,))

# ─── Au sol ───
# Chat-vache : mains et genoux restent posés, bras tendus ; la colonne s'arrondit vers le haut (tête rentrée) puis
# se creuse (tête relevée). Le bassin est résolu pour que les hanches restent au-dessus des genoux et les épaules
# à longueur de bras des mains.
_q = joints("quadruped")
QW = {s: _q[f"wrist.{s}"].copy() for s in "LR"}
QA = {s: _q[f"foot.{s}"].copy() for s in "LR"}
_qr = ik.fk("quadruped")[0]
QHAND = {s: hand_axes("quadruped", s) for s in "LR"}
QARM = float(np.linalg.norm(_q["upperarm01.L"] - QW["L"]))
def quad(curve, neck, head, clav, share=(0.24, 0.24, 0.22, 0.18, 0.12)):
    """curve : flexion totale de la colonne (> 0 dos rond) ; clav : omoplates écartées (< 0) ou serrées (> 0) ;
    share : part de chaque étage, du bas du dos (spine05) au haut (spine01)."""
    sp = {f"spine0{5 - i}": [curve * w, 0, 0] for i, w in enumerate(share)}
    def body(x):
        return P("quadruped", root={"rot": [["x", 78 + x[0]], ["y", 90]], "offset": [float(x[1]), float(x[2]), 0.0]}, **sp,
                 neck01=[-6 + neck, 0, 0], head=[head, 0, 0], clavicle=[0, clav, 0])
    def res(x):
        J = joints(body(x)); h = J["upperleg01.L"] - _q["upperleg01.L"]
        return [h[0], h[1], np.linalg.norm(J["upperarm01.L"] - QW["L"]) - QARM]
    x = fsolve(res, [-curve / 2, 0, 0])
    p = legs(body(x), L=QA["L"], R=QA["R"], pole_L=(1, -1, 0), pole_R=(1, -1, 0), foot_rot_L=_qr["foot.L"], foot_rot_R=_qr["foot.R"])
    for s in "LR":
        p = fixed_hand(p, s, QW[s], QHAND[s][0], QHAND[s][2], (-1, 0, 0))
    return p
# Appuis réglés sur la peau : paumes, genoux et dessus des pieds touchent le sol ensemble.
_v = posed_skin(quad(0, 0, 0, 0))[0]
_knee = _v[region(("lowerleg", "upperleg")), 1].min()
for s in "LR":
    QW[s][1] += _knee - _v[region(("finger", "wrist"), s), 1].min()
    QA[s][1] += _knee - _v[region(("foot", "toes"), s), 1].min()
# Vache : le bassin bascule, le ventre descend (creux surtout lombaire), la poitrine avance ; le regard monte à peine,
# la nuque prolonge la colonne (pas de tête renversée).
COW_SHARE = (0.32, 0.27, 0.2, 0.13, 0.08)
def catcow(u):
    """u : −1 vache (dos creux, regard un peu vers l'avant), 0 dos plat, 1 chat (dos rond, menton rentré)."""
    if u >= 0:
        return quad(72 * u, 24 * u, 22 * u, -12 * u)
    return quad(COW_CURVE * u, COW_NECK * u, COW_HEAD * u, -8 * u, tuple(a + (b - a) * -u for a, b in zip((0.24, 0.24, 0.22, 0.18, 0.12), COW_SHARE)))
COW_CURVE, COW_NECK, COW_HEAD = 62.0, 16.0, 10.0
neutral, cat, cow = catcow(0), catcow(1), catcow(-1)
motion("cat-cow", [K(0, neutral)] + planted(0, 2.5, lambda s: catcow(s)) + planted(2.5, 5, lambda s: catcow(1 - s))
       + planted(5, 7.5, lambda s: catcow(-s)) + planted(7.5, 10, lambda s: catcow(s - 1)),
       muscles=("lowerBack", "abs"), yaw=0, props=(MAT,))

# Posture de l'enfant : tibias et dessus des pieds au sol, fesses vers les talons, dos rond, front posé sur le tapis,
# bras allongés devant, paumes au sol. Le bassin et le pli des hanches sont résolus sur la peau (front, genoux et
# pieds touchent le sol ensemble).
_hj = ik.H["head"]
_hd = region(("head",))
FOREHEAD = _hd[(MESH.v[_hd, 2] > _hj[2] + 0.07) & (MESH.v[_hd, 1] > _hj[1] + 0.105) & (MESH.v[_hd, 1] < _hj[1] + 0.17)]
_shin, _feet = region(("lowerleg",)), region(("foot", "toes"))
CHILD_KNEE, CHILD_CURVE, CHILD_NECK, CHILD_ABD = 156.0, 46.0, 16.0, -3.0
CHILD_ROT = 13.0
CHILD_YAW, CHILD_PITCH = -40, 22
def child_body(pitch, hip, foot, extra=(0, 0, 0, 0, 0)):
    """extra : flexion ajoutée au bas du dos, au milieu du dos, au haut du dos, au cou, à la tête (degrés)."""
    extra = tuple(extra) + (0,) * (5 - len(extra))
    w = (0.2, 0.24, 0.24, 0.2, 0.12)
    sp = {f"spine0{5 - i}": [CHILD_CURVE * w[i], 0, 0] for i in range(5)}
    sp["spine05"][0] += extra[0]; sp["spine03"][0] += extra[1]; sp["spine01"][0] += extra[2]
    return P("stand", root={"rot": [["x", pitch], ["y", 90]]}, upperleg01=[-hip, CHILD_ROT, CHILD_ABD], lowerleg01=[CHILD_KNEE, 0, 0], foot=[foot, 0, 0],
             **sp, neck01=[CHILD_NECK * 0.5 + extra[3], 0, 0], head=[CHILD_NECK * 0.5 + extra[4], 0, 0])
def child_res(x):
    v = posed_skin(child_body(x[0], x[1], x[2]))[0]
    knee = v[_shin, 1].min()
    return [(v[FOREHEAD, 1].min() - knee) * 100, (v[_feet, 1].min() - knee) * 100, (v[_shin, 1].max() - knee - CHILD_SHIN) * 100]
_st = posed_skin(P("stand"))[0]
CHILD_SHIN = float(np.ptp(_st[_shin, 2])) + 0.004               # tibia couché : épaisseur du mollet au-dessus du sol
_sol = least_squares(child_res, [70.0, 130.0, 76.0], bounds=([30, 90, 55], [110, 170, 90]), diff_step=0.01).x
print("enfant : bassin, hanches, pieds", np.round(_sol, 1), "résidus", np.round(child_res(_sol), 2))
# Respiration « dans le dos » : le milieu du dos s'arrondit (CHILD_BREATH degrés de plus), le bas et le haut du dos, le cou
# et la tête rendent la courbure pour que le point du front posé au sol ne bouge pas (la tête roule à peine sur le front) ;
# bassin, jambes et mains restent en place. Le dos monte d'environ 2,5 cm (avec la tête tenue fixe, 5 mm à peine).
CHILD_BREATH = 20.0
def child_breath(breath):
    v0 = posed_skin(child_body(*_sol))[0]
    fi = FOREHEAD[np.argmin(v0[FOREHEAD, 1])]
    def res(d):
        v = posed_skin(child_body(*_sol, extra=(d[0], CHILD_BREATH * breath, d[1], d[2], d[3])))[0]
        return list((v[fi, [0, 1]] - v0[fi, [0, 1]]) * 100) + [0.02 * x for x in d]
    d = least_squares(res, [-2.0, -2.0, 0.0, 0.0], diff_step=1e-3).x
    assert np.abs(res(d)[:2]).max() < 0.05, res(d)                  # front fixe à 0,5 mm près
    return (d[0], CHILD_BREATH * breath, d[1], d[2], d[3])
def child_pose(breath=0.0):
    p = child_body(*_sol, extra=child_breath(breath)) if breath else child_body(*_sol)
    floor = posed_skin(child_body(*_sol))[0][_shin, 1].min()
    p = P(p, **open_hand(1.0)); wy = floor + 0.024
    def reach(q, fixed=None):
        kw = {}
        for s, sg in (("L", 1), ("R", -1)):
            sh = joints(q)[f"upperarm01.{s}"]
            d = np.sqrt((0.96 * ARM) ** 2 - (sh[1] - wy) ** 2)              # bras allongés jusqu'au sol, coudes à peine pliés (de quoi suivre le dos qui monte sans que les mains glissent)
            w = fixed[s] if fixed is not None else [sh[0] + d, wy, sh[2]]
            kw.update({s: w, f"fingers_{s}": [1, 0, 0], f"palm_{s}": [0, -1, 0], f"pole_{s}": (0, 0.2, -sg)})
        return hands(p, **kw)
    if breath:                                          # mains posées : elles restent où elles sont au repos
        J = joints(child)
        return flat_hands(reach(p, {s: J[f"wrist.{s}"] for s in "LR"}))
    q = reach(child_body(*_sol))
    p = reach(reach(q))                                 # l'épaule monte avec le bras (rythme scapulaire) : objectif repris
    return flat_hands(p)
child = child_pose(0)
_cv = posed_skin(child)[0]; _cx = float((_cv[:, 0].max() + _cv[:, 0].min()) / 2 - joints(child)["root"][0])
assert np.ptp(_cv[:, 0]) < 1.8, "posture de l'enfant plus longue que le tapis"
# Cadré sur le corps, de trois quarts et un peu d'en haut : vu de côté au ras du sol, le personnage était minuscule et
# le dos qui respire ne se voyait pas.
motion("child-pose", [K(0, child), K(3, child_pose(1)), K(6, child)], muscles=("lowerBack",), yaw=CHILD_YAW, pitch=CHILD_PITCH,
       props=(prop("mat", "root", 0, (_cx, 0, 0), floor=True),))
close_up("child-pose", ("head", "wrist", "toes", "upperleg01", "spine03"), 0.05)

# ─── Au lit : scan corporel et étirements du soir ───
BED_TOP = 0.5
BED_LYING = prop("bed", "root", 0, (-0.05, 0, 0), floor=True)            # allongé dans la longueur, tête vers −X
BED_SIT = prop("bed", "root", 0, (0, -SEAT_DROP, BED_EDGE - 0.71))        # assis au bord, le lit derrière soi
HEAD_ON_PILLOW = dict(neck01=[16, 0, 0], head=[6, 0, 0])

motion("bed-sit-breathe", breathe("chairSit"), yaw=28, pitch=10, props=(BED_SIT,))
motion("bed-neck", neck_tilt("chairSit"), muscles=("neck", "upperBack"), yaw=12, pitch=10, props=(BED_SIT,))

# Arrière des cuisses : au bord du lit, une jambe tendue talon au sol, buste penché en avant dos long.
# Le bassin reste posé sur le matelas : la jambe qui se tend descend la cuisse au bord du lit, et le buste qui se penche
# fait pivoter le bassin autour de l'articulation racine (les hanches, devant elle, descendraient de 4 cm dans le
# matelas). À chaque clé, le bassin est donc remonté jusqu'à ce que la peau touche le dessus du matelas (`on_seat`) :
# on roule sur les fesses, pieds et mains résolus ensuite.
_seat = joints("chairSit")
BED_FRONT = SEAT_Z + BED_EDGE                            # bord avant du matelas (z)
LEG = float(np.linalg.norm(STAND["lowerleg01.L"] - STAND["upperleg01.L"]) + np.linalg.norm(STAND["foot.L"] - STAND["lowerleg01.L"]))
HAM_SIT, HAM_LEAN, HAM_REACH = 10.0, 46.0, 0.998         # buste jambe tendue, puis penché (degrés) ; jambe tendue à 99,8 %
def ham_body(hinge, ankle_L=None, pitch_L=None, lift=0.0):
    """Assis au bord du lit, buste basculé de « hinge » degrés depuis les hanches, dos long (le haut du dos se redresse
    un peu, la tête reste dans le prolongement), jambe gauche tendue talon au sol (ou cheville en « ankle_L »).
    Jambe tendue, le bassin qui roule vers l'avant éloignerait la hanche du talon, qui ne bouge pas : il recule de
    quelques millimètres sur le matelas pour que la jambe garde la même longueur, sans plier ni décoller le talon."""
    def build(dy):
        def body(dz):
            return P("chairSit", root={"rot": [["x", hinge]], "offset": [0, dy, dz]}, spine04=[-hinge * 0.1, 0, 0],
                     spine03=[-hinge * 0.12, 0, 0], spine02=[-hinge * 0.2, 0, 0], spine01=[-hinge * 0.08, 0, 0],
                     neck01=[-hinge * 0.2, 0, 0], **open_hand(0.6))
        dz = 0.0
        if ankle_L is None:
            h = joints(body(0.0))["upperleg01.L"]; a = HAM_ANKLE
            dz = float(a[2] - np.sqrt(max((LEG * HAM_REACH) ** 2 - (h[1] - a[1]) ** 2 - (h[0] - a[0]) ** 2, 1e-6)) - h[2])
        q = legs(body(dz), L=(HAM_ANKLE if ankle_L is None else ankle_L) + np.array([0, lift, 0]),
                 foot_pitch_L=HAM_PITCH if pitch_L is None else pitch_L)
        return legs(q, R=_seat["foot.R"])
    return on_seat(build, BED_FRONT, SEAT_TOP, hi=0.13)
# Jambe tendue : seul le talon est posé, pointe du pied vers le haut (cheville fléchie de 12° vers soi). La hauteur de la
# cheville est réglée sur la peau : le talon touche le sol au niveau de la plante de l'autre pied.
_hip = _seat["upperleg01.L"]; _foot_L, _foot_R = region(("foot", "toes"), "L"), region(("foot", "toes"), "R")
HAM_ANKLE = np.array([float(_hip[0]), float(_seat["foot.R"][1]) + 0.05, 0.0])
def heel_gap(pose):
    """Hauteur du pied gauche au-dessus de la plante du pied droit, posé."""
    v = posed_skin(pose)[0]
    return float(v[_foot_L, 1].min() - v[_foot_R, 1].min())
for _ in range(8):
    _drop = _hip[1] - HAM_ANKLE[1]
    HAM_ANKLE[2] = _hip[2] + float(np.sqrt((LEG * HAM_REACH) ** 2 - _drop ** 2))
    HAM_PITCH = -(90 - float(np.degrees(np.arcsin(_drop / (LEG * HAM_REACH))))) - 12   # perpendiculaire au tibia, puis fléchi
    _hp = ham_body(HAM_SIT, ankle_L=HAM_ANKLE)           # cheville imposée : le bassin ne recule pas pendant ce réglage
    HAM_ANKLE[1] -= heel_gap(_hp)
    _hip = joints(_hp)["upperleg01.L"]                   # hanche de la pose posée sur le matelas (bassin remonté)
def hamstring(side, hinge):
    o = other(side)
    p = ham_body(hinge)
    J = joints(p)
    knee = J[f"lowerleg01.{side}"]; thigh = (J[f"upperleg01.{side}"] + knee) / 2
    hand_on = knee * 0.7 + thigh * 0.3 + [0, 0.055, 0]
    # Une main sur la cuisse tendue, l'autre sur le genou plié : un bras qui irait vers la jambe tendue traverserait ce genou.
    knee_o = J[f"lowerleg01.{o}"]; thigh_o = (J[f"upperleg01.{o}"] + knee_o) / 2
    rest_o = knee_o * 0.75 + thigh_o * 0.25 + [0, 0.06, 0]
    assert side == "L"                                   # côté droit : mirror_pose
    return hands(p, L=hand_on, R=rest_o,
                 fingers_L=[0, -0.3, 1], palm_L=[0, -1, 0], fingers_R=[0.15, -0.3, 1], palm_R=[0, -1, 0],
                 pole_L=(1, -0.6, -0.3), pole_R=(-0.5, -0.3, -1))
hL0, hL1 = hamstring("L", HAM_SIT), hamstring("L", HAM_LEAN)
# La jambe se tend en glissant vers l'avant, pied juste décollé du sol (12 mm sous le point le plus bas du pied, réglé
# sur la peau : le pied bascule sur le talon en avançant), puis le talon se pose. Le buste s'incline à peine.
def ham_way(f):
    lift = 0.02
    for _ in range(3):
        p = ham_body(HAM_SIT * f, ankle_L=_seat["foot.L"] + (HAM_ANKLE - _seat["foot.L"]) * f, pitch_L=HAM_PITCH * f, lift=lift)
        lift += 0.012 - heel_gap(p)
    return p
_hway = [settle_hands(p, gap=0.006) for p in (ham_way(0.12), ham_way(0.5), ham_way(0.93), ham_way(1.0))]   # la cuisse monte sous la main
def ham_keys(t0, flip):
    f = mirror_pose if flip else (lambda p: p)
    w = [f(p) for p in _hway]; h0, h1 = f(hL0), f(hL1)
    # mains résolues sur les cuisses à chaque clé : elles ne s'y enfoncent pas
    lean = lambda s: f(hamstring("L", HAM_SIT + (HAM_LEAN - HAM_SIT) * s))
    mid = w[3]                                           # jambe tendue, talon à 12 mm du sol, juste avant de le poser
    return ([K(t0 + 0.3, w[0]), K(t0 + 0.8, w[1], "linear"), K(t0 + 1.3, w[2], "linear"), K(t0 + 1.55, mid, "linear"), K(t0 + 1.8, h0, "out")]
            + planted(t0 + 1.8, t0 + 3.6, lean, n=5) + [K(t0 + 7.6, h1)] + planted(t0 + 7.6, t0 + 9.2, lambda s: lean(1 - s), n=5)
            + [K(t0 + 9.45, mid, "in"), K(t0 + 9.7, w[2], "linear"), K(t0 + 10.2, w[1], "linear"), K(t0 + 10.7, w[0], "linear"), K(t0 + 11.0, "chairSit", "out")])
motion("bed-hamstring", [K(0, "chairSit")] + ham_keys(0, False) + ham_keys(11.0, True),
       muscles=("hamstrings", "calves"), yaw=62, pitch=8, props=(BED_SIT,))

# Hanches (« 4 ») : cheville droite posée sur le genou gauche, genou droit ouvert, léger penché en avant.
F4_OUT, F4_FWD = 0.03, -0.01                             # cheville par rapport au genou d'appui : vers l'extérieur, vers l'avant
def figure4(lean, hover=0.0, cross=1.0):
    """hover : mains levées de cette hauteur au-dessus de leur appui ; cross : 0 pied encore au sol, 1 cheville sur le genou."""
    p = P("chairSit", spine04=[lean * 0.4, 0, 0], spine03=[lean * 0.3, 0, 0], spine02=[lean * 0.2, 0, 0], neck01=[-lean * 0.3, 0, 0],
          **open_hand(0.6))
    knee_L = joints(p)["lowerleg01.L"]
    # Cheville posée sur le genou, un peu au-delà de lui : le genou croisé reste ouvert (plié à l'excès, mollet et
    # cuisse se fondaient en boule).
    p = legs(p, R=knee_L + [F4_OUT, 0.1, F4_FWD], pole_R=(-1, 0.25, 0.35), foot_yaw_R=70, foot_pitch_R=15)
    J = joints(p)
    if cross < 1:                                        # la jambe n'est pas encore croisée (pied juste décollé) : les mains attendent
        p = legs(P("chairSit", **open_hand(0.6)), R=_seat["foot.R"] + [0, 0.045, 0], foot_pitch_R=12)
    # Main sur le genou ouvert : doigts vers l'intérieur, dans le prolongement de l'avant-bras (poignet sans inclinaison).
    return hands(p, L=J["foot.R"] + [0.0, 0.068 + hover, 0.02 + 0.15 * hover], R=J["lowerleg01.R"] + [0.03, 0.07 + hover, -0.02 - 0.3 * hover],
                 fingers_L=[-0.4, -0.3, 1], palm_L=[0, -1, 0], fingers_R=[0.8, -0.3, 1], palm_R=[0, -1, 0],
                 pole_L=(1, -0.5, -0.3), pole_R=(-0.45, -1, -0.5))     # coude du genou ouvert : vers le bas, près du corps
F4_LEAN = 24
f0, f1 = figure4(0), figure4(F4_LEAN)
# Les mains quittent les cuisses et attendent au-dessus pendant que la jambe se croise (elle passait à travers la main),
# puis se posent sur la cheville et le genou ; même chemin au retour. Penché : mains replacées à chaque clé.
_f4_up, _f4_over = figure4(0, hover=0.14, cross=0.0), figure4(0, hover=0.09)
def figure4_keys(t0, flip):
    f = mirror_pose if flip else (lambda p: p)
    # La jambe se croise et se décroise posément (1,3 s puis 1,5 s : elle retombait en 0,8 s).
    return ([K(t0 + 0.5, f(_f4_up)), K(t0 + 1.8, f(_f4_over)), K(t0 + 2.2, f(f0))] + planted(t0 + 2.2, t0 + 3.8, lambda s: f(figure4(F4_LEAN * s)), n=4)
            + [K(t0 + 7.8, f(f1))] + planted(t0 + 7.8, t0 + 9.2, lambda s: f(figure4(F4_LEAN * (1 - s))), n=4)
            + [K(t0 + 9.5, f(_f4_over)), K(t0 + 11.0, f(_f4_up)), K(t0 + 11.6, "chairSit")])
motion("bed-figure4", [K(0, "chairSit")] + figure4_keys(0, False) + figure4_keys(11.6, True),
       muscles=("glutes", "lowerBack"), yaw=0, pitch=16, props=(BED_SIT,))

# Scan corporel : le corps repose vraiment sur le matelas (dos, bassin, mollets, talons, dos des mains), la tête sur
# l'oreiller. Chaque étape a son geste, discret et lent, et son cadrage (`camera.frame`) : la caméra s'approche de la
# zone dont parle la consigne. Toutes les étapes partent de la même pose : le lit et l'oreiller ne bougent pas.
# Le squelette n'a pas de cage thoracique qui se gonfle : la respiration soulève le milieu du buste (le dos se creuse
# à peine), bassin et épaules restent posés ; la tête, les bras et les jambes ne bougent donc pas avec elle.
SCAN_GAP = 0.0005                                                 # jeu au-dessus du matelas : le buste reste le point le plus bas
SCAN_BREATH = 8.5                                                 # inspiration ample : le ventre se soulève d'environ 2 cm
SCAN_BASE = P("supine", **HEAD_ON_PILLOW)
SCAN_Y = low_of(SCAN_BASE, region(("spine", "root", "pelvis", "clavicle", "shoulder", "upperleg")))   # matelas, avant mise au sol
SCAN_LEGS = region(("lowerleg", "foot", "toes"))
SCAN_HAND = {s: region(("wrist", "finger"), s) for s in "LR"}
SCAN_HEAD = region(("head", "neck"))
def scan_solve(build, idx, lo, hi, target=None, n=13):
    """Paramètre (entre lo et hi) pour lequel le point le plus bas de la partie « idx » touche le matelas ;
    le point le plus bas descend quand le paramètre augmente."""
    target = SCAN_Y + SCAN_GAP if target is None else target
    for _ in range(n):
        m = (lo + hi) / 2
        if low_of(build(m), idx) > target: lo = m
        else: hi = m
    return build(lo)
def scan_breath(pose, amount, peak="spine03"):
    """Inspiration : le buste se soulève autour de « peak » ; bassin, épaules et tête restent où ils sont
    (les rotations se compensent, la dernière est réglée pour que le haut du buste retrouve sa hauteur)."""
    if amount < 1e-6:
        return pose
    rest = joints(pose)["neck01"][1]
    def build(b):
        return P(pose, spine05=[amount, 0, 0], **{peak: [-b, 0, 0]}, spine01=[b - amount, 0, 0])
    lo, hi = amount, 4 * amount                                   # le haut du buste descend quand b augmente
    for _ in range(16):
        m = (lo + hi) / 2
        if joints(build(m))["neck01"][1] > rest: lo = m
        else: hi = m
    return build((lo + hi) / 2)
def scan_legs(pose, turn=18.0, point=14.0, toes=0.0, knee=3.0):
    """Jambes posées : la hanche s'étend jusqu'à ce que mollets et talons touchent le matelas.
    turn : rotation des jambes vers l'extérieur ; point : pointe du pied relâchée ; toes : orteils relevés (< 0)."""
    return scan_solve(lambda e: P(pose, upperleg01=[e, turn, 0], lowerleg01=[knee, 0, 0], foot=[point, 0, 0], toes=[toes, 0, 0]),
                      SCAN_LEGS, -2.0, 14.0)
_sj = joints(SCAN_BASE)
SCAN_WRIST = {s: np.array([_sj[f"upperarm01.{s}"][0] + 0.93 * ARM * np.cos(np.radians(16)), 0.0,
                           _sj[f"upperarm01.{s}"][2] + (1 if s == "R" else -1) * 0.93 * ARM * np.sin(np.radians(16))]) for s in "LR"}
SCAN_FORE = {s: region(("lowerarm",), s) for s in "LR"}
SCAN_ARM_DOWN = {s: np.concatenate([SCAN_HAND[s], SCAN_FORE[s]]) for s in "LR"}
SCAN_THUMB = (0.6, 0.7, 0.25)                                      # pouce : le long de l'index, vers le matelas
SCAN_HAND_PITCH, SCAN_HAND_OPEN = 0.25, 0.5                        # doigts un peu relevés, à demi dépliés
def scan_hands(pose, curl=0.0, shrug=0.0):
    """Bras le long du corps, mains posées paume vers le matelas, doigts détendus (curl : doigts refermés, ou dépliés
    si < 0 ; shrug : épaules décollées du matelas et remontées vers les oreilles, ou abaissées vers les pieds si < 0).
    Paume, bout des doigts et avant-bras touchent le matelas ensemble ; le pouce repose le long de l'index. Posées sur
    le dos (paumes vers le plafond), la torsion de l'avant-bras plafonnait à 100° : la main restait sur la tranche,
    pouce et doigts dressés vers le plafond au-dessus de la hanche."""
    op = open_hand(SCAN_HAND_OPEN)
    p = P(pose, clavicle=[0, -6 * max(shrug, 0.0), 4 * shrug],
          **{k: [0, 0, op.get(k, [0, 0, 0])[2] + v[2] * 0.5 * curl] for k, v in fist(1.0).items()})
    for s in "LR":
        out = 1 if s == "R" else -1
        def build(drop, pitch, s=s, out=out, p=p):
            w = SCAN_WRIST[s] + [0, SCAN_Y + 0.09 - drop, 0]
            q = fixed_hand(p, s, w, [1, pitch, 0.12 * out], [0, -1, 0], (0, -0.25, out), flat=False)
            fingers, across, palm = hand_axes(q, s)
            want = SCAN_THUMB[0] * fingers + SCAN_THUMB[1] * across + SCAN_THUMB[2] * palm
            for bone, child in (("finger1-1", "finger1-2"), ("finger1-2", "finger1-3")):
                q = aim_bone(q, s, bone, child, want / np.linalg.norm(want))
            return q
        q = scan_solve(lambda d: build(d, SCAN_HAND_PITCH), SCAN_ARM_DOWN[s], -0.04, 0.085)
        if curl > 0:
            # Main qui se referme : les doigts repliés soulèveraient le poignet et l'avant-bras ; le poignet se relève
            # (doigts vers le plafond) juste assez pour que l'avant-bras reste posé.
            lo, hi = SCAN_HAND_PITCH, 1.6
            for _ in range(7):
                m = (lo + hi) / 2
                q = scan_solve(lambda d: build(d, m), SCAN_ARM_DOWN[s], -0.04, 0.085)
                if low_of(q, SCAN_FORE[s]) > SCAN_Y + SCAN_GAP + 0.0015: lo = m
                else: hi = m
            q = scan_solve(lambda d: build(d, hi), SCAN_ARM_DOWN[s], -0.04, 0.085)
        p = q
    return p
def scan_head(pose, lift=0.0, turn=0.0):
    """Tête posée sur l'oreiller : le cou se règle pour que l'arrière du crâne (le crâne seul : le bas du cou passe
    au-delà du bord de l'oreiller) reste sur son dessus (lift : tête rentrée, menton vers l'arrière si < 0 ;
    turn : tête tournée de quelques degrés)."""
    if abs(lift) < 1e-6 and abs(turn) < 1e-6:
        return pose
    return scan_solve(lambda x: P(pose, neck01=[16 - x, 0, 0], head=[6 - lift, turn, 0]), SCAN_SKULL, -8.0, 12.0, target=SCAN_PILLOW_TOP)
def scan_pose(breath=0.0, peak="spine03", curl=0.0, shrug=0.0, lift=0.0, head_turn=0.0, **leg):
    """leg : réglage des jambes (scan_legs : turn, point, toes, knee). head_turn : tête tournée sur l'oreiller (ce
    paramètre s'appelait « turn », comme la rotation des jambes : l'étape « Pieds et jambes » tournait la tête de 34°
    au lieu de rouler les jambes vers l'extérieur)."""
    p = scan_legs(scan_breath(SCAN_BASE, breath, peak), **leg)
    return placed(scan_head(scan_hands(p, curl, shrug), lift, head_turn))
SCAN_PILLOW = low_of(SCAN_BASE, SCAN_HEAD)                         # point le plus bas de la tête et du cou au repos
# Oreiller sous la tête : son dessus est réglé sur le point le plus bas du crâne (la tête y repose, enfoncée de
# PILLOW_SINK : réglé sur le bas du cou, plus bas que le crâne, il laissait la tête 6 à 17 mm au-dessus) ; son bord
# côté pieds est placé d'après la peau, au ras de la nuque (plus loin, le cou et les épaules, plus bas que le dessus
# de l'oreiller, y entreraient) ; sa profondeur (PILLOW_DEPTH, le long du lit) est à la mesure d'une tête. Avec un
# décalage fixe depuis l'articulation de la tête, l'oreiller de 34 cm dépassait de 13 cm au-delà du crâne et la nuque
# arrivait sur son bord : la tête semblait posée au bord de l'oreiller.
SCAN_SKULL = region(("head",))
PILLOW_DEPTH, PILLOW_WIDTH = 0.26, 0.48                            # oreiller : le long du lit, en travers (m)
PILLOW_SINK = 0.001                                                # la tête s'enfonce à peine dans l'oreiller
def pillow_under(pose):
    """Oreiller sous la tête de « pose » (première clé du mouvement) : bord côté pieds juste avant la première peau
    (cou, épaules) plus basse que son dessus, dans sa largeur ; dessus au point le plus bas du crâne au-dessus de
    l'oreiller (moins PILLOW_SINK : le crâne y repose). Les deux se règlent l'un l'autre (quelques passes)."""
    v = posed_skin(pose)[0]; J = joints(pose)
    cx = float(v[SCAN_SKULL, 0].mean())
    near = (np.abs(v[:, 2] - J["head"][2]) < PILLOW_WIDTH / 2) & (v[:, 0] > cx)
    top, edge = float(v[SCAN_SKULL, 1].min()) + PILLOW_SINK, np.inf
    for _ in range(4):
        edge = float(v[near & (v[:, 1] < top - 0.003), 0].min()) - 0.001
        on = SCAN_SKULL[v[SCAN_SKULL, 0] < edge]
        top = float(v[on, 1].min()) + PILLOW_SINK
    pr = prop("pillow", "head", 0, (edge - PILLOW_DEPTH / 2 - float(J["head"][0]), top - float(J["head"][1]), 0))
    pr.update(depth=PILLOW_DEPTH, width=PILLOW_WIDTH)
    return pr, top
scan_rest = scan_pose()
# Oreiller réglé sur le crâne de chaque corps ; lit sans plaid (« bare » : les jambes sont posées à cet endroit),
# centré sur le corps allongé. SCAN_PILLOW_TOP : dessus de l'oreiller (repère de la pose, avant mise au sol).
PILLOW_SCAN, SCAN_PILLOW_TOP = pillow_under(scan_rest)
BED_SCAN = dict(prop("bed", "root", 0, (0, 0, 0), floor=True), bare=True)
def scan_motion(mid, keys, frame=None, margin=None, muscles=()):
    motion(mid, keys, muscles=muscles, yaw=8, pitch=30, props=(BED_SCAN, PILLOW_SCAN), support=BED_TOP)
    if frame:
        close_up(mid, frame, margin)
# Les gestes sont lents mais francs : ils doivent se lire sur un écran de téléphone.
# Installation et corps entier : respiration seule, vue d'ensemble (très lente à la fin).
scan_motion("bed-scan-rest", [K(0, scan_rest), K(3, scan_pose(breath=SCAN_BREATH * 0.6)), K(6, scan_rest)])
scan_motion("bed-scan-whole", [K(0, scan_rest), K(4.5, scan_pose(breath=SCAN_BREATH * 0.6)), K(10, scan_rest)])
# Respiration : 4 secondes d'inspiration, 6 d'expiration ; le haut du buste se soulève, les épaules suivent.
scan_motion("bed-scan-breath", [K(0, scan_rest), K(4, scan_pose(breath=SCAN_BREATH * 1.4, peak="spine02", shrug=0.9)), K(10, scan_rest)],
            frame=("neck01", "upperarm01", "spine04"), margin=0.1, muscles=("chest", "abs"))
# Pieds et jambes : à l'inspiration les pieds se redressent, pointes ramenées vers soi, orteils relevés ; à l'expiration
# les pointes retombent, plus loin qu'au repos, puis tout se dépose.
# (Les jambes gardent leur rotation de repos : un « turn » passé ici tournait la tête de 34°, hors du cadre ; roulées
# de 0 à 34°, les talons s'enfonçaient de 6 mm dans le matelas entre deux clés.)
scan_motion("bed-scan-legs", [K(0, scan_rest), K(3.5, scan_pose(breath=1.5, point=-8.0, toes=-16.0)),
                              K(7.5, scan_pose(point=26.0)), K(10, scan_rest)],
            frame=("upperleg01", "foot", "toes"), margin=0.2, muscles=("feet", "calves", "shins", "quads", "hamstrings"))
# Ventre et poitrine : le ventre se soulève (environ 3 cm, ample pour se lire sur un téléphone) et redescend.
scan_motion("bed-scan-belly", [K(0, scan_rest), K(3.5, scan_pose(breath=SCAN_BREATH * 1.6)), K(8, scan_rest)],
            frame=("spine02", "spine05", "upperleg01"), margin=0.08, muscles=("abs", "chest"))
# Mains, bras, épaules : à l'inspiration les mains se referment et les épaules se décollent, remontées vers les oreilles ;
# à l'expiration les doigts se déplient, plus ouverts qu'au repos, et les épaules se déposent dans le matelas.
# Clés rapprochées : interpolée en angles entre deux clés éloignées, la main fermée paume vers le matelas décollait
# l'avant-bras de 3 cm.
_arm_in = lambda s: scan_pose(breath=1.5 * s, curl=1.9 * s, shrug=2.2 * s)
_arm_out = lambda s: scan_pose(breath=1.5 * (1 - s), curl=1.9 - 2.4 * s, shrug=2.2 - 2.8 * s)
_arm_back = lambda s: scan_pose(curl=-0.5 * (1 - s), shrug=-0.6 * (1 - s))
scan_motion("bed-scan-arms", [K(0, scan_rest)] + planted(0, 3.5, _arm_in, n=4) + planted(3.5, 7.5, _arm_out, n=4)
            + planted(7.5, 10, _arm_back, n=3)[:-1] + [K(10, scan_rest, "linear")],
            frame=("neck01", "upperarm01", "wrist", "finger3-3"), margin=0.12, muscles=("hands", "forearms", "biceps", "triceps", "shoulders"))
# Visage : le mannequin n'a pas de visage ; le relâchement se lit sur les épaules et la tête, cadrées de près, sans
# hochement (la tête ne bascule ni vers l'avant ni vers l'arrière : un menton qui monte et descend se lisait comme un
# « oui »). À l'inspiration les épaules se décollent et remontent un peu vers les oreilles ; à l'expiration elles se
# déposent dans le matelas, plus bas qu'au repos, et la tête, devenue lourde, roule doucement sur le côté, l'arrière du
# crâne toujours posé sur l'oreiller ; la pose est tenue, puis de l'autre côté.
_face_in = scan_pose(breath=2.5, shrug=1.4)
_face_out = {sd: scan_pose(shrug=-0.9, head_turn=11.0 * sd) for sd in (1, -1)}
scan_motion("bed-scan-face", [K(0, scan_rest), K(3.5, _face_in), K(8, _face_out[1]), K(10, _face_out[1]), K(13.5, _face_in),
                              K(18, _face_out[-1]), K(20, _face_out[-1]), K(22, scan_rest)],
            frame=("head", "neck01", "clavicle"), margin=0.16, muscles=("head", "neck"))
# Repos allongé (hors exercices) : la même pose, posée sur le matelas.
motion("bed-rest", [K(0, scan_rest), K(3, scan_pose(breath=SCAN_BREATH * 0.6)), K(6, scan_rest)], yaw=8, pitch=30,
       props=(BED_SCAN, PILLOW_SCAN), support=BED_TOP)

# ─── Au lit, allongé : torsion, genoux vers la poitrine ───
# Comme pour le scan corporel, le corps repose vraiment sur le matelas : buste et bassin posés, dos des mains posé,
# tête sur l'oreiller (placé sous le crâne de chaque corps). La mise au sol automatique de l'app échantillonne la
# peau, à quelques millimètres près ; ici chaque clé est placée exactement (sans mise au sol), d'après toute la peau.
BED_BODY = region(("spine", "root", "pelvis", "clavicle", "shoulder", "upperleg"))
PILLOW_H = SCAN_PILLOW - SCAN_Y                                    # arrière du crâne au-dessus du matelas, tête sur l'oreiller
def bed_head(pose, level, turn=0.0):
    """Tête sur l'oreiller (turn : tournée sur le côté) : le cou se règle pour que le crâne reste à sa hauteur."""
    return scan_solve(lambda x: P(pose, neck01=[16 - x, turn * 0.45, 0], head=[6, turn * 0.55, 0]), SCAN_HEAD, -16.0, 34.0,
                      target=level + PILLOW_H)
def laid(pose):
    """Pose allongée placée sur le matelas : le point le plus bas de toute la peau le touche."""
    low = float(posed_skin(pose)[0][:, 1].min()); o = resolve(pose, POSES)["root"]["offset"]
    return placed(P(pose, root={"offset": [float(o[0]), float(o[1]) + BED_TOP + SCAN_GAP - low, float(o[2])]}, ground=False))
def bed_pillow(first, top=None):
    """Oreiller sous le crâne de la première clé (pose déjà placée sur le matelas), bord au ras de la nuque ;
    top : hauteur de son dessus (par défaut celle du scan corporel)."""
    top = BED_TOP + PILLOW_H if top is None else top
    return prop("pillow", "head", 0, (-0.11, top - float(joints(first)["head"][1]) - 0.001, 0))

# Torsion allongée : sur le dos, genoux pliés, pieds à plat sur le matelas. Les genoux tombent ensemble d'un côté :
# le bassin roule (TW_PELVIS), les hanches font le reste (TW_KNEES : inclinaison du plan de chaque jambe), jusqu'à ce
# que le côté de la jambe du dessous se pose ; la jambe du dessus se pose sur elle sans la traverser. Les pieds
# roulent sur leur tranche, presque sur place (TW_ROLL_SHIFT). La colonne se tord en sens inverse : épaules et bras ouverts
# restent posés (mains fixes), la tête tourne à l'opposé sur l'oreiller. a : de −1 (genoux à droite) à 1 (à gauche).
# Comme pour le scan corporel, chaque appui est réglé sur la peau de chaque corps ; chaque clé est placée exactement
# sur le matelas (`laid`).
from rig import axis_angle  # noqa: E402
from ik import to_euler  # noqa: E402
from motion_eval import AX  # noqa: E402
from scipy.spatial.transform import Rotation  # noqa: E402
TW_OPEN = np.radians(30.0)                                         # bras ouverts en V : angle avec l'axe du corps
TW_PELVIS, TW_KNEES, TW_HEAD, TW_ROLL = 45.0, 96.0, 60.0, 45.0     # bassin, plan des jambes, tête, pieds sur la tranche (degrés)
TW_SPINE = dict(spine05=0.3, spine04=0.3, spine03=0.25, spine02=0.15)       # part de la torsion prise par chaque étage
TW_BACK = region(("spine01", "spine02", "spine03", "clavicle", "shoulder"))  # haut du dos
TW_SEAT = region(("root", "spine05", "spine04", "pelvis"))
TW_FOOT = {s: region(("foot", "toes"), s) for s in "LR"}
_knee_y = float(STAND["lowerleg01.L"][1]); _thigh_y = _knee_y + 0.55 * float(STAND["upperleg01.L"][1] - _knee_y)
TW_SHANK = {s: (lambda r: r[MESH.v[r, 1] < _thigh_y])(region(("upperleg", "lowerleg"), s)) for s in "LR"}   # du bas de la cuisse à la cheville
TW_HIPS = np.concatenate([TW_SEAT] + [np.setdiff1d(region(("upperleg",), s), TW_SHANK[s]) for s in "LR"])   # bassin et haut des cuisses
# du milieu des cuisses aux pieds (plus haut, près de l'aine, les cuisses se touchent toujours)
_knee_top = _knee_y + 0.5 * float(STAND["upperleg01.L"][1] - _knee_y)
TW_LIMB = {s: np.concatenate([TW_SHANK[s][MESH.v[TW_SHANK[s], 1] < _knee_top], TW_FOOT[s]]) for s in "LR"}
# des genoux aux pieds : là, les jambes ne se touchent pas au repos et ne doivent jamais se traverser
_knee_top = _knee_y + 0.3 * float(STAND["upperleg01.L"][1] - _knee_y)
TW_KNEES_DOWN = {s: np.concatenate([TW_SHANK[s][MESH.v[TW_SHANK[s], 1] < _knee_top], TW_FOOT[s]]) for s in "LR"}
TW_ROLL_SHIFT = 0.009                                              # déplacement du centre d'un pied roulé à fond sur sa tranche
TW_GAP, TW_SQUEEZE = 0.003, 0.006                                  # jeu entre les deux jambes ; chair écrasée, là où les cuisses se touchent déjà au repos
_tw0 = P("supine", **open_hand(0.6))
_twj = joints(_tw0)
TW_WRIST = {s: np.array([_twj[f"upperarm01.{s}"][0] + 0.93 * ARM * np.cos(TW_OPEN), 0.0,
                         _twj[f"upperarm01.{s}"][2] + (1 if s == "R" else -1) * 0.93 * ARM * np.sin(TW_OPEN)]) for s in "LR"}
_tw_leg = float(np.linalg.norm(STAND["lowerleg01.L"] - STAND["upperleg01.L"]) + np.linalg.norm(STAND["foot.L"] - STAND["lowerleg01.L"]))
TW_ANKLE = {s: np.array([_twj[f"upperleg01.{s}"][0] + 0.58 * _tw_leg, 0.0, float(_twj["root"][2]) + (1 if s == "R" else -1) * 0.075 * S_HIP])
            for s in "LR"}
TW_REST = {}                # réglés sur la pose de repos : inclinaison du buste (tilt), centre de chaque pied (L, R), hauteur du crâne (skull)
def tw_skin(pose, idx):
    """Une partie de la peau dans cette pose (positions, normales)."""
    r = resolve(pose, POSES)
    R, Pj = MESH.rig.fk(local_rotations(r, MESH.names), np.asarray(r["root"]["offset"], float))
    return MESH.rig.skin(MESH.v[idx], MESH.n[idx], MESH.bi[idx], MESH.bw[idx], R, Pj)
def tw_low(pose, idx):
    return float(tw_skin(pose, idx)[0][:, 1].min())
def twist_arms(p, level, drops=None):
    """Bras ouverts, dos des mains posé sur le matelas, poignets au même endroit quelle que soit la torsion.
    drops : hauteur de chaque poignet déjà réglée (sinon elle l'est ici). Rend la pose et ces hauteurs."""
    found = {}
    for s in "LR":
        out = 1 if s == "R" else -1
        def build(drop, s=s, out=out, p=p):
            return fixed_hand(p, s, TW_WRIST[s] + [0, level + 0.10 - drop, 0], [np.cos(TW_OPEN), 0, out * np.sin(TW_OPEN)], [0, 1, 0],
                              (0, -0.25, out), flat=False)
        lo, hi = 0.0, 0.095                                        # la main descend quand « drop » augmente
        for _ in range(0 if drops else 13):
            m = (lo + hi) / 2
            if tw_low(build(m), SCAN_HAND[s]) > level + SCAN_GAP: lo = m
            else: hi = m
        found[s] = drops[s] if drops else lo
        p = build(found[s])
    return p, found
def twist_leg_ik(p, s, ankle, phi, roll):
    """Jambe « s » : cheville en « ankle », plan de la jambe incliné de « phi » degrés (vers la gauche du corps si > 0),
    pied pointé vers le bout du lit et roulé de « roll » degrés sur sa tranche."""
    return legs(p, **{s: ankle, f"pole_{s}": (0.0, float(np.cos(np.radians(phi))), float(-np.sin(np.radians(phi)))),
                      f"foot_rot_{s}": axis_angle([1, 0, 0], -roll) @ axis_angle([0, 1, 0], 90)})
def twist_trunk(a, spec=None, flat=None, drops=None):
    """Bassin roulé, colonne tordue en sens inverse, épaules au même endroit, bras ouverts. Le bassin qui roule sur une
    fesse soulève le sacrum : il bascule (« tilt ») jusqu'à ce que le bassin et le haut du dos touchent le matelas
    ensemble, le haut du buste gardant son inclinaison de repos (« flat » ; None : tout le corps bascule d'un bloc).
    Rend la pose, le niveau du matelas (avant mise en place), la bascule et la hauteur des poignets.
    spec : jambes déjà réglées (cheville, inclinaison, roulis du pied ; le haut des cuisses compte alors dans l'appui du
    bassin) ; drops : hauteur des poignets d'un réglage précédent (les bras pèsent sur la peau des épaules : ils sont
    posés avant de régler la bascule)."""
    rho = TW_PELVIS * a
    def world(rot):
        M = np.eye(3)
        for axis, deg in rot: M = axis_angle(AX[axis], deg) @ M
        return M
    def build(tilt):
        rot = [["y", rho], ["x", -90], ["y", 90], ["z", tilt]]
        # la colonne ramène le haut du buste à plat : la rotation qui sépare le bassin du thorax est répartie entre ses
        # étages, autour du même axe
        rv = Rotation.from_matrix(world(rot).T @ world([["x", -90], ["y", 90], ["z", tilt if flat is None else flat]])).as_rotvec()
        p = P(_tw0, root={"rot": rot}, **{k: to_euler(Rotation.from_rotvec(rv * f).as_matrix()) for k, f in TW_SPINE.items()})
        d = _twj["neck01"] - joints(p)["neck01"]
        p = P(p, root={"offset": [float(d[0]), 0.0, float(d[2])]})
        for s, leg in (spec or {}).items(): p = twist_leg_ik(p, s, *leg)
        return p, tw_low(p, TW_HIPS if spec else TW_SEAT)
    for _ in range(1 if drops else 2):
        lo, hi = -10.0, 36.0                                       # le haut du dos descend quand « tilt » augmente
        for _ in range(13):
            m = (lo + hi) / 2; p, level = build(m)
            if tw_low(twist_arms(p, level, drops or {"L": 0.07, "R": 0.07})[0], TW_BACK) > level: lo = m
            else: hi = m
        p, level = build((lo + hi) / 2)
        p, drops = twist_arms(p, level)
    return p, level, (lo + hi) / 2, drops
def twist_leg(p, s, level, phi, roll, start=None):
    """Jambe « s » posée : le pied touche le matelas et roule sur place. Son centre se déplace à peine vers le côté où
    il roule (TW_ROLL_SHIFT) : c'est le partage qui fait le moins glisser à la fois le pied et la peau qui touche le
    matelas. Rend la pose et la cheville visée."""
    t = TW_ANKLE[s] + [0, level + FLOOR_ANKLE, 0] if start is None else np.array(start, float)
    for _ in range(6):
        q = twist_leg_ik(p, s, t, phi, roll)
        v = tw_skin(q, TW_FOOT[s])[0]
        c = TW_REST.get(s, (v[:, 0].mean(), v[:, 2].mean()))
        err = np.array([c[0] - v[:, 0].mean(), level + SCAN_GAP - v[:, 1].min(), c[1] - TW_ROLL_SHIFT * roll / TW_ROLL - v[:, 2].mean()])
        if np.abs(err).max() < 2e-4: break
        t = t + err
    return q, t
def twist_gap(p, limb=TW_LIMB):
    """Écart entre les deux jambes sur la zone « limb » (m ; négatif : elles se traversent). Chaque jambe est prise
    comme un volume autour de ses os : un point de l'autre jambe est dedans s'il est plus près de l'os que la peau à cet
    endroit (mesure qui reste juste quand les jambes se traversent de part en part)."""
    J = joints(p); skin = {s: tw_skin(p, limb[s])[0] for s in "LR"}
    def to_bones(v, s):
        best = np.full(len(v), np.inf)
        for a, b in (("upperleg01", "lowerleg01"), ("lowerleg01", "foot"), ("foot", "toes")):
            p0, d = J[f"{a}.{s}"], J[f"{b}.{s}"] - J[f"{a}.{s}"]
            u = np.clip((v - p0) @ d / (d @ d), 0, 1)
            best = np.minimum(best, np.linalg.norm(v - p0 - u[:, None] * d, axis=1))
        return best
    worst = 0.08
    for a, b in ("LR", "RL"):
        dist, j = cKDTree(skin[b]).query(skin[a], distance_upper_bound=0.08)
        ok = np.isfinite(dist)
        if ok.any():
            worst = min(worst, float((to_bones(skin[a][ok], b) - to_bones(skin[b], b)[j[ok]]).min()))
    return worst
def twist_legs(p, level, a, prev=None):
    """Les deux jambes : celle du côté où tombent les genoux mène, jusqu'à se poser sur le matelas (pas plus bas) ;
    l'autre la suit et s'arrête à son contact (TW_GAP des genoux aux pieds, TW_REST["gap"] jusqu'au milieu des cuisses). Rend la pose et le réglage de chaque jambe (cheville, inclinaison,
    roulis du pied) ; prev : réglage précédent, dont on repart."""
    low, top = ("L", "R") if a >= 0 else ("R", "L")
    sg, phi = (1.0 if a >= 0 else -1.0), TW_KNEES * abs(a)         # phi : vers le côté où tombent les genoux
    spec = {}
    def one(p, s, phi, start):
        spec[s] = [None, sg * phi, sg * phi * TW_ROLL / TW_KNEES]
        q, spec[s][0] = twist_leg(p, s, level, spec[s][1], spec[s][2], start)
        return q
    for s, bad in ((low, lambda q: tw_low(q, TW_SHANK[low]) < level + SCAN_GAP), (top, lambda q: twist_gap(q, TW_KNEES_DOWN) < TW_GAP or twist_gap(q) < TW_REST.get("gap", -1.0))):
        if prev: phi = sg * prev[s][1]                             # le bassin a été réglé sur ces jambes : elles ne vont pas plus loin
        q = one(p, s, phi, prev[s][0] if prev else None)
        if bad(q):
            lo, hi = -25.0, phi
            for _ in range(9):
                m = (lo + hi) / 2
                if bad(one(p, s, m, spec[s][0])): hi = m
                else: lo = m
            q = one(p, s, lo, spec[s][0])
        p = q
    return p, spec
def twist_head(p, level, turn):
    """Tête sur l'oreiller, tournée de « turn » degrés : le cou se règle pour que le crâne reste à la hauteur qu'il a
    au repos (au plus près de sa courbure naturelle : tête tournée, la hauteur du crâne ne varie pas dans un seul sens)."""
    def build(x): return P(p, neck01=[16 - x, turn * 0.45, 0], head=[6, turn * 0.55, 0])
    if "skull" not in TW_REST: return build(0.0)
    def over(x): return tw_low(build(x), SCAN_HEAD) - level - TW_REST["skull"]
    xs = np.arange(-22.0, 30.1, 2.0); f = np.array([over(x) for x in xs])
    cross = [i for i in range(len(xs) - 1) if f[i] * f[i + 1] <= 0]
    if not cross:
        return build(float(xs[np.abs(f).argmin()]))
    i = min(cross, key=lambda i: abs(xs[i] + 1.0))
    lo, hi, up = float(xs[i]), float(xs[i + 1]), f[i] > 0
    for _ in range(9):
        m = (lo + hi) / 2
        if (over(m) > 0) == up: lo = m
        else: hi = m
    return build(lo if up else hi)                                 # du côté où le crâne effleure l'oreiller, sans y entrer
def twist_pose(a):
    p, level, _, drops = twist_trunk(a, flat=TW_REST["tilt"])
    q, spec = twist_legs(p, level, a)
    for _ in range(TW_PASSES):                                     # le haut des cuisses, une fois les jambes placées, fait partie de l'appui
        p, level, _, drops = twist_trunk(a, spec, TW_REST["tilt"], drops)
        q, spec = twist_legs(p, level, a, spec)
    return laid(twist_head(q, level, -TW_HEAD * a))
TW_PASSES = 1
# Repères pris sur la pose de repos : inclinaison du buste, centre de chaque pied posé à plat, hauteur du crâne.
_p, _lv, TW_REST["tilt"], _ = twist_trunk(0.0)
_p = twist_legs(_p, _lv, 0.0)[0]
for _s in "LR":
    _v = tw_skin(_p, TW_FOOT[_s])[0]
    TW_REST[_s] = (float(_v[:, 0].mean()), float(_v[:, 2].mean()))
TW_REST["gap"] = min(TW_GAP, twist_gap(_p) - TW_SQUEEZE)            # jambes : pas plus serrées qu'au repos, à la chair écrasée près
TW_REST["skull"] = low_of(twist_pose(0.0), SCAN_HEAD) - BED_TOP - SCAN_GAP
_tw_cache = {}
def twist_bed(a):
    import copy
    k = round(float(a), 6)
    if k not in _tw_cache: _tw_cache[k] = twist_pose(k)
    return copy.deepcopy(_tw_cache[k])
_tw_rest = twist_bed(0)
TW_N = 12
def twist_keys(t0, side, drop=3.0, hold=3.0, back=2.5):
    """Les genoux tombent d'un côté (side = 1 : à gauche), y restent, puis reviennent au centre."""
    return (planted(t0, t0 + drop, lambda s: twist_bed(side * s), n=TW_N) + [K(t0 + drop + hold, twist_bed(side))]
            + planted(t0 + drop + hold, t0 + drop + hold + back, lambda s: twist_bed(side * (1 - s)), n=TW_N))
motion("bed-twist", [K(0, _tw_rest)] + twist_keys(0, 1) + twist_keys(8.5, -1), muscles=("lowerBack", "glutes"), yaw=-72, pitch=38,
       props=(dict(BED_LYING, bare=True), bed_pillow(_tw_rest, BED_TOP + SCAN_GAP + TW_REST["skull"])), support=BED_TOP)
# Vu depuis le pied du lit, de haut : on voit les genoux tomber et la tête tourner ; cadré sur le corps, pas sur le lit.
close_up("bed-twist", ("head", "wrist", "lowerleg01", "toes"), 0.08)

# Genoux vers la poitrine : sur le dos, cuisses ramenées sur le ventre, genoux pliés (tibias à peu près horizontaux, talons
# vers les fesses), genoux écartés de la largeur du bassin, tibias parallèles ; chaque main posée sur le devant de son
# genou (les bras ne se croisent pas, coudes souples sur les côtés). Le bassin bascule (rétroversion : le bas du dos
# s'arrondit) jusqu'à ce que le sacrum et le haut du dos touchent le matelas ensemble ; la colonne rend la bascule, le
# thorax reste à plat et la tête posée sur l'oreiller (oreiller réglé sur le crâne, comme au scan corporel). Jambes
# résolues par cinématique inverse (cuisse à KC_THIGH degrés de la direction des pieds, tibia à KC_SHIN) : posées par des
# angles, les tibias s'écartaient en V et se dressaient vers le plafond vus d'en haut. À l'expiration, les mains
# ramènent les genoux vers la poitrine (15° de plus) ; ils repartent à l'inspiration. Cadré sur le corps, presque de
# profil, un peu d'en haut : la silhouette jambes repliées se lit.
from rig import axis_angle as _kaa  # noqa: E402
from ik import to_euler as _keu  # noqa: E402
from motion_eval import AX as _KAX  # noqa: E402
from scipy.spatial.transform import Rotation as _KRot  # noqa: E402
KC_HAND = (0.03, 0.03, -0.04)  # main par rapport au genou : vers le plafond, le côté, les pieds (négatif : vers la tête)
KC_ARM = (0.2, 0.3 if BODY == "male" else 0.5, 0.0)   # coude (vers le plafond), paume inclinée vers le genou (vers le côté)
KC_THIGH = (125.0, 140.0)       # cuisse : angle depuis la direction des pieds, au repos → genoux ramenés (degrés)
KC_SHIN, KC_SHIN_GAIN = -12.0, 0.8   # tibia au repos (talon un peu plus bas que le genou) ; part de la traction qu'il suit
KC_KNEE_W = 0.9                 # écart des genoux (part de l'écart des hanches)
KC_FOOT = 12.0                  # pied détendu
KC_OPEN = 0.85 if BODY == "male" else 0.7   # doigts : plus ouverts pour l'homme (fermés à 0,7, leurs bouts entraient de 4 mm dans le tibia)
_kc_lt = float(np.linalg.norm(STAND["lowerleg01.L"] - STAND["upperleg01.L"]))
_kc_ls = float(np.linalg.norm(STAND["foot.L"] - STAND["lowerleg01.L"]))
KC_SPINE = dict(spine05=0.34, spine04=0.33, spine03=0.21, spine02=0.12)
KC_SEAT = region(("root", "spine05", "pelvis"))                   # sacrum, bas du dos
KC_BACK = region(("spine01", "spine02", "spine03"))                  # haut du dos (sans les épaules, que les bras soulèvent)
_kc_flat = [["x", -90], ["y", 90]]
_kc_ref = joints(P("supine", neck01=[16, 0, 0], head=[6, 0, 0]))
def _kc_world(rot):
    M = np.eye(3)
    for axis, deg in rot: M = _kaa(_KAX[axis], deg) @ M
    return M
def kc_body(tilt, pull):
    rot = _kc_flat + [["z", tilt]]
    rv = _KRot.from_matrix(_kc_world(rot).T @ _kc_world(_kc_flat)).as_rotvec()
    p = P("supine", root={"rot": rot}, **{k: _keu(_KRot.from_rotvec(rv * f).as_matrix()) for k, f in KC_SPINE.items()},
          neck01=[16, 0, 0], head=[6, 0, 0], **open_hand(KC_OPEN))
    d = _kc_ref["neck01"] - joints(p)["neck01"]                     # le haut du buste ne bouge pas
    p = P(p, root={"rot": rot, "offset": [float(d[0]), float(d[1]), float(d[2])]})
    J = joints(p)
    phi = np.radians(KC_THIGH[0] + (KC_THIGH[1] - KC_THIGH[0]) * pull)
    psi = np.radians(KC_SHIN + KC_SHIN_GAIN * (KC_THIGH[1] - KC_THIGH[0]) * pull)
    mid = (J["upperleg01.L"] + J["upperleg01.R"]) / 2
    kw = {}
    for s_ in "LR":
        h = J[f"upperleg01.{s_}"]
        knee = np.array([h[0] + _kc_lt * np.cos(phi), h[1] + _kc_lt * np.sin(phi), mid[2] + KC_KNEE_W * (h[2] - mid[2])])
        knee = h + (knee - h) / np.linalg.norm(knee - h) * _kc_lt
        ank = knee + 0.999 * _kc_ls * np.array([np.cos(psi), np.sin(psi), 0.0])     # tibias parallèles
        kw[s_] = ank; kw[f"pole_{s_}"] = tuple(knee - (h + ank) / 2)
    return P(legs(p, **kw), foot=[KC_FOOT, 0, 0])
def kc_tilt(pull):
    """Bascule du bassin pour laquelle sacrum et haut du dos touchent le matelas ensemble."""
    lo, hi = -40.0, 40.0
    f = lambda t: low_of(kc_body(t, pull), KC_BACK) - low_of(kc_body(t, pull), KC_SEAT)
    s_lo = f(lo) > 0
    for _ in range(16):
        m = (lo + hi) / 2
        if (f(m) > 0) == s_lo: lo = m
        else: hi = m
    return (lo + hi) / 2
def knees_chest(pull, hand=None, arm=None):
    hand, arm = hand or KC_HAND, arm or KC_ARM
    p = kc_body(kc_tilt(pull), pull)
    J = joints(p)
    up, toward_feet = np.array([0, 1.0, 0]), np.array([1.0, 0, 0])   # tête vers −X
    for s_, sg in (("L", 1.0), ("R", -1.0)):
        side = _kc_world(_kc_flat) @ np.array([sg, 0, 0])
        def place(h, s_=s_, side=side, q=p):
            w = J[f"lowerleg01.{s_}"] + up * h + side * hand[1] + toward_feet * hand[2]
            return fixed_hand(q, s_, w, toward_feet + arm[2] * side, -np.sqrt(1 - arm[1] ** 2) * up - arm[1] * side,
                              tuple(side + arm[0] * up), flat=False)
        # la paume se pose sur le genou : hauteur du poignet réglée sur la peau (CONTACT_GAP au point le plus proche)
        lo, hi = -0.02, 0.10
        for _ in range(14):
            m = (lo + hi) / 2
            pen, dist = kc_gap(place(m), s_)
            if pen < -0.0015 or dist < CONTACT_GAP: lo = m
            else: hi = m
        p = place(hi)
    return laid(p)
KC_LEGS = region(("upperleg", "lowerleg"))
KC_HANDS = {s: region(("wrist", "finger"), s) for s in "LR"}
KC_FORE = {s: region(("lowerarm",), s) for s in "LR"}
def kc_gap(p, s):
    """Main et avant-bras face aux jambes : enfoncement (distance signée au sommet le plus proche, comme contact_scan)
    et distance de la main à la peau."""
    v, n = posed_skin(p)
    arm = np.concatenate([KC_HANDS[s], KC_FORE[s]])
    d, j = cKDTree(v[KC_LEGS]).query(v[arm])
    side = np.einsum("ij,ij->i", v[arm] - v[KC_LEGS][j], n[KC_LEGS][j])
    return float(np.where(d < 0.04, side, 1.0).min()), float(d[: len(KC_HANDS[s])].min())
kc0, kc1 = knees_chest(0), knees_chest(1)
# Presque de profil, un peu d'en haut : la silhouette des jambes repliées et la traction des mains se lisent. Vue de trois
# quarts d'en haut (35°, 40°), les tibias semblaient dressés vers le plafond et les bras croisés sur les genoux.
KC_YAW, KC_PITCH = 10, 20
print("genoux vers la poitrine : bascule du bassin", round(kc_tilt(0), 1), "→", round(kc_tilt(1), 1), "degrés")
motion("bed-knees-chest", [K(0, kc0)] + planted(0, 3, knees_chest) + [K(3.6, kc1)] + planted(3.6, 7, lambda s: knees_chest(1 - s)) + [K(7.6, kc0)],
       muscles=("lowerBack", "glutes"), yaw=KC_YAW, pitch=KC_PITCH, props=(BED_LYING, pillow_under(kc0)[0]), support=BED_TOP)
close_up("bed-knees-chest", ("head", "upperarm01", "lowerleg01", "toes", "upperleg01"), 0.15)

# ─── Visage ───
# Relaxation progressive, étape « Visage », assis sur la chaise : le mannequin n'a pas de visage, la contraction se lit
# sur les épaules et la tête, cadrées de près, de trois quarts. 5 secondes de contraction tenue : les épaules montent
# vers les oreilles et la tête se rentre un peu (elle recule sans basculer : le bas du cou se redresse, la tête reste
# droite, regard horizontal ; un menton qui monte puis descend se lisait comme un hochement). Puis le relâchement, net :
# les épaules retombent, plus bas qu'au repos, la tête revient droite, et 10 secondes de respiration calme (la poitrine
# se soulève, les épaules suivent à peine). Mains posées sur les cuisses.
_face_tense = keep_hands(P("chairSit", clavicle=[0, -5, 18], neck01=[-9, 0, 0], head=[9, 0, 0]), "chairSit")
_face_relax = keep_hands(P("chairSit", clavicle=[0, 2, -4]), "chairSit")
_face_breath = keep_hands(P("chairSit", clavicle=[0, 1, 0], spine01=[-5, 0, 0], spine02=[-3, 0, 0], neck01=[5, 0, 0], head=[3, 0, 0]),
                          "chairSit")
motion("chair-face", [K(0, "chairSit"), K(1, _face_tense), K(5, _face_tense), K(5.6, _face_relax, "out"), K(8.2, _face_breath),
                      K(10.6, _face_relax), K(13.0, _face_breath), K(15, "chairSit")], muscles=("head", "neck"), yaw=38, props=(CHAIR,))
close_up("chair-face", ("head", "neck01", "upperarm01"), 0.14)
# ─── Assis sur une chaise ───
clench = P("chairSit", upperarm01=[-24, 0, 6], lowerarm01=[-80, 0, 0], lowerarm02=[0, 0, 0], wrist=[0, 0, 0], **fist(1))
# Tempo de la consigne : contracter 5 secondes, relâcher d'un coup, observer 10 secondes.
motion("fists-clench", [K(0, "chairSit"), K(1, clench), K(6, clench), K(6.5, "chairSit", "out"), K(16.5, "chairSit")],
       muscles=("forearms", "biceps", "hands"), yaw=35, props=(CHAIR,))
# Ventre contracté : on reste assis droit, tête haute. Le ventre rentre et les côtes basses descendent (le bas de la
# colonne se fléchit à peine, le haut se redresse d'autant : ni les épaules ni la tête n'avancent) ; tenu 5 secondes,
# puis relâché lentement, le temps d'une longue expiration.
# Avant de contracter, une inspiration (la poitrine se soulève) ; le ventre se creuse ensuite nettement : le bas de la
# colonne s'arrondit, les côtes basses descendent vers le bassin, les épaules s'abaissent et avancent à peine, la tête
# reste droite. Cadré sur le buste, de profil : de face et en entier, le geste ne se voyait pas.
_brace_in = keep_hands(P("chairSit", spine01=[-5, 0, 0], spine02=[-3, 0, 0], clavicle=[0, 1, 2], neck01=[6, 0, 0], head=[2, 0, 0]), "chairSit")
_brace = keep_hands(P("chairSit", spine05=[6, 0, 0], spine04=[5, 0, 0], spine03=[2, 0, 0], spine02=[-2, 0, 0], spine01=[-1, 0, 0],
                      neck01=[-8, 0, 0], head=[-2, 0, 0], clavicle=[0, -2, -5]), "chairSit")
motion("abs-contract", [K(0, "chairSit"), K(1.0, _brace_in), K(2.0, _brace), K(7.0, _brace), K(10.0, "chairSit"), K(11.5, "chairSit")],
       muscles=("abs",), yaw=70, props=(CHAIR,))
close_up("abs-contract", ("head", "spine03", "upperleg01", "upperarm01"), 0.14)
legs_out = P("chairSit", ground=False, lowerleg01=[12, 0, 0], foot=[-22, 0, 0])
motion("legs-tense", [K(0, "chairSit"), K(1.5, legs_out), K(3, legs_out), K(4.5, "chairSit")], muscles=("quads", "shins", "calves"),
       yaw=60, props=(CHAIR,))

# ─── Mouvements issus de captures réelles (CMU Graphics Lab, http://mocap.cs.cmu.edu) ───
# (identifiant, fichier BVH, fenêtre en secondes, durée de boucle min/max, vitesse, angle de vue, muscles, redressement)
# Redressement : flexion ajoutée à un os (degrés, > 0 vers l'avant). Plus aucun mouvement n'en vient : les deux captures
# de marche (CMU 07_04 et 07_01) ont le genou d'appui plié de 20 à 30° dans la capture elle-même, ce qui donnait une
# marche accroupie ; la promenade et la marche soutenue sont écrites par objectifs (voir « Marche », plus haut).
MOCAP = []
KEY_BONES = ["root", "spine03", "spine01", "neck01", "upperarm01.L", "upperarm01.R", "lowerarm01.L", "lowerarm01.R",
             "upperleg01.L", "upperleg01.R", "lowerleg01.L", "lowerleg01.R"]

def build_mocap(bvh_root, joints_):
    from mocap import retarget, mapping, slerp
    names = [j["name"] for j in joints_]; parents = [j["parent"] for j in joints_]
    heads = {j["name"]: np.array(j["head"]) for j in joints_}
    mapped = sorted(set(mapping()), key=names.index)
    out = {}
    for mid, path, (t0, t1), (lmin, lmax), speed, yaw, muscles, upright in MOCAP:
        Q, _ = retarget(os.path.join(bvh_root, path), names, parents, heads, int(t0 * 120), int(t1 * 120), fps=30, blend=0)
        key = [names.index(b) for b in KEY_BONES]
        best = None
        for i in range(len(Q)):
            for j in range(i + int(lmin * 30), min(len(Q), i + int(lmax * 30) + 1)):
                d = sum(1 - abs(float(Q[i, k] @ Q[j, k])) for k in key)
                if best is None or d < best[0]:
                    best = (d, i, j)
        _, i, j = best
        C = Q[i:j].copy()
        nb = min(8, len(C) // 4)
        for k in range(nb):                      # fondu des dernières images vers la première
            w = (k + 1) / (nb + 1)
            for b in range(C.shape[1]):
                C[len(C) - nb + k, b] = slerp(C[len(C) - nb + k, b], Q[j, b] if j < len(Q) else C[0, b], w)
        for bone, deg in upright.items():         # redressement : rotation autour de X ajoutée à l'os, à chaque image
            h = np.radians(deg) / 2; cx, cw = np.sin(h), np.cos(h); b = names.index(bone)
            for f in range(len(C)):
                x, y, z, w = C[f, b]
                C[f, b] = [cw * x + cx * w, cw * y - cx * z, cw * z + cx * y, cw * w - cx * x]
        idx = [names.index(b) for b in mapped]
        frames = [[round(float(x), 4) for b in idx for x in C[f, b]] for f in range(len(C))]
        out[mid] = {"clip": {"fps": 30 * speed, "bones": mapped, "frames": frames,
                             "source": f"CMU {os.path.basename(path)} {i / 30 + t0:.2f}–{j / 30 + t0:.2f} s"},
                    "muscles": list(muscles), "camera": {"yaw": yaw, "pitch": 8}, "props": []}
        print(f"  {mid}: {len(C)} images, boucle {i / 30 + t0:.2f}–{j / 30 + t0:.2f} s, écart {best[0]:.3f}")
    return out

def rounded(x):
    """Arrondit les angles au dixième de degré (fichier plus léger)."""
    if isinstance(x, dict): return {k: (round(v, 3) if k == "t" else rounded(v)) for k, v in x.items()}
    if isinstance(x, list): return [rounded(v) for v in x]
    if isinstance(x, float): return round(x, 4 if abs(x) < 2 else 1)
    return x

def strip_private(x):
    """Retire les annotations internes (« _pinned »…) avant l'écriture du JSON."""
    if isinstance(x, dict): return {k: strip_private(v) for k, v in x.items() if not k.startswith("_")}
    if isinstance(x, list): return [strip_private(v) for v in x]
    return x

def check(poses, motions, bones, where):
    def check_pose(p, ctx):
        if isinstance(p, str):
            assert p in poses, f"{where}/{ctx} : pose inconnue {p}"
            return
        for b in p.get("bones", {}):
            assert b in bones or (b + ".L") in bones, f"{where}/{ctx} : os inconnu {b}"
        if "base" in p: check_pose(p["base"], ctx)
    for name, pose in poses.items(): check_pose(pose, name)
    for mid, m in motions.items():
        for k in m["keys"]: check_pose(k["pose"], mid)
        for r in m["muscles"]: assert r in REGIONS, f"{where}/{mid} : région inconnue {r}"
        ts = [k["t"] for k in m["keys"]]; assert ts == sorted(ts) and ts[0] == 0, mid
        for pr in m["props"]:
            assert pr["anchor"] is None or pr["anchor"] in bones, f"{where}/{mid} : ancre inconnue {pr['anchor']}"

if __name__ == "__main__":
    import runpy
    # Os animés (les articulations d'appoint suivent leur os : elles ne figurent pas dans les poses).
    bones = [j["name"] for j in META["bodies"]["male"]["joints"] if not j.get("half")]
    bvh_root = os.environ.get("CMU_BVH", "/home/user/una-dinosauria/cmu-mocap/data")
    previous = json.load(open(OUT)) if os.path.exists(OUT) else {}
    bodies = {}
    for body in ("male", "female"):
        # Le script est rejoué pour chaque corps : objectifs et cinématique inverse sur son propre squelette.
        ns = runpy.run_path(os.path.abspath(__file__), init_globals={"BODY": body}, run_name=f"motions_{body}")
        poses, motions = ns["POSES"], ns["MOTIONS"]
        check(poses, motions, bones, body)
        if os.path.isdir(bvh_root):
            motions.update(ns["build_mocap"](bvh_root, [j for j in META["bodies"][body]["joints"] if not j.get("half")]))
        else:
            print("Captures CMU introuvables : les mouvements captés du fichier précédent sont conservés.")
            old = previous.get("bodies", {}).get(body, {}).get("motions", previous.get("motions", {}))
            motions.update({k: v for k, v in old.items() if "clip" in v and k in {m[0] for m in MOCAP}})
        bodies[body] = {"poses": rounded(strip_private(poses)), "motions": rounded(strip_private(motions))}
        print(f"{body} : {len(motions)} mouvements")
    json.dump({"version": 3, "bones": bones, "regions": REGIONS, "bodies": bodies},
              open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    print("→", OUT, os.path.getsize(OUT) // 1024, "Ko")
    # Contrôle des accessoires sur le fichier écrit, tel que l'app le joue (15 images/s) : aucune peau à plus de 5 mm
    # à l'intérieur d'une chaise, d'un lit, d'une table, d'un mur ou d'une porte.
    from prop_scan import scan, LIMIT_MM
    print("Peau dans les accessoires (prop_scan.py)…")
    bad = scan(show=False)
    if bad:
        print("!" * 100)
        print(f"ATTENTION : peau à plus de {LIMIT_MM:.0f} mm à l'intérieur d'un accessoire, à corriger avant de livrer :")
        for body, mid, res in bad:
            print(f"  {body:6} {mid:22} " + " | ".join(f"{n} {d:.0f} mm à t={t} s ({bone}, {cnt} sommets)" for n, d, t, bone, cnt in res))
        print("!" * 100)
    else:
        print(f"  aucun mouvement ne dépasse {LIMIT_MM:.0f} mm.")
