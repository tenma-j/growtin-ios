"""Reciblage de captures de mouvement réelles (CMU Graphics Lab, conversion BVH de B. Hahne) sur le mannequin.

Données : http://mocap.cs.cmu.edu — « free for use in research projects. You may include this data in
commercially-sold products, but you may not resell this data directly, even in converted form. »
Base créée avec le financement NSF EIA-0196217.

Principe : pour chaque os du mannequin, on applique la rotation « monde » qu'a subie l'articulation CMU
correspondante depuis sa pose en T (première image de chaque fichier). Le mouvement est rendu sur place,
rééchantillonné et bouclé sans à-coup.
"""
import numpy as np

# ─── Lecture BVH ───
def parse_bvh(path):
    lines = open(path).read().split("\n")
    joints, stack, i = [], [], 0
    while not lines[i].strip().startswith("MOTION"):
        tok = lines[i].split()
        if tok and tok[0] in ("ROOT", "JOINT"):
            joints.append({"name": tok[1], "parent": stack[-1] if stack else None, "offset": None, "channels": []})
        elif tok and tok[0] == "End":
            joints.append({"name": None, "parent": stack[-1], "offset": None, "channels": []})
        elif tok and tok[0] == "{":
            stack.append(len(joints) - 1)
        elif tok and tok[0] == "}":
            stack.pop()
        elif tok and tok[0] == "OFFSET":
            joints[stack[-1]]["offset"] = np.array([float(x) for x in tok[1:4]])
        elif tok and tok[0] == "CHANNELS":
            joints[stack[-1]]["channels"] = tok[2:2 + int(tok[1])]
        i += 1
    n = int(lines[i + 1].split()[1]); dt = float(lines[i + 2].split()[2])
    data = np.array([[float(x) for x in l.split()] for l in lines[i + 3:i + 3 + n] if l.strip()])
    return joints, data, dt

def rot(axis, deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    if axis == "X": return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == "Y": return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])

def bvh_fk(joints, frame):
    """Rotations et positions monde de chaque articulation pour une image."""
    G, P, k = [None] * len(joints), [None] * len(joints), 0
    for j, jt in enumerate(joints):
        R = np.eye(3); t = np.zeros(3)
        for ch in jt["channels"]:
            v = frame[k]; k += 1
            if ch.endswith("position"):
                t["XYZ".index(ch[0])] = v
            else:
                R = R @ rot(ch[0], v)
        p = jt["parent"]
        if p is None:
            G[j] = R; P[j] = t + jt["offset"]
        else:
            G[j] = G[p] @ R; P[j] = P[p] + G[p] @ jt["offset"]
    return G, P

# ─── Correspondance des os ───
LEFT_RIGHT = (("L", "Left"), ("R", "Right"))
def mapping():
    m = {"root": "Hips", "spine05": "LowerBack", "spine04": "LowerBack", "spine03": "Spine", "spine02": "Spine",
         "spine01": "Spine1", "neck01": "Neck", "neck02": "Neck1", "neck03": "Neck1", "head": "Head"}
    for s, side in LEFT_RIGHT:
        m.update({f"pelvis.{s}": "Hips", f"upperleg01.{s}": f"{side}UpLeg", f"upperleg02.{s}": f"{side}UpLeg",
                  f"lowerleg01.{s}": f"{side}Leg", f"lowerleg02.{s}": f"{side}Leg", f"foot.{s}": f"{side}Foot",
                  f"toes.{s}": f"{side}ToeBase", f"clavicle.{s}": f"{side}Shoulder", f"shoulder01.{s}": f"{side}Shoulder",
                  f"upperarm01.{s}": f"{side}Arm", f"upperarm02.{s}": f"{side}Arm", f"lowerarm01.{s}": f"{side}ForeArm",
                  f"lowerarm02.{s}": f"{side}ForeArm", f"wrist.{s}": f"{side}Hand"})
    return m

def shortest(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = a @ b; s = np.linalg.norm(v)
    if s < 1e-9:
        return np.eye(3)
    k = v / s; K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    ang = np.arctan2(s, c)
    return np.eye(3) + np.sin(ang) * K + (1 - np.cos(ang)) * K @ K

def tpose_offsets(rig_names, heads, arm_dirs=None):
    """Orientation monde de chaque os du mannequin dans la pose en T de la capture (bras presque horizontaux)."""
    T = {}
    for s, sgn in (("L", 1), ("R", -1)):
        sh, el = heads[f"upperarm01.{s}"], heads[f"lowerarm01.{s}"]
        target = arm_dirs[s] if arm_dirs else np.array([sgn, 0.0, 0.0])
        R = shortest(el - sh, target)
        for n in rig_names:
            if n.endswith("." + s) and n.split(".")[0].startswith(("upperarm", "lowerarm", "wrist", "finger", "metacarpal")):
                T[n] = R
    return T

def matrix_to_quat(R):
    t = np.trace(R)
    if t > 0:
        s = np.sqrt(t + 1) * 2; w = 0.25 * s
        x = (R[2, 1] - R[1, 2]) / s; y = (R[0, 2] - R[2, 0]) / s; z = (R[1, 0] - R[0, 1]) / s
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = np.sqrt(1 + R[0, 0] - R[1, 1] - R[2, 2]) * 2; w = (R[2, 1] - R[1, 2]) / s
        x = 0.25 * s; y = (R[0, 1] + R[1, 0]) / s; z = (R[0, 2] + R[2, 0]) / s
    elif R[1, 1] > R[2, 2]:
        s = np.sqrt(1 + R[1, 1] - R[0, 0] - R[2, 2]) * 2; w = (R[0, 2] - R[2, 0]) / s
        x = (R[0, 1] + R[1, 0]) / s; y = 0.25 * s; z = (R[1, 2] + R[2, 1]) / s
    else:
        s = np.sqrt(1 + R[2, 2] - R[0, 0] - R[1, 1]) * 2; w = (R[1, 0] - R[0, 1]) / s
        x = (R[0, 2] + R[2, 0]) / s; y = (R[1, 2] + R[2, 1]) / s; z = 0.25 * s
    q = np.array([x, y, z, w]); return q / np.linalg.norm(q)

def quat_to_matrix(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])

def slerp(a, b, t):
    d = a @ b
    if d < 0: b = -b; d = -d
    if d > 0.9995:
        q = a + (b - a) * t; return q / np.linalg.norm(q)
    th = np.arccos(d); return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)

def retarget(path, rig_names, rig_parents, heads, start, end, fps=30, face=True, in_place=True, blend=0.35):
    """Renvoie (noms d'os, rotations locales [images × os × 4], décalages horizontaux de la racine [images × 2])."""
    joints, data, dt = parse_bvh(path)
    idx = {j["name"]: k for k, j in enumerate(joints) if j["name"]}
    G0, P0 = bvh_fk(joints, data[0])
    m = mapping()
    arm_dirs = {}
    for s, side in LEFT_RIGHT:
        d = P0[idx[f"{side}ForeArm"]] - P0[idx[f"{side}Arm"]]
        arm_dirs[s] = d / np.linalg.norm(d)
    T = tpose_offsets(rig_names, heads, arm_dirs)
    step = max(1, int(round(1 / (fps * dt))))
    frames = list(range(start, min(end, len(data)), step))
    # Cap moyen sur l'extrait : le personnage est tourné pour regarder vers +Z.
    yaw = 0.0
    if face:
        fw = []
        for f in frames[:: max(1, len(frames) // 12)]:
            G, _ = bvh_fk(joints, data[f])
            D = G[idx["Hips"]] @ G0[idx["Hips"]].T
            v = D @ np.array([0, 0, 1.0]); fw.append(np.arctan2(v[0], v[2]))
        yaw = np.degrees(np.arctan2(np.mean(np.sin(fw)), np.mean(np.cos(fw))))
    Ryaw = rot("Y", -yaw)
    hip_h = P0[idx["Hips"]][1] - min(P0[k][1] for k in range(len(joints)))
    our_hip = heads["root"][1]
    scale = our_hip / hip_h
    out_q, out_off = [], []
    base_xz = None
    for f in frames:
        G, P = bvh_fk(joints, data[f])
        W = {}
        for n in rig_names:
            if n in m and m[n] in idx:
                j = idx[m[n]]
                D = Ryaw @ G[j] @ G0[j].T @ Ryaw.T
                W[n] = D @ T.get(n, np.eye(3))
        # Os sans correspondance (doigts, orteils…) : ils suivent leur parent.
        local = []
        for n, p in zip(rig_names, rig_parents):
            if n not in W:
                W[n] = W[p] @ (T[p].T @ T.get(n, np.eye(3)) if p in T else T.get(n, np.eye(3))) if p is not None and p in W else np.eye(3)
            L = W[n] if p is None else W[p].T @ W[n]
            local.append(matrix_to_quat(L))
        hp = Ryaw @ (P[idx["Hips"]] - P0[idx["Hips"]]) * scale
        if base_xz is None: base_xz = hp[[0, 2]]
        out_q.append(local); out_off.append(hp[[0, 2]] - base_xz)
    Q = np.array(out_q); off = np.array(out_off)
    if in_place:
        off[:] = 0
    # Boucle : les dernières images se fondent dans les premières.
    nb = int(blend * fps)
    if nb > 1 and len(Q) > 2 * nb:
        for k in range(nb):
            t = (k + 1) / (nb + 1)
            i = len(Q) - nb + k
            for b in range(Q.shape[1]):
                Q[i, b] = slerp(Q[i, b], Q[k, b], t)
    return Q, off
