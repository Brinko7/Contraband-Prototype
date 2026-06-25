"""
Generate SNES-style hooded-thief PLAYER sprite sheets for Contraband.

Style target: Secret of Mana / FF6 — chibi proportions (big readable head),
strong per-material colour separation (hood / cape / tunic / pants / boots /
skin / steel), visible separated legs, bold high-contrast shading, hard outline.

Three classes: CUTPURSE, SHADOWDANCER, ASSASSIN.
Each sheet: 4 cols (walk frames) x 4 rows (directions), 32x40 cells.
  row0 = DOWN/south (face visible)   row1 = LEFT/west (profile)
  row2 = RIGHT/east (profile)        row3 = UP/north  (back of hood)
  col0 = contact/idle  col1 = left-leg-fwd  col2 = passing  col3 = right-leg-fwd

Run from project root:  python3 spritegen/gen_player.py
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Canvas, Sheet, PAL, rgb, lighten, darken, mix, ramp, T, OUTLINE

CW, CH = 32, 40
CX = 16              # horizontal centre
BASE_Y = 37          # foot baseline


# ── per-class theme ───────────────────────────────────────────────────────────

class Theme:
    def __init__(self, cloak, tunic, pants, boots, skin, accent, eye,
                 trim=None, glow=False):
        self.cloak  = ramp(cloak, 5)     # hood + cape / mantle
        self.tunic  = ramp(tunic, 5)     # chest panel
        self.pants  = ramp(pants, 5)     # legs
        self.boots  = ramp(boots, 5)     # feet
        self.skin   = ramp(skin, 5)      # face + hands
        self.accent = ramp(accent, 5)    # buckle / metal trim
        self.trim   = ramp(trim if trim else lighten(cloak, 0.22), 5)
        self.eye    = eye                # eye / glow colour
        self.glow   = glow               # draws an eye-glow bloom


THEMES = {
    "cutpurse": Theme(
        cloak=PAL["leather"],        tunic=PAL["cloth_blue"],
        pants=PAL["leather_dk"],     boots=PAL["cloth_black"],
        skin=PAL["skin_tan"],        accent=PAL["gold"],
        eye=rgb(40, 32, 36),         trim=PAL["wood_lt"]),
    "shadowdancer": Theme(
        cloak=PAL["cloth_purple"],   tunic=PAL["cloth_black"],
        pants=PAL["obsidian"],       boots=PAL["cloth_black"],
        skin=mix(PAL["skin_pale"], PAL["cloth_purple"], 0.14),
        accent=PAL["gem_purple"],    eye=rgb(206, 150, 255),
        trim=mix(PAL["cloth_purple"], PAL["gem_purple"], 0.6), glow=True),
    "assassin": Theme(
        cloak=PAL["cloth_black"],    tunic=darken(PAL["cloth_red"], 0.28),
        pants=PAL["cloth_black"],    boots=darken(PAL["cloth_black"], 0.25),
        skin=mix(PAL["skin_tan"], PAL["cloth_black"], 0.14),
        accent=PAL["steel"],         eye=rgb(255, 78, 64),
        trim=PAL["cloth_red"],       glow=True),
}


# walk cycle: per frame -> (left_leg_dy, right_leg_dy, body_bob)
WALK = [(0, 0, 0), (1, -1, -1), (0, 0, 0), (-1, 1, -1)]
# near-arm swing per frame (profile)
ARM_SWING = [0, -1, 0, 1]


# ── shading helpers ───────────────────────────────────────────────────────────

def col_shade(rmp, x, x0, x1, base=2, lit=0.30, shad=0.78):
    """Pick a ramp tone by horizontal position across [x0,x1] — light upper-left."""
    if x1 <= x0:
        return rmp[base]
    f = (x - x0) / (x1 - x0)        # 0 left .. 1 right
    if f < lit:   return rmp[min(4, base + 2)]
    if f < 0.42:  return rmp[min(4, base + 1)]
    if f > shad:  return rmp[max(0, base - 2)]
    if f > 0.6:   return rmp[max(0, base - 1)]
    return rmp[base]


def vpanel(c, x0, x1, y0, y1, rmp, top_hi=True):
    """Fill a vertical panel with left-lit cylindrical shading."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            sh = col_shade(rmp, x, x0, x1)
            if top_hi and y == y0:
                sh = lighten(sh, 0.12)
            c.put(x, y, sh)


# ── DOWN (facing camera) ──────────────────────────────────────────────────────

def build_down(t, frame):
    c = Canvas(CW, CH)
    dl, dr, bob = WALK[frame]
    by = BASE_Y
    top = 19 + bob               # shoulder line

    # — legs (two visible) —
    leg_top = top + 9
    for (lx0, lx1, dy) in ((CX - 4, CX - 1, dl), (CX + 1, CX + 4, dr)):
        vpanel(c, lx0, lx1, leg_top, by - 2 + dy, t.pants)
        # boot
        for yy in range(by - 2 + dy, by + dy):
            for xx in range(lx0, lx1 + 1):
                c.put(xx, yy, col_shade(t.boots, xx, lx0, lx1))
        c.put(lx0, by - 2 + dy, t.boots[3])           # toe glint
        # toe cap forward
        c.put(lx1 + 1, by - 1 + dy, t.boots[1])

    # — mantle / cape behind shoulders (hangs to hips) —
    cap_hi = top - 1
    cap_lo = top + 8
    for y in range(cap_hi, cap_lo + 1):
        tt = (y - cap_hi) / max(1, cap_lo - cap_hi)
        half = int(round(8 + tt * 2))
        for x in range(CX - half, CX + half + 1):
            c.put(x, y, col_shade(t.cloak, x, CX - half, CX + half, base=1))
    # cape centre seam
    for y in range(cap_hi + 2, cap_lo):
        c.put(CX, y, t.cloak[0])

    # — torso / tunic (chest panel framed by the open cape) —
    for y in range(top + 1, top + 8):
        tt = (y - (top + 1)) / 6.0
        half = int(round(4 - tt * 0.6))
        vpanel(c, CX - half, CX + half, y, y, t.tunic, top_hi=(y == top + 1))
    # V-neck / collar shadow
    c.put(CX, top + 1, darken(t.tunic[0], 0.2))
    c.put(CX - 1, top + 2, t.tunic[3]); c.put(CX + 1, top + 2, t.tunic[1])

    # — belt + buckle —
    belt_y = top + 8
    for x in range(CX - 4, CX + 5):
        if c.get(x, belt_y)[3]:
            c.put(x, belt_y, col_shade(t.boots, x, CX - 4, CX + 4, base=2))
    c.put(CX, belt_y, t.accent[4]); c.put(CX + 1, belt_y, t.accent[2])

    # — arms down the sides + bare hands —
    sw = ARM_SWING[frame]
    ay = top + 1
    # left arm
    vpanel(c, CX - 7, CX - 5, ay + max(0, sw), ay + 6 + max(0, sw), t.cloak, top_hi=False)
    c.rect(CX - 7, ay + 7 + max(0, sw), 2, 2, t.skin[2]); c.put(CX - 7, ay + 7 + max(0, sw), t.skin[3])
    # right arm + dagger
    vpanel(c, CX + 5, CX + 7, ay + max(0, -sw), ay + 6 + max(0, -sw), t.cloak, top_hi=False)
    c.rect(CX + 6, ay + 7 + max(0, -sw), 2, 2, t.skin[1])
    draw_dagger(c, CX + 7, ay + 8 + max(0, -sw), +1, t.accent)

    # — hood + face —
    draw_hood_front(c, t, top)

    c.auto_outline()
    return c


def draw_hood_front(c, t, shoulder):
    clk, trm, skn = t.cloak, t.trim, t.skin
    cx = CX
    crown = shoulder - 12        # top of hood
    midy  = shoulder - 5
    # hood dome — big and rounded (chibi head)
    for y in range(crown, shoulder + 1):
        ny = (y - midy) / 7.5
        w = int(round(math.sqrt(max(0.0, 1 - ny * ny)) * 8))
        if w < 2:
            w = 2
        for x in range(cx - w, cx + w + 1):
            c.put(x, y, col_shade(clk, x, cx - w, cx + w, base=2))
    # peaked crown highlight
    c.put(cx - 1, crown, clk[3]); c.put(cx, crown, clk[2])

    # face opening — large oval, lower-centre of the hood
    fy0, fy1 = midy, shoulder
    fcx = cx
    for y in range(fy0, fy1 + 1):
        ny = (y - (fy0 + (fy1 - fy0) * 0.5)) / max(1.0, (fy1 - fy0) * 0.55)
        w = int(round(math.sqrt(max(0.0, 1 - ny * ny)) * 4))
        if w < 1:
            continue
        for x in range(fcx - w, fcx + w + 1):
            # skin: left cheek lit, right cheek shadowed
            f = (x - (fcx - w)) / max(1, 2 * w)
            sh = skn[3] if f < 0.32 else (skn[2] if f < 0.62 else skn[1])
            c.put(x, y, sh)
    # brow shadow cast by the hood
    for x in range(fcx - 3, fcx + 4):
        c.put(x, fy0, darken(skn[0], 0.30))
    # eyes
    ey = fy0 + 2
    if t.glow:
        c.put(fcx - 2, ey, t.eye); c.put(fcx + 1, ey, t.eye)
        c.put(fcx - 2, ey - 0, lighten(t.eye, 0.4))
        c.put(fcx - 2, ey + 1, mix(t.eye, skn[1], 0.5))
        c.put(fcx + 1, ey + 1, mix(t.eye, skn[1], 0.5))
    else:
        c.put(fcx - 2, ey, t.eye); c.put(fcx + 1, ey, t.eye)
        c.put(fcx - 1, ey, lighten(skn[3], 0.2))   # nose bridge catchlight
    # nose + mouth
    c.put(fcx, ey + 1, skn[1])
    c.put(fcx, ey + 2, darken(skn[0], 0.15))
    c.put(fcx - 1, fy1, skn[2]); c.put(fcx, fy1, skn[1])   # chin/jaw light

    # hood brim arc over the brow (trim band)
    for x in range(fcx - 5, fcx + 6):
        dx = abs(x - fcx)
        yy = (fy0 - 1) + (1 if dx >= 4 else 0)
        c.put(x, yy, trm[3] if x < fcx else trm[1])


def draw_dagger(c, x, y, f, accent):
    st = ramp(PAL["steel"], 5)
    c.put(x, y, st[4]); c.put(x, y + 1, st[3]); c.put(x, y + 2, st[2]); c.put(x, y + 3, st[1])
    c.put(x + (1 if f >= 0 else -1), y + 1, st[2])
    c.put(x - 1, y - 1, accent[3]); c.put(x + 1, y - 1, accent[2])   # crossguard
    c.put(x, y - 2, accent[4])                                       # pommel


# ── SIDE (profile). f = -1 left, +1 right ─────────────────────────────────────

def build_side(t, frame, f):
    c = Canvas(CW, CH)
    dl, dr, bob = WALK[frame]
    by = BASE_Y
    top = 19 + bob
    cx = CX

    # — striding legs along facing axis —
    swing = [(2, -2), (3, -3), (0, 0), (-2, 2)][frame]   # (front, back)
    leg_top = top + 9
    for near, sw in ((False, swing[1]), (True, swing[0])):
        fx = cx + f * sw
        pcol = t.pants if near else [darken(x, 0.16) for x in t.pants]
        x0 = min(fx - 1, fx + 1)
        vpanel(c, x0, x0 + 2, leg_top, by - 2, pcol)
        bcol = t.boots if near else [darken(x, 0.16) for x in t.boots]
        for yy in range(by - 2, by):
            for xx in range(x0, x0 + 3 + (1 if f > 0 else 0)):
                c.put(xx, yy, bcol[1])
        c.put(cx + f * (sw + 2), by - 1, bcol[2])      # toe forward

    # — cape trailing behind —
    draw_cape_side(c, t, top, by, frame, f)

    # — torso / tunic —
    for y in range(top + 1, top + 9):
        x0 = cx - 4
        x1 = cx + 4
        for x in range(x0, x1 + 1):
            local = (x - cx) * f                       # >0 toward front
            if local > 1:   col = t.tunic[3]
            elif local > -1: col = t.tunic[2]
            else:            col = t.cloak[1]           # back = cape
            c.put(x, y, col)
    # belt
    belt_y = top + 8
    for x in range(cx - 4, cx + 5):
        if c.get(x, belt_y)[3]:
            c.put(x, belt_y, t.boots[1])
    c.put(cx + f * 3, belt_y, t.accent[3])

    # — near arm + dagger —
    asw = ARM_SWING[frame]
    ay = top + 2
    ax = cx + f * 2
    vpanel(c, min(ax, ax + f * 2), max(ax, ax + f * 2), ay + max(0, asw), ay + 5 + max(0, asw), t.cloak, top_hi=False)
    hx = cx + f * 4
    c.rect(min(hx, hx + 1), ay + 6 + max(0, asw), 2, 2, t.skin[2])
    draw_dagger(c, cx + f * 5, ay + 7 + max(0, asw), f, t.accent)

    # — hood + profile face —
    draw_hood_side(c, t, top, f)

    c.auto_outline()
    return c


def draw_hood_side(c, t, shoulder, f):
    clk, trm, skn = t.cloak, t.trim, t.skin
    cx = CX
    crown = shoulder - 12
    midy = shoulder - 5
    for y in range(crown, shoulder + 1):
        ny = (y - midy) / 7.5
        w = int(round(math.sqrt(max(0.0, 1 - ny * ny)) * 8))
        if w < 2:
            w = 2
        for x in range(cx - w, cx + w + 1):
            local = (x - cx) * f
            if local < -w * 0.4:   sh = clk[0]       # back of hood
            elif local < 0:        sh = clk[1]
            elif local > w * 0.4:  sh = clk[3]        # front-top lit
            else:                  sh = clk[2]
            c.put(x, y, sh)
    c.put(cx - f, crown, clk[2])
    # draped back of hood slumping to the shoulders
    bx = cx - f * 7
    c.put(bx, midy + 1, clk[1]); c.put(bx, midy + 2, clk[0])
    c.put(bx + f, midy + 3, clk[0])

    # face opening on facing side
    fcx = cx + f * 3
    for y in range(midy, shoulder):
        for x in range(min(fcx, fcx + f * 2), max(fcx, fcx + f * 2) + 1):
            c.put(x, y, skn[2])
    # protruding nose / brow / chin profile
    nx = cx + f * 6
    c.put(nx, midy + 1, skn[3])                 # brow
    c.put(nx + f, midy + 2, skn[3])             # nose tip
    c.put(nx, midy + 3, skn[2])
    c.put(nx - f, shoulder - 1, skn[1])         # chin
    # eye
    ex, ey = cx + f * 4, midy + 2
    if t.glow:
        c.put(ex, ey, t.eye); c.put(ex, ey, lighten(t.eye, 0.4))
    else:
        c.put(ex, ey, t.eye)
    # brow trim
    for i in range(4):
        c.put(cx + f * (2 + i), midy, trm[2])


def draw_cape_side(c, t, top, by, frame, f):
    cap = t.cloak
    length = [5, 7, 6, 8][frame]
    for y in range(top, by - 3):
        tt = (y - top) / max(1, (by - 3) - top)
        ln = int(round(length * (0.4 + tt)))
        x0 = cx_back = CX - f * 3
        for i in range(ln):
            x = x0 - f * i
            wob = int(round(math.sin(i * 0.6 + frame * 0.9) * 1.1))
            sh = 1 if i < ln - 2 else 0
            c.put(x, y + wob, cap[sh])


# ── UP (back of hood) ─────────────────────────────────────────────────────────

def build_up(t, frame):
    c = Canvas(CW, CH)
    dl, dr, bob = WALK[frame]
    by = BASE_Y
    top = 19 + bob
    cx = CX

    # legs
    leg_top = top + 9
    for (lx0, lx1, dy) in ((cx - 4, cx - 1, dl), (cx + 1, cx + 4, dr)):
        vpanel(c, lx0, lx1, leg_top, by - 2 + dy, t.pants)
        for yy in range(by - 2 + dy, by + dy):
            for xx in range(lx0, lx1 + 1):
                c.put(xx, yy, col_shade(t.boots, xx, lx0, lx1))

    # cape down the back (covers most of the torso)
    cap_hi = top - 1
    for y in range(cap_hi, leg_top):
        tt = (y - cap_hi) / max(1, leg_top - cap_hi)
        half = int(round(7 + tt * 1))
        for x in range(cx - half, cx + half + 1):
            c.put(x, y, col_shade(t.cloak, x, cx - half, cx + half, base=1))
    for y in range(cap_hi + 2, leg_top - 1):
        c.put(cx, y, t.cloak[0])                 # centre seam

    # arms
    sw = ARM_SWING[frame]
    ay = top + 1
    vpanel(c, cx - 7, cx - 5, ay + max(0, sw), ay + 6 + max(0, sw), t.cloak, top_hi=False)
    vpanel(c, cx + 5, cx + 7, ay + max(0, -sw), ay + 6 + max(0, -sw), t.cloak, top_hi=False)

    # hood back dome (no face)
    crown = top - 12
    midy = top - 5
    for y in range(crown, top + 1):
        ny = (y - midy) / 7.5
        w = int(round(math.sqrt(max(0.0, 1 - ny * ny)) * 8))
        if w < 2:
            w = 2
        for x in range(cx - w, cx + w + 1):
            c.put(x, y, col_shade(t.cloak, x, cx - w, cx + w, base=2))
    for y in range(crown + 2, top):
        c.put(cx, y, t.cloak[1])                 # back seam
    c.put(cx, crown, t.cloak[3])
    # trim ring where hood meets shoulders
    for x in range(cx - 6, cx + 7):
        c.put(x, top, t.trim[2] if x < cx else t.trim[1])

    c.auto_outline()
    return c


# ── assemble sheets ───────────────────────────────────────────────────────────

def place(sheet_canvas, col, row, cell):
    ox, oy = col * CW, row * CH
    for y in range(cell.h):
        for x in range(cell.w):
            p = cell.px[y * cell.w + x]
            if p[3]:
                sheet_canvas.put(ox + x, oy + y, p, blend=False)


def build_sheet(name):
    t = THEMES[name]
    sh = Sheet(4, 4, CW, CH)
    for frame in range(4):
        place(sh.canvas, frame, 0, build_down(t, frame))
        place(sh.canvas, frame, 1, build_side(t, frame, -1))
        place(sh.canvas, frame, 2, build_side(t, frame, +1))
        place(sh.canvas, frame, 3, build_up(t, frame))
    return sh


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sprites = os.path.join(root, "sprites")
    prev = os.path.join(root, "spritegen", "previews")
    os.makedirs(prev, exist_ok=True)
    for name in ("cutpurse", "shadowdancer", "assassin"):
        sh = build_sheet(name)
        cv = sh.canvas
        out = os.path.join(sprites, f"player_{name}.png")
        lib.write_png(out, cv.px, cv.w, cv.h)
        lib.save_preview(cv, os.path.join(prev, f"player_{name}.png"), factor=6)
        print(f"wrote {out} {cv.w}x{cv.h}")


if __name__ == "__main__":
    main()
