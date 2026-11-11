"""Outil d'auteur : trouve les angles d'une pose au sol à partir de contraintes simples sur les articulations.
Usage : python3 scripts/mannequin/solve_poses.py <male.npz>
"""
import sys, os, json
import numpy as np
from scipy.optimize import minimize
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from motion_eval import Body, resolve, local_rotations  # noqa: E402

body = Body(sys.argv[1])
names = body.names; J = {n: i for i, n in enumerate(names)}

def joints(pose):
    p = resolve(pose, {})
    loc = local_rotations(p, names)
    R, P = body.rig.fk(loc, p["root"]["offset"])
    s = body.sample
    vs, _ = body.rig.skin(body.v[s], body.n[s], body.bi[s], body.bw[s], R, P)
    P = P + [0, -vs[:, 1].min(), 0]
    return P

def solve(build, x0, cost, iters=400):
    f = lambda x: cost(joints(build(x)))
    res = minimize(f, x0, method="Powell", options={"maxiter": iters, "xtol": 0.05, "ftol": 1e-7})
    return np.round(res.x, 1), res.fun

def bones(**kw):
    return {"bones": {k: [float(a) for a in v] for k, v in kw.items()}}

# 1. À quatre pattes (repère avant le quart de tour de caméra) : mains sous les épaules, genoux sous les hanches.
def quad(x):
    pitch, hip, knee, foot, sh, pron, wx, wz = x
    d = bones(upperleg01=[hip, 0, 2], lowerleg01=[knee, 0, 0], foot=[foot, 0, 0], upperarm01=[sh, 0, 3], lowerarm01=[-4, 0, 0],
              lowerarm02=[0, pron, 0], wrist=[wx, 0, wz])
    d["root"] = {"rot": [["x", pitch]]}
    return d
def quad_cost(P):
    kn, an, hi = P[J["lowerleg01.L"]], P[J["foot.L"]], P[J["upperleg01.L"]]
    sh, wr = P[J["upperarm01.L"]], P[J["wrist.L"]]
    f2, f3, f5 = P[J["finger2-1.L"]], P[J["finger3-1.L"]], P[J["finger5-1.L"]]
    return ((kn[1] - 0.06) ** 2 + (an[1] - 0.07) ** 2 + 2 * (kn[2] - hi[2]) ** 2 + 2 * (wr[2] - sh[2]) ** 2 + 2 * (wr[0] - sh[0]) ** 2
            + (wr[1] - 0.05) ** 2 + (f2[1] - 0.025) ** 2 + (f3[1] - 0.025) ** 2 + (f5[1] - 0.025) ** 2
            + 2 * max(0, wr[2] - f3[2] + 0.07) ** 2)
x, c = solve(quad, [80, -80, 92, 70, -80, 0, 0, 0], quad_cost, iters=800)
print("quadruped", x.tolist(), c)

# 2. Assis en tailleur : genoux larges et bas, pieds croisés sous les genoux opposés.
def cross(x):
    hx, hy, hz, k, f = x
    return bones(**{"upperleg01.L": [hx, hy, hz], "upperleg01.R": [hx, -hy, -hz], "lowerleg01.L": [k, 0, 0], "lowerleg01.R": [k, 0, 0],
                    "foot.L": [f, 0, 0], "foot.R": [f, 0, 0]})
def cross_cost(P):
    hip, kl, al = P[J["upperleg01.L"]], P[J["lowerleg01.L"]], P[J["foot.L"]]
    return ((kl[1] - (hip[1] - 0.04)) ** 2 + (kl[0] - 0.36) ** 2 + (kl[2] - hip[2] - 0.22) ** 2
            + (al[0] + 0.1) ** 2 + (al[2] - hip[2] - 0.3) ** 2 + (al[1] - 0.07) ** 2)
x, c = solve(cross, [-85, 40, -60, 130, 10], cross_cost)
print("crossLegged", x.tolist(), c)

# 3. Papillon : plantes de pied jointes devant le bassin, genoux écartés.
def butter(x):
    hx, hy, hz, k, f = x
    return bones(**{"upperleg01.L": [hx, hy, hz], "upperleg01.R": [hx, -hy, -hz], "lowerleg01.L": [k, 0, 0], "lowerleg01.R": [k, 0, 0],
                    "foot.L": [f, 0, -30], "foot.R": [f, 0, 30]})
def butter_cost(P):
    hip, kl, al = P[J["upperleg01.L"]], P[J["lowerleg01.L"]], P[J["foot.L"]]
    return ((al[0] - 0.05) ** 2 + (al[2] - hip[2] - 0.38) ** 2 + (al[1] - 0.08) ** 2 + (kl[0] - 0.42) ** 2 + (kl[1] - hip[1] - 0.02) ** 2)
x, c = solve(butter, [-80, 40, -40, 120, 10], butter_cost)
print("butterfly", x.tolist(), c)

# 4. Posture de l'enfant (repère avant le quart de tour) : assis sur les talons, buste sur les cuisses, bras devant.
def child(x):
    pitch, hip, knee, foot, sh, neck = x
    d = bones(upperleg01=[hip, 0, 10], lowerleg01=[knee, 0, 0], foot=[foot, 0, 0], upperarm01=[sh, 0, 6], lowerarm01=[-4, 0, 0], neck01=[neck, 0, 0])
    d["root"] = {"rot": [["x", pitch]]}
    return d
def child_cost(P):
    kn, an, hi = P[J["lowerleg01.L"]], P[J["foot.L"]], P[J["upperleg01.L"]]
    wr, he, sh = P[J["wrist.L"]], P[J["head"]], P[J["upperarm01.L"]]
    return ((kn[1] - 0.06) ** 2 + (an[1] - 0.06) ** 2 + (hi[2] - an[2] - 0.03) ** 2 + (hi[1] - 0.26) ** 2
            + (wr[1] - 0.05) ** 2 + 0.3 * (he[1] - 0.16) ** 2 + 0.2 * (sh[1] - 0.22) ** 2)
x, c = solve(child, [94, -150, 150, 78, -168, 18], child_cost)
print("child", x.tolist(), c)
