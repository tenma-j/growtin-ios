"""Pipeline complet du mannequin : morphologie MakeHuman → tête lisse → pose debout → régions et tenue → export.

Usage : python3 scripts/mannequin/export.py <makehuman/data> [--preview dossier]
"""
import json, os, struct, sys
import numpy as np
import scipy.sparse as sp

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from makehuman import morph, skeleton, skin, PROFILES, OUT  # noqa: E402
from rig import Rig, axis_angle  # noqa: E402

REGIONS = ["skin", "head", "neck", "shoulders", "chest", "upperBack", "lowerBack", "abs", "biceps", "triceps",
           "forearms", "hands", "glutes", "quads", "hamstrings", "calves", "shins", "feet"]
CLOTHING = ["none", "shorts", "top"]

def adjacency(n, tris):
    i = np.concatenate([tris[:, 0], tris[:, 1], tris[:, 2], tris[:, 1], tris[:, 2], tris[:, 0]])
    j = np.concatenate([tris[:, 1], tris[:, 2], tris[:, 0], tris[:, 0], tris[:, 1], tris[:, 2]])
    A = sp.coo_matrix((np.ones(len(i)), (i, j)), shape=(n, n)).tocsr()
    A.data[:] = 1
    deg = np.asarray(A.sum(1)).ravel()
    return sp.diags(1 / np.maximum(deg, 1)) @ A

def taubin(v, avg, strength, iterations, lam=0.6, mu=-0.63):
    s = strength[:, None]
    for _ in range(iterations):
        v = v + lam * s * (avg @ v - v)
        v = v + mu * s * (avg @ v - v)
    return v

def normals_of(v, tris):
    fn = np.cross(v[tris[:, 1]] - v[tris[:, 0]], v[tris[:, 2]] - v[tris[:, 0]])
    vn = np.zeros_like(v)
    for k in range(3):
        np.add.at(vn, tris[:, k], fn)
    return vn / (np.linalg.norm(vn, axis=1, keepdims=True) + 1e-12)

def shortest_arc(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    axis = np.cross(a, b); s = np.linalg.norm(axis)
    if s < 1e-8:
        return np.array([1.0, 0, 0]), 0.0
    return axis / s, np.degrees(np.arctan2(s, a @ b))

def build(data, sex):
    base, verts, faces, groups = morph(data, PROFILES[sex])
    verts = verts * 0.1
    order, bones, sk, weights_raw = skeleton(data, verts)
    bone_idx, bone_w, W = skin(order, bones, sk, weights_raw, len(verts))
    body = [f for f, g in zip(faces, groups) if g == "body"]
    tris = np.array([t for f in body for t in ([f[0], f[1], f[2]], [f[0], f[2], f[3]])[: len(f) - 2]])
    quad_of = np.array([qi for qi, f in enumerate(body) for _ in range(len(f) - 2)])
    used = np.unique(tris)
    remap = -np.ones(len(verts), int); remap[used] = np.arange(len(used))
    tris = remap[tris]
    v = verts[used].copy(); bone_idx = bone_idx[used]; bone_w = bone_w[used]; W = W[used]
    index = {n: i for i, n in enumerate(order)}
    heads = {n: bones[n]["head"].copy() for n in order}
    tails = {n: bones[n]["tail"].copy() for n in order}
    avg = adjacency(len(v), tris)

    # 1. Tête de mannequin : projetée sur un crâne lisse (ni visage ni oreilles), raccord progressif au cou.
    head_w = W[:, index["head"]]
    h = heads["head"]
    k = 0.93 if sex == "female" else 1.0
    skull = [(np.array([0, h[1] + 0.058 * k, h[2] - 0.004]), np.array([0.071, 0.1, 0.104]) * k),
             (np.array([0, h[1] - 0.004 * k, h[2] + 0.046 * k]), np.array([0.056, 0.068, 0.064]) * k)]
    def skull_sdf(q):
        ds = []
        for c, r in skull:
            z = (q - c) / r
            k0 = np.linalg.norm(z, axis=-1); k1 = np.linalg.norm(z / r, axis=-1)
            ds.append(k0 * (k0 - 1) / np.maximum(k1, 1e-9))
        a, b = ds; kk = 0.025
        hmix = np.clip(0.5 + 0.5 * (b - a) / kk, 0, 1)
        return b * (1 - hmix) + a * hmix - kk * hmix * (1 - hmix)
    centre = np.array([0, h[1] + 0.035 * k, h[2] + 0.0])
    strength = np.clip((head_w - 0.5) / 0.4, 0, 1) * np.clip((v[:, 1] - (h[1] - 0.085 * k)) / 0.035, 0, 1)
    sel = np.where(strength > 0)[0]
    d = v[sel] - centre; d /= np.linalg.norm(d, axis=1, keepdims=True)
    lo, hi = np.zeros(len(sel)), np.full(len(sel), 0.3)
    for _ in range(40):
        mid = (lo + hi) / 2
        inside = skull_sdf(centre + d * mid[:, None]) < 0
        lo = np.where(inside, mid, lo); hi = np.where(inside, hi, mid)
    target = centre + d * ((lo + hi) / 2)[:, None]
    v[sel] = v[sel] + strength[sel, None] * (target - v[sel])
    v = taubin(v, avg, np.clip(strength * 1.5, 0, 1) * (strength < 0.98), 15)
    # Faces internes repliées par la projection (bouche, paupières, oreilles) : supprimées.
    fn = np.cross(v[tris[:, 1]] - v[tris[:, 0]], v[tris[:, 2]] - v[tris[:, 0]])
    radial = v[tris].mean(1) - centre
    area = np.linalg.norm(fn, axis=1)
    in_head = strength[tris].min(1) > 0.9
    inverted = in_head & ((fn * radial).sum(1) <= 0)
    tris[inverted] = tris[inverted][:, ::-1]                  # repliées vers l'extérieur : elles comblent les fentes
    keep = area > 1e-12
    tris, quad_of = tris[keep], quad_of[keep]
    # 2. Pose debout : bras le long du corps, paumes vers les cuisses.
    rig = Rig(order, {n: bones[n]["parent"] for n in order}, heads)
    local = {}
    for side, sgn in ((".L", 1), (".R", -1)):
        sh, el, wr = heads["upperarm01" + side], heads["lowerarm01" + side], heads["wrist" + side]
        target = np.array([sgn * np.sin(np.radians(7)), -np.cos(np.radians(7)), -0.02])
        ax, ang = shortest_arc(el - sh, target)
        rig.world_rotate(local, "upperarm01" + side, ax, ang)
        R, P = rig.fk(local)
        fore = P[index["wrist" + side]] - P[index["lowerarm01" + side]]
        upper = P[index["lowerarm01" + side]] - P[index["upperarm01" + side]]
        want = axis_angle([1, 0, 0], -8) @ (upper / np.linalg.norm(upper))
        ax, ang = shortest_arc(fore, want)
        rig.world_rotate(local, "lowerarm01" + side, ax, ang)
        R, P = rig.fk(local)
        hand = P[index["finger3-1" + side]] - P[index["wrist" + side]]
        fore = P[index["wrist" + side]] - P[index["lowerarm01" + side]]
        ax, ang = shortest_arc(hand, fore)
        rig.world_rotate(local, "wrist" + side, ax, ang)
        # Paume tournée vers la cuisse : rotation autour de l'axe de l'avant-bras.
        R, P = rig.fk(local)
        pv, _ = rig.skin(v, normals_of(v, tris), bone_idx, bone_w, R, P)
        palm_idx = np.where(W[:, index["wrist" + side]] > 0.6)[0]
        across = P[index["finger2-1" + side]] - P[index["finger5-1" + side]]   # de l'auriculaire vers l'index
        axis = fore / np.linalg.norm(fore)
        across -= axis * (across @ axis)
        want = np.array([0, 0, 1.0])                                           # index vers l'avant
        want -= axis * (want @ axis)
        a = np.degrees(np.arctan2(np.cross(across, want) @ axis, across @ want)) if np.linalg.norm(across) > 1e-6 else 0
        rig.world_rotate(local, "lowerarm02" + side, axis, a * 0.6)
        rig.world_rotate(local, "wrist" + side, axis, a * 0.4)
    R, P = rig.fk(local)
    n0 = normals_of(v, tris)
    v, _ = rig.skin(v, n0, bone_idx, bone_w, R, P)
    newheads = {n: P[index[n]] for n in order}
    newtails = {n: P[index[n]] + R[index[n]] @ (tails[n] - heads[n]) for n in order}
    # Sol à y = 0, personnage centré.
    ground = v[:, 1].min()
    shift = np.array([-0.0, -ground, -np.median(v[:, 2])])
    v += shift
    newheads = {n: p + shift for n, p in newheads.items()}
    newtails = {n: p + shift for n, p in newtails.items()}
    nrm = normals_of(v, tris)

    # 3. Régions musculaires.
    R_ = {r: i for i, r in enumerate(REGIONS)}
    hipy = newheads["upperleg01.L"][1]
    def limb(c, a, b2):
        """Position le long du membre (0 → 1) et angle autour de lui (0° = devant, ±180° = derrière)."""
        ax = b2 - a; L2 = ax @ ax; t = (c - a) @ ax / L2
        r = c - (a + t * ax); fwd = np.array([0, 0, 1.0]) - ax * (ax[2] / L2)
        side = np.cross(ax / np.sqrt(L2), fwd / np.linalg.norm(fwd))
        return t, np.degrees(np.arctan2(r @ side, r @ fwd))
    def label(b, n, c):
        nz, ny = n[2], n[1]
        sd = b[-2:] if b[-2:] in (".L", ".R") else ""
        if b.startswith("upperleg"):
            t, phi = limb(c, newheads["upperleg01" + sd], newheads["lowerleg01" + sd])
            if abs(phi) > 125 and t < 0.22:
                return R_["glutes"]
            return R_["hamstrings"] if abs(phi) > 105 else R_["quads"]
        if b.startswith("lowerleg"):
            t, phi = limb(c, newheads["lowerleg01" + sd], newheads["foot" + sd])
            return R_["calves"] if abs(phi) > 70 else R_["shins"]
        if b.startswith("upperarm02"):
            t, phi = limb(c, newheads["upperarm02" + sd], newheads["lowerarm01" + sd])
            return R_["biceps"] if abs(phi) < 90 else R_["triceps"]
        if b == "head":
            return R_["head"]
        if b.startswith("neck"):
            return R_["neck"]
        if b.startswith("clavicle") or b.startswith("shoulder01"):
            return R_["upperBack"] if nz < -0.15 or ny > 0.6 else R_["shoulders"]
        if b.startswith("upperarm01"):
            return R_["shoulders"]
        if b.startswith("upperarm02"):
            return R_["biceps"] if nz > -0.05 else R_["triceps"]
        if b.startswith("lowerarm"):
            return R_["forearms"]
        if b.startswith(("wrist", "finger", "metacarpal")):
            return R_["hands"]
        if b in ("spine01", "spine02"):
            if nz < -0.1:
                return R_["upperBack"]
            return R_["chest"] if (nz > 0.25 or c[1] > newheads["spine02"][1] + 0.06) else R_["abs"]
        if b in ("spine03", "spine04", "spine05"):
            return R_["lowerBack"] if nz < -0.25 else R_["abs"]
        if b == "root" or b.startswith("pelvis"):
            return R_["glutes"] if nz < -0.05 else R_["abs"]
        if b.startswith("upperleg"):
            if nz < -0.3 and c[1] > hipy - 0.17:
                return R_["glutes"]
            return R_["hamstrings"] if nz < -0.2 else R_["quads"]
        if b.startswith("lowerleg"):
            return R_["calves"] if nz < 0.25 else R_["shins"]
        if b.startswith(("foot", "toes")):
            return R_["feet"]
        return R_["skin"]
    # Étiquette par face d'origine (quad) : bords alignés sur les lignes du maillage.
    nq = quad_of.max() + 1
    fn = np.cross(v[tris[:, 1]] - v[tris[:, 0]], v[tris[:, 2]] - v[tris[:, 0]])
    qn = np.zeros((nq, 3)); np.add.at(qn, quad_of, fn); qn /= np.linalg.norm(qn, axis=1, keepdims=True) + 1e-12
    qc = np.zeros((nq, 3)); cnt = np.zeros(nq); np.add.at(qc, quad_of, v[tris].mean(1)); np.add.at(cnt, quad_of, 1); qc /= np.maximum(cnt, 1)[:, None]
    qW = np.zeros((nq, W.shape[1])); np.add.at(qW, quad_of, W[tris].mean(1))
    qdom = np.array(order)[np.argmax(qW, axis=1)]
    qlab = np.zeros(nq, int)
    for q in range(nq):
        qlab[q] = label(qdom[q], qn[q], qc[q])
    # Voisinage des quads (arêtes partagées) pour lisser les étiquettes.
    edge_quads = {}
    for t, q in zip(tris, quad_of):
        for e in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            edge_quads.setdefault((min(e), max(e)), set()).add(q)
    neigh = [set() for _ in range(nq)]
    for qs in edge_quads.values():
        for q in qs:
            neigh[q] |= qs
    def majority(lab, passes=2, protect=()):
        lab = lab.copy()
        for _ in range(passes):
            new = lab.copy()
            for q in range(nq):
                if lab[q] in protect:
                    continue
                vals = [lab[x] for x in neigh[q]]
                best = max(set(vals), key=vals.count)
                if vals.count(best) > vals.count(lab[q]):
                    new[q] = best
            lab = new
        return lab
    qlab = majority(qlab, protect={R_["head"], R_["hands"], R_["feet"]})
    tri_lab = qlab[quad_of]
    # 4. Tenue : short (et brassière pour la version femme), par face d'origine.
    knee_y = newheads["lowerleg01.L"][1]
    waist_y = newheads["spine04"][1] + (0.0 if sex == "male" else -0.01)
    hem_y = knee_y + 0.62 * (hipy - knee_y)
    arm_bones = ("upperarm", "lowerarm", "wrist", "finger", "metacarpal")
    qarm = np.array([b.startswith(arm_bones) for b in qdom])
    qcloth = np.zeros(nq, int)
    for q in range(nq):
        b = qdom[q]
        if qarm[q]:
            continue
        sd = b[-2:] if b[-2:] in (".L", ".R") else ""
        if b.startswith("upperleg"):
            t, _ = limb(qc[q], newheads["upperleg01" + sd], newheads["lowerleg01" + sd])
            qcloth[q] = 1 if t < 0.42 else 0
        elif b in ("root", "pelvis.L", "pelvis.R", "spine05") or (b == "spine04" and qc[q][1] < waist_y):
            qcloth[q] = 1 if qc[q][1] < waist_y else 0
    if sex == "female":
        chest = (np.abs(v[:, 0]) > 0.04) & (np.abs(v[:, 0]) < 0.13) & (v[:, 1] > newheads["spine02"][1]) & (v[:, 1] < newheads["neck01"][1])
        apex = v[chest][np.argmax(v[chest][:, 2])]
        top = (qc[:, 1] > apex[1] - 0.085) & (qc[:, 1] < apex[1] + 0.07) & ~qarm & (qlab != R_["shoulders"]) \
              & np.isin(qdom, ["spine01", "spine02", "spine03"])
        qcloth[top] = 2
    qcloth = majority(qcloth, passes=3)
    tri_cloth = qcloth[quad_of]
    # Attributs par sommet : deux régions dominantes parmi les faces voisines, mélange et part de tissu.
    nv = len(v)
    counts = np.zeros((nv, len(REGIONS)))
    fab = np.zeros(nv); inc = np.zeros(nv)
    for t, q in zip(tris, quad_of):
        for k in t:
            counts[k, qlab[q]] += 1
            fab[k] += qcloth[q] > 0; inc[k] += 1
    order2 = np.argsort(-counts, axis=1)
    ra, rb = order2[:, 0], order2[:, 1]
    ca = np.take_along_axis(counts, ra[:, None], 1)[:, 0]; cb = np.take_along_axis(counts, rb[:, None], 1)[:, 0]
    rb = np.where(cb > 0, rb, ra)
    blend = np.where(cb > 0, cb / np.maximum(ca + cb, 1), 0)
    attr = np.stack([ra, rb, np.round(blend * 255), np.round(fab / np.maximum(inc, 1) * 255)], 1).astype(np.uint8)
    return dict(order=order, parents={n: bones[n]["parent"] for n in order}, heads=newheads, tails=newtails, attr=attr,
                v=v.astype(np.float32), n=nrm.astype(np.float32), tris=tris, bone_idx=bone_idx, bone_w=bone_w,
                tri_lab=tri_lab, tri_cloth=tri_cloth)

def export(sex, b):
    os.makedirs(OUT, exist_ok=True)
    idx = b["tris"].astype("<u4").ravel()
    n = len(b["v"])
    with open(os.path.join(OUT, f"mannequin-{sex}.bin"), "wb") as fh:
        fh.write(struct.pack("<4sII", b"GTM3", n, len(idx)))
        fh.write(b["v"].astype("<f4").tobytes())
        fh.write(b["n"].astype("<f4").tobytes())
        fh.write(b["bone_idx"].astype("<u2").tobytes())
        fh.write(b["bone_w"].astype("<f4").tobytes())
        fh.write(b["attr"].astype(np.uint8).tobytes())
        fh.write(idx.tobytes())
    return {
        "joints": [{"name": k, "parent": b["parents"][k], "head": [round(float(x), 5) for x in b["heads"][k]],
                    "tail": [round(float(x), 5) for x in b["tails"][k]]} for k in b["order"]],
        "vertexCount": n, "indexCount": int(len(idx)),
    }

def render(v, n, tris, colors, path, size=640, yaw=20, pitch=0, center=None, zoom=1.0):
    """Aperçu logiciel : z-buffer, lumière principale, d'appoint et liseré bleuté."""
    from PIL import Image
    a, p = np.radians(yaw), np.radians(pitch)
    Ry = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    Rx = np.array([[1, 0, 0], [0, np.cos(p), -np.sin(p)], [0, np.sin(p), np.cos(p)]])
    M = Rx @ Ry
    c = np.asarray(center if center is not None else [0, 0.9, 0])
    pv = (v - c) @ M.T; pn = n @ M.T
    scale = size / 2.1 * zoom
    px = pv[:, 0] * scale + size / 2; py = size / 2 - pv[:, 1] * scale
    zbuf = np.full((size, size), -1e9); img = np.zeros((size, size, 3)) + 0.06
    light = np.array([-0.45, 0.6, 0.65]); light /= np.linalg.norm(light)
    fill = np.array([0.7, 0.1, 0.4]); fill /= np.linalg.norm(fill)
    order = np.argsort(pv[tris].mean(1)[:, 2])
    for t in order:
        tri = tris[t]
        xs, ys, zs = px[tri], py[tri], pv[tri, 2]
        x0, x1 = int(max(xs.min(), 0)), int(min(xs.max() + 1, size)); y0, y1 = int(max(ys.min(), 0)), int(min(ys.max() + 1, size))
        if x0 >= x1 or y0 >= y1: continue
        gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-12: continue
        w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
        w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
        sub = zbuf[y0:y1, x0:x1]
        upd = inside & (z > sub)
        if not upd.any(): continue
        nn = w0[..., None] * pn[tri[0]] + w1[..., None] * pn[tri[1]] + w2[..., None] * pn[tri[2]]
        nn /= np.linalg.norm(nn, axis=-1, keepdims=True) + 1e-9
        col = np.asarray(colors[t])
        diff = np.clip(nn @ light, 0, 1)[..., None]; fl = np.clip(nn @ fill, 0, 1)[..., None]
        spec = np.clip(nn @ ((light + [0, 0, 1]) / np.linalg.norm(light + [0, 0, 1])), 0, 1)[..., None] ** 30
        rim = (1 - np.clip(nn[..., 2], 0, 1))[..., None] ** 3
        cc = col * (0.16 + 0.68 * diff + 0.22 * fl) + spec * 0.18 + rim * np.array([0.5, 0.65, 1.0]) * 0.45
        sub[upd] = z[upd]
        img[y0:y1, x0:x1][upd] = np.clip(cc[upd], 0, 1)
    Image.fromarray((img * 255).astype(np.uint8)).save(path)

def colors_for(b, highlight=()):
    skin = np.array([0.80, 0.81, 0.83]); fabric = np.array([0.13, 0.13, 0.15]); hi = np.array([0.98, 0.45, 0.12])
    out = []
    for r, c in zip(b["tri_lab"], b["tri_cloth"]):
        if REGIONS[r] in highlight:
            out.append(fabric * 0.7 + hi * 0.3 if c else hi)
        else:
            out.append(fabric if c else skin)
    return out

if __name__ == "__main__":
    data = sys.argv[1]
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    meta = {"source": "MakeHuman (https://github.com/makehumancommunity/makehuman), ressources CC0 1.0",
            "regions": REGIONS, "clothing": CLOTHING, "bodies": {}}
    for sex in ("male", "female"):
        b = build(data, sex)
        meta["bodies"][sex] = export(sex, b)
        print(sex, len(b["v"]), "sommets", len(b["tris"]), "triangles", "hauteur", round(float(b["v"][:, 1].max()), 3))
        if preview:
            np.savez(f"{preview}/{sex}.npz", **{k: b[k] for k in ("v", "n", "tris", "bone_idx", "bone_w", "tri_lab", "tri_cloth", "attr")},
                     order=np.array(b["order"]), heads=np.array([b["heads"][k] for k in b["order"]]),
                     parents=np.array([b["parents"][k] or "" for k in b["order"]]))
            render(b["v"], b["n"], b["tris"], colors_for(b, {"quads", "calves"}), f"{preview}/{sex}-front.png", yaw=25)
            render(b["v"], b["n"], b["tris"], colors_for(b), f"{preview}/{sex}-back.png", yaw=160)
            render(b["v"], b["n"], b["tris"], colors_for(b), f"{preview}/{sex}-head.png", yaw=35, center=b["heads"]["head"] + [0, 0.08, 0], zoom=5)
    json.dump(meta, open(os.path.join(OUT, "mannequin.json"), "w"), indent=1)
