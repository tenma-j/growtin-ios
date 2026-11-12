"""Aperçu d'un extrait de capture reciblé : une vignette toutes les N secondes.
Usage : python3 scripts/mannequin/mocap_preview.py <corps.npz> <fichier.bvh> <début> <fin> <pas_s> <sortie.png> [lacet]
(début et fin en images à 120 i/s)
"""
import sys, os
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from motion_eval import Body  # noqa: E402
from export import render, MATERIAL_COLORS  # noqa: E402
from mocap import retarget, quat_to_matrix  # noqa: E402
from PIL import Image, ImageDraw

def pose_from_quats(body, q):
    loc = {n: quat_to_matrix(q[i]) for i, n in enumerate(body.names)}
    R, P = body.rig.fk(loc)
    s = body.sample
    vs, _ = body.rig.skin(body.v[s], body.n[s], body.bi[s], body.bw[s], R, P)
    P = P + [0, -vs[:, 1].min(), 0]
    return body.rig.skin(body.v, body.n, body.bi, body.bw, R, P)

if __name__ == "__main__":
    body = Body(sys.argv[1])
    start, end, step = int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
    yaw = float(sys.argv[7]) if len(sys.argv) > 7 else 25
    parents = [body.rig.parents[i] for i in range(len(body.names))]
    heads = {n: body.rig.heads[i] for i, n in enumerate(body.names)}
    Q, _ = retarget(sys.argv[2], body.names, parents, heads, start, end, fps=30, blend=0)
    idxs = list(range(0, len(Q), max(1, int(step * 30))))
    tiles = []
    cols = [MATERIAL_COLORS[int(x)] for x in body.tri_mat]
    for k in idxs:
        v, n = pose_from_quats(body, Q[k])
        c = np.array([0, 0.9, 0.0]); tmp = f"/tmp/_mp_{os.getpid()}.png"
        render(v, n, body.tris, cols, tmp, size=int(os.environ.get("TILE", 240)), yaw=yaw, pitch=6, center=[v[:, 0].mean(), 0.95, v[:, 2].mean()], zoom=1.0)
        im = Image.open(tmp).convert("RGB"); ImageDraw.Draw(im).text((4, 4), f"{(start + k * 4) / 120:.1f}s", fill=(255, 255, 255)); tiles.append(im)
    T = int(os.environ.get("TILE", 240)); cols_n = 10 if T < 200 else 8; rows = (len(tiles) + cols_n - 1) // cols_n
    out = Image.new("RGB", (cols_n * T, rows * T))
    for i, t in enumerate(tiles): out.paste(t, ((i % cols_n) * T, (i // cols_n) * T))
    out.save(sys.argv[6]); print(len(tiles), "vignettes")
