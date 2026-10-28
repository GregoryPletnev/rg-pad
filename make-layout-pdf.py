"""Render the rgpad layout (from rgpad.conf) into a 2-page A4 landscape PDF.

Usage: python3 make-layout-pdf.py rgpad.conf rgpad-layout.pdf

Requires: pip install reportlab
On macOS the script uses the bundled Arial / Courier New fonts.
On Linux, point the paths below to any TTF fonts (for example DejaVu).
"""
import math
import os
import platform
import sys

from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

CONF, OUT = sys.argv[1], sys.argv[2]

if platform.system() == "Darwin":
    FONT_DIR = "/System/Library/Fonts/Supplemental"
    F_SANS = os.path.join(FONT_DIR, "Arial.ttf")
    F_SANS_B = os.path.join(FONT_DIR, "Arial Bold.ttf")
    F_MONO = os.path.join(FONT_DIR, "Courier New Bold.ttf")
else:
    F_SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    F_SANS_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    F_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

pdfmetrics.registerFont(TTFont("Sans", F_SANS))
pdfmetrics.registerFont(TTFont("SansB", F_SANS_B))
pdfmetrics.registerFont(TTFont("Mono", F_MONO))

INK = HexColor("#1f2328")
MUTED = HexColor("#656d76")
LINE = HexColor("#d0d7de")
FILL = HexColor("#f6f8fa")
BTN = {"x": HexColor("#2f6fdf"), "a": HexColor("#d1382f"),
       "b": HexColor("#d99a00"), "y": HexColor("#2e9a48")}
ORDER = ["x", "a", "b", "y"]           # tokens order in the config: clockwise from top
DIRS = {"e": 0, "ne": 45, "n": 90, "nw": 135, "w": 180, "sw": 225, "s": 270, "se": 315}
SHORT = {"SPACE": "Spc", "BACKSPACE": "BS", "DELETE": "Del", "TAB": "Tab", "ENTER": "Ent"}


def parse(path):
    sections, layers, cur = {}, [], None
    for raw in open(path, encoding="utf-8"):
        s = raw.strip()
        if not s or s[0] in "#;":
            continue
        if s.startswith("["):
            name = s[1:s.index("]")].strip()
            if name.lower().startswith("layer "):
                cur = {}
                layers.append((name[6:].strip(), cur))
            else:
                cur = sections.setdefault(name.lower(), {})
            continue
        k, v = s.split("=", 1)
        cur[k.strip().lower()] = v.strip()
    return sections, layers


sec, layers = parse(CONF)
buttons = sec.get("buttons", {})
rs = sec.get("right_stick", {})
rs_keys = rs.get("keys", "").split()
rs_mode = rs.get("mode", "mouse").lower()
W, H = landscape(A4)
c = canvas.Canvas(OUT, pagesize=landscape(A4))
c.setTitle("rgpad — RG35XXH layout")
c.setAuthor("rgpad")


def text(x, y, s, font="Sans", size=10, color=INK, anchor="l"):
    c.setFont(font, size)
    c.setFillColor(color)
    {"l": c.drawString, "c": c.drawCentredString, "r": c.drawRightString}[anchor](x, y, s)


def header(title, sub):
    text(36, H - 48, title, "SansB", 20)
    text(36, H - 68, sub, "Sans", 10, MUTED)
    c.setStrokeColor(LINE)
    c.line(36, H - 78, W - 36, H - 78)


def describe(v):
    v = v.strip()
    if v.lower() == "@layer":
        return "next layer (abc → ABC → 123)"
    return {"BTN_LEFT": "mouse: left button", "BTN_RIGHT": "mouse: right button",
            "BTN_MIDDLE": "mouse: middle (paste in gpm)",
            "LEFTCTRL": "Ctrl (hold)"}.get(v.upper(), v.upper())


# ---------------- page 1: buttons ----------------
header("rgpad — RG35XXH layout",
       "Gamepad → keyboard and mouse. Config: /etc/rgpad.conf, apply: systemctl restart rgpad")

names = [("select", "Select"), ("start", "Start"), ("menu", "Menu"), ("l1", "L1"),
         ("r1", "R1"), ("l2", "L2"), ("r2", "R2"), ("l3", "L3 (left stick press)"),
         ("r3", "R3 (right stick press)"), ("up", "D-pad ↑"), ("down", "D-pad ↓"),
         ("left", "D-pad ←"), ("right", "D-pad →")]
x0, y = 36, H - 110
text(x0, y, "Buttons", "SansB", 13)
y -= 22
for key, label in names:
    if key not in buttons:
        continue
    c.setFillColor(FILL)
    c.setStrokeColor(LINE)
    c.roundRect(x0, y - 6, 410, 20, 4, fill=1, stroke=1)
    text(x0 + 10, y, label, "SansB", 10)
    text(x0 + 175, y, describe(buttons[key]), "Sans", 10)
    y -= 24

rows = [
    ("Left stick + X / A / B / Y", "character: 8 directions × 4 buttons (p. 2)"),
    ("Left stick at rest + button", "X = Tab, A = Space, B = Backspace, Y = Delete"),
]
if rs_mode == "keys":
    rows.append(("Right stick", "keys mode — see the wheel on page 2"))
else:
    rows.append(("Right stick", "mouse pointer (gpm in the console)"))
rows += [
    ("Start + Menu", "toggle the mapping (gamepad goes to games)"),
    ("Vol+ / Vol−", "not captured (volume)"),
]
y -= 8
text(x0, y, "Sticks and combos", "SansB", 13)
y -= 22
for a, b in rows:
    c.setFillColor(FILL)
    c.setStrokeColor(LINE)
    c.roundRect(x0, y - 6, 410, 20, 4, fill=1, stroke=1)
    text(x0 + 10, y, a, "SansB", 10)
    text(x0 + 175, y, b, "Sans", 9)
    y -= 24

# right column: how a chord works + LED
cx, cy = 620, H - 250
text(480, H - 110, "How to type a character", "SansB", 13)
steps = ["1. Deflect the left stick in one of 8 directions.",
         "2. Press X, A, B or Y — buttons go clockwise",
         "    from the top: X (top), A (right), B (bottom), Y (left).",
         "3. Hold the button for auto-repeat.",
         "Example (abc layer): ↑ + X = a,  ↑ + A = b,  → + A = j."]
for i, s in enumerate(steps):
    text(480, H - 134 - i * 16, s, "Sans", 10)

# diamond legend
r = 34
c.setStrokeColor(LINE)
c.circle(cx, cy - 40, 62, stroke=1, fill=0)
for b, ang in zip(ORDER, (90, 0, 270, 180)):
    px = cx + r * math.cos(math.radians(ang))
    py = cy - 40 + r * math.sin(math.radians(ang))
    c.setFillColor(BTN[b])
    c.circle(px, py, 15, stroke=0, fill=1)
    text(px, py - 5, b.upper(), "SansB", 14, white, "c")

ly = cy - 140
text(480, ly, "Indicator (red LED)", "SansB", 13)
for i, s in enumerate(["off — abc layer", "on — ABC layer",
                       "blinking — 123 layer", "pulsing — mapping disabled"]):
    text(480, ly - 22 - i * 16, "•  " + s, "Sans", 10)
c.showPage()

# ---------------- page 2: chord wheels ----------------
header("Chords: left stick + X / A / B / Y",
       "Each sector shows the characters for X (top), A (right), B (bottom), "
       "Y (left). Center — stick at rest. Menu switches the layer.")

R = 108
centers = [(W / 2 + (i - 1) * 272, H / 2 - 30) for i in range(len(layers[:3]))]


def short(tok):
    return SHORT.get(tok.upper(), tok) if len(tok) > 1 else tok


def diamond(x, y, toks, size, d):
    for b, ang, tok in zip(ORDER, (90, 0, 270, 180), toks + [""] * (4 - len(toks))):
        if not tok:
            continue
        px = x + d * math.cos(math.radians(ang))
        py = y + d * math.sin(math.radians(ang))
        s = short(tok)
        fs = size if len(s) == 1 else size * 0.55
        text(px, py - fs * 0.35, s, "Mono" if len(s) == 1 else "SansB", fs, BTN[b], "c")


for (name, lay), (x, y) in zip(layers, centers):
    text(x, y + R + 34, f"layer {name}", "SansB", 15, INK, "c")
    c.setStrokeColor(LINE)
    c.setFillColor(FILL)
    c.circle(x, y, R, stroke=1, fill=1)
    c.setFillColor(white)
    c.circle(x, y, 34, stroke=1, fill=1)
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        c.line(x + 34 * math.cos(a), y + 34 * math.sin(a), x + R * math.cos(a), y + R * math.sin(a))
    for dname, ang in DIRS.items():
        toks = lay.get(dname, "").split()
        px = x + 72 * math.cos(math.radians(ang))
        py = y + 72 * math.sin(math.radians(ang))
        diamond(px, py, toks, 15, 15)
        # direction arrow outside the wheel
        ax = x + (R + 10) * math.cos(math.radians(ang))
        ay = y + (R + 10) * math.sin(math.radians(ang))
        bx = x + (R + 20) * math.cos(math.radians(ang))
        by = y + (R + 20) * math.sin(math.radians(ang))
        c.setStrokeColor(MUTED)
        c.line(ax, ay, bx, by)
        for side in (-25, 25):
            h = math.radians(ang + 180 + side)
            c.line(bx, by, bx + 5 * math.cos(h), by + 5 * math.sin(h))
    diamond(x, y, lay.get("center", "").split(), 15, 17)

text(W / 2, 44, "Generated from rgpad.conf. Characters are typed on the US "
     "layout; hold Start + character = Ctrl+character.", "Sans", 9, MUTED, "c")

if rs_mode == "keys":
    # -------- extra page: right stick key wheel --------
    c.showPage()
    header("Right stick keys",
           "mode = keys in [right_stick]: each direction holds one key while "
           "the stick is deflected past the threshold.")
    x, y = W / 2, H / 2 - 20
    R = 130
    text(x, y + R + 44, "layer-independent", "SansB", 12, MUTED, "c")
    c.setStrokeColor(LINE)
    c.setFillColor(FILL)
    c.circle(x, y, R, stroke=1, fill=1)
    c.setFillColor(white)
    c.circle(x, y, 40, stroke=1, fill=1)
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        c.line(x + 40 * math.cos(a), y + 40 * math.sin(a),
               x + R * math.cos(a), y + R * math.sin(a))
    for (dname, ang), tok in zip(DIRS.items(), rs_keys):
        px = x + 85 * math.cos(math.radians(ang))
        py = y + 85 * math.sin(math.radians(ang))
        s = SHORT.get(tok.upper(), tok)
        fs = 18 if len(s) == 1 else 13
        text(px, py - fs * 0.35, s, "SansB", fs, INK, "c")
        ax = x + (R + 10) * math.cos(math.radians(ang))
        ay = y + (R + 10) * math.sin(math.radians(ang))
        bx = x + (R + 20) * math.cos(math.radians(ang))
        by = y + (R + 20) * math.sin(math.radians(ang))
        c.setStrokeColor(MUTED)
        c.line(ax, ay, bx, by)
        for side in (-25, 25):
            h = math.radians(ang + 180 + side)
            c.line(bx, by, bx + 5 * math.cos(h), by + 5 * math.sin(h))
        dx = x + (R - 34) * math.cos(math.radians(ang))
        dy = y + (R - 34) * math.sin(math.radians(ang))
        text(dx, dy - 4, dname.upper(), "Sans", 8, MUTED, "c")
    text(x, y - 6, "stick", "Sans", 9, MUTED, "c")
    text(x, y - 18, "at rest:", "Sans", 9, MUTED, "c")
    text(x, y - 30, "no key", "SansB", 9, INK, "c")

c.showPage()
c.save()
print("written", OUT)
