import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Canvas, PAL, rgb, lighten, darken, mix, ramp, shift_hue_warm, OUTLINE, T, save_preview

SPR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sprites")
PRE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "previews")
os.makedirs(PRE, exist_ok=True)
os.makedirs(SPR, exist_ok=True)


# ── small shading helpers ─────────────────────────────────────────────────────

def shade_v(c, x, y, w, h):
    """Vertical-ish material shading factor by position in a w*h box.
    Returns a color: top-left lighter, bottom-right darker."""
    fx = x / max(1, w - 1)
    fy = y / max(1, h - 1)
    d = (fx + fy) / 2.0  # 0 = top-left, 1 = bottom-right
    if d < 0.45:
        return lighten(c, (0.45 - d) * 0.5)
    if d > 0.6:
        return darken(c, (d - 0.6) * 0.45)
    return c


def grain(cv, x0, y0, w, h, base, seed=0):
    """Vertical wood-grain plank fill with shading + speckle."""
    r = random.Random(seed)
    rr = ramp(base, 5)
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            fx = (x - x0) / max(1, w - 1)
            fy = (y - y0) / max(1, h - 1)
            d = (fx * 0.6 + fy * 0.4)
            idx = int(round((d) * 4))
            idx = max(0, min(4, 4 - idx))  # top-left bright
            c = rr[idx]
            # subtle grain streaks
            if r.random() < 0.10:
                c = darken(c, 0.10)
            elif r.random() < 0.06:
                c = lighten(c, 0.10)
            cv.put(x, y, c)


def plank_seam(cv, x, y0, y1, base):
    cv.vline(x, y0, y1, darken(base, 0.35))


def contact(cv, cx, by, rx, ry=None, alpha=95):
    if ry is None:
        ry = max(2, rx // 3)
    cv.drop_shadow(cx, by, rx, ry, alpha)


# ─────────────────────────────────────────────────────────────────────────────
# FURNITURE
# ─────────────────────────────────────────────────────────────────────────────

def gen_bookcase():
    W, H = 28, 32
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 12, 4)
    wood = PAL["wood"]
    x0, y0, bw, bh = 4, 2, 20, 28
    # back panel / carcass
    grain(cv, x0, y0, bw, bh, darken(wood, 0.2), seed=1)
    # outer frame posts
    cv.rect(x0, y0, 2, bh, darken(wood, 0.35))
    cv.rect(x0 + bw - 2, y0, 2, bh, darken(wood, 0.35))
    cv.rect(x0, y0, bw, 2, lighten(wood, 0.15))  # top trim
    cv.rect(x0, y0 + bh - 2, bw, 2, darken(wood, 0.4))  # base
    # interior cavity
    ix, iw = x0 + 2, bw - 4
    shelf_ys = [y0 + 2, y0 + 10, y0 + 18, y0 + 26]
    # dark recess
    cv.rect(ix, y0 + 2, iw, bh - 4, rgb(34, 24, 18))
    # book spine colors
    cols = [PAL["cloth_red"], PAL["cloth_blue"], PAL["gold_dk"], PAL["cloth_purple"],
            PAL["gem_green"], PAL["bronze"], rgb(60, 110, 90), PAL["cloth_red"],
            rgb(90, 60, 120), PAL["gold"], rgb(40, 80, 120)]
    rnd = random.Random(7)
    for si in range(3):
        sy0 = shelf_ys[si] + 2
        sy1 = shelf_ys[si + 1] - 1
        bx = ix + 1
        while bx < ix + iw - 1:
            bwid = rnd.choice([2, 2, 3, 3])
            if bx + bwid > ix + iw - 1:
                bwid = ix + iw - 1 - bx
            if bwid < 1:
                break
            col = rnd.choice(cols)
            bk = ramp(col, 5)
            topy = sy0 + rnd.choice([0, 1, 0])
            for x in range(bx, bx + bwid):
                fx = (x - bx) / max(1, bwid - 1)
                c = bk[1] if fx < 0.4 else (bk[3] if fx > 0.7 else bk[2])
                cv.vline(x, topy, sy1, c)
            # gold band detail
            if rnd.random() < 0.4 and bwid >= 2:
                cv.hline(bx, bx + bwid - 1, (topy + sy1) // 2, PAL["gold"])
            cv.vline(bx, topy, sy1, darken(col, 0.4))  # spine seam
            bx += bwid + rnd.choice([0, 0, 1])
        # shelf board
        cv.hline(ix, ix + iw - 1, sy1 + 1, lighten(wood, 0.1))
        cv.hline(ix, ix + iw - 1, sy1 + 2, darken(wood, 0.3))
    cv.auto_outline()
    return cv, H - 2


def gen_weaponrack():
    W, H = 28, 32
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 11, 4)
    wood = PAL["wood"]
    # two vertical posts + cross bars
    px = [6, W - 8]
    for x in px:
        grain(cv, x, 3, 3, 26, wood, seed=x)
        cv.vline(x, 3, 28, darken(wood, 0.4))
    # crossbars
    for y in (7, 25):
        cv.rect(6, y, W - 14, 2, lighten(wood, 0.1))
        cv.hline(6, W - 8, y + 1, darken(wood, 0.35))
    steel = ramp(PAL["steel"], 5)
    gold = ramp(PAL["gold"], 5)
    # crossed swords (X)
    def sword(x0, y0, x1, y1, hiltcol):
        cv.line(x0, y0, x1, y1, steel[3])
        cv.line(x0 + 1, y0, x1 + 1, y1, steel[2])
        cv.line(x0, y0 + 1, x1, y1 + 1, steel[1])
        # tip
        cv.put(x1, y1, steel[4])
        # guard + hilt at start
        cv.hline(x0 - 1, x0 + 2, y0, hiltcol[1])
        cv.vline(x0, y0, y0 + 3, hiltcol[3])
        cv.put(x0, y0 + 4, gold[4])  # pommel
    sword(9, 24, 19, 9, gold)
    sword(19, 24, 9, 9, gold)
    # spear vertical center behind
    sx = W // 2
    cv.vline(sx, 5, 27, mix(wood, PAL["leather"], 0.5))
    cv.vline(sx + 1, 5, 27, darken(wood, 0.3))
    # spearhead
    cv.line(sx, 5, sx, 1, steel[3])
    cv.put(sx, 1, steel[4])
    cv.put(sx - 1, 4, steel[2]); cv.put(sx + 1, 4, steel[2])
    cv.put(sx - 1, 3, steel[2]); cv.put(sx + 1, 3, steel[2])
    cv.auto_outline()
    return cv, H - 2


def gen_crate():
    W, H = 28, 32
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 12, 4)
    wood = PAL["wood"]
    x0, y0 = 4, 6
    bw, bh = 20, 22
    # top surface (3/4 view) — slight parallelogram lid
    top_h = 5
    for y in range(top_h):
        inset = 0
        cv.hline(x0 + inset, x0 + bw - 1 - inset, y0 - top_h + y + 1,
                 lighten(wood, 0.25 - y * 0.04))
    # body planks
    grain(cv, x0, y0, bw, bh, wood, seed=3)
    # plank seams vertical
    for sx in (x0 + 5, x0 + 10, x0 + 15):
        plank_seam(cv, sx, y0, y0 + bh - 1, wood)
    # cross banding (X)
    band = darken(wood, 0.3)
    bandh = lighten(wood, 0.12)
    cv.line(x0 + 1, y0 + 1, x0 + bw - 2, y0 + bh - 2, band)
    cv.line(x0 + 1, y0 + 2, x0 + bw - 2, y0 + bh - 1, bandh)
    cv.line(x0 + bw - 2, y0 + 1, x0 + 1, y0 + bh - 2, band)
    cv.line(x0 + bw - 2, y0 + 2, x0 + 1, y0 + bh - 1, bandh)
    # frame border
    cv.frame(x0, y0, bw, bh, darken(wood, 0.4))
    cv.frame(x0 + 1, y0 + 1, bw - 2, bh - 2, lighten(wood, 0.08))
    # metal corner brackets
    steel = ramp(PAL["steel"], 5)
    for (cx, cy) in [(x0, y0), (x0 + bw - 3, y0), (x0, y0 + bh - 3), (x0 + bw - 3, y0 + bh - 3)]:
        cv.rect(cx, cy, 3, 3, steel[1])
        cv.put(cx, cy, steel[3])
        cv.put(cx + 2, cy + 2, steel[0])
        cv.put(cx + 1, cy, steel[0])  # rivets
    cv.auto_outline()
    return cv, H - 2


def gen_trophyshelf():
    W, H = 28, 32
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 12, 3)
    wood = PAL["wood"]
    # wall-mounted shelf board with a back plate
    bx, bw = 3, 22
    # back board
    grain(cv, bx, 6, bw, 20, darken(wood, 0.15), seed=11)
    cv.frame(bx, 6, bw, 20, darken(wood, 0.4))
    # shelf board (the surface objects sit on)
    shy = 22
    cv.rect(bx - 1, shy, bw + 2, 3, lighten(wood, 0.18))
    cv.hline(bx - 1, bx + bw, shy + 3, darken(wood, 0.4))
    cv.hline(bx - 1, bx + bw, shy, lighten(wood, 0.3))
    # bracket supports
    cv.line(bx + 2, shy + 3, bx + 4, shy + 6, darken(wood, 0.3))
    cv.line(bx + bw - 3, shy + 3, bx + bw - 5, shy + 6, darken(wood, 0.3))

    shelf_top = shy  # objects rest with their base at this row
    # --- skull (left) ---
    sk = ramp(PAL["bone"], 5)
    scx = 8
    scy = shelf_top - 4  # cranium center so jaw sits on shelf
    cv.fill_ellipse_shaded(scx, scy, 3, 3, sk, light=(-0.6, -0.6))
    cv.rect(scx - 2, scy + 2, 5, 2, sk[1])     # jaw block
    cv.put(scx - 2, scy + 3, sk[0]); cv.put(scx + 2, scy + 3, sk[0])  # teeth gaps
    cv.put(scx, scy + 3, darken(PAL["bone"], 0.4))
    cv.rect(scx - 2, scy - 1, 2, 2, OUTLINE)   # left eye socket
    cv.rect(scx + 1, scy - 1, 2, 2, OUTLINE)   # right eye socket
    cv.put(scx, scy + 1, darken(PAL["bone"], 0.5))  # nasal cavity
    cv.put(scx - 1, scy - 2, lighten(PAL["bone"], 0.3))  # brow highlight

    # --- vase (center) — smaller, slimmer urn ---
    vc = ramp(PAL["gem_blue"], 5)
    vcx = 14
    vby = shelf_top - 1   # base sits on shelf
    # body bulge
    cv.fill_ellipse_shaded(vcx, vby - 3, 2, 3, vc, light=(-0.5, -0.6))
    cv.put(vcx - 1, vby, vc[1]); cv.put(vcx, vby, vc[1]); cv.put(vcx + 1, vby, vc[0])  # foot
    cv.put(vcx, vby - 7, vc[2]); cv.put(vcx, vby - 6, vc[2])  # neck
    cv.hline(vcx - 1, vcx + 1, vby - 8, vc[3])  # lip
    cv.put(vcx - 1, vby - 4, vc[4])  # highlight

    # --- gem (right) on small stand ---
    gm = ramp(PAL["gem_red"], 5)
    gcx = 20
    gcy = shelf_top - 3
    cv.put(gcx, gcy - 2, gm[4])
    cv.hline(gcx - 1, gcx + 1, gcy - 1, gm[3])
    cv.hline(gcx - 2, gcx + 2, gcy, gm[2])
    cv.hline(gcx - 1, gcx + 1, gcy + 1, gm[1])
    cv.put(gcx, gcy + 2, gm[0])
    cv.put(gcx - 1, gcy - 1, lighten(PAL["gem_red"], 0.4))
    cv.hline(gcx - 2, gcx + 2, gcy + 3, PAL["gold_dk"])  # stand base on shelf
    cv.auto_outline()
    return cv, H - 2


def gen_winerack():
    W, H = 28, 32
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 12, 4)
    wood = PAL["wood"]
    x0, y0 = 4, 4
    bw, bh = 20, 24
    grain(cv, x0, y0, bw, bh, darken(wood, 0.1), seed=5)
    cv.frame(x0, y0, bw, bh, darken(wood, 0.4))
    cv.frame(x0 + 1, y0 + 1, bw - 2, bh - 2, lighten(wood, 0.1))
    # grid cells with bottles (necks pointing out toward viewer)
    cells = [(x0 + 3 + cx * 7, y0 + 3 + cy * 7) for cy in range(3) for cx in range(2)]
    glass = ramp(PAL["gem_green"], 5)
    for (cx, cy) in cells:
        # cell recess
        cv.rect(cx, cy, 6, 6, rgb(30, 24, 18))
        cv.frame(cx - 1, cy - 1, 8, 8, darken(wood, 0.3))
        # bottle bottom (circle) seen end-on
        bcx, bcy = cx + 2, cy + 2
        cv.fill_ellipse_shaded(bcx, bcy, 2, 2, glass, light=(-0.6, -0.6))
        cv.put(bcx - 1, bcy - 1, lighten(PAL["gem_green"], 0.4))  # glint
        cv.put(bcx, bcy, darken(PAL["gem_green"], 0.3))  # punt dimple
        # cork
        cv.put(bcx, bcy, mix(PAL["leather"], wood, 0.5))
    cv.auto_outline()
    return cv, H - 2


def gen_barrel():
    W, H = 28, 32
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 11, 4)
    wood = PAL["wood"]
    cx = W // 2
    top_y, bot_y = 6, 29
    # barrel body — bulging staves
    body = ramp(wood, 6)
    for y in range(top_y, bot_y):
        t = (y - top_y) / (bot_y - top_y)
        bulge = math.sin(t * math.pi)
        rad = 8 + bulge * 2.5
        rad = int(rad)
        for x in range(cx - rad, cx + rad + 1):
            fx = (x - (cx - rad)) / max(1, 2 * rad)
            # round shading across width
            d = abs(fx - 0.38) * 1.6
            idx = int(d * 5)
            idx = max(0, min(5, idx))
            c = body[5 - idx] if idx <= 5 else body[0]
            cv.put(x, y, c)
        # stave seams
        if (y % 1) == 0:
            pass
    # vertical stave seams
    for off in (-6, -2, 2, 6):
        for y in range(top_y + 1, bot_y - 1):
            t = (y - top_y) / (bot_y - top_y)
            rad = int(8 + math.sin(t * math.pi) * 2.5)
            sx = cx + int(off * (rad / 9.0))
            if abs(off) < rad:
                cv.put(sx, y, darken(wood, 0.28))
    # metal bands
    steel = ramp(PAL["steel"], 5)
    for by in (top_y + 2, (top_y + bot_y) // 2 - 1, bot_y - 3):
        t = (by - top_y) / (bot_y - top_y)
        rad = int(8 + math.sin(t * math.pi) * 2.5)
        for x in range(cx - rad, cx + rad + 1):
            fx = (x - (cx - rad)) / max(1, 2 * rad)
            c = steel[3] if fx < 0.4 else (steel[1] if fx > 0.7 else steel[2])
            cv.put(x, by, c)
            cv.put(x, by + 1, darken(steel[1], 0.2))
    # top lid ellipse
    lid = ramp(lighten(wood, 0.1), 5)
    cv.fill_ellipse_shaded(cx, top_y + 1, 8, 3, lid, light=(-0.5, -0.7))
    cv.ellipse(cx, top_y + 1, 8, 3, T)  # noop guard
    cv.put(cx - 3, top_y, lighten(wood, 0.3))
    # rim
    for x in range(cx - 8, cx + 9):
        cv.put(x, top_y - 1, darken(wood, 0.2))
    cv.auto_outline()
    return cv, H - 2


def gen_table():
    W, H = 28, 32
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 13, 4)
    wood = PAL["wood"]
    # top surface (3/4 view): a thick slab
    tx, tw = 2, 24
    ty, th = 10, 6
    # table top face
    grain(cv, tx, ty, tw, 4, lighten(wood, 0.1), seed=9)
    # plank seams on top
    for sx in (tx + 6, tx + 12, tx + 18):
        plank_seam(cv, sx, ty, ty + 3, lighten(wood, 0.1))
    # front edge (thickness)
    cv.rect(tx, ty + 4, tw, 3, darken(wood, 0.25))
    cv.hline(tx, tx + tw - 1, ty + 4, lighten(wood, 0.15))
    cv.hline(tx, tx + tw - 1, ty + 6, darken(wood, 0.45))
    # legs
    leg = ramp(wood, 5)
    for lx in (tx + 2, tx + tw - 4):
        for y in range(ty + 7, H - 3):
            cv.put(lx, y, leg[2])
            cv.put(lx + 1, y, leg[1])
            cv.put(lx - 0, y, leg[3] if y < ty + 12 else leg[2])
    # back legs hint (darker, inset)
    for lx in (tx + 6, tx + tw - 8):
        for y in range(ty + 7, H - 6):
            cv.put(lx, y, darken(wood, 0.35))
    # apron under top
    cv.rect(tx + 1, ty + 7, tw - 2, 2, darken(wood, 0.3))
    cv.auto_outline()
    return cv, H - 2


# ─────────────────────────────────────────────────────────────────────────────
# ANIMATED STRIPS
# ─────────────────────────────────────────────────────────────────────────────

def chest_frame(opened, glow_t=0.0):
    W, H = 24, 24
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 3, 10, 3)
    wood = PAL["wood"]
    x0, bw = 4, 16
    body_y = 12 if not opened else 12
    bh = 9
    # body
    grain(cv, x0, body_y, bw, bh, wood, seed=2)
    cv.frame(x0, body_y, bw, bh, darken(wood, 0.4))
    # gold bands vertical
    gold = ramp(PAL["gold"], 5)
    for gx in (x0 + 3, x0 + bw - 4):
        cv.vline(gx, body_y, body_y + bh - 1, gold[2])
        cv.vline(gx + 1, body_y, body_y + bh - 1, gold[0])
        cv.put(gx, body_y, gold[4])
    cv.hline(x0, x0 + bw - 1, body_y + bh - 2, gold[1])  # bottom band
    # lock
    lk = x0 + bw // 2 - 1
    cv.rect(lk, body_y + 2, 3, 4, gold[3])
    cv.put(lk + 1, body_y + 3, OUTLINE)  # keyhole
    cv.put(lk + 1, body_y + 4, OUTLINE)
    if not opened:
        # curved closed lid
        ly = body_y - 5
        for y in range(6):
            inset = [3, 1, 0, 0, 0, 0][y]
            shade = lighten(wood, 0.2 - y * 0.04)
            cv.hline(x0 + inset, x0 + bw - 1 - inset, ly + y, shade)
        cv.frame(x0, ly, bw, 6, darken(wood, 0.4))
        for gx in (x0 + 3, x0 + bw - 4):
            cv.vline(gx, ly, ly + 5, gold[2])
        # lid front lip
        cv.hline(x0 + 1, x0 + bw - 2, body_y - 1, gold[1])
    else:
        # open lid tilted back
        ly = body_y - 8
        for y in range(5):
            inset = y
            cv.hline(x0 + inset, x0 + bw - 1 - inset, ly + y, darken(wood, 0.1 + y * 0.05))
        cv.frame(x0 + 1, ly, bw - 2, 5, darken(wood, 0.45))
        # interior dark
        cv.rect(x0 + 1, body_y - 3, bw - 2, 4, rgb(28, 20, 14))
        # gold pile glow
        g = glow_t
        glowc = lighten(PAL["gold"], 0.2 + 0.25 * g)
        for i in range(7):
            gx = x0 + 3 + (i * 2) % (bw - 6)
            gy = body_y - 1 - (i % 2)
            cv.put(gx, gy, glowc)
            cv.put(gx + 1, gy, gold[2])
        # coin highlights / sparkle
        cv.put(x0 + 5, body_y - 2, lib.lighten(PAL["flame_hot"], 0.2 * g))
        cv.put(x0 + bw - 6, body_y - 1, lighten(PAL["gold"], 0.5))
        # upward glow haze
        haze = rgb(255, 230, 150, int(70 + 80 * g))
        for gy in range(body_y - 6, body_y):
            a = int((1 - (body_y - gy) / 6.0) * (50 + 60 * g))
            cv.hline(x0 + 4, x0 + bw - 5, gy, rgb(255, 226, 140, a))
    cv.auto_outline()
    return cv


def gen_chest():
    frames = [chest_frame(False), chest_frame(True, glow_t=1.0)]
    W, H = 24, 24
    sheet = Canvas(W * 2, H)
    for i, f in enumerate(frames):
        f.blit(sheet, i * W, 0)
    return sheet, frames, (W, H, 2, H - 3)


def torch_frame(phase):
    W, H = 16, 28
    cv = Canvas(W, H)
    cx = W // 2
    # wall bracket (iron) at lower portion
    iron = ramp(PAL["iron"], 5)
    # bracket arm
    cv.rect(cx - 1, 16, 3, 9, iron[2])
    cv.vline(cx - 1, 16, 24, iron[3])
    cv.vline(cx + 1, 16, 24, iron[0])
    # bracket cup holding torch
    cv.rect(cx - 3, 14, 7, 3, iron[2])
    cv.put(cx - 3, 14, iron[3]); cv.put(cx + 3, 16, iron[0])
    # wall mount plate
    cv.rect(cx - 2, 23, 5, 4, iron[1])
    cv.put(cx - 2, 23, iron[3])
    # torch handle (wood) going up into flame
    wood = ramp(PAL["wood"], 5)
    cv.rect(cx - 1, 10, 3, 6, wood[2])
    cv.vline(cx - 1, 10, 15, wood[3])
    cv.vline(cx + 1, 10, 15, wood[0])
    # charred top
    cv.rect(cx - 1, 9, 3, 1, rgb(40, 30, 30))

    # flame — animated by phase 0..3
    rnd = random.Random(phase * 13 + 1)
    sway = [-1, 0, 1, 0][phase]
    tall = [0, 1, 0, 1][phase]
    fb = cx + sway
    base_y = 9
    flame_dk = PAL["flame_dk"]
    flame = PAL["flame"]
    hot = PAL["flame_hot"]
    # outer flame body
    fh = 7 + tall
    for i, y in enumerate(range(base_y - fh, base_y)):
        prog = i / fh  # 0 top .. 1 bottom
        wid = int(1 + prog * 2.6)
        wob = rnd.choice([0, 0, 1, -1]) if 0.2 < prog < 0.9 else 0
        ccx = fb + wob
        for x in range(ccx - wid, ccx + wid + 1):
            cv.put(x, y, flame_dk)
    # mid flame
    for i, y in enumerate(range(base_y - fh + 1, base_y - 1)):
        prog = i / fh
        wid = int(prog * 2.2)
        ccx = fb + (rnd.choice([0, 1, -1]) if prog > 0.4 else 0)
        for x in range(ccx - wid, ccx + wid + 1):
            cv.put(x, y, flame)
    # hot core
    for i, y in enumerate(range(base_y - fh + 3, base_y - 1)):
        ccx = fb
        cv.put(ccx, y, hot)
        if i % 2 == 0:
            cv.put(ccx, y, lighten(hot, 0.2))
    # spark
    if tall:
        cv.put(fb + sway, base_y - fh - 1, flame)
    # warm glow halo (drawn under, low alpha)
    glow = Canvas(W, H)
    ga = 60 + tall * 18
    glow.ellipse(fb, base_y - fh + 3, 6, 7, rgb(255, 180, 70, ga))
    glow.ellipse(fb, base_y - fh + 3, 4, 5, rgb(255, 210, 110, ga + 20))
    # composite glow beneath flame (so flame stays crisp)
    out = Canvas(W, H)
    for y in range(H):
        for x in range(W):
            gc = glow.get(x, y)
            if gc[3]:
                out.put(x, y, gc)
    cv.auto_outline()
    cv.blit(out, 0, 0)
    return out


def gen_torch():
    frames = [torch_frame(p) for p in range(4)]
    W, H = 16, 28
    sheet = Canvas(W * 4, H)
    for i, f in enumerate(frames):
        f.blit(sheet, i * W, 0)
    return sheet, frames, (W, H, 4, 24)


def chandelier_frame(phase):
    W, H = 32, 24
    cv = Canvas(W, H)
    cx = W // 2
    iron = ramp(PAL["iron"], 5)
    gold = ramp(PAL["gold"], 5)
    # chain to ceiling
    for y in range(0, 6, 2):
        cv.put(cx, y, iron[3])
        cv.put(cx, y + 1, iron[1])
    # central hub
    cv.fill_ellipse_shaded(cx, 8, 3, 2, gold, light=(-0.5, -0.6))
    # arms from hub to ring (drawn first, behind ring)
    ring_y = 13
    for dx in (-11, -6, 0, 6, 11):
        ex = cx + dx
        cv.line(cx, 9, ex, ring_y, gold[1])
    # ring frame: a clean gold band (ellipse outline, 2px front lip)
    rx, ry = 11, 4
    for ang in range(0, 360, 4):
        a = math.radians(ang)
        x = int(round(cx + math.cos(a) * rx))
        y = int(round(ring_y + math.sin(a) * ry))
        # top arc darker (in shadow / facing away), front lip lighter
        if math.sin(a) > 0.25:
            cv.put(x, y, gold[2]); cv.put(x, y + 1, gold[0])  # front lip thickness
        elif math.sin(a) < -0.25:
            cv.put(x, y, gold[3])
        else:
            cv.put(x, y, gold[1])
    # candles around ring
    candle_xs = [cx - 12, cx - 6, cx, cx + 6, cx + 12]
    rnd = random.Random(phase * 17 + 3)
    for ci, ckx in enumerate(candle_xs):
        cky = ring_y - 1
        # candle stub
        cv.vline(ckx, cky - 3, cky, PAL["bone"])
        cv.put(ckx, cky - 3, darken(PAL["bone"], 0.2))
        cv.put(ckx - 0, cky, darken(PAL["bone"], 0.3))
        # cup
        cv.put(ckx, cky + 1, gold[2])
        # flame flicker
        flick = [(0, 0), (0, 1), (-1, 0), (1, 1)][(phase + ci) % 4]
        fx = ckx + flick[0]
        fy = cky - 4 - flick[1]
        cv.put(fx, fy, PAL["flame"])
        cv.put(fx, fy - 1, PAL["flame_dk"])
        cv.put(fx, fy + 1, PAL["flame_hot"])
        cv.put(fx, fy, lighten(PAL["flame_hot"], 0.1))
    # glow halo
    glow = Canvas(W, H)
    ga = 46 + (phase % 2) * 14
    for ckx in candle_xs:
        glow.ellipse(ckx, ring_y - 5, 3, 4, rgb(255, 200, 90, ga))
    out = Canvas(W, H)
    for y in range(H):
        for x in range(W):
            gc = glow.get(x, y)
            if gc[3]:
                out.put(x, y, gc)
    cv.auto_outline()
    cv.blit(out, 0, 0)
    return out


def gen_chandelier():
    frames = [chandelier_frame(p) for p in range(3)]
    W, H = 32, 24
    sheet = Canvas(W * 3, H)
    for i, f in enumerate(frames):
        f.blit(sheet, i * W, 0)
    return sheet, frames, (W, H, 3, 17)


# ─────────────────────────────────────────────────────────────────────────────
# PICKUPS (16x16)
# ─────────────────────────────────────────────────────────────────────────────

def gen_coin():
    W = H = 16
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 6, 2, alpha=80)
    gold = ramp(PAL["gold"], 5)
    cx = 8
    # stack of 3 coins (ellipses)
    for i, cy in enumerate((11, 9, 7)):
        cv.fill_ellipse_shaded(cx, cy, 5, 2, gold, light=(-0.6, -0.6))
        cv.ellipse(cx, cy, 5, 2, T)
        cv.hline(cx - 4, cx + 4, cy + 2, gold[0])  # side edge
    # top coin face detail
    cv.fill_ellipse_shaded(cx, 6, 5, 2, gold, light=(-0.6, -0.7))
    cv.put(cx, 6, gold[1])  # emboss
    cv.put(cx - 1, 6, gold[1]); cv.put(cx + 1, 6, gold[1])
    cv.put(cx - 3, 5, lighten(PAL["gold"], 0.5))  # glint
    # sparkle
    cv.put(cx + 4, 4, rgb(255, 250, 220))
    cv.put(cx + 4, 3, rgb(255, 250, 220, 160))
    cv.put(cx + 5, 4, rgb(255, 250, 220, 160))
    cv.put(cx + 3, 4, rgb(255, 250, 220, 160))
    cv.auto_outline()
    return cv, H - 2


def gen_gem():
    W = H = 16
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 5, 2, alpha=80)
    g = ramp(PAL["gem_blue"], 6)
    cx, cy = 8, 8
    # diamond cut facets
    # top table
    cv.hline(cx - 3, cx + 3, cy - 3, g[4])
    cv.hline(cx - 4, cx + 4, cy - 2, g[3])
    cv.hline(cx - 5, cx + 5, cy - 1, g[3])
    # crown facets
    for y in range(cy, cy + 5):
        wid = 5 - (y - cy)
        for x in range(cx - wid, cx + wid + 1):
            fx = (x - (cx - wid)) / max(1, 2 * wid)
            depth = (y - cy) / 5.0
            if fx < 0.35:
                c = g[4]
            elif fx > 0.65:
                c = g[1]
            else:
                c = g[2]
            c = darken(c, depth * 0.25)
            cv.put(x, y, c)
    # facet lines
    cv.line(cx - 5, cy - 1, cx, cy + 4, darken(PAL["gem_blue"], 0.35))
    cv.line(cx + 5, cy - 1, cx, cy + 4, darken(PAL["gem_blue"], 0.35))
    cv.line(cx, cy - 3, cx, cy + 4, mix(PAL["gem_blue"], rgb(255, 255, 255), 0.2))
    # highlight glint
    cv.put(cx - 2, cy - 2, rgb(240, 252, 255))
    cv.put(cx - 1, cy - 2, rgb(210, 240, 255))
    cv.put(cx - 3, cy, lighten(PAL["gem_blue"], 0.5))
    # sparkle
    cv.put(cx + 4, cy - 4, rgb(255, 255, 255, 200))
    cv.auto_outline()
    return cv, H - 2


def gen_relic():
    W = H = 16
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 5, 2, alpha=85)
    gold = ramp(PAL["gold"], 6)
    cx = 8
    # idol: a stylized seated figure / mask on a base
    # base
    cv.rect(cx - 4, 13, 9, 2, gold[1])
    cv.hline(cx - 4, cx + 4, 13, gold[3])
    cv.hline(cx - 4, cx + 4, 14, gold[0])
    # body trapezoid
    for y in range(8, 13):
        wid = 2 + (y - 8)
        for x in range(cx - wid, cx + wid + 1):
            fx = (x - (cx - wid)) / max(1, 2 * wid)
            c = gold[4] if fx < 0.35 else (gold[1] if fx > 0.7 else gold[3])
            cv.put(x, y, c)
    # head (mask)
    cv.fill_ellipse_shaded(cx, 5, 3, 3, gold, light=(-0.6, -0.6))
    # headdress fan
    cv.hline(cx - 4, cx + 4, 2, gold[2])
    cv.put(cx - 4, 2, gold[1]); cv.put(cx + 4, 2, gold[1])
    cv.put(cx - 3, 1, gold[3]); cv.put(cx + 3, 1, gold[3])
    cv.put(cx, 1, gold[4])
    # face features (gem eyes)
    cv.put(cx - 1, 5, PAL["gem_blue"])
    cv.put(cx + 1, 5, PAL["gem_blue"])
    cv.put(cx, 6, gold[0])  # mouth
    # arms folded
    cv.hline(cx - 3, cx + 3, 10, gold[2])
    cv.put(cx - 3, 10, gold[4])
    # central gem on chest
    cv.put(cx, 11, PAL["gem_red"])
    # glints
    cv.put(cx - 2, 4, rgb(255, 250, 220))
    cv.auto_outline()
    return cv, H - 2


def gen_lootbag():
    W = H = 16
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 6, 2, alpha=85)
    cloth = PAL["leather"]
    cl = ramp(cloth, 5)
    cx = 8
    # bulging sack body
    cv.fill_ellipse_shaded(cx, 10, 6, 5, cl, light=(-0.6, -0.6))
    # bottom flatten + bulges
    cv.fill_ellipse_shaded(cx - 3, 11, 3, 3, cl, light=(-0.6, -0.5))
    cv.fill_ellipse_shaded(cx + 3, 11, 3, 3, cl, light=(-0.5, -0.5))
    # neck cinch
    cv.rect(cx - 2, 4, 5, 3, cl[1])
    cv.hline(cx - 2, cx + 2, 4, cl[3])
    # tie string
    tie = PAL["gold"]
    cv.hline(cx - 3, cx + 3, 6, darken(tie, 0.2))
    cv.hline(cx - 3, cx + 3, 7, tie)
    cv.put(cx - 3, 6, tie); cv.put(cx + 3, 6, tie)
    # gathered top opening
    cv.put(cx - 1, 3, cl[2]); cv.put(cx, 3, cl[3]); cv.put(cx + 1, 3, cl[1])
    cv.put(cx, 2, cl[2])
    # coins spilling at top
    cv.put(cx - 1, 4, PAL["gold"])
    cv.put(cx + 1, 4, lighten(PAL["gold"], 0.2))
    cv.put(cx, 3, PAL["gold"])
    # $ stitch / fold detail
    cv.line(cx - 2, 9, cx + 1, 13, darken(cloth, 0.3))
    cv.put(cx - 3, 9, lighten(cloth, 0.25))  # highlight
    # sparkle
    cv.put(cx + 4, 5, rgb(255, 250, 220, 200))
    cv.auto_outline()
    return cv, H - 2


def gen_key():
    W = H = 16
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 5, 2, alpha=75)
    br = ramp(PAL["bronze"], 5)
    gold = ramp(PAL["gold"], 5)
    # Upright key: ornate ring bow at top, straight shaft, bit/teeth at bottom.
    sx = 7  # shaft column
    # --- bow: a hollow ring at top ---
    bcy = 4
    ring = [(-2, -2), (-1, -3), (0, -3), (1, -3), (2, -2),
            (-3, -1), (3, -1), (-3, 0), (3, 0),
            (-3, 1), (3, 1), (-2, 2), (-1, 3), (0, 3), (1, 3), (2, 2)]
    for dx, dy in ring:
        c = br[3] if dy < 0 else (br[1] if dy > 1 else br[2])
        cv.put(sx + dx, bcy + dy, c)
    # top-left highlight on ring
    cv.put(sx - 1, bcy - 3, gold[4])
    cv.put(sx - 3, bcy - 1, gold[4])
    # gem inset in the ring center
    cv.put(sx, bcy, PAL["gem_blue"])
    cv.put(sx - 1, bcy, lighten(PAL["gem_blue"], 0.4))
    cv.put(sx + 1, bcy + 1, darken(PAL["gem_blue"], 0.3))
    # --- shaft straight down ---
    for y in range(bcy + 4, 13):
        cv.put(sx - 1, y, br[3])
        cv.put(sx, y, br[2])
        cv.put(sx + 1, y, br[1])
    # collar bead
    cv.hline(sx - 2, sx + 2, 9, gold[2])
    cv.put(sx - 2, 9, gold[4]); cv.put(sx + 2, 9, gold[0])
    # --- bit / teeth at bottom (point right) ---
    cv.rect(sx, 13, 3, 1, br[2])      # base of bit
    cv.put(sx + 2, 12, br[3])          # tooth 1 (up)
    cv.put(sx + 1, 14, br[1])          # tooth 2 (down notch)
    cv.put(sx + 3, 13, br[2])          # tooth tip out
    cv.put(sx - 1, 13, br[3])          # left nub highlight
    # glints
    cv.put(sx - 1, bcy - 2, rgb(255, 245, 210))
    cv.put(sx - 1, bcy + 5, lighten(PAL["bronze"], 0.4))
    cv.auto_outline()
    return cv, H - 2


def gen_potion():
    W = H = 16
    cv = Canvas(W, H)
    contact(cv, W // 2, H - 2, 5, 2, alpha=80)
    cx = 8
    glass = rgb(190, 210, 220)
    liq = PAL["gem_red"]
    lr = ramp(liq, 5)
    # round bottle body
    body = ramp(glass, 5)
    cv.fill_ellipse_shaded(cx, 10, 4, 4, body, light=(-0.6, -0.6))
    # liquid fill (lower 2/3)
    for y in range(9, 14):
        for x in range(cx - 4, cx + 5):
            if ((x - cx) / 4.0) ** 2 + ((y - 10) / 4.0) ** 2 <= 1.0:
                fx = (x - (cx - 4)) / 8.0
                c = lr[3] if fx < 0.35 else (lr[1] if fx > 0.7 else lr[2])
                cv.put(x, y, c)
    # surface meniscus
    cv.hline(cx - 3, cx + 3, 8, lighten(liq, 0.25))
    # neck
    cv.rect(cx - 1, 4, 3, 5, body[2])
    cv.vline(cx - 1, 4, 8, body[3])
    cv.vline(cx + 1, 4, 8, body[1])
    # cork
    cv.rect(cx - 1, 2, 3, 2, mix(PAL["leather"], PAL["wood"], 0.4))
    cv.put(cx, 2, lighten(PAL["leather"], 0.2))
    # glass highlight streak
    cv.vline(cx - 2, 8, 12, rgb(255, 255, 255, 120))
    cv.put(cx - 3, 9, rgb(255, 255, 255, 90))
    # shine on liquid
    cv.put(cx - 2, 10, lighten(liq, 0.4))
    # sparkle
    cv.put(cx + 3, 6, rgb(255, 255, 255, 180))
    cv.auto_outline()
    return cv, H - 2


# ─────────────────────────────────────────────────────────────────────────────
# DRIVER
# ─────────────────────────────────────────────────────────────────────────────

REGISTRY = {}


def save_single(name, fn):
    cv, base = fn()
    path = os.path.join(SPR, name + ".png")
    lib.write_png(path, cv.px, cv.w, cv.h)
    save_preview(cv, os.path.join(PRE, name + ".png"), factor=8)
    REGISTRY[name] = (cv.w, cv.h, 1, cv.w, cv.h, base)
    print(f"{name}: {cv.w}x{cv.h} baseline_y={base}")


def save_strip(name, fn):
    sheet, frames, meta = fn()
    fw, fh, nframes, base = meta
    path = os.path.join(SPR, name + ".png")
    lib.write_png(path, sheet.px, sheet.w, sheet.h)
    save_preview(sheet, os.path.join(PRE, name + ".png"), factor=8)
    REGISTRY[name] = (sheet.w, sheet.h, nframes, fw, fh, base)
    print(f"{name}: sheet {sheet.w}x{sheet.h}, {nframes} frames @ {fw}x{fh}, baseline_y={base}")


def main():
    save_single("prop_bookcase", gen_bookcase)
    save_single("prop_weaponrack", gen_weaponrack)
    save_single("prop_crate", gen_crate)
    save_single("prop_trophyshelf", gen_trophyshelf)
    save_single("prop_winerack", gen_winerack)
    save_single("prop_barrel", gen_barrel)
    save_single("prop_table", gen_table)
    save_strip("prop_chest", gen_chest)
    save_strip("prop_torch", gen_torch)
    save_strip("prop_chandelier", gen_chandelier)
    save_single("pickup_coin", gen_coin)
    save_single("pickup_gem", gen_gem)
    save_single("pickup_relic", gen_relic)
    save_single("pickup_lootbag", gen_lootbag)
    save_single("pickup_key", gen_key)
    save_single("pickup_potion", gen_potion)
    write_layout()


def write_layout():
    lines = ["# Props Layout", "",
             "Light from upper-left. Ground-contact baseline is the y-row (within each",
             "frame) where the object's contact shadow sits — anchor mounts so this row",
             "aligns with the floor.", "",
             "| File | Canvas | Frames | Frame size | Baseline y |",
             "|------|--------|--------|------------|-----------|"]
    order = ["prop_bookcase", "prop_weaponrack", "prop_crate", "prop_trophyshelf",
             "prop_winerack", "prop_barrel", "prop_table", "prop_chest",
             "prop_torch", "prop_chandelier", "pickup_coin", "pickup_gem",
             "pickup_relic", "pickup_lootbag", "pickup_key", "pickup_potion"]
    for n in order:
        w, h, nf, fw, fh, base = REGISTRY[n]
        lines.append(f"| sprites/{n}.png | {w}x{h} | {nf} | {fw}x{fh} | {base} |")
    lines += ["",
              "Strips are horizontal; read frames left-to-right.",
              "- prop_chest: frame 0 closed, frame 1 open (gold glow).",
              "- prop_torch: 4-frame flame flicker loop.",
              "- prop_chandelier: 3-frame candle flicker loop.",
              ""]
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "PROPS_LAYOUT.md")
    with open(p, "w") as f:
        f.write("\n".join(lines))
    print("wrote", p)


if __name__ == "__main__":
    main()
