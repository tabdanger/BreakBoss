#!/usr/bin/env python3
"""Builds BreakBoss.swiftpm/Resources/PatternBank.json, the factory PRESETS (patterns only).

Started fresh on Oct 17 from the drum research (/mnt/project-files/research/realistic-drums-and-genres.md):
17 styles, 10 presets each, in the order of the genre guide (West Coast, which replaced Bay Area 2026
on Oct 20, has 20). Oct 24: 17 more from Tyrone's genre list, 10 each, after the BK Editions. Every pattern is written the way the genre's producers and drummers play it (tempo,
swing, where the kick and snare sit, what the hats do, ghost notes, fills), "in the style of", never a
transcription.

Lanes are step strings, 16 steps per bar (1, 2 or 4 bars). Codes:
  .  rest          x  hit (0.82)    X  accent (1.0)   o  medium (0.62)   g  ghost (0.38)
  r  two 32nds     q  four 64ths    t  triplet: three hits across this step and the next
  808 lane: 0-9 = semitones up, a b c = 10 11 12, A-L = 1..12 down, - = hold, . = rest
Lane keys: k kick, s snare, c clap, r rim / snap, h hat, o open hat, b 808, p1 p2 percussion,
lt ht toms, cr cymbal (crash or ride, whichever the kit has).
Swing is MPC-style percent (50 = straight).
Feel (optional, by lane): swingLanes = a track's own swing (0..1 like the SWING knob, 0 = straight),
shift = pushed early (-) or pulled late (+) in ticks (96 a beat), ghostChance = how often its ghost
notes (velocity g) play, 0..1.
"""
import json, os
from collections import Counter

LANES = {"k": 0, "s": 1, "c": 2, "r": 3, "h": 4, "o": 5, "b": 6, "p1": 7, "p2": 8, "lt": 9, "ht": 10, "cr": 11}
P = []
def pat(style, name, bpm, swing=50, glide=False, **lanes):
    for key, v in lanes.items():
        assert key in LANES, key
        assert len(v) in (16, 32, 64), (name, key, len(v))
    n = {len(v) for v in lanes.values()}
    assert len(n) == 1, (name, n)
    P.append({"style": style, "name": name, "bpm": bpm, "swing": swing, "glide": glide, "lanes": lanes})

# Browser order: the genre guide's order.
STYLES = ["Neo Soul", "Dilla Time", "Boom Bap", "90s Rap", "70s Soul", "80s Breaks", "Rock", "Trap", "Alt Trap",
          "Drill", "UK Drill", "NY Drill", "Detroit 2026", "West Coast", "RnB", "90s RnB", "UK RnB"]
# Played by one drummer: never more than two hand-played sounds on a step.
DRUMMER = {"Neo Soul", "Dilla Time", "70s Soul", "80s Breaks", "Rock", "Vintage R&B", "Live Soul", "Live Pop"}

# The feel each style is played with (the research: Dilla's snare early over a straight kick and swung hats,
# neo soul snares early and kicks late, 90s hats swung harder than the kick and snare, soul backbeats a hair
# behind, R&B snares late, ghost notes that come and go).
FEEL = {
    "Neo Soul": {"shift": {"s": -3, "r": -3, "k": 2}, "ghostChance": {"s": 0.7}},
    "Dilla Time": {"swingLanes": {"h": 0.55, "k": 0}, "shift": {"s": -4, "c": -4, "r": -3, "k": 2}, "ghostChance": {"s": 0.7, "h": 0.85}},
    "Boom Bap": {"swingLanes": {"h": 0.9}, "ghostChance": {"s": 0.8}},
    "90s Rap": {"swingLanes": {"h": 0.9}, "shift": {"c": 2}, "ghostChance": {"s": 0.8}},
    "70s Soul": {"shift": {"s": 2}, "ghostChance": {"s": 0.75}},
    "80s Breaks": {"ghostChance": {"s": 0.8}},
    "RnB": {"swingLanes": {"h": 0.5}, "shift": {"s": 3, "c": 3, "r": 2}},
    "UK RnB": {"shift": {"s": 3, "c": 3, "r": 2}},
    "Trapsoul": {"swingLanes": {"h": 0.4}, "shift": {"s": 3, "c": 3, "r": 2}},
    "Phonk": {"swingLanes": {"h": 0.3}},
    "Memphis": {"swingLanes": {"h": 0.3}, "shift": {"c": 1}},
    "Toronto R&B": {"swingLanes": {"h": 0.3}, "shift": {"s": 4, "c": 4, "r": 3}},
    "Vintage R&B": {"shift": {"s": 2}, "ghostChance": {"s": 0.75}},
    "2000s R&B": {"shift": {"c": 2, "s": 1}},
    "Live Soul": {"shift": {"s": 2, "k": 1}, "ghostChance": {"s": 0.75}},
    "East Coast": {"swingLanes": {"h": 0.8}, "ghostChance": {"s": 0.8}},
    "Lo-fi": {"swingLanes": {"h": 0.7}, "shift": {"s": 3, "r": 3}, "ghostChance": {"s": 0.6, "h": 0.8}},
    "Afrobeats": {"swingLanes": {"p1": 0.35, "h": 0.3}, "shift": {"r": -1}},
    "Live Pop": {"shift": {"s": 1}, "ghostChance": {"s": 0.8}},
    "World & Latin": {"swingLanes": {"p1": 0.3}},
}
FEEL_NAMES = {
    "NEO SOUL 3 BROKEN TIME": {"swingLanes": {"h": 0.5, "k": 0}, "shift": {"s": -3}, "ghostChance": {"s": 0.7}},
    "BOOM BAP 2 SP DUST": {"swingLanes": {"h": 0.9}, "shift": {"r": -2}},
}

def st(n, *hits, ch="x"):
    """A lane of n steps with `ch` at the given step numbers (0-based)."""
    l = ["."] * n
    for h in hits: l[h] = ch
    return "".join(l)
def two(bar):            # same bar twice (2 bars, 32 steps)
    assert len(bar) == 16, bar
    return bar * 2
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
def bars(*b):
    for x in b: assert len(x) % 16 == 0 and x, x
    return "".join(b)
def phrase(main, b2=None, b3=None, fill=None):
    """Four bars: the groove, a variation, the groove again, then a fill bar."""
    return bars(main, b2 or main, b3 or main, fill or b2 or main)
HALF = st(32, 8, 24, ch="X")                     # half-time backbeat (beat 3 of each bar)
BACK = st(32, 4, 12, 20, 28, ch="X")             # 2 and 4
HAT16 = "XgogxgogXgogxgog"                       # 16ths, loud on the beat, soft in between
HAT8 = "X.o.x.o.X.o.x.o."                        # 8ths, leaning on the beat
CRASH4 = st(64, 0)                               # crash on the 1 of the phrase (lands after the fill)

# ---------------- Neo Soul (65-95, swing 58-66: cross-stick on 2 and 4 with ghosts around it, lazy kick
# anticipations on the "a" of 2 and 3, snare early and kick late; Questlove, D'Angelo, Chris Dave,
# Karriem Riggins, Glasper, Kaytranada) ----------------
N = "Neo Soul"
pat(N, "NEO SOUL 1 VOODOO POCKET", 84, 62, k=phrase("X......x..x.....", "X.....x...x..x..", "X......x..x.....", "X.....x...x....."),
    s=phrase("....X..g...gX..g", "....X..g.g..X..g", "....X..g...gX..g", "....X..g.g..XgXg"), h=phrase("xgogxgogxgogxgo.", fill="xgogxgogxgog...."), o=phrase("...............o", fill="................"), cr=CRASH4)
pat(N, "NEO SOUL 2 CROSS STICK", 78, 64, k=phrase("X.......x..x....", "X......x..x....."), r=phrase("....x.......x...", fill="....x..........."), s=phrase("..g......g....g.", fill="..g......g..ggoX"),
    h=phrase("x.oxx.oxx.oxx.ox", fill="x.oxx.oxx.ox...."), cr=CRASH4)
pat(N, "NEO SOUL 3 BROKEN TIME", 90, 60, k=phrase("X..x...x..x.....", "X..x.....x..x..."), s=phrase("....X.g...g.X...", "....X.g..g..X.g."),
    h=phrase("x.x.x.x.x.x.x.x."), p1=phrase("gogogogogogogogo"), cr=CRASH4)
pat(N, "NEO SOUL 4 LAZY ONE", 82, 62, k=two("X.....x...x....."[:16]), r=BACK.replace("X", "x"), s=two("..g....g.g....g."),
    h=two("x.o.x.o.x.o.x.o."))
pat(N, "NEO SOUL 5 RIDE BELL", 88, 60, k=phrase("X.......x.x.....", "X.......x.x..x.."), s=phrase("..g.X..g...gX...", fill="..g.X..g...gXgXX"),
    cr=phrase("x.ox.ox.x.ox.ox.", fill="x.ox.ox.x......."), h=phrase("....g.......g..."))
pat(N, "NEO SOUL 6 HOUSE PARTY", 94, 58, k=two("X..x..x...x..x.."), c=two("....x.......x..."), h=two("..x...x...x...x."),
    p1=rep("ogxgogxgogxgogxg"), r=st(32, 15, 31, ch="g"))
pat(N, "NEO SOUL 7 QUIET STORM", 70, 60, k=phrase("X.......x..x....", "X......x...x...."), r=phrase("....x.......x...", fill="....x..........."),
    h=phrase("o.g.o.g.o.g.o.g.", fill="o.g.o.g.o.g....."), s=bars("." * 48, "...........gooxX"), cr=CRASH4)
pat(N, "NEO SOUL 8 SPLIT KICK", 80, 62, k=phrase("X..x....x..x....", "X..x......x....."), s=phrase("....X..g..g.X...", fill="....X..g..g.X.gg"),
    h=phrase("x.ogx.ogx.ogx.og", fill="x.ogx.ogx.og...."), cr=CRASH4)
pat(N, "NEO SOUL 9 SNARE DRAG", 76, 64, k=two("X......x..x....."), s=two("....X..r....X.g."), h=put(two("x.x.x.x.x.x.x.x."), (30, ".")), o=st(32, 30, ch="o"))
pat(N, "NEO SOUL 10 SUNDAY PEDAL", 86, 60, k=two("X.....x.x......."), s=two("....X.......X..."), o=two("..o...o...o...o."), r=st(32, 7, 23, ch="g"), p2=st(32, 14, 30, ch="g"))

# ---------------- Boom Bap (85-98, MPC / SP-1200 swing 54-62: kick on 1 with a pickup on the "and" of 2 or
# the "e" of 3, hard snare on 2 and 4, the hats carry the dynamics, open hat on the last "and";
# DJ Premier, Pete Rock, RZA, Large Professor, Buckwild, Alchemist) ----------------
BB = "Boom Bap"
pat(BB, "BOOM BAP 1 LIVE BREAK", 92, 58, k=phrase("X.x.......x..x..", "X.x....x..x....."), s=phrase("....X..g.g..X...", "....X..g.g..X..g", fill="....X..g.g..XgXX"),
    h=phrase("x.x.x.x.x.x.x.x."), o=phrase("..............o.", fill="................"), cr=CRASH4)
pat(BB, "BOOM BAP 2 SP DUST", 90, 62, k=phrase("X......x..x.....", "X......x..x..x.."), s=phrase("....X.......X..."), h=phrase("x.ogx.ogx.ogx.og"), r=phrase("..........g.....", "......g........."))
pat(BB, "BOOM BAP 3 HARD KNOCK", 94, 56, k=phrase("X......x..X.....", "X.x....x..X....."), s=phrase("....X.......X...", fill="....X.......X.XX"), h=phrase("x...x...x...x..."), p2=phrase("..............o."))
pat(BB, "BOOM BAP 4 CHOPPED", 94, 56, k="X.....x...x.....X......x..x.....", s=BACK, h=two(HAT8), o=st(32, 14, 30, ch="o"))
pat(BB, "BOOM BAP 5 HORNS LOOP", 92, 60, k="X......x..x..x..X......x..x.....", s=put(BACK, (15, "g")), h=two("xgxoxgxoxgxoxgxo"), p1=two("....x.......x..."))
pat(BB, "BOOM BAP 6 BASEMENT", 90, 58, k="X..x......x.....X..x.....x.x....", s=BACK, h=two("x...x...x...x..x"), r=st(32, 7, 23, ch="g"))
pat(BB, "BOOM BAP 7 PICKUP", 88, 62, k="X......x........X.........x.....", s=BACK, h=two("x.ogx.ogx.ogx.og"), o=st(32, 14, 30, ch="o"))
pat(BB, "BOOM BAP 8 DOUBLE KICK", 95, 56, k="XX......x.x.....XX......x......x", s=BACK, h=two("x.x.x.x.x.x.x.x."))
pat(BB, "BOOM BAP 9 OPEN HATS", 86, 60, k="X.........x.x...X.......x.......", s=BACK, h=two("x...x...x...x..."), o=two("..o...o...o...o."))
pat(BB, "BOOM BAP 10 GHOST TOWN", 90, 58, k="X.....x...x.....X.....x.....x...", s=two("....X..g.g..X..g"), h=two("x.x.x.x.x.x.x.x."), cr=st(32, 0))

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

# ---------------- West Coast (Oct 20, replaces Bay Area 2026; Tyrone: "remove ALL the current WEST COAST patterns
# and replace them with 20 fresh patterns in the style of these loops"). Learned from his West Coast drum loops
# (LA, Cali and NorCal bounce at 86-102: clap on 2 and 4 every bar, the kick bouncing on the 1, the "a" of 1 and
# the "and" of 2, sparse syncopated hats with open hats on the off-beats, rim and snare pickups into the next
# bar) by tools/learn_west_coast.py (tools/learned_westcoast.json; the audio itself never ships). Each preset is
# four bars of one loop. Split from full mixes, so a few things are cleaned up: a snare, clap or rim on the kick's
# step that isn't a backbeat is the kick's own crack, the kick's soft hits play medium (its low end, not a
# ghost), one loop's kick reads as hats (its click), so it plays as the kick, and one loop's clap reads as hats. Tops loops (no low end) play
# the kick of another of his loops, off the steps where their backbeat lands (and its backbeat, for the one
# loop of hats alone). ----------------
WC = "West Coast"
WEST_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "learned_westcoast.json")
# (name, loop, its four bars, the loop and bars the kick comes from when it has none of its own)
WEST = [
    ("WEST COAST 1 BOUNCE BACK", "BABYSTONEGORRILAS DRUMS", [0, 1, 2, 3], None),
    ("WEST COAST 2 DROP BAR", "BABYSTONEGORRILAS DRUMS", [4, 5, 6, 7], None),
    ("WEST COAST 3 SLOW ROLL", "BIGSAD1900 DRUM LOOP", [0, 1, 2, 3], None),
    ("WEST COAST 4 HAT ROLLS", "WEST COAST X LA DRUMS", [4, 5, 6, 7], None),
    ("WEST COAST 5 THREE KICKS", "BIGSAD1900 DRUMS", [4, 5, 6, 7], None),
    ("WEST COAST 6 ONE CLAP", "BIGSAD1900 DRUMS", [12, 13, 14, 15], None),
    ("WEST COAST 7 NORCAL BOUNCE", "EBK X NORCAL DRUMS", [4, 5, 6, 7], None),
    ("WEST COAST 8 CALI KNOCK", "CALI DRUMS (FAVS)", [0, 1, 2, 3], None),
    ("WEST COAST 9 CALI SKIP", "CALI DRUMS (FAVS)", [4, 5, 6, 7], None),
    ("WEST COAST 10 OPEN ONE", "CALI DRUMS (FAVS)", [8, 9, 10, 11], ("CALI DRUMS (FAVS)", [0, 1, 2, 3])),
    ("WEST COAST 11 NORCAL STOMP", "EBK X NORCAL DRUMS", [0, 1, 2, 3], None),
    ("WEST COAST 12 NORCAL OPEN", "EBK X NORCAL DRUMS", [8, 9, 10, 11], ("EBK X NORCAL DRUMS", [4, 5, 6, 7])),
    ("WEST COAST 13 FILTERED", "FILTERED LA DRUMS", [0, 1, 2, 3], ("BIGSAD1900 DRUMS", [16, 17, 18, 19])),
    ("WEST COAST 14 KNOCK AND SNARE", "HIP HOP DRUMS", [0, 1, 2, 3], None),
    ("WEST COAST 15 OPEN HAT RIDE", "LA BLUEBUCKSCLAN DRUMS", [0, 1, 2, 3], ("LA DRUMS (FAVS)", [4, 5, 6, 7])),
    ("WEST COAST 16 LA STEP", "LA DRUMS (FAVS)", [0, 1, 2, 3], None),
    ("WEST COAST 17 LA HAT RUN", "LA DRUMS (FAVS)", [4, 5, 6, 7], None),
    ("WEST COAST 18 HAT SLIDE", "MODERN WEST COAST DRUMS", [0, 1, 2, 3], ("BIGSAD1900 DRUM LOOP", [0, 1, 2, 3])),
    ("WEST COAST 19 CLAP CRUISE", "WEST COAST DRUMS (FAVS)", [0, 1, 2, 3], ("WEST COAST X LA DRUMS", [0, 1, 2, 3])),
    ("WEST COAST 20 HAT SKIPS", "WEST COAST X LA DRUMS", [0, 1, 2, 3], None),
]
KICK_IS_HATS = {"HIP HOP DRUMS"}
CLAP_IS_HATS = {"WEST COAST X LA DRUMS"}          # its clap on 2 and 4 reads as hats
def west_coast():
    loops = {lp["title"]: lp for lp in json.load(open(WEST_FILE))["learned"]}
    take = lambda lane, bars: "".join(lane[b * 16:b * 16 + 16] for b in bars)
    for name, title, bars, kick_from in WEST:
        lp = loops[title]
        lanes = {k: take(v, bars) for k, v in lp["lanes"].items()}
        if title in KICK_IS_HATS:
            lanes["k"] = lanes.pop("h")
            lanes.pop("r", None)
        if title in CLAP_IS_HATS:
            h = lanes["h"]
            lanes["c"] = "".join("X" if h[j] != "." and j % 16 in (4, 12) else "." for j in range(len(h)))
            lanes["h"] = "".join("." if j % 16 in (4, 12) else ch for j, ch in enumerate(h))
        if kick_from:
            assert not lanes.get("k", "").strip(".") or title == "MODERN WEST COAST DRUMS", name   # that one's kick plays only on bars 1 and 5
            src = loops[kick_from[0]]["lanes"]
            if not (lanes.get("s") or lanes.get("c")):          # a hats loop: the other loop's backbeat too
                lanes.update({b: take(src[b], kick_from[1]) for b in ("s", "c") if b in src})
            back = lanes.get("s") or lanes.get("c")
            lanes["k"] = "".join("." if back[j] != "." and j % 16 in (4, 12) else ch for j, ch in enumerate(take(src["k"], kick_from[1])))
            lanes.pop("r", None) if title == "MODERN WEST COAST DRUMS" else None
        lanes["k"] = lanes["k"].replace("g", "o")
        for lane in ("s", "c", "r"):
            if lane in lanes:
                lanes[lane] = "".join("." if lanes["k"][j] != "." and j % 16 not in (4, 12) else ch for j, ch in enumerate(lanes[lane]))
        lanes = {k: v for k, v in lanes.items() if v.strip(".")}
        assert len(lanes["k"]) == 64 and sum((lanes.get("s", "") + "." * 64)[j] != "." or (lanes.get("c", "") + "." * 64)[j] != "." for j in range(4, 64, 8)) >= 4, name
        pat(WC, name, lp["bpm"], 50, **{k: lanes[k] for k in LANES if k in lanes})
west_coast()

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


# ---------------- Trap (Atlanta, 130-160, nearly straight: clap on beat 3, the kick follows the 808 on the
# offbeats, 8th or 16th hats with rolls (32nds, 64ths, triplets) into the snare or at the end of the bar,
# a new hat pattern every couple of bars; Zaytoven, Metro Boomin, Southside, Wheezy, Tay Keith) ----------------
T = "Trap"
pat(T, "TRAP 1 ATL BOUNCE", 140, k=st(32, 0, 7, 10, 16, 23, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (22, "t")),
    b=bass((0, "0", 7), (7, "0", 3), (10, "3", 6), (16, "0", 7), (23, "0", 3), (26, "5", 6)))
pat(T, "TRAP 2 TRIPLET HATS", 145, k=st(32, 0, 11, 16, 27), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (4, "t"), (20, "t"), (28, "t")),
    b=bass((0, "0", 11), (11, "0", 5), (16, "7", 11), (27, "5", 5)))
pat(T, "TRAP 3 ROLL CALL", 140, k=st(64, 0, 10, 16, 26, 32, 42, 48, 58, 61), c=st(64, 8, 24, 40, 56, ch="X"),
    h=put(rep("x.x.x.x.x.x.x.x.", 64), (22, "r"), (23, "r"), *[(i, "x") for i in range(33, 48, 2)], (60, "q"), (61, "q"), (62, "q")),
    b=bass((0, "0", 10), (10, "0", 6), (16, "3", 10), (26, "0", 6), (32, "0", 10), (42, "0", 6), (48, "5", 10), (58, "7", 3), (61, "c", 3), n=64))
pat(T, "TRAP 4 CHURCH KEYS", 138, k=st(32, 0, 3, 6, 16, 19, 22, 30), c=HALF, s=st(32, 8, 24, ch="o"), h=rep("xoxoxoxoxoxoxoxo"), o=st(32, 14),
    b=bass((0, "0", 3), (3, "0", 3), (6, "7", 10), (16, "0", 3), (19, "0", 3), (22, "5", 8), (30, "0", 2)))
pat(T, "TRAP 5 DARK SPACE", 142, k=st(32, 0, 14, 16, 26), c=HALF, h=put(rep("x...x...x...x..."), (12, "t"), (28, "q")), o=st(32, 6, 22, ch="o"), cr=st(32, 0),
    b=bass((0, "0", 14), (14, "0", 2), (16, "A", 10), (26, "0", 6)), glide=True)
pat(T, "TRAP 6 KNOCK", 145, k=st(32, 0, 2, 7, 10, 16, 18, 23, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (30, "r"), (31, "r")), s=st(32, 15, 31, ch="g"),
    b=bass((0, "0", 2), (2, "0", 5), (7, "0", 3), (10, "3", 6), (16, "0", 2), (18, "0", 5), (23, "0", 3), (26, "a", 6)))
pat(T, "TRAP 7 RIM BOUNCE", 150, 54, k=st(32, 0, 6, 10, 16, 22, 26), c=HALF, r=st(32, 3, 11, 19, 27, ch="o"), h=put(rep("x.x.x.x.x.x.x.x."), (14, "t"), (30, "t")),
    b=bass((0, "0", 6), (6, "0", 4), (10, "5", 6), (16, "0", 6), (22, "0", 4), (26, "7", 6)))
pat(T, "TRAP 8 MEMPHIS RUN", 160, k=st(32, 0, 3, 6, 11, 16, 19, 22, 27), c=HALF, h=rep("x.xxx.xxx.xxx.xx"), p1=st(32, 4, 20, ch="o"),
    b=bass((0, "0", 3), (3, "0", 3), (6, "3", 5), (11, "0", 5), (16, "0", 3), (19, "0", 3), (22, "5", 5), (27, "7", 5)))
pat(T, "TRAP 9 64TH RAMP", 140, k=st(32, 0, 10, 16, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (28, "q"), (29, "q"), (30, "q"), (31, "q")), o=st(32, 22),
    b=bass((0, "0", 10), (10, "0", 6), (16, "3", 10), (26, "5", 6)))
pat(T, "TRAP 10 DROP OUT", 140, k=bars(st(16, 0, 7, 10), st(16, 0, 7, 10), st(16, 0, 7, 10), st(16, 0)), c=bars(st(16, 8, ch="X"), st(16, 8, ch="X"), st(16, 8, ch="X"), "." * 16),
    h=bars(rep("x.x.x.x.x.x.x.x.", 16), put(rep("x.x.x.x.x.x.x.x.", 16), (14, "t")), rep("xxxxxxxxxxxxxxxx", 16), "." * 12 + "qqqq"),
    b=bass((0, "0", 7), (7, "0", 3), (10, "3", 6), (16, "0", 7), (23, "0", 3), (26, "5", 6), (32, "0", 7), (39, "0", 3), (42, "3", 6), (48, "0", 16), n=64))

# ---------------- Drill (Chicago, 130-145: trap's bones with busier snares, crashes, bells and brass hits,
# shorter 808s with few slides; Young Chop, Chief Keef, DJ L, Leek-E-Leek, Chopsquad DJ, ChaseTheMoney) ----------------
DR = "Drill"
pat(DR, "DRILL 1 CHOP HOUSE", 140, k=st(32, 0, 3, 10, 16, 19, 26), s=put(HALF, (6, "o"), (30, "o")), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (12, "t"), (28, "t")),
    p1=st(32, 0, 6, 16, 22, ch="o"), cr=st(32, 0), b=bass((0, "0", 3), (3, "0", 3), (10, "3", 4), (16, "0", 3), (19, "0", 3), (26, "5", 4)))
pat(DR, "DRILL 2 BRASS STABS", 138, k=st(32, 0, 7, 16, 23, 26), s=put(HALF, (14, "o"), (15, "o")), c=HALF, h=rep("x.x.x.x.x.x.x.x."), p2=st(32, 0, 3, 16, 19, ch="X"),
    b=bass((0, "0", 4), (7, "0", 4), (16, "3", 4), (23, "0", 3), (26, "5", 4)))
pat(DR, "DRILL 3 BELL RIDE", 142, k=st(32, 0, 10, 16, 22, 26), c=HALF, s=st(32, 30, 31, ch="o"), p1=rep("x.o.x.o.x.o.x.o."), h=st(32, 4, 12, 20, 28),
    b=bass((0, "0", 4), (10, "0", 4), (16, "7", 4), (22, "5", 3), (26, "0", 4)))
pat(DR, "DRILL 4 TRIPLET SNARE", 140, k=st(32, 0, 3, 11, 16, 19, 27), s=put(HALF, (28, "t"), (30, "t")), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (6, "t")),
    b=bass((0, "0", 3), (3, "0", 4), (11, "3", 4), (16, "0", 3), (19, "0", 4), (27, "5", 4)))
pat(DR, "DRILL 5 CRASH EVERY BAR", 144, k=st(32, 0, 6, 10, 16, 22, 26), c=HALF, s=st(32, 8, 15, 24, 31, ch="x"), h=rep("x.x.x.x.x.x.x.x."), cr=st(32, 0, 16),
    b=bass((0, "0", 4), (6, "0", 3), (10, "3", 4), (16, "0", 4), (22, "0", 3), (26, "a", 4)))
pat(DR, "DRILL 6 COLD STREETS", 136, k=st(32, 0, 14, 16, 30), c=HALF, h=put(rep("x...x...x...x..."), (10, "t"), (26, "t")), p1=st(32, 6, 22, ch="o"), o=st(32, 20),
    b=bass((0, "0", 6), (14, "0", 2), (16, "3", 6), (30, "0", 2)))
pat(DR, "DRILL 7 SHORT 808", 140, k=st(32, 0, 2, 7, 10, 16, 18, 23, 26), c=HALF, s=st(32, 12, 28, ch="o"), h=rep("x.xxx.x.x.xxx.x."),
    b=bass((0, "0", 2), (2, "0", 2), (7, "3", 2), (10, "0", 2), (16, "0", 2), (18, "0", 2), (23, "5", 2), (26, "7", 2)))
pat(DR, "DRILL 8 STORYTELLER", 135, k=st(32, 0, 11, 16, 27), c=HALF, s=st(32, 8, 24, ch="x"), r=st(32, 3, 19, ch="o"), h=put(rep("x.x.x.x.x.x.x.x."), (22, "r"), (23, "r")),
    b=bass((0, "0", 6), (11, "0", 4), (16, "5", 6), (27, "3", 4)))
pat(DR, "DRILL 9 STADIUM", 145, k=st(64, 0, 10, 16, 26, 32, 42, 48), c=st(64, 8, 24, 40, 56, ch="X"), s=st(64, 8, 24, 40, 56, ch="x"), h=rep("x.x.x.x.x.x.x.x.", 64)[:56] + "." * 8,
    ht=st(64, 56, 57, ch="X"), lt=st(64, 58, 59, 60, ch="X"), cr=st(64, 0, 32), b=bass((0, "0", 4), (10, "0", 4), (16, "3", 4), (26, "0", 4), (32, "0", 4), (42, "5", 4), (48, "7", 8), n=64))
pat(DR, "DRILL 10 GHOST SNARES", 140, k=st(32, 0, 6, 16, 22, 26), c=HALF, s=put(HALF, (5, "g"), (13, "g"), (21, "g"), (29, "g")), h=rep("x.x.x.x.x.x.x.x."), p1=st(32, 14, 30, ch="o"),
    b=bass((0, "0", 4), (6, "0", 4), (16, "3", 4), (22, "0", 4), (26, "5", 4)))

# ---------------- RnB (modern: 60-90 felt, programmed double time so the snare sits on beat 3; soft, sparse
# kicks, the snare layered with a rim or clap and sitting late, hats swung on their own, a long 808 under the
# chord root; 40, Boi-1da, Hit-Boy, Mustard, Kaytranada, Carter Lang, Nineteen85) ----------------
R = "RnB"
pat(R, "RNB 1 NIGHT DRIVE", 136, k=st(32, 0, 11, 16, 27, ch="o"), s=st(32, 8, 24), r=st(32, 8, 24, ch="o"), h=rep("x.ogx.ogx.ogx.og"),
    b=bass((0, "0", 11), (11, "0", 5), (16, "5", 16)), glide=True)
pat(R, "RNB 2 SLOW JAM", 128, k=st(32, 0, 7, 16, 26, ch="o"), c=st(32, 8, 24), r=st(32, 8, 24, ch="g"), h=rep("x.x.x.x.x.x.x.x."), o=st(32, 30, ch="o"),
    b=bass((0, "0", 7), (7, "3", 9), (16, "5", 10), (26, "3", 6)), glide=True)
pat(R, "RNB 3 BOUNCE", 150, k=st(32, 0, 3, 10, 16, 19, 26), c=HALF, s=st(32, 8, 24, ch="o"), h=rep("x.x.x.x.x.x.x.x."), p1=st(32, 6, 22, ch="o"),
    b=bass((0, "0", 3), (3, "0", 7), (10, "5", 6), (16, "0", 3), (19, "0", 7), (26, "3", 6)))
pat(R, "RNB 4 TRAP SOUL", 140, k=st(32, 0, 10, 16, 26, ch="x"), s=HALF, c=st(32, 8, 24, ch="o"), h=put(rep("x.x.x.x.x.x.x.x."), (14, "t"), (30, "r")),
    b=bass((0, "0", 10), (10, "0", 6), (16, "3", 10), (26, "5", 6)), glide=True)
pat(R, "RNB 5 SNAPS", 132, k=st(32, 0, 11, 16, 26, ch="o"), r=st(32, 8, 24, ch="X"), s=st(32, 24, ch="o"), h=rep("x.oxx.oxx.oxx.ox"),
    b=bass((0, "0", 11), (11, "3", 5), (16, "5", 10), (26, "3", 6)), glide=True)
pat(R, "RNB 6 FLOAT", 120, 56, k=st(32, 0, 6, 10, 16, 22, 26, ch="o"), c=st(32, 8, 24), h=rep("..x...x...x...x."), p1=rep("ogxgogxgogxgogxg"),
    b=bass((0, "0", 6), (6, "0", 4), (10, "7", 6), (16, "5", 6), (22, "5", 4), (26, "3", 6)))
pat(R, "RNB 7 RIM AND 808", 124, r=st(32, 8, 13, 24, 29, ch="x"), h=rep("x.x.x.x.x.x.x.x."), o=st(32, 14, ch="o"),
    b=bass((0, "0", 13), (13, "3", 3), (16, "5", 16)), glide=True)
pat(R, "RNB 8 LATE SNARE", 138, k=st(32, 0, 7, 16, 23, ch="o"), s=st(32, 8, 24, ch="X"), c=st(32, 8, 24, ch="o"), h=rep("xgxgxgxgxgxgxgxg"),
    b=bass((0, "0", 7), (7, "0", 9), (16, "3", 7), (23, "5", 9)), glide=True)
pat(R, "RNB 9 PIANO BALLAD", 120, k=st(32, 0, 16, 26, ch="o"), s=st(32, 8, 24), h=rep("x...x...x...x..."), cr=st(32, 0),
    b=bass((0, "0", 16), (16, "5", 10), (26, "7", 6)))
pat(R, "RNB 10 KNOCK", 144, k=st(32, 0, 3, 11, 16, 19, 27), s=HALF, c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (22, "r"), (23, "r")), o=st(32, 6, ch="o"),
    b=bass((0, "0", 3), (3, "0", 8), (11, "3", 5), (16, "0", 3), (19, "0", 8), (27, "5", 5)), glide=True)

# ---------------- 90s RnB (new jack swing at 100-118 with heavy swing and a loud snare stacked on a clap;
# Timbaland's syncopated kicks and stuttering hats; Darkchild's stutters, cabasa and layered claps;
# Jermaine Dupri's 808 and clap bounce; Jam & Lewis machines; the Neptunes' bare knock) ----------------
R9 = "90s RnB"
pat(R9, "90S RNB 1 NEW JACK", 108, 66, k="X..x..x...x..x..X..x..x...x.....", s=BACK, c=BACK, h=two("x.x.x.x.x.x.x.x."))
pat(R9, "90S RNB 2 SWING BEAT", 112, 64, k="X.....x.x.x.....X.....x.x...x.x.", s=BACK, c=BACK, h=two("XgxgXgxgXgxgXgxg"), o=st(32, 14, 30, ch="o"))
pat(R9, "90S RNB 3 STUTTER", 96, 54, k="X..x...x.x..x...X..x....x.x..x..", s=BACK, h=two("x.xr..x.x.xr..x."), p1=st(32, 7, 15, 23, 31, ch="o"))
pat(R9, "90S RNB 4 808 BOUNCE", 94, 58, k="X.....x...x.....X.....x..x......", c=BACK, h=two("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 6), (6, "0", 4), (10, "5", 6), (16, "0", 6), (22, "0", 3), (25, "3", 7)))
pat(R9, "90S RNB 5 CABASA CLAPS", 100, 56, k="X......x..x.....X......x.x......", c=put(BACK, (13, "r"), (29, "r")), s=BACK, p1=rep("ogxgogxgogxgogxg"))
pat(R9, "90S RNB 6 QUIET STORM", 72, 60, k="X.......x..x....X......x........", r=BACK.replace("X", "x"), h=two("o.g.o.g.o.g.o.g."), o=st(32, 30, ch="g"))
pat(R9, "90S RNB 7 MACHINE FUNK", 104, 56, k="X..X..X...X..X..X..X..X...X.....", c=BACK, h=two("xgxgxgxgxgxgxgxg"), o=st(32, 6, 22, ch="o"))
pat(R9, "90S RNB 8 SAMPLE SOUL", 92, 58, k="X......x..x.....X.......x.x.....", s=BACK, h=two("x.x.x.x.x.x.x.x."), o=st(32, 14, 30, ch="o"), p1=two("....x.......x..."))
pat(R9, "90S RNB 9 VIRGINIA KNOCK", 100, 52, k="X.......X.x.....X.......X.......", s=BACK, p1=st(32, 2, 10, 18, 26, ch="o"), r=st(32, 7, 23, ch="g"))
pat(R9, "90S RNB 10 DUNGEON FAMILY", 90, 58, k="X.....x...x..x..X.....x...x.....", s=put(BACK, (7, "g"), (23, "g")), h=two("xgoxxgoxxgoxxgox"), o=st(32, 14, ch="o"), p2=st(32, 30, ch="o"))

# ================= Oct 24: the 17 genres Tyrone listed (Boom Bap and Drill were already here). Researched per
# genre in /mnt/project-files/research/realistic-drums-and-genres.md section 8; same lane codes as above. =================
def b4(*notes): return bass(*notes, n=64)
FILL0 = "." * 48                                  # three empty bars before a fill bar's toms

# ---------------- Trapsoul (120-150 written double time, felt 60-75: soft sparse kicks, clap or snap on beat 3
# sitting late, hats swung on their own with a roll at the end of a phrase, long 808 on the chord root that glides) ----------------
TS = "Trapsoul"
pat(TS, "TRAPSOUL 1 AFTER HOURS", 136, k=st(32, 0, 11, 16, 26, ch="o"), c=HALF, r=st(32, 8, 24, ch="g"), h=put(rep("x.x.x.x.x.x.x.x."), (14, "t"), (30, "r")),
    b=bass((0, "0", 11), (11, "0", 5), (16, "5", 10), (26, "3", 6)), glide=True)
pat(TS, "TRAPSOUL 2 SLOW MOTION", 124, k=st(32, 0, 7, 16, 23, ch="o"), c=HALF, h=rep("x...x...x.x.x..."), o=st(32, 14, ch="o"),
    b=bass((0, "0", 7), (7, "3", 9), (16, "7", 7), (23, "5", 9)), glide=True)
pat(TS, "TRAPSOUL 3 SNAP BACK", 140, k=st(32, 0, 10, 16, 19), r=st(32, 8, 24, ch="X"), c=st(32, 24, ch="o"), h=put(rep("x.oxx.oxx.oxx.ox"), (22, "t")),
    b=bass((0, "0", 10), (10, "3", 6), (16, "0", 3), (19, "5", 13)), glide=True)
pat(TS, "TRAPSOUL 4 PILLOW KICK", 130, k=st(32, 0, 3, 16, 27, ch="o"), s=HALF, c=st(32, 8, 24, ch="o"), h=rep("x.x.x.x.x.x.x.x."), p1=st(32, 6, 22, ch="g"),
    b=bass((0, "0", 3), (3, "0", 13), (16, "5", 11), (27, "3", 5)), glide=True)
pat(TS, "TRAPSOUL 5 HALF ASLEEP", 120, k=st(32, 0, 16, ch="o"), c=HALF, h=rep("x.......x.x....."), r=st(32, 13, 29, ch="g"),
    b=bass((0, "0", 16), (16, "3", 16)), glide=True)
pat(TS, "TRAPSOUL 6 FLUTTER HATS", 144, k=st(32, 0, 6, 10, 16, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (6, "r"), (7, "r"), (20, "t"), (28, "q"), (29, "q")),
    b=bass((0, "0", 6), (6, "0", 4), (10, "7", 6), (16, "5", 10), (26, "3", 6)), glide=True)
pat(TS, "TRAPSOUL 7 LATE NIGHT TEXT", 128, k=st(32, 0, 11, 16, 22, ch="o"), c=HALF, s=st(32, 15, 31, ch="g"), h=rep("x.ogx.ogx.ogx.og"), o=st(32, 30, ch="o"),
    b=bass((0, "0", 11), (11, "3", 5), (16, "5", 6), (22, "3", 10)), glide=True)
pat(TS, "TRAPSOUL 8 RAIN ON GLASS", 132, k=st(32, 0, 10, 16, 26, ch="o"), r=st(32, 8, 24), c=st(32, 8, 24, ch="g"), h=rep("x.x...x.x.x...x."), p2=st(32, 4, 20, ch="g"),
    b=bass((0, "0", 10), (10, "0", 6), (16, "B", 10), (26, "0", 6)), glide=True)
pat(TS, "TRAPSOUL 9 DOUBLE CLAP", 138, k=st(32, 0, 7, 16, 23), c=put(HALF, (9, "o"), (25, "o")), h=put(rep("x.x.x.x.x.x.x.x."), (14, "t"), (30, "t")),
    b=bass((0, "0", 7), (7, "0", 9), (16, "3", 7), (23, "5", 9)), glide=True)
pat(TS, "TRAPSOUL 10 SLOW BURN", 126, k=phrase("o..........o....", "o......o...o...."), c=phrase("........X......."), h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x.q.q."),
    cr=CRASH4, b=b4((0, "0", 11), (11, "0", 5), (16, "5", 16), (32, "0", 11), (43, "0", 5), (48, "7", 16)), glide=True)

# ---------------- Dark Trap (130-160: the trap skeleton stripped back, kicks and 808 on the minor second and the
# flat fifth, hats thinned out with open hats left hanging, bars that drop out to nothing) ----------------
DK = "Dark Trap"
pat(DK, "DARK TRAP 1 NIGHTMARE", 140, k=st(32, 0, 10, 16, 26), c=HALF, h=rep("x...x...x...x.x."), o=st(32, 14, 30, ch="o"),
    b=bass((0, "0", 10), (10, "1", 6), (16, "0", 10), (26, "6", 6)))
pat(DK, "DARK TRAP 2 HAUNTED HOUSE", 150, k=st(32, 0, 3, 16, 19, 30), c=HALF, s=st(32, 31, ch="o"), h=put(rep("x.x.x.x.x.x.x.x."), (28, "t")),
    b=bass((0, "0", 3), (3, "0", 13), (16, "1", 3), (19, "1", 11), (30, "0", 2)), glide=True)
pat(DK, "DARK TRAP 3 CANDLE LIT", 136, k=st(32, 0, 16, 22), c=HALF, h=rep("x.....x...x....."), p1=st(32, 6, 22, ch="g"),
    b=bass((0, "0", 16), (16, "A", 6), (22, "B", 10)), glide=True)
pat(DK, "DARK TRAP 4 FOG MACHINE", 145, k=st(32, 0, 7, 10, 16, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (6, "r"), (22, "q"), (23, "q")), o=st(32, 30),
    b=bass((0, "0", 7), (7, "0", 3), (10, "1", 6), (16, "0", 10), (26, "7", 6)))
pat(DK, "DARK TRAP 5 MIDNIGHT MASS", 132, k=phrase("X.........x.....", "X......x..x....."), c=phrase("........X......."), h=phrase("x...x...x...x...", fill="x...x...x.x.rrqq"),
    cr=CRASH4, b=b4((0, "0", 10), (10, "1", 6), (16, "0", 7), (23, "0", 3), (26, "6", 6), (32, "0", 10), (42, "1", 6), (48, "0", 16)))
pat(DK, "DARK TRAP 6 STATIC", 155, k=st(32, 0, 11, 16, 27), c=HALF, s=st(32, 8, 24, ch="o"), h=rep("xxx.x.xxx.x.x.x."),
    b=bass((0, "0", 11), (11, "6", 5), (16, "0", 11), (27, "5", 5)))
pat(DK, "DARK TRAP 7 GRAVEYARD SHIFT", 140, k=st(32, 0, 6, 16, 22, 28), c=HALF, r=st(32, 3, 19, ch="g"), h=put(rep("x...x...x...x..."), (10, "t"), (26, "t")),
    b=bass((0, "0", 6), (6, "0", 10), (16, "1", 6), (22, "0", 6), (28, "A", 4)), glide=True)
pat(DK, "DARK TRAP 8 BLACKOUT", 148, k=st(32, 0, 10, 16, 26), c=HALF, h=bars("x.x.x.x.x.x.x.x.", "." * 16), cr=st(32, 16),
    b=bass((0, "0", 10), (10, "0", 6), (16, "1", 16)))
pat(DK, "DARK TRAP 9 SLOW CREEP", 130, k=st(32, 0, 14, 16, 30), c=HALF, h=rep("x.......x......."), o=st(32, 12, 28, ch="o"), p2=st(32, 4, 20, ch="g"),
    b=bass((0, "0", 14), (14, "0", 2), (16, "1", 14), (30, "0", 2)))
pat(DK, "DARK TRAP 10 RED EYES", 160, k=st(32, 0, 7, 10, 16, 23, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (14, "t"), (28, "q"), (29, "q"), (30, "q"), (31, "q")),
    b=bass((0, "0", 7), (7, "0", 3), (10, "6", 6), (16, "0", 7), (23, "0", 3), (26, "1", 6)), glide=True)

# ---------------- Phonk (drift phonk at 120-150 with the clap on 2 and 4 and a percussion line on the offbeats;
# the older tape-house kind half time with triplet hats; Brazilian funk's tamborzao kick) ----------------
PH = "Phonk"
pat(PH, "PHONK 1 DRIFT", 130, k=st(32, 0, 6, 10, 16, 22, 26), c=BACK, h=rep("x.x.x.x.x.x.x.x."), p1=rep("..x...x...x...x."),
    b=bass((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 6), (22, "0", 4), (26, "5", 6)))
pat(PH, "PHONK 2 HOUSE OF SMOKE", 138, 56, k=st(32, 0, 3, 10, 16, 19, 26), c=HALF, h=rep("xgxgxgxgxgxgxgxg"), p1=st(32, 0, 3, 6, 10, 16, 19, 22, 26, ch="o"),
    b=bass((0, "0", 3), (3, "0", 7), (10, "1", 6), (16, "0", 3), (19, "0", 7), (26, "A", 6)))
pat(PH, "PHONK 3 TAPE CHOP", 136, k=st(32, 0, 7, 10, 16, 23), s=HALF, c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (14, "t"), (30, "t")), o=st(32, 6, 22, ch="o"),
    b=bass((0, "0", 7), (7, "0", 3), (10, "3", 6), (16, "0", 7), (23, "5", 9)))
pat(PH, "PHONK 4 BRAZIL FUNK", 130, k=rep("X..x..x...x....."), c=rep("....x.......x..x"), p1=rep("..x..x....x..x.."),
    b=bass((0, "0", 3), (3, "0", 3), (6, "0", 4), (10, "3", 6), (16, "0", 3), (19, "0", 3), (22, "0", 4), (26, "5", 6)))
pat(PH, "PHONK 5 SLOWED NIGHT", 120, 58, k=st(32, 0, 10, 16, 26), c=HALF, h=rep("x.x.x.x.x.x.x.x."), o=st(32, 14, 30, ch="o"), p1=rep("x..x..x...x..x.."),
    b=bass((0, "0", 10), (10, "0", 6), (16, "B", 16)), glide=True)
pat(PH, "PHONK 6 ROLL OUT", 140, k=st(32, 0, 7, 16, 23, 26), c=BACK, h=put(rep("x.xxx.x.x.xxx.x."), (30, "q")),
    b=bass((0, "0", 7), (7, "0", 9), (16, "0", 7), (23, "3", 3), (26, "5", 6)))
pat(PH, "PHONK 7 DOUBLE TIME", 145, k=st(32, 0, 6, 8, 16, 22, 24), c=BACK, h=rep("XxoxXxoxXxoxXxox"),
    b=bass((0, "0", 6), (6, "0", 2), (8, "3", 8), (16, "0", 6), (22, "0", 2), (24, "5", 8)))
pat(PH, "PHONK 8 CHOPPED VOX", 132, 54, k=st(32, 0, 3, 10, 16, 26), c=HALF, r=st(32, 4, 12, 20, 28, ch="o"), h=rep("x...x...x...x..."), p2=st(32, 14, 30, ch="o"),
    b=bass((0, "0", 3), (3, "0", 7), (10, "1", 6), (16, "0", 10), (26, "0", 6)))
pat(PH, "PHONK 9 BASS SLIDE", 128, k=st(32, 0, 10, 16, 26), c=BACK, h=rep("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 10), (10, "7", 6), (16, "5", 10), (26, "c", 6)), glide=True)
pat(PH, "PHONK 10 STREET RACE", 150, k=phrase("X.....x...x.....", "X.....x...x..x.."), c=phrase("....X.......X..."), h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x.q.q."),
    p1=phrase("..o...o...o...o."), cr=CRASH4, b=b4((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 6), (22, "0", 4), (26, "3", 3), (29, "5", 3),
                                                (32, "0", 6), (38, "0", 4), (42, "3", 6), (48, "0", 6), (54, "0", 4), (58, "7", 6)))

# ---------------- ATL Trap (Atlanta 2005 to now, 130-150 written double time: the snap and crunk roots at 76-80,
# then trap's syncopated kicks that the 808 follows, clap on 3, hat rolls and triplet hats for triplet flows) ----------------
AL = "ATL Trap"
pat(AL, "ATL TRAP 1 TRAP HOUSE", 140, k=st(32, 0, 3, 10, 16, 19, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (14, "r"), (15, "r")),
    b=bass((0, "0", 3), (3, "0", 7), (10, "3", 6), (16, "0", 3), (19, "0", 7), (26, "5", 6)))
pat(AL, "ATL TRAP 2 SNAP CITY", 76, k=st(32, 0, 3, 6, 16, 22), r=st(32, 4, 12, 20, 28, ch="X"), h=rep("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 3), (3, "0", 3), (6, "3", 10), (16, "0", 6), (22, "5", 10)))
pat(AL, "ATL TRAP 3 CRUNK STOMP", 80, k=rep("X..x..x.X......."), s=BACK, c=BACK, h=rep("x.x.x.x.x.x.x.x."), cr=st(32, 0),
    b=bass((0, "0", 3), (3, "0", 3), (6, "0", 2), (8, "3", 8), (16, "0", 3), (19, "0", 3), (22, "0", 2), (24, "5", 8)))
pat(AL, "ATL TRAP 4 TRIPLET FLOW", 150, k=st(32, 0, 7, 10, 16, 26, 29), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (2, "t"), (6, "t"), (18, "t"), (22, "t"), (28, "q")),
    b=bass((0, "0", 7), (7, "0", 3), (10, "5", 6), (16, "0", 10), (26, "3", 3), (29, "0", 3)))
pat(AL, "ATL TRAP 5 ZONE SIX", 145, k=st(32, 0, 6, 10, 16, 22, 26, 30), c=HALF, s=st(32, 15, 31, ch="o"), h=rep("x.x.x.xxx.x.x.xx"), o=st(32, 12),
    b=bass((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 6), (22, "0", 4), (26, "7", 4), (30, "5", 2)))
pat(AL, "ATL TRAP 6 PIANO KEYS", 138, k=st(32, 0, 3, 6, 16, 19, 22), c=HALF, h=rep("xoxoxoxoxoxoxoxo"),
    b=bass((0, "0", 3), (3, "0", 3), (6, "7", 10), (16, "0", 3), (19, "0", 3), (22, "5", 10)))
pat(AL, "ATL TRAP 7 STADIUM CLAP", 142, k=st(32, 0, 10, 16, 23, 26), s=HALF, c=put(HALF, (7, "o")), h=put(rep("x.x.x.x.x.x.x.x."), (22, "r"), (23, "r")), cr=st(32, 0),
    b=bass((0, "0", 10), (10, "0", 6), (16, "3", 7), (23, "0", 3), (26, "5", 6)))
pat(AL, "ATL TRAP 8 SNARE ROLL", 140, k=st(32, 0, 10, 16, 26), c=HALF, s=put(st(32, 8, 24, ch="X"), (28, "r"), (29, "r"), (30, "q"), (31, "q")), h=rep("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 10), (10, "0", 6), (16, "5", 10), (26, "3", 6)))
pat(AL, "ATL TRAP 9 BANDO", 135, k=st(32, 0, 11, 16, 27), c=HALF, h=put(rep("x...x...x...x..."), (10, "t"), (26, "t")), p1=st(32, 4, 20, ch="o"),
    b=bass((0, "0", 11), (11, "0", 5), (16, "7", 11), (27, "5", 5)))
pat(AL, "ATL TRAP 10 PEACHTREE", 148, k=phrase("X......x..x.....", "X..x...x..x....."), c=phrase("........X......."),
    h=phrase("x.x.x.x.x.x.x.x.", "x.x.x.x.x.x.t.x.", fill="x.x.x.x.rrrrqqqq"), cr=CRASH4,
    b=b4((0, "0", 7), (7, "0", 3), (10, "3", 6), (16, "0", 3), (19, "0", 4), (23, "0", 3), (26, "5", 6),
         (32, "0", 7), (39, "0", 3), (42, "3", 6), (48, "0", 3), (51, "0", 4), (55, "7", 9)))

# ---------------- Memphis (90s tape rap, 66-80 or written double time at 136-150: hard kicks with a long 808 under
# them, a bell or percussion line in a 3-3-2 shape, triplet hats, the clap or snare loud on the backbeat) ----------------
MM = "Memphis"
pat(MM, "MEMPHIS 1 TAPE HOUSE", 72, k="X.....x.x.......X.......x.x.....", s=BACK, c=BACK, h=put(two("x.x.x.x.x.x.x.x."), (6, "t"), (22, "t")), p1=two("x..x..x...x..x.."),
    b=bass((0, "0", 6), (6, "0", 2), (8, "0", 8), (16, "0", 8), (24, "0", 2), (26, "3", 6)))
pat(MM, "MEMPHIS 2 TRIPLET BELL", 140, k=st(32, 0, 10, 16, 26), c=HALF, h=rep("x.x.x.x.x.x.x.x."), p1=put(st(32, 0, 16, ch="o"), (4, "t"), (12, "t"), (20, "t"), (28, "t")),
    b=bass((0, "0", 10), (10, "0", 6), (16, "1", 10), (26, "0", 6)))
pat(MM, "MEMPHIS 3 BASEMENT TAPE", 76, k="X..x....x.x.....X..x......x.....", s=BACK, h=two("xgxgxgxgxgxgxgxg"), o=st(32, 14, 30, ch="o"),
    b=bass((0, "0", 3), (3, "0", 5), (8, "0", 2), (10, "3", 6), (16, "0", 3), (19, "0", 7), (26, "A", 6)))
pat(MM, "MEMPHIS 4 NORTH SIDE", 150, k=st(32, 0, 6, 16, 22, 26), c=HALF, s=st(32, 8, 24, ch="o"), h=put(rep("x.x.x.x.x.x.x.x."), (2, "t"), (18, "t"), (26, "t")),
    b=bass((0, "0", 6), (6, "0", 10), (16, "0", 6), (22, "0", 4), (26, "1", 6)))
pat(MM, "MEMPHIS 5 GANGSTA WALK", 140, k=rep("X...X...X...X..."), c=HALF, h=rep("x.x.x.x.x.x.x.x."), p1=rep("..x...x...x...x."),
    b=bass((0, "0", 4), (4, "0", 4), (8, "0", 4), (12, "3", 4), (16, "0", 4), (20, "0", 4), (24, "1", 4), (28, "0", 4)))
pat(MM, "MEMPHIS 6 SMOKED OUT", 68, k="X.......x.x.....X.......x.......", s=BACK, h=put(two("x.x.x.x.x.x.x.x."), (10, "t"), (26, "t")), p1=st(32, 3, 19, ch="o"),
    b=bass((0, "0", 8), (8, "0", 2), (10, "3", 6), (16, "0", 8), (24, "5", 8)))
pat(MM, "MEMPHIS 7 HALF MOON", 145, k=st(32, 0, 3, 16, 19, 28), c=HALF, h=put(rep("x...x...x...x..."), (6, "t"), (14, "t"), (22, "t"), (30, "t")), p2=st(32, 12, 28, ch="o"),
    b=bass((0, "0", 3), (3, "0", 13), (16, "0", 3), (19, "1", 9), (28, "0", 4)))
pat(MM, "MEMPHIS 8 RAW CHOP", 74, 56, k="X.x.......x..x..X.x.......x.....", s=put(BACK, (15, "g"), (31, "g")), h=two("x.x.x.x.x.x.x.x."), p1=two("x..x..x........."))
pat(MM, "MEMPHIS 9 DOUBLE KICK", 136, k=st(32, 0, 1, 10, 16, 17, 26), c=HALF, h=rep("x.x.x.x.x.x.x.x."), p1=rep("x..x..x.x..x..x."),
    b=bass((0, "0", 10), (10, "0", 6), (16, "1", 10), (26, "0", 6)))
pat(MM, "MEMPHIS 10 CASSETTE FILL", 70, k=phrase("X.....x.x.......", "X.....x...x....."), s=phrase("....X.......X...", fill="....X.......XgXX"),
    h=phrase("x.x.x.x.x.x.x.x.", "x.x.x.t.x.x.x.t.", fill="x.x.x.x.x.x....."), p1=phrase("x..x..x...x..x.."), cr=CRASH4,
    b=b4((0, "0", 6), (6, "0", 2), (8, "0", 8), (16, "0", 6), (22, "3", 10), (32, "0", 6), (38, "0", 2), (40, "0", 8), (48, "0", 6), (54, "5", 10)))

# ---------------- Toronto R&B (dark, muffled, 120-145 written double time and felt half: the kick barely there,
# snare or rim on 3 pulled late, hats sparse with a 32nd burst, the 808 held for whole bars) ----------------
TO = "Toronto R&B"
pat(TO, "TORONTO R&B 1 UNDERWATER", 130, k=st(32, 0, 11, 16, ch="o"), s=HALF, h=rep("x.......x.x....."), b=bass((0, "0", 16), (16, "5", 16)), glide=True)
pat(TO, "TORONTO R&B 2 SIX AM", 136, k=st(32, 0, 7, 16, 26, ch="o"), r=st(32, 8, 24), s=st(32, 8, 24, ch="g"), h=put(rep("x...x...x...x..."), (14, "r"), (30, "r")),
    b=bass((0, "0", 7), (7, "3", 9), (16, "5", 10), (26, "3", 6)), glide=True)
pat(TO, "TORONTO R&B 3 COLD CITY", 140, k=st(32, 0, 10, 16, 26, ch="o"), c=HALF, h=rep("x.x...x.x.x...x."), p1=st(32, 4, 20, ch="g"),
    b=bass((0, "0", 10), (10, "0", 6), (16, "A", 10), (26, "B", 6)), glide=True)
pat(TO, "TORONTO R&B 4 SLOW FADE", 120, k=st(32, 0, 16, 23, ch="o"), s=HALF, h=rep("o.o.o.o.o.o.o.o."), o=st(32, 30, ch="o"),
    b=bass((0, "0", 16), (16, "3", 7), (23, "5", 9)), glide=True)
pat(TO, "TORONTO R&B 5 LAKESHORE", 132, k=st(32, 0, 3, 16, 19, ch="o"), r=st(32, 8, 24, ch="X"), h=put(rep("x.ogx.ogx.ogx.og"), (22, "t")),
    b=bass((0, "0", 3), (3, "0", 13), (16, "5", 3), (19, "5", 13)), glide=True)
pat(TO, "TORONTO R&B 6 MUFFLED", 128, k=st(32, 0, 11, 16, 27, ch="o"), s=st(32, 8, 24, ch="o"), c=st(32, 8, 24, ch="g"), h=rep("g.o.g.o.g.o.g.o."),
    b=bass((0, "0", 11), (11, "0", 5), (16, "3", 11), (27, "0", 5)), glide=True)
pat(TO, "TORONTO R&B 7 FLOAT HATS", 144, k=st(32, 0, 10, 16, 26), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (6, "q"), (22, "r"), (28, "t")),
    b=bass((0, "0", 10), (10, "0", 6), (16, "7", 10), (26, "5", 6)), glide=True)
pat(TO, "TORONTO R&B 8 NO SNARE", 124, k=st(32, 0, 10, 16, 26, ch="o"), r=st(32, 8, 24, ch="o"), h=rep("x...x...x...x..."), p2=st(32, 14, 30, ch="g"),
    b=bass((0, "0", 10), (10, "3", 6), (16, "5", 10), (26, "3", 6)), glide=True)
pat(TO, "TORONTO R&B 9 WINTER", 136, k=phrase("o..........o....", "o......o........"), s=phrase("........X.......", fill="........X.....gg"),
    h=phrase("x...x...x...x...", fill="x...x...x.x.rrrr"), cr=CRASH4, b=b4((0, "0", 16), (16, "5", 16), (32, "0", 16), (48, "3", 16)), glide=True)
pat(TO, "TORONTO R&B 10 PENTHOUSE", 140, k=st(32, 0, 7, 10, 16, 26), c=HALF, s=HALF, h=rep("xgxgxgxgxgxgxgxg"), o=st(32, 14, ch="o"),
    b=bass((0, "0", 7), (7, "0", 3), (10, "3", 6), (16, "5", 10), (26, "3", 6)), glide=True)

# ---------------- Vintage R&B (60s and 70s soul and R&B, one drummer: the Detroit four-snare beat with tambourine,
# Southern soul's laid-back backbeat, Philly's open hats on the offbeat, slow dances in a swung 12/8, fills into a crash) ----------------
VR = "Vintage R&B"
pat(VR, "VINTAGE R&B 1 MOTOR CITY", 120, k=phrase("X......xX.......", "X......xX.x....."), s=phrase("X...X...X...X...", fill="X...X...X.X.XXXX"),
    h=phrase("..x...x...x...x.", fill="..x...x........."), p1=phrase("....x.......x..."))
pat(VR, "VINTAGE R&B 2 SOUTHERN SOUL", 104, 56, k=phrase("X.......x.x.....", "X......x..x....."), s=phrase("....X.......X...", fill="....X.......X.XX"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x.x..."), cr=CRASH4)
pat(VR, "VINTAGE R&B 3 PHILLY STRINGS", 112, k=phrase("X...X...X...X..."), s=phrase("....X.......X..."), h=phrase("x...x...x...x..."), o=phrase("..o...o...o...o."),
    p1=phrase("xgxgxgxgxgxgxgxg"))
pat(VR, "VINTAGE R&B 4 SLOW DANCE", 70, 62, k=two("X.......x.x....."), s=two("....X.......X..."), h=put(two("x.x.x.x.x.x.x.x."), (30, ".")), o=st(32, 30, ch="o"))
pat(VR, "VINTAGE R&B 5 SOUL CLAP", 96, k=two("X..x....x.x....."), s=BACK, c=BACK, h=two("x.x.x.x.x.x.x.x."))
pat(VR, "VINTAGE R&B 6 GHOST STROKES", 100, 58, k=phrase("X......x..x.....", "X......x..x..x.."), s=phrase("....X..g.g..X..g", fill="....X..g.g..XgXX"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x....."), cr=CRASH4)
pat(VR, "VINTAGE R&B 7 TAMBOURINE", 116, k=phrase("X.....x.X......."), s=phrase("....X.......X..."), h=phrase("x.x.x.x.x.x.x.x."), p1=phrase("x.x.x.x.x.x.x.x."))
pat(VR, "VINTAGE R&B 8 SIDE STICK", 84, 60, k=phrase("X.......x.x.....", "X......x........"), r=phrase("....x.......x..."), h=phrase("x.ox.ox.x.ox.ox."))
pat(VR, "VINTAGE R&B 9 SHUFFLE", 108, 66, k=two("X.....x.X.....x."), s=two("....X..g....X..g"), h=two("x.ox.ox.x.ox.ox."))
pat(VR, "VINTAGE R&B 10 BRIDGE FILL", 98, k=phrase("X.......x.x....."), s=phrase("....X.......X...", fill="....X...gogoXXXX"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x........."), ht=bars(FILL0, "........X.X....."), lt=bars(FILL0, "...........X...."), cr=CRASH4)

# ---------------- 2000s R&B (70-105: syncopated stutter kicks, a clap stacked on the snare, finger snaps, rim
# stutters on the off-16ths, club remixes with an 808, ringtone-era skip hats) ----------------
R2 = "2000s R&B"
pat(R2, "2000S R&B 1 CLUB REMIX", 100, k="X..x..x...x.....X..x..x...x..x..", c=BACK, s=BACK, h=two("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 3), (3, "0", 3), (6, "0", 4), (10, "3", 6), (16, "0", 3), (19, "0", 3), (22, "0", 4), (26, "5", 3), (29, "3", 3)))
pat(R2, "2000S R&B 2 STUTTER KICK", 92, k="X.xX......x..x..X.xX.....x.x....", s=BACK, h=two("xgxgxgxgxgxgxgxg"), r=st(32, 7, 23, ch="o"))
pat(R2, "2000S R&B 3 CRUNK BOUNCE", 84, k=two("X......xX.x....."), c=BACK, h=two("x.x.x.x.x.x.x.x."), p1=two("..x...x...x...x."),
    b=bass((0, "0", 7), (7, "0", 1), (8, "0", 2), (10, "3", 6), (16, "0", 7), (23, "0", 1), (24, "0", 2), (26, "5", 6)))
pat(R2, "2000S R&B 4 FINGER SNAPS", 76, k=two("X......x..x....."), r=st(32, 4, 12, 20, 28, ch="X"), h=two("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 7), (7, "0", 3), (10, "3", 6), (16, "0", 7), (23, "0", 3), (26, "5", 6)))
pat(R2, "2000S R&B 5 SLOW GRIND", 70, 58, k=two("X.......x..x...."), s=BACK, h=put(two("x.oxx.oxx.oxx.ox"), (30, ".")), o=st(32, 30, ch="o"),
    b=bass((0, "0", 8), (8, "0", 3), (11, "3", 5), (16, "0", 8), (24, "0", 3), (27, "5", 5)))
pat(R2, "2000S R&B 6 RIM STUTTER", 96, k=two("X.....x...x....."), s=BACK, r=two("..x..x....x..x.."), h=two("x.x.x.x.x.x.x.x."))
pat(R2, "2000S R&B 7 RINGTONE", 88, k=two("X..x....x.....x."), c=BACK, h=two("xxx.x.x.xxx.x.x."), p2=st(32, 14, 30, ch="o"),
    b=bass((0, "0", 3), (3, "0", 5), (8, "3", 6), (14, "0", 2), (16, "0", 3), (19, "0", 5), (24, "5", 6), (30, "0", 2)))
pat(R2, "2000S R&B 8 DANCE FLOOR", 104, k=rep("X...X...X...X..."), c=BACK, h=two("..x...x...x...x."), p1=rep("xgxgxgxgxgxgxgxg"))
pat(R2, "2000S R&B 9 BALLAD", 66, k=two("X.......x.x....."), s=BACK, h=two("x.x.x.x.x.x.x.x."), cr=st(32, 0))
pat(R2, "2000S R&B 10 SYNCOPATED", 98, k=phrase("X..x...x..x.....", "X..x...x..x..x.."), s=phrase("....X.......X..."), c=phrase("....X.......X..."),
    h=phrase("x.xrx.x.x.xrx.x.", fill="x.x.x.x.x.xrqqqq"), cr=CRASH4)

# ---------------- Live Soul (one drummer, 70-110: the pocket with ghost strokes around the backbeat, ride grooves,
# tom grooves, open-hat lifts, triplet shuffles, half-time sections, fills that land on the crash) ----------------
LS = "Live Soul"
pat(LS, "LIVE SOUL 1 POCKET", 92, 58, k=phrase("X......x..x.....", "X.....x...x..x.."), s=phrase("....X..g.g..X..g", fill="....X..g.g..XgXX"),
    h=phrase("x.x.x.x.x.x.x...", fill="x.x.x.x.x.x....."), o=phrase("..............o.", fill="." * 16), cr=CRASH4)
pat(LS, "LIVE SOUL 2 SUNDAY BEST", 84, k=phrase("X.......x.x.....", "X......x..x....."), s=phrase("....X.......X...", fill="....X...X.X.XXXX"),
    h=phrase("x.ox.ox.x.ox.ox.", fill="x.ox.ox........."), cr=CRASH4)
pat(LS, "LIVE SOUL 3 RIDE GROOVE", 100, k=phrase("X.....x...x....."), s=phrase("....X..g....X...", fill="....X..g....XgXX"), cr=phrase("x.x.x.x.x.x.x.x."),
    h=phrase("....x.......x..."))
pat(LS, "LIVE SOUL 4 SLOW SIMMER", 72, 62, k=phrase("X.......x..x....", "X......x..x....."), r=phrase("....x.......x...", fill="....x..........."),
    s=phrase("..g......g....g.", fill="..g......g..ggoX"), h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x....."), cr=CRASH4)
pat(LS, "LIVE SOUL 5 FUNKY FOUR", 104, 54, k=phrase("X.x....x..x..x..", "X.x....x.x......"), s=phrase("....X..g.g.gX..g"), h=phrase("x.xxx.x.x.xxx.x."))
pat(LS, "LIVE SOUL 6 TOM GROOVE", 96, k=phrase("X......x..x....."), s=phrase("....X.......X..."), ht=phrase("......x........."), lt=phrase("..........x....x"),
    h=phrase("x.x.x.x.x.x.x.x."))
pat(LS, "LIVE SOUL 7 HALF TIME", 80, k=phrase("X..x......x....."), s=phrase("........X.......", fill="........X...gXgX"), r=phrase("...g.......g....", fill="...g............"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x....."))
pat(LS, "LIVE SOUL 8 OPEN HAT LIFT", 108, k=phrase("X.....x.X......."), s=phrase("....X.......X..."), h=phrase("x.x...x.x.x...x."), o=phrase("....o.......o..."))
pat(LS, "LIVE SOUL 9 TRIPLET SHUFFLE", 90, 66, k=phrase("X.....xx......x."), s=phrase("....X..g....X..g", fill="....X..g....XXXX"), h=phrase("x.ox.ox.x.ox.ox.", fill="x.ox.ox.x.ox...."))
pat(LS, "LIVE SOUL 10 BIG FINISH", 100, k=phrase("X......x..x....."), s=phrase("....X.......X...", fill="....X..gX.XXX.X."), h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x........."),
    ht=bars(FILL0, "...........X.X.."), lt=bars(FILL0, "...............X"), cr=CRASH4)

# ---------------- East Coast (New York and up the coast, 84-100 with MPC swing: Queens grime, Bronx break kicks,
# Harlem's soul-sample bounce with a stacked clap, Buffalo's near-drumless rim grooves, Brooklyn stomps) ----------------
EC = "East Coast"
pat(EC, "EAST COAST 1 QUEENS GRIME", 92, 60, k="X......x..x.....X......x.x......", s=BACK, h=two("x.x.x.x.x.x.x.x."), r=st(32, 14, ch="g"))
pat(EC, "EAST COAST 2 BRONX BREAK", 98, 56, k="X.x.......x..x..X.x.....x.......", s=put(BACK, (7, "g"), (23, "g")), h=put(two("x.xxx.x.x.xxx.x."), (30, ".")), o=st(32, 30, ch="o"))
pat(EC, "EAST COAST 3 HARLEM SOUL", 88, 54, k="X.....x...x.....X.....x...x..x..", s=BACK, c=BACK, h=two("x.x.x.x.x.x.x.x."))
pat(EC, "EAST COAST 4 BUFFALO GRIT", 86, 52, k="X.........x.....X.........x.....", r=st(32, 4, 12, 20, 28), h=two("x...x...x...x..."))
pat(EC, "EAST COAST 5 BROOKLYN STOMP", 95, 58, k="X..x..x...x.....X..x..x.....x...", s=BACK, h=put(two("xgxgxgxgxgxgxgxg"), (14, ".")), o=st(32, 14, ch="o"))
pat(EC, "EAST COAST 6 SUBWAY", 90, 62, k="X.......x.x.....X......x..x.....", s=put(BACK, (15, "g"), (31, "g")), h=two("x.ogx.ogx.ogx.og"), p1=two("....x.......x..."))
pat(EC, "EAST COAST 7 MIXTAPE", 94, 56, k="X......x..x..x..X......x..x.....", s=BACK, h=two("x.x.x.x.x.x.x.x."), cr=st(32, 0), p2=st(32, 14, 30, ch="o"))
pat(EC, "EAST COAST 8 BLOCK PARTY", 100, k="X.x...x...x.....X.x...x...x.x...", s=BACK, c=BACK, h=put(two("x.x.x.x.x.x.x.x."), (6, "."), (22, ".")), o=st(32, 6, 22, ch="o"))
pat(EC, "EAST COAST 9 PROJECT HALLS", 84, 60, k="X.........x..x..X.......x.......", s=two("....X..g....X.g."), h=two("x...x...x...x..."), r=st(32, 10, 26, ch="g"))
pat(EC, "EAST COAST 10 CYPHER", 93, 58, k=phrase("X......x..x.....", "X.x....x..x..x.."), s=phrase("....X.......X...", fill="....X.......X.XX"),
    h=phrase("x.x.x.x.x.x.x...", fill="x.x.x.x.x.x.x..."), o=phrase("..............o.", fill="." * 16), cr=CRASH4)

# ---------------- Lo-fi (70-90, swing 56-66: soft dynamics, a lazy snare or rim pulled late, swung hats with
# ghosts that come and go, kicks a little off the beat, nothing hit at full force except the downbeat) ----------------
LF = "Lo-fi"
pat(LF, "LO-FI 1 RAINY WINDOW", 80, 62, k="X......x..x.....X......x........", s=st(32, 4, 12, 20, 28), h=two("x.ogx.ogx.ogx.og"))
pat(LF, "LO-FI 2 STUDY SESSION", 85, 60, k="X.......x.x.....X.......x.......", r=st(32, 4, 12, 20, 28), h=two("o.o.o.o.o.o.o.o."), s=st(32, 15, 31, ch="g"))
pat(LF, "LO-FI 3 COFFEE SHOP", 76, 64, k="X.....x...x.....X.....x.........", s=two("....x..g....x..."), h=put(two("x.o.x.o.x.o.x.o."), (30, ".")), o=st(32, 30, ch="g"))
pat(LF, "LO-FI 4 LATE BUS", 72, 62, k="X..x......x.....X..x.......x....", s=st(32, 4, 12, 20, 28, ch="o"), h=two("xgxgxgxgxgxgxgxg"), p1=two("..g...g...g...g."))
pat(LF, "LO-FI 5 DUSTY VINYL", 88, 58, k="X......x..x..x..X......x..x.....", s=st(32, 4, 12, 20, 28), h=two("x.x.x.x.x.x.x.x."), r=st(32, 7, 23, ch="g"))
pat(LF, "LO-FI 6 SLEEPY", 70, 66, k="X.......x.......X......x..x.....", r=st(32, 4, 12, 20, 28, ch="o"), h=two("o.g.o.g.o.g.o.g."))
pat(LF, "LO-FI 7 TAPE WOBBLE", 82, 60, k="X.....x.x.......X.....x...x.....", s=put(st(32, 4, 12, 20, 28), (10, "g"), (26, "g")), h=two("x.ox.ox.x.ox.ox."))
pat(LF, "LO-FI 8 SUNSET WALK", 90, 56, k="X.......x..x....X......x..x.....", c=st(32, 4, 12, 20, 28, ch="o"), s=st(32, 4, 12, 20, 28, ch="g"), h=two("x.x.x.x.x.x.x.x."),
    p1=two("ogxgogxgogxgogxg"))
pat(LF, "LO-FI 9 BEDROOM", 78, 62, k="X.x.......x.....X.x.....x.......", s=st(32, 4, 12, 20, 28), h=two("x...x...x...x..x"), o=st(32, 14, ch="g"))
pat(LF, "LO-FI 10 NIGHT LIGHT", 74, 64, k=phrase("X......x..x.....", "X.........x....."), s=phrase("....x.......x...", fill="....x.......x.gg"),
    h=phrase("x.ogx.ogx.ogx.og", fill="x.ogx.ogx.og...."), cr=CRASH4)

# ---------------- Afrobeats (95-115: the 3-3-2 kick or a four-on-the-floor, a rim or snare on the off-16ths
# (the dancehall skeleton), a swung shaker carrying the 16ths, a clap on beat 4, talking drum and bell lines) ----------------
AF = "Afrobeats"
pat(AF, "AFROBEATS 1 LAGOS NIGHTS", 104, k=rep("X.....x.X.....x."), r=rep("...x..x....x..x."), c=st(32, 12, 28, ch="o"), p1=rep("xgogxgogxgogxgog"), h=rep("..x...x...x...x."))
pat(AF, "AFROBEATS 2 ACCRA SWAY", 100, 56, k=rep("X..x..x.X..x..x."), r=rep("....x.......x..."), p1=rep("ogxgogxgogxgogxg"), p2=rep("..o...o...o..o.."), h=rep("x.x.x.x.x.x.x.x."))
pat(AF, "AFROBEATS 3 FLOOR FILLER", 112, k=rep("X...X...X...X..."), r=rep("...x..x....x..x."), p1=rep("xgxgxgxgxgxgxgxg"), o=rep("..o...o...o...o."))
pat(AF, "AFROBEATS 4 SLOW WINE", 96, 58, k=rep("X.....x...x....."), r=rep("...x..x....x...."), c=st(32, 12, 28), p1=rep("ogxgogxgogxgogxg"),
    b=bass((0, "0", 6), (6, "0", 4), (10, "5", 6), (16, "0", 6), (22, "0", 4), (26, "3", 6)))
pat(AF, "AFROBEATS 5 STREET POP", 106, k=rep("X..x..x...x....."), s=st(32, 12, 28), r=rep("...x..x....x..x."), h=rep("x.xxx.xxx.xxx.xx"), p2=st(32, 7, 23, ch="o"))
pat(AF, "AFROBEATS 6 HIGHLIFE", 110, 54, k=rep("X.......X......."), r=rep("x..x..x...x.x..."), p2=rep("x.x.xx.x.x.xx.x."), p1=rep("xgxgxgxgxgxgxgxg"))
pat(AF, "AFROBEATS 7 AFROSWING", 102, 60, k=rep("X.....x...x....."), c=st(32, 12, 28), r=rep("...x..x........."), h=rep("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 6), (6, "0", 4), (10, "3", 6), (16, "0", 6), (22, "0", 4), (26, "5", 6)))
pat(AF, "AFROBEATS 8 TALKING PERC", 108, k=rep("X..x..x.X..x..x."), r=rep("....x.......x..."), p1=rep("xgogxgogxgogxgog"), p2=rep("..x..x...x..x..."),
    ht=st(32, 13, 29, ch="o"), lt=st(32, 14, 30, ch="o"))
pat(AF, "AFROBEATS 9 SUNDOWN", 98, k=rep("X.....x.X......."), r=rep("...x..x....x..x."), c=st(32, 12, 28, ch="o"), h=rep("..x...x...x...x."), p1=rep("ogxgogxgogxgogxg"), cr=st(32, 0))
pat(AF, "AFROBEATS 10 PARTY", 114, k=phrase("X.....x.X.....x."), r=phrase("...x..x....x..x.", fill="...x..x....xxxxx"), p1=phrase("xgogxgogxgogxgog"),
    c=phrase("............x..."), cr=CRASH4)

# ---------------- Bouncy (club bounce, 95-140: the New Orleans triggerman kick, Jersey club's five-kick figure,
# Baltimore club's breakbeat stomp, the Bay's slapping 808, clap-heavy party beats) ----------------
BO = "Bouncy"
pat(BO, "BOUNCY 1 TRIGGER BEAT", 100, k=rep("X..x..x.X..x..x."), c=rep("....X.......X..X"), h=rep("x.x.x.x.x.x.x.x."), p1=rep("..x...x...x...x."))
pat(BO, "BOUNCY 2 JERSEY CLUB", 140, k=rep("X..X..X...X.X..."), c=rep("....X.......X..."), o=rep("..o...o...o...o."))
pat(BO, "BOUNCY 3 BMORE CLUB", 130, k=rep("X...X...X...X.x."), c=rep("....X.......X..."), h=rep("x.x.x.x.x.x.x.x."), s=st(32, 14, 15, 30, 31, ch="o"))
pat(BO, "BOUNCY 4 SLAP BOUNCE", 100, k=rep("X.....x.X.x....."), c=BACK, h=rep("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 6), (6, "0", 2), (8, "0", 2), (10, "5", 6), (16, "0", 6), (22, "0", 2), (24, "0", 2), (26, "7", 6)))
pat(BO, "BOUNCY 5 SKIP STEP", 96, 58, k=rep("X..x....x..x...."), s=BACK, h=rep("xgxgxgxgxgxgxgxg"), p1=st(32, 6, 22, ch="o"))
pat(BO, "BOUNCY 6 PARTY STARTER", 104, k=rep("X...X...X...X..."), c=BACK, s=BACK, o=rep("..o...o...o...o."), p2=rep("x..x..x...x..x.."))
pat(BO, "BOUNCY 7 RUBBER BAND", 94, k=rep("X.x...x...x.x..."), c=BACK, h=rep("x.x.x.x.x.x.x.x."),
    b=bass((0, "0", 2), (2, "0", 4), (6, "3", 4), (10, "0", 2), (12, "5", 4), (16, "0", 2), (18, "0", 4), (22, "3", 4), (26, "0", 2), (28, "7", 4)))
pat(BO, "BOUNCY 8 DOUBLE CLAP", 98, k=rep("X..x..x...x....."), c=put(BACK, (13, "o"), (29, "o")), h=put(rep("x.x.x.x.x.x.x.x."), (14, "."), (30, ".")), o=st(32, 14, 30))
pat(BO, "BOUNCY 9 CHOPPER", 110, k=rep("X..x..x.X..x..x."), c=st(32, 4, 12, 20, 28), s=st(32, 15, 30, 31, ch="o"), h=rep("x.xxx.xxx.xxx.xx"))
pat(BO, "BOUNCY 10 BLOCK BOUNCE", 102, k=phrase("X..x..x...x.....", "X..x..x...x..x.."), c=phrase("....X.......X...", fill="....X.......XXXX"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x....."), cr=CRASH4)

# ---------------- 80s Pop (drum machines and big rooms, 70-132: the gated snare on 2 and 4, eighth or sixteenth
# hats, handclaps on the backbeat, four-on-the-floor dance pop, tom runs into the crash) ----------------
EP = "80s Pop"
pat(EP, "80S POP 1 GATED SNARE", 118, k=phrase("X.......X.x....."), s=phrase("....X.......X..."), h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x....."),
    ht=bars(FILL0, "............XX.."), lt=bars(FILL0, "..............XX"), cr=CRASH4)
pat(EP, "80S POP 2 SYNTH DANCE", 124, k=phrase("X...X...X...X..."), s=phrase("....X.......X..."), c=phrase("....X.......X..."), h=phrase("x...x...x...x..."),
    o=phrase("..o...o...o...o."), cr=CRASH4)
pat(EP, "80S POP 3 NEW WAVE", 132, k=rep("X.......X......."), s=BACK, h=rep("XxoxXxoxXxoxXxox"))
pat(EP, "80S POP 4 POWER BALLAD", 72, k=phrase("X.......X.x....."), s=phrase("....X.......X...", fill="....X..........."), h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x........."),
    ht=bars(FILL0, "........X.X....."), lt=bars(FILL0, "............X.XX"), cr=CRASH4)
pat(EP, "80S POP 5 FUNK MACHINE", 110, k=rep("X..x..x...x..x.."), c=BACK, h=put(rep("xgxgxgxgxgxgxgxg"), (14, "."), (30, ".")), o=st(32, 14, 30, ch="o"))
pat(EP, "80S POP 6 MIDNIGHT DRIVE", 108, k=rep("X...X...X...X..."), s=BACK, h=rep("..x...x...x...x."))
pat(EP, "80S POP 7 HANDCLAP HIT", 116, k=rep("X.....x.X......."), c=BACK, h=rep("x.x.x.x.x.x.x.x."), p1=rep("....x.......x..."))
pat(EP, "80S POP 8 MACHINE SHUFFLE", 104, 62, k=rep("X.....x.X.....x."), s=BACK, h=rep("x.ox.ox.x.ox.ox."))
pat(EP, "80S POP 9 TOM BREAK", 120, k=phrase("X.......X.x....."), s=phrase("....X.......X...", fill="....X..........."), h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x........."),
    ht=bars(FILL0, "........XX.X...."), lt=bars(FILL0, "..........X.XXXX"), cr=CRASH4)
pat(EP, "80S POP 10 ARENA", 128, k=rep("X...X...X...X..."), s=BACK, c=BACK, h=rep("x.x.x.x.x.x.x.x."), cr=st(32, 0, 16))

# ---------------- Live Pop (one drummer with a band, 72-132: eighth-note hats in the verse, the ride or open hat
# in the chorus, four-on-the-floor lifts, half-time bridges, pre-chorus builds, tom fills into the crash) ----------------
LP = "Live Pop"
pat(LP, "LIVE POP 1 RADIO VERSE", 116, k=phrase("X.......X.x.....", "X.......X......x"), s=phrase("....X.......X...", fill="....X.......XXXX"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x....."), cr=CRASH4)
pat(LP, "LIVE POP 2 FOUR ON FLOOR", 120, k=phrase("X...X...X...X..."), s=phrase("....X.......X..."), h=phrase("x...x...x...x..."), o=phrase("..o...o...o...o."), cr=CRASH4)
pat(LP, "LIVE POP 3 RIDE CHORUS", 124, k=phrase("X.....x.X......."), s=phrase("....X.......X..."), cr=phrase("x.x.x.x.x.x.x.x."), h=phrase("....x.......x..."))
pat(LP, "LIVE POP 4 HALF TIME BRIDGE", 90, k=phrase("X.........x....."), s=phrase("........X.......", fill="........X...XXXX"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x....."), cr=CRASH4)
pat(LP, "LIVE POP 5 TOM GROOVE", 104, k=phrase("X.......X......."), s=phrase("....X.......X..."), lt=phrase("x.....x...x....."), cr=CRASH4)
pat(LP, "LIVE POP 6 BALLAD", 72, k=phrase("X.......x.x....."), r=phrase("....x.......x...", fill="....x..........."), s=bars(FILL0, "............goxX"),
    h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x.x.x....."), cr=CRASH4)
pat(LP, "LIVE POP 7 DRIVING EIGHTHS", 132, k=phrase("X.X.....X.X....."), s=phrase("....X.......X..."), h=phrase("x.x.x.x.x.x.x.x."))
pat(LP, "LIVE POP 8 PRE CHORUS BUILD", 120, k=bars("X.......X.......", "X...X...X...X...", "X.X.X.X.X.X.X.X.", "XXXXXXXXXXXXXXXX"),
    s=bars("....X.......X...", "....X.......X...", "X...X...X...X...", "X.X.X.X.XXXXXXXX"), h=bars("x.x.x.x.x.x.x.x.", "x.x.x.x.x.x.x.x.", "..x...x...x...x.", "." * 16), cr=CRASH4)
pat(LP, "LIVE POP 9 SIXTEENTHS", 100, k=phrase("X......x..x.....", "X......x..x...x."), s=phrase("....X.......X..."), h=phrase("xgxgxgxgxgxgxgxg"))
pat(LP, "LIVE POP 10 STADIUM FILL", 128, k=phrase("X.......X.x....."), s=phrase("....X.......X...", fill="....X...X.X.X.X."), h=phrase("x.x.x.x.x.x.x.x.", fill="x.x.x.x........."),
    ht=bars(FILL0, ".........X.X...."), lt=bars(FILL0, ".............X.X"), cr=CRASH4)

# ---------------- Dark Experimental (70-160: kicks displaced off the grid's usual spots, 3- 5- and 7-step cycles
# running against the bar, glitch rolls, industrial four-on-the-floor, the 808 on the minor second and flat fifth) ----------------
DX = "Dark Experimental"
pat(DX, "DARK EXPERIMENTAL 1 GLITCH", 140, k=st(32, 0, 3, 9, 13, 16, 22, 27), s=st(32, 8, 21, ch="X"), h=rep("xx..x.q..x.r..x."),
    b=bass((0, "0", 3), (3, "1", 6), (9, "0", 4), (13, "6", 3), (16, "0", 6), (22, "1", 5), (27, "0", 5)))
pat(DX, "DARK EXPERIMENTAL 2 THREE OVER FOUR", 120, k=rep("X.."), c=BACK, h=rep("x.x.x.x.x.x.x.x."), b=bass((0, "0", 12), (12, "1", 12), (24, "0", 8)))
pat(DX, "DARK EXPERIMENTAL 3 INDUSTRIAL", 128, k=rep("X...X...X...X..."), s=st(32, 4, 12, 20, 28, ch="X"), c=st(32, 4, 12, 20, 28, ch="X"), p1=rep("..x..x..x..x..x."), cr=st(32, 0, 16))
pat(DX, "DARK EXPERIMENTAL 4 BROKEN CLOCK", 90, k=st(32, 0, 5, 11, 16, 19, 26), s=st(32, 7, 23, ch="X"), r=rep("x...."), h=rep("x....."))
pat(DX, "DARK EXPERIMENTAL 5 VOID", 70, k=st(32, 0, 16), s=st(32, 12, ch="X"), o=st(32, 6, 22, ch="o"), p2=st(32, 3, 29, ch="g"), b=bass((0, "0", 16), (16, "1", 16)), glide=True)
pat(DX, "DARK EXPERIMENTAL 6 STUTTER GATE", 150, k=st(32, 0, 10, 16, 26), c=HALF, h=rep("q.q.r.r.x.x.q..."), b=bass((0, "0", 10), (10, "6", 6), (16, "0", 10), (26, "1", 6)))
pat(DX, "DARK EXPERIMENTAL 7 SEVEN STEP", 110, k=rep("X......"), s=st(32, 4, 12, 20, 28), h=rep("x..x..x..x..x..x"), p1=rep("g.g.g"))
pat(DX, "DARK EXPERIMENTAL 8 NOISE RITUAL", 100, k=st(32, 0, 8, 16, 24), c=st(32, 12, 28, ch="X"), lt=rep("x..x..x.x..x..x."), ht=st(32, 6, 14, 22, 30, ch="o"), p1=rep("g.g.g.g.g.g.g.g."))
pat(DX, "DARK EXPERIMENTAL 9 DRIFTING", 160, k=st(32, 0, 7, 13, 18, 25, 30), c=HALF, h=put(rep("x.x.x.x.x.x.x.x."), (4, "t"), (18, "t"), (26, "t")),
    b=bass((0, "0", 7), (7, "1", 6), (13, "0", 5), (18, "6", 7), (25, "0", 5), (30, "1", 2)), glide=True)
pat(DX, "DARK EXPERIMENTAL 10 COLLAPSE", 136, k=bars("X.....x...x.....", "X.....x...x..x..", "X.x.x.x.x.x.x.x.", "X..............."),
    c=bars("........X.......", "........X.......", "....X.......X...", "." * 16), h=bars("x.x.x.x.x.x.x.x.", "x.xxx.xxx.xxx.xx", "qqqqqqqqqqqqqqqq", "." * 16),
    cr=st(64, 48), b=b4((0, "0", 16), (16, "1", 16), (32, "6", 16), (48, "0", 16)))

# ---------------- World & Latin (reggaeton's dembow, bossa nova, samba, son clave, cumbia, dancehall, baile funk,
# moombahton, soca and mambo: the kick and the rim or clave carry the style; the 3-2 clave spans two bars) ----------------
WL = "World & Latin"
CLAVE32 = st(32, 0, 6, 12, 20, 24)                # son clave 3-2 across two bars
pat(WL, "WORLD & LATIN 1 DEMBOW", 96, k=rep("X...X...X...X..."), s=rep("...x..x....x..x."), h=rep("x.x.x.x.x.x.x.x."))
pat(WL, "WORLD & LATIN 2 BOSSA", 136, k=rep("X..xX..xX..xX..x"), r=st(32, 0, 3, 6, 10, 13, 18, 21, 25, 28), h=rep("xgxgxgxgxgxgxgxg"))
pat(WL, "WORLD & LATIN 3 SAMBA", 100, k=rep("o.......X......."), p1=rep("xgxxxgxxxgxxxgxx"), r=st(32, 0, 3, 6, 10, 12, 16, 19, 22, 26, 28), p2=rep("x..x..x...x.x..."))
pat(WL, "WORLD & LATIN 4 SON CLAVE", 100, k=st(32, 3, 8, 19, 24), r=CLAVE32, p1=rep("..x.x..x..x.x..x"), p2=rep("x.x.x.x.x.x.x.x."), lt=st(32, 14, 30))
pat(WL, "WORLD & LATIN 5 CUMBIA", 92, k=rep("X.......X......."), r=rep("....x.......x..."), p1=rep("x.xxx.xxx.xxx.xx"), h=rep("..x...x...x...x."))
pat(WL, "WORLD & LATIN 6 DANCEHALL", 94, k=rep("X...X...X...X..."), r=rep("...x..x....x...."), c=st(32, 12, 28), h=rep("x.x.x.x.x.x.x.x."))
pat(WL, "WORLD & LATIN 7 BAILE FUNK", 130, k=rep("X..x..x...x..x.."), c=rep("....X.......X..."), p1=rep("x..x..x.x..x..x."))
pat(WL, "WORLD & LATIN 8 MOOMBAHTON", 108, k=rep("X...X...X...X..."), s=rep("...x..x....x..x."), c=st(32, 12, 28), o=rep("..o...o...o...o."))
pat(WL, "WORLD & LATIN 9 SOCA", 160, k=rep("X...X...X...X..."), s=rep("......x.......x."), h=rep("x.xxx.xxx.xxx.xx"), p2=rep("x.x.x.x.x.x.x.x."))
pat(WL, "WORLD & LATIN 10 MAMBO", 104, k=st(32, 3, 8, 19, 24), r=CLAVE32, p2=rep("x.x.xx.xx.x.xx.x"), p1=rep("..x.x..x..x.x..x"), lt=st(32, 14, 15, 30, 31), cr=st(32, 0))

# ---------------- Learned Loops (Oct 20): the grooves tools/learn_from_loops.py heard in Tyrone's own
# drum loops and stems (tools/learned_patterns.json; the audio itself never ships). Each keeps the loop's
# tempo, length (4 or 8 bars), where every hit sits and how hard. Loops played off the 16ths (triplet
# feel, grid fit above 0.12) are left out: the lane format can't hold them. Names say what the groove does,
# not the pack it came from. ----------------
# BK Editions (Tyrone, Oct 20: "change the learned patterns to something else like BK Editions"):
# Vol 1 was Learned Loops, Vol 2 Learned RnB, Vol 3 his Drum Loops pack.
LEARNED = "BK Editions Vol 1"
LEARNED_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "learned_patterns.json")
def learned_name(i, lp, label="BK V1"):
    l = lp["lanes"]
    bar = lambda lane: [l[lane][j:j + 16] for j in range(0, len(l[lane]), 16)] if lane in l else []
    snare = bar("s") or bar("c") or bar("r")
    hat = l.get("h", "")
    bars_n = max(1, len(hat) // 16)
    if "lt" in l or "ht" in l: what = "TOM GROOVE"
    elif "t" in hat: what = "TRIPLET HATS"
    # a roll in most bars, not one stray double (Vol 1 keeps the names it first shipped with: any roll)
    elif hat.count("r") + hat.count("q") >= (1 if label == "BK V1" else bars_n): what = "HAT ROLLS"
    elif "r" in l and "s" not in l and "c" not in l: what = "RIM GROOVE"
    elif snare and lp["bpm"] >= 120 and all(b[4] == "." and b[12] == "." and b[8] != "." for b in snare if b.strip(".")): what = "HALF TIME"
    elif "o" in l: what = "OPEN HATS"
    else: what = "BOUNCE"
    return f"{label} {i} {lp['bpm']:g} {what}"
# Learned RnB: Tyrone's R&B loops (full mixes, no stems), split by tools/learn_fills.py --loops against the
# one-shots of the kit they were made with (tools/learned_mixed.json).
LEARNED_RNB = "BK Editions Vol 2"
# Vol 3: Tyrone's Drum Loops pack (Oct 20), split by tools/learn_fills.py --loops against his matching one-shots
# (tools/learned_drumloops.json). They are tops loops with no kick: each keeps its own snares, rims, hats and
# opens, and plays the kick of the Vol 1 groove nearest its tempo (off the steps where its snare lands).
LEARNED_DL = "BK Editions Vol 3"
# Vol 4: Tyrone's danger drum loops (Oct 20, West Coast R&B), split the same way (tools/learned_danger.json),
# each with the lanes' own lay-back (shift); all five kept, as he asked ("recreate them").
LEARNED_DANGER = "BK Editions Vol 4"
LEARNED_STYLES = (LEARNED, LEARNED_RNB, LEARNED_DL, LEARNED_DANGER)
def clean(lp):          # hats-only loops, and loops played off the 16ths (grid fit above 0.12): lines, not presets
    return lp.get("gridFit", 0) <= 0.12 and "k" in lp["lanes"]
def tops(lp):           # timed within 16 ms of the 16ths (the doubled tempo makes gridFit read in 32nds), 8+ hits
    return lp["gridFit"] * 15 / lp["bpm"] <= 0.016 and sum(c != "." for v in lp["lanes"].values() for c in v) >= 8
def with_kick(lp, kicks):
    if "k" in lp["lanes"]: return lp["lanes"]
    src = min(kicks, key=lambda k: (abs(k["bpm"] - lp["bpm"]), k["title"]))
    n = len(next(iter(lp["lanes"].values())))
    kick = (src["lanes"]["k"] * (n // len(src["lanes"]["k"]) + 1))[:n]
    snare = lp["lanes"].get("s") or lp["lanes"].get("c") or "." * n
    kick = "".join("." if snare[j] == "X" else ch for j, ch in enumerate(kick))
    return {"k": kick, **lp["lanes"]}
def add_learned(style, path, label, keep=clean, kicks=None):
    if not os.path.exists(path): return
    learned = [lp for lp in json.load(open(path))["learned"] if keep(lp)]
    learned.sort(key=lambda lp: (lp["bpm"], lp["title"]))
    for i, lp in enumerate(learned, 1):
        lanes = with_kick(lp, kicks) if kicks else lp["lanes"]
        lanes = {k: lanes[k] for k in LANES if k in lanes}
        P.append({"style": style, "name": learned_name(i, dict(lp, lanes=lanes), label), "bpm": lp["bpm"], "swing": 50, "glide": False, "lanes": lanes})
        for key in ("swingLanes", "shift"):
            if lp.get(key): P[-1][key] = lp[key]
    if learned: STYLES.append(style)
add_learned(LEARNED, LEARNED_FILE, "BK V1")
add_learned(LEARNED_RNB, os.path.join(os.path.dirname(LEARNED_FILE), "learned_mixed.json"), "BK V2")
add_learned(LEARNED_DL, os.path.join(os.path.dirname(LEARNED_FILE), "learned_drumloops.json"), "BK V3", keep=tops,
            kicks=[lp for lp in json.load(open(LEARNED_FILE))["learned"] if clean(lp)])
add_learned(LEARNED_DANGER, os.path.join(os.path.dirname(LEARNED_FILE), "learned_danger.json"), "BK V4", keep=lambda lp: "k" in lp["lanes"])
# Oct 24: Tyrone's genre list, in his order (Boom Bap and Drill were already above). After the BK Editions, so every
# older preset keeps its place in the list (the AUv3's factory preset numbers that hosts save).
STYLES += [TS, DK, PH, AL, MM, TO, VR, R2, LS, EC, LF, AF, BO, EP, LP, DX, WL]

# ---------------- checks and output ----------------
cnt = Counter(p["style"] for p in P)
assert list(cnt) and set(cnt) == set(STYLES), set(cnt) ^ set(STYLES)
for style, n in cnt.items(): assert n == (20 if style == WC else 10) or style in LEARNED_STYLES, (style, n)
P.sort(key=lambda p: STYLES.index(p["style"]))                      # stable: each style keeps its own order
names = [p["name"] for p in P]
assert len(set(names)) == len(names)
for p in P:
    for key, by_lane in FEEL_NAMES.get(p["name"], FEEL.get(p["style"], {})).items():
        used = {lane: v for lane, v in by_lane.items() if lane in p["lanes"]}
        if used: p[key] = used
VALID = set(".xXogrqt")
HANDS = ("s", "r", "h", "o", "cr", "lt", "ht")
for p in P:
    for key in ("swingLanes", "shift", "ghostChance"):
        for lane, v in p.get(key, {}).items():
            assert lane in LANES and lane in p["lanes"], (p["name"], key, lane)
            assert (-24 <= v <= 24) if key == "shift" else (0 <= v <= 1), (p["name"], key, v)
    for lane, s in p["lanes"].items():
        assert len(s) in ((16, 32, 64, 128) if p["style"] in LEARNED_STYLES else (16, 32, 64)), (p["name"], lane, len(s))
        allowed = set(".-0123456789abcABCDEFGHIJKL") if lane == "b" else VALID
        bad = set(s) - allowed
        assert not bad, (p["name"], lane, bad)
    assert 60 <= p["bpm"] <= 180 and 50 <= p["swing"] <= 66
    if p["style"] in DRUMMER:
        n = len(next(iter(p["lanes"].values())))
        ride = sum(ch != "." for ch in p["lanes"].get("cr", "")) >= n // 4      # riding the cymbal: the hat is the foot
        for i in range(n):
            hands = [l for l in HANDS if l in p["lanes"] and p["lanes"][l][i] != "." and not (ride and l == "h")]
            assert len(hands) <= 2, (p["name"], i, hands)
out = os.path.join(os.path.dirname(__file__), "..", "BreakBoss.swiftpm", "Resources", "PatternBank.json")
json.dump({"version": 1, "patterns": P}, open(out, "w"), indent=1)
print(len(P), "patterns;", dict(cnt))
