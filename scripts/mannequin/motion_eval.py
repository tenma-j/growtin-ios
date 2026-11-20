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
    # clés sans côté d'abord, puis clés latéralisées (même ordre que l'app)
    items = sorted(pose.get("bones", {}).items(), key=lambda kv: kv[0].endswith((".L", ".R")))
    for k, val in items:
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

def read_bin(path):
    """Corps tel que l'app le lit (Resources/Mannequin/mannequin-*.bin, format GTM5 ou GTM4) : maillages bout à bout."""
    import struct
    data = open(path, "rb").read()
    magic, count = struct.unpack_from("<4sI", data, 0)
    off = 8
    if magic == b"GTM5":
        k = struct.unpack_from("<I", data, off)[0]; off += 4
    elif magic == b"GTM4":
        k = 4
    else:
        raise ValueError(f"{path} : en-tête inconnu")
    v, n, bi, bw, tris, mat = [], [], [], [], [], []
    base = 0
    for _ in range(count):
        material, nv, ni = struct.unpack_from("<III", data, off); off += 12
        def take(dtype, size):
            nonlocal off
            a = np.frombuffer(data, dtype, size, off); off += a.nbytes
            return a
        v.append(take("<f4", nv * 3).reshape(nv, 3)); n.append(take("<f4", nv * 3).reshape(nv, 3))
        bi.append(take("<u2", nv * k).reshape(nv, k).astype(int)); bw.append(take("<f4", nv * k).reshape(nv, k))
        t = take("<u4", ni).reshape(-1, 3).astype(int) + base
        tris.append(t); mat.append(np.full(len(t), material)); base += nv
    return {"v": np.concatenate(v).astype(float), "n": np.concatenate(n).astype(float), "tris": np.concatenate(tris),
            "bone_idx": np.concatenate(bi), "bone_w": np.concatenate(bw).astype(float), "tri_mat": np.concatenate(mat)}

class Body:
    def __init__(self, npz):
        d = np.load(npz) if isinstance(npz, str) else npz
        has = (lambda key: key in d.files) if hasattr(d, "files") else (lambda key: key in d)
        self.v, self.n, self.tris = d["v"], d["n"], d["tris"]
        self.bi, self.bw = d["bone_idx"], d["bone_w"]
        self.names = [str(x) for x in d["order"]]
        parents = {n: (str(p) or None) for n, p in zip(self.names, d["parents"])}
        halves = {self.names[int(h)]: self.names[int(b)] for h, b in d["halves"]} if has("halves") else {}
        self.rig = Rig(self.names, parents, {n: h for n, h in zip(self.names, d["heads"])}, halves)
        self.tri_mat = d["tri_mat"] if has("tri_mat") else np.zeros(len(self.tris), int)
        body_count = int(d["body_count"]) if has("body_count") else len(self.v)
        self.sample = np.arange(0, body_count, 7)
        self.offset_scale = 1.0       # décalages de la racine mis à l'échelle du corps (comme dans l'app)

    @classmethod
    def from_resources(cls, body_name, resources):
        """Corps de l'app : Resources/Mannequin/mannequin.json (squelette) et mannequin-<corps>.bin (maillages)."""
        meta = json.load(open(os.path.join(resources, "mannequin.json")))["bodies"][body_name]
        names = [j["name"] for j in meta["joints"]]
        d = read_bin(os.path.join(resources, f"mannequin-{body_name}.bin"))
        d.update(order=names, parents=[j["parent"] or "" for j in meta["joints"]], heads=[j["head"] for j in meta["joints"]],
                 halves=[(names.index(j["name"]), names.index(j["half"])) for j in meta["joints"] if j.get("half")])
        return cls(d)

    def lift(self, p, previous=0.0):
        """Mise au sol : le point le plus bas touche y = 0 ; sans mise au sol, on garde la hauteur précédente."""
        if not p["ground"]:
            return previous
        loc = local_rotations(p, self.names)
        R, P = self.rig.fk(loc, np.asarray(p["root"]["offset"], float) * self.offset_scale)
        s = self.sample
        vs, _ = self.rig.skin(self.v[s], self.n[s], self.bi[s], self.bw[s], R, P)
        return -vs[:, 1].min()

    def pose(self, p, joints=False, lift=None):
        loc = local_rotations(p, self.names)
        R, P = self.rig.fk(loc, np.asarray(p["root"]["offset"], float) * self.offset_scale)
        P = P + [0, self.lift(p) if lift is None else lift, 0]
        v, n = self.rig.skin(self.v, self.n, self.bi, self.bw, R, P)
        return (v, n, P) if joints else (v, n)

    def lifts(self, motion, poses):
        out, prev = [], 0.0
        support = motion.get("support") or 0.0
        for key in motion["keys"]:
            p = resolve(key["pose"], poses)
            prev = self.lift(p, prev - support) + support if p["ground"] else prev
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
    elif k == "bed":
        top = 0.5 if prop.get("floor") else a[1]
        out += [((0, (top - 0.09) / 2, 0), (1.0, (top - 0.09) / 2, 0.73)), ((0, top - 0.1, 0), (0.98, 0.1, 0.71)),
                ((-1.03, (top + 0.45) / 2, 0), (0.035, (top + 0.45) / 2, 0.73))]
    elif k == "pillow":
        # « depth » : profondeur le long du lit, « width » : largeur en travers (34 et 56 cm par défaut)
        out.append(((0, a[1] - 0.05, 0), ((prop.get("depth") or 0.34) / 2, 0.05, (prop.get("width") or 0.56) / 2)))
    elif k == "door":
        half = (prop.get("width") or 1.0) / 2                # distance entre les axes des montants : à la mesure du corps
        for x in (-half, half):
            out.append(((x, 1.025, 0), (0.035, 1.025, 0.06)))
        out.append(((0, 2.085, 0), (half + 0.035, 0.035, 0.06)))
    yaw = np.radians(prop.get("yaw", 0)); c, s_ = np.cos(yaw), np.sin(yaw)
    Ry = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
    res = []
    for center, half in out:
        cc = np.array(center, float)
        cc = Ry @ cc if k in ("wall",) else cc
        if k in ("chair", "table", "door", "bed", "pillow"):
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

# ─── Serviette (même calcul que TowelPath, GrowtinCore) ───
TOWEL_WIDTH, TOWEL_THICKNESS = 0.05, 0.006              # bande à plat (valeurs par défaut)
TOWEL_GRIP = (0.022, 0.012)                             # bande resserrée dans le poing (largeur, épaisseur)

def towel_grip(palm, back, depth):
    """Point tenu dans le creux du poing : à « depth » de la paume, à l'opposé du dos de la main (TowelPath.grip)."""
    out = palm - back; n = np.linalg.norm(out)
    return palm + out * (depth / n) if n > 1e-6 else palm

def towel_segments(prop, v):
    """Trois tronçons de bande d'une serviette coincée sous un pied, d'après la peau déformée « v » :
    brin gauche (du sol au poing), passage à plat sous le pied, brin droit (du sol au poing).
    Chaque tronçon : (départ, arrivée, largeur, normale, (largeur, épaisseur) au départ, (largeur, épaisseur) à l'arrivée)."""
    ids, under = prop.get("vertices") or [], prop.get("under") or []
    if len(ids) != 3 or len(under) != 2:
        return []
    w, th = prop.get("width") or TOWEL_WIDTH, prop.get("thickness") or TOWEL_THICKNESS
    left, foot, right = (np.asarray(v[i], float) for i in ids)
    backs = prop.get("backs")
    if backs and len(backs) == 2:
        left, right = (towel_grip(p, np.asarray(v[i], float), prop.get("depth") or 0.0) for p, i in ((left, backs[0]), (right, backs[1])))
    a = np.array([foot[0] + under[0][0], th / 2, foot[2] + under[0][1]])
    b = np.array([foot[0] + under[1][0], th / 2, foot[2] + under[1][1]])
    u = (b - a) / np.linalg.norm(b - a)
    side0 = np.array([-u[2], 0.0, u[0]])                # largeur sous le pied : horizontale, dans l'axe du pied
    out = []
    for p, q, s0, s1 in ((a, left, (w, th), TOWEL_GRIP), (a, b, (w, th), (w, th)), (b, right, (w, th), TOWEL_GRIP)):
        d = (q - p) / np.linalg.norm(q - p)
        side = side0 - d * (side0 @ d); side /= np.linalg.norm(side)
        out.append((p, q, side, np.cross(side, d), s0, s1))
    return out

def band_mesh(seg):
    """Maillage d'un tronçon de bande (section qui change d'un bout à l'autre), comme le dessine l'app."""
    p, q, side, normal, s0, s1 = seg
    corners = np.array([c + sx * side * s[0] / 2 + sz * normal * s[1] / 2
                        for c, s in ((p, s0), (q, s1)) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    v, n, t = [], [], []
    for f in faces:
        pts = corners[list(f)]; fn = np.cross(pts[1] - pts[0], pts[2] - pts[0]); fn /= np.linalg.norm(fn)
        base = len(v); v += list(pts); n += [fn] * 4; t += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    return np.array(v), np.array(n), np.array(t)

def band_distance(seg, pts):
    """Distance de points à la surface d'un tronçon de bande (négative à l'intérieur) et abscisse le long du tronçon (m)."""
    p, q, side, normal, s0, s1 = seg
    L = np.linalg.norm(q - p); d = (q - p) / L
    rel = np.asarray(pts, float) - p
    s = rel @ d; f = np.clip(s / L, 0, 1)
    hw = (s0[0] + (s1[0] - s0[0]) * f) / 2; ht = (s0[1] + (s1[1] - s0[1]) * f) / 2
    e = np.stack([np.abs(rel @ side) - hw, np.abs(rel @ normal) - ht, np.maximum(-s, s - L)], 1)
    outside = np.linalg.norm(np.maximum(e, 0), axis=1)
    return np.where(outside > 0, outside, e.max(1)), s

# ─── Verre tenu en main (même calcul que HeldGlass, GrowtinCore) ───
GLASS_WIDTH, GLASS_HEIGHT = 0.062, 0.105                # diamètre et hauteur par défaut

def glass_pose(prop, v):
    """Centre et axe (du fond vers le bord) d'un verre tenu, d'après la peau déformée « v » : sommets du creux de la
    paume, du bord de la paume côté index et du dos de la main ; l'axe du verre est à « depth » de la paume."""
    palm, index, back = (np.asarray(v[i], float) for i in prop["vertices"])
    n = (palm - back) / np.linalg.norm(palm - back)
    up = (index - palm) - n * ((index - palm) @ n)
    return palm + n * (prop.get("depth") or 0.0), up / np.linalg.norm(up)

def glass_mesh(prop, v, sides=20):
    """Maillage du verre (cylindre fermé), comme le dessine l'app."""
    c, a = glass_pose(prop, v)
    r, h = (prop.get("width") or GLASS_WIDTH) / 2, prop.get("height") or GLASS_HEIGHT
    x = np.cross(a, [1.0, 0, 0] if abs(a[0]) < 0.9 else [0, 0, 1.0]); x /= np.linalg.norm(x); z = np.cross(x, a)
    ang = np.arange(sides) * 2 * np.pi / sides
    ring = np.cos(ang)[:, None] * x + np.sin(ang)[:, None] * z
    V = np.vstack([c - a * h / 2 + r * ring, c + a * h / 2 + r * ring, [c - a * h / 2], [c + a * h / 2]])
    N = np.vstack([ring, ring, [-a], [a]])
    T = []
    for i in range(sides):
        j = (i + 1) % sides
        T += [(i, j, sides + j), (i, sides + j, sides + i), (2 * sides, j, i), (2 * sides + 1, sides + i, sides + j)]
    return V, N, np.array(T)

def glass_distance(prop, v, pts):
    """Distance de points à la surface du verre (négative à l'intérieur)."""
    c, a = glass_pose(prop, v)
    r, h = (prop.get("width") or GLASS_WIDTH) / 2, prop.get("height") or GLASS_HEIGHT
    rel = np.asarray(pts, float) - c; along = rel @ a
    dr = np.linalg.norm(rel - np.outer(along, a), axis=1) - r; da = np.abs(along) - h / 2
    return np.hypot(np.maximum(dr, 0), np.maximum(da, 0)) + np.minimum(np.maximum(dr, da), 0)

# ─── Cadrage (même calcul que CameraFraming, GrowtinCore) ───
VIEW_ASPECT = 1.03                                      # largeur / hauteur de la carte du personnage dans l'app
MIN_DISTANCE = 1.0                                      # cadrage resserré : distance minimale de la caméra

def camera_shot(key_positions, joints, yaw, pitch=None, margin=None, aspect=VIEW_ASPECT, fov=30.0):
    """Cadrage de l'app : point visé (repère du personnage, avant rotation de « yaw »), distance de la caméra et
    hauteur de la scène visible à cette distance (pour un aperçu sans perspective).
    key_positions : positions des articulations à chaque image clé ; joints : indices à cadrer, None = corps entier."""
    a = np.radians(yaw); c, s = np.cos(a), np.sin(a)
    Ry = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    pts = np.concatenate([np.asarray(P)[joints] if joints is not None else np.asarray(P) for P in key_positions]) @ Ry.T
    m = 0.2 if margin is None else margin
    lo, hi = pts.min(0) - m, pts.max(0) + m
    if joints is None: lo[1] = 0
    center = (lo + hi) / 2; width, height, depth = hi - lo
    p = np.radians(max(8 if pitch is None else pitch, 6))
    half_v = np.tan(np.radians(fov) / 2); half_h = half_v * aspect
    if joints is not None:
        seen = height * np.cos(p) + depth * np.sin(p); along = depth * np.cos(p) + height * np.sin(p)
        distance = max(max(seen / 2 / half_v, width / 2 / half_h) * 1.06 + along / 2, MIN_DISTANCE)
        target = center
    else:
        distance = max(height / 2 / half_v, width / 2 / half_h) * 1.06 + depth / 2
        target = np.array([center[0], center[1] * 0.95, center[2]])
    return Ry.T @ target, float(distance), float(2 * distance * half_v)

def library_for(lib, body_name):
    """Bibliothèque d'un corps (format 3 : une version par corps ; format 2 : bibliothèque unique)."""
    if "bodies" in lib:
        sub = lib["bodies"][body_name]
        return {"poses": sub["poses"], "motions": sub["motions"]}
    return lib

def body_name_of(npz_path):
    return "female" if "female" in os.path.basename(npz_path) else "male"

def sheet(body, motion_ids, lib, path, size=300, export_mod=None):
    from PIL import Image, ImageDraw
    from export import render, MATERIAL_COLORS
    tiles = []
    if lib.get("referenceHeight"):
        body.offset_scale = body.rig.heads[0][1] / lib["referenceHeight"]
    for mid in motion_ids:
        m = lib["motions"][mid]
        if "clip" in m:
            from mocap import quat_to_matrix
            from PIL import Image as _I, ImageDraw as _D
            clip = m["clip"]; nb = len(clip["bones"]); F = clip["frames"]
            for k in np.linspace(0, len(F) - 1, 6).astype(int):
                loc = {}
                for bi_, bname in enumerate(clip["bones"]):
                    q = np.array(F[k][bi_ * 4: bi_ * 4 + 4])
                    loc[bname] = quat_to_matrix(q / np.linalg.norm(q))
                R, P = body.rig.fk(loc)
                ss = body.sample
                vs, _ = body.rig.skin(body.v[ss], body.n[ss], body.bi[ss], body.bw[ss], R, P)
                P = P + [0, -vs[:, 1].min(), 0]
                v, n = body.rig.skin(body.v, body.n, body.bi, body.bw, R, P)
                cols = [MATERIAL_COLORS[int(x)] for x in body.tri_mat]
                vb = v[: len(body.v)]
                c = vb.mean(0); c[1] = 0.95
                tmp = f"/tmp/_tile_{os.getpid()}.png"
                render(v, n, body.tris, cols, tmp, size=size, yaw=m["camera"]["yaw"], pitch=8, center=c, zoom=1.0)
                im = _I.open(tmp).convert("RGB"); _D.Draw(im).text((6, 6), f"{mid} {k / clip['fps']:.1f}s", fill=(255, 255, 255))
                tiles.append(im)
            continue
        lifts = body.lifts(m, lib["poses"])
        limit = int(os.environ.get("MAXK", 99))
        pick = set(np.linspace(0, len(m["keys"]) - 1, min(limit, len(m["keys"]))).round().astype(int))
        for i, key in enumerate(m["keys"]):
            if i not in pick:
                continue
            p = resolve(key["pose"], lib["poses"])
            v, n = body.pose(p, lift=lifts[i])
            cols = [MATERIAL_COLORS[int(x)] for x in body.tri_mat]
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
    lib = library_for(json.load(open(sys.argv[1])), body_name_of(sys.argv[2])); body = Body(sys.argv[2])
    ids = sys.argv[4].split(",") if len(sys.argv) > 4 else list(lib["motions"])
    sheet(body, ids, lib, sys.argv[3])
