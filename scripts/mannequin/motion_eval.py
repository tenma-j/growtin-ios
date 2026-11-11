"""Évaluation des poses du fichier motions.json (mêmes règles que l'app) et aperçus en planche.

Règles :
- "bones" : angles d'Euler (degrés, ordre X puis Y puis Z) relatifs au parent. Une clé sans côté
  (ex. "upperleg01") s'applique aux deux côtés, en miroir pour la droite : [x, -y, -z].
- "root" : liste de rotations successives autour des axes du monde (["x", -90], ["y", 90]…), puis "offset".
- Chaque image clé est posée au sol : le point le plus bas de la peau est ramené à y = 0 (sauf "ground": false).
"""
import json, sys, os
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from rig import Rig, euler, axis_angle  # noqa: E402

AX = {"x": [1, 0, 0], "y": [0, 1, 0], "z": [0, 0, 1]}

def resolve(pose, poses):
    """Fusionne une pose avec sa pose de base (« base »), récursivement."""
    if isinstance(pose, str):
        pose = {"base": pose}
    out = {"bones": {}, "root": {"rot": [], "offset": [0, 0, 0]}, "ground": True}
    if "base" in pose:
        b = resolve(pose["base"] if isinstance(pose["base"], dict) else poses[pose["base"]], poses)
        out["bones"].update(b["bones"]); out["root"] = json.loads(json.dumps(b["root"])); out["ground"] = b["ground"]
    for k, val in pose.get("bones", {}).items():
        if k.endswith((".L", ".R")):
            out["bones"][k] = val
        else:
            out["bones"][k + ".L"] = val
            out["bones"][k + ".R"] = [val[0], -val[1], -val[2]]
            out["bones"][k] = val  # os central (colonne, tête…)
    if "root" in pose:
        if "rot" in pose["root"]: out["root"]["rot"] = pose["root"]["rot"]
        if "offset" in pose["root"]: out["root"]["offset"] = pose["root"]["offset"]
    if "ground" in pose: out["ground"] = pose["ground"]
    return out

def local_rotations(p, names):
    loc = {}
    for n in names:
        if n in p["bones"]:
            loc[n] = euler(p["bones"][n])
    R = np.eye(3)
    for axis, deg in p["root"]["rot"]:
        R = axis_angle(AX[axis], deg) @ R
    loc["root"] = R @ loc.get("root", np.eye(3))
    return loc

class Body:
    def __init__(self, npz):
        d = np.load(npz)
        self.v, self.n, self.tris = d["v"], d["n"], d["tris"]
        self.bi, self.bw = d["bone_idx"], d["bone_w"]
        self.names = [str(x) for x in d["order"]]
        parents = {n: (str(p) or None) for n, p in zip(self.names, d["parents"])}
        self.rig = Rig(self.names, parents, {n: h for n, h in zip(self.names, d["heads"])})
        self.tri_lab, self.tri_cloth = d["tri_lab"], d["tri_cloth"]
        self.sample = np.arange(0, len(self.v), 7)

    def lift(self, p, previous=0.0):
        """Mise au sol : le point le plus bas touche y = 0 ; sans mise au sol, on garde la hauteur précédente."""
        if not p["ground"]:
            return previous
        loc = local_rotations(p, self.names)
        R, P = self.rig.fk(loc, p["root"]["offset"])
        s = self.sample
        vs, _ = self.rig.skin(self.v[s], self.n[s], self.bi[s], self.bw[s], R, P)
        return -vs[:, 1].min()

    def pose(self, p, joints=False, lift=None):
        loc = local_rotations(p, self.names)
        R, P = self.rig.fk(loc, p["root"]["offset"])
        P = P + [0, self.lift(p) if lift is None else lift, 0]
        v, n = self.rig.skin(self.v, self.n, self.bi, self.bw, R, P)
        return (v, n, P) if joints else (v, n)

    def lifts(self, motion, poses):
        out, prev = [], 0.0
        for key in motion["keys"]:
            prev = self.lift(resolve(key["pose"], poses), prev)
            out.append(prev)
        return out

# ─── Accessoires (mêmes dimensions que dans l'app) ───
def boxes_for(prop, anchor):
    """Liste de pavés (centre, demi-tailles) dans le repère du personnage."""
    a = np.array(anchor if anchor is not None else [0, 0, 0], float) + prop["offset"]
    if prop.get("floor"): a[1] = 0
    out = []
    k = prop["kind"]
    if k == "chair":
        top = a[1]
        out += [((0, top - 0.02, 0), (0.22, 0.02, 0.21)), ((0, top + 0.24, -0.2), (0.22, 0.22, 0.015))]
        for x in (-0.19, 0.19):
            for z in (-0.18, 0.18):
                out.append(((x, (top - 0.04) / 2, z), (0.017, (top - 0.04) / 2, 0.017)))
    elif k == "table":
        top = a[1]
        out += [((0, top - 0.02, 0.1), (0.5, 0.02, 0.32))]
        for x in (-0.45, 0.45):
            for z in (-0.18, 0.38):
                out.append(((x, (top - 0.04) / 2, z), (0.025, (top - 0.04) / 2, 0.025)))
    elif k == "wall":
        out.append(((0.03, 1.1, 0), (0.03, 1.1, 1.2)))
    elif k == "mat":
        out.append(((0, 0.003, 0), (0.95, 0.003, 0.31)))
    yaw = np.radians(prop.get("yaw", 0)); c, s_ = np.cos(yaw), np.sin(yaw)
    Ry = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
    res = []
    for center, half in out:
        cc = np.array(center, float)
        cc = Ry @ cc if k in ("wall",) else cc
        if k in ("chair", "table"):
            cc = Ry @ np.array([center[0], 0, center[2]]) + [0, center[1], 0]
            res.append((cc + [a[0], 0, a[2]], half, Ry))
        elif k == "wall":
            res.append((cc + [a[0], 0, a[2]], half, Ry))
        else:
            res.append((cc + [a[0], 0, a[2]], half, Ry))
    return res

def box_mesh(center, half, R):
    corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], float) * half
    v = corners @ R.T + center
    f = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]
    tris = np.array(f)
    fn = np.cross(v[tris[:, 1]] - v[tris[:, 0]], v[tris[:, 2]] - v[tris[:, 0]])
    n = np.zeros_like(v)
    for k in range(3): np.add.at(n, tris[:, k], fn)
    n /= np.linalg.norm(n, axis=1, keepdims=True)
    return v, n, tris

def sheet(body, motion_ids, lib, path, size=300, export_mod=None):
    from PIL import Image, ImageDraw
    from export import render, colors_for, REGIONS
    tiles = []
    for mid in motion_ids:
        m = lib["motions"][mid]
        lifts = body.lifts(m, lib["poses"])
        for i, key in enumerate(m["keys"]):
            p = resolve(key["pose"], lib["poses"])
            v, n = body.pose(p, lift=lifts[i])
            cols = colors_for({"tri_lab": body.tri_lab, "tri_cloth": body.tri_cloth}, set(m.get("muscles", [])))
            tris = body.tris
            for pr in m.get("props", []):
                ki = pr.get("key") or 0
                kp = resolve(m["keys"][ki]["pose"], lib["poses"])
                _, _, J = body.pose(kp, joints=True, lift=lifts[ki])
                anchor = J[body.names.index(pr["anchor"])] if pr.get("anchor") else None
                for center, half, R in boxes_for(pr, anchor):
                    bv, bn, bt = box_mesh(center, np.array(half), R)
                    tris = np.vstack([tris, bt + len(v)]); v = np.vstack([v, bv]); n = np.vstack([n, bn])
                    cols = list(cols) + [np.array([0.35, 0.36, 0.4])] * len(bt)
            yaw = m.get("camera", {}).get("yaw", 30)
            vb = v[: len(body.v)]
            c = vb.mean(0); c[1] = (vb[:, 1].max() + vb[:, 1].min()) / 2
            ext = max(vb[:, 1].max() - vb[:, 1].min(), np.ptp(vb[:, 0]), np.ptp(vb[:, 2])) * 1.25
            tmp = f"/tmp/_tile_{os.getpid()}.png"
            render(v, n, tris, cols, tmp, size=size, yaw=yaw, pitch=m.get("camera", {}).get("pitch", 8), center=c, zoom=2.1 / ext)
            im = Image.open(tmp).convert("RGB"); ImageDraw.Draw(im).text((6, 6), f"{mid} #{i}", fill=(255, 255, 255))
            tiles.append(im)
    cols_n = 6; rows = (len(tiles) + cols_n - 1) // cols_n
    out = Image.new("RGB", (cols_n * size, rows * size))
    for k, t in enumerate(tiles): out.paste(t, ((k % cols_n) * size, (k // cols_n) * size))
    out.save(path)

if __name__ == "__main__":
    lib = json.load(open(sys.argv[1])); body = Body(sys.argv[2])
    ids = sys.argv[4].split(",") if len(sys.argv) > 4 else list(lib["motions"])
    sheet(body, ids, lib, sys.argv[3])
