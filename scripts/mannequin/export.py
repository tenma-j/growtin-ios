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

def smooth_weights(W, avg, order, iterations=8, lam=0.5):
    """Lisse les poids dans les zones de transition entre os (sauf mains et tête), puis garde les 4 plus forts."""
    def cols(prefixes):
        return [i for i, n in enumerate(order) if n.startswith(prefixes)]
    hands = W[:, cols(("wrist", "finger"))].sum(1)
    head = W[:, cols(("head", "neck"))].sum(1)
    blended = W.max(1) < 0.97
    mask = blended & (hands < 0.3) & (head < 0.5)
    # une couronne de plus autour des zones mélangées
    grow = (avg @ mask.astype(float)) > 0
    mask = (mask | grow) & (hands < 0.3) & (head < 0.5)
    m = mask[:, None].astype(float)
    Ws = W.copy()
    for _ in range(iterations):
        Ws = Ws + lam * m * (avg @ Ws - Ws)
    top = np.argsort(-Ws, axis=1)[:, :4]
    tw = np.take_along_axis(Ws, top, 1)
    tw = np.clip(tw, 0, None); s = tw.sum(1, keepdims=True)
    tw = tw / np.maximum(s, 1e-9)
    return top.astype(np.uint16), tw.astype(np.float32)

# Articulations d'appoint : (os doublé, os du côté parent dont la peau se mélange à la sienne dans la pliure).
HALF_JOINTS = []
for _s in (".L", ".R"):
    HALF_JOINTS += [
        ("upperarm01" + _s, ["spine01", "spine02", "spine03", "clavicle" + _s, "shoulder01" + _s, "neck01"]),
        ("lowerarm01" + _s, ["upperarm01" + _s, "upperarm02" + _s]),
        ("upperleg01" + _s, ["pelvis" + _s, "spine05", "spine04", "spine03", "root"]),
        ("lowerleg01" + _s, ["upperleg01" + _s, "upperleg02" + _s]),
    ]

def half_joint_name(bone):
    base, side = bone.rsplit(".", 1)
    return f"{base}-half.{side}"

def add_half_joints(order, parents, bone_idx, bone_w):
    """Articulations d'appoint à mi-rotation : épaules, coudes, hanches, genoux.

    Dans une pliure, un sommet partagé entre deux os prend la moyenne de deux positions (skinning linéaire) :
    la pliure se pince et forme un angle vif. L'appoint, placé au même point que l'os, tourne de la moitié de
    son angle ; la part de chaque sommet est répartie entre le parent, l'appoint et l'os, si bien qu'aucun
    mélange ne dépasse la moitié de l'angle : la pliure reste arrondie et garde son volume.
    Renvoie (noms, parents, appoints {appoint: os}, indices, poids)."""
    names = list(order); parents = dict(parents)
    children = {}
    for n in names:
        children.setdefault(parents[n], []).append(n)
    def subtree(n):
        out = [n]
        for c in children.get(n, []):
            out += subtree(c)
        return out
    index = {n: i for i, n in enumerate(names)}
    nb = len(names)
    W = np.zeros((len(bone_idx), nb + len(HALF_JOINTS)))
    for k in range(bone_idx.shape[1]):
        np.add.at(W, (np.arange(len(bone_idx)), bone_idx[:, k].astype(int)), bone_w[:, k])
    halves = {}
    for j, (bone, parent_side) in enumerate(HALF_JOINTS):
        h = nb + j
        name = half_joint_name(bone)
        names.append(name); parents[name] = parents[bone]; halves[name] = bone
        child = [index[n] for n in subtree(bone)]
        par = [index[n] for n in parent_side if n in index]
        a = W[:, par].sum(1); b = W[:, child].sum(1); t = a + b
        mixed = (a > 1e-4) & (b > 1e-4)
        f = np.where(mixed, b / np.maximum(t, 1e-9), 0.0)        # part de l'os : 0 côté parent, 1 côté os
        lo = mixed & (f <= 0.5); hi = mixed & (f > 0.5)
        sa = np.ones(len(W)); sb = np.ones(len(W)); wh = np.zeros(len(W))
        sa[lo] = t[lo] * (1 - 2 * f[lo]) / a[lo]; sb[lo] = 0; wh[lo] = t[lo] * 2 * f[lo]
        sa[hi] = 0; sb[hi] = t[hi] * (2 * f[hi] - 1) / b[hi]; wh[hi] = t[hi] * (2 - 2 * f[hi])
        W[:, par] *= sa[:, None]; W[:, child] *= sb[:, None]; W[:, h] += wh
    top = np.argsort(-W, axis=1)[:, :4]
    tw = np.take_along_axis(W, top, 1)
    tw = tw / np.maximum(tw.sum(1, keepdims=True), 1e-9)
    return names, parents, halves, top.astype(np.uint16), tw.astype(np.float32)

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
    # 1 bis. Poids lissés dans les zones de pliure (épaules, hanches, coudes, genoux) : plis arrondis au lieu d'angles vifs.
    bone_idx, bone_w = smooth_weights(W, avg, order)
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
    # 2 bis. Articulations d'appoint aux pliures (la pose debout devient la pose de référence : elles y sont neutres).
    parents = {n: bones[n]["parent"] for n in order}
    order, parents, halves, bone_idx, bone_w = add_half_joints(order, parents, bone_idx, bone_w)
    for name, bone in halves.items():
        newheads[name] = newheads[bone].copy(); newtails[name] = newtails[bone].copy()

    # 3. Vêtements : coques séparées, découpées le long de lignes lisses, portées par les mêmes os.
    names_arr = np.array(order)
    def wsum(prefixes):
        # poids d'origine (sans les articulations d'appoint) : zones du corps pour dessiner la tenue
        cols = [i for i, nme in enumerate(order) if nme.startswith(prefixes) and i < W.shape[1]]
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
    cloth_fields, trim_fields = [f_shorts], [f_band]
    if sex == "female":
        chest = (np.abs(v[:, 0]) > 0.04) & (np.abs(v[:, 0]) < 0.13) & (v[:, 1] > newheads["spine02"][1]) & (v[:, 1] < newheads["neck01"][1])
        apex = v[chest][np.argmax(v[chest][:, 2])]
        lo, hi = apex[1] - 0.09, apex[1] + 0.07
        def smoothstep(a, b, x):
            t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)
        def smax(a, b, k):
            h = np.maximum(k - np.abs(a - b), 0) / k
            return np.maximum(a, b) + h * h * k / 4
        # Brassière de sport : décolleté arrondi devant, dos droit, bretelles croisées en dos nageur,
        # jonctions arrondies (union douce des champs).
        sx = 0.5 * (abs(newheads["clavicle.L"][0]) + abs(newheads["upperarm01.L"][0])) - 0.012
        z_mid = newheads["spine02"][2] + 0.05
        front = smoothstep(z_mid - 0.05, z_mid + 0.05, v[:, 2])
        neckline = (apex[1] + 0.025) + (hi + 0.01 - apex[1] - 0.025) * np.clip(np.abs(v[:, 0]) / sx, 0, 1.4) ** 2
        top_edge = front * neckline + (1 - front) * (hi - 0.015)
        f_body = np.minimum.reduce([v[:, 1] - lo, top_edge - v[:, 1], (0.3 - w_arm - w_shoulder) * 0.1])
        shoulder_top = newheads["upperarm01.L"][1] + 0.05
        racer = 0.035 + (sx - 0.035) * smoothstep(hi - 0.04, shoulder_top, v[:, 1])      # dos nageur : les bretelles se rejoignent
        centre = front * sx + (1 - front) * racer
        w_head = wsum(("head", "neck"))
        # bornes purement géométriques (des bords nets, pas des poids d'os bruités)
        f_straps = np.minimum.reduce([0.018 - np.abs(np.abs(v[:, 0]) - centre), v[:, 1] - (lo + 0.04),
                                      (shoulder_top + 0.10) - v[:, 1]])
        f_top = smax(f_body, f_straps, 0.012)
        f_top_band = np.minimum(f_top, (lo + 0.026) - v[:, 1])
        cloth_fields.append(f_top); trim_fields.append(f_top_band)
    # Le tissu fait partie de la surface du corps : la peau est découpée le long des lignes du vêtement
    # (courbes nettes), la zone de tissu est légèrement gonflée et lissée (sans relief du corps dessous).
    # Une seule surface : rien ne peut passer à travers le vêtement.
    f_cloth = np.maximum.reduce(cloth_fields)
    f_trim = np.maximum.reduce(trim_fields)
    v, nrm, bone_idx, bone_w, tris, (f_cloth, f_trim) = split_along(v, nrm, bone_idx, bone_w, tris, f_cloth, [f_cloth, f_trim])
    v, nrm, bone_idx, bone_w, tris, (f_cloth, f_trim) = split_along(v, nrm, bone_idx, bone_w, tris, f_trim, [f_cloth, f_trim])
    def ramp(f, width):
        t = np.clip(f / width, 0, 1); return t * t * (3 - 2 * t)
    want = 0.003 * ramp(f_cloth, 0.010) + 0.0015 * ramp(f_trim, 0.003)
    n0 = normals_of(v, tris)
    p0 = v.copy()
    pos = v + n0 * want[:, None]
    # pas de lissage sur les lignes de découpe : les bords restent des courbes nettes
    strength = (ramp(f_cloth - 0.004, 0.016) * ramp(np.abs(f_trim) - 0.002, 0.008))[:, None]
    avg2 = adjacency(len(v), tris)
    for _ in range(40):
        pos = pos + 0.5 * strength * (avg2 @ pos - pos)
        d = ((pos - p0) * n0).sum(1)
        pos = pos + n0 * np.maximum(want - d, 0)[:, None]
    v = pos
    nrm = normals_of(v, tris)
    centre_f = (f_cloth[tris].mean(1), f_trim[tris].mean(1))
    tri_material = np.where(centre_f[1] > 0, 2, np.where(centre_f[0] > 0, 1, 0))
    return dict(order=order, parents=parents, halves=halves, heads=newheads, tails=newtails,
                v=v.astype(np.float32), n=nrm.astype(np.float32), tris=tris, bone_idx=bone_idx, bone_w=bone_w,
                tri_material=tri_material)

def split_along(v, n, bi, bw, tris, f, extras):
    """Coupe les triangles qui traversent la ligne f = 0 (sommets de coupe partagés : maillage sans fissure).
    Les poids d'os et les champs « extras » sont interpolés sur les sommets créés."""
    P, N, BI, BW = list(v), list(n), list(bi), list(bw)
    X = [list(e) for e in extras]
    cut = {}
    def edge(i, j):
        key = (min(i, j), max(i, j))
        if key not in cut:
            t = f[i] / (f[i] - f[j])
            p = v[i] + t * (v[j] - v[i]); nn = n[i] + t * (n[j] - n[i]); nn = nn / (np.linalg.norm(nn) + 1e-12)
            w = {}
            for b_, x in zip(bi[i], bw[i] * (1 - t)): w[int(b_)] = w.get(int(b_), 0) + x
            for b_, x in zip(bi[j], bw[j] * t): w[int(b_)] = w.get(int(b_), 0) + x
            top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
            tot = sum(x for _, x in top) or 1
            bix = np.zeros(4, np.uint16); bwx = np.zeros(4, np.float32)
            for k, (b_, x) in enumerate(top): bix[k] = b_; bwx[k] = x / tot
            cut[key] = len(P); P.append(p); N.append(nn); BI.append(bix); BW.append(bwx)
            for e, xs in zip(extras, X):
                xs.append(e[i] + t * (e[j] - e[i]))
        return cut[key]
    T = []
    for t in tris:
        side = f[t] >= 0
        if side.all() or not side.any():
            T.append(list(t)); continue
        for r in range(3):                       # sommet seul de son côté en premier, ordre conservé
            a, b, c = t[r], t[(r + 1) % 3], t[(r + 2) % 3]
            if side[r] != side[(r + 1) % 3] and side[r] != side[(r + 2) % 3]:
                eab, eac = edge(a, b), edge(a, c)
                T += [[a, eab, eac], [eab, b, c], [eab, c, eac]]
                break
    out_extras = [np.array(xs) for xs in X]
    for i, xs in enumerate(out_extras):
        if len(xs) > len(v):
            xs[len(v):][np.abs(xs[len(v):]) < 1e-9] = 0.0
    # la valeur du champ de coupe vaut exactement 0 sur la ligne
    return (np.array(P), np.array(N), np.array(BI, np.uint16), np.array(BW, np.float32), np.array(T, int), out_extras)

def export(sex, b):
    """Format GTM4 : plusieurs maillages (corps puis vêtements), chacun avec son matériau et ses poids."""
    os.makedirs(OUT, exist_ok=True)
    # Un maillage par matière (peau, tissu, liseré), découpés dans la même surface.
    meshes = []
    for mat in (0, 1, 2):
        sel = b["tris"][b["tri_material"] == mat]
        if not len(sel):
            continue
        used = np.unique(sel)
        remap = -np.ones(len(b["v"]), int); remap[used] = np.arange(len(used))
        meshes.append(dict(v=b["v"][used], n=b["n"][used], tris=remap[sel], bi=b["bone_idx"][used], bw=b["bone_w"][used], material=mat))
    with open(os.path.join(OUT, f"mannequin-{sex}.bin"), "wb") as fh:
        fh.write(struct.pack("<4sI", b"GTM4", len(meshes)))
        for m in meshes:
            idx = m["tris"].astype("<u4").ravel()
            fh.write(struct.pack("<III", m["material"], len(m["v"]), len(idx)))
            fh.write(m["v"].astype("<f4").tobytes()); fh.write(m["n"].astype("<f4").tobytes())
            fh.write(m["bi"].astype("<u2").tobytes()); fh.write(m["bw"].astype("<f4").tobytes())
            fh.write(idx.tobytes())
    return {
        "joints": [dict({"name": k, "parent": b["parents"][k], "head": [round(float(x), 5) for x in b["heads"][k]],
                         "tail": [round(float(x), 5) for x in b["tails"][k]]},
                        **({"half": b["halves"][k]} if k in b["halves"] else {})) for k in b["order"]],
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
            np.savez(f"{preview}/{sex}.npz", v=V, n=Nn, tris=T, bone_idx=BI, bone_w=BW, tri_mat=M, body_count=len(V),
                     order=np.array(b["order"]), heads=np.array([b["heads"][k] for k in b["order"]]),
                     parents=np.array([b["parents"][k] or "" for k in b["order"]]),
                     halves=np.array([(b["order"].index(h), b["order"].index(o)) for h, o in b["halves"].items()]))
            cols = [MATERIAL_COLORS[int(x)] for x in M]
            render(V, Nn, T, cols, f"{preview}/{sex}-front.png", yaw=25)
            render(V, Nn, T, cols, f"{preview}/{sex}-back.png", yaw=160)
            render(V, Nn, T, cols, f"{preview}/{sex}-hand.png", yaw=60, center=b["heads"]["wrist.L"] + [0, -0.08, 0], zoom=8)
    json.dump(meta, open(os.path.join(OUT, "mannequin.json"), "w"), indent=1)
