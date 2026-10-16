# Faceplate art pipeline

Run from the art working folder (sources in art2/src, measurements in knobs.json / rects.json):

    python3 platinum.py   # Platinum plates onto Modern (straight-line grid warp)
    python3 unify.py      # Vintage/Texture onto Modern; BreakBoss knob, Aldrich lettering and Modern's wood on every plate
    python3 clean.py      # live-control areas cleared, overlays and layout JSONs
    python3 buttons.py    # piano-roll / export / menu caps
    python3 check_align.py

Lettering uses Aldrich (SIL Open Font License, Google Fonts) only to bake the art; the font isn't shipped.

## Platinum master (Oct 14)
Tyrone: "KEEP Platinum layout and match every other faceplate around it". Platinum is now the master:
1. `platinum.py` (its iPad fixes, unwarped copy `src/l_platinum_raw.png`; iPhone plate lined up `src/p_platinum_W.png`)
2. `plat_geom.py` measures the iPad Platinum plate as drawn (no warp), clears its old knobs and words, fits it inside
   Modern's wood frame with one straight scale, writes `src/l_platinum_P.png` and `plat_geom_l.json`
3. `plat_phone.py` does the same clean-up for the iPhone plate (`src/p_platinum_P.png`)
4. `plat_unify.py` builds Modern, Vintage and Texture from Platinum (`master2.py`), adds the same knobs, Aldrich
   lettering and wood to all four, and (iPad) the piano / export / menu buttons in the top-right corner
5. `clean.py`, then `buttons.py`, then `check_align.py`
