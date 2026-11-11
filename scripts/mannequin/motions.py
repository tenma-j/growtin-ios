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
Usage : python3 scripts/mannequin/motions.py
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
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
    return {"t": t, "pose": pose, "ease": ease}

def S(name, side):
    return f"{name}_{side}"

def other(side):
    return "R" if side == "L" else "L"

FINGERS = [f"finger{f}-{p}" for f in range(2, 6) for p in (1, 2, 3)]
def fist(amount=1.0):
    d = {f: [0, 0, -70 * amount] for f in FINGERS}
    d["finger1-2"] = [0, 0, -30 * amount]; d["finger1-3"] = [0, 0, -40 * amount]
    return d

BREATH_IN = dict(spine01=[-3, 0, 0], spine02=[-2, 0, 0], clavicle=[0, 0, 4])

POSES = {
    "stand": P(),
    "handsHips": P(upperarm01=[0, -90, 45], lowerarm01=[-90, 0, 0], wrist=[0, 0, 10]),
    "supine": P(root={"rot": [["x", -90], ["y", 90]]}, upperarm01=[0, 0, 10]),
    # Angles obtenus avec scripts/mannequin/solve_poses.py (mains sous les épaules, genoux sous les hanches).
    "quadruped": P(root={"rot": [["x", 78], ["y", 90]]}, upperleg01=[-73, 0, 2], lowerleg01=[83, 0, 0], foot=[65, 0, 0],
                   upperarm01=[-74, 0, 3], lowerarm01=[-4, 0, 0], lowerarm02=[0, -95, 0], wrist=[-28, 0, 74], neck01=[-6, 0, 0]),
    "crossLegged": P(upperleg01=[-127, 9, -85], lowerleg01=[121, 0, 0], foot=[0, 0, 0],
                     upperarm01=[-30, 0, 14], lowerarm01=[-40, 0, 0]),
    "chairSit": P(upperleg01=[-88, 0, 4], lowerleg01=[88, 0, 0], upperarm01=[-22, 0, 4], lowerarm01=[-48, 0, 0]),
    "sitFloor": P(root={"rot": [["y", 90]]}, upperleg01=[-90, 0, 2], upperarm01=[-8, 0, 14], lowerarm01=[-10, 0, 0]),
}

MOTIONS = {}
def motion(mid, keys, muscles=(), yaw=30, props=(), pitch=8):
    MOTIONS[mid] = {"keys": keys, "muscles": list(muscles), "camera": {"yaw": yaw, "pitch": pitch}, "props": list(props)}

def prop(kind, anchor=None, key=0, offset=(0, 0, 0), yaw=0, floor=False):
    return {"kind": kind, "anchor": anchor, "key": key, "offset": [float(x) for x in offset], "yaw": float(yaw), "floor": floor}

CHAIR = prop("chair", "root", 0, (0, -0.105, -0.06))
MAT = prop("mat", "root", 0, (0, 0, 0), floor=True)

def breathe(base, cycle=5.0, extra=None):
    inhale = dict(BREATH_IN); inhale.update(extra or {})
    return [K(0, base), K(cycle / 2, P(base, **inhale)), K(cycle, base)]

# ─── Respiration ───
motion("breathe-stand", breathe("stand"), yaw=20)
motion("rib-breathing", breathe(P("stand", upperarm01=[0, -90, 26], lowerarm01=[-108, 0, 0], wrist=[0, 0, 15]),
                                extra=dict(upperarm01=[0, -90, 30])), muscles=("chest", "abs"), yaw=20)
motion("look-far", [K(0, P("stand", head=[-5, 0, 0])), K(3, P("stand", head=[-6, 12, 0], **BREATH_IN)),
                    K(6, P("stand", head=[-5, 0, 0])), K(9, P("stand", head=[-6, -12, 0], **BREATH_IN)), K(12, P("stand", head=[-5, 0, 0]))], yaw=25)
motion("lying-breathe", breathe(P("supine", upperarm01=[0, 60, 18]), cycle=6), yaw=0, pitch=25, props=(MAT,))
motion("chair-breathe", breathe(P("chairSit")), yaw=30, props=(CHAIR,))
motion("seated-breathe", breathe(P("crossLegged"), cycle=6), yaw=20, props=(MAT,))

# ─── Marche et cardio ───
def gait(s, hip, knee, arm, elbow, twist=4, rear=6):
    o = other(s)
    return P("stand", **{S("upperleg01", s): [-hip, 0, 0], S("lowerleg01", s): [knee, 0, 0], S("foot", s): [hip * 0.25, 0, 0],
                         S("upperleg01", o): [rear, 0, 0], S("lowerleg01", o): [8, 0, 0],
                         S("upperarm01", o): [-arm, 0, 5], S("lowerarm01", o): [-elbow, 0, 0],
                         S("upperarm01", s): [arm * 0.6, 0, 5], S("lowerarm01", s): [-elbow * 0.6, 0, 0]},
             spine03=[0, twist if s == "L" else -twist, 0])
def cycle(mid, hip, knee, arm, elbow, period, muscles, mid_elbow=None, yaw=35):
    mid_pose = P("stand", lowerleg01=[8, 0, 0], lowerarm01=[-(mid_elbow if mid_elbow is not None else elbow * 0.5), 0, 0])
    h = period / 4
    motion(mid, [K(0, gait("L", hip, knee, arm, elbow)), K(h, mid_pose), K(2 * h, gait("R", hip, knee, arm, elbow)),
                 K(3 * h, mid_pose), K(4 * h, gait("L", hip, knee, arm, elbow))], muscles=muscles, yaw=yaw)
cycle("walk", 28, 42, 20, 18, 2.2, ("quads", "calves", "glutes"))
cycle("walk-fast", 40, 62, 38, 85, 1.7, ("quads", "calves", "glutes", "hamstrings"), mid_elbow=85)
cycle("march", 55, 75, 32, 70, 1.8, ("quads", "calves", "abs"), mid_elbow=70, yaw=30)

def high_knee(s):
    o = other(s)
    return P("stand", **{S("upperleg01", s): [-82, 0, 0], S("lowerleg01", s): [92, 0, 0], S("foot", s): [20, 0, 0],
                         S("upperarm01", o): [-42, 0, -18], S("lowerarm01", o): [-70, 0, 0],
                         S("upperarm01", s): [18, 0, 6], S("lowerarm01", s): [-40, 0, 0]}, spine03=[4, 0, 0])
motion("high-knees", [K(0, high_knee("L")), K(0.5, P("stand", lowerleg01=[6, 0, 0])), K(1.0, high_knee("R")),
                      K(1.5, P("stand", lowerleg01=[6, 0, 0])), K(2.0, high_knee("L"))], muscles=("quads", "abs"), yaw=40)

def side_step(s):
    return P("stand", **{S("upperleg01", s): [-4, 0, 20], S("lowerleg01", s): [14, 0, 0], S("foot", s): [0, 0, -14]},
             upperarm01=[0, 0, 60], lowerleg01=[10, 0, 0])
motion("side-steps", [K(0, side_step("L")), K(0.6, P("stand", lowerleg01=[16, 0, 0], upperleg01=[-8, 0, 0])), K(1.2, side_step("R")),
                      K(1.8, P("stand", lowerleg01=[16, 0, 0], upperleg01=[-8, 0, 0])), K(2.4, side_step("L"))],
       muscles=("quads", "glutes", "calves"), yaw=10)

half_squat = P("stand", root={"rot": [["x", 16]]}, upperleg01=[-62, 0, 5], lowerleg01=[64, 0, 0], foot=[-8, 0, 0],
               upperarm01=[-95, 0, 6], neck01=[-8, 0, 0])
motion("half-squat-arms", [K(0, "stand"), K(2, half_squat), K(4, "stand")], muscles=("quads", "glutes", "shoulders"), yaw=60)

guard = P("stand", upperleg01=[-12, 0, 4], lowerleg01=[16, 0, 0], foot=[-4, 0, 0],
          upperarm01=[-38, -30, 18], lowerarm01=[-125, 0, 0], **fist(0.9))
def punch(s):
    o = other(s)
    return P(guard, **{S("upperarm01", s): [-86, -20, 4], S("lowerarm01", s): [-10, 0, 0]},
             spine03=[0, -16 if s == "L" else 16, 0], spine02=[0, -6 if s == "L" else 6, 0])
motion("shadow-boxing", [K(0, guard), K(0.45, punch("L")), K(0.9, guard), K(1.35, punch("R")), K(1.8, guard)],
       muscles=("shoulders", "triceps", "abs"), yaw=45)

def arm_circle_keys(leg_side):
    return P("stand", **{S("upperleg01", leg_side): [-30, 0, 0], S("lowerleg01", leg_side): [45, 0, 0]})
motion("warmup-march", [
    K(0, P(arm_circle_keys("L"))), K(0.9, P(arm_circle_keys("R"), upperarm01=[-90, 0, 4])),
    K(1.8, P(arm_circle_keys("L"), upperarm01=[-175, 0, 4])), K(2.7, P(arm_circle_keys("R"), upperarm01=[0, 0, 95])),
    K(3.6, P(arm_circle_keys("L")))], muscles=("shoulders", "quads"), yaw=30)

# ─── Renforcement ───
squat_low = P("stand", root={"rot": [["x", 32]]}, upperleg01=[-110, 0, 6], lowerleg01=[96, 0, 0], foot=[-12, 0, 0],
              spine04=[4, 0, 0], spine02=[4, 0, 0], neck01=[-12, 0, 0], upperarm01=[-70, 0, 6], lowerarm01=[-6, 0, 0])
motion("chair-squat", [K(0, "stand"), K(3, squat_low, "inOut"), K(4, "stand", "out"), K(4.8, "stand")],
       muscles=("quads", "glutes"), yaw=70, props=(prop("chair", "root", 1, (0, -0.13, -0.16)),))

push_top = P("stand", root={"rot": [["x", 42]]}, foot=[-42, 0, 0], upperarm01=[-80, 0, 10], lowerarm01=[-4, 0, 0], wrist=[0, 0, 0],
             neck01=[-14, 0, 0], head=[-6, 0, 0])
push_low = P("stand", root={"rot": [["x", 55]]}, foot=[-55, 0, 0], upperarm01=[-38, 0, 30], lowerarm01=[-92, 0, 0],
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

motion("calf-raises", [K(0, "stand"), K(1, P("stand", foot=[28, 0, 0], toes=[-34, 0, 0]), "out"),
                       K(1.4, P("stand", foot=[28, 0, 0], toes=[-34, 0, 0])), K(4, "stand", "inOut")], muscles=("calves",), yaw=70)

lunge = lambda s: P("stand", **{S("upperleg01", s): [-48, 0, 2], S("lowerleg01", s): [56, 0, 0], S("foot", s): [-6, 0, 0],
                                S("upperleg01", other(s)): [16, 0, 0], S("lowerleg01", other(s)): [48, 0, 0], S("foot", other(s)): [24, 0, 0],
                                S("toes", other(s)): [-30, 0, 0]}, upperarm01=[0, -90, 45], lowerarm01=[-90, 0, 0])
motion("gentle-lunge", [K(0, "handsHips"), K(1.5, lunge("L")), K(3, "handsHips"), K(4.5, lunge("R")), K(6, "handsHips")],
       muscles=("quads", "glutes"), yaw=70)

def quad_stretch():
    return P("stand", upperleg01_L=[10, 0, 0], lowerleg01_L=[145, 0, 0], foot_L=[30, 0, 0],
             upperarm01_L=[38, 0, 6], lowerarm01_L=[-22, 0, 0], upperarm01_R=[0, 0, 40])
chest_open = P("stand", upperarm01=[34, 30, -6], lowerarm01=[-8, 0, 0], clavicle=[0, 14, 0], spine01=[-6, 0, 0], head=[-6, 0, 0])
motion("cooldown-stretch", [K(0, "stand"), K(1.5, quad_stretch()), K(4.5, quad_stretch()), K(6, "stand"),
                            K(7.5, chest_open), K(10.5, chest_open), K(12, "stand")], muscles=("quads", "chest"), yaw=60)

# ─── Mobilité, épaules, nuque ───
motion("shoulder-rolls", [K(0, "stand"), K(0.8, P("stand", clavicle=[0, 0, 14])), K(1.6, P("stand", clavicle=[0, 14, 8])),
                          K(2.4, P("stand", clavicle=[0, 10, -4])), K(3.2, "stand")], muscles=("shoulders", "upperBack"), yaw=40)
motion("shrugs", [K(0, "stand"), K(1.2, P("stand", clavicle=[0, 0, 18], neck01=[-2, 0, 0])), K(3.2, P("stand", clavicle=[0, 0, 18])),
                  K(3.7, "stand", "out"), K(5, "stand")], muscles=("upperBack", "neck"), yaw=25)
motion("chair-shrugs", [K(0, "chairSit"), K(1.2, P("chairSit", clavicle=[0, 0, 18])), K(3.2, P("chairSit", clavicle=[0, 0, 18])),
                        K(3.7, "chairSit", "out"), K(5, "chairSit")], muscles=("upperBack", "neck"), yaw=30, props=(CHAIR,))

def neck_tilt(base):
    tilt = lambda a: P(base, neck01=[0, 0, a * 0.35], neck02=[0, 0, a * 0.25], neck03=[0, 0, a * 0.2], head=[0, 0, a * 0.2])
    return [K(0, base), K(1.5, tilt(32)), K(3, tilt(32)), K(4.5, base), K(6, tilt(-32)), K(7.5, tilt(-32)), K(9, base)]
motion("neck-tilt", neck_tilt("stand"), muscles=("neck",), yaw=10)
motion("seated-neck", neck_tilt("crossLegged"), muscles=("neck", "upperBack"), yaw=10, props=(MAT,))
motion("chin-tucks", [K(0, "stand"), K(1, P("stand", neck01=[-10, 0, 0], neck03=[-4, 0, 0], head=[14, 0, 0])),
                      K(3, P("stand", neck01=[-10, 0, 0], neck03=[-4, 0, 0], head=[14, 0, 0])), K(4, "stand")], muscles=("neck",), yaw=75)
trap = P("stand", neck01=[0, 0, 12], neck02=[0, 0, 9], neck03=[0, 0, 7], head=[0, 0, 7],
         upperarm01_R=[-20, 0, -150], lowerarm01_R=[-100, 0, 0], wrist_R=[0, 0, -20], clavicle_L=[0, 0, -6])
motion("trap-stretch", [K(0, "stand"), K(2, trap), K(6, trap), K(8, "stand")], muscles=("neck", "upperBack"), yaw=15)
goal = P("stand", upperarm01=[0, 90, 88], lowerarm01=[-92, 0, 0], clavicle=[0, 10, 0], spine01=[-5, 0, 0], head=[-4, 0, 0])
motion("doorway-stretch", [K(0, P("stand", upperarm01=[0, 90, 88], lowerarm01=[-92, 0, 0])), K(2, goal), K(5, goal),
                           K(7, P("stand", upperarm01=[0, 90, 88], lowerarm01=[-92, 0, 0]))], muscles=("chest", "shoulders"), yaw=50)
squeeze = P("stand", clavicle=[0, 14, 0], upperarm01=[16, 10, 6], lowerarm01=[-24, 0, 0], spine01=[-4, 0, 0])
motion("scapular-squeeze", [K(0, "stand"), K(1, squeeze), K(5, squeeze), K(6, "stand")], muscles=("upperBack",), yaw=150)

def hip_circle(a, b):
    return P("handsHips", root={"rot": [["z", a], ["x", b]]},
             upperleg01_L=[-b, 0, -a], upperleg01_R=[-b, 0, -a], spine05=[-b * 0.8, 0, -a * 0.8], spine04=[-b * 0.4, 0, -a * 0.4])
motion("hip-circles", [K(0, hip_circle(8, 0)), K(1, hip_circle(0, 8)), K(2, hip_circle(-8, 0)), K(3, hip_circle(0, -8)), K(4, hip_circle(8, 0))],
       muscles=("lowerBack", "abs", "glutes"), yaw=30)
motion("ankle-circles", [K(0, P("stand", upperleg01_R=[-28, 0, 0], lowerleg01_R=[40, 0, 0], upperarm01_L=[0, 0, 62], lowerarm01_L=[-12, 0, 0], foot_R=[22, 0, 0])),
                         K(1, P("stand", upperleg01_R=[-28, 0, 0], lowerleg01_R=[40, 0, 0], upperarm01_L=[0, 0, 62], lowerarm01_L=[-12, 0, 0], foot_R=[0, -18, -12])),
                         K(2, P("stand", upperleg01_R=[-28, 0, 0], lowerleg01_R=[40, 0, 0], upperarm01_L=[0, 0, 62], lowerarm01_L=[-12, 0, 0], foot_R=[-22, 0, 0])),
                         K(3, P("stand", upperleg01_R=[-28, 0, 0], lowerleg01_R=[40, 0, 0], upperarm01_L=[0, 0, 62], lowerarm01_L=[-12, 0, 0], foot_R=[0, 18, 12])),
                         K(4, P("stand", upperleg01_R=[-28, 0, 0], lowerleg01_R=[40, 0, 0], upperarm01_L=[0, 0, 62], lowerarm01_L=[-12, 0, 0], foot_R=[22, 0, 0]))],
       muscles=("calves", "shins"), yaw=35, props=(prop("wall", "wrist.L", 0, (0.06, 0, 0), floor=True),))
side_bend = lambda a: P("stand", upperarm01=[0, 0, 168], lowerarm01=[-6, 0, 0], spine03=[0, 0, a * 0.4], spine02=[0, 0, a * 0.35], spine01=[0, 0, a * 0.25])
motion("overhead-stretch", [K(0, "stand"), K(2, side_bend(0)), K(4, side_bend(22)), K(6, side_bend(0)), K(8, side_bend(-22)), K(10, side_bend(0)), K(12, "stand")],
       muscles=("upperBack", "abs", "shoulders"), yaw=10)
motion("arm-raise", [K(0, "stand"), K(2, P("stand", upperarm01=[0, 0, 170], lowerarm01=[-4, 0, 0], spine01=[-4, 0, 0], head=[-6, 0, 0])), K(4, "stand")],
       muscles=("shoulders",), yaw=15)
motion("back-extension", [K(0, "handsHips"), K(2, P("handsHips", spine04=[-5, 0, 0], spine03=[-5, 0, 0], spine02=[-4, 0, 0], neck01=[-8, 0, 0], head=[-8, 0, 0])),
                          K(4, "handsHips"), K(6, P("handsHips", spine04=[8, 0, 0], spine03=[8, 0, 0], spine02=[8, 0, 0], neck01=[14, 0, 0], head=[10, 0, 0])),
                          K(8, "handsHips")], muscles=("lowerBack", "abs"), yaw=70)

fold = P("stand", root={"rot": [["x", 62]]}, upperleg01=[-64, 0, 4], lowerleg01=[18, 0, 0], foot=[-16, 0, 0], spine04=[8, 0, 0], spine03=[8, 0, 0],
         spine02=[8, 0, 0], spine01=[6, 0, 0], neck01=[14, 0, 0], head=[10, 0, 0], upperarm01=[-92, 0, 4], lowerarm01=[-12, 0, 0])
motion("forward-fold", [K(0, "stand"), K(3, fold), K(6, fold), K(9, "stand")], muscles=("hamstrings", "lowerBack"), yaw=70)

# ─── Au sol ───
cat = P("quadruped", spine05=[8, 0, 0], spine04=[9, 0, 0], spine03=[9, 0, 0], spine02=[7, 0, 0], neck01=[10, 0, 0], head=[14, 0, 0])
cow = P("quadruped", spine05=[-7, 0, 0], spine04=[-7, 0, 0], spine03=[-6, 0, 0], spine02=[-4, 0, 0], neck01=[-24, 0, 0], head=[-10, 0, 0])
motion("cat-cow", [K(0, "quadruped"), K(2.5, cat), K(5, cow), K(7.5, "quadruped")], muscles=("lowerBack", "abs"), yaw=0, props=(MAT,))

child = P("stand", root={"rot": [["x", 94.5], ["y", 90]]}, upperleg01=[-154.5, 0, 10], lowerleg01=[145, 0, 0], foot=[78, 0, 0],
          upperarm01=[-166, 0, 6], lowerarm01=[-4, 0, 0], neck01=[-5, 0, 0])
motion("child-pose", [K(0, child), K(3, P(child, **BREATH_IN)), K(6, child)], muscles=("lowerBack",), yaw=0, props=(MAT,))

knees_up = P("supine", upperleg01=[-88, 0, 2], lowerleg01=[90, 0, 0], foot=[-6, 0, 0], upperarm01=[0, 0, 82], lowerarm01=[-4, 0, 0])
twist = lambda a: P(knees_up, root={"rot": [["y", a], ["x", -90], ["y", 90]]}, spine05=[0, -a * 0.3, 0], spine04=[0, -a * 0.3, 0], spine03=[0, -a * 0.4, 0])
motion("supine-twist", [K(0, knees_up), K(2, twist(42)), K(5, twist(42)), K(7, knees_up), K(9, twist(-42)), K(12, twist(-42)), K(14, knees_up)],
       muscles=("lowerBack", "glutes"), yaw=-70, pitch=28, props=(MAT,))
wall_legs = P("supine", upperleg01=[-88, 0, 2], foot=[-4, 0, 0], upperarm01=[0, 60, 40])
motion("legs-up-wall", [K(0, wall_legs), K(3, P(wall_legs, **BREATH_IN)), K(6, wall_legs)], muscles=("hamstrings",), yaw=0,
       props=(prop("wall", "lowerleg01.L", 0, (0.09, 0, 0), floor=True), MAT))

seated_fold = P("sitFloor", root={"rot": [["x", 38], ["y", 90]]}, upperleg01=[-128, 0, 2], lowerleg01=[10, 0, 0], foot=[-8, 0, 0],
                spine04=[6, 0, 0], spine03=[6, 0, 0], spine02=[6, 0, 0], neck01=[10, 0, 0], upperarm01=[-70, 0, 6], lowerarm01=[-6, 0, 0])
motion("seated-forward-fold", [K(0, "sitFloor"), K(3, seated_fold), K(6, seated_fold), K(9, "sitFloor")], muscles=("hamstrings", "lowerBack"),
       yaw=0, props=(MAT,))
butterfly = P(upperleg01=[-138, 7, -74], lowerleg01=[114, 0, 0], foot=[-100, 0, -30], upperarm01=[-50, 0, -6], lowerarm01=[-22, 0, 0], **fist(0.5))
motion("butterfly", [K(0, butterfly), K(3, P(butterfly, upperleg01=[-138, 7, -80], spine02=[4, 0, 0])), K(6, butterfly)],
       muscles=("quads", "glutes"), yaw=15, props=(MAT,))

# ─── Assis sur une chaise ───
clench = P("chairSit", upperarm01=[-24, 0, 6], lowerarm01=[-80, 0, 0], **fist(1))
motion("fists-clench", [K(0, "chairSit"), K(1, clench), K(3, clench), K(3.5, "chairSit", "out"), K(6, "chairSit")],
       muscles=("forearms", "biceps", "hands"), yaw=35, props=(CHAIR,))
motion("abs-contract", [K(0, "chairSit"), K(1.5, P("chairSit", spine04=[8, 0, 0], spine03=[8, 0, 0], spine02=[4, 0, 0])),
                        K(3, P("chairSit", spine04=[8, 0, 0], spine03=[8, 0, 0], spine02=[4, 0, 0])), K(4.5, "chairSit")],
       muscles=("abs",), yaw=60, props=(CHAIR,))
legs_out = P("chairSit", ground=False, lowerleg01=[12, 0, 0], foot=[-22, 0, 0])
motion("legs-tense", [K(0, "chairSit"), K(1.5, legs_out), K(3, legs_out), K(4.5, "chairSit")], muscles=("quads", "shins", "calves"),
       yaw=60, props=(CHAIR,))

if __name__ == "__main__":
    meta = json.load(open(MANNEQUIN))
    bones = [j["name"] for j in meta["bodies"]["male"]["joints"]]
    regions = meta["regions"]
    # Contrôles : os et régions connus
    def check_pose(p, where):
        if isinstance(p, str):
            assert p in POSES, f"{where} : pose inconnue {p}"
            return
        for b in p.get("bones", {}):
            assert b in bones or (b + ".L") in bones, f"{where} : os inconnu {b}"
        if "base" in p: check_pose(p["base"], where)
    for name, pose in POSES.items(): check_pose(pose, name)
    for mid, m in MOTIONS.items():
        for k in m["keys"]: check_pose(k["pose"], mid)
        for r in m["muscles"]: assert r in regions, f"{mid} : région inconnue {r}"
        ts = [k["t"] for k in m["keys"]]; assert ts == sorted(ts) and ts[0] == 0, mid
        for pr in m["props"]:
            assert pr["anchor"] is None or pr["anchor"] in bones, f"{mid} : ancre inconnue {pr['anchor']}"
    json.dump({"version": 1, "bones": bones, "regions": regions, "poses": POSES, "motions": MOTIONS},
              open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    print(len(MOTIONS), "mouvements →", OUT, os.path.getsize(OUT) // 1024, "Ko")
