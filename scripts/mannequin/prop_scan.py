"""Peau dans les accessoires : pour chaque mouvement à accessoires, chaque corps, à FPS images/s (lecture de l'app),
profondeur max de peau à l'intérieur de chaque pavé, et l'os qui porte ces sommets."""
import json, os, sys
import numpy as np
from concurrent.futures import ProcessPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from review import Player, MOTIONS, RES
from motion_eval import Body, library_for, boxes_for
FPS = float(os.environ.get("FPS", 15))

def job(a):
    body_name, mid = a
    body = Body.from_resources(body_name, RES); lib = library_for(json.load(open(MOTIONS)), body_name)
    m = lib["motions"][mid]; pl = Player(body, lib, mid)
    boxes = []
    for pr in m.get("props", []):
        if pr["kind"] in ("towel", "mat"): continue
        anchor = None
        if pr.get("anchor"):
            R, P = pl.at(pl.keys[pr.get("key") or 0][0]); anchor = P[body.names.index(pr["anchor"])]
        for i, (c, h, Rb) in enumerate(boxes_for(pr, anchor)):
            boxes.append((f"{pr['kind']}#{i}", np.array(c), np.array(h), np.array(Rb)))
    if not boxes: return body_name, mid, []
    worst = {}
    for t in np.arange(0, pl.duration, 1 / FPS):
        R, P = pl.at(t)
        v, _ = body.rig.skin(body.v, body.n, body.bi, body.bw, R, P)
        for name, c, h, Rb in boxes:
            loc = (v - c) @ Rb
            inside = np.all(np.abs(loc) < h, axis=1)
            if not inside.any(): continue
            depth = np.min(h - np.abs(loc[inside]), axis=1)
            j = int(np.argmax(depth)); d = float(depth[j]) * 1000
            vid = np.flatnonzero(inside)[j]; bone = body.names[int(body.bi[vid][0])]
            if d > worst.get(name, (0,))[0]: worst[name] = (d, round(float(t), 2), bone, int(inside.sum()))
    return body_name, mid, sorted(((n,) + w for n, w in worst.items()), key=lambda x: -x[1])

if __name__ == "__main__":
    lib = json.load(open(MOTIONS))
    mids = sorted(k for k, m in lib["bodies"]["female"]["motions"].items() if any(p["kind"] not in ("towel","mat") for p in m.get("props", [])))
    with ProcessPoolExecutor(os.cpu_count()) as ex:
        for b, mid, res in ex.map(job, [(b, m) for m in mids for b in ("female", "male")]):
            bad = [r for r in res if r[1] > 5]
            print(f"{b:6} {mid:22} " + ("ok" if not bad else " | ".join(f"{n} {d:.0f}mm t={t} {bone} ({cnt} sommets)" for n, d, t, bone, cnt in bad)), flush=True)
