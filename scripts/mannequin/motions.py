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
    Si la main est au-dessus de l'épaule, la ceinture scapulaire monte d'abord (rythme scapulo-huméral)."""
    p = pose if isinstance(pose, dict) else P(pose)
    for side, target, fingers, palm, pole in (("L", L, fingers_L, palm_L, pole_L), ("R", R, fingers_R, palm_R, pole_R)):
        if target is None:
            continue
        amt = rhythm_amount(arm_elevation(p, side, target))
        if amt > 0.02:
            p = add_rhythm(p, side, amt)
        if fingers is not None:
            p = ik.place_hand(p, side, target, fingers, palm, pole)
        else:
            p = with_bones(p, ik.arm(p, side, target, pole))
        p["_pinned"] = sorted(set(p.get("_pinned", [])) | {side})
    return p

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

_hip = [float(STAND["upperleg01.L"][0] + 0.067), float(STAND["spine04"][1] - 0.03), float(STAND["spine04"][2] + 0.03)]
POSES["handsHips"] = hands(P("stand"), L=_hip, R=[-_hip[0], _hip[1], _hip[2]],
                           fingers_L=[-0.2, -0.45, 1], palm_L=[-1, 0, 0], fingers_R=[0.2, -0.45, 1], palm_R=[1, 0, 0],
                           pole_L=(1, 0.1, -0.6), pole_R=(-1, 0.1, -0.6))

# Assis en tailleur, mains posées sur les genoux, paumes vers le ciel.
_cl = joints(P("crossLeggedLegs"))
POSES["crossLegged"] = hands(P("crossLeggedLegs"),
                             L=_cl["lowerleg01.L"] + [-0.06, 0.08, 0.0], R=_cl["lowerleg01.R"] + [0.06, 0.08, 0.0],
                             fingers_L=[0.35, -0.1, 1], palm_L=[0, 1, 0], fingers_R=[-0.35, -0.1, 1], palm_R=[0, 1, 0],
                             pole_L=(1, -0.6, -0.4), pole_R=(-1, -0.6, -0.4))
# Assis sur une chaise, mains posées à plat sur les cuisses.
_ch = joints(P("chairLegs"))
def _thigh(side, f):
    return _ch[f"upperleg01.{side}"] * (1 - f) + _ch[f"lowerleg01.{side}"] * f
POSES["chairSit"] = hands(P("chairLegs"),
                          L=_thigh("L", 0.55) + [0.0, 0.085, 0.0], R=_thigh("R", 0.55) + [0.0, 0.085, 0.0],
                          fingers_L=[0, -0.15, 1], palm_L=[0, -1, 0], fingers_R=[0, -0.15, 1], palm_R=[0, -1, 0],
                          pole_L=(1, -0.3, -0.6), pole_R=(-1, -0.3, -0.6))

MOTIONS = {}
def motion(mid, keys, muscles=(), yaw=30, props=(), pitch=8, support=None):
    for k in keys:
        k["pose"] = shoulder_rhythm(k["pose"] if isinstance(k["pose"], dict) else P(k["pose"]))
    MOTIONS[mid] = {"keys": keys, "muscles": list(muscles), "camera": {"yaw": yaw, "pitch": pitch}, "props": list(props)}
    if support: MOTIONS[mid]["support"] = support

def prop(kind, anchor=None, key=0, offset=(0, 0, 0), yaw=0, floor=False):
    return {"kind": kind, "anchor": anchor, "key": key, "offset": [float(x) for x in offset], "yaw": float(yaw), "floor": floor}

CHAIR = prop("chair", "root", 0, (0, -0.105, -0.06))
MAT = prop("mat", "root", 0, (0, 0, 0), floor=True)

def breathe(base, cycle=5.0, extra=None):
    inhale = dict(BREATH_IN); inhale.update(extra or {})
    return [K(0, base), K(cycle / 2, P(base, **inhale)), K(cycle, base)]

def circle_keys(n, period, build, ease="linear"):
    """n images clés régulières sur un tour (la dernière reprend la première)."""
    return [K(period * i / n, build(2 * np.pi * i / n), ease) for i in range(n + 1)]

# ─── Respiration ───
motion("breathe-stand", breathe("stand"), yaw=20)
_rib = [float(SH[0] * 0.71), float(STAND["spine02"][1] - 0.01), float(STAND["spine02"][2] + 0.10)]
ribs = hands(P("stand"), L=_rib, R=[-_rib[0], _rib[1], _rib[2]],
             fingers_L=[-0.6, -0.1, 0.8], palm_L=[-1, 0, -0.2], fingers_R=[0.6, -0.1, 0.8], palm_R=[1, 0, -0.2],
             pole_L=(1, -0.4, -0.5), pole_R=(-1, -0.4, -0.5))
motion("rib-breathing", breathe(ribs), muscles=("chest", "abs"), yaw=20)
motion("look-far", [K(0, P("stand", head=[-5, 0, 0])), K(3, P("stand", head=[-6, 12, 0], **BREATH_IN)),
                    K(6, P("stand", head=[-5, 0, 0])), K(9, P("stand", head=[-6, -12, 0], **BREATH_IN)), K(12, P("stand", head=[-5, 0, 0]))], yaw=25)
motion("chair-breathe", breathe("chairSit"), yaw=30, props=(CHAIR,))
motion("seated-breathe", breathe("crossLegged", cycle=6), yaw=15, props=(MAT,))

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
push_top = P("stand", root={"rot": [["x", 42]]}, foot=[-42, 0, 5], upperarm01=[-80, 0, 10], lowerarm01=[-4, 0, 0], wrist=[0, 0, 0],
             neck01=[-14, 0, 0], head=[-6, 0, 0])
push_low = P("stand", root={"rot": [["x", 55]]}, foot=[-55, 0, 5], upperarm01=[-38, 0, 30], lowerarm01=[-92, 0, 0],
             neck01=[-16, 0, 0], head=[-8, 0, 0])
motion("incline-pushup", [K(0, push_top), K(1.8, push_low), K(3, push_top), K(3.6, push_top)],
       muscles=("chest", "triceps", "shoulders"), yaw=75, props=(prop("table", "wrist.L", 0, (-0.12, -0.03, 0.04)),))

bridge_rest = P("supine", upperleg01=[-50, 0, 2], lowerleg01=[100, 0, 0], foot=[-40, 0, 0])
bridge_up = P(bridge_rest, root={"rot": [["x", -90], ["x", -27], ["y", 90]]}, upperleg01=[-24, 0, 2], lowerleg01=[100, 0, 0], foot=[-56, 0, 0])
motion("glute-bridge", [K(0, bridge_rest), K(1.5, bridge_up), K(3.5, bridge_up), K(5, bridge_rest)],
       muscles=("glutes", "hamstrings"), yaw=0, pitch=12, props=(MAT,))

row_base = dict(root={"rot": [["x", 26]]}, upperleg01=[-24, 0, 4], lowerleg01=[14, 0, 0], neck01=[-14, 0, 0])
row_start = P("stand", **row_base, upperarm01=[-34, 0, 4], lowerarm01=[-6, 0, 0], **fist(0.8))
row_end = P("stand", **row_base, upperarm01=[34, 0, 10], lowerarm01=[-96, 0, 0], clavicle=[0, 12, 0], **fist(0.8))
motion("towel-row", [K(0, row_start), K(1.5, row_end), K(2.3, row_end), K(3.6, row_start)],
       muscles=("upperBack", "biceps"), yaw=70)

plank = P("stand", root={"rot": [["x", 76], ["y", 90]]}, upperleg01=[0, 0, 0], lowerleg01=[70, 0, 0], foot=[30, 0, 0],
          upperarm01=[-76, 0, 6], lowerarm01=[-94, 0, 0], neck01=[-10, 0, 0], **fist(0.4))
motion("knee-plank", [K(0, plank), K(3, P(plank, spine01=[-2, 0, 0])), K(6, plank)], muscles=("abs", "shoulders"), yaw=0, props=(MAT,))

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

def quad_stretch():
    p = P("stand", upperleg01_L=[10, 0, -2], lowerleg01_L=[145, 0, 0], foot_L=[30, 0, 0], upperarm01_R=[0, 0, 40], **open_hand(0.4, "R"))
    heel = joints(p)["foot.L"]
    return hands(p, L=heel + [0.02, 0.06, -0.06], pole_L=(0.6, -0.2, -1))
chest_open = hands(P("stand", clavicle=[0, 16, 0], spine01=[-7, 0, 0], neck01=[-4, 0, 0], head=[-6, 0, 0]),
                   L=[0.05, float(STAND["root"][1] + 0.02), float(STAND["root"][2] - 0.14)],
                   R=[-0.05, float(STAND["root"][1] + 0.02), float(STAND["root"][2] - 0.14)], pole_L=(0.8, -0.6, -0.4), pole_R=(-0.8, -0.6, -0.4))
motion("cooldown-stretch", [K(0, "stand"), K(1.5, quad_stretch()), K(4.5, quad_stretch()), K(6, "stand"),
                            K(7.5, chest_open), K(10.5, chest_open), K(12, "stand")], muscles=("quads", "chest"), yaw=60)

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
motion("chair-shrugs", [K(0, "chairSit"), K(1.2, P("chairSit", clavicle=[0, 0, 22])), K(3.2, P("chairSit", clavicle=[0, 0, 22])),
                        K(3.6, "chairSit", "out"), K(5, "chairSit")], muscles=("upperBack", "neck"), yaw=30, props=(CHAIR,))

def neck_tilt(base):
    tilt = lambda a: P(base, neck01=[0, 0, a * 0.35], neck02=[0, 0, a * 0.25], neck03=[0, 0, a * 0.2], head=[0, 0, a * 0.2])
    return [K(0, base), K(1.5, tilt(32)), K(3, tilt(32)), K(4.5, base), K(6, tilt(-32)), K(7.5, tilt(-32)), K(9, base)]
motion("neck-tilt", neck_tilt("stand"), muscles=("neck",), yaw=10)
motion("chin-tucks", [K(0, "stand"), K(1, P("stand", neck01=[-10, 0, 0], neck03=[-4, 0, 0], head=[14, 0, 0])),
                      K(3, P("stand", neck01=[-10, 0, 0], neck03=[-4, 0, 0], head=[14, 0, 0])), K(4, "stand")], muscles=("neck",), yaw=75)
_trap = P("stand", neck01=[0, 0, 12], neck02=[0, 0, 9], neck03=[0, 0, 7], head=[0, 0, 7], clavicle_L=[0, 0, -6], **open_hand(0.9, "R"))
_tr, _tp = ik.fk(_trap)
_hr = _tr["head"]
# Main droite posée sur le haut du crâne, doigts vers l'oreille gauche.
trap = hands(_trap, R=_tp["head"] + _hr @ [0.0, 0.185, 0.0], fingers_R=_hr @ [1, -0.55, 0], palm_R=_hr @ [0.3, -1, 0], pole_R=(-1, 0.3, 0.2))
motion("trap-stretch", [K(0, "stand"), K(2, trap), K(6, trap), K(8, "stand")], muscles=("neck", "upperBack"), yaw=15)

# Ouverture de poitrine dans l'encadrement d'une porte : avant-bras sur les montants, le buste avance.
def doorway(lean):
    p = P("stand", root={"offset": [0, 0, lean]}, spine01=[-3 - lean * 30, 0, 0], head=[-3, 0, 0], **open_hand(0.9))
    p = legs(p, L=ankle("L"), R=ankle("R"))
    sh = joints(P("stand"))
    for side, sg in (("L", 1), ("R", -1)):
        p = hands(p, **{side: [sg * float(SH[0] + 0.21), float(SH[1] + 0.24), sh[f"upperarm01.{side}"][2] + 0.02]},
                  **{f"fingers_{side}": [0, 1, 0], f"palm_{side}": [-sg, 0, 0.25], f"pole_{side}": (sg, -0.6, 0)})
    return p
motion("doorway-stretch", [K(0, doorway(0.0)), K(2, doorway(0.13 * S_LEG)), K(5, doorway(0.13 * S_LEG)), K(7, doorway(0.0))],
       muscles=("chest", "shoulders"), yaw=62, props=(prop("door", "root", 0, (0, 0, 0.1), floor=True),))

squeeze = P("stand", clavicle=[0, 20, -2], upperarm01=[14, 14, 6], lowerarm01=[-20, 0, 0], spine01=[-5, 0, 0])
motion("scapular-squeeze", [K(0, "stand"), K(1, squeeze), K(5, squeeze), K(6, "stand")], muscles=("upperBack",), yaw=155)

# Cercles de hanches : le bassin dessine un cercle, les pieds restent posés, le buste reste au-dessus.
def hip_circle(theta):
    r = 0.08 * S_LEG
    ox, oz = r * np.cos(theta), r * np.sin(theta)
    tilt_z, tilt_x = 8 * np.cos(theta), -7 * np.sin(theta)
    p = P("handsHips", root={"rot": [["z", -tilt_z], ["x", tilt_x]], "offset": [ox, -0.025, oz]},
          spine05=[-tilt_x * 0.6, 0, tilt_z * 0.6], spine03=[-tilt_x * 0.7, 0, tilt_z * 0.7], spine01=[-tilt_x * 0.4, 0, tilt_z * 0.4])
    return legs(p, L=ankle("L"), R=ankle("R"))
motion("hip-circles", circle_keys(12, 4.8, hip_circle), muscles=("lowerBack", "abs", "glutes"), yaw=35)

# Cercles de cheville : main gauche à plat contre le mur, genou droit levé, la cheville dessine des cercles.
_ank_base = hands(P("stand", **open_hand(1.0, "L")), L=[float(SH[0] + 0.415), float(SH[1] - 0.02), -0.02], fingers_L=[0, 1, 0.1], palm_L=[1, 0, 0], pole_L=(0.2, -1, -0.4))
def ankle_circle(theta):
    return P(_ank_base, upperleg01_R=[-38, 0, 3], lowerleg01_R=[52, 0, 0],
             foot_R=sided("R", [22 * np.cos(theta), 14 * np.sin(theta), -16 * np.sin(theta)]))
motion("ankle-circles", circle_keys(10, 3.4, ankle_circle), muscles=("calves", "shins"), yaw=25,
       props=(prop("wall", "wrist.L", 0, (0.035, 0, -0.02), floor=True),))

side_bend = lambda a: P("stand", upperarm01=[0, 0, 168], lowerarm01=[-6, 0, 0], clavicle=[0, 0, 8], spine03=[0, 0, a * 0.4], spine02=[0, 0, a * 0.35],
                        spine01=[0, 0, a * 0.25], **open_hand(0.9))
motion("overhead-stretch", [K(0, "stand"), K(2, side_bend(0)), K(4, side_bend(22)), K(6, side_bend(0)), K(8, side_bend(-22)), K(10, side_bend(0)), K(12, "stand")],
       muscles=("upperBack", "abs", "shoulders"), yaw=10)
motion("back-extension", [K(0, "handsHips"), K(2, P("handsHips", spine04=[-5, 0, 0], spine03=[-5, 0, 0], spine02=[-4, 0, 0], neck01=[-8, 0, 0], head=[-8, 0, 0])),
                          K(4, "handsHips"), K(6, P("handsHips", spine04=[8, 0, 0], spine03=[8, 0, 0], spine02=[8, 0, 0], neck01=[14, 0, 0], head=[10, 0, 0])),
                          K(8, "handsHips")], muscles=("lowerBack", "abs"), yaw=70)

# ─── Yoga (sur un tapis) ───
# Montagne : debout, grandi, paumes légèrement tournées vers l'avant.
mountain = P("stand", upperarm01=[0, 16, 5], lowerarm01=[-6, 0, 0], **open_hand(0.7))
motion("mountain", breathe(mountain, cycle=6), yaw=15, props=(MAT,))

# Salutation des bras : les bras montent devant soi jusqu'au-dessus de la tête, paumes jointes, puis redescendent.
arms_front_up = P(mountain, upperarm01=[-90, 0, 5], lowerarm01=[-4, 0, 0])
_up = P(mountain, clavicle=[0, 0, 10], spine01=[-4, 0, 0], neck01=[-6, 0, 0], head=[-8, 0, 0])
salute = hands(_up, L=[PALM, OVERHEAD[0], OVERHEAD[1]], R=[-PALM, OVERHEAD[0], OVERHEAD[1]], fingers_L=[0, 1, 0], palm_L=[-1, 0, 0],
               fingers_R=[0, 1, 0], palm_R=[1, 0, 0], pole_L=(1, 0, -0.3), pole_R=(-1, 0, -0.3))
motion("arm-raise", [K(0, mountain), K(2.4, arms_front_up), K(4.2, salute), K(5.6, salute), K(7.4, arms_front_up), K(9.4, mountain), K(10.4, mountain)],
       muscles=("shoulders",), yaw=40, props=(MAT,))

fold = P("stand", root={"rot": [["x", 62]]}, upperleg01=[-64, 0, 4], lowerleg01=[18, 0, 0], foot=[-16, 0, 5], spine04=[8, 0, 0], spine03=[8, 0, 0],
         spine02=[8, 0, 0], spine01=[6, 0, 0], neck01=[14, 0, 0], head=[10, 0, 0], upperarm01=[-92, 0, 4], lowerarm01=[-12, 0, 0], **open_hand(0.5))
half_up = P("stand", root={"rot": [["x", 30]]}, upperleg01=[-34, 0, 4], lowerleg01=[10, 0, 0], foot=[-8, 0, 5], spine04=[10, 0, 0], spine03=[10, 0, 0],
            spine02=[10, 0, 0], spine01=[8, 0, 0], neck01=[16, 0, 0], head=[10, 0, 0], upperarm01=[-45, 0, 4], lowerarm01=[-8, 0, 0], **open_hand(0.5))
motion("forward-fold", [K(0, mountain), K(3, fold), K(6, fold), K(7.6, half_up), K(9.4, mountain), K(10, mountain)],
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
CHEST_IN = dict(spine01=[-3, 0, 0], spine02=[-2, 0, 0])      # inspiration sans bouger le regard
motion("warrior-two", [K(0, w0), K(1.6, wt), K(3.2, wl), K(5.2, P(wl, **CHEST_IN)), K(7.2, wl), K(8.6, wt), K(10.0, w0),
                       K(11.6, wrt), K(13.2, wr), K(15.2, P(wr, **CHEST_IN)), K(17.2, wr), K(18.6, wrt), K(20.0, w0r)],
       muscles=("quads", "glutes", "shoulders"), yaw=6, props=(MAT,))

# Arbre : en équilibre sur la jambe gauche, plante du pied droit contre l'intérieur du mollet puis de la cuisse,
# mains jointes devant la poitrine, puis bras au-dessus de la tête.
def tree(stage, arms):
    """stage : 0 debout, 1 pied contre le mollet, 2 pied contre la cuisse ; arms : « down », « prayer », « up »."""
    shift = [0.0, 0.07 * S_HIP, 0.085 * S_HIP][stage]
    p = P(mountain, root={"offset": [shift, -0.01, 0]}, upperleg01_R=[0, 0, 5], foot_R=[0, 0, -5])
    p = legs(p, L=ankle("L"))
    if stage:
        J = joints(p)
        hipL, kneeL = J["upperleg01.L"], J["lowerleg01.L"]
        if stage == 1:
            target = kneeL + (ANK["L"] - kneeL) * 0.45 + [-0.085, 0, 0.0]
            p = legs(p, R=target, pole_R=(-1, -0.2, 0.45), foot_yaw_R=-90, foot_pitch_R=55)
        else:
            target = kneeL + (hipL - kneeL) * 0.42 + [-0.095, 0, 0.01]
            p = legs(p, R=target, pole_R=(-1, -0.1, 0.35), foot_yaw_R=-90, foot_pitch_R=75)
    if arms == "prayer":
        p = P(p, **open_hand(1.0))
        p = hands(p, L=[PALM, CHEST[0], CHEST[1]], R=[-PALM, CHEST[0], CHEST[1]], fingers_L=[0, 1, 0.25], palm_L=[-1, 0, 0],
                  fingers_R=[0, 1, 0.25], palm_R=[1, 0, 0], pole_L=(1, -0.5, -0.3), pole_R=(-1, -0.5, -0.3))
    elif arms == "up":
        p = P(p, clavicle=[0, 0, 10], **open_hand(1.0))
        p = hands(p, L=[PALM, OVERHEAD[0], OVERHEAD[1]], R=[-PALM, OVERHEAD[0], OVERHEAD[1]], fingers_L=[0, 1, 0], palm_L=[-1, 0, 0],
                  fingers_R=[0, 1, 0], palm_R=[1, 0, 0], pole_L=(1, 0, -0.3), pole_R=(-1, 0, -0.3))
    return p
_tree = [tree(0, "down"), tree(1, "prayer"), tree(2, "prayer"), tree(2, "up")]
_treeR = [mirror_pose(x) for x in _tree]
def tree_keys(seq, t0):
    s0, s1, s2, s3 = seq
    return [K(t0, s0), K(t0 + 1.4, s1), K(t0 + 2.6, s2), K(t0 + 4.2, s3), K(t0 + 6.0, P(s3, **BREATH_IN)), K(t0 + 7.8, s3),
            K(t0 + 9.2, s2), K(t0 + 10.4, s1), K(t0 + 11.6, s0)]
motion("tree-pose", tree_keys(_tree, 0) + tree_keys(_treeR, 11.6)[1:], muscles=("calves", "glutes", "abs"), yaw=12, props=(MAT,))

# ─── Au sol ───
# Chat-vache : mains et genoux restent posés ; le bassin bascule et la colonne s'arrondit puis se creuse.
_q = joints("quadruped")
QW = {s: _q[f"wrist.{s}"].copy() for s in "LR"}
QA = {s: _q[f"foot.{s}"].copy() for s in "LR"}
_qr = ik.fk("quadruped")[0]
def quad(pelvis, spine, neck, head):
    p = P("quadruped", root={"rot": [["x", 78 + pelvis], ["y", 90]]},
          spine05=[spine, 0, 0], spine04=[spine, 0, 0], spine03=[spine * 0.85, 0, 0], spine02=[spine * 0.6, 0, 0], spine01=[spine * 0.2, 0, 0],
          neck01=[-6 + neck, 0, 0], head=[head, 0, 0])
    p = legs(p, L=QA["L"], R=QA["R"], pole_L=(1, -1, 0), pole_R=(1, -1, 0), foot_rot_L=_qr["foot.L"], foot_rot_R=_qr["foot.R"])
    for s in "LR":
        p = with_bones(p, ik.arm(p, s, QW[s], pole=(-1, 0, 0)))
    return p
cat = quad(-13, 10, 14, 16)
cow = quad(9, -8, -20, -12)
neutral = quad(0, 0, 0, 0)
motion("cat-cow", [K(0, neutral), K(2.5, cat), K(5, neutral), K(7.5, cow), K(10, neutral)], muscles=("lowerBack", "abs"), yaw=0, props=(MAT,))

child = P("stand", root={"rot": [["x", 94.5], ["y", 90]]}, upperleg01=[-154.5, 0, 10], lowerleg01=[145, 0, 0], foot=[78, 0, 0],
          upperarm01=[-166, 0, 6], lowerarm01=[-4, 0, 0], neck01=[-5, 0, 0], **open_hand(0.8))
motion("child-pose", [K(0, child), K(3, P(child, **BREATH_IN)), K(6, child)], muscles=("lowerBack",), yaw=0, props=(MAT,))

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
def hamstring(side, hinge):
    o = other(side)
    p = P("chairSit", root={"rot": [["x", hinge]]}, spine04=[-hinge * 0.15, 0, 0], neck01=[-hinge * 0.4, 0, 0], **open_hand(0.6))
    hip = joints(p)[f"upperleg01.{side}"]
    floor_ankle = float(_seat[f"foot.{o}"][1])          # niveau du sol dans cette pose (avant mise au sol)
    drop = hip[1] - (floor_ankle + 0.02)
    reach = float(np.sqrt(max(LEG ** 2 - drop ** 2, 0.0))) * 0.985
    p = legs(p, **{side: [float(hip[0]), floor_ankle + 0.02, float(hip[2] + reach)]}, **{f"foot_pitch_{side}": -28})
    p = legs(p, **{o: _seat[f"foot.{o}"]})
    J = joints(p)
    knee = J[f"lowerleg01.{side}"]; thigh = (J[f"upperleg01.{side}"] + knee) / 2
    hand_on = knee * 0.7 + thigh * 0.3 + [0, 0.075, 0]
    return hands(p, L=hand_on + [0.03, 0, 0], R=hand_on + [-0.03, 0, 0],
                 fingers_L=[0, -0.3, 1], palm_L=[0, -1, 0], fingers_R=[0, -0.3, 1], palm_R=[0, -1, 0],
                 pole_L=(1, -0.6, -0.3), pole_R=(-1, -0.6, -0.3))
hL0, hL1 = hamstring("L", 0), hamstring("L", 24)
hR0, hR1 = mirror_pose(hL0), mirror_pose(hL1)
motion("bed-hamstring", [K(0, "chairSit"), K(1.6, hL0), K(3.4, hL1), K(7.4, hL1), K(9.0, hL0), K(10.4, "chairSit"),
                         K(12.0, hR0), K(13.8, hR1), K(17.8, hR1), K(19.4, hR0), K(20.8, "chairSit")],
       muscles=("hamstrings", "calves"), yaw=62, pitch=8, props=(BED_SIT,))

# Hanches (« 4 ») : cheville droite posée sur le genou gauche, genou droit ouvert, léger penché en avant.
def figure4(lean):
    p = P("chairSit", spine04=[lean * 0.4, 0, 0], spine03=[lean * 0.3, 0, 0], spine02=[lean * 0.2, 0, 0], neck01=[-lean * 0.3, 0, 0],
          **open_hand(0.6))
    knee_L = joints(p)["lowerleg01.L"]
    p = legs(p, R=knee_L + [0.0, 0.1, -0.06], pole_R=(-1, 0.25, 0.35), foot_yaw_R=70, foot_pitch_R=15)
    J = joints(p)
    return hands(p, L=J["foot.R"] + [0.0, 0.06, 0.02], R=J["lowerleg01.R"] + [0.03, 0.07, -0.02],
                 fingers_L=[-0.4, -0.3, 1], palm_L=[0, -1, 0], fingers_R=[0.2, -0.3, 1], palm_R=[0, -1, 0],
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
motion("abs-contract", [K(0, "chairSit"), K(1.5, P("chairSit", spine04=[8, 0, 0], spine03=[8, 0, 0], spine02=[4, 0, 0])),
                        K(3, P("chairSit", spine04=[8, 0, 0], spine03=[8, 0, 0], spine02=[4, 0, 0])), K(4.5, "chairSit")],
       muscles=("abs",), yaw=60, props=(CHAIR,))
legs_out = P("chairSit", ground=False, lowerleg01=[12, 0, 0], foot=[-22, 0, 0])
motion("legs-tense", [K(0, "chairSit"), K(1.5, legs_out), K(3, legs_out), K(4.5, "chairSit")], muscles=("quads", "shins", "calves"),
       yaw=60, props=(CHAIR,))

# ─── Mouvements issus de captures réelles (CMU Graphics Lab, http://mocap.cs.cmu.edu) ───
# (identifiant, fichier BVH, fenêtre en secondes, durée de boucle min/max, vitesse, angle de vue, muscles)
MOCAP = [
    ("walk", "007/07_01.bvh", (0.2, 2.6), (0.9, 1.4), 1.0, 70, ("quads", "calves", "glutes")),
    ("walk-fast", "008/08_01.bvh", (0.2, 2.3), (0.8, 1.3), 1.0, 70, ("quads", "calves", "glutes", "hamstrings")),
    ("shadow-boxing", "013/13_17.bvh", (6.2, 9.8), (2.4, 3.4), 1.0, 40, ("shoulders", "triceps", "abs")),
]
KEY_BONES = ["root", "spine03", "spine01", "neck01", "upperarm01.L", "upperarm01.R", "lowerarm01.L", "lowerarm01.R",
             "upperleg01.L", "upperleg01.R", "lowerleg01.L", "lowerleg01.R"]

def build_mocap(bvh_root, joints_):
    from mocap import retarget, mapping, slerp
    names = [j["name"] for j in joints_]; parents = [j["parent"] for j in joints_]
    heads = {j["name"]: np.array(j["head"]) for j in joints_}
    mapped = sorted(set(mapping()), key=names.index)
    out = {}
    for mid, path, (t0, t1), (lmin, lmax), speed, yaw, muscles in MOCAP:
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
        idx = [names.index(b) for b in mapped]
        frames = [[round(float(x), 4) for b in idx for x in C[f, b]] for f in range(len(C))]
        out[mid] = {"clip": {"fps": 30 * speed, "bones": mapped, "frames": frames,
                             "source": f"CMU {os.path.basename(path)} {i / 30 + t0:.2f}–{j / 30 + t0:.2f} s"},
                    "muscles": list(muscles), "camera": {"yaw": yaw, "pitch": 8}, "props": []}
        print(f"  {mid}: {len(C)} images, boucle {i / 30 + t0:.2f}–{j / 30 + t0:.2f} s, écart {best[0]:.3f}")
    return out

def rounded(x):
    """Arrondit les angles au dixième de degré (fichier plus léger)."""
    if isinstance(x, dict): return {k: rounded(v) for k, v in x.items()}
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
    bones = [j["name"] for j in META["bodies"]["male"]["joints"]]
    bvh_root = os.environ.get("CMU_BVH", "/home/user/una-dinosauria/cmu-mocap/data")
    previous = json.load(open(OUT)) if os.path.exists(OUT) else {}
    bodies = {}
    for body in ("male", "female"):
        # Le script est rejoué pour chaque corps : objectifs et cinématique inverse sur son propre squelette.
        ns = runpy.run_path(os.path.abspath(__file__), init_globals={"BODY": body}, run_name=f"motions_{body}")
        poses, motions = ns["POSES"], ns["MOTIONS"]
        check(poses, motions, bones, body)
        if os.path.isdir(bvh_root):
            motions.update(ns["build_mocap"](bvh_root, META["bodies"][body]["joints"]))
        else:
            print("Captures CMU introuvables : les mouvements captés du fichier précédent sont conservés.")
            old = previous.get("bodies", {}).get(body, {}).get("motions", previous.get("motions", {}))
            motions.update({k: v for k, v in old.items() if "clip" in v and k in {m[0] for m in MOCAP}})
        bodies[body] = {"poses": rounded(strip_private(poses)), "motions": rounded(strip_private(motions))}
        print(f"{body} : {len(motions)} mouvements")
    json.dump({"version": 3, "bones": bones, "regions": REGIONS, "bodies": bodies},
              open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    print("→", OUT, os.path.getsize(OUT) // 1024, "Ko")
