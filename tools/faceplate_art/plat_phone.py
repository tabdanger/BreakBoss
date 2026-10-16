# iPhone Platinum master (Oct 14): Tyrone's Platinum plate lined up with the iPhone layout (platinum.py),
# then: the lit MODERN button becomes a dark cap with a red dash (like the iPad and every other button),
# and the old knobs and their labels are cleared row by row so the new knobs and lettering sit clean.
# Writes src/p_platinum_P.png. Run after platinum.py (src/p_platinum_W.png), before plat_unify.py.
import json, numpy as np, cv2
from plat_geom import dash, row_clear
A2 = "/home/claude/art2"
R2 = json.load(open(f"{A2}/rects.json"))["p_modern"]; K2 = json.load(open(f"{A2}/knobs.json"))["p_modern"]
LB = json.load(open("labels_modern.json"))["p"]
PK = json.load(open("p_plat_knobs.json"))
ORDER = ["pitch","tune","bounce","velocity","filter","clipDrive","output","boost","punch","analogEQ","grit","shine","tighten","noise"]
a = cv2.imread("src/p_platinum_W.png")
# MODERN: VINTAGE's dark cap, its grey dash lit red
vx0, vy0, vx1, vy1 = R2["mode_vintage"]; mx0, my0, mx1, my1 = R2["mode_modern"]
cap = cv2.resize(a[vy0:vy1, vx0:vx1], (mx1 - mx0, my1 - my0), interpolation=cv2.INTER_AREA)
a[my0:my1, mx0:mx1] = cap
sub = a[my0:my1, mx0:mx1].astype(np.float32); L = sub.mean(2); h = L.shape[0]
low = np.zeros_like(L, bool); low[int(h * 0.6):h - 6, 10:-10] = True
bright = low & (L > np.median(L[low]) + 50)
ys, xs = np.nonzero(bright)
a = dash(a, mx0 + (xs.min() + xs.max()) / 2, my0 + ys.mean(), xs.max() - xs.min() + 3, 4, (255, 46, 32), 0.9)
# old knobs and knob labels
clr = np.zeros(a.shape[:2], np.uint8)
for k in ORDER:
    x, y, _ = K2[k]; r = PK[k][2]
    cv2.circle(clr, (int(round(x - 2)), int(round(y + 4))), int(round(r * 1.8)), 1, -1)
    b = LB[k]; cv2.rectangle(clr, (b[0] - 6, b[1] - 5), (b[2] + 6, b[3] + 5), 1, -1)
a = row_clear(a, clr.astype(bool), 21)
cv2.imwrite("src/p_platinum_P.png", a)
print("ok")
