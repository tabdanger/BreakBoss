# Faceplate art pipeline

Run from the art working folder (sources in art2/src, measurements in knobs.json / rects.json):

    python3 platinum.py   # Platinum plates onto Modern (straight-line grid warp)
    python3 unify.py      # Vintage/Texture onto Modern; BreakBoss knob, Aldrich lettering and Modern's wood on every plate
    python3 clean.py      # live-control areas cleared, overlays and layout JSONs
    python3 buttons.py    # piano-roll / export / menu caps
    python3 check_align.py

Lettering uses Aldrich (SIL Open Font License, Google Fonts) only to bake the art; the font isn't shipped.
