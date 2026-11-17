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

def prop(kind, anchor=None, key=0, offset=(0, 0, 0), yaw=0, floor=False):
    return {"kind": kind, "anchor": anchor, "key": key, "offset": [float(x) for x in offset], "yaw": float(yaw), "floor": floor}

CHAIR = prop("chair", "root", 0, (0, -0.105, -0.06))
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
motion("look-far", [K(0, P("stand", head=[-5, 0, 0])), K(3, P("stand", head=[-6, 12, 0], **BREATH_IN)),
                    K(6, P("stand", head=[-5, 0, 0])), K(9, P("stand", head=[-6, -12, 0], **BREATH_IN)), K(12, P("stand", head=[-5, 0, 0]))], yaw=25)
motion("chair-breathe", breathe("chairSit"), yaw=30, props=(CHAIR,))
# Méditation assise : dos des mains posé sur les genoux, paumes vers le ciel, doigts ouverts, coudes souples.
def seated(breath=0.0):
    p = P("crossLeggedLegs", spine01=[-3 * breath, 0, 0], spine02=[-2 * breath, 0, 0], neck01=[-breath, 0, 0], **open_hand(0.75))
    kw = {}
    for s, sg in (("L", 1), ("R", -1)):
        hip, knee = _cl[f"upperleg01.{s}"], _cl[f"lowerleg01.{s}"]
        kw.update({s: knee + 0.36 * (hip - knee) + [0.0, 0.04, 0.0], f"fingers_{s}": [0.75 * sg, -0.12, 1], f"palm_{s}": [0, 1, 0.1],
                   f"pole_{s}": (sg, -0.5, -0.8)})
    return hands(p, **kw)
motion("seated-breathe", [K(0, seated()), K(3, seated(1)), K(6, seated())], yaw=15, props=(MAT,))

# ─── Marche sur place, montées de genoux ───
def knee_lift(side, hip, knee, arm, elbow, back_arm=18, twist=5):
    """Genou « side » levé ; bras opposé vers l'avant, bras du même côté vers l'arrière, coudes pliés."""
    o = other(side)
    return P("stand", **{S("upperleg01", side): sided(side, [-hip, 0, -3]), S("lowerleg01", side): [knee, 0, 0],
                         S("foot", side): sided(side, [hip * 0.35, 0, 3]),
                         S("upperarm01", o): sided(o, [-arm, 0, 6]), S("lowerarm01", o): [-elbow, 0, 0],
                         S("upperarm01", side): sided(side, [back_arm, 0, 6]), S("lowerarm01", side): [-elbow * 0.8, 0, 0]},
             spine03=[0, twist if side == "L" else -twist, 0], **open_hand(0.4))
def step_mid(elbow):
    return P("stand", lowerleg01=[4, 0, 0], upperarm01=[-4, 0, 6], lowerarm01=[-elbow, 0, 0], **open_hand(0.4))
def stepping(mid, hip, knee, arm, elbow, period, muscles, yaw=30):
    h = period / 4
    motion(mid, [K(0, knee_lift("L", hip, knee, arm, elbow)), K(h, step_mid(elbow * 0.85)),
                 K(2 * h, knee_lift("R", hip, knee, arm, elbow)), K(3 * h, step_mid(elbow * 0.85)),
                 K(4 * h, knee_lift("L", hip, knee, arm, elbow))], muscles=muscles, yaw=yaw)
stepping("march", 52, 72, 34, 80, 1.3, ("quads", "calves", "abs"), yaw=50)
stepping("high-knees", 82, 96, 48, 90, 1.1, ("quads", "abs"), yaw=50)
# Récupération : marche sur place lente et calme. Le pied monte et redescend à la verticale de son appui (il ne glisse
# pas), l'autre reste posé ; les bras balancent à peine.
def slow_step(side, up=1.0):
    o = other(side)
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
# Retour au calme : quelques pas lents sur place, puis une respiration profonde (la poitrine s'ouvre, les bras s'écartent un peu).
_deep = P("stand", spine01=[-6, 0, 0], spine02=[-4, 0, 0], spine03=[-2, 0, 0], neck01=[-3, 0, 0], clavicle=[0, 6, 4],
          upperarm01=[2, 28, 16], lowerarm01=[-8, 0, 0], **open_hand(0.6))
motion("march-breathe", [K(0, slow_step("L", 0))] + slow_steps(0, 4) + [K(5.8, "stand"), K(9.8, _deep), K(15.4, "stand"), K(16.0, "stand")],
       muscles=("quads", "calves", "chest"), yaw=40)

# Pause : une gorgée d'eau (la main droite porte un verre aux lèvres, la tête bascule un peu en arrière), puis quelques pas
# tranquilles sur place.
_head = region(("head",))
_hv = MESH.v[_head]; _front = _hv[_hv[:, 2] > ik.H["head"][2] + 0.04]
_chin = _front[np.argmin(_front[:, 1])]
_lip = _hv[np.abs(_hv[:, 1] - (_chin[1] + 0.045)) < 0.006]
MOUTH = np.array([0.0, _chin[1] + 0.045, _lip[:, 2].max()]) - ik.H["head"]          # dans le repère de la tête
_grip = {S(k, "R"): sided("R", v) for k, v in fist(0.5).items()}
_w0 = STAND["wrist.R"]; _f0, _, _n0 = hand_axes(P("stand"), "R")
def drink(u, tip=0.0):
    """u : 0 bras le long du corps, 1 verre aux lèvres ; tip : le verre et la tête basculent pour boire."""
    p = P("stand", neck01=[-4 * tip, 0, 0], head=[-9 * tip, 0, 0], **{k: [x * u for x in v] for k, v in _grip.items()})
    if u < 0.01:
        return p
    R, J = ik.fk(p)
    glass = J["head"] + R["head"] @ (MOUTH + [0.0, -0.05, 0.045])
    w1 = glass + [-0.05, -0.075 + 0.02 * tip, 0.025]
    w = _w0 + (w1 - _w0) * u + [0.0, 0.0, 0.14 * np.sin(np.pi * u)]                # la main monte par l'avant du corps
    pole = (-0.62, -1, 0.1)                                                        # coude bas, avant-bras presque vertical
    q = with_bones(p, ik.arm(p, "R", w, pole)); Jq = joints(q)
    f1 = Jq["wrist.R"] - Jq["lowerarm01.R"]; f1 = f1 / np.linalg.norm(f1) + np.array([0.1, 0.0, -0.25 * tip])   # main dans l'axe de l'avant-bras
    n1 = np.array([0.75, 0.0, -0.65])                                              # paume vers le verre, tenu devant les lèvres
    return hands(p, R=w, fingers_R=_f0 + (f1 - _f0) * u, palm_R=_n0 + (n1 - _n0) * u, pole_R=pole)
_sip = drink(1, 1)
motion("water-break", [K(0, "stand")] + planted(0.3, 1.5, drink) + [K(1.9, _sip), K(2.9, _sip), K(3.3, drink(1))]
       + planted(3.3, 4.5, lambda s: drink(1 - s)) + [K(4.8, slow_step("L", 0))] + slow_steps(4.8, 4) + [K(10.6, "stand")], yaw=35)

# Boxe dans le vide : garde (pied gauche devant, genoux souples, poings au menton), direct du gauche, retour en garde,
# direct du droit avec rotation du buste, retour. Les pieds restent posés.
BOX_FEET = {"L": ankle("L", dx=0.03 * S_HIP, dz=0.17 * S_LEG), "R": ankle("R", dx=-0.06 * S_HIP, dz=-0.15 * S_LEG)}
def boxing(jab=0.0, cross=0.0):
    yaw = -26 - 5 * jab + 18 * cross                 # bassin tourné vers la droite en garde
    twist = -8 * jab + 30 * cross                    # rotation des épaules en plus de celle du bassin
    look = -(yaw + twist)
    p = P("stand", root={"rot": [["y", yaw]], "offset": [0, -0.06 * S_LEG, 0.02 * S_LEG * (jab + cross)]},
          spine04=[3, twist * 0.2, 0], spine03=[3, twist * 0.3, 0], spine02=[0, twist * 0.3, 0], spine01=[0, twist * 0.2, 0],
          neck01=[5, look * 0.35, 0], neck02=[0, look * 0.25, 0], head=[3, look * 0.4, 0], **fist(1.0))
    p = legs(p, L=BOX_FEET["L"], R=BOX_FEET["R"], pole_L=(0.1, 0, 1), pole_R=(-0.5, 0, 1), foot_yaw_L=-8, foot_yaw_R=-42)
    R, J = ik.fk(p); Rc = R["spine01"]; kw = {}
    for s, sg, u in (("L", 1, jab), ("R", -1, cross)):
        sh = J[f"upperarm01.{s}"]
        guard = J["head"] + Rc @ [sg * 0.095, -0.075, 0.19 if s == "L" else 0.15]
        reach = 0.97 * ARM
        hit = np.array([0.02 * sg, sh[1] + 0.01, sh[2] + np.sqrt(reach ** 2 - (sh[0] - 0.02 * sg) ** 2)])
        w = guard + (hit - guard) * u
        f = Rc @ [-0.15 * sg, 1, 0.25]; f = f / np.linalg.norm(f) * (1 - u) + (hit - sh) / reach * u
        n = Rc @ [-sg, 0, 0.2]; n = n / np.linalg.norm(n) * (1 - u) + np.array([-0.25 * sg, -1, 0]) * u
        kw.update({s: w, f"fingers_{s}": f, f"palm_{s}": n, f"pole_{s}": tuple(Rc @ [0.45 * sg, -1, -0.15])})
    return grip_thumbs(hands(p, **kw))
_guard = boxing()
_jab, _cross = boxing(jab=1), boxing(cross=1)
motion("shadow-boxing", [K(0, _guard), K(0.04, _guard)] + planted(0.04, 0.27, lambda s: boxing(jab=s), n=4) + [K(0.37, _jab)]
       + planted(0.37, 0.7, lambda s: boxing(jab=1 - s), n=4) + [K(1.1, _guard)] + planted(1.1, 1.36, lambda s: boxing(cross=s), n=4)
       + [K(1.46, _cross)] + planted(1.46, 1.84, lambda s: boxing(cross=1 - s), n=4) + [K(2.2, _guard)],
       muscles=("shoulders", "triceps", "abs"), yaw=58)

# Échauffement : marche sur place et grands cercles de bras vers l'arrière (devant → en haut → derrière → en bas).
def warmup(theta):
    a = -np.degrees(theta)                       # angle du bras autour de l'épaule (0 = le long du corps)
    lift = max(0.0, -np.sin(theta))              # bras au-dessus de l'horizontale → épaule qui monte
    phase = (theta / (2 * np.pi)) * 2            # deux pas par cercle
    up = np.sin(np.pi * phase) ** 2              # 0 → 1 → 0 sur chaque pas
    side = "L" if int(phase) % 2 == 0 else "R"
    hip = 48 * up
    return P("stand", **{S("upperleg01", side): sided(side, [-hip, 0, -3]), S("lowerleg01", side): [hip * 1.35, 0, 0],
                         S("foot", side): sided(side, [hip * 0.35, 0, 3])},
             upperarm01=[a, 0, 10], lowerarm01=[-6, 0, 0], clavicle=[0, 0, 12 * lift], **open_hand(0.7))
motion("warmup-march", circle_keys(16, 3.2, warmup), muscles=("shoulders", "quads"), yaw=55)

# Pas chassés : deux pas vers la droite, deux vers la gauche ; les pieds se posent vraiment, le bassin suit.
def side_steps():
    step, lift, soft = 0.30 * S_LEG, 0.07 * S_LEG, -0.035 * S_LEG
    def pose(fl, fr, cx, lifted=None):
        p = P("stand", root={"offset": [cx, soft, 0]}, upperarm01=[-10, 0, 9], lowerarm01=[-40, 0, 0], **open_hand(0.6))
        tl = ankle("L", x=fl, lift=lift if lifted == "L" else 0)
        tr = ankle("R", x=fr, lift=lift if lifted == "R" else 0)
        return legs(p, L=tl, R=tr, pole_L=(0.2, 0, 1), pole_R=(-0.2, 0, 1))
    feet = {"L": float(ANK["L"][0]), "R": float(ANK["R"][0])}
    cx, t = 0.0, 0.0
    keys = [K(0, pose(feet["L"], feet["R"], cx))]
    # deux pas vers la droite (−X, le pied droit mène), puis deux vers la gauche ; le pied qui bouge est levé à mi-course
    for direction, lead in ((-1, "R"), (-1, "R"), (1, "L"), (1, "L")):
        for mover, share in ((lead, 0.22), (other(lead), 0.28)):
            start = feet[mover]; end = start + direction * step
            mid = dict(feet); mid[mover] = (start + end) / 2
            t += 0.32; keys.append(K(t, pose(mid["L"], mid["R"], cx + direction * step * share, mover)))
            feet[mover] = end; cx += direction * step / 2
            t += 0.28; keys.append(K(t, pose(feet["L"], feet["R"], cx)))
    return keys
motion("side-steps", side_steps(), muscles=("quads", "glutes", "calves"), yaw=8)

# Squats partiels : on descend bras vers l'avant, on remonte en levant les bras au-dessus de la tête.
def squat(depth, back, lean, arms):
    depth, back = depth * S_LEG, back * S_LEG
    p = P("stand", root={"rot": [["x", lean]], "offset": [0, -depth, -back]}, spine04=[4, 0, 0], neck01=[-lean * 0.45, 0, 0], **arms)
    return legs(p, L=ankle("L"), R=ankle("R"), pole_L=(0.15, 0, 1), pole_R=(-0.15, 0, 1))
arms_up = dict(upperarm01=[-8, 0, 168], lowerarm01=[-4, 0, 0], clavicle=[0, 0, 10], **open_hand(0.8))
arms_front = dict(upperarm01=[-62, 0, 8], lowerarm01=[-8, 0, 0], **open_hand(0.5))
top = P("stand", **arms_up)
motion("half-squat-arms", [K(0, top), K(1.8, squat(0.2, 0.09, 24, arms_front)), K(2.3, squat(0.2, 0.09, 24, arms_front)), K(4.0, top), K(4.6, top)],
       muscles=("quads", "glutes", "shoulders"), yaw=60)

# Squat sur chaise : s'asseoir en 3 secondes, se relever en 1, sans les mains.
seat = squat(0.4, 0.2, 34, dict(upperarm01=[-78, 0, 6], lowerarm01=[-4, 0, 0], **open_hand(0.6)))
motion("chair-squat", [K(0, "stand"), K(3, seat), K(3.3, seat), K(4.3, "stand", "out"), K(5.2, "stand")],
       muscles=("quads", "glutes"), yaw=70, props=(prop("chair", "root", 1, (0, -0.075, -0.17)),))

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

# Rowing serviette : un pied un peu avancé, à plat sur la serviette, talons au sol, genoux souples, buste penché
# d'environ 35° dos long. Chaque main tient un bout ; on tire des bras tendus vers le pied jusqu'aux côtes basses,
# coudes en arrière, omoplates serrées.
ROW_LEAN = 35.0
ROW_FEET = {"L": np.array([0.03 * S_HIP, FLOOR_ANKLE, ANK["L"][2] + 0.11 * S_LEG]),
            "R": np.array([-0.15 * S_HIP, FLOOR_ANKLE, ANK["R"][2] - 0.01 * S_LEG])}
def row_body(u):
    p = P("stand", root={"rot": [["x", ROW_LEAN]], "offset": [-0.04 * S_HIP, -0.02 * S_LEG, -0.085 * S_LEG]},
          spine01=[-4 * u, 0, 0], neck01=[-16, 0, 0], head=[-6, 0, 0], clavicle=[0, 4 + 14 * u, -2 * u], **fist(1.0))
    return legs(p, L=ROW_FEET["L"], R=ROW_FEET["R"], pole_L=(0.2, 0, 1), pole_R=(-0.3, 0, 1))
def row_targets(u):
    J = joints(row_body(u)); out = {}
    for s, sg in (("L", 1), ("R", -1)):
        sh = J[f"upperarm01.{s}"]
        aim = np.array([sg * (SH[0] + 0.06), 0.0, ROW_FEET["L"][2] + 0.10]) - sh
        a = sh + 0.965 * ARM * aim / np.linalg.norm(aim)
        b = np.array([sg * (SH[0] * ROW_WIDE), J["spine03"][1] + ROW_END[0], J["spine03"][2] + ROW_END[1]])
        out[s] = a + (b - a) * u
    return out
ROW_WIDE, ROW_END = 1.06, (0.0, 0.135)
def row(u):
    p = row_body(u); T = row_targets(u)
    for s, sg in (("L", 1), ("R", -1)):
        pole = (0.35 * sg, 0.25, -1)
        q = with_bones(p, ik.arm(p, s, T[s], pole)); J = joints(q)
        f = J[f"wrist.{s}"] - J[f"lowerarm01.{s}"]                     # poing dans l'axe de l'avant-bras
        p = hands(p, **{s: T[s], f"fingers_{s}": f, f"palm_{s}": [-sg, 0.15, 0], f"pole_{s}": pole})
    return grip_thumbs(p)
# Serviette : deux brins, de chaque poing au creux du pied avant (indices de sommets de la peau, propres à chaque corps).
def towel_vertices():
    v, n = MESH.v, MESH.n
    out = []
    for s, sg in (("L", 1), ("R", -1)):
        w, f3 = ik.H[f"wrist.{s}"], ik.H[f"finger3-1.{s}"]
        f = f3 - w; palm = sg * np.cross(f, ik.H[f"finger2-1.{s}"] - ik.H[f"finger5-1.{s}"]); palm /= np.linalg.norm(palm)
        c = w + 0.62 * f + 0.012 * palm
        idx = HAND_VERTS[s][(n[HAND_VERTS[s]] @ palm) > 0.5]
        out.append(int(idx[np.argmin(np.linalg.norm(v[idx] - c, axis=1))]))
    foot = region(("foot", "toes"), "L")
    a, t = ik.H["foot.L"], ik.H["toes.L"]
    c = np.array([(a[0] + t[0]) / 2, 0.0, a[2] + 0.6 * (t[2] - a[2])])
    idx = foot[n[foot, 1] < -0.6]
    i_foot = int(idx[np.argmin(np.linalg.norm(v[idx] - c, axis=1))])
    return [out[0], i_foot, out[1]]
TOWEL = dict(prop("towel", None, 0), vertices=towel_vertices())
_free = {s: np.setdiff1d(np.arange(len(MESH.v)), np.concatenate([HAND_VERTS[s], region(("foot", "toes"), "L")])) for s in "LR"}
def towel_clearance(pose):
    """Plus petite distance entre l'axe d'un brin et la peau (hors main qui le tient et pied posé dessus)."""
    v = posed_skin(pose)[0]; a, f, b = (v[i] for i in TOWEL["vertices"]); worst = 9.0
    for s, h in (("L", a), ("R", b)):
        pts = v[_free[s]]; pts = pts[np.linalg.norm(pts - f, axis=1) > 0.10]
        d = h - f; t = np.clip(((pts - f) @ d) / (d @ d), 0, 1)
        worst = min(worst, float(np.linalg.norm(pts - (f + t[:, None] * d), axis=1).min()))
    return worst
# Mains assez écartées pour que les brins (22 mm de rayon) passent à 2 cm au moins du genou et de la cuisse.
for _ in range(8):
    if min(towel_clearance(row(u)) for u in (0.5, 0.8, 1.0)) >= 0.042: break
    ROW_END = (ROW_END[0], ROW_END[1] + 0.012); ROW_WIDE += 0.02
print("serviette : écartement des mains", round(ROW_WIDE, 2), "dégagement", [round(towel_clearance(row(u)), 3) for u in (0, 0.5, 1)])
row_start, row_end = row(0), row(1)
motion("towel-row", [K(0, row_start)] + planted(0, 1.5, row, n=5) + [K(2.3, row_end)] + planted(2.3, 3.6, lambda s: row(1 - s), n=5)
       + [K(4.0, row_start)], muscles=("upperBack", "biceps"), yaw=70, props=(TOWEL,))

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

motion("calf-raises", [K(0, "stand"), K(1, P("stand", foot=[28, 0, 5], toes=[-34, 0, 0]), "out"),
                       K(1.4, P("stand", foot=[28, 0, 5], toes=[-34, 0, 0])), K(4, "stand", "inOut")], muscles=("calves",), yaw=70)

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
def quad_stretch(knee=150.0, hip=6.0, foot=38.0, u=1.0, grab=True):
    """Côté gauche. knee, hip, foot : genou plié, cuisse en arrière (> 0) ou en avant, pointe tendue ; grab : main sur le pied."""
    p = P("stand", root={"offset": [-0.03 * S_HIP * u, 0, 0]}, upperleg01_L=[hip, 0, -3 * u], lowerleg01_L=[knee, 0, 0],
          foot_L=[foot, 0, 0], upperarm01_R=[0, 0, -14 * u], lowerarm01_R=[-10 * u, 0, 0], **open_hand(0.4, "R"))
    p = legs(p, R=ankle("R"))
    if not grab:
        return p
    R, J = ik.fk(p); Rf = R["foot.L"]
    axis, top, inward = Rf @ [0, 0, 1.0], Rf @ [0, 1.0, 0], Rf @ [-1.0, 0, 0]
    mid = J["foot.L"] + 0.5 * (J["toes.L"] - J["foot.L"])             # cou-de-pied
    f = inward + 0.25 * axis; f /= np.linalg.norm(f)
    p = P(p, **{S(k, "L"): [x * 0.45 for x in v] for k, v in fist(1.0).items()})
    return hands(p, L=mid + top * 0.04 - f * 0.12 + axis * 0.03, fingers_L=f, palm_L=-top, pole_L=(1, 0.1, -0.45))
_quad = quad_stretch()
_quad_r = mirror_pose(_quad)
def quad_keys(t0, flip):
    f = mirror_pose if flip else (lambda p: p)
    # Le pied décolle genou un peu en avant (il ne traîne pas au sol), le talon monte, puis la main le saisit.
    # (le talon se lève d'abord, la pointe du pied reste posée au même endroit jusqu'à ce que le pied quitte le sol)
    toe = STAND["toes.L"]; a = ANK["L"] - toe; c, sn = np.cos(np.radians(34)), np.sin(np.radians(34))
    off = legs(quad_stretch(0, 0, 0, 0.6, False), L=toe + [a[0], a[1] * c - a[2] * sn, a[1] * sn + a[2] * c], foot_pitch_L=34, toes_L=-34)
    up = legs(quad_stretch(0, 0, 0, 1.0, False), L=ankle("L", lift=0.17 * S_LEG, dz=-0.10 * S_LEG), foot_pitch_L=45)
    hold, off, up, high = f(_quad), f(off), f(up), f(quad_stretch(118, 0, 30, 1.0, False))
    return [K(t0 + 0.5, off), K(t0 + 0.8, up, "linear"), K(t0 + 1.3, high, "out"), K(t0 + 2.0, hold), K(t0 + 5.0, hold), K(t0 + 5.6, high),
            K(t0 + 6.0, up, "in"), K(t0 + 6.3, off, "linear"), K(t0 + 6.8, "stand")]
# Ouverture de la poitrine : omoplates serrées, bras tendus vers l'arrière et le bas, mains écartées paumes face à face
# (rapprochées, elles se traversaient derrière le dos).
chest_open = hands(P("stand", clavicle=[0, 16, 0], spine01=[-7, 0, 0], neck01=[-4, 0, 0], head=[-6, 0, 0]),
                   L=[0.1, float(STAND["root"][1] - 0.02), float(STAND["root"][2] - 0.16)],
                   R=[-0.1, float(STAND["root"][1] - 0.02), float(STAND["root"][2] - 0.16)],
                   fingers_L=[0, -1, -0.35], palm_L=[-1, 0, 0], fingers_R=[0, -1, -0.35], palm_R=[1, 0, 0],
                   pole_L=(0.8, -0.6, -0.4), pole_R=(-0.8, -0.6, -0.4))
motion("cooldown-stretch", [K(0, "stand")] + quad_keys(0, False) + quad_keys(6.8, True)
       + [K(15.1, chest_open), K(17.6, P(chest_open, **CHEST_IN)), K(19.6, chest_open), K(21.1, "stand")], muscles=("quads", "chest"), yaw=140)

# ─── Mobilité, épaules, nuque ───
# Grands cercles d'épaules vers l'arrière : avant → haut → arrière → bas. Les bras restent pendants.
def roll(theta):
    z = 7 + 17 * np.sin(theta)                # élévation
    y = -15 * np.cos(theta)                   # recul (> 0) ou avancée (< 0) de l'omoplate
    return P("stand", clavicle=[0, y, z], upperarm01=[0, 0, -z + 3], lowerarm01=[-10, 0, 0])
motion("shoulder-rolls", circle_keys(12, 4.2, roll), muscles=("shoulders", "upperBack"), yaw=58)

shrug_up = dict(clavicle=[0, 0, 24], upperarm01=[0, 0, -22], lowerarm01=[-6, 0, 0])
motion("shrugs", [K(0, "stand"), K(1.2, P("stand", **shrug_up, neck01=[-2, 0, 0])), K(3.2, P("stand", **shrug_up)),
                  K(3.6, "stand", "out"), K(5, "stand")], muscles=("upperBack", "neck"), yaw=25)
_chair_shrug = keep_hands(P("chairSit", clavicle=[0, 0, 22]), "chairSit")
motion("chair-shrugs", [K(0, "chairSit"), K(1.2, _chair_shrug), K(3.2, _chair_shrug),
                        K(3.6, "chairSit", "out"), K(5, "chairSit")], muscles=("upperBack", "neck"), yaw=30, props=(CHAIR,))

def neck_tilt(base):
    tilt = lambda a: P(base, neck01=[0, 0, a * 0.35], neck02=[0, 0, a * 0.25], neck03=[0, 0, a * 0.2], head=[0, 0, a * 0.2])
    return [K(0, base), K(1.5, tilt(32)), K(3, tilt(32)), K(4.5, base), K(6, tilt(-32)), K(7.5, tilt(-32)), K(9, base)]
motion("neck-tilt", neck_tilt("stand"), muscles=("neck",), yaw=10)
# Menton rentré, vu de profil : la tête part d'une position un peu avancée (posture d'écran) et recule à l'horizontale,
# le bas du cou se redresse, le menton rentre (double menton) sans que le regard ne monte ni ne descende.
_chin0 = P("stand", neck01=[7, 0, 0], neck02=[3, 0, 0], head=[-10, 0, 0])
_chin1 = P("stand", neck01=[-15, 0, 0], neck02=[-7, 0, 0], neck03=[-2, 0, 0], head=[30, 0, 0], spine01=[-2, 0, 0])
motion("chin-tucks", [K(0, _chin0), K(1.2, _chin1), K(4.2, _chin1), K(5.2, _chin0), K(6.2, _chin0)], muscles=("neck",), yaw=90, pitch=4)
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
def trap_keys(t0, flip):
    f = mirror_pose if flip else (lambda p: p)
    return [K(t0 + 1.0, f(_trap_way)), K(t0 + 2.0, f(trap)), K(t0 + 6.0, f(trap)), K(t0 + 7.0, f(_trap_way)), K(t0 + 8.0, "stand")]
motion("trap-stretch", [K(0, "stand")] + trap_keys(0, False) + trap_keys(8, True), muscles=("neck", "upperBack"), yaw=15)

# Ouverture de poitrine dans l'encadrement d'une porte : avant-bras sur les montants, le buste avance.
# Les montants (7 cm de large, intérieur à 46,5 cm de l'axe) sont juste devant les épaules : paumes et avant-bras à plat
# sur leur face, coudes à hauteur d'épaule, mains au-dessus. Les mains ne bougent plus ; le corps avance d'un bloc depuis
# les chevilles, la poitrine passe entre les montants et s'ouvre. Vue de trois quarts arrière : on voit les appuis.
DOOR_Z = float(STAND["upperarm01.L"][2] + 0.085)             # face des montants côté personnage
UPPER_ARM = float(np.linalg.norm(STAND["lowerarm01.L"] - SH))
def doorway(lean):
    p = P("stand", root={"rot": [["x", 50 * lean]], "offset": [0, 0, lean]}, spine01=[-3 - lean * 40, 0, 0], clavicle=[0, 60 * lean, 0],
          neck01=[-50 * lean, 0, 0], head=[-3, 0, 0], **open_hand(1.0))
    p = legs(p, L=ankle("L"), R=ankle("R"))
    for side, sg in (("L", 1), ("R", -1)):
        sh = STAND[f"upperarm01.{side}"]
        dz = DOOR_Z - PALM - 0.017 - sh[2]; dy = -0.02; back = 0.028          # l'avant-bras, plus épais au coude, s'écarte un peu
        elbow = sh + [sg * np.sqrt(UPPER_ARM ** 2 - (dz - back) ** 2 - dy ** 2), dy, dz - back]
        out = float(np.clip((0.5 - abs(elbow[0])) / FOREARM, 0.0, 0.75))                    # avant-bras incliné jusqu'au montant
        fore = np.array([sg * out, np.sqrt(1 - out ** 2 - (back / FOREARM) ** 2), back / FOREARM])
        # la main se redresse le long du montant (poignet incliné de 20° au plus), au lieu de dépasser sur le côté
        tilt = np.radians(max(0.0, np.degrees(np.arcsin(out)) - 20)); up = np.array([sg * np.sin(tilt), np.cos(tilt), 0.0])
        p = fixed_hand(p, side, elbow + FOREARM * fore, up, [0, 0, 1], tuple(elbow - joints(p)[f"upperarm01.{side}"]))
        amt = rhythm_amount(arm_elevation(p, side))
        if amt > 0.02:
            p = fixed_hand(add_rhythm(p, side, amt), side, elbow + FOREARM * fore, up, [0, 0, 1], tuple(elbow - joints(p)[f"upperarm01.{side}"]))
    return p
_door_in = 0.11 * S_LEG
motion("doorway-stretch", [K(0, doorway(0.0))] + planted(0, 2, lambda s: doorway(_door_in * s), n=4) + [K(5, doorway(_door_in))]
       + planted(5, 7, lambda s: doorway(_door_in * (1 - s)), n=4) + [K(7.6, doorway(0.0))],
       muscles=("chest", "shoulders"), yaw=150, pitch=10, props=(prop("door", "root", 0, (0, 0, DOOR_Z + 0.06 - float(STAND["root"][2])), floor=True),))

squeeze = P("stand", clavicle=[0, 20, -2], upperarm01=[14, 14, 6], lowerarm01=[-20, 0, 0], spine01=[-5, 0, 0])
motion("scapular-squeeze", [K(0, "stand"), K(1, squeeze), K(5, squeeze), K(6, "stand")], muscles=("upperBack",), yaw=155)

# Cercles de hanches : le bassin dessine un cercle, les pieds restent posés, le buste reste au-dessus.
def hip_circle(theta):
    r = 0.08 * S_LEG
    ox, oz = r * np.cos(theta), r * np.sin(theta)
    tilt_z, tilt_x = 8 * np.cos(theta), -7 * np.sin(theta)
    p = P("handsHips", root={"rot": [["z", -tilt_z], ["x", tilt_x]], "offset": [ox, -0.025, oz]},
          spine05=[-tilt_x * 0.6, 0, tilt_z * 0.6], spine03=[-tilt_x * 0.7, 0, tilt_z * 0.7], spine01=[-tilt_x * 0.4, 0, tilt_z * 0.4])
    # Les mains restent posées sur les hanches pendant que le bassin tourne.
    return keep_hands(legs(p, L=ankle("L"), R=ankle("R")), "handsHips")
motion("hip-circles", circle_keys(12, 4.8, hip_circle), muscles=("lowerBack", "abs", "glutes"), yaw=35)

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
motion("ankle-circles", [K(0, _a0)] + ankle_keys(0, "R") + ankle_keys(5.6, "L"), muscles=("calves", "shins"), yaw=35, pitch=3,
       props=(prop("wall", "wrist.L", 0, (_wall, 0, -0.02), floor=True),))

side_bend = lambda a: P("stand", upperarm01=[0, 0, 168], lowerarm01=[-6, 0, 0], clavicle=[0, 0, 8], spine03=[0, 0, a * 0.4], spine02=[0, 0, a * 0.35],
                        spine01=[0, 0, a * 0.25], **open_hand(0.9))
motion("overhead-stretch", [K(0, "stand"), K(2, side_bend(0)), K(4, side_bend(22)), K(6, side_bend(0)), K(8, side_bend(-22)), K(10, side_bend(0)), K(12, "stand")],
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
_up = P(mountain, clavicle=[0, 0, 10], spine01=[-4, 0, 0], neck01=[-6, 0, 0], head=[-8, 0, 0])
salute = joined_hands(hands(_up, L=[PALM, OVERHEAD[0], OVERHEAD[1]], R=[-PALM, OVERHEAD[0], OVERHEAD[1]], fingers_L=[0, 1, 0], palm_L=[-1, 0, 0],
                             fingers_R=[0, 1, 0], palm_R=[1, 0, 0], pole_L=(1, 0, -0.3), pole_R=(-1, 0, -0.3)))
motion("arm-raise", [K(0, mountain), K(2.4, arms_front_up), K(4.2, salute), K(5.6, salute), K(7.4, arms_front_up), K(9.4, mountain), K(10.4, mountain)],
       muscles=("shoulders",), yaw=40, props=(MAT,))

# Flexion avant douce : le bassin bascule et recule, genoux fléchis, pieds posés ; le dos s'enroule, la tête pend dans le
# prolongement (nuque relâchée), les bras pendent à la verticale sous les épaules. Remontée en déroulant le dos : le
# bassin se redresse d'abord, la tête remonte en dernier.
def fold(u, curl=None):
    """u : bascule du bassin (0 debout, 1 flexion complète) ; curl : enroulement du dos et de la nuque (u par défaut)."""
    c = u if curl is None else curl
    p = P("stand", root={"rot": [["x", 68 * u]], "offset": [0, -0.07 * S_LEG * u, -0.11 * S_LEG * u]}, spine05=[6 * c, 0, 0], spine04=[9 * c, 0, 0],
          spine03=[10 * c, 0, 0], spine02=[9 * c, 0, 0], spine01=[8 * c, 0, 0], neck01=[14 * c, 0, 0], neck02=[10 * c, 0, 0], neck03=[6 * c, 0, 0],
          head=[12 * c, 0, 0], **open_hand(0.5))
    p = legs(p, L=ankle("L"), R=ankle("R"), pole_L=(0.1, 0, 1), pole_R=(-0.1, 0, 1))
    J = joints(p)
    for s, sg in (("L", 1), ("R", -1)):
        sh = J[f"upperarm01.{s}"]
        w = [sh[0] + 0.02 * sg, max(sh[1] - 0.975 * ARM, 0.21), sh[2] + 0.03]              # doigts au ras du sol, pas dedans
        p = with_bones(p, ik.arm(p, s, w, (sg, 0, -0.4)))
    return p
_fold = fold(1.0)
motion("forward-fold", [K(0, mountain), K(3, _fold), K(6, _fold), K(7.6, fold(0.45, 0.85)), K(9.4, mountain), K(10, mountain)],
       muscles=("hamstrings", "lowerBack"), yaw=70, props=(MAT,))

# Guerrier II : pieds très écartés, genou avant plié au-dessus de la cheville, bras à l'horizontale, regard sur la main avant.
def warrior(bend):
    """bend = 0 : jambes tendues, pieds écartés ; 1 : guerrier II (côté gauche devant)."""
    root = P("stand", root={"offset": [0.1 * bend * S_LEG, (-0.14 - 0.09 * bend) * S_LEG, 0]},
             upperarm01=[0, 0, 86 * min(1, bend * 1.6)], lowerarm01=[-3, 0, 0], **open_hand(1.0),
             neck01=[0, 26 * bend, 0], neck02=[0, 16 * bend, 0], head=[0, 26 * bend, 0])
    # écart symétrique : les pieds restent aux mêmes endroits quand on change de côté
    front = np.array([0.57 * S_LEG, FLOOR_ANKLE, ANK["L"][2]]); back = np.array([-0.57 * S_LEG, FLOOR_ANKLE, ANK["R"][2]])
    p = legs(root, L=front, R=back, pole_L=(1, 0, 0.25), pole_R=(0, 0, 1),
             foot_yaw_L=90 * min(1, bend * 1.6), foot_yaw_R=12)
    return p
wl = warrior(1.0); wt = warrior(0.45); w0 = warrior(0.0)
wr, wrt, w0r = mirror_pose(wl), mirror_pose(wt), mirror_pose(w0)
motion("warrior-two", [K(0, w0), K(1.6, wt), K(3.2, wl), K(5.2, P(wl, **CHEST_IN)), K(7.2, wl), K(8.6, wt), K(10.0, w0),
                       K(11.6, wrt), K(13.2, wr), K(15.2, P(wr, **CHEST_IN)), K(17.2, wr), K(18.6, wrt), K(20.0, w0r)],
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
def tree_arms(p, u):
    """u : 0 mains jointes devant la poitrine, 1 au-dessus de la tête ; les mains montent jointes devant le visage."""
    x0 = joints(p)["spine01"][0]
    y = CHEST[0] + (OVERHEAD[0] - CHEST[0]) * u
    z = CHEST[1] + (OVERHEAD[1] - CHEST[1]) * u + 0.12 * np.sin(np.pi * u) ** 2
    p = P(p, clavicle=[0, 0, 10 * u], **open_hand(1.0))
    if u > 0.5: p = P(p, spine01=[-4 * (2 * u - 1), 0, 0], neck01=[-6 * (2 * u - 1), 0, 0], head=[-8 * (2 * u - 1), 0, 0])
    t = 0.25 * (1 - u); k = -0.5 * (1 - u)
    # Les deux mains sont placées en miroir autour du sternum, sans mise en contact séparée : elles restent jointes
    # et symétriques pendant toute la montée.
    for s, sg in (("L", 1), ("R", -1)):
        target = [x0 + sg * PALM, y, z]
        amt = rhythm_amount(arm_elevation(p, s, target))
        if amt > 0.02: p = add_rhythm(p, s, amt)
        p = ik.place_hand(p, s, target, [0, 1, t], [-sg, 0, 0], (sg, k, -0.3))
    p = joined_hands(p); p["_pinned"] = ["L", "R"]
    return placed(p)
def tree_keys(flip, t0):
    f = (lambda p: placed(mirror_pose(p)) if is_placed(p) else mirror_pose(p)) if flip else (lambda p: p)
    prayer, up = f(tree_arms(_tree1, 0)), f(tree_arms(_tree1, 1))
    # Le pied arrive contre le mollet par le côté (et le quitte de même) : en ligne droite, il traverserait la jambe d'appui.
    near = blend(_tree0, tree_arms(_tree1, 0), 0.75)
    near = f(legs(near, L=ankle("L"), R=joints(tree_legs(True, away=0.07))["foot.R"], pole_R=(-1, -0.15, 0.4), foot_rot_R=TREE_FOOT))
    rise = planted(t0 + 2.6, t0 + 4.2, lambda s: f(tree_arms(_tree1, s)), n=6)
    fall = planted(t0 + 7.8, t0 + 9.2, lambda s: f(tree_arms(_tree1, 1 - s)), n=6)
    return ([K(t0, f(_tree0)), K(t0 + 1.1, near), K(t0 + 1.6, prayer), K(t0 + 2.6, prayer)] + rise
            + [K(t0 + 6.0, P(up, **BREATH_IN)), K(t0 + 7.8, up)] + fall
            + [K(t0 + 10.2, prayer), K(t0 + 10.7, near), K(t0 + 11.6, f(_tree0))])
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
def quad(curve, neck, head, clav):
    """curve : flexion totale de la colonne (> 0 dos rond) ; clav : omoplates écartées (< 0) ou serrées (> 0)."""
    sp = {f"spine0{5 - i}": [curve * w, 0, 0] for i, w in enumerate((0.24, 0.24, 0.22, 0.18, 0.12))}
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
def catcow(u):
    """u : −1 vache (dos creux, regard devant), 0 dos plat, 1 chat (dos rond, menton rentré)."""
    return quad(72 * u, 24 * u, 22 * u, -12 * u) if u >= 0 else quad(46 * u, 28 * u, 16 * u, -8 * u)
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
def child_body(pitch, hip, foot, extra=(0, 0, 0, 0)):
    w = (0.2, 0.24, 0.24, 0.2, 0.12)
    sp = {f"spine0{5 - i}": [CHILD_CURVE * w[i], 0, 0] for i in range(5)}
    sp["spine05"][0] += extra[0]; sp["spine03"][0] += extra[1]; sp["spine01"][0] += extra[2]
    return P("stand", root={"rot": [["x", pitch], ["y", 90]]}, upperleg01=[-hip, CHILD_ROT, CHILD_ABD], lowerleg01=[CHILD_KNEE, 0, 0], foot=[foot, 0, 0],
             **sp, neck01=[CHILD_NECK * 0.5 + extra[3], 0, 0], head=[CHILD_NECK * 0.5, 0, 0])
def child_res(x):
    v = posed_skin(child_body(x[0], x[1], x[2]))[0]
    knee = v[_shin, 1].min()
    return [(v[FOREHEAD, 1].min() - knee) * 100, (v[_feet, 1].min() - knee) * 100, (v[_shin, 1].max() - knee - CHILD_SHIN) * 100]
_st = posed_skin(P("stand"))[0]
CHILD_SHIN = float(np.ptp(_st[_shin, 2])) + 0.004               # tibia couché : épaisseur du mollet au-dessus du sol
_sol = least_squares(child_res, [70.0, 130.0, 76.0], bounds=([30, 90, 55], [110, 170, 90]), diff_step=0.01).x
print("enfant : bassin, hanches, pieds", np.round(_sol, 1), "résidus", np.round(child_res(_sol), 2))
def child_pose(breath=0.0):
    p = child_body(*_sol)
    if breath:
        # respiration « dans le dos » : le milieu du dos monte, bassin, front et mains ne bougent pas
        J0 = joints(p); R0 = ik.fk(p)[0]["head"]
        def res(d):
            q = child_body(*_sol, extra=(d[0], 5.0 * breath, d[1], d[2])); J = joints(q); R = ik.fk(q)[0]["head"]
            return [J["head"][0] - J0["head"][0], J["head"][1] - J0["head"][1], (R @ R0.T)[1, 0]]
        d = least_squares(res, [-2.0, -2.0, -1.0], x_scale=1.0, diff_step=1e-3).x
        p = child_body(*_sol, extra=(d[0], 5.0 * breath, d[1], d[2]))
        assert np.abs(res(d)).max() < 5e-3, res(d)
    floor = posed_skin(child_body(*_sol))[0][_shin, 1].min()
    p = P(p, **open_hand(1.0)); wy = floor + 0.024
    def reach(q):
        kw = {}
        for s, sg in (("L", 1), ("R", -1)):
            sh = joints(q)[f"upperarm01.{s}"]
            d = np.sqrt((0.985 * ARM) ** 2 - (sh[1] - wy) ** 2)             # bras presque tendus jusqu'au sol
            kw.update({s: [sh[0] + d, wy, sh[2]], f"fingers_{s}": [1, 0, 0], f"palm_{s}": [0, -1, 0], f"pole_{s}": (0, 0.2, -sg)})
        return hands(p, **kw)
    q = reach(child_body(*_sol))
    p = reach(reach(q))                                 # l'épaule monte avec le bras (rythme scapulaire) : objectif repris
    return flat_hands(p)
child = child_pose(0)
_cv = posed_skin(child)[0]; _cx = float((_cv[:, 0].max() + _cv[:, 0].min()) / 2 - joints(child)["root"][0])
assert np.ptp(_cv[:, 0]) < 1.8, "posture de l'enfant plus longue que le tapis"
motion("child-pose", [K(0, child), K(3, child_pose(1)), K(6, child)], muscles=("lowerBack",), yaw=0,
       props=(prop("mat", "root", 0, (_cx, 0, 0), floor=True),))

# ─── Au lit : scan corporel et étirements du soir ───
BED_TOP = 0.5
BED_LYING = prop("bed", "root", 0, (-0.05, 0, 0), floor=True)            # allongé dans la longueur, tête vers −X
PILLOW = prop("pillow", "head", 0, (-0.03, -0.085, 0))                    # sous l'arrière de la tête
BED_SIT = prop("bed", "root", 0, (0, -0.105, -0.55))                      # assis au bord, le lit derrière soi
HEAD_ON_PILLOW = dict(neck01=[16, 0, 0], head=[6, 0, 0])

lying_bed = P("supine", upperarm01=[0, 30, 8], lowerarm01=[-8, 0, 0], **HEAD_ON_PILLOW, **open_hand(0.5))
motion("bed-rest", breathe(lying_bed, cycle=6), yaw=8, pitch=30, props=(BED_LYING, PILLOW), support=BED_TOP)

motion("bed-sit-breathe", breathe("chairSit"), yaw=28, pitch=10, props=(BED_SIT,))
motion("bed-neck", neck_tilt("chairSit"), muscles=("neck", "upperBack"), yaw=12, pitch=10, props=(BED_SIT,))

# Arrière des cuisses : au bord du lit, une jambe tendue talon au sol, buste penché en avant dos long.
_seat = joints("chairSit")
LEG = float(np.linalg.norm(STAND["lowerleg01.L"] - STAND["upperleg01.L"]) + np.linalg.norm(STAND["foot.L"] - STAND["lowerleg01.L"]))
# Jambe tendue : seul le talon est posé, pointe du pied vers le haut (cheville fléchie de 12° vers soi). La hauteur de la
# cheville est réglée sur la peau : le talon touche le sol au niveau de la plante de l'autre pied.
_hip = _seat["upperleg01.L"]; _foot_L, _foot_R = region(("foot", "toes"), "L"), region(("foot", "toes"), "R")
HAM_ANKLE = np.array([float(_hip[0]), float(_seat["foot.R"][1]) + 0.05, 0.0])
for _ in range(6):
    _drop = _hip[1] - HAM_ANKLE[1]
    HAM_ANKLE[2] = _hip[2] + float(np.sqrt(LEG ** 2 - _drop ** 2)) * 0.985
    HAM_PITCH = -(90 - float(np.degrees(np.arcsin(_drop / (LEG * 0.985))))) - 12       # perpendiculaire au tibia, puis fléchi
    _hp = legs(legs(P("chairSit"), L=HAM_ANKLE, foot_pitch_L=HAM_PITCH), R=_seat["foot.R"])
    _hv = posed_skin(_hp)[0]
    HAM_ANKLE[1] -= float(_hv[_foot_L, 1].min() - _hv[_foot_R, 1].min())
def hamstring(side, hinge):
    o = other(side)
    p = P("chairSit", root={"rot": [["x", hinge]]}, spine04=[-hinge * 0.15, 0, 0], neck01=[-hinge * 0.4, 0, 0], **open_hand(0.6))
    p = legs(p, **{side: HAM_ANKLE}, **{f"foot_pitch_{side}": HAM_PITCH})
    p = legs(p, **{o: _seat[f"foot.{o}"]})
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
hL0, hL1 = hamstring("L", 0), hamstring("L", 30)
# La jambe se tend pied décollé du sol, puis le talon se pose.
def ham_way(f, lift):
    p = legs(P("chairSit"), L=_seat["foot.L"] + (HAM_ANKLE - _seat["foot.L"]) * f + [0, lift, 0], foot_pitch_L=HAM_PITCH * f)
    return legs(p, R=_seat["foot.R"])
_hway = [ham_way(0.12, 0.04), ham_way(0.5, 0.075), ham_way(0.93, 0.05)]
def ham_keys(t0, flip):
    f = mirror_pose if flip else (lambda p: p)
    w = [f(p) for p in _hway]; h0, h1 = f(hL0), f(hL1)
    return [K(t0 + 0.3, w[0]), K(t0 + 0.8, w[1], "linear"), K(t0 + 1.3, w[2], "linear"), K(t0 + 1.8, h0, "out"), K(t0 + 3.6, h1), K(t0 + 7.6, h1),
            K(t0 + 9.2, h0), K(t0 + 9.7, w[2], "in"), K(t0 + 10.2, w[1], "linear"), K(t0 + 10.7, w[0], "linear"), K(t0 + 11.0, "chairSit", "out")]
motion("bed-hamstring", [K(0, "chairSit")] + ham_keys(0, False) + ham_keys(11.0, True),
       muscles=("hamstrings", "calves"), yaw=62, pitch=8, props=(BED_SIT,))

# Hanches (« 4 ») : cheville droite posée sur le genou gauche, genou droit ouvert, léger penché en avant.
def figure4(lean):
    p = P("chairSit", spine04=[lean * 0.4, 0, 0], spine03=[lean * 0.3, 0, 0], spine02=[lean * 0.2, 0, 0], neck01=[-lean * 0.3, 0, 0],
          **open_hand(0.6))
    knee_L = joints(p)["lowerleg01.L"]
    p = legs(p, R=knee_L + [0.0, 0.1, -0.06], pole_R=(-1, 0.25, 0.35), foot_yaw_R=70, foot_pitch_R=15)
    J = joints(p)
    # Main sur le genou ouvert : doigts vers l'intérieur, dans le prolongement de l'avant-bras (poignet sans inclinaison).
    return hands(p, L=J["foot.R"] + [0.0, 0.06, 0.02], R=J["lowerleg01.R"] + [0.03, 0.07, -0.02],
                 fingers_L=[-0.4, -0.3, 1], palm_L=[0, -1, 0], fingers_R=[0.8, -0.3, 1], palm_R=[0, -1, 0],
                 pole_L=(1, -0.5, -0.3), pole_R=(-1, -0.5, -0.3))
f0, f1 = figure4(0), figure4(16)
f0m, f1m = mirror_pose(f0), mirror_pose(f1)
motion("bed-figure4", [K(0, "chairSit"), K(1.8, f0), K(3.4, f1), K(7.4, f1), K(8.8, f0), K(10.4, "chairSit"),
                       K(12.2, f0m), K(13.8, f1m), K(17.8, f1m), K(19.2, f0m), K(20.8, "chairSit")],
       muscles=("glutes", "lowerBack"), yaw=22, pitch=12, props=(BED_SIT,))

# Torsion allongée sur le lit (bras ouverts sans dépasser du matelas).
knees_bed = P("supine", upperleg01=[-88, 0, 2], lowerleg01=[90, 0, 0], foot=[-6, 0, 0], upperarm01=[0, 0, 52], lowerarm01=[-10, 0, 0],
              **HEAD_ON_PILLOW, **open_hand(0.6))
twist_bed = lambda a: P(knees_bed, root={"rot": [["y", a], ["x", -90], ["y", 90]]}, spine05=[0, -a * 0.3, 0], spine04=[0, -a * 0.3, 0],
                        spine03=[0, -a * 0.4, 0], neck01=[16, a * 0.4, 0])
motion("bed-twist", [K(0, knees_bed), K(2, twist_bed(40)), K(5, twist_bed(40)), K(7, knees_bed), K(9, twist_bed(-40)), K(12, twist_bed(-40)),
                     K(14, knees_bed)], muscles=("lowerBack", "glutes"), yaw=-60, pitch=30, props=(BED_LYING, PILLOW), support=BED_TOP)

# Genoux vers la poitrine : mains posées sur les genoux, coudes ouverts sur les côtés.
def knees_chest(pull):
    p = P("supine", upperleg01=[-128 - 10 * pull, 0, 8], lowerleg01=[138, 0, 0], foot=[25, 0, 0], **HEAD_ON_PILLOW, **open_hand(0.7))
    R, J = ik.fk(p)
    up = R["root"] @ np.array([0, 0, 1.0])               # « avant » du corps allongé : vers le plafond
    toward_feet = R["root"] @ np.array([0, -1.0, 0])
    out = {}
    for s_ in "LR":
        side_dir = R["root"] @ np.array([1.0 if s_ == "L" else -1.0, 0, 0])
        out[s_] = J[f"lowerleg01.{s_}"] + up * 0.06 + toward_feet * 0.02
    return hands(p, L=out["L"], R=out["R"],
                 fingers_L=toward_feet + 0.4 * (R["root"] @ np.array([-1.0, 0, 0])), palm_L=-up,
                 fingers_R=toward_feet + 0.4 * (R["root"] @ np.array([1.0, 0, 0])), palm_R=-up,
                 pole_L=tuple(R["root"] @ np.array([1.0, 0, -0.3])), pole_R=tuple(R["root"] @ np.array([-1.0, 0, -0.3])))
kc0, kc1 = knees_chest(0), knees_chest(1)
motion("bed-knees-chest", [K(0, kc0), K(3, kc1), K(6, kc0)], muscles=("lowerBack", "glutes"), yaw=-28, pitch=24,
       props=(BED_LYING, PILLOW), support=BED_TOP)

# ─── Assis sur une chaise ───
clench = P("chairSit", upperarm01=[-24, 0, 6], lowerarm01=[-80, 0, 0], lowerarm02=[0, 0, 0], wrist=[0, 0, 0], **fist(1))
motion("fists-clench", [K(0, "chairSit"), K(1, clench), K(3, clench), K(3.5, "chairSit", "out"), K(6, "chairSit")],
       muscles=("forearms", "biceps", "hands"), yaw=35, props=(CHAIR,))
_curl = keep_hands(P("chairSit", spine04=[8, 0, 0], spine03=[8, 0, 0], spine02=[4, 0, 0]), "chairSit")
motion("abs-contract", [K(0, "chairSit"), K(1.5, _curl), K(3, _curl), K(4.5, "chairSit")],
       muscles=("abs",), yaw=60, props=(CHAIR,))
legs_out = P("chairSit", ground=False, lowerleg01=[12, 0, 0], foot=[-22, 0, 0])
motion("legs-tense", [K(0, "chairSit"), K(1.5, legs_out), K(3, legs_out), K(4.5, "chairSit")], muscles=("quads", "shins", "calves"),
       yaw=60, props=(CHAIR,))

# ─── Mouvements issus de captures réelles (CMU Graphics Lab, http://mocap.cs.cmu.edu) ───
# (identifiant, fichier BVH, fenêtre en secondes, durée de boucle min/max, vitesse, angle de vue, muscles, redressement)
# Marche : capture « marche lente », ralentie ; marche rapide : capture de marche normale, accélérée (un pied toujours
# au sol, rien d'un petit trot). Redressement : degrés dont le buste, que le reciblage penche trop en avant, est relevé.
MOCAP = [
    ("walk", "007/07_04.bvh", (0.2, 3.7), (1.2, 2.2), 0.85, 70, ("quads", "calves", "glutes"), 2.0),
    ("walk-fast", "007/07_01.bvh", (0.2, 2.6), (0.9, 1.4), 1.3, 70, ("quads", "calves", "glutes", "hamstrings"), 3.0),
]
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
        if upright:                              # buste relevé : rotation vers l'arrière ajoutée au bas de la colonne
            h = np.radians(-upright) / 2; cx, cw = np.sin(h), np.cos(h); b = names.index("spine05")
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
