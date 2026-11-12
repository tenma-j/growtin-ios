"""Cinématique directe et déformation de la peau (skinning linéaire), identiques à celles de l'app.

Convention commune avec l'app : dans la pose de référence, chaque os a l'orientation du repère monde
(X vers la gauche du personnage, Y vers le haut, Z vers l'avant). Une pose donne pour chaque os une
rotation locale (angles d'Euler en degrés, appliqués dans l'ordre X puis Y puis Z), relative à son parent.
Articulations d'appoint (épaules, coudes, hanches, genoux) : placées au même point que l'os qu'elles doublent,
elles prennent la moitié de sa rotation ; la peau de la pliure les suit, ce qui garde son volume.
"""
import numpy as np

def axis_angle(axis, deg):
    axis = np.asarray(axis, float); axis = axis / np.linalg.norm(axis)
    a = np.radians(deg); c, s = np.cos(a), np.sin(a); x, y, z = axis
    return np.array([[c + x*x*(1-c), x*y*(1-c) - z*s, x*z*(1-c) + y*s],
                     [y*x*(1-c) + z*s, c + y*y*(1-c), y*z*(1-c) - x*s],
                     [z*x*(1-c) - y*s, z*y*(1-c) + x*s, c + z*z*(1-c)]])

def euler(xyz):
    """Rotation locale : X, puis Y, puis Z (R = Rz · Ry · Rx), en degrés."""
    x, y, z = xyz
    return axis_angle([0, 0, 1], z) @ axis_angle([0, 1, 0], y) @ axis_angle([1, 0, 0], x)

def half_rotation(R):
    """Moitié d'une rotation (même axe, angle divisé par deux, par le chemin le plus court)."""
    c = np.clip((np.trace(R) - 1) / 2, -1, 1); ang = np.arccos(c)
    if ang < 1e-7:
        return np.eye(3)
    ax = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]])
    if np.linalg.norm(ax) < 1e-7:                       # demi-tour : l'axe est le vecteur propre de valeur 1
        w, V = np.linalg.eigh((R + np.eye(3)) / 2); ax = V[:, np.argmax(w)]
    return axis_angle(ax, np.degrees(ang / 2))

class Rig:
    def __init__(self, names, parents, heads, halves=None):
        self.names = list(names)
        self.index = {n: i for i, n in enumerate(self.names)}
        self.parents = [parents[n] for n in self.names]
        self.heads = np.array([heads[n] for n in self.names], float)
        # Articulations d'appoint : {appoint: os} ; l'appoint prend la moitié de la rotation locale de l'os.
        self.halves = dict(halves or {})

    def fk(self, local, root_offset=(0, 0, 0)):
        """local : {os: matrice 3×3}. Renvoie (rotations monde, positions monde des articulations)."""
        n = len(self.names)
        R = np.zeros((n, 3, 3)); P = np.zeros((n, 3))
        for i, name in enumerate(self.names):
            L = local.get(name, np.eye(3))
            if name in self.halves:
                L = half_rotation(local.get(self.halves[name], np.eye(3)))
            p = self.parents[i]
            if p is None:
                R[i] = L; P[i] = self.heads[i] + np.asarray(root_offset, float)
            else:
                j = self.index[p]
                R[i] = R[j] @ L
                P[i] = P[j] + R[j] @ (self.heads[i] - self.heads[j])
        return R, P

    def skin(self, verts, normals, bone_idx, bone_w, R, P):
        v = np.zeros_like(verts); nn = np.zeros_like(normals)
        for k in range(bone_idx.shape[1]):
            b = bone_idx[:, k]; w = bone_w[:, k][:, None]
            rel = verts - self.heads[b]
            v += w * (np.einsum("nij,nj->ni", R[b], rel) + P[b])
            nn += w * np.einsum("nij,nj->ni", R[b], normals)
        nn /= np.linalg.norm(nn, axis=1, keepdims=True) + 1e-9
        return v, nn

    def world_rotate(self, local, bone, axis, deg):
        """Ajoute à un os une rotation exprimée dans le repère monde (pour la mise en pose de référence)."""
        R, _ = self.fk(local)
        i = self.index[bone]
        p = self.parents[i]
        Rp = R[self.index[p]] if p is not None else np.eye(3)
        delta = axis_angle(axis, deg)
        local[bone] = Rp.T @ delta @ Rp @ local.get(bone, np.eye(3))
        return local
