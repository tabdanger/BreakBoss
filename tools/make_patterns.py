#!/usr/bin/env python3
"""Builds BreakBoss.swiftpm/Resources/PatternBank.json, the factory PRESETS (patterns only).

Lanes are step strings, 16 steps per bar (1, 2 or 4 bars). Codes:
  .  rest          x  hit (0.82)    X  accent (1.0)   o  medium (0.62)   g  ghost (0.38)
  r  two 32nds     q  four 64ths    t  triplet: three hits across this step and the next
  808 lane: 0-9 = semitones up, a b c = 10 11 12, A-L = 1..12 down, - = hold, . = rest
Swing is MPC-style percent (50 = straight). Tyrone's own patterns are the "Danger Patterns".
Feel (optional, by lane): swingLanes = a track's own swing (0..1 like the SWING knob, 0 = straight),
shift = pushed early (-) or pulled late (+) in ticks (96 a beat), ghostChance = how often its ghost
notes (velocity g) play, 0..1.
"""
import json, os, sys

LANES = {"k": 0, "s": 1, "c": 2, "r": 3, "h": 4, "o": 5, "b": 6, "p1": 7, "p2": 8, "lt": 9, "ht": 10, "cr": 11}
P = []
def pat(style, name, bpm, swing=50, glide=False, **lanes):
    for key, v in lanes.items():
        assert key in LANES, key
        assert len(v) in (16, 32, 64), (name, key, len(v))
    n = {len(v) for v in lanes.values()}
    assert len(n) == 1, (name, n)
    P.append({"style": style, "name": name, "bpm": bpm, "swing": swing, "glide": glide, "lanes": lanes})

# The feel each live style is played with (the research: Dilla's snare early over a straight kick and
# swung hats, 90s hats swung harder than the kick and snare, soul backbeats a hair behind, R&B snares late).
FEEL = {
    "Dilla Time": {"swingLanes": {"h": 0.55, "k": 0}, "shift": {"s": -4, "c": -4, "r": -3, "k": 2}, "ghostChance": {"s": 0.7, "h": 0.85}},
    "90s Rap": {"swingLanes": {"h": 0.9}, "shift": {"c": 2}, "ghostChance": {"s": 0.8}},
    "70s Soul": {"shift": {"s": 2}, "ghostChance": {"s": 0.75}},
    "80s Breaks": {"ghostChance": {"s": 0.8}},
    "UK RnB": {"shift": {"s": 3, "c": 3, "r": 2}},
}
FEEL_NAMES = {   # the live additions to older styles (their older presets keep playing as they did)
    "NEO SOUL 11 LIVE POCKET": {"shift": {"s": -3, "r": -3, "k": 2}, "ghostChance": {"s": 0.7}},
    "NEO SOUL 12 CROSS STICK": {"shift": {"r": -3, "k": 2}, "ghostChance": {"s": 0.7}},
    "NEO SOUL 13 BROKEN TIME": {"swingLanes": {"h": 0.5, "k": 0}, "shift": {"s": -3}, "ghostChance": {"s": 0.7}},
    "BOOM BAP 11 LIVE BREAK": {"swingLanes": {"h": 0.9}, "ghostChance": {"s": 0.8}},
    "BOOM BAP 12 SP DUST": {"swingLanes": {"h": 0.9}, "shift": {"r": -2}},
    "BOOM BAP 13 HARD KNOCK": {"swingLanes": {"h": 0.9}},
}

# ---------------- Danger Patterns (Tyrone's) ----------------
D = "Danger Patterns"
pat(D, "80s HIP HOP 1", 87, 54, h="x.x.xxx.x.xxxxxx", s="...xx..xxx..x..x", k="x..x..x...x..x..")
pat(D, "80s HIP HOP 2", 87, 54, h="x.xxx.xxxxx.xx.x", s="....x..xxx..x..x", k="x..x..x...x..x..")
pat(D, "80s HIP HOP 3", 87, 54, o="......x.........", h="x.xxx..xxxx.xx.x", s="....x....x..x..x", k="x..x......x....x")
pat(D, "80s HIP HOP 4", 87, 54, h="x.xxx.xxxxxxxx.x", s="...xx....x..x..x", k="x..x..x...x...x.")
pat(D, "80s HIP HOP 5", 87, 54, h="x.x.x.x.x.x.x.x.", s="....x.......x...", k="x.........x.....")
pat(D, "AFRO TRAP 1", 120,
    k="x...x...x..xx...x...x...x...x..x", s="x..x..x...x.x...x..x..x...x.x...",
    p1=".x.....x.........x....x.x.....x.", p2=".........x...x..............xx.x")
pat(D, "AFRO TRAP 2", 120,
    k="x.......x...x...x.......x...x...", s="x..x..x...x.x...x..x..x.....x...",
    p1=".....x...............x........xx", h="..x...............x..x..........", o="......x...............x.........")
pat(D, "AFRO TRAP 3", 120,
    k="x...x...x...x...x...x...........", s="x..x..x.....x...x..x..x.x...x...",
    h=".........x.x.............x.x....", o="..............x...............x.")
pat(D, "AFRO TRAP 4", 120, k="x...x...x...x...", s="x..x..x...x...x.", p1="xxx.........xx..", o="..............x.", h="........xx......")
pat(D, "AFRO TRAP 5", 120,
    k="x...x...x...x...x...x...x...x...", s="x..x..x...x.x...x..x..x...x.x...",
    p1="x.x...x.......x.x..xx.x.x.x.x.x.", p2="x.x.............x.x.............")
pat(D, "90s BREAKBEAT 1", 90, 54, h="xxxxx.xxxxxxxxxx", s="....x....x...x..", k="x..x...x...x...x")
pat(D, "90s BREAKBEAT 2", 90, 54, h="x.xxxxxxxxxxx.xx", s="....x........x.x", k="x.x....xx.x.....")
pat(D, "90s BREAKBEAT 3", 90, 54, h="xxxxx.xxx.xxx.xx", s="....x....x.x.x.x", c="....x...........", k="x.x....x........")

# ---------------- Trap (half-time: snare/clap on 3) ----------------
T = "Trap"
pat(T, "TRAP 1 ATL BOUNCE", 140, k="x......x..x.....x.....x...x.....", c="........X...............X.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.qx.x", o="......................o.........", b="0------.7-.....0-----.....5-----")
pat(T, "TRAP 2 TRIPLET HATS", 142, k="x.....x...x.....x.......x.x.....", c="........X...............X.......",
    h="x.x.t.x.x.x.t.x.x.x.x.t.x.x.r.x.", b="0-----0---0-----0-------3-3-----")
pat(T, "TRAP 3 MEMPHIS", 145, k="x..x..x...x.....x..x....x.x.....", c="........X...............X.......",
    h="xxxxxxxxxxxxrrxxxxxxxxxxxxxxqqxx", p1="....g.......g.......g.......g...", b="0--0--0---3-----0--0----3-5-----")
pat(T, "TRAP 4 ROLLS", 140, k="x.......x.x.....x.....x.........", c="........X...............X.......",
    h="x.x.x.x.r.r.x.x.x.x.x.x.qqqqx.x.", o="...........o...............o....", b="0-------7-0-----0-----A---------", glide=True)
pat(T, "TRAP 5 BOUNCY", 138, k="x.....x..x......x.....x..x..x...", c="........X...............X.......", s="..............g...............g.",
    h="x.xxx.x.x.xxx.x.x.xxx.x.x.xxr.x.", b="0-----0--0------0-----0--5--5---")
pat(T, "TRAP 6 SPACE", 150, k="x...........x...x.........x.....", c="........X...............X.......",
    h="x.x.x.x.x.x.x.x.t.x.x.x.x.x.t.x.", p2="....o...............o...........", b="0-----------0---0---------3-----", glide=True)
pat(T, "TRAP 7 CLAP STACK", 140, k="x.....x.....x...x.....x.x.......", c="........X.......o.......X......o", s="........X...............X.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0-----0-----0---0-----0-0-------")
pat(T, "TRAP 8 STUTTER", 145, k="x.x.......x.....x.x.....x.x.....", c="........X...............X.......",
    h="x.x.x.rrx.x.x.x.x.x.x.qqx.x.x.x.", r="...x...........x...x...........x", b="0-0-------0-----0-0-----5-5-----")
pat(T, "TRAP 9 OPEN HAT", 138, k="x......x..x.....x......x.x......", c="........X...............X.......",
    h="x.x...x.x.x...x.x.x...x.x.x...x.", o="....o.......o.......o.......o...", b="0------0--0-----0------5-5------")
pat(T, "TRAP 10 FINAL", 148, k="x.....x...x.x...x.....x...x.x...", c="........X...............X...X.XX",
    h="x.x.x.x.x.x.x.x.x.x.x.x.qqqqqqqq", cr="x...............................", b="0-----0---0-0---0-----0---7-7---")

# ---------------- Dark Trap ----------------
DT = "Dark Trap"
pat(DT, "DARK TRAP 1 GRAVE", 140, k="x...........x...x.........x.....", c="........X...............X.......",
    h="x...x.t.x...x...x...x.t.x...x.r.", r="..........g...........g.........", b="0-----------0---0---------A-----", glide=True)
pat(DT, "DARK TRAP 2 HAUNT", 144, k="x.......x.......x.....x.........", s="........X...............X.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.t.x.t.", p1="...o.......o.......o.......o....", b="0-------0-------0-----B---------", glide=True)
pat(DT, "DARK TRAP 3 SMOKE", 135, k="x..........x....x.......x.......", c="........X...............X.......",
    h="x...x...x...x.x.x...x...x...qqqq", o="......o...............o.........", b="0----------0----0-------3-------")
pat(DT, "DARK TRAP 4 VOID", 150, k="x...............x.....x.........", c="........X...............X.......",
    h="x.t.x.x.x.t.x.x.x.t.x.x.x.t.x.x.", b="0---------------0-----C---------", glide=True)
pat(DT, "DARK TRAP 5 RITUAL", 140, k="x.....x.....x...x.....x.....x...", c="........X...............X.......",
    r="....g.......g.......g.......g...", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0-----0-----0---0-----3-----5---")
pat(DT, "DARK TRAP 6 GLOOM", 132, k="x.........x.....x.........x.x...", s="........X...............X.......",
    h="x.x.r.x.x.x.r.x.x.x.r.x.x.x.qqx.", p2="..............o...............o.", b="0---------0-----0---------A-A---")
pat(DT, "DARK TRAP 7 BELLS", 146, k="x.......x.x.....x.......x.......", c="........X...............X.......",
    h="x.x.x.x.t.x.x.x.x.x.x.x.t.x.qqx.", p1="......o.......o.......o.......o.", b="0-------0-0-----0-------5-------", glide=True)
pat(DT, "DARK TRAP 8 CRAWL", 138, k="x...x...........x...x...........", c="........X...............X.......",
    h="x...x...x...x...x...x...x.x.x.x.", o="..........o...............o.....", b="0---0-----------0---3-----------")
pat(DT, "DARK TRAP 9 OMEN", 142, k="x.....x.x.......x.....x...x.....", c="........X.......................", s="........................X.....gX",
    h="x.x.x.x.x.x.x.x.x.x.x.x.qqqqqqqq", b="0-----0-0-------0-----0---A-----")
pat(DT, "DARK TRAP 10 NIGHT", 140, k="x.........x.....x.........x.....", c="........X...............X.......",
    h="t.x.x.x.t.x.x.x.t.x.x.x.t.x.x.x.", cr="x...............................", b="0---------0-----0---------B-----", glide=True)

# ---------------- West Coast (ratchet / Mustard / Ty / Mozzy + 90s) ----------------
W = "West Coast"
pat(W, "WEST COAST 1 RATCHET", 98, k="x.....x.x.......x.....x.x...x...", c="....X.......X.......X.......X...",
    r="....x.......x.......x.......x...", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p1="..............o...............o.", b="0.....0.0.......0.....5.5...7...")
pat(W, "WEST COAST 2 HEY", 100, k="x.....x...x.....x.....x...x.x...", c="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p2="...........X...............X....", b="0.....0...0-----0.....5...5.5---")
pat(W, "WEST COAST 3 SNAP", 96, k="x.......x.x.....x.......x.x.....", r="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="......o...............o.........", b="0-------0.0-----0-------3.3-----")
pat(W, "WEST COAST 4 MOZZY", 92, k="x.....x...x.x...x.....x...x.....", s="....X.......X.......X.......X...",
    h="xxx.xxx.xxx.xxx.xxx.xxx.xxx.xxx.", b="0-----0---0-0---0-----0---5-----")
pat(W, "WEST COAST 5 TY", 104, k="x.....x.x.....x.x.....x.x.......", c="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p1="..o.......o.......o.......o.....", b="0.....0.0.....0.0.....3.3-------")
pat(W, "WEST COAST 6 G-FUNK", 94, 58, k="x.......x.x.....x.......x...x.x.", c="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="..............o...............o.", p1=".o.o.o.o.o.o.o.o.o.o.o.o.o.o.o.o")
pat(W, "WEST COAST 7 LOWRIDER", 92, 56, k="x..x....x.x.....x..x....x.....x.", s="....X.......X.......X.......X...",
    c="....x.......x.......x.......x...", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0..3....0.0-----0..3....5.....7-")
pat(W, "WEST COAST 8 SLAP", 100, k="x.x...x...x.x...x.x...x...x.x...", c="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.r.x.", b="0.0...0...0.0---0.0...5...5.5---")
pat(W, "WEST COAST 9 BAY", 96, k="x.....x.x..x....x.....x.x..x.x..", s="....X.......X.......X.......X...",
    r="..........g...........g.....g...", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0-----0.0..0----0-----0.0..3.3--", glide=True)
pat(W, "WEST COAST 10 CRUISE", 98, k="x.......x.....x.x.......x.....x.", c="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="......o.......o.......o.......o.", p2="...........o...............o....", b="0-------0.....0.0-------5.....5.")

# ---------------- Drill (UK / NY) ----------------
DR = "Drill"
pat(DR, "DRILL 1 UK", 142, k="x.........x.....x.....x.........", s="........X..x...............X....",
    h="x..x..x.x..x..x.x..x..x.x..x.x..", b="0-----------3---0-----5---------", glide=True)
pat(DR, "DRILL 2 NY", 144, k="x......x..x.....x......x...x....", s="........X..x...............X....",
    h="x..x..x.x..x.x..x..x..x.x..x.x..", p1="....o..............o............", b="0------3--0-----0------5---3----", glide=True)
pat(DR, "DRILL 3 SLIDES", 140, k="x.........x.x...x.........x.....", s="........X..x...............X....",
    h="x..x..x.x.t..x..x..x..x.x.t..x..", b="0---------7-5---0---------3-----", glide=True)
pat(DR, "DRILL 4 BROOKLYN", 143, k="x..x......x.....x..x......x.....", s="........X..x...............X..x.",
    h="x.x..x.x..x.x..xx.x..x.x..x.x..x", b="0--3------0-----0--3------5-----", glide=True)
pat(DR, "DRILL 5 DARK", 140, k="x.........x.....x.........x.....", s="........X..x...............X....",
    h="x..x..x.x..x..x.x..x..x.qq.x..x.", r="......g...........g.............", b="0---------A-----0---------3-----", glide=True)
pat(DR, "DRILL 6 BOUNCE", 142, k="x....x....x.....x....x....x.x...", s="........X..x...............X....",
    h="x..x..x.x..x..x.x..x..x.x..x..x.", o="..............o...............o.", b="0----5----0-----0----3----0-0---", glide=True)
pat(DR, "DRILL 7 SKIPPY", 145, k="x.......x.x.....x.......x.....x.", s="........X..x...............X....",
    h="x..xx.x.x..x..x.x..xx.x.x..x.qq.", b="0-------0-7-----0-------5-----3-", glide=True)
pat(DR, "DRILL 8 CHICAGO", 140, k="x..x..x...x.....x..x..x...x.x...", s="........X...............X.......",
    h="x.x.x.x.x.x.x.x.qqqqx.x.x.x.x.x.", b="0--0--0---0-----0--0--3---3-3---")
pat(DR, "DRILL 9 RIM", 141, k="x.........x.....x.........x.....", s="........X..x...............X....",
    r="..x.....x.....x...x.....x.....x.", h="x..x..x.x..x..x.x..x..x.x..x..x.", b="0---------0-----0---------5-----", glide=True)
pat(DR, "DRILL 10 SHUFFLE", 144, k="x......x.x......x......x.x.x....", s="........X..x...............X..g.",
    h="x..x..x.x..x..x.x..x..x.x..x..x.", p2="...............o...............o", b="0------3.0------0------5.5.3----", glide=True)

# ---------------- Amapiano ----------------
A = "Amapiano"
pat(A, "AMAPIANO 1 LOG DRUM", 112, 56, k="x...x...x...x...x...x...x...x...", r="..x.....x..x.......x...x.....x..",
    p1="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", o="..o...o...o...o...o...o...o...o.", b="0.....0.3...0...0.....0.5...3...")
pat(A, "AMAPIANO 2 PRIVATE", 113, 56, k="x.......x.......x.......x.......", c="....x.......x.......x.......x...",
    p1="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx", r="......x.....x.x.......x.....x...", b="0..0..0.....5...0..0..0.....7...", glide=True)
pat(A, "AMAPIANO 3 SHAKER", 112, 58, k="x...x...x...x...x...x...x...x...", p1="xoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxo",
    c="........x...............x.......", r="...x..x....x..x....x..x....x..x.", b="0.......0.0.5.......0.0.....7.5.")
pat(A, "AMAPIANO 4 GROOVE", 114, 56, k="x...x...x...x...x...x...x...x...", s="........g......x........g.......",
    h="..x...x...x...x...x...x...x...x.", p2="....x.......x.......x.....x.....", b="0.....3.....0...0.....5.....3...", glide=True)
pat(A, "AMAPIANO 5 BACARDI", 115, 54, k="x...x...x...x...x...x...x...x...", c="....x.......x.......x.......x...",
    p1="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", o="..x...x...x...x...x...x...x...x.", b="0.0.....0.0.....0.0.....5.5.....")
pat(A, "AMAPIANO 6 SPARSE", 110, 56, k="x.......x.......x.......x.......", r="......x.......x.......x.....x...",
    p1="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0.....0...7.......0.....0...5...", glide=True)
pat(A, "AMAPIANO 7 SGIJA", 112, 58, k="x...x...x...x...x...x...x...x...", c="...........x...............x....",
    r="..x..x..x..x..x...x..x..x..x..x.", p1="xoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxo", b="0...0...0.3.0...0...0...5.3.0...")
pat(A, "AMAPIANO 8 DEEP", 111, 56, k="x...x...x...x...x...x...x...x...", s="........x...............x.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="..o.......o.......o.......o.....", b="0.......3.......0.......5.....3.", glide=True)
pat(A, "AMAPIANO 9 PERC", 113, 56, k="x...x...x...x...x...x...x...x...", p1="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx",
    p2="..o.....o..o......o.....o..o....", lt="......x...............x.........", b="0.....0.5.......0.....0.3.......")
pat(A, "AMAPIANO 10 CLUB", 114, 56, k="x...x...x...x...x...x...x...x...", c="....x.......x.......x.......x...",
    p1="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", o="..o...o...o...o...o...o...o...o.", r="......x.......x.....x.......x...", b="0..0..0.5.......0..0..0.7.....5.", glide=True)

# ---------------- South African RnB ----------------
SA = "South African RnB"
pat(SA, "SA RNB 1 SOFT LOG", 108, 56, k="x.......x.......x.......x.......", r="....x.......x.......x.......x...",
    p1="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0.....3.....0...0.....5.....3...", glide=True)
pat(SA, "SA RNB 2 MELLOW", 106, 56, k="x...x...x...x...x...x...x...x...", c="....x.......x.......x.......x...",
    h="..x...x...x...x...x...x...x...x.", b="0.......0.3.....0.......5.3.....")
pat(SA, "SA RNB 3 SHAKER", 110, 58, k="x.......x.......x.......x.......", s="....x.......x.......x.......x...",
    p1="xoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxo", r="..........x...............x.....", b="0.....0.......7.0.....0.......5.")
pat(SA, "SA RNB 4 SNAP", 105, 56, k="x.....x...x.....x.....x...x.....", r="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0.....0...3-----0.....0...5-----", glide=True)
pat(SA, "SA RNB 5 GROOVE", 108, 56, k="x...x...x...x...x...x...x...x...", c="....x.......x.......x.......x...",
    p1="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx", o="..o.......o.......o.......o.....", b="0...0.....3.....0...0.....5.....")
pat(SA, "SA RNB 6 LATE NIGHT", 104, 58, k="x.......x..x....x.......x..x....", s="....x.......x.......x.......x..g",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0.......0..3----0.......5..3----", glide=True)
pat(SA, "SA RNB 7 KEYS", 107, 56, k="x...x...x...x...x...x...x...x...", r="......x.......x.......x.......x.",
    p1="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", c="....x.......x.......x.......x...", b="0.....0.3.......5.....5.3.......")
pat(SA, "SA RNB 8 RIMSHOT", 109, 56, k="x.......x.......x.......x.......", r="..x...x...x.x...x...x...x...x.x.",
    p1="xoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxo", b="0.......0.0.....0.......7.5.....")
pat(SA, "SA RNB 9 SWAY", 106, 58, k="x.....x.x.......x.....x.x.......", c="....x.......x.......x.......x...",
    h="..x...x...x...x...x...x...x...x.", p2="...........o...............o....", b="0.....0.0.......3.....3.3.......", glide=True)
pat(SA, "SA RNB 10 SUNSET", 108, 56, k="x...x...x...x...x...x...x...x...", s="....x.......x.......x.......x...",
    p1="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx", o="..............o...............o.", b="0...........3...0...........5...", glide=True)

# ---------------- RnB (modern) ----------------
R = "RnB"
pat(R, "RNB 1 SLOW JAM", 70, k="x.....x...x.....x.....x..x......", c="........X...............X.......", r="........x...............x.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.r.x.x.x.", b="0.....0...0-----0.....5..5------")
pat(R, "RNB 2 SNAPS", 74, k="x......x..x.....x......x........", r="........X...............X.......",
    h="xxxxxxxxxxxxxxxxxxxxxxxxqqxxxxxx", o="..............o...............o.", b="0------0..0-----0------5--------", glide=True)
pat(R, "RNB 3 TRAP SOUL", 68, k="x.......x.x.....x.....x.........", c="........X...............X.......",
    h="x.x.x.x.t.x.x.x.x.x.x.x.t.x.x.x.", p1="......g...............g.........", b="0-------0.0-----0-----3---------", glide=True)
pat(R, "RNB 4 VELVET", 72, k="x.....x.....x...x.....x.........", s="........X...............X.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", r="..........g...............g.....", b="0-----0-----0---0-----0---------")
pat(R, "RNB 5 RIDE", 76, k="x.........x.x...x.........x.....", c="........X...............X.......",
    h="x.xxx.xxx.xxx.xxx.xxx.xxx.xxqqx.", b="0---------0.0---0---------5-----")
pat(R, "RNB 6 MIDNIGHT", 66, k="x......x........x......x..x.....", c="........X...............X.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="......o...............o.........", b="0------0--------0------5--3-----", glide=True)
pat(R, "RNB 7 KNOCK", 75, k="x..x......x.....x..x......x.x...", c="........X...............X.......", s="........x...............x.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", b="0..0......0-----0..0......5.5---")
pat(R, "RNB 8 SILK", 70, k="x.......x.......x.....x.x.......", r="........X...............X.......",
    h="x.x.r.x.x.x.r.x.x.x.r.x.x.x.qqx.", b="0-------0-------0-----3.3-------")
pat(R, "RNB 9 LATE", 72, k="x.....x...x.x...x.....x...x.....", c="........X...............X.......",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p2="...o...............o............", b="0-----0---0.0---0-----0---5-----", glide=True)
pat(R, "RNB 10 DRIP", 74, k="x.......x..x....x.......x..x....", c="........X...............X.....g.",
    h="xxx.xxx.xxx.xxx.xxx.xxx.xxx.qqqq", b="0-------0..0----0-------5..5----")

# ---------------- 90s RnB (swung) ----------------
N9 = "90s RnB"
pat(N9, "90s RNB 1 SWING", 92, 60, k="x......x..x.....x......x..x.....", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", r="....x.......x.......x.......x...")
pat(N9, "90s RNB 2 NEW JACK", 104, 62, k="x.....x...x.....x.....x...x.x...", s="....X.......X.......X.......X...",
    h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", o="..............o...............o.")
pat(N9, "90s RNB 3 SNAPS", 88, 60, k="x.......x.x.....x.......x.......", r="....X.......X.......X.......X...",
    h="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx", p1="..........g...............g.....")
pat(N9, "90s RNB 4 SLOW", 76, 58, k="x.....x...x.....x.....x.x.......", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p2="........o...............o.......")
pat(N9, "90s RNB 5 BOUNCE", 96, 62, k="x..x....x.x..x..x..x....x.x.....", s="....X.......X.......X.......X..g",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="......o...............o.........")
pat(N9, "90s RNB 6 SMOOTH", 90, 60, k="x.......x...x...x.......x.......", s="....X.......X.......X.......X...", c="....x.......x.......x.......x...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.")
pat(N9, "90s RNB 7 GHOST", 94, 60, k="x.....x.x.......x.....x.x.......", s="..g.X..g.g..X.g...g.X.g....X...g",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.")
pat(N9, "90s RNB 8 TIMBO", 98, 58, k="x..x..x...x.....x..x..x...x.x...", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.r.x.x.x.x.x.x.x.r.x.x.", p1="...o.......o.......o.......o....", r="..x.......x.......x.......x.....")
pat(N9, "90s RNB 9 SHUFFLE", 86, 64, k="x.......x..x....x.......x..x....", s="....X.......X.......X.......X...",
    h="xxx.xxx.xxx.xxx.xxx.xxx.xxx.xxx.", o="..............o...............o.")
pat(N9, "90s RNB 10 QUIET STORM", 80, 58, k="x.........x.....x.........x.x...", r="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p2="...........o...............o....")

# ---------------- 80s RnB (drum machine) ----------------
E8 = "80s RnB"
pat(E8, "80s RNB 1 LINN", 108, k="x.....x...x.....x.....x...x.....", c="....X.......X.......X.......X...", s="....x.......x.......x.......x...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.")
pat(E8, "80s RNB 2 QUIET", 96, k="x.......x.x.....x.......x.......", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p1="..o...o...o...o...o...o...o...o.")
pat(E8, "80s RNB 3 SEXUAL", 94, k="x..x....x.......x..x....x.x.....", c="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="..............o...............o.", b="0..0....0.......0..0....5.5.....")
pat(E8, "80s RNB 4 BOOGIE", 112, k="x.....x.x.....x.x.....x.x.....x.", c="....X.......X.......X.......X...",
    h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", p1="..x...x...x...x...x...x...x...x.")
pat(E8, "80s RNB 5 SLOW", 84, k="x.......x.......x.......x..x....", s="....X.......X.......X.......X...", c="....x.......x.......x.......x...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.")
pat(E8, "80s RNB 6 COWBELL", 104, k="x.....x...x.....x.....x...x.....", c="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p2="x..x..x...x.x...x..x..x...x.x...")
pat(E8, "80s RNB 7 JAM", 100, k="x..x......x.....x..x......x.x...", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="......o...............o.........", lt="..............................xx")
pat(E8, "80s RNB 8 STREET", 106, k="x.....x...x.x...x.....x...x.....", c="....X.......X.......X.......X...", r="..x.......x.......x.......x.....",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.")
pat(E8, "80s RNB 9 SMOOTH", 92, k="x.......x..x....x.......x..x....", s="....X.......X.......X.......X...",
    h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", p1="....o.......o.......o.......o...")
pat(E8, "80s RNB 10 DANCE", 116, k="x...x...x...x...x...x...x...x...", c="....X.......X.......X.......X...",
    h="..x...x...x...x...x...x...x...x.", o="..o...o...o...o...o...o...o...o.")

# ---------------- 80s Pop ----------------
E8P = "80s Pop"
pat(E8P, "80s POP 1 GATED", 118, k="x.......x.x.....x.......x.x.....", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", cr="x...............................")
pat(E8P, "80s POP 2 DRIVE", 124, k="x...x...x...x...x...x...x...x...", s="....X.......X.......X.......X...",
    h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
pat(E8P, "80s POP 3 TOMS", 120, k="x.......x.......x.......x.......", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", ht="........................x.x.....", lt="............................x.x.")
pat(E8P, "80s POP 4 SYNTH", 112, k="x.....x...x.....x.....x...x.....", c="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="......o.......o.......o.......o.")
pat(E8P, "80s POP 5 ARENA", 116, k="x.....x.x.......x.....x.x.......", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", cr="x...............x...............")
pat(E8P, "80s POP 6 NEW WAVE", 128, k="x...x...x...x...x...x...x...x...", s="....X.......X.......X.......X...",
    h="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx", p1="..o...o...o...o...o...o...o...o.")
pat(E8P, "80s POP 7 BALLAD", 84, k="x.........x.....x.........x.....", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", lt="..............................x.", ht="............................x...")
pat(E8P, "80s POP 8 CLAPS", 120, k="x.......x.x.....x.......x.x.....", c="....X.......X.......X.......X...", s="....X.......X.......X.......X...",
    h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
pat(E8P, "80s POP 9 DANCE", 122, k="x...x...x...x...x...x...x...x...", c="....X.......X.......X.......X...",
    h="..x...x...x...x...x...x...x...x.", o="..o...o...o...o...o...o...o...o.", p2="x..x..x.x..x..x.x..x..x.x..x..x.")
pat(E8P, "80s POP 10 FILL", 118, k="x.......x.x.....x.......x.x.....", s="....X.......X.......X.......XXXX",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.....", ht="........................x.x.....", lt="............................xx..")

# ---------------- 80s Funk ----------------
F = "80s Funk"
pat(F, "80s FUNK 1 GROOVE", 104, 54, k="x..x......x.x...x..x....x.x.....", s="....X..g.g..X...g...X..g.g..X...",
    h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", o="..............o...............o.")
pat(F, "80s FUNK 2 SLAP", 108, 54, k="x.x...x...x.....x.x...x...x.x...", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p2="..x.......x.......x.......x.....")
pat(F, "80s FUNK 3 GHOSTS", 100, 56, k="x.....x...x.....x.....x.x.......", s="..g.X.g..g.gX.g...g.X.g..g.gX.g.",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="......o...............o.........")
pat(F, "80s FUNK 4 CLAP", 112, k="x..x..x...x.....x..x..x...x.x...", c="....X.......X.......X.......X...",
    h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", p1="..o...o...o...o...o...o...o...o.")
pat(F, "80s FUNK 5 MINNEAPOLIS", 116, k="x.....x.x.....x.x.....x.x.....x.", c="....X.......X.......X.......X...", s="....x.......x.......x.......x...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="..o...o...o...o...o...o...o...o.")
pat(F, "80s FUNK 6 STRUT", 98, 56, k="x...x.....x.x...x...x.....x.x...", s="....X.......X..g....X.......X...",
    h="xxx.xxx.xxx.xxx.xxx.xxx.xxx.xxx.", o="...o...o...o...o...o...o...o...o")
pat(F, "80s FUNK 7 COWBELL", 106, k="x..x..x...x.x...x..x..x...x.x...", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p2="x.x..x.x..x.x..xx.x..x.x..x.x..x")
pat(F, "80s FUNK 8 SYNCOPATE", 110, 54, k="x.......x..x..x.x.......x..x..x.", s="....X..g....X..g....X..g....X..g",
    h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
pat(F, "80s FUNK 9 TOMS", 102, 54, k="x..x......x.....x..x......x.....", s="....X.......X.......X.......X...",
    h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", ht="..............x...............x.", lt="...............x...............x")
pat(F, "80s FUNK 10 PARTY", 114, k="x...x...x...x...x...x...x...x...", c="....X.......X.......X.......X...",
    h="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx", o="..o...o...o...o...o...o...o...o.", p1="...x.......x.......x.......x....")

# ---------------- EDM ----------------
ED = "EDM"
for i, (name, bpm, extra) in enumerate([
    ("EDM 1 MAIN ROOM", 128, dict(c="....X.......X.......X.......X...", o="..x...x...x...x...x...x...x...x.", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.")),
    ("EDM 2 BIG ROOM", 128, dict(c="....X.......X.......X.......X...", s="....X.......X.......X.......X...", o="..x...x...x...x...x...x...x...x.", cr="x...............................")),
    ("EDM 3 BUILD", 128, dict(s="x...x...x...x...x.x.x.x.xxxxXXXX", h="x.x.x.x.x.x.x.x.xxxxxxxxxxxxxxxx", cr="x...............................")),
    ("EDM 4 FUTURE", 150, dict(k2=None, c="........X...............X.......", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p1="..o.....o..o......o.....o..o....")),
    ("EDM 5 PROG", 126, dict(c="....x.......x.......x.......x...", o="..x...x...x...x...x...x...x...x.", p1="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx")),
    ("EDM 6 ELECTRO", 128, dict(c="....X.......X.......X.......X...", h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", p2="..x..x....x..x....x..x....x..x..")),
    ("EDM 7 FESTIVAL", 130, dict(c="....X.......X.......X.......X...", s="....x.......x.......x.......x...", o="..x...x...x...x...x...x...x...x.", ht="............................xx..", lt="..............................xx")),
    ("EDM 8 MELODIC", 124, dict(c="....x.......x.......x.......x...", h="..x...x...x...x...x...x...x...x.", r="......x.......x.......x.....x...")),
    ("EDM 9 BOUNCE", 128, dict(c="....X.......X.......X.......X...", o="..x...x...x...x...x...x...x...x.", p1=".x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x")),
    ("EDM 10 DROP", 128, dict(c="....X.......X.......X.......X...", s="....X.......X.......X.......X...", o="..x...x...x...x...x...x...x...x.", cr="x...............x...............", b="..0...0...0...0...0...0...0...0.")),
]):
    lanes = {k: v for k, v in extra.items() if v is not None and k != "k2"}
    if "k2" in extra:   # future bass: half-time kick
        lanes["k"] = "x.....x...x.....x.....x...x.x..."
    else:
        lanes.setdefault("k", "x...x...x...x...x...x...x...x...")
    pat(ED, name, bpm, **lanes)

# ---------------- House ----------------
H = "House"
FOUR = "x...x...x...x...x...x...x...x..."
pat(H, "HOUSE 1 CLASSIC", 124, k=FOUR, c="....X.......X.......X.......X...", o="..x...x...x...x...x...x...x...x.", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.")
pat(H, "HOUSE 2 DEEP", 122, 56, k=FOUR, r="....x.......x.......x.......x...", o="..x...x...x...x...x...x...x...x.", p1="xoxoxoxoxoxoxoxoxoxoxoxoxoxoxoxo")
pat(H, "HOUSE 3 GARAGE", 128, 60, k="x.......x.x.....x.......x.....x.", s="....X.......X.......X.......X...", h="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx", o="..o...o...o...o...o...o...o...o.")
pat(H, "HOUSE 4 CHICAGO", 120, k=FOUR, c="....X.......X.......X.......X...", h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", o="..x...x...x...x...x...x...x...x.", p2="...x......x....x...x......x...x.")
pat(H, "HOUSE 5 TECH", 125, k=FOUR, c="....x.......x.......x.......x...", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", r="...x..x....x..x....x..x....x..x.", b="..0...0...0.0...0...0...0...0.0.")
pat(H, "HOUSE 6 DISCO", 120, 54, k=FOUR, c="....X.......X.......X.......X...", o="..x...x...x...x...x...x...x...x.", p1="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", ht="..........................x.x.x.")
pat(H, "HOUSE 7 AFRO", 122, 56, k=FOUR, r="..x...x..x..x.x...x...x..x..x.x.", p1="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", lt="......x.......x.......x.......x.", o="..o...o...o...o...o...o...o...o.")
pat(H, "HOUSE 8 SOULFUL", 123, 56, k=FOUR, c="....X.......X.......X.......X...", s="....x.......x.......x.......x...", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", o="..x...x...x...x...x...x...x...x.")
pat(H, "HOUSE 9 JACKIN", 126, k=FOUR, c="....X..x....X.......X..x....X...", o="..x...x...x...x...x...x...x...x.", h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
pat(H, "HOUSE 10 BASS", 124, k=FOUR, c="....X.......X.......X.......X...", o="..x...x...x...x...x...x...x...x.", b="..0-..0-..3-..0-..0-..0-..5-..3-")

# ---------------- Techno ----------------
TE = "Techno"
pat(TE, "TECHNO 1 WAREHOUSE", 130, k=FOUR, h="..x...x...x...x...x...x...x...x.", r="...x..x....x..x....x..x....x..x.", b="..0.0...0.0...0.0...0.0...0.0...")
pat(TE, "TECHNO 2 RUMBLE", 132, k=FOUR, h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", c="............X...............X...", b=".000.000.000.000.000.000.000.000")
pat(TE, "TECHNO 3 BERLIN", 128, k=FOUR, o="..x...x...x...x...x...x...x...x.", h="x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.", p2="......x.......x.....x.......x...")
pat(TE, "TECHNO 4 DETROIT", 126, k=FOUR, c="....X.......X.......X.......X...", h="x.xxx.xxx.xxx.xxx.xxx.xxx.xxx.xx", p1="..o..o..o.o..o....o..o..o.o..o..")
pat(TE, "TECHNO 5 HYPNOTIC", 134, k=FOUR, r="..x.....x..x......x.....x..x....", h="..x...x...x...x...x...x...x...x.", lt=".......x.......x.......x.......x")
pat(TE, "TECHNO 6 INDUSTRIAL", 136, k="x...x...x...x.x.x...x...x...x.x.", s="....x.......x.......x.......x...", h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", cr="x...............................")
pat(TE, "TECHNO 7 MINIMAL", 126, k=FOUR, r="...x.......x.......x...x...x....", h="..x...x...x...x...x...x...x...x.", p1="x.......x.......x.......x.......")
pat(TE, "TECHNO 8 ACID", 130, k=FOUR, c="....x.......x.......x.......x...", o="..x...x...x...x...x...x...x...x.", b="0.0.c.0.0.3.0.c.0.0.c.0.5.0.3.0.")
pat(TE, "TECHNO 9 PEAK", 138, k=FOUR, c="....X.......X.......X.......X...", h="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", o="..x...x...x...x...x...x...x...x.", r="..x..x....x..x....x..x....x..x..")
pat(TE, "TECHNO 10 DUB", 124, 54, k=FOUR, r="......x.......x.......x.....x...", h="..x...x...x...x...x...x...x...x.", p2="...o.......o.......o.......o....", b="..0.....0.......0.....0.0.......")

# ---------------- checks and output ----------------

# ================= VINTAGE STYLES (acoustic kits: boom bap, jazz, neo soul, soul R&B) =================
def two(bar):            # same bar twice (2 bars, 32 steps)
    assert len(bar) == 16, bar
    return bar * 2
RIDE = two("x...x..xx...x..x")          # jazz "spang-a-lang": 1, 2 (a), 3, 4 (a)
FOOT = two("....x.......x...")          # hi-hat foot on 2 and 4
BACK = two("....X.......X...")          # backbeat
H8 = two("x.x.x.x.x.x.x.x.")
SHAKE = two("ogogogogogogogog")

# ---------------- Boom Bap (MPC swing, knocking kicks, crack on 2 & 4) ----------------
BB = "Boom Bap"
pat(BB, "BOOM BAP 1 CLASSIC", 90, 58, k="X......x..x.....X......x..x..x..", s=BACK, h=H8)
pat(BB, "BOOM BAP 2 DUSTY GHOSTS", 88, 60, k="X.....x...x.....X.....x..x......", s="....X..g...gX.......X..g....X.g.", h=two("x.xgx.xgx.xgx.xg"))
pat(BB, "BOOM BAP 3 HEAD NOD", 93, 56, k="X..x......x.....X..x....x.x.....", s=BACK, h=H8, o="..............x...............x.")
pat(BB, "BOOM BAP 4 KNOCK & RIM", 92, 57, k="X.......x.x.....X.....x...x.....", s=BACK, r="..g.......g.......g.......g...g.", h=two("x...x...x...x..."))
pat(BB, "BOOM BAP 5 SHAKER", 86, 62, k="X......x..x...x.X......x.x......", s=BACK, h=H8, p1=SHAKE)
pat(BB, "BOOM BAP 6 CHOP", 95, 55, k="X.x.......x..x..X.x.....x.......", s="....X.......X.......X.....g.X...", c="............x...............x...", h=H8)
pat(BB, "BOOM BAP 7 LAZY", 84, 64, k="X......x.......x.X......x..x....", s="....X.....g.X.......X.....g.X...", h=two("x..xx..xx..xx..x"))
pat(BB, "BOOM BAP 8 BREAK", 96, 55, k="X.x.......xx....X.x.......x.....", s="....X..g.g..X.......X..g.g..X..g", h=H8, o="......x...............x.........")
pat(BB, "BOOM BAP 9 RIDE", 90, 58, k="X......x..x.....X......x.....x..", s=BACK, cr=two("x...x...x...x..."), h=two("..x...x...x...x."))
pat(BB, "BOOM BAP 10 DARK", 82, 60, k="X.........x.....X.......x..x....", s=BACK, h=H8, p2="..............x...............x.",
    b="0---------3-----0-------5--3----")

# ---------------- Jazz (swung ride, foot hat on 2 & 4, feathered kick, comping) ----------------
J = "Jazz"
pat(J, "JAZZ 1 SWING RIDE", 120, 66, cr=RIDE, h=FOOT, k=two("g...g...g...g..."), s="......g.....g.........g......g..")
pat(J, "JAZZ 2 BRUSHES", 96, 64, cr=RIDE, h=FOOT, p1=two("oggoggoggoggoggo"), k=two("g.......g......."))
pat(J, "JAZZ 3 BEBOP", 160, 62, cr=RIDE, h=FOOT, s="...g..x......g....g....x...g..g.", k="..........x.............x.......")
pat(J, "JAZZ 4 JAZZ HOP", 88, 60, k="X......x..x.....X......x..x.....", s=BACK, cr=RIDE, h=FOOT)
pat(J, "JAZZ 5 BOSSA", 130, 50, k=two("x..x....x..x...."), r="x..x..x...x..x..x..x..x...x..x..", h=H8)
pat(J, "JAZZ 6 BALLAD", 70, 66, cr=RIDE, p1=two("o.g.o.g.o.g.o.g."), h=FOOT, k=two("g.......g......."))
pat(J, "JAZZ 7 FUNK", 100, 58, k="X..x..x...x.....X..x....x.x.....", s="....X..g.g..X..g....X..g.g..X..g", h=H8, cr=two("x.......x......."))
pat(J, "JAZZ 8 SHUFFLE", 110, 66, cr=two("x.x.x.x.x.x.x.x."), k=two("X.......x......."), s="....X.......X.......X.......X..g")
pat(J, "JAZZ 9 LO-FI", 82, 62, k="X.....x...x.....X.......x.x.....", s=BACK, cr=RIDE, r=two("......g.......g."))
pat(J, "JAZZ 10 UPTEMPO", 150, 60, cr=RIDE, h=FOOT, k=two("g...g...g...g..."), s="..g.....g..x.......g....x..g....")

# ---------------- Neo Soul (Dilla / D'Angelo: lazy kicks, late snares, rims, ghosts) ----------------
N = "Neo Soul"
pat(N, "NEO SOUL 1 DILLA", 88, 62, k="X......x..x.x...X.....x....x....", s=BACK, h=two("x.xgx.xgx.xgx.xg"))
pat(N, "NEO SOUL 2 RIM KEEPER", 82, 60, k="X.........x..x..X.......x.......", r=BACK, h=H8, p1=SHAKE)
pat(N, "NEO SOUL 3 VOODOO", 78, 64, k="X......x...x....X.....x...x.....", s=two("....X..g....X..g"), h=two("x..x..x.x..x..x."))
pat(N, "NEO SOUL 4 LATE SNARE", 85, 66, k="X.....x...x.....X.....x.....x...", s=two(".....X.......X.."), h=H8)
pat(N, "NEO SOUL 5 OPEN HAT", 90, 58, k="X..x......x.....X..x....x.x.....", s=BACK, h=H8, o="......x.......x.......x.......x.")
pat(N, "NEO SOUL 6 BROKEN", 92, 56, k="X..x...x..x.....X..x...x.....x..", s="....X.....g.X.......X.....g.X...", h=two("xgxgxgxgxgxgxgxg"))
pat(N, "NEO SOUL 7 SOFT CLAP", 80, 62, k="X.......x.x.....X.......x...x...", c=two("....o.......o..."), s=two("....x.......x..."), h=H8,
    b="0-------5--3----0-------7--5----", glide=True)
pat(N, "NEO SOUL 8 RIDE", 84, 60, k="X......x..x.....X......x...x....", s=BACK, cr=H8, r=two("..g.......g....."))
pat(N, "NEO SOUL 9 SHAKER POCKET", 86, 64, p1=two("xgogxgogxgogxgog"), k="X.....x...x.....X.....x.x.......", s=BACK, h=two("..x...x...x...x."))
pat(N, "NEO SOUL 10 SLOW JAM", 72, 66, k="X.......x..x....X.......x.......", s=BACK, h=H8, o="..............x...............x.", p2="...............x...............x")

# ---------------- Soul RnB (Motown, 70s, quiet storm, Philly) ----------------
SR = "Soul RnB"
pat(SR, "SOUL RNB 1 MOTOWN", 104, 52, k="x.......x.x.....x.......x.x.....", s=BACK, p1=two("....x.......x..."), h=H8)
pat(SR, "SOUL RNB 2 70s GROOVE", 98, 54, k="X..x....x.x.....X..x....x..x....", s=two("....X..g....X..g"), h=two("x.xxx.xxx.xxx.xx"), o="..............x...............x.")
pat(SR, "SOUL RNB 3 SLOW JAM", 68, 58, k="X.......x..x....X.......x..x....", s=BACK, h=H8, r="..............g...............g.")
pat(SR, "SOUL RNB 4 QUIET STORM", 76, 56, k="X......x..x.....X......x........", s=BACK, h=H8, cr="x...............x...............")
pat(SR, "SOUL RNB 5 BREAK SOUL", 100, 55, k="X.x.......xx.x..X.x.......x.....", s="....X..g.g..X.......X..g.g..X..g", h=H8)
pat(SR, "SOUL RNB 6 GOSPEL PUSH", 94, 60, k="X.....x...x..x..X.....x...x.....", s=BACK, c=BACK, h=H8, o="......x...............x.........")
pat(SR, "SOUL RNB 7 SHAKER", 88, 58, p1=SHAKE, k="X......x..x.....X......x..x.x...", s=BACK, h=two("x...x...x...x..."))
pat(SR, "SOUL RNB 8 PHILLY", 112, 50, k=two("x...x...x...x..."), s=BACK, o=two("..x...x...x...x."), h=two("x...x...x...x..."))
pat(SR, "SOUL RNB 9 HALF TIME", 72, 60, k="X.......x.......X.....x.x.......", s=two("........X......."), h=H8)
pat(SR, "SOUL RNB 10 RIDE", 92, 56, cr=H8, k="X..x......x.....X..x......x.x...", s=BACK)


# ---------------- Detroit (2020+ Detroit / Michigan rap: fast 150-172, hard snare + clap on 2 & 4,
# off-beat "neck-breaking" kicks the 808 follows, sparse hats, rim / perc accents, few rolls) ----------------
DT = "Detroit"
BB2 = two("....X.......X...")
pat(DT, "DETROIT 1 NECK BREAKER", 162, k="x..x..x...x...x.x..x..x...xx....", s=BB2, c=BB2, h=two("x...x...x...x..."),
    b="0--0--0---0---5-0--0--0---33----")
pat(DT, "DETROIT 2 SCAM BOUNCE", 158, k="x.x..x....x..x..x.x..x...x..x...", s=BB2, c=BB2, r="..x.......x.......x.......x.....",
    h=two("x.x.x.x.x.x.x.x."), b="0-0--0----3--3--0-0--5---3--0---")
pat(DT, "DETROIT 3 FLINT OFFBEAT", 166, k="..x..x...x..x.....x..x...x...x..", s=BB2, c=BB2, h=two("....x.......x..."),
    p1="x.......x.......x.......x.......", b="..0--0---0--5.....0--3---0---0--")
pat(DT, "DETROIT 4 SAMPLE CHOP", 150, k="x......x..x.....x..x......x.....", s=BB2, c=BB2, h=two("x.x.x.x.x.x.x.x."),
    o="..............x...............x.", b="0------0--3-----0--0------5-----")
pat(DT, "DETROIT 5 MUTTER", 156, k="x..x......x..x..x..x.....x.x....", s=BB2, r=two("......x.......x."), h=two("x...x...x...x..."),
    b="0--0------3--3--0--0-----5-3----")
pat(DT, "DETROIT 6 SKIP KICK", 168, k="x.x...x.x..x....x.x...x..x.x....", s=BB2, c=BB2, h="x.x.x.x.x.x.x.t.x.x.x.x.x.x.x.t.",
    b="0-0---0-0--3----0-0---5--3-3----")
pat(DT, "DETROIT 7 COLD PIANO", 152, k="x.......x.x.....x.....x...x.....", s=BB2, c=BB2, h=two("x.....x.....x..."),
    p2="......o...............o.........", b="0-------3-3-----0-----5---3-----")
pat(DT, "DETROIT 8 HARD DRUMS", 172, k="x..x..x..x..x...x..x..x..x.x....", s=BB2, c=BB2, h=two("x.x.x.x.x.x.x.x."),
    r="...x.......x.......x.......x....", b="0--0--0--0--3---0--0--5--3-3----")
pat(DT, "DETROIT 9 SLOW CRUISE", 150, k="x.........x..x..x.......x.x.....", s=BB2, c=BB2, h=two("x...x...x...x..."),
    o="......o...............o.........", b="0---------3--3--0-------5-3-----", glide=True)
pat(DT, "DETROIT 10 PERC TALK", 160, k="x..x....x.x..x..x..x....x...x...", s=BB2, c=BB2, p1=two("..x...x...x..x.."),
    h=two("x.......x......."), b="0--0----3-3--3--0--0----5---3---")


# ---------------- More Danger Patterns (Tyrone's Sampley cheat book) and two KXVI-style trap patterns ----------------
def st(n, *hits, ch="x"):
    """A lane of n steps with `ch` at the given step numbers (0-based)."""
    l = ["."] * n
    for h in hits: l[h] = ch
    return "".join(l)
pat(D, "DRILL 1", 142, k=st(32, 0, 22), h=st(32, 0, 3, 6, 8, 10, 11, 12, 13, 14, 16, 19, 22, 23, 24, 28, 29, 30, 31),
    s=st(32, 8, 28, ch="X"), p1=st(32, 0, 3, 6, 14, 16, 19), r=st(32, 26), o=st(32, 4))
pat(D, "DRILL 2", 142, k=st(32, 0, 20, 24, 26), h=st(32, 0, 3, 6, 8, 11, 12, 13, 14, 15, 16, 19, 22, 24, 27, 28, 29, 30, 31),
    s=st(32, 8, 28, ch="X"), p1=st(32, 18, 30), p2=st(32, 1, 3, 6, 20), o=st(32, 2, 5))
pat(D, "HIP HOP SWING 1", 90, 56, o=st(16, 7, 13), h=st(16, 0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 14, 15),
    s=st(16, 4, 7, 9, 11, 12, 15), k=st(16, 0, 2, 10, 13))
pat(D, "HIP HOP SWING 2", 90, 56, h=st(16, 2, 6, 10, 14), s=st(16, 4, 12, ch="X"), k=st(16, 0, 7, 15))
pat(D, "HIP HOP SWING 3", 90, 56, ht=st(16, 2, 3, 10, 11), o=st(16, 6, 14), h=st(16, 2, 3, 7, 8, 9, 14, 15),
    s=st(16, 4, 12, ch="X"), r=st(16, 4, 12), k=st(16, 0, 2, 5, 8, 11, 15))
pat(D, "HIP HOP SWING 4", 85, 60, p1=st(16, 0), h=st(16, 2, 4, 6, 8, 10, 12, 14), c=st(16, 4, 12), s=st(16, 12, ch="X"),
    k=st(16, 0, 7, 8, 10, 13, 15))
pat(D, "HIP HOP SWING 5", 85, 60, o=st(16, 6, 14), p1=st(16, 4, 12), h=st(16, *range(16)), c=st(16, 1),
    s=st(16, 4, 7, 12, ch="X"), k=st(16, 0, 11, 13, 14))
pat(D, "HIP HOP SWING 6", 85, 60, h=st(16, 0, 2, 4, 6, 8, 10, 12, 14), s=st(16, 4, 12, ch="X"), k=st(16, 0, 1, 7, 10, 14))
pat(D, "HIP HOP SWING 7", 95, 60, p1=st(16, 0), h=st(16, 0, 2, 4, 6, 8, 10, 12, 14), s=st(16, 4, 12, ch="X"),
    k=st(16, 0, 7, 8, 10, 13, 15))
pat(D, "HIP HOP SWING 8", 95, 60, h=st(16, 0, 2, 4, 6, 8, 10, 12, 14), c=st(16, 4, 12), s=st(16, 10, 15, ch="X"),
    k=st(16, 0, 2, 5, 6, 7))
pat(D, "HIP HOP SWING 9", 95, 60, o=st(16, 14), h=st(16, 0, 2, 4, 6, 8, 10, 12), s=st(16, 4, 7, 12, ch="X"), k=st(16, 0, 10))
pat(D, "HIP HOP SWING 10", 95, 60, o=st(16, 15), h=st(16, 0, 2, 4, 6, 8, 10, 12, 14), s=st(16, 4, 7, 12, ch="X"), k=st(16, 0, 10))
pat(D, "HIP HOP RIDE", 90, 60, cr=st(16, 0, 4, 8, 12), r=st(16, 10), k=st(16, 0, 2, 6))
pat(D, "BOOM BAP 90 1", 90, 60, h=st(16, 2, 6, 9), s=st(16, 4, 7, 11, ch="X"), k=st(16, 0, 8))
pat(D, "BOOM BAP 90 2", 90, 60, h=st(16, 2, 6, 10), s=st(16, 4, 8, 11, ch="X"), k=st(16, 0, 9, 13, 14))
pat(D, "BOOM BAP 90 3", 90, 60, h=st(16, 2, 10), s=st(16, 4, 11, ch="X"), k=st(16, 0, 8))
pat(D, "BOOM BAP 90 4", 90, 60, h=st(16, 2, 6, 10), s=st(16, 4, 7, 11, ch="X"), k=st(16, 0, 8))
pat(D, "BOOM BAP 90 5", 90, 60, h=st(16, 2, 6, 9), s=st(16, 4, 11, ch="X"), k=st(16, 0, 7, 8))
# KXVI-style trap (FL channel rack, 2 bars): 808 leads, clap + snare stacked on 3, bounce snare, 8th hats
pat(T, "TRAP 11 ATL BOUNCE SNARE", 130, b="0-------------" + "0-----" * 3, c=st(32, 8, 24, ch="X"),
    s=st(32, 8, 24, ch="X") [:14] + "o" + st(32, 8, 24, ch="X")[15:18] + "o" + st(32, 8, 24, ch="X")[19:],
    h=st(32, *range(0, 32, 2)), o=st(32, 0, 24))
pat(T, "TRAP 12 ATL 808 PUSH", 130, b="0-----0-----0-------------------", c=st(32, 8, 24, ch="X"),
    s=st(32, 8, 24, ch="X")[:14] + "o" + st(32, 8, 24, ch="X")[15:18] + "o" + st(32, 8, 24, ch="X")[19:],
    h=st(32, *[i for i in range(0, 32, 2) if i != 10]), o=st(32, 0, 24))


# ---------------- Artist styles (Oct 14): named for the sound, not the artist ----------------
def rep(unit, n=32): return (unit * (n // len(unit) + 1))[:n]
def put(lane, *pairs):
    l = list(lane)
    for i, ch in pairs: l[i] = ch
    return "".join(l)
def bass(*notes, n=32):
    """808 line: (step, note char, length in steps)."""
    l = ["."] * n
    for step, ch, ln in notes:
        l[step] = ch
        for j in range(step + 1, min(n, step + ln)): l[j] = "-"
    return "".join(l)
HALF = st(32, 8, 24, ch="X")                     # half-time backbeat (beat 3 of each bar)
BACK = st(32, 4, 12, 20, 28, ch="X")             # 2 and 4

# TORONTO NIGHTS (Drake): dark half-time, muffled kicks, sparse hats, long sliding 808s
TN = "Toronto Nights"
pat(TN, "TORONTO NIGHTS 1 SIX", 136, k=st(32, 0, 10, 16, 26), c=HALF, h=rep("x...x..."), b=bass((0, "0", 10), (10, "0", 6), (16, "3", 10), (26, "5", 6)), glide=True)
pat(TN, "TORONTO NIGHTS 2 MIDNIGHT", 134, k=st(32, 0, 7, 16, 22), s=HALF, h=rep("x.x.x.x.x.x.x.xq"), o=st(32, 14), b=bass((0, "0", 7), (7, "0", 9), (16, "A", 6), (22, "0", 10)), glide=True)
pat(TN, "TORONTO NIGHTS 3 QUEEN STREET", 140, k=st(32, 0, 3, 10, 16, 19), c=HALF, r=st(32, 15, 31), h=rep("x...x...x...x.r."), b=bass((0, "0", 3), (3, "0", 7), (10, "7", 6), (16, "0", 3), (19, "5", 13)), glide=True)
pat(TN, "TORONTO NIGHTS 4 COLD NIGHT", 132, k=st(32, 0, 11, 16), s=HALF, p1=st(32, 6, 22), h=rep("x.....x.x.....x."), b=bass((0, "0", 11), (11, "C", 5), (16, "0", 16)), glide=True)
pat(TN, "TORONTO NIGHTS 5 BOUNCE", 138, k=st(32, 0, 6, 10, 16, 22, 26), c=HALF, h=rep("x.x.x.x.t.x.x.x."), o=st(32, 6, 22), b=bass((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 6), (22, "0", 4), (26, "5", 6)))
pat(TN, "TORONTO NIGHTS 6 SLIDE", 136, k=st(32, 0, 13, 16, 29), s=HALF, c=st(32, 8, 24), h=rep("x.x.x.xxx.x.x.x."), b=bass((0, "0", 13), (13, "7", 3), (16, "0", 13), (29, "c", 3)), glide=True)
pat(TN, "TORONTO NIGHTS 7 DRIFT", 128, k=st(32, 0, 9, 16, 25), c=HALF, r=st(32, 20), h=rep("x...x...x...x..."), p2=st(32, 12, 28), b=bass((0, "0", 9), (9, "B", 7), (16, "0", 9), (25, "3", 7)), glide=True)
pat(TN, "TORONTO NIGHTS 8 WINTER", 140, k=st(32, 0, 2, 10, 16, 18), s=HALF, h=rep("x.x.x.x.x.x.x.x.").replace("x.x.x.x.x.x.x.x.", "x.x.x.x.x.x.x.x.", 1), o=st(32, 30), b=bass((0, "0", 2), (2, "0", 8), (10, "5", 6), (16, "0", 2), (18, "0", 14)))
pat(TN, "TORONTO NIGHTS 9 DUNDAS", 136, k=st(32, 0, 6, 11, 16, 27), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (13, "t"), (29, "q")), b=bass((0, "0", 6), (6, "3", 5), (11, "5", 5), (16, "0", 11), (27, "A", 5)), glide=True)
pat(TN, "TORONTO NIGHTS 10 LAKESHORE", 130, k=st(32, 0, 16, 23), s=HALF, h=rep("x.......x......."), p1=st(32, 4, 12, 20, 28), b=bass((0, "0", 16), (16, "0", 7), (23, "5", 9)), glide=True)

# LATE NIGHT RNB (PARTYNEXTDOOR): slow dark RnB, snaps and rims, swung hats, gliding 808
LN = "Late Night RnB"
pat(LN, "LATE NIGHT RNB 1 AFTER HOURS", 72, 54, k=st(32, 0, 7, 10, 16, 23), c=HALF, r=st(32, 8, 24), h=rep("x.x.x.x.x.x.x.xr"), b=bass((0, "0", 7), (7, "0", 3), (10, "3", 6), (16, "0", 7), (23, "5", 9)), glide=True)
pat(LN, "LATE NIGHT RNB 2 SNAPS", 70, 56, k=st(32, 0, 10, 16, 26), r=HALF, h=rep("xxxxxxxxxxxxxxxx"), o=st(32, 14, 30), b=bass((0, "0", 10), (10, "A", 6), (16, "0", 10), (26, "3", 6)), glide=True)
pat(LN, "LATE NIGHT RNB 3 NEON", 74, 54, k=st(32, 0, 6, 16, 19, 22), s=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (14, "t"), (30, "t")), p1=st(32, 12, 28, ch="g"), b=bass((0, "0", 6), (6, "0", 10), (16, "5", 3), (19, "3", 3), (22, "0", 10)), glide=True)
pat(LN, "LATE NIGHT RNB 4 SLOW MOTION", 68, 58, k=st(32, 0, 11, 16), c=HALF, r=st(32, 8, 24, 30, ch="o"), h=rep("x...x...x...x..."), b=bass((0, "0", 11), (11, "7", 5), (16, "0", 16)), glide=True)
pat(LN, "LATE NIGHT RNB 5 CITY LIGHTS", 76, 55, k=st(32, 0, 3, 10, 16, 26), c=HALF, h=rep("x.xxx.xxx.xxx.xx"), b=bass((0, "0", 3), (3, "0", 7), (10, "3", 6), (16, "0", 10), (26, "B", 6)), glide=True)
pat(LN, "LATE NIGHT RNB 6 CANDLES", 72, 56, k=st(32, 0, 9, 16, 25), r=HALF, s=st(32, 8, 24, ch="o"), h=rep("x.x.x.x.x.x.x.x."), o=st(32, 6, 22), b=bass((0, "0", 9), (9, "5", 7), (16, "0", 9), (25, "7", 7)), glide=True)
pat(LN, "LATE NIGHT RNB 7 LATE TEXT", 70, 54, k=st(32, 0, 7, 16, 18, 23), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (12, "r"), (28, "q")), b=bass((0, "0", 7), (7, "3", 9), (16, "0", 2), (18, "0", 5), (23, "A", 9)), glide=True)
pat(LN, "LATE NIGHT RNB 8 PENTHOUSE", 75, 57, k=st(32, 0, 10, 13, 16, 26), c=HALF, r=st(32, 15, 31, ch="g"), h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 10), (10, "0", 3), (13, "5", 3), (16, "0", 16)))
pat(LN, "LATE NIGHT RNB 9 RAIN", 66, 58, k=st(32, 0, 16, 22), s=HALF, r=st(32, 8, 24), h=rep("x.....x.x.....x."), p1=st(32, 2, 18, ch="g"), b=bass((0, "0", 16), (16, "3", 6), (22, "5", 10)), glide=True)
pat(LN, "LATE NIGHT RNB 10 LOW LIGHT", 73, 55, k=st(32, 0, 6, 10, 16, 22, 28), c=HALF, h=rep("x.x.x.x.t.x.x.x."), o=st(32, 30), b=bass((0, "0", 6), (6, "0", 4), (10, "7", 6), (16, "0", 6), (22, "5", 6), (28, "3", 4)), glide=True)

# ATL WAVE (Future): fast trap, rolling hats, punchy 808 bounces
AW = "ATL Wave"
pat(AW, "ATL WAVE 1 NIGHT RIDE", 150, k=st(32, 0, 7, 10, 16, 23, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (12, "r"), (13, "r"), (28, "q")), b=bass((0, "0", 7), (7, "0", 3), (10, "0", 6), (16, "0", 7), (23, "3", 3), (26, "5", 6)))
pat(AW, "ATL WAVE 2 CUP", 145, k=st(32, 0, 3, 10, 16, 19, 26), c=HALF, s=st(32, 8, 24), h=rep("x.x.t.x.x.x.t.x."), o=st(32, 14), b=bass((0, "0", 3), (3, "0", 7), (10, "7", 6), (16, "0", 3), (19, "0", 7), (26, "5", 6)))
pat(AW, "ATL WAVE 3 OUTER SPACE", 148, k=st(32, 0, 6, 11, 16, 22, 27), c=HALF, h=rep("xxxxxxxxxxxxxxqx"), b=bass((0, "0", 6), (6, "0", 5), (11, "3", 5), (16, "0", 6), (22, "0", 5), (27, "A", 5)))
pat(AW, "ATL WAVE 4 SYRUP", 140, k=st(32, 0, 10, 13, 16, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (6, "t"), (22, "t"), (30, "q")), p1=st(32, 4, 20), b=bass((0, "0", 10), (10, "5", 3), (13, "7", 3), (16, "0", 10), (26, "3", 6)))
pat(AW, "ATL WAVE 5 BANDS", 150, k=st(32, 0, 2, 7, 16, 18, 23), c=HALF, h=rep("x.x.x.x.x.x.x.xr"), o=st(32, 6, 22), b=bass((0, "0", 2), (2, "0", 5), (7, "0", 9), (16, "0", 2), (18, "0", 5), (23, "C", 9)))
pat(AW, "ATL WAVE 6 PURPLE", 144, k=st(32, 0, 11, 16, 27), c=HALF, s=st(32, 30, ch="o"), h=put(rep("x.x.x.x.x.x.x.x."), (9, "q"), (25, "r")), b=bass((0, "0", 11), (11, "3", 5), (16, "0", 11), (27, "5", 5)), glide=True)
pat(AW, "ATL WAVE 7 STAR", 152, k=st(32, 0, 3, 6, 16, 19, 22), c=HALF, h=rep("x.x.x.x.t.x.x.x."), b=bass((0, "0", 3), (3, "0", 3), (6, "0", 10), (16, "0", 3), (19, "0", 3), (22, "7", 10)))
pat(AW, "ATL WAVE 8 ROLLING", 142, k=st(32, 0, 7, 16, 23, 29), c=HALF, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 14, 30), p2=st(32, 10, 26), b=bass((0, "0", 7), (7, "0", 9), (16, "0", 7), (23, "3", 6), (29, "5", 3)))
pat(AW, "ATL WAVE 9 STREETS", 148, k=st(32, 0, 10, 16, 20, 26), c=HALF, h=put(rep("xxxxxxxxxxxxxxxx"), (14, "q"), (15, "q")), b=bass((0, "0", 10), (10, "0", 6), (16, "0", 4), (20, "5", 6), (26, "3", 6)))
pat(AW, "ATL WAVE 10 SLOW POUR", 140, k=st(32, 0, 6, 16, 22), c=HALF, h=rep("x...x.x.x...x.x."), b=bass((0, "0", 6), (6, "A", 10), (16, "0", 6), (22, "C", 10)), glide=True)

# ROCKSTAR BOUNCE (Lil Uzi Vert): fast, bright, bouncy, melodic 808s
RB = "Rockstar Bounce"
pat(RB, "ROCKSTAR BOUNCE 1 PINK", 155, k=st(32, 0, 6, 10, 16, 22, 26), c=HALF, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 14, 30), b=bass((0, "0", 6), (6, "7", 4), (10, "5", 6), (16, "0", 6), (22, "3", 4), (26, "5", 6)))
pat(RB, "ROCKSTAR BOUNCE 2 BRIGHT", 160, k=st(32, 0, 3, 10, 16, 19, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (13, "r"), (29, "t")), b=bass((0, "0", 3), (3, "0", 7), (10, "c", 6), (16, "0", 3), (19, "0", 7), (26, "7", 6)))
pat(RB, "ROCKSTAR BOUNCE 3 PHILLY", 150, k=st(32, 0, 7, 10, 16, 23), c=HALF, s=st(32, 15, ch="g"), h=rep("xxxxxxxxxxxxxxxx"), b=bass((0, "0", 7), (7, "3", 3), (10, "5", 6), (16, "0", 7), (23, "7", 9)))
pat(RB, "ROCKSTAR BOUNCE 4 GLOW", 158, k=st(32, 0, 6, 11, 16, 22, 27), c=HALF, h=rep("x.x.t.x.x.x.t.x."), p1=st(32, 2, 18), b=bass((0, "0", 6), (6, "0", 5), (11, "3", 5), (16, "0", 6), (22, "5", 5), (27, "7", 5)))
pat(RB, "ROCKSTAR BOUNCE 5 FLEX", 154, k=st(32, 0, 10, 16, 26, 29), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (6, "q"), (22, "q")), o=st(32, 12, 28), b=bass((0, "0", 10), (10, "0", 6), (16, "0", 10), (26, "5", 3), (29, "7", 3)))
pat(RB, "ROCKSTAR BOUNCE 6 MONEY", 162, k=st(32, 0, 3, 7, 16, 19, 23), c=HALF, h=rep("x.x.x.x.x.x.x.xr"), b=bass((0, "0", 3), (3, "0", 4), (7, "0", 9), (16, "0", 3), (19, "0", 4), (23, "3", 9)))
pat(RB, "ROCKSTAR BOUNCE 7 SPACE", 150, k=st(32, 0, 11, 16, 27), c=HALF, h=rep("x.x.x.x.t.x.x.x."), p2=st(32, 6, 22), b=bass((0, "0", 11), (11, "7", 5), (16, "0", 11), (27, "c", 5)), glide=True)
pat(RB, "ROCKSTAR BOUNCE 8 SKIPPY", 156, k=st(32, 0, 6, 16, 22, 30), c=HALF, s=st(32, 8, 24), h=put(rep("xxxxxxxxxxxxxxxx"), (12, "q"), (28, "q")), b=bass((0, "0", 6), (6, "5", 10), (16, "0", 6), (22, "3", 8), (30, "5", 2)))
pat(RB, "ROCKSTAR BOUNCE 9 SUGAR", 152, k=st(32, 0, 7, 10, 16, 26), c=HALF, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 6, 22, 30), b=bass((0, "0", 7), (7, "0", 3), (10, "7", 6), (16, "0", 10), (26, "5", 6)))
pat(RB, "ROCKSTAR BOUNCE 10 LASER", 160, k=st(32, 0, 2, 10, 16, 18, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (13, "t"), (14, "r"), (30, "q")), b=bass((0, "0", 2), (2, "0", 8), (10, "3", 6), (16, "0", 2), (18, "0", 8), (26, "A", 6)))

# VAMP RAGE (Playboi Carti): rage, distorted 808 on every kick, sparse snares, choppy hats
VR = "Vamp Rage"
pat(VR, "VAMP RAGE 1 MOSH", 150, k=st(32, 0, 3, 6, 10, 16, 19, 22, 26), c=HALF, h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 3), (3, "0", 3), (6, "0", 4), (10, "0", 6), (16, "0", 3), (19, "0", 3), (22, "0", 4), (26, "3", 6)))
pat(VR, "VAMP RAGE 2 NONSTOP", 160, k=st(32, 0, 4, 8, 12, 16, 20, 24, 28), c=HALF, h=rep("x.xxx.xxx.xxx.xx"), b=bass((0, "0", 4), (4, "0", 4), (8, "0", 4), (12, "3", 4), (16, "0", 4), (20, "0", 4), (24, "0", 4), (28, "5", 4)))
pat(VR, "VAMP RAGE 3 SKY", 155, k=st(32, 0, 7, 10, 16, 23, 26), c=HALF, o=st(32, 6, 14, 22, 30), h=rep("x...x...x...x..."), b=bass((0, "0", 7), (7, "0", 3), (10, "0", 6), (16, "0", 7), (23, "7", 3), (26, "5", 6)))
pat(VR, "VAMP RAGE 4 SLAM", 152, k=st(32, 0, 2, 6, 10, 16, 18, 22, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (14, "q"), (30, "q")), b=bass((0, "0", 2), (2, "0", 4), (6, "0", 4), (10, "0", 6), (16, "0", 2), (18, "0", 4), (22, "0", 4), (26, "A", 6)))
pat(VR, "VAMP RAGE 5 PUNK", 158, k=st(32, 0, 6, 12, 16, 22, 28), c=HALF, s=st(32, 30, ch="o"), h=rep("xxxxxxxxxxxxxxxx"), b=bass((0, "0", 6), (6, "0", 6), (12, "3", 4), (16, "0", 6), (22, "0", 6), (28, "5", 4)))
pat(VR, "VAMP RAGE 6 SPIKES", 150, k=st(32, 0, 3, 10, 13, 16, 19, 26, 29), c=HALF, h=rep("x.x.x.x.x.x.x.x."), p1=st(32, 4, 20), b=bass((0, "0", 3), (3, "0", 7), (10, "0", 3), (13, "3", 3), (16, "0", 3), (19, "0", 7), (26, "0", 3), (29, "5", 3)))
pat(VR, "VAMP RAGE 7 FLOWERS", 162, k=st(32, 0, 3, 6, 11, 16, 19, 22, 27), c=HALF, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 14), b=bass((0, "0", 3), (3, "0", 3), (6, "0", 5), (11, "7", 5), (16, "0", 3), (19, "0", 3), (22, "0", 5), (27, "5", 5)))
pat(VR, "VAMP RAGE 8 BLACKOUT", 155, k=st(32, 0, 5, 10, 16, 21, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (12, "r"), (28, "r")), b=bass((0, "0", 5), (5, "0", 5), (10, "0", 6), (16, "0", 5), (21, "0", 5), (26, "C", 6)))
pat(VR, "VAMP RAGE 9 CHAOS", 148, k=st(32, 0, 2, 4, 10, 16, 18, 20, 26), c=HALF, h=rep("x.x.x.x.x.x.x.x."), p2=st(32, 7, 23), b=bass((0, "0", 2), (2, "0", 2), (4, "0", 6), (10, "3", 6), (16, "0", 2), (18, "0", 2), (20, "0", 6), (26, "5", 6)))
pat(VR, "VAMP RAGE 10 FULL VAMP", 165, k=st(32, *range(0, 32, 2)), c=HALF, h=rep("x...x...x...x..."), o=st(32, 30), b=bass(*[(i, "0" if i % 8 else "3", 2) for i in range(0, 32, 2)]))

# CAROLINA SOUL (J. Cole): soulful boom bap, dusty swung drums, warm kicks
CS = "Carolina Soul"
pat(CS, "CAROLINA SOUL 1 DUSTY", 90, 58, k=st(32, 0, 7, 10, 16, 23, 26), s=BACK, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 14, 30))
pat(CS, "CAROLINA SOUL 2 PORCH", 86, 60, k=st(32, 0, 3, 10, 16, 19, 26), s=BACK, h=rep("x.xgx.xgx.xgx.xg"), p1=st(32, 30, ch="g"))
pat(CS, "CAROLINA SOUL 3 SUNSET", 92, 56, k=st(32, 0, 6, 9, 16, 22, 25), s=put(BACK, (15, "g"), (31, "g")), h=rep("x.x.x.x.x.x.x.x."))
pat(CS, "CAROLINA SOUL 4 HOMETOWN", 88, 60, k=st(32, 0, 10, 11, 16, 26), s=BACK, h=rep("xxxxxxxxxxxxxxxx"), o=st(32, 6, 22))
pat(CS, "CAROLINA SOUL 5 CROOKED", 94, 57, k=st(32, 0, 7, 8, 16, 23, 24), s=put(BACK, (10, "g"), (26, "g")), h=rep("x.x.x.x.x.x.x.x."), cr=st(32, 0))
pat(CS, "CAROLINA SOUL 6 WARM", 84, 58, k=st(32, 0, 9, 16, 25), s=BACK, r=st(32, 14, 30, ch="g"), h=rep("x.x.x.x.x.x.x.x."))
pat(CS, "CAROLINA SOUL 7 VILLE", 90, 62, k=st(32, 0, 3, 7, 16, 19, 23), s=BACK, h=put(rep("x.x.x.x.x.x.x.x."), (14, "o"), (15, "x")))
pat(CS, "CAROLINA SOUL 8 TAPE", 88, 56, k=st(32, 0, 10, 16, 22, 26), s=BACK, h=rep("x.xxx.xxx.xxx.xx"), b=bass((0, "0", 10), (16, "0", 6), (22, "5", 4), (26, "3", 6)))
pat(CS, "CAROLINA SOUL 9 FIRST CHILD", 92, 55, k=st(32, 0, 6, 10, 16, 22, 26), s=BACK, h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 6), (6, "0", 4), (10, "A", 6), (16, "0", 6), (22, "3", 4), (26, "5", 6)))
pat(CS, "CAROLINA SOUL 10 DREAMS", 86, 60, k=st(32, 0, 7, 11, 16, 27), s=put(BACK, (23, "g")), h=rep("x.x.x.x.x.x.x.x."), p1=st(32, 8, 24, ch="o"))

# LA LYRICIST (Kendrick Lamar): West Coast bounce meets jazz and boom bap
LL = "LA Lyricist"
pat(LL, "LA LYRICIST 1 STRUT", 94, 56, k=st(32, 0, 3, 10, 16, 19, 26), s=BACK, c=st(32, 4, 20), h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 3), (3, "0", 7), (10, "5", 6), (16, "0", 3), (19, "7", 7), (26, "5", 6)))
pat(LL, "LA LYRICIST 2 STOMP", 150, k=st(32, 0, 3, 16, 19), c=HALF, h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 3), (3, "0", 13), (16, "0", 3), (19, "A", 13)))
pat(LL, "LA LYRICIST 3 CITY", 96, 54, k=st(32, 0, 6, 10, 16, 22, 26), c=BACK, h=rep("x.xxx.xxx.xxx.xx"), o=st(32, 14, 30), b=bass((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 6), (22, "5", 4), (26, "7", 6)))
pat(LL, "LA LYRICIST 4 WINGS", 98, 62, k=st(32, 0, 7, 16, 23), s=BACK, h=rep("x.xgx.xgx.xgx.xg"), cr=st(32, 0), p1=st(32, 14, 30, ch="g"))
pat(LL, "LA LYRICIST 5 DOUBLE TIME", 140, k=st(32, 0, 6, 10, 16, 22, 26), c=HALF, s=st(32, 15, 31, ch="g"), h=rep("xxxxxxxxxxxxxxxx"), b=bass((0, "0", 6), (6, "0", 4), (10, "0", 6), (16, "0", 6), (22, "3", 4), (26, "0", 6)))
pat(LL, "LA LYRICIST 6 GOOD STEP", 92, 58, k=st(32, 0, 10, 16, 26), s=BACK, r=st(32, 7, 23, ch="g"), h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 10), (10, "5", 6), (16, "0", 10), (26, "3", 6)), glide=True)
pat(LL, "LA LYRICIST 7 MARCH", 110, 56, k=st(32, 0, 3, 8, 16, 19, 24), s=BACK, h=put(rep("x.x.x.x.x.x.x.x."), (14, "r")), o=st(32, 30))
pat(LL, "LA LYRICIST 8 WEST SIDE", 92, 55, k=st(32, 0, 7, 10, 16, 23, 26), c=BACK, h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 7), (7, "0", 3), (10, "7", 6), (16, "0", 7), (23, "5", 3), (26, "3", 6)), glide=True)
pat(LL, "LA LYRICIST 9 SERMON", 100, 60, k=st(32, 0, 9, 16, 21, 25), s=put(BACK, (11, "g"), (27, "g")), h=rep("x.xxx.xxx.xxx.xx"))
pat(LL, "LA LYRICIST 10 CHAPTER", 90, 58, k=st(32, 0, 3, 6, 16, 22), s=BACK, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 14), p2=st(32, 10, 26))

# SOFT SOUL (SZA): airy neo soul RnB, laid-back swung drums, soft 808
SS = "Soft Soul"
pat(SS, "SOFT SOUL 1 CONTROL", 80, 58, k=st(32, 0, 7, 16, 23), r=BACK, h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 7), (7, "3", 9), (16, "0", 7), (23, "5", 9)), glide=True)
pat(SS, "SOFT SOUL 2 GOOD MORNING", 76, 60, k=st(32, 0, 10, 16, 26), s=put(BACK, (14, "g"), (30, "g")), h=rep("x.xgx.xgx.xgx.xg"), b=bass((0, "0", 10), (10, "5", 6), (16, "A", 10), (26, "0", 6)), glide=True)
pat(SS, "SOFT SOUL 3 SLEEP IN", 84, 56, k=st(32, 0, 6, 16, 22), c=BACK, h=put(rep("x.x.x.x.x.x.x.x."), (14, "t")), b=bass((0, "0", 6), (6, "0", 10), (16, "3", 6), (22, "5", 10)), glide=True)
pat(SS, "SOFT SOUL 4 SWAY", 88, 54, k=st(32, 0, 3, 10, 16, 19, 26), s=BACK, h=rep("x.x.x.x.x.x.x.x."), p1=st(32, 6, 22, ch="o"))
pat(SS, "SOFT SOUL 5 GARDEN", 72, 60, k=st(32, 0, 9, 16), r=BACK, h=rep("x...x...x...x..."), cr=st(32, 0), b=bass((0, "0", 9), (9, "7", 7), (16, "0", 16)), glide=True)
pat(SS, "SOFT SOUL 6 CLOCKS", 82, 57, k=st(32, 0, 7, 10, 16, 23), c=BACK, h=rep("x.xxx.xxx.xxx.xx"), b=bass((0, "0", 7), (7, "0", 3), (10, "3", 6), (16, "0", 16)))
pat(SS, "SOFT SOUL 7 CLOUDS", 70, 58, k=st(32, 0, 7, 10, 16, 23, 26), c=HALF, r=st(32, 8, 24), h=put(rep("x.x.x.x.x.x.x.x."), (12, "r"), (28, "t")), b=bass((0, "0", 7), (7, "0", 3), (10, "5", 6), (16, "0", 7), (23, "3", 9)), glide=True)
pat(SS, "SOFT SOUL 8 DRIVE", 86, 55, k=st(32, 0, 6, 11, 16, 22), s=BACK, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 14, 30))
pat(SS, "SOFT SOUL 9 ORBIT", 78, 60, k=st(32, 0, 10, 16, 22, 26), r=BACK, s=st(32, 15, 31, ch="g"), h=rep("x.xgx.xgx.xgx.xg"), b=bass((0, "0", 10), (10, "3", 6), (16, "0", 6), (22, "5", 4), (26, "7", 6)), glide=True)
pat(SS, "SOFT SOUL 10 SUNDAY", 74, 62, k=st(32, 0, 7, 16), s=BACK, h=rep("x.x.x.x.x.x.x.x."), p1=st(32, 3, 19, ch="g"), b=bass((0, "0", 7), (7, "5", 9), (16, "0", 16)), glide=True)

# HOUSTON QUEEN (Beyonce): big claps, bounce, RnB-pop drums, a little Houston swing
HQ = "Houston Queen"
pat(HQ, "HOUSTON QUEEN 1 MARCH", 124, k=st(32, 0, 6, 10, 16, 22, 26), c=BACK, h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 6), (22, "0", 4), (26, "5", 6)))
pat(HQ, "HOUSTON QUEEN 2 CRUSH", 100, 56, k=st(32, 0, 3, 7, 16, 19, 23), s=BACK, c=BACK, h=rep("xxxxxxxxxxxxxxxx"), o=st(32, 14, 30))
pat(HQ, "HOUSTON QUEEN 3 LATE PARTY", 120, 54, k=st(32, 0, 10, 16, 26), c=put(BACK, (13, "o"), (29, "o")), h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 10), (10, "5", 6), (16, "0", 10), (26, "3", 6)), glide=True)
pat(HQ, "HOUSTON QUEEN 4 DISCO", 120, k=st(32, 0, 4, 8, 12, 16, 20, 24, 28), c=BACK, h=rep("..x...x...x...x."), o=st(32, 2, 10, 18, 26))
pat(HQ, "HOUSTON QUEEN 5 BACKSEAT", 96, 57, k=st(32, 0, 7, 10, 16, 23), c=BACK, h=put(rep("x.x.x.x.x.x.x.x."), (14, "r"), (30, "q")), b=bass((0, "0", 7), (7, "0", 3), (10, "7", 6), (16, "0", 7), (23, "5", 9)))
pat(HQ, "HOUSTON QUEEN 6 BOUNCE", 130, k=st(32, 0, 6, 16, 22), c=HALF, h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 6), (6, "0", 10), (16, "0", 6), (22, "3", 10)))
pat(HQ, "HOUSTON QUEEN 7 STRUT", 84, 58, k=st(32, 0, 10, 16, 26), s=put(BACK, (15, "g")), h=rep("x.xgx.xgx.xgx.xg"), p1=st(32, 6, 22, ch="o"))
pat(HQ, "HOUSTON QUEEN 8 SLOW BOUNCE", 72, 60, k=st(32, 0, 3, 10, 16, 19), c=HALF, r=st(32, 8, 24), h=rep("x.x.x.x.x.x.x.xr"), b=bass((0, "0", 3), (3, "0", 7), (10, "5", 6), (16, "0", 3), (19, "3", 13)), glide=True)
pat(HQ, "HOUSTON QUEEN 9 THIRD WARD", 98, 56, k=st(32, 0, 6, 9, 16, 22, 25), c=BACK, s=BACK, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 30))
pat(HQ, "HOUSTON QUEEN 10 RODEO", 105, 55, k=st(32, 0, 10, 16, 26), s=BACK, h=rep("x.x.x.x.x.x.x.x."), p2=st(32, 3, 7, 19, 23, ch="o"))

# ================= LIVE DRUMMER STYLES (Oct 17): written the way a drummer plays =================
# Velocity carries the feel: X accent, x normal, o medium, g ghost. Hats lean on the quarter notes
# and fall away on the 16ths, snares get ghost notes around the backbeat, and the 4-bar phrases
# change a little each bar and end in a fill, with the crash on the 1 coming back around.
# Breaks are "in the style of" the famous records (the rhythm, not a transcription).
def bars(*b):
    for x in b: assert len(x) % 16 == 0 and x, x
    return "".join(b)
def phrase(main, b2=None, b3=None, fill=None):
    """Four bars: the groove, a variation, the groove again, then a fill bar."""
    return bars(main, b2 or main, b3 or main, fill or b2 or main)
HAT16 = "XgogxgogXgogxgog"        # 16ths, loud on the beat, soft in between
HAT8 = "X.o.x.o.X.o.x.o."         # 8ths, leaning on the beat
CRASH4 = st(64, 0)                # crash on the 1 of the phrase (lands after the fill)

# ---------------- Dilla Time (MPC 3000 feel: lazy kicks that land early or late, doubled kicks,
# uneven hats, snare ghosts; set HUMANIZE up for the drunk timing) ----------------
DL = "Dilla Time"
pat(DL, "DILLA TIME 1 DRUNK KICKS", 90, 62, k="X.....x..x.x...xX......xx..x...x", s=BACK, h=two("x.ogx.goxgo.x.og"))
pat(DL, "DILLA TIME 2 LATE CLAP", 88, 64, k="X......x.x......X.....x...x.x...", s=BACK, c=st(32, 5, 13, 21, 29, ch="o"), h=two("xgx.xgxgx.xgxgx."))
pat(DL, "DILLA TIME 3 DONUT", 92, 60, k="X.x.......x..x..X.x.....x..x....", s=put(BACK, (7, "g"), (23, "g"), (31, "g")), h=two("x.x.xox.x.x.xox."))
pat(DL, "DILLA TIME 4 RIM CRACK", 86, 62, k="X......xx.......X.....x...xx....", s=BACK, r=st(32, 10, 26, 30, ch="g"), h=two("xoxgxoxgxoxgxoxg"))
pat(DL, "DILLA TIME 5 PUSHED ONE", 94, 58, k="X.....x...x....xX.....x...x....x", s=put(BACK, (14, "g")), h=two("x.x.x.x.x.x.x..o"), o=st(32, 14, 30, ch="o"))
pat(DL, "DILLA TIME 6 STUMBLE", 90, 66, k="X..x.x....x.....X..x.....xx.....", s=put(BACK, (9, "g"), (25, "g")), h=two("xg.gxg.gxg.gxg.g"))
pat(DL, "DILLA TIME 7 SHAKER STAGGER", 84, 62, k="X......x..x.x...X......x...x....", s=BACK, p1=two("ogxgogxgogxgogxg"), h=two("..x...x...x...x."))
pat(DL, "DILLA TIME 8 SOFT KNOCK", 88, 60, k="X.......x.xx....X.......x..x..x.", s=st(32, 4, 12, 20, 28, ch="x"), c=st(32, 12, 28, ch="o"), h=two("xgxgxgxgxgxgxgxg"))
pat(DL, "DILLA TIME 9 HALF DRUNK", 76, 64, k="X......x..x.....X.....x.x.......", s=st(32, 8, 24, ch="X"), r=st(32, 3, 14, 19, 30, ch="g"), h=two("x.ox.ox.x.ox.ox."))
pat(DL, "DILLA TIME 10 DETROIT LOOP", 95, 58, k=phrase("X.....x..x.x....", "X.....x...x..x.x", "X.....x..x.x....", "X.....x...x.x.x."),
    s=phrase("....X.......X...", "....X..g....X..g", "....X.......X...", "....X..g.g..X.gg"), h=phrase("x.ogx.ogx.ogx.og", "x.ogx.ogx.ogx.o."))

# ---------------- 90s Rap (golden era NY plus West and South: MPC / SP-1200 swing, chopped breaks,
# hard snares, kicks that knock off the beat) ----------------
NR = "90s Rap"
pat(NR, "90S RAP 1 HARD CHOP", 94, 56, k="X......x..X.....X......x..x.....", s=BACK, h=two("x.x.x.x.x.x.x.x."), p2=st(32, 30, ch="o"))
pat(NR, "90S RAP 2 SOUL BROTHER", 94, 60, k="X.....x...x..x..X.......x.x.....", s=put(BACK, (15, "g")), h=two("xgxoxgxoxgxoxg.o"), o=st(32, 14, 30, ch="o"))
pat(NR, "90S RAP 3 QUEENSBRIDGE", 92, 54, k="X.........x.....X.......x.x.....", s=BACK, r=st(32, 7, 23, ch="g"), h=two("x...x...x...x..."))
pat(NR, "90S RAP 4 SHAOLIN DUST", 92, 58, k="X..x......x.....X.....x...x..x..", s=put(BACK, (7, "g"), (25, "g")), h=two("x.xox.xox.xox.xo"))
pat(NR, "90S RAP 5 G-FUNK ROLL", 92, 54, k="X.....x.x.......X.....x.x.x.....", s=BACK, c=BACK, h=two("xoxoxoxoxoxoxoxo"), o=st(32, 30))
pat(NR, "90S RAP 6 JAZZ TONGUES", 94, 60, k="X......x..x.....X..x......x.....", s=BACK, cr=two("x.x.x.x.x.x.x.x."), r=st(32, 10, 26, ch="g"))
pat(NR, "90S RAP 7 BACKPACK", 92, 58, k="X.x.......x..x..X.x.......x.....", s=put(BACK, (9, "g"), (31, "g")), h=two("x.x.x.x.x.x.x.x."), p1=two("..g...g...g...g."))
pat(NR, "90S RAP 8 DIRTY SOUTH", 96, 54, k="X.....x.x..x....X.....x...x.x...", s=BACK, h=two("xoxoxoxoxoxoxoxo"), p1=st(32, 6, 22, ch="o"))
pat(NR, "90S RAP 9 SHINY SUIT", 98, 54, k="X......x..x.....X..x...x..x.....", s=BACK, c=BACK, h=two("x.x.x.x.x.x.x.x."), o=st(32, 14))
pat(NR, "90S RAP 10 MEMPHIS TAPE", 140, k="X.....x...x.....X.x.....x.......", c=HALF, h="x.x.t.x.x.x.x.x.x.x.t.x.x.x.x.x.", p2=two("x..x..x...x..x.."), b=bass((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 8), (24, "5", 8)))

# ---------------- 70s Soul (the drummers behind the samples: JB funk ghosts, Purdie shuffle,
# Stax and Motown backbeats, Philly disco, New Orleans syncopation; 4-bar phrases with fills) ----------------
SO = "70s Soul"
pat(SO, "70S SOUL 1 FUNKY GHOSTS", 100, 52, k=phrase("X.x...x...x..x..", fill="X.x...x...x....."),
    s=phrase("....X..g.g.gX..g", "....X..g.g.gX.g.", fill="....X..g.g.gXgXX"), h=phrase("xgxgxg.gxgxgx.xg", fill="xgxgxg.gxgxg...."), o=phrase("......o......o..", fill="......o........."), cr=CRASH4)
pat(SO, "70S SOUL 2 HALF SHUFFLE", 88, 66, k=phrase("X.......x.....x.", "X.....x.x......."), s=phrase("..g..g..X..g..g.", "..g..g..X..g.gg.", fill="..g..g..X..gXgXg"),
    h=phrase("x.x.x.x.x.x.x.x."), cr=CRASH4)
pat(SO, "70S SOUL 3 MEMPHIS BACKBEAT", 98, 52, k=phrase("X.......X.x.....", "X.......X.x...x."), s=phrase("....X.......X...", fill="....X.......XoXo"),
    h=phrase("x.o.x.o.x.o.x.o."), p1=phrase("....x.......x..."), cr=CRASH4)
pat(SO, "70S SOUL 4 HITSVILLE", 120, 50, k=phrase("x...x...x...x..."), s=phrase("X...X...X...X...", fill="X...X...X.X.XXXX"), p1=phrase("....x.......x..."),
    h=phrase("x.x.x.x.x.x.x.x."))
pat(SO, "70S SOUL 5 PHILLY FLOOR", 112, 50, k=phrase("X...x...X...x..."), s=phrase("....X.......X...", fill="....X.......XoXX"), h=phrase("xgx.xgx.xgx.xgx."),
    o=phrase("..o...o...o...o.", fill="..o...o...o....."), cr=CRASH4)
pat(SO, "70S SOUL 6 SECOND LINE", 100, 54, k=phrase("X..x..x...x..x..", "X..x....x.x..x.."), s=phrase("..g.X..g.gx.X.g.", fill="..g.X..g.gx.XoXo"),
    h=phrase("x.x.x.xox.x.x.xo"), cr=CRASH4)
pat(SO, "70S SOUL 7 QUIET BALLAD", 70, 58, k=phrase("X.......x..x....", "X......x..x....."), r=phrase("....x.......x...", fill="....x..........."),
    cr=phrase("x.o.x.o.x.o.x.o."), h=phrase("....g.......g..."), s=bars("." * 16, "." * 16, "." * 16, "............ooxX"))
pat(SO, "70S SOUL 8 SOUL POWER", 108, 54, k=phrase("X..x..x...x.....", "X..x......x..x.."), s=phrase("....X..g.g..X..g", fill="....X..g.g..XgXg"),
    h=phrase("xoxoxoxoxoxoxoxo"), p1=phrase("x.x.x.x.x.x.x.x."), cr=CRASH4)
pat(SO, "70S SOUL 9 SUPERFLY", 104, 54, k=phrase("X.....x.x.....x.", "X.....x...x....."), s=phrase("....X.......X..g"),
    o=phrase("x.o.x.o.x.o.x.o."), h=phrase(".g.g.g.g.g.g.g.g"), p2=phrase("..x.....x.x.....", "..x...x.....x..."), cr=CRASH4)
pat(SO, "70S SOUL 10 CHURCH CHOPS", 96, 60, k=phrase("X......x..x.....", "X..x...x..x....."), s=phrase("....X..g...gX...", fill="....X..g.ggXgXgX"),
    h=phrase("x.oxx.oxx.oxx.o.", fill="x.oxx.oxx......."), lt=bars("." * 48, "............o.xx"), cr=CRASH4)

# ---------------- 80s Breaks (the records every 80s hip hop DJ cut up; rhythm in the style of each break) ----------------
BR = "80s Breaks"
pat(BR, "BREAKS 1 AMEN STYLE", 136, 52, k=phrase("X.x.......xx....", fill="..x.......x....."),
    s=phrase("....X..g.g..X..g", "....X..g.g..X..g", "....X..g.g....X.", ".g..X..g.g....X."), cr=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.X.x.x."))
pat(BR, "BREAKS 2 THINK STYLE", 114, 52, k=phrase("X.....x...X.....", "X.....x...X..x.."), s=phrase("....X..x.x..X..x", "....X..x.x..X..."),
    h=phrase("x.x.x.x.x.x.x.x."), o=phrase(".............o..", "................"))
pat(BR, "BREAKS 3 IMPEACH STYLE", 98, 56, k=phrase("X......X..x.....", "X......X........"), s=phrase("....X.......X..."),
    h=phrase("x.x.x...x.x.x..."), o=phrase("......o.......o."), cr=CRASH4)
pat(BR, "BREAKS 4 SUBSTITUTION STYLE", 102, 54, k=phrase("X.x....x..xx....", "X.x....x..x....."), s=phrase("....X.......X..."), h=phrase("x.x.x.x.x.x.x.x."))
pat(BR, "BREAKS 5 BONGO ROCK STYLE", 112, 54, k=phrase("X.....x...x....."), s=phrase("....X.......X..."), h=phrase("x.x.x.x.x.x.x.x."),
    p1=phrase("x.ox.ox.x.ox.oxo"), p2=phrase("..x...x...x..xx.", "..x...x.x.x...x."))
pat(BR, "BREAKS 6 SKULL SNAP STYLE", 96, 56, k=phrase("X.x.......xx....", "X.x.......x....."), s=phrase("....X..g....X...", "....X..g....X..g"),
    h=phrase("x.x.x.x.x.x.x.x."), o=phrase("..............o."))
pat(BR, "BREAKS 7 ROACH CLIP STYLE", 98, 54, k=phrase("X..x......x.....", "X..x....x.x....."), s=phrase("....X.......X...", fill="....X.......X.XX"),
    h=phrase("xoxoxoxoxoxoxoxo"))
pat(BR, "BREAKS 8 BIG BEAT STYLE", 98, 50, k=phrase("X.....x.x.......", "X.....x.x.....x."), s=phrase("....X.......X..."), cr=CRASH4)
pat(BR, "BREAKS 9 LEVEE STYLE", 72, 52, k=phrase("X.x.......xx....", "X.x.......x....."), s=phrase("....X.......X..."),
    h=phrase("x.x.x.x.x.x.x.x."), o=phrase("..............o."))
pat(BR, "BREAKS 10 PRESIDENT STYLE", 100, 54, k=phrase("X.....x...x..x..", "X.....x...x....."), s=phrase("....X..g.g..X...", "....X..g.g..X..g"),
    h=phrase("x.x.x.xox.x.x.xo"), cr=CRASH4)

# ---------------- Rock (8th-note hats or ride, kick and snare trading, tom fills into a crash) ----------------
RK = "Rock"
pat(RK, "ROCK 1 STRAIGHT EIGHTS", 120, k=phrase("X.......X.x.....", fill="X.......X......."), s=phrase("....X.......X...", fill="....X.......xxXX"),
    h=phrase("X.x.X.x.X.x.X.x.", fill="X.x.X.x.X......."), ht=bars("." * 48, "........xx......"), lt=bars("." * 48, "..........xx...."), cr=CRASH4)
pat(RK, "ROCK 2 HALF TIME", 140, k=phrase("X.....x.........", "X.....x...x....."), s=phrase("........X.......", fill="........X...xxXX"),
    h=phrase("x.x.x.x.x.x.x.x."), cr=CRASH4)
pat(RK, "ROCK 3 DANCE FLOOR", 126, k=phrase("X...X...X...X..."), s=phrase("....X.......X...", fill="....X.......XXXX"),
    h=phrase("x.o.x.o.x.o.x.o."), o=phrase("..o...o...o...o.", fill="..o...o........."), cr=CRASH4)
pat(RK, "ROCK 4 HEAVY ROOM", 74, k=phrase("X.x.......xx....", "X.x.......x....."), s=phrase("....X.......X..."),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x........."), ht=bars("." * 48, "........XX......"), lt=bars("." * 48, "..........XXX..."), cr=CRASH4)
pat(RK, "ROCK 5 PUNK", 176, k=phrase("X.x.X.x.X.x.X.x."), s=phrase("..X...X...X...X.", fill="..X...X...XxXXXX"), h=phrase("x.x.x.x.x.x.x.x."), cr=CRASH4)
pat(RK, "ROCK 6 POP PUNK", 160, k=phrase("X......xX.x.....", "X.x....xX......."), s=phrase("....X.......X...", fill="....X...xxxxXXXX"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x........."), lt=bars("." * 48, "........o.o....."), cr=CRASH4)
pat(RK, "ROCK 7 FUNK ROCK", 100, 54, k=phrase("X..x..x...x.....", "X..x....x.x..x.."), s=phrase("....X..g.g..X..g", fill="....X..g.g..XgXX"),
    h=phrase("xoxoxoxoxoxoxoxo"), o=phrase("..............o.", fill="................"), cr=CRASH4)
pat(RK, "ROCK 8 FLOOR TOM", 108, k=phrase("X.......X.......", "X.......X.x....."), s=phrase("....X.......X..."), lt=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.X.X.XXXX"), cr=CRASH4)
pat(RK, "ROCK 9 RIDE GROOVE", 112, k=phrase("X.....x.X.......", "X.....x.X.x....."), s=phrase("....X.......X...", fill="....X.......X.XX"),
    cr=phrase("x.o.x.o.x.o.x.o."), h=phrase("....g.......g..."))
pat(RK, "ROCK 10 POWER BALLAD", 72, k=phrase("X.......X.x.....", "X......xX......."), s=phrase("....X.......X...", fill="....X...xxoxXxXX"),
    h=phrase("x.o.x.o.x.o.x.o.", fill="x.o.x.o........."), ht=bars("." * 48, "........oo......"), lt=bars("." * 48, "..........oo...."), cr=CRASH4)

# ---------------- Alt Trap (rage, plugg, pluggnb: sparse drums, the 808 leads, hats in clumps,
# rolls only at the end of a phrase, drop-outs used as rhythm) ----------------
AT = "Alt Trap"
pat(AT, "ALT TRAP 1 RAGE ARENA", 160, k=st(32, 0, 10, 16), c=HALF, h=put(rep("x...x...x...x..."), (28, "t"), (30, "t")),
    b=bass((0, "0", 10), (10, "0", 6), (16, "c", 6), (22, "0", 10)), glide=True)
pat(AT, "ALT TRAP 2 PLUGGNB", 150, c=HALF, r=rep("...x.......x...."), h=rep("x.x...x.x.x....."), s=st(32, 30, ch="q"),
    p1=rep("x.......", 32), b=bass((0, "0", 6), (6, "4", 4), (10, "0", 6), (16, "5", 6), (22, "4", 4), (26, "0", 6)), glide=True)
pat(AT, "ALT TRAP 3 PLUGG CLUMPS", 145, 56, k=st(32, 0, 16), c=BACK, h=rep("xxx.....xx.x....", 32), r=st(32, 11, 27, ch="o"),
    cr=st(32, 0), b=bass((0, "0", 8), (8, "7", 4), (12, "5", 4), (16, "0", 8), (24, "3", 8)))
pat(AT, "ALT TRAP 4 TERROR PLUGG", 150, c=st(32, 8, 24, ch="o"), r=rep("...x......x....."), h=rep("x...x.x.x...x..."), o=st(32, 14),
    b=bass((0, "0", 4), (4, "0", 4), (8, "A", 8), (16, "0", 4), (20, "0", 4), (24, "B", 8)), glide=True)
pat(AT, "ALT TRAP 5 CLIPPED", 155, k=st(32, 0, 7, 16, 23), s=HALF, c=HALF, h=rep("x.x.x.x.x.x.x.x."), p2=st(32, 15, 31, ch="X"),
    b=bass((0, "0", 7), (7, "0", 9), (16, "0", 7), (23, "7", 9)))
pat(AT, "ALT TRAP 6 OPIUM BOUNCE", 158, k=st(32, 0, 3, 10, 16, 19, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (30, "r")),
    b=bass((0, "0", 3), (3, "0", 7), (10, "c", 6), (16, "0", 3), (19, "0", 7), (26, "a", 6)), glide=True)
pat(AT, "ALT TRAP 7 HYPERPLUGG", 155, c=HALF, s=put(st(32, 24, ch="X"), (14, "g"), (15, "g")), h=rep("x.xx..x.x.xx..x."), p1=st(32, 6, 22, ch="o"),
    b=bass((0, "0", 2), (2, "0", 2), (4, "7", 4), (8, "5", 8), (16, "0", 2), (18, "0", 2), (20, "7", 4), (24, "a", 8)))
pat(AT, "ALT TRAP 8 GAME BOUNCE", 145, k=st(32, 0, 6, 16, 22, 27), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (12, "t"), (14, "t")), o=st(32, 26),
    b=bass((0, "0", 6), (6, "0", 10), (16, "3", 6), (22, "0", 5), (27, "5", 5)), glide=True)
pat(AT, "ALT TRAP 9 DROP OUT", 152, k=st(32, 0, 10), c=st(32, 8, ch="X"), h=rep("x.x.x.x.........", 32), s=st(32, 28, 29, 30, 31, ch="o"),
    b=bass((0, "0", 10), (10, "0", 6), (16, "3", 16)))
pat(AT, "ALT TRAP 10 ETHEREAL RAGE", 156, k=st(32, 0, 16, 26), c=HALF, h=rep("x...x...x...x..."), cr=st(32, 0), p1=rep("..o...o.", 32),
    b=bass((0, "0", 16), (16, "5", 10), (26, "7", 6)), glide=True)

# ---------------- Bay Area 2026 (mobb and hyphy roots: 808 bounce, slapping claps on 2 and 4,
# light-swung 8th hats with few rolls, long melodic 808s that jump octaves, chant / FX percussion) ----------------
BA = "Bay Area 2026"
pat(BA, "BAY AREA 1 SLAP", 100, 56, k="X..x..x...x.....X..x..x...x..x..", c=BACK, s=st(32, 4, 12, 20, 28, ch="o"), h=rep("x.o.x.o.x.o.x.o."),
    p1=st(32, 7, 14, 23, 30, ch="o"), b=bass((0, "0", 3), (3, "0", 3), (6, "c", 4), (10, "0", 6), (16, "0", 3), (19, "0", 3), (22, "c", 4), (26, "5", 6)))
pat(BA, "BAY AREA 2 HYPHY", 106, 54, k="X..x..x.x.x.....X..x..x.x..x.x..", c=BACK, h=rep("xoxoxoxoxoxoxoxo"), p2=st(32, 15, 31, ch="X"), o=st(32, 14, 30),
    b=bass((0, "0", 3), (3, "0", 3), (6, "0", 2), (8, "3", 2), (10, "5", 6), (16, "0", 3), (19, "0", 3), (22, "c", 10)))
pat(BA, "BAY AREA 3 MOBB SLOW", 86, 58, k="X......x..x.....X......x.x......", c=BACK, h=rep("x.x.x.x.x.x.x.x."), r=st(32, 14, 30, ch="g"),
    b=bass((0, "0", 7), (7, "0", 3), (10, "7", 6), (16, "0", 7), (23, "5", 2), (25, "3", 7)), glide=True)
pat(BA, "BAY AREA 4 LO-FI HYPHY", 98, 58, k="X.....x...x.....X.....x...x.....", c=BACK, h=rep("x...x...x...x..."), p1=rep("..g...g.", 32),
    b=bass((0, "0", 6), (6, "0", 4), (10, "5", 6), (16, "0", 6), (22, "0", 4), (26, "3", 6)))
pat(BA, "BAY AREA 5 HEAVY BASS", 96, 56, k="X..x......x..x..X..x......x.....", c=BACK, s=st(32, 15, 31, ch="g"), h=rep("x.x.x.x.x.x.x.x."), o=st(32, 6, 22, ch="o"),
    b=bass((0, "0", 3), (3, "c", 7), (10, "0", 3), (13, "5", 3), (16, "0", 3), (19, "c", 7), (26, "3", 6)))
pat(BA, "BAY AREA 6 SIDESHOW", 104, 54, k="X.x...x.x.x...x.X.x...x.x.x.x...", c=BACK, h=rep("x.x.x.x.x.x.x.xr"), p2=st(32, 3, 19, ch="o"),
    b=bass((0, "0", 2), (2, "0", 4), (6, "0", 2), (8, "c", 2), (10, "0", 4), (14, "3", 2), (16, "0", 2), (18, "0", 4), (22, "0", 2), (24, "c", 2), (26, "5", 6)))
pat(BA, "BAY AREA 7 SOUL CRUISE", 88, 60, k="X......x..x.....X..x......x.....", s=BACK, h=rep("xgxgxgxgxgxgxgxg"), o=st(32, 14, 30, ch="o"), r=st(32, 10, 26, ch="g"))
pat(BA, "BAY AREA 8 SNAP BOUNCE", 102, 56, k="X..x..x...x..x..X..x..x...x.....", c=BACK, p1=st(32, 4, 12, 20, 28, ch="o"), h=rep("x.o.x.o.x.o.x.o."),
    b=bass((0, "0", 3), (3, "0", 3), (6, "7", 4), (10, "0", 3), (13, "5", 3), (16, "0", 3), (19, "0", 3), (22, "c", 4), (26, "7", 6)))
pat(BA, "BAY AREA 9 VALLEJO", 94, 58, k="X.....x.x.....x.X.....x.x.......", c=BACK, h=rep("x.x.x.x.x.x.x.x."), p2=st(32, 7, 23, ch="g"),
    b=bass((0, "0", 6), (6, "3", 2), (8, "5", 6), (14, "7", 2), (16, "0", 6), (22, "3", 2), (24, "5", 8)), glide=True)
pat(BA, "BAY AREA 10 TURF", 108, 54, k="X..x..x...x.x...X..x..x...x.x.x.", c=BACK, h=rep("xoxoxoxoxoxoxoxo"), o=st(32, 14), cr=st(32, 0),
    b=bass((0, "0", 3), (3, "0", 3), (6, "c", 4), (10, "0", 2), (12, "5", 4), (16, "0", 3), (19, "0", 3), (22, "c", 4), (26, "0", 2), (28, "7", 4)))

# ---------------- Detroit 2026 (the half-time bounce at 92-100: soft or pitched-up snare, the second backbeat
# pushed half a beat late, the 808 is the kick with quick octave rolls, quiet hats, piano stabs as drums) ----------------
DN = "Detroit 2026"
LATE2 = st(32, 4, 14, 20, 30, ch="x")                  # beat 2, then beat 4 pushed late (the bounce)
pat(DN, "DETROIT 2026 1 BOUNCE", 96, 56, k="X..x..x...x.x..xX..x..x...x.x..x", s=LATE2, c=st(32, 3, 19, ch="o"), o=st(32, 6, 22, ch="o"), h=rep("g.g.g.g.g.g.g.g."),
    b=bass((0, "0", 3), (3, "0", 3), (6, "0", 4), (10, "0", 2), (12, "3", 3), (15, "c", 1), (16, "0", 3), (19, "0", 3), (22, "0", 4), (26, "0", 2), (28, "5", 3), (31, "c", 1)))
pat(DN, "DETROIT 2026 2 SPIN ROLL", 98, 56, k="X..x..x...x.....X..x..x...x.....", r=BACK, h=rep("o.g.o.g.o.g.o.g."), o=st(32, 14, 30, ch="o"),
    b="0..0..0...0.0c0c0..0..0...0.5c5c")
pat(DN, "DETROIT 2026 3 PIANO DRUMS", 94, 58, k="X.....x...x.....X.....x..x......", s=BACK, p2=rep("x.x.x.x.x.x.x.x."), h=rep("g...g...g...g..."),
    b=bass((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 6), (22, "0", 3), (25, "5", 7)))
pat(DN, "DETROIT 2026 4 SCAM SYNTH", 100, 54, k="X.x..x..x.x..x..X.x..x..x...x...", s=st(32, 4, 12, 20, 28, ch="o"), c=BACK, h=rep("xgxgxgxgxgxgxgxg"),
    b="0.0..0..3.3..5..0.0..0..7...5...")
pat(DN, "DETROIT 2026 5 MUTTER LOW", 92, 58, k="X......x..x.....X......x.x......", r=LATE2, h=rep("g.g.g.g.g.g.g.g."), o=st(32, 15, 31, ch="g"),
    b=bass((0, "0", 7), (7, "0", 3), (10, "A", 6), (16, "0", 7), (23, "0", 2), (25, "B", 7)), glide=True)
pat(DN, "DETROIT 2026 6 HYPE", 100, 54, k="X..x..x..x..x...X..x..x..x.x.x..", s=BACK, c=BACK, h=rep("o.o.o.o.o.o.o.o."), cr=st(32, 0), p1=st(32, 3, 11, 19, 27, ch="o"),
    b="0..0..0..0..3...0..0..5..3.3.cc.")
pat(DN, "DETROIT 2026 7 PITCHED SNARE", 96, 56, k="X..x......x..x..X..x....x.x.....", s=LATE2, h=rep("g.g.g.g.g.g.g.g."), o=st(32, 6, 16, 22),
    b=bass((0, "0", 3), (3, "0", 7), (10, "3", 3), (13, "5", 3), (16, "0", 3), (19, "0", 5), (24, "c", 2), (26, "0", 6)))
pat(DN, "DETROIT 2026 8 FLINT BLOWN", 98, 56, k="X..x..x...x..x..X..x..x...xx....", s=st(32, 4, 12, 20, 28, ch="X"), r=st(32, 7, 23, ch="g"), h=rep("g...g...g...g..."),
    b="0..0..0...0..0..0..0..0...00.c.c")
pat(DN, "DETROIT 2026 9 FREESTYLE SAMPLE", 98, 54, k="X..x..x...x.....X..x..x...x.x...", c=BACK, p1=rep("x.x.x.x.x.x.x.x."), o=st(32, 14, 30, ch="o"),
    b=bass((0, "0", 3), (3, "0", 3), (6, "0", 4), (10, "5", 6), (16, "0", 3), (19, "0", 3), (22, "0", 4), (26, "7", 6)))
pat(DN, "DETROIT 2026 10 RIO GLIDE", 94, 58, k="X......x..x.....X......x..x.....", s=LATE2, h=rep("o.g.o.g.o.g.o.g."), p2=st(32, 11, 27, ch="o"),
    b=bass((0, "0", 7), (7, "0", 3), (10, "5", 6), (16, "0", 7), (23, "0", 3), (26, "7", 6)), glide=True)

# ---------------- UK Drill (London, 138-146: tresillo hats on 16ths 1, 4, 7 with holes, snare on beat 3 of
# bar 1 and beat 4 of bar 2, kicks on 1 and the last 8th, gliding 808s, rim ticks, one open hat) ----------------
UK = "UK Drill"
UKS = st(32, 8, 28, ch="X")
pat(UK, "UK DRILL 1 TEMPLATE", 142, k=st(32, 0, 14, 16, 19, 22, 30), s=UKS, h=put(st(32, 0, 3, 6, 16, 19, 22), (15, "g"), (3, "o"), (19, "o")), p1=st(32, 0, 24, 30, ch="o"),
    b=bass((0, "0", 14), (14, "0", 2), (16, "3", 3), (19, "0", 3), (22, "5", 8), (30, "7", 2)), glide=True)
pat(UK, "UK DRILL 2 SKIPPY", 140, 52, k=st(32, 0, 10, 14, 16, 19, 22, 30), s=put(UKS, (22, "g")), h=put(st(32, 0, 3, 6, 8, 10, 11, 16, 19, 22, 24, 26, 27), (11, "g"), (27, "g")),
    r=st(32, 13, 29, ch="o"), b=bass((0, "0", 10), (10, "3", 4), (14, "0", 5), (19, "0", 3), (22, "A", 8), (30, "0", 2)), glide=True)
pat(UK, "UK DRILL 3 SLIDE", 144, k=st(32, 0, 14, 16, 22, 30), s=UKS, h=put(st(32, 0, 3, 6, 10, 16, 19, 22, 26), (12, "t"), (28, "t")), o=st(32, 20),
    b=bass((0, "0", 6), (6, "c", 8), (14, "0", 8), (22, "7", 8), (30, "5", 2)), glide=True)
pat(UK, "UK DRILL 4 DARK KEYS", 140, k=st(32, 0, 14, 16, 19, 30), s=put(UKS, (15, "g"), (31, "g")), h=st(32, 0, 3, 6, 16, 19, 22, 24), p1=st(32, 4, 20, ch="g"),
    b=bass((0, "0", 14), (14, "B", 2), (16, "0", 3), (19, "0", 11), (30, "3", 2)), glide=True)
pat(UK, "UK DRILL 5 GARAGE TOUCH", 140, 54, k=st(32, 0, 10, 14, 16, 26, 30), s=UKS, h=put(rep("x..x..x...x..x.."), (13, "o")), r=st(32, 7, 23, ch="o"),
    b=bass((0, "0", 10), (10, "0", 4), (14, "5", 2), (16, "0", 10), (26, "3", 4), (30, "0", 2)), glide=True)
pat(UK, "UK DRILL 6 RIPPLE KICKS", 142, k="x.........x.xx..x..x..x.....x.xx", s=UKS, h=st(32, 0, 3, 6, 16, 19, 22), o=st(32, 12),
    b=bass((0, "0", 10), (10, "0", 6), (16, "3", 6), (22, "0", 6), (28, "7", 4)), glide=True)
pat(UK, "UK DRILL 7 CINEMATIC", 138, k=st(32, 0, 14, 16, 22), s=UKS, h=st(32, 0, 3, 6, 9, 16, 19, 22, 25), cr=st(32, 0), p2=st(32, 30, ch="o"),
    b=bass((0, "0", 14), (14, "0", 2), (16, "A", 6), (22, "0", 10)), glide=True)
pat(UK, "UK DRILL 8 SPLIT SNARE", 144, k=st(32, 0, 14, 16, 19, 22), s=put(st(32, 8, 20, 28, ch="X"), (20, "x")), h=put(st(32, 0, 3, 6, 10, 16, 19, 22, 26), (30, "r")),
    b=bass((0, "0", 8), (8, "3", 6), (14, "0", 5), (19, "0", 3), (22, "5", 10)), glide=True)
pat(UK, "UK DRILL 9 RIM WORK", 142, k=st(32, 0, 14, 16, 19, 22, 30), s=UKS, r=rep("..x..x....x..x..", 32), h=st(32, 0, 6, 16, 22),
    b=bass((0, "0", 14), (14, "0", 2), (16, "0", 3), (19, "3", 3), (22, "5", 10)), glide=True)
pat(UK, "UK DRILL 10 STRIPPED", 140, k=st(32, 0, 14, 16, 30), s=UKS, h=put(st(32, 0, 3, 6, 16, 19, 22), (15, "g")),
    b=bass((0, "0", 14), (14, "0", 2), (16, "c", 14), (30, "0", 2)), glide=True)

# ---------------- NY Drill (Brooklyn / Bronx, 140-148: the UK skeleton with heavier kicks and 808s,
# long slides, sample drill and Jersey club crossovers) ----------------
NY = "NY Drill"
pat(NY, "NY DRILL 1 BROOKLYN", 144, k=st(32, 0, 10, 16, 19, 22, 30), s=UKS, h=put(st(32, 0, 3, 6, 8, 10, 12, 16, 19, 22, 24), (6, "t")), o=st(32, 26),
    b=bass((0, "0", 10), (10, "0", 6), (16, "c", 3), (19, "0", 3), (22, "A", 8), (30, "0", 2)), glide=True)
pat(NY, "NY DRILL 2 WOO", 146, k=st(32, 0, 3, 10, 16, 19, 22, 28), s=put(UKS, (12, "o")), c=UKS, h=put(st(32, 0, 3, 6, 10, 12, 16, 19, 22, 26), (28, "t")),
    b=bass((0, "0", 3), (3, "0", 7), (10, "3", 6), (16, "0", 3), (19, "0", 3), (22, "c", 6), (28, "0", 4)), glide=True)
pat(NY, "NY DRILL 3 SAMPLE DRILL", 142, k=st(32, 0, 10, 14, 16, 22, 26, 30), s=UKS, h=put(st(32, 0, 3, 6, 9, 12, 16, 19, 22, 25), (14, "r")), p1=st(32, 6, 22, ch="o"),
    b=bass((0, "0", 10), (10, "0", 4), (14, "5", 2), (16, "0", 6), (22, "0", 4), (26, "7", 6)), glide=True)
pat(NY, "NY DRILL 4 SEXY DRILL", 140, 54, k=st(32, 0, 10, 16, 26), c=UKS, s=st(32, 4, 20, ch="g"), h=rep("x..x..x.x..x..x."), o=st(32, 14, 30, ch="o"),
    b=bass((0, "0", 10), (10, "3", 6), (16, "5", 10), (26, "3", 6)), glide=True)
pat(NY, "NY DRILL 5 JERSEY CLUB", 142, k="X..X..X.X..X..X.X..X..X.X.X.X.X.", s=UKS, c=st(32, 4, 12, 20, 28, ch="o"), h=st(32, 0, 3, 6, 16, 19, 22),
    b=bass((0, "0", 6), (6, "0", 2), (8, "3", 8), (16, "0", 6), (22, "0", 2), (24, "5", 8)))
pat(NY, "NY DRILL 6 BRONX DARK", 144, k=st(32, 0, 14, 16, 19, 22, 30), s=UKS, h=st(32, 0, 3, 6, 16, 19, 22), r=st(32, 11, 27, ch="o"), p2=st(32, 24, ch="X"),
    b=bass((0, "0", 14), (14, "B", 2), (16, "0", 3), (19, "0", 3), (22, "C", 8), (30, "0", 2)), glide=True)
pat(NY, "NY DRILL 7 HEAVY 808", 146, k=st(32, 0, 3, 6, 16, 19, 22, 30), s=UKS, h=put(st(32, 0, 3, 6, 10, 16, 19, 22, 26), (12, "q")),
    b=bass((0, "0", 3), (3, "0", 3), (6, "c", 10), (16, "0", 3), (19, "0", 3), (22, "7", 8), (30, "c", 2)), glide=True)
pat(NY, "NY DRILL 8 PIANO", 140, k=st(32, 0, 10, 16, 22, 30), s=put(UKS, (31, "g")), h=st(32, 0, 3, 6, 9, 16, 19, 22, 25, 28), cr=st(32, 0),
    b=bass((0, "0", 10), (10, "5", 6), (16, "0", 6), (22, "3", 8), (30, "0", 2)), glide=True)
pat(NY, "NY DRILL 9 ROLL CALL", 144, k=st(32, 0, 10, 16, 19, 22), s=UKS, h=put(st(32, 0, 3, 6, 10, 16, 19, 22), (12, "t"), (14, "t"), (26, "r"), (27, "r")),
    b=bass((0, "0", 10), (10, "0", 6), (16, "3", 3), (19, "0", 3), (22, "A", 10)), glide=True)
pat(NY, "NY DRILL 10 BLOCK", 148, k=st(32, 0, 7, 10, 16, 19, 26, 30), s=UKS, c=UKS, h=st(32, 0, 3, 6, 16, 19, 22, 24), p1=st(32, 13, 29, ch="o"), o=st(32, 10),
    b=bass((0, "0", 7), (7, "0", 3), (10, "7", 6), (16, "0", 3), (19, "0", 7), (26, "5", 4), (30, "0", 2)), glide=True)

# ---------------- UK RnB (2-step garage swing, afroswing, drill-R&B, and live London soul) ----------------
UR = "UK RnB"
SHK = rep("ogxgogxgogxgogxg")
pat(UR, "UK RNB 1 TWO STEP", 132, 62, k="X.........x.....X.........x..x..", s=BACK, h=rep("..x...x...x...x."), p1=SHK)
pat(UR, "UK RNB 2 GARAGE SWING", 134, 64, k="X.......x.x.....X.........x.....", s=put(BACK, (15, "g")), r=st(32, 7, 23, ch="g"), h=rep("..x...x...x..xx."), p1=SHK)
pat(UR, "UK RNB 3 AFROSWING", 102, 58, k="X..x..x...x.....X..x..x...x.....", r=rep("..x..x....x..x.."), c=BACK, h=rep("x.x.x.x.x.x.x.x."), p1=SHK)
pat(UR, "UK RNB 4 AFRO SLOW", 98, 60, k="X.....x...x.....X.....x...x..x..", c=st(32, 4, 12, 20, 28, ch="o"), r=rep("...x..x....x..x."), p2=st(32, 14, 30, ch="o"), h=rep("x.o.x.o.x.o.x.o."),
    b=bass((0, "0", 6), (6, "0", 4), (10, "5", 6), (16, "0", 6), (22, "0", 4), (26, "3", 6)))
pat(UR, "UK RNB 5 DRILL RNB", 142, k=st(32, 0, 14, 16, 22), s=st(32, 8, 28, ch="x"), h=st(32, 0, 3, 6, 16, 19, 22), r=st(32, 12, ch="g"),
    b=bass((0, "0", 14), (14, "0", 2), (16, "3", 6), (22, "5", 10)), glide=True)
pat(UR, "UK RNB 6 LONDON SOUL", 82, 60, k=phrase("X......x..x.....", "X......x....x..."), r=phrase("....x.......x...", fill="....x..........."),
    s=bars("." * 16, "." * 16, "." * 16, "............ggoX"), h=phrase("xgogxgogxgogxgog", fill="xgogxgogxgog...."), cr=CRASH4)
pat(UR, "UK RNB 7 LATE NIGHT", 76, 62, k="X.......x..x....X.......x.......", c=st(32, 8, 24, ch="o"), s=st(32, 8, 24, ch="x"), h=rep("x.xgx.xgx.xgx.xg"), o=st(32, 30, ch="o"),
    b=bass((0, "0", 8), (8, "5", 3), (11, "3", 5), (16, "0", 8), (24, "7", 8)), glide=True)
pat(UR, "UK RNB 8 SPEED GARAGE", 130, 58, k="X...X...X...X...X...X...X...X...", s=BACK, o=rep("..x...x...x...x."), p1=SHK, b=bass((2, "0", 2), (6, "0", 2), (10, "3", 2), (14, "5", 2), (18, "0", 2), (22, "0", 2), (26, "7", 2), (30, "5", 2)))
pat(UR, "UK RNB 9 BEDROOM", 88, 58, k="X......x..x.....X......x....x...", s=BACK, h=rep("x.o.x.o.x.o.x.o."), r=st(32, 14, 30, ch="g"), p2=st(32, 6, 22, ch="g"))
pat(UR, "UK RNB 10 PIRATE RADIO", 136, 62, k="X.........x..x..X.......x.x.....", s=put(BACK, (7, "g"), (23, "g")), h=rep("..x...x...x...x."), o=st(32, 14, 30), p1=SHK)

# ---------------- live 4-bar additions to the existing acoustic styles ----------------
pat(N, "NEO SOUL 11 LIVE POCKET", 84, 62, k=phrase("X......x..x.....", "X.....x...x..x..", "X......x..x.....", "X.....x...x....."),
    s=phrase("....X..g...gX..g", "....X..g.g..X..g", "....X..g...gX..g", "....X..g.g..XgXg"), h=phrase("xgogxgogxgogxgo.", fill="xgogxgogxgog...."), o=phrase("...............o", fill="................"), cr=CRASH4)
pat(N, "NEO SOUL 12 CROSS STICK", 78, 64, k=phrase("X.......x..x....", "X......x..x....."), r=phrase("....x.......x...", fill="....x..........."), s=phrase("..g......g....g.", fill="..g......g..ggoX"),
    h=phrase("x.oxx.oxx.oxx.ox", fill="x.oxx.oxx.ox...."), cr=CRASH4)
pat(N, "NEO SOUL 13 BROKEN TIME", 90, 60, k=phrase("X..x...x..x.....", "X..x.....x..x..."), s=phrase("....X.g...g.X...", "....X.g..g..X.g."),
    h=phrase("x.x.x.x.x.x.x.x."), p1=phrase("gogogogogogogogo"), cr=CRASH4)
pat(BB, "BOOM BAP 11 LIVE BREAK", 92, 58, k=phrase("X.x.......x..x..", "X.x....x..x....."), s=phrase("....X..g.g..X...", "....X..g.g..X..g", fill="....X..g.g..XgXX"),
    h=phrase("x.x.x.x.x.x.x.x."), o=phrase("..............o.", fill="................"), cr=CRASH4)
pat(BB, "BOOM BAP 12 SP DUST", 90, 62, k=phrase("X......x..x.....", "X......x..x..x.."), s=phrase("....X.......X..."), h=phrase("x.ogx.ogx.ogx.og"), r=phrase("..........g.....", "......g.........g"[:16]))
pat(BB, "BOOM BAP 13 HARD KNOCK", 94, 56, k=phrase("X......x..X.....", "X.x....x..X....."), s=phrase("....X.......X...", fill="....X.......X.XX"), h=phrase("x...x...x...x..."), p2=phrase("..............o."))


from collections import Counter
cnt = Counter(p["style"] for p in P)
for st, n in cnt.items():
    if st != D: assert n >= 10, (st, n)
assert len(cnt) == 40, cnt
names = [p["name"] for p in P]
assert len(set(names)) == len(names)
for p in P:
    for key, by_lane in FEEL_NAMES.get(p["name"], FEEL.get(p["style"], {})).items():
        used = {lane: v for lane, v in by_lane.items() if lane in p["lanes"]}
        if used: p[key] = used
VALID = set(".xXogrqt")
for p in P:
    for key in ("swingLanes", "shift", "ghostChance"):
        for lane, v in p.get(key, {}).items():
            assert lane in LANES and lane in p["lanes"], (p["name"], key, lane)
            assert (-24 <= v <= 24) if key == "shift" else (0 <= v <= 1), (p["name"], key, v)
    for lane, s in p["lanes"].items():
        allowed = set(".-0123456789abcABCDEFGHIJKL") if lane == "b" else VALID
        bad = set(s) - allowed
        assert not bad, (p["name"], lane, bad)
    assert 60 <= p["bpm"] <= 180 and 50 <= p["swing"] <= 66
out = os.path.join(os.path.dirname(__file__), "..", "BreakBoss.swiftpm", "Resources", "PatternBank.json")
json.dump({"version": 1, "patterns": P}, open(out, "w"), indent=1)
print(len(P), "patterns;", dict(cnt))
