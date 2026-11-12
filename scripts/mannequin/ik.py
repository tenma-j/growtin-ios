"""Cinématique inverse pour écrire les poses par objectifs (pied posé ici, main posée là) plutôt que par angles.

Chaîne à deux segments (cuisse-jambe, bras-avant-bras) résolue analytiquement, avec les mêmes conventions
que l'app : os alignés sur le repère monde dans la pose de référence, angles d'Euler X puis Y puis Z
(R = Rz · Ry · Rx), relatifs au parent. Les angles produits s'écrivent tels quels dans les poses (os latéralisés).
"""
import numpy as np
from rig import Rig, euler, axis_angle
from motion_eval import resolve, local_rotations

def to_euler(R):
    """Matrice → angles (degrés) tels que R = Rz · Ry · Rx."""
    y = -np.degrees(np.arcsin(np.clip(R[2, 0], -1, 1)))
    x = np.degrees(np.arctan2(R[2, 1], R[2, 2]))
    z = np.degrees(np.arctan2(R[1, 0], R[0, 0]))
    return [round(float(x), 1), round(float(y), 1), round(float(z), 1)]

def _unit(v):
    return v / np.linalg.norm(v)

def with_bones(pose, bones):
    """Copie d'une pose (dict) avec des os latéralisés en plus (« upperleg01_L » ou « upperleg01.L »)."""
    import copy
    p = copy.deepcopy(pose) if isinstance(pose, dict) else {"base": pose, "bones": {}}
    p.setdefault("bones", {})
    for k, v in bones.items():
        name = k[:-2] + "." + k[-1] if k.endswith(("_L", "_R")) else k
        p["bones"][name] = [float(x) for x in v]
    return p

class IK:
    def __init__(self, joints, poses):
        names = [j["name"] for j in joints]
        self.names = names
        self.rig = Rig(names, {j["name"]: j["parent"] for j in joints}, {j["name"]: np.array(j["head"], float) for j in joints})
        self.H = {n: self.rig.heads[i] for i, n in enumerate(names)}
        self.poses = poses

    def fk(self, pose):
        p = resolve(pose, self.poses)
        loc = local_rotations(p, self.names)
        R, P = self.rig.fk(loc, p["root"]["offset"])
        return {n: R[i] for i, n in enumerate(self.names)}, {n: P[i] for i, n in enumerate(self.names)}

    def _chain(self, pose, side, upper, lower, end, target, pole, bend_sign):
        """Oriente « upper » et plie « lower » (charnière X) pour amener « end » sur « target »."""
        R, P = self.fk(pose)
        u, l, e = f"{upper}.{side}", f"{lower}.{side}", f"{end}.{side}"
        parent = self.rig.parents[self.rig.index[u]]
        Rp = R[parent]
        H = P[u]
        L1 = np.linalg.norm(self.H[l] - self.H[u]); L2 = np.linalg.norm(self.H[e] - self.H[l])
        b1 = _unit(self.H[l] - self.H[u]); b2 = _unit(self.H[e] - self.H[l])
        T = np.asarray(target, float)
        d = T - H; dist = np.clip(np.linalg.norm(d), abs(L1 - L2) + 1e-4, L1 + L2 - 1e-4)
        dn = _unit(d)
        # Position du coude / genou : loi des cosinus, dans le plan contenant le pôle.
        a = (L1 ** 2 - L2 ** 2 + dist ** 2) / (2 * dist)
        h = np.sqrt(max(L1 ** 2 - a ** 2, 0.0))
        pole = np.asarray(pole, float)
        pv = _unit(pole - (pole @ dn) * dn)
        K = H + dn * a + pv * h
        t = _unit(K - H); s = _unit(T - K)
        # Axe de charnière : perpendiculaire au plan du membre (choisi pour que la flexion ait le bon signe).
        hinge = np.cross(t, s)
        if np.linalg.norm(hinge) < 1e-6:
            hinge = np.cross(t, pv)
        hinge = _unit(hinge) * bend_sign
        def frame(down, x):
            y = -down; x = _unit(x - (x @ y) * y); return np.column_stack([x, y, np.cross(x, y)])
        Fb = frame(b1, np.array([1.0, 0, 0]))
        Fp = frame(t, hinge)
        Rw = Fp @ Fb.T                                   # rotation monde du segment supérieur
        local_upper = Rp.T @ Rw
        sl = Rw.T @ s                                    # direction voulue du segment inférieur, repère du segment supérieur
        k = np.degrees(np.arctan2(sl[2], sl[1]) - np.arctan2(b2[2], b2[1]))
        k = (k + 180) % 360 - 180
        return to_euler(local_upper), round(float(k), 1), Rw @ euler([k, 0, 0])

    def _solve(self, pose, side, upper, lower, end, target, pole, bend_sign, iterations=6):
        """La jambe et le bras de référence ne sont pas parfaitement plans : on corrige l'objectif jusqu'à l'atteindre."""
        T = np.asarray(target, float); aim = T.copy()
        for _ in range(iterations):
            up, k, Rlow = self._chain(pose, side, upper, lower, end, aim, pole, bend_sign)
            trial = with_bones(pose, {f"{upper}_{side}": up, f"{lower}_{side}": [k, 0, 0]})
            err = T - self.fk(trial)[1][f"{end}.{side}"]
            if np.linalg.norm(err) < 5e-4:
                break
            aim = aim + err
        return up, k, Rlow

    def leg(self, pose, side, ankle, pole=(0, 0, 1), foot_yaw=0.0, foot_pitch=0.0, toes=None, foot_rot=None):
        """Angles de la jambe pour poser la cheville en « ankle » ; pied à plat (ou incliné de foot_pitch, X > 0 pointe en bas).
        foot_rot : orientation monde imposée au pied (matrice), à la place de foot_yaw / foot_pitch."""
        up, k, Rshin = self._solve(pose, side, "upperleg01", "lowerleg01", "foot", ankle, pole, +1)
        Rfoot = foot_rot if foot_rot is not None else axis_angle([0, 1, 0], foot_yaw) @ axis_angle([1, 0, 0], foot_pitch)
        out = {f"upperleg01_{side}": up, f"lowerleg01_{side}": [k, 0, 0], f"foot_{side}": to_euler(Rshin.T @ Rfoot)}
        if toes is not None:
            out[f"toes_{side}"] = [toes, 0, 0]
        return out

    def arm(self, pose, side, wrist, pole=(0, -1, -0.3)):
        """Angles du bras pour amener le poignet en « wrist » (pôle : direction du coude)."""
        up, k, _ = self._solve(pose, side, "upperarm01", "lowerarm01", "wrist", wrist, pole, -1)
        return {f"upperarm01_{side}": up, f"lowerarm01_{side}": [k, 0, 0]}

    def joint(self, pose, name):
        return self.fk(pose)[1][name]

    def ground_offset(self, pose, name, target_xz):
        """Décalage horizontal de la racine pour que l'articulation « name » se trouve en target_xz."""
        p = self.joint(pose, name)
        return np.array([target_xz[0] - p[0], 0.0, target_xz[1] - p[2]])

def _quat(R):
    t = np.trace(R)
    if t > 0:
        s = np.sqrt(t + 1) * 2
        return np.array([(R[2, 1] - R[1, 2]) / s, (R[0, 2] - R[2, 0]) / s, (R[1, 0] - R[0, 1]) / s, 0.25 * s])
    i = int(np.argmax(np.diag(R)))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = np.sqrt(1 + R[i, i] - R[j, j] - R[k, k]) * 2
    q = np.zeros(4); q[i] = 0.25 * s
    q[j] = (R[j, i] + R[i, j]) / s; q[k] = (R[k, i] + R[i, k]) / s; q[3] = (R[k, j] - R[j, k]) / s
    return q

def _hand_frame(fingers, palm):
    f = _unit(np.asarray(fingers, float)); n = np.asarray(palm, float)
    n = _unit(n - (n @ f) * f)
    return np.column_stack([f, n, np.cross(f, n)])

def _hand_world(self, pose, side, fingers, palm):
    """Rotation du poignet (avant-bras : torsion sur lowerarm02, reste sur wrist) pour orienter la main.
    fingers : direction des doigts ; palm : direction vers laquelle regarde la paume (monde)."""
    R, P = self.fk(pose)
    sgn = 1 if side == "L" else -1
    fb = _unit(self.H[f"finger3-1.{side}"] - self.H[f"wrist.{side}"])
    across = self.H[f"finger2-1.{side}"] - self.H[f"finger5-1.{side}"]
    nb = sgn * _unit(np.cross(fb, across))
    Rhand = _hand_frame(fingers, palm) @ _hand_frame(fb, nb).T
    Q = R[f"lowerarm01.{side}"].T @ Rhand              # = torsion (lowerarm02) · poignet
    q = _quat(Q)
    tw = np.array([0, q[1], 0, q[3]]); tw /= np.linalg.norm(tw)
    ang = np.degrees(2 * np.arctan2(tw[1], tw[3]))
    ang = (ang + 180) % 360 - 180
    ang = float(np.clip(ang, -100, 100))
    T = axis_angle([0, 1, 0], ang)
    return {f"lowerarm02_{side}": [0, round(ang, 1), 0], f"wrist_{side}": to_euler(T.T @ Q)}

IK.hand = _hand_world

def _place_hand(self, pose, side, wrist, fingers, palm, pole=(0, -1, -0.3), passes=2):
    """Poignet en « wrist » et main orientée (doigts, paume) ; deux passes car la torsion déplace un peu le poignet."""
    p = pose
    for _ in range(passes):
        p = with_bones(p, self.arm(p, side, wrist, pole))
        p = with_bones(p, self.hand(p, side, fingers, palm))
    return p

IK.place_hand = _place_hand
