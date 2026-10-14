# Label lettering for every faceplate: Aldrich (OFL), the free face closest to Modern's squared type.
import numpy as np
from PIL import Image, ImageDraw, ImageFont
FONT = "/home/claude/fonts/gf/ofl/aldrich/Aldrich-Regular.ttf"
SS = 4

def text_alpha(text, cap_h, target_w=None, max_track=3.0):
    """Anti-aliased alpha of `text` whose capitals are cap_h px tall; letter spacing is
    adjusted (0..max_track px) toward target_w. Returns (alpha, cap_top_offset)."""
    size = 40
    f = ImageFont.truetype(FONT, size * SS)
    hb = f.getbbox("H")
    scale = cap_h * SS / (hb[3] - hb[1])
    f = ImageFont.truetype(FONT, max(4, int(round(size * SS * scale))))
    hb = f.getbbox("H")
    widths = [f.getlength(ch) for ch in text]
    natural = sum(widths)
    track = 0.0
    if target_w and len(text) > 1:
        track = np.clip((target_w * SS - natural) / (len(text) - 1), 0, max_track * SS)
    W = int(natural + track * (len(text) - 1)) + 8 * SS
    H = int(cap_h * SS * 2.2)
    im = Image.new("L", (W, H), 0); d = ImageDraw.Draw(im)
    x = 4 * SS; top = int(cap_h * SS * 0.5) - hb[1]
    for ch, w in zip(text, widths):
        d.text((x, top), ch, font=f, fill=255)
        x += w + track
    a = np.asarray(im.resize((W // SS, H // SS), Image.LANCZOS)).astype(np.float32) / 255
    cols = np.nonzero(a.max(0) > 0.05)[0]
    a = a[:, cols.min():cols.max() + 1]
    return a, cap_h * 0.5

def draw(img, text, cx, top, cap_h, color, target_w=None):
    """Draws text centred on cx with its capitals starting at `top` (img float32 HxWx3, BGR)."""
    a, off = text_alpha(text, cap_h, target_w)
    h, w = a.shape
    x0 = int(round(cx - w / 2)); y0 = int(round(top - off))
    sub = img[y0:y0 + h, x0:x0 + w]
    a = a[:sub.shape[0], :sub.shape[1], None]
    img[y0:y0 + h, x0:x0 + w] = sub * (1 - a) + np.array(color, np.float32) * a
