"""Planches de contrôle de tous les exercices, telles que l'app les joue.

Pour chaque étape d'exercice (Exercises.swift) et chaque corps, N images réparties sur toute la boucle, transitions
comprises, interpolées comme dans l'app (rotations locales sphériques, courbe de la clé d'arrivée, racine et hauteur de
mise au sol linéaires avec la même courbe), avec le sol, les accessoires et la consigne écrite.
Mesures à chaque image : peau sous le sol / sous le matelas (enfoncement) et corps en l'air (aucun appui).

Usage : python3 scripts/mannequin/review.py <dossier de sortie> [N images] [exercice…]
"""
import json, os, re, sys
from concurrent.futures import ProcessPoolExecutor
import numpy as np
from scipy.spatial.transform import Rotation, Slerp

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "../.."))
from motion_eval import (Body, resolve, library_for, local_rotations, boxes_for, box_mesh, towel_segments, band_mesh, glass_mesh,  # noqa: E402
                         camera_shot)
from export import render, MATERIAL_COLORS  # noqa: E402

MOTIONS = os.environ.get("MOTIONS_JSON") or os.path.join(ROOT, "Packages/GrowtinCore/Sources/GrowtinCore/Resources/motions.json")
EXERCISES = os.path.join(ROOT, "Packages/GrowtinCore/Sources/GrowtinCore/Explore/Exercises.swift")
RES = os.path.join(ROOT, "Growtin/Resources/Mannequin")


def steps():
    """[(exercice, titre de l'étape, consigne, mouvement)] dans l'ordre du fichier."""
    src = open(EXERCISES).read()
    out, ex = [], None
    for m in re.finditer(r'Exercise\(\s*id: "([^"]+)", title: "([^"]+)"|ExerciseStep\("([^"]*)", "([^"]*)"(.*?)motion: "([^"]+)"', src, re.S):
        if m.group(1):
            ex = (m.group(1), m.group(2))
        else:
            out.append((ex, m.group(3), m.group(4), m.group(6)))
    return out


def ease(u, name):
    if name == "linear": return u
    if name == "in": return u * u
    if name == "out": return 1 - (1 - u) ** 2
    return u * u * (3 - 2 * u)


class Player:
    """Même calcul que MannequinStage : une clé par image clé, mise au sol par clé, interpolation entre clés."""

    def __init__(self, body, lib, mid):
        self.body, self.m = body, lib["motions"][mid]
        names = body.names
        self.support = self.m.get("support") or 0.0
        scale = body.rig.heads[0][1] / lib["referenceHeight"] if lib.get("referenceHeight") else 1.0
        self.keys = []
        if "clip" in self.m:
            from mocap import quat_to_matrix
            clip = self.m["clip"]
            for i, fr in enumerate(clip["frames"]):
                loc = {b: quat_to_matrix(np.array(fr[j * 4:j * 4 + 4]) / np.linalg.norm(fr[j * 4:j * 4 + 4]))
                       for j, b in enumerate(clip["bones"])}
                self.keys.append((i / clip["fps"], loc, np.zeros(3), None, True))
            self.keys.append((len(clip["frames"]) / clip["fps"], self.keys[0][1], np.zeros(3), None, True))
            self.duration = self.keys[-1][0]
        else:
            for k in self.m["keys"]:
                p = resolve(k["pose"], lib["poses"])
                self.keys.append((k["t"], local_rotations(p, names), np.asarray(p["root"]["offset"], float) * scale,
                                  k.get("ease"), p["ground"]))
            self.duration = self.keys[-1][0]
        # hauteur de mise au sol de chaque clé (l'app garde la précédente pour une clé sans mise au sol)
        self.lifts, lift = [], 0.0
        for t, loc, off, _, ground in self.keys:
            if ground:
                R, P = body.rig.fk(loc, off)
                s = body.sample
                vs, _ = body.rig.skin(body.v[s], body.n[s], body.bi[s], body.bw[s], R, P)
                lift = -vs[:, 1].min() + self.support
            self.lifts.append(lift)

    def at(self, t):
        ks = self.keys
        if t <= ks[0][0]: i, u = 0, 0.0
        elif t >= ks[-1][0]: i, u = len(ks) - 2, 1.0
        else:
            i = max(j for j in range(len(ks) - 1) if ks[j][0] <= t)
            u = (t - ks[i][0]) / max(ks[i + 1][0] - ks[i][0], 1e-6)
        a, b = ks[i], ks[i + 1]
        e = ease(u, b[3])
        loc = {}
        for n in set(a[1]) | set(b[1]):
            ra = Rotation.from_matrix(a[1].get(n, np.eye(3))); rb = Rotation.from_matrix(b[1].get(n, np.eye(3)))
            loc[n] = Slerp([0, 1], Rotation.concatenate([ra, rb]))(e).as_matrix()
        off = a[2] * (1 - e) + b[2] * e
        lift = self.lifts[i] * (1 - e) + self.lifts[i + 1] * e
        R, P = self.body.rig.fk(loc, off + [0, lift, 0])
        return R, P


def props_mesh(body, lib, m, player):
    vs, ns, ts, cs = [], [], [], []
    base = 0
    for pr in m.get("props", []):
        anchor = None
        if pr.get("anchor"):
            ki = pr.get("key") or 0
            R, P = player.at(player.keys[ki][0])
            anchor = P[body.names.index(pr["anchor"])]
        for center, half, Rb in boxes_for(pr, anchor):
            bv, bn, bt = box_mesh(center, np.array(half), Rb)
            vs.append(bv); ns.append(bn); ts.append(bt + base); base += len(bv)
            col = {"mat": [0.45, 0.62, 0.52], "bed": [0.93, 0.93, 0.92], "pillow": [0.97, 0.97, 0.97]}.get(pr["kind"], [0.55, 0.42, 0.3])
            cs += [np.array(col)] * len(bt)
    return vs, ns, ts, cs


def floor_mesh(cx, cz):
    v, n, t = box_mesh(np.array([cx, -0.01, cz]), np.array([1.6, 0.01, 1.6]), np.eye(3))
    return v, n, t


def strip(job):
    body_name, mid, frames, size, out = job
    body = Body.from_resources(body_name, RES)
    lib = library_for(json.load(open(MOTIONS)), body_name)
    m = lib["motions"][mid]
    pl = Player(body, lib, mid)
    from PIL import Image, ImageDraw
    tiles, metrics = [], []
    pvs, pns, pts, pcs = props_mesh(body, lib, m, pl)
    times = np.linspace(0, pl.duration, frames, endpoint=False)
    cam = m.get("camera", {"yaw": 30, "pitch": 8})
    # cadrage commun à toute la bande (comme l'app : cadre fixe sur le mouvement)
    boxes = []
    poses = []
    for t in times:
        R, P = pl.at(t)
        v, n = body.rig.skin(body.v, body.n, body.bi, body.bw, R, P)
        poses.append((v, n)); boxes.append((v.min(0), v.max(0)))
        lo = v[:, 1].min()
        # appui : le sol (y = 0) ou le matelas (support) ; mesure de l'écart du point le plus bas
        metrics.append({"t": round(float(t), 2), "low_mm": round(float(lo) * 1000, 1)})
    lo = np.min([b[0] for b in boxes], 0); hi = np.max([b[1] for b in boxes], 0)
    c = (lo + hi) / 2; ext = max(hi[1] - min(lo[1], 0), hi[0] - lo[0], hi[2] - lo[2]) * 1.2
    c[1] = (hi[1] + min(lo[1], 0)) / 2
    if cam.get("frame"):
        # Cadrage resserré sur une zone du corps : même point visé et même champ que l'app (CameraFraming), calculés
        # sur les articulations des images clés ; aperçu sans perspective, à l'échelle de la distance de la caméra.
        ids = [body.names.index(j) for j in cam["frame"]]
        c, _, ext = camera_shot([pl.at(k[0])[1] for k in pl.keys], ids, cam["yaw"], cam.get("pitch"), cam.get("margin"))
    fv, fn, ft = floor_mesh(c[0], c[2])
    for (v, n), t, mt in zip(poses, times, metrics):
        cols = [MATERIAL_COLORS[int(x)] for x in body.tri_mat]
        V, N, T, C = [v], [n], [body.tris], list(cols)
        off = len(v)
        for bv, bn, bt, in zip(pvs, pns, pts):
            V.append(bv); N.append(bn); T.append(bt + off)
        C += pcs
        off += sum(len(x) for x in pvs)
        V.append(fv); N.append(fn); T.append(ft + off); C += [np.array([0.62, 0.62, 0.64])] * len(ft)
        off += len(fv)
        for pr in m.get("props", []):
            if pr["kind"] == "glass":
                # Verre tenu : cylindre posé contre la paume (même placement que l'app).
                bv, bn, bt = glass_mesh(pr, v)
                V.append(bv); N.append(bn); T.append(bt + off); off += len(bv); C += [np.array([0.45, 0.72, 0.92])] * len(bt)
            if pr["kind"] != "towel": continue
            # Serviette : brin gauche, passage à plat sous le pied, brin droit (mêmes tronçons que l'app).
            for seg in towel_segments(pr, v):
                bv, bn, bt = band_mesh(seg)
                V.append(bv); N.append(bn); T.append(bt + off); off += len(bv); C += [np.array([0.42, 0.63, 0.78])] * len(bt)
        tmp = f"/tmp/_rv_{os.getpid()}.png"
        render(np.vstack(V), np.vstack(N), np.vstack(T), C, tmp, size=size, yaw=cam["yaw"], pitch=cam.get("pitch", 8),
               center=c, zoom=2.1 / ext)
        im = Image.open(tmp).convert("RGB")
        d = ImageDraw.Draw(im)
        flag = mt["low_mm"] < -5
        d.text((5, 4), f"{t:.1f}s  bas {mt['low_mm']:+.0f} mm", fill=(255, 80, 80) if flag else (255, 255, 255))
        tiles.append(im)
    row = Image.new("RGB", (size * len(tiles), size))
    for i, im in enumerate(tiles): row.paste(im, (i * size, 0))
    row.save(out)
    return body_name, mid, metrics


def main():
    out_dir = sys.argv[1]; frames = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    only = set(sys.argv[3:])
    os.makedirs(out_dir, exist_ok=True)
    st = [s for s in steps() if not only or s[0][0] in only]
    mids = sorted({s[3] for s in st})
    size = int(os.environ.get("SIZE", 200))
    jobs = [(b, mid, frames, size, os.path.join(out_dir, f"_{b}_{mid}.png")) for b in ("female", "male") for mid in mids]
    with ProcessPoolExecutor(int(os.environ.get("JOBS", os.cpu_count() or 2))) as ex:
        results = list(ex.map(strip, jobs))
    json.dump([{"body": b, "motion": mid, "frames": mt} for b, mid, mt in results], open(os.path.join(out_dir, "metrics.json"), "w"), indent=1)
    # une planche par exercice : chaque étape (consigne écrite), femme puis homme
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    by_ex = {}
    for ex, title, text, mid in st:
        by_ex.setdefault(ex, []).append((title, text, mid))
    W = size * frames
    for (eid, etitle), ss in by_ex.items():
        seen, rows = set(), []
        for title, text, mid in ss:
            if (title, mid) in seen: continue
            seen.add((title, mid))
            rows.append((title, text, mid))
        H = sum(44 + 2 * size + 6 for _ in rows) + 40
        sheet = Image.new("RGB", (W, H), (245, 245, 247)); d = ImageDraw.Draw(sheet)
        d.text((8, 10), f"{etitle}  ({eid})", fill=(0, 0, 0), font=font)
        y = 40
        for title, text, mid in rows:
            d.text((8, y), f"{title} · {mid}", fill=(10, 90, 50), font=font)
            d.text((8, y + 22), text[:200], fill=(40, 40, 40), font=small)
            y += 44
            for b in ("female", "male"):
                sheet.paste(Image.open(os.path.join(out_dir, f"_{b}_{mid}.png")), (0, y)); y += size
            y += 6
        sheet.save(os.path.join(out_dir, f"{eid}.png"))
    print(out_dir, len(by_ex), "planches,", len(jobs), "bandes")


if __name__ == "__main__":
    main()
