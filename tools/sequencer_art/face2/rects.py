"""Where everything sits on Tyrone's Face 2 renders (1672 x 941 picture pixels, Oct 17 2026).
The four renders line up pixel for pixel, so one set of rectangles serves every finish."""
W, H = 1672, 941

TOOLS = [[325, 94, 427, 150], [430, 94, 529, 150], [532, 94, 630, 150]]
UNDO, REDO = [633, 94, 730, 150], [732, 94, 830, 150]
STOP, PLAY, REC = [858, 94, 925, 150], [928, 94, 995, 150], [997, 94, 1064, 150]
BPM, BARS = [1082, 94, 1238, 150], [1242, 94, 1382, 150]
GEAR, CLOUD = [1465, 95, 1528, 150], [1542, 93, 1605, 152]
TEMPO_SYNC, FOLLOW_DAW = [636, 160, 790, 205], [796, 160, 950, 205]
SNAP, SWING, HUMANIZE = [957, 159, 1171, 205], [1183, 161, 1369, 205], [1375, 161, 1530, 205]
SWING_KNOB, HUMANIZE_KNOB = [1327, 165, 1358, 196], [1490, 165, 1521, 196]
PAGE_BACK, PAGE_TEXT, PAGE_FWD = [432, 162, 466, 202], [466, 164, 594, 200], [592, 162, 626, 202]
LOGO = [92, 88, 296, 190]

LEFT_PANEL = [45, 218, 334, 707]           # SOUNDS header, well, GENERATE header
HEADER_H = 46

RACK_X0, RACK_X1 = 347, 606                # the track headers (tab + dark body)
GRID_WELL = [611, 221, 1629, 694]
GRID_X0, GRID_X1 = 626, 1576               # the steps
TOOLS_X = 1585                             # the per-track buttons column (dice / clear)
LABELS_Y = 247
ROWS_Y0, ROWS_Y1 = 266, 676
ROW_H = 62.5

SLIDER = [67, 728, 184, 790]
POWER = [197, 726, 263, 792]
# the render's PATTERN / KIT (moved left in the app, see build_face2.py)
PAT_ARROWS, PAT_CHIP = [605, 741, 703, 785], [704, 740, 956, 785]
KIT_ARROWS, KIT_CHIP = [1015, 741, 1112, 785], [1114, 740, 1329, 785]
PAT_LABEL, KIT_LABEL = [603, 711, 682, 733], [1013, 711, 1045, 733]
DIVIDERS_X = [577, 985]
DIVIDER_Y = [713, 787]
