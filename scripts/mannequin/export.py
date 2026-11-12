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
        # Mains détendues : doigts rapprochés et légèrement fléchis, pouce tourné vers la paume.
        palm = np.array([-sgn, 0.0, 0.0])                 # côté paume (vers la cuisse)
        def bone_dir(name):
            R_, P_ = rig.fk(local)
            i = index[name]
            d = R_[i] @ (tails[name] - heads[name])
            return d / (np.linalg.norm(d) + 1e-12)
        middle = bone_dir("finger3-1" + side)
        for f in (2, 4, 5):
            d = bone_dir(f"finger{f}-1" + side)
            dp = d - palm * (d @ palm); mp = middle - palm * (middle @ palm)
            ang = np.degrees(np.arctan2(np.cross(dp, mp) @ palm, dp @ mp))
            rig.world_rotate(local, f"finger{f}-1" + side, palm, 0.7 * ang)
        for f in (2, 3, 4, 5):
            for p_, curl in ((1, 10), (2, 22), (3, 16)):
                name = f"finger{f}-{p_}" + side
                d = bone_dir(name)
                ax = np.cross(d, palm)
                if np.linalg.norm(ax) > 1e-6:
                    rig.world_rotate(local, name, ax / np.linalg.norm(ax), curl)
        for p_, curl in ((1, 14), (2, 12), (3, 10)):
            name = f"finger1-{p_}" + side
            d = bone_dir(name)
            ax = np.cross(d, palm)
            if np.linalg.norm(ax) > 1e-6:
                rig.world_rotate(local, name, ax / np.linalg.norm(ax), curl)
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

    nrm = normals_of(v, tris)

    # 3. Vêtements : coques séparées, découpées le long de lignes lisses, portées par les mêmes os.
    names_arr = np.array(order)
    def wsum(prefixes):
        cols = [i for i, nme in enumerate(order) if nme.startswith(prefixes)]
        return W[:, cols].sum(1)
    w_arm = wsum(("upperarm", "lowerarm", "wrist", "finger", "metacarpal"))
    w_shoulder = wsum(("clavicle", "shoulder01"))
    w_leg_low = wsum(("lowerleg", "foot", "toes"))
    def thigh_t(side):
        a_, b2 = newheads["upperleg01" + side], newheads["lowerleg01" + side]
        ax = b2 - a_
        return (v - a_) @ ax / (ax @ ax), np.linalg.norm(ax)
    tL, lenL = thigh_t(".L"); tR, lenR = thigh_t(".R")
    t_side = np.where(v[:, 0] >= 0, tL, tR); thigh_len = (lenL + lenR) / 2
    waist_y = newheads["spine04"][1] + (0.005 if sex == "male" else -0.005)
    leg_cut = 0.40 if sex == "male" else 0.30
    f_shorts = np.minimum.reduce([(leg_cut - t_side) * thigh_len, waist_y - v[:, 1], (0.5 - w_arm) * 0.1, (0.5 - w_leg_low) * 0.1])
    f_band = np.minimum(f_shorts, v[:, 1] - (waist_y - 0.036))
    garments = [(f_shorts, 0.0045, 1), (f_band, 0.0075, 2)]
    if sex == "female":
        chest = (np.abs(v[:, 0]) > 0.04) & (np.abs(v[:, 0]) < 0.13) & (v[:, 1] > newheads["spine02"][1]) & (v[:, 1] < newheads["neck01"][1])
        apex = v[chest][np.argmax(v[chest][:, 2])]
        lo, hi = apex[1] - 0.09, apex[1] + 0.07
        f_band_top = np.minimum.reduce([v[:, 1] - lo, hi - v[:, 1], (0.3 - w_arm - w_shoulder) * 0.1])
        # Bretelles : deux bandes qui passent sur les épaules, de l'avant vers le dos.
        sx = 0.5 * (abs(newheads["clavicle.L"][0]) + abs(newheads["upperarm01.L"][0])) - 0.012
        w_head = wsum(("head", "neck"))
        f_straps = np.minimum.reduce([0.016 - np.abs(np.abs(v[:, 0]) - sx), v[:, 1] - (hi - 0.02), (0.4 - w_arm) * 0.1,
                                      (0.65 - w_head) * 0.1, newheads["neck01"][1] + 0.14 - v[:, 1]])
        f_top = np.maximum(f_band_top, f_straps)
        f_top_band = np.minimum(f_top, (lo + 0.026) - v[:, 1])
        garments += [(f_top, 0.004, 1), (f_top_band, 0.0065, 2)]
    shells = []
    for f, off, mat in garments:
        cv, cn, ct, cbi, cbw = clip_mesh(v, nrm, tris, bone_idx, bone_w, f)
        if len(ct):
            shells.append(make_shell(cv, cn, ct, cbi, cbw, off, mat))
    return dict(order=order, parents={n: bones[n]["parent"] for n in order}, heads=newheads, tails=newtails,
                v=v.astype(np.float32), n=nrm.astype(np.float32), tris=tris, bone_idx=bone_idx, bone_w=bone_w, shells=shells)

def clip_mesh(v, n, tris, bi, bw, f):
    """Garde la partie du maillage où f ≥ 0, en coupant les triangles le long de la ligne f = 0."""
    keep_v = {}
    P, N, BI, BW, T = [], [], [], [], []
    def vert(i):
        if i not in keep_v:
            keep_v[i] = len(P); P.append(v[i]); N.append(n[i]); BI.append(bi[i]); BW.append(bw[i])
        return keep_v[i]
    cut = {}
    def edge(i, j):
        key = (min(i, j), max(i, j))
        if key not in cut:
            t = f[i] / (f[i] - f[j])
            p = v[i] + t * (v[j] - v[i]); nn = n[i] + t * (n[j] - n[i]); nn /= np.linalg.norm(nn) + 1e-12
            w = {}
            for b_, x in zip(bi[i], bw[i] * (1 - t)): w[b_] = w.get(b_, 0) + x
            for b_, x in zip(bi[j], bw[j] * t): w[b_] = w.get(b_, 0) + x
            top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
            tot = sum(x for _, x in top) or 1
            bix = np.zeros(4, np.uint16); bwx = np.zeros(4, np.float32)
            for k, (b_, x) in enumerate(top): bix[k] = b_; bwx[k] = x / tot
            cut[key] = len(P); P.append(p); N.append(nn); BI.append(bix); BW.append(bwx)
        return cut[key]
    for t in tris:
        s_ = f[t] >= 0
        if s_.all():
            T.append([vert(t[0]), vert(t[1]), vert(t[2])])
        elif s_.any():
            # rotation pour que le cas soit (in, out, out) ou (in, in, out)
            for r in range(3):
                a_, b_, c_ = t[r], t[(r + 1) % 3], t[(r + 2) % 3]
                ia, ib, ic = f[a_] >= 0, f[b_] >= 0, f[c_] >= 0
                if ia and not ib and not ic:
                    T.append([vert(a_), edge(a_, b_), edge(a_, c_)]); break
                if ia and ib and not ic:
                    e1, e2 = edge(b_, c_), edge(a_, c_)
                    T.append([vert(a_), vert(b_), e1]); T.append([vert(a_), e1, e2]); break
    return (np.array(P), np.array(N), np.array(T, int).reshape(-1, 3), np.array(BI, np.uint16).reshape(-1, 4),
            np.array(BW, np.float32).reshape(-1, 4))

def make_shell(v, n, tris, bi, bw, offset, material):
    """Coque de vêtement : surface décalée le long des normales, plus un ourlet qui rejoint la peau."""
    outer = v + n * offset
    edges = {}
    for t in tris:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            key = (min(a, b), max(a, b))
            edges.setdefault(key, []).append((a, b))
    boundary = [e[0] for e in edges.values() if len(e) == 1]
    nv = len(v)
    P = [outer]; NN = [normals_of(outer, tris)]; BI = [bi]; BW = [bw]; F = [tris]
    hp, hn, hbi, hbw, hf = [], [], [], [], []
    for a, b in boundary:
        k = nv + len(hp)
        pts = [outer[a], outer[b], v[b] - n[b] * 0.0008, v[a] - n[a] * 0.0008]
        e = pts[1] - pts[0]; inward = pts[3] - pts[0]
        nrm_ = np.cross(e, inward); nrm_ /= np.linalg.norm(nrm_) + 1e-12
        # même sens de parcours que le triangle d'origine : l'extérieur de la coque est à droite de a→b
        tri_n = n[a] + n[b]
        out_dir = np.cross(e, tri_n)
        if nrm_ @ out_dir < 0:
            nrm_ = -nrm_; hf += [[k, k + 1, k + 2], [k, k + 2, k + 3]]
        else:
            hf += [[k, k + 2, k + 1], [k, k + 3, k + 2]]
        hp += pts; hn += [nrm_] * 4; hbi += [bi[a], bi[b], bi[b], bi[a]]; hbw += [bw[a], bw[b], bw[b], bw[a]]
    if hp:
        P.append(np.array(hp)); NN.append(np.array(hn)); BI.append(np.array(hbi)); BW.append(np.array(hbw)); F.append(np.array(hf))
    return dict(v=np.vstack(P).astype(np.float32), n=np.vstack(NN).astype(np.float32), tris=np.vstack(F),
                bi=np.vstack(BI).astype(np.uint16), bw=np.vstack(BW).astype(np.float32), material=material)

def export(sex, b):
    """Format GTM4 : plusieurs maillages (corps puis vêtements), chacun avec son matériau et ses poids."""
    os.makedirs(OUT, exist_ok=True)
    meshes = [dict(v=b["v"], n=b["n"], tris=b["tris"], bi=b["bone_idx"], bw=b["bone_w"], material=0)]
    for sh in b["shells"]:
        meshes.append(dict(v=sh["v"], n=sh["n"], tris=sh["tris"], bi=sh["bi"], bw=sh["bw"], material=sh["material"]))
    with open(os.path.join(OUT, f"mannequin-{sex}.bin"), "wb") as fh:
        fh.write(struct.pack("<4sI", b"GTM4", len(meshes)))
        for m in meshes:
            idx = m["tris"].astype("<u4").ravel()
            fh.write(struct.pack("<III", m["material"], len(m["v"]), len(idx)))
            fh.write(m["v"].astype("<f4").tobytes()); fh.write(m["n"].astype("<f4").tobytes())
            fh.write(m["bi"].astype("<u2").tobytes()); fh.write(m["bw"].astype("<f4").tobytes())
            fh.write(idx.tobytes())
    return {
        "joints": [{"name": k, "parent": b["parents"][k], "head": [round(float(x), 5) for x in b["heads"][k]],
                    "tail": [round(float(x), 5) for x in b["tails"][k]]} for k in b["order"]],
        "meshes": [{"material": m["material"], "vertexCount": len(m["v"]), "indexCount": int(m["tris"].size)} for m in meshes],
    }, meshes

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

MATERIAL_COLORS = {0: np.array([0.80, 0.80, 0.79]), 1: np.array([0.17, 0.18, 0.20]), 2: np.array([0.10, 0.55, 0.33])}

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
            "materials": ["skin", "fabric", "accent"], "bodies": {}}
    for sex in ("male", "female"):
        b = build(data, sex)
        info, meshes = export(sex, b)
        meta["bodies"][sex] = info
        print(sex, [(m["material"], len(m["v"]), len(m["tris"])) for m in meshes], "hauteur", round(float(b["v"][:, 1].max()), 3))
        if preview:
            V, Nn, T, BI, BW, M = [], [], [], [], [], []
            off = 0
            for m in meshes:
                V.append(m["v"]); Nn.append(m["n"]); T.append(m["tris"] + off); BI.append(m["bi"]); BW.append(m["bw"])
                M.append(np.full(len(m["tris"]), m["material"])); off += len(m["v"])
            V, Nn, T, BI, BW, M = map(np.concatenate, (V, Nn, T, BI, BW, M))
            np.savez(f"{preview}/{sex}.npz", v=V, n=Nn, tris=T, bone_idx=BI, bone_w=BW, tri_mat=M, body_count=len(meshes[0]["v"]),
                     order=np.array(b["order"]), heads=np.array([b["heads"][k] for k in b["order"]]),
                     parents=np.array([b["parents"][k] or "" for k in b["order"]]))
            cols = [MATERIAL_COLORS[int(x)] for x in M]
            render(V, Nn, T, cols, f"{preview}/{sex}-front.png", yaw=25)
            render(V, Nn, T, cols, f"{preview}/{sex}-back.png", yaw=160)
            render(V, Nn, T, cols, f"{preview}/{sex}-hand.png", yaw=60, center=b["heads"]["wrist.L"] + [0, -0.08, 0], zoom=8)
    json.dump(meta, open(os.path.join(OUT, "mannequin.json"), "w"), indent=1)
