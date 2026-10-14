# Straight-line grid warp shared by platinum.py and unify.py.
import numpy as np, cv2

def mono_map(pairs, lo, hi, lo_s, hi_s):
    """Monotone 1-D map (target -> source) through averaged control pairs, pinned at both ends."""
    from scipy.interpolate import PchipInterpolator
    pairs = sorted(pairs); xs, ys = [lo], [lo_s]
    i = 0
    while i < len(pairs):
        j = i
        while j + 1 < len(pairs) and pairs[j + 1][0] - pairs[i][0] < 10: j += 1
        grp = np.array(pairs[i:j + 1]); xm, xsrc = grp[:, 0].mean(), grp[:, 1].mean()
        if xm - xs[-1] > 6 and xsrc > ys[-1] + 2: xs.append(xm); ys.append(xsrc)
        i = j + 1
    if hi - xs[-1] > 6: xs.append(hi); ys.append(max(hi_s, ys[-1] + 3))
    return PchipInterpolator(xs, ys)

def grid_warp(img, M, Sp, Aff, bands, xo=(), yo=()):
    """Straight-line warp: one y map for the whole plate, an x map per horizontal band.
    xo: extra (target x, source x) pairs used by every band (the plate's side edges);
    yo: extra (target y, source y) pairs for the y map only (top and bottom edges)."""
    xo, yo = list(xo), list(yo)
    H, W = img.shape[:2]
    edge = lambda x, y: np.array([x, y, 1.0]) @ np.linalg.inv(np.vstack([Aff.T, [0, 0, 1]])).T
    fy = mono_map(list(zip(M[:, 1], Sp[:, 1])) + yo, 0, H - 1, edge(W / 2, 0)[1], edge(W / 2, H - 1)[1])
    rows = np.arange(H, dtype=np.float64); my = np.repeat(fy(rows)[:, None], W, 1).astype(np.float32)
    cols = np.arange(W, dtype=np.float64); fx = []
    for b0, b1 in zip(bands[:-1], bands[1:]):
        sel = (M[:, 1] >= b0) & (M[:, 1] < b1)
        mid = (b0 + b1) / 2
        fx.append(mono_map(list(zip(M[sel, 0], Sp[sel, 0])) + xo, 0, W - 1, edge(0, mid)[0], edge(W - 1, mid)[0])(cols))
    # Near the left and right edges every band uses one shared map, so the plate's outline stays straight.
    glob = mono_map(list(zip(M[:, 0], Sp[:, 0])) + xo, 0, W - 1, edge(0, H / 2)[0], edge(W - 1, H / 2)[0])(cols)
    wgt = np.clip(np.minimum(cols - 70, (W - 1 - 70) - cols) / 30, 0, 1); wgt = wgt * wgt * (3 - 2 * wgt)
    fx = [f * wgt + glob * (1 - wgt) for f in fx]
    mx = np.zeros((H, W), np.float32)
    centers = [(b0 + b1) / 2 for b0, b1 in zip(bands[:-1], bands[1:])]
    for y in range(H):
        # Blend neighbouring bands across a 40 px seam at each boundary.
        k = np.searchsorted(bands, y, side="right") - 1; k = min(max(k, 0), len(fx) - 1)
        row = fx[k]
        for bnd, (ka, kb) in zip(bands[1:-1], zip(range(len(fx) - 1), range(1, len(fx)))):
            t = (y - (bnd - 20)) / 40
            if 0 < t < 1:
                t = t * t * (3 - 2 * t); row = fx[ka] * (1 - t) + fx[kb] * t
        mx[y] = row
    return cv2.remap(img, mx, my, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)

