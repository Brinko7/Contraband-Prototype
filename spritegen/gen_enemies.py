import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Canvas, Sheet, PAL, rgb, lighten, darken, mix, ramp, shift_hue_warm, OUTLINE, T

PREV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "previews")
SPRITES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sprites")
os.makedirs(PREV, exist_ok=True)
os.makedirs(SPRITES, exist_ok=True)

# ─────────────────────────────────────────────────────────────────────────────
# Shared helpers
# ─────────────────────────────────────────────────────────────────────────────

# directions: 0 DOWN, 1 LEFT, 2 RIGHT, 3 UP
DOWN, LEFT, RIGHT, UP = 0, 1, 2, 3

def walk_offsets(frame):
    """Return (leg_phase, body_bob) for a 4-frame walk cycle.
    frame 0 = contact, 1 = passing(up), 2 = contact(opposite), 3 = passing(up)."""
    # leg_phase: -1..1 how far front leg is forward
    lp = [0.9, 0.0, -0.9, 0.0][frame]
    bob = [0, -1, 0, -1][frame]
    return lp, bob

def arm_swing(frame):
    return [-1, 0, 1, 0][frame]


def shade_limb(cav, x, y, w, h, cols, vert=True):
    """Fill a rectangle with a left->right (or top->bottom) shading ramp."""
    n = len(cols)
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if vert:
                t = (xx - x) / max(1, w - 1)
            else:
                t = (yy - y) / max(1, h - 1)
            idx = int(t * (n - 1))
            cav.put(xx, yy, cols[idx])


def sphere(cav, cx, cy, rx, ry, cols, light=(-0.55, -0.6)):
    cav.fill_ellipse_shaded(cx, cy, rx, ry, cols, light=light)


def rim_light(cav, x0, y0, x1, y1, col):
    cav.line(x0, y0, x1, y1, col)


# ─────────────────────────────────────────────────────────────────────────────
# HUMANOID base builder.
# Builds one cell (Canvas) given a "spec" dict describing the enemy, the
# direction and frame. Coordinates assume a 32x40 cell, baseline (feet) at y=38.
# ─────────────────────────────────────────────────────────────────────────────

def build_humanoid(spec, direction, frame, cw=32, ch=40):
    c = Canvas(cw, ch)
    cx = cw // 2
    base_y = spec.get("base_y", 38)          # foot baseline
    scale = spec.get("scale", 1.0)
    # vertical sizing relative to scale (bigger enemies stand taller)
    height = int(26 * scale)
    lp, bob = walk_offsets(frame)
    asw = arm_swing(frame)

    sk = spec["skin"]
    sk_r = ramp(sk, 5)
    body = spec["body"]            # torso/armor base
    body_r = ramp(body, 5)
    leg_c = spec.get("legs", darken(body, 0.2))
    leg_r = ramp(leg_c, 5)
    cloth = spec.get("cloth")      # tabard/cape base or None
    cloth_r = ramp(cloth, 5) if cloth else None

    # ── shadow ─────────────────────────────────────────────────────────────
    c.drop_shadow(cx, base_y + 1, int(8 * scale), int(2.6 * scale), 95)

    top = base_y - height          # top of torso block roughly
    head_r = int(4.4 * scale)
    head_cy = top - head_r + 2
    torso_top = head_cy + head_r
    torso_bot = base_y - int(11 * scale)
    torso_h = torso_bot - torso_top
    torso_w = int(11 * scale)

    # ── LEGS (drawn first, behind torso) ─────────────────────────────────────
    leg_top = torso_bot - 1
    leg_h = base_y - leg_top
    legw = max(3, int(3 * scale))
    front_dx = int(round(lp * 2))
    if direction in (LEFT, RIGHT):
        s = -1 if direction == LEFT else 1
        # one leg forward, one back along facing axis
        fx = cx + s * front_dx
        bx = cx - s * front_dx - s * 1
        for (lx, fwd) in [(bx, False), (fx, True)]:
            cols = leg_r if fwd else [darken(cc, 0.18) for cc in leg_r]
            shade_limb(c, lx - legw // 2, leg_top + bob, legw, leg_h - bob, cols)
            # foot
            c.rect(lx - legw // 2 + (s if s > 0 else 0), base_y - 1, legw + 1, 2, darken(leg_c, 0.4))
    else:
        for side in (-1, 1):
            ph = side * front_dx
            lx = cx + side * 2
            ly = leg_top + bob + (1 if (ph > 0) else 0)
            shade_limb(c, lx - legw // 2, ly, legw, base_y - ly, leg_r)
            c.rect(lx - legw // 2, base_y - 1, legw, 2, darken(leg_c, 0.4))

    # ── CAPE (boss) drawn behind torso for UP/SIDE ───────────────────────────
    cape = spec.get("cape")
    if cape and direction != DOWN:
        # custom cape ramp: deep reds only, mild highlight (no pink washout)
        cape_r = [darken(cape, 0.55), darken(cape, 0.32), darken(cape, 0.12),
                  cape, lighten(cape, 0.18)]
        flow = [0, 1, 0, 1][frame]
        cw2 = int(7 * scale)
        for yy in range(torso_top - 1, base_y - 2):
            t = (yy - torso_top) / max(1, (base_y - torso_top))
            ww = int(cw2 * (0.6 + t))
            wob = int(math.sin(t * 3 + flow) * 1.5)
            for xx in range(cx - ww + wob, cx + ww + wob):
                tt = (xx - (cx - ww)) / max(1, 2 * ww)
                # left-lit fold: bright on left edge, dark core toward right
                idx = int(tt * (len(cape_r) - 1))
                col = cape_r[len(cape_r) - 1 - idx]
                # vertical fold lines for cloth motion
                if (xx + int(t * 6)) % 5 == 0:
                    col = darken(col, 0.22)
                c.put(xx, yy, col)

    # ── TORSO ────────────────────────────────────────────────────────────────
    # rounded torso block via shaded ellipse + rect for solidity
    sphere(c, cx, (torso_top + torso_bot) // 2, torso_w // 2 + 1, torso_h // 2 + 1, body_r)
    c.rect(cx - torso_w // 2, torso_top + 1, torso_w, torso_h, body)
    # re-shade torso rect with vertical-ish ramp + AO at bottom
    for yy in range(torso_top + 1, torso_bot):
        for xx in range(cx - torso_w // 2, cx + torso_w // 2 + (torso_w & 1)):
            # left-lit gradient
            tx = (xx - (cx - torso_w // 2)) / max(1, torso_w - 1)
            ty = (yy - torso_top) / max(1, torso_h - 1)
            shade = 0.55 - tx * 0.55 + ty * 0.25
            idx = int((1 - shade) * (len(body_r) - 1) + 0.0)
            idx = max(0, min(len(body_r) - 1, idx))
            c.put(xx, yy, body_r[idx])
    # belt
    c.hline(cx - torso_w // 2, cx + torso_w // 2, torso_bot - 1, darken(leg_c, 0.3))
    bcol = spec.get("belt")
    if bcol:
        c.hline(cx - torso_w // 2, cx + torso_w // 2, torso_bot - 2, bcol)

    # ── TABARD / surcoat (guard, captain) ───────────────────────────────────
    if cloth and not cape:
        tw = int(5 * scale)
        for yy in range(torso_top + 3, base_y - int(8 * scale)):
            t = (yy - (torso_top + 3)) / max(1, (base_y - int(8 * scale)) - (torso_top + 3))
            ww = int(tw * (1 - 0.15 * t))
            for xx in range(cx - ww, cx + ww):
                tx = (xx - (cx - ww)) / max(1, 2 * ww - 1)
                shade = 0.6 - tx * 0.5
                idx = int((1 - shade) * (len(cloth_r) - 1))
                idx = max(0, min(len(cloth_r) - 1, idx))
                c.put(xx, yy, cloth_r[idx])
        # tabard emblem hint
        em = spec.get("emblem")
        if em and direction == DOWN:
            c.put(cx, torso_top + 6, em)
            c.put(cx - 1, torso_top + 7, em); c.put(cx + 1, torso_top + 7, em)
            c.put(cx, torso_top + 8, em)

    # ── SHOULDERS / pauldrons ────────────────────────────────────────────────
    pa = spec.get("pauldron")
    if pa:
        pa_r = ramp(pa, 5)
        for side in (-1, 1):
            px = cx + side * (torso_w // 2 + 1)
            sphere(c, px, torso_top + 2, int(3.2 * scale), int(2.6 * scale), pa_r)

    # ── ARMS ─────────────────────────────────────────────────────────────────
    armw = max(2, int(2.4 * scale))
    arm_top = torso_top + 2
    arm_len = int(9 * scale)
    sk_arm = sk_r
    if direction == DOWN:
        for side in (-1, 1):
            ax = cx + side * (torso_w // 2 + 1)
            ay = arm_top + (asw * side if side < 0 else -asw * side)
            shade_limb(c, ax - armw // 2, arm_top, armw, arm_len, body_r if spec.get("armsleeve") else sk_arm)
            # hand
            c.rect(ax - armw // 2, arm_top + arm_len - 1, armw, 2, sk)
    elif direction == UP:
        for side in (-1, 1):
            ax = cx + side * (torso_w // 2 + 1)
            shade_limb(c, ax - armw // 2, arm_top, armw, arm_len, body_r if spec.get("armsleeve") else sk_arm)
    else:  # side: one near arm visible swinging
        s = -1 if direction == LEFT else 1
        ax = cx + s * 1
        ay = arm_top + asw
        shade_limb(c, ax - armw // 2, ay, armw, arm_len, body_r if spec.get("armsleeve") else sk_arm)
        c.rect(ax - armw // 2, ay + arm_len - 1, armw, 2, sk)

    # ── HEAD ─────────────────────────────────────────────────────────────────
    spec["draw_head"](c, cx, head_cy, head_r, direction, frame, spec, scale)

    # ── WEAPON ─────────────────────────────────────────────────────────────────
    if spec.get("draw_weapon"):
        spec["draw_weapon"](c, cx, torso_top, base_y, direction, frame, spec, scale)

    c.auto_outline()
    return c


# ─────────────────────────────────────────────────────────────────────────────
# HEAD drawers
# ─────────────────────────────────────────────────────────────────────────────

def head_helmet(c, cx, cy, r, direction, frame, spec, scale):
    """Steel/iron helmet with face slit. Used by guard."""
    steel = spec.get("helm", PAL["steel"])
    steel_r = ramp(steel, 5)
    sk = spec["skin"]
    # skin under helm (face)
    if direction == DOWN:
        c.fill_ellipse_shaded(cx, cy + 1, r - 1, r - 1, ramp(sk, 5))
    # helmet dome
    c.fill_ellipse_shaded(cx, cy - 1, r, r, steel_r, light=(-0.6, -0.7))
    # cheek guards
    c.rect(cx - r, cy - 1, 2, r + 1, steel_r[1])
    c.rect(cx + r - 1, cy - 1, 2, r + 1, steel_r[2])
    if direction == DOWN:
        # face slit (dark) with eyes
        c.rect(cx - r + 2, cy, (r - 2) * 2, 2, darken(steel, 0.6))
        c.put(cx - 2, cy, rgb(180, 60, 50))  # eye glint
        c.put(cx + 2, cy, rgb(180, 60, 50))
        # nasal bar
        c.vline(cx, cy - 1, cy + r - 1, steel_r[4])
    elif direction == UP:
        c.fill_ellipse_shaded(cx, cy, r, r, [darken(s, 0.15) for s in steel_r])
    else:
        s = -1 if direction == LEFT else 1
        c.rect(cx - r + 1, cy, 2 * r - 2, 2, darken(steel, 0.55))
        c.put(cx + s * 2, cy, rgb(180, 60, 50))
    # crest/comb
    c.hline(cx - r + 1, cx + r - 1, cy - r, steel_r[4])
    # rim light lower-right
    c.put(cx + r - 1, cy + r - 2, lighten(steel, 0.4))


def head_captain(c, cx, cy, r, direction, frame, spec, scale):
    steel = spec.get("helm", PAL["steel"])
    steel_r = ramp(steel, 5)
    gold = PAL["gold"]; gold_r = ramp(gold, 5)
    c.fill_ellipse_shaded(cx, cy - 1, r, r, steel_r, light=(-0.6, -0.7))
    # gold brow band
    c.hline(cx - r + 1, cx + r - 1, cy + 1, gold_r[3])
    c.hline(cx - r + 1, cx + r - 1, cy + 2, gold_r[1])
    # plume (red) rising from top, sweeps with frame
    plume = PAL["cloth_red"]; pr = ramp(plume, 5)
    sweep = [0, 1, 0, -1][frame]
    for i, yy in enumerate(range(cy - r - 6, cy - r + 1)):
        ww = 2 + (i // 2)
        ox = int((i / 6) * sweep)
        for xx in range(cx - ww + ox, cx + ww + ox):
            tt = (xx - (cx - ww + ox)) / max(1, 2 * ww - 1)
            c.put(xx, yy, pr[1 + int(tt * 3)])
    if direction == DOWN:
        c.rect(cx - r + 2, cy + 3, (r - 2) * 2, 2, darken(steel, 0.6))
        c.put(cx - 2, cy + 3, rgb(200, 70, 50)); c.put(cx + 2, cy + 3, rgb(200, 70, 50))
        c.vline(cx, cy + 1, cy + r - 1, gold_r[3])
    elif direction != UP:
        s = -1 if direction == LEFT else 1
        c.rect(cx - r + 1, cy + 3, 2 * r - 2, 2, darken(steel, 0.55))
        c.put(cx + s * 2, cy + 3, rgb(200, 70, 50))
    c.put(cx + r - 1, cy + r - 2, lighten(steel, 0.45))


def head_boss(c, cx, cy, r, direction, frame, spec, scale):
    blk = spec.get("helm", PAL["cloth_black"])
    blk_r = ramp(blk, 5)
    c.fill_ellipse_shaded(cx, cy - 1, r, r, blk_r, light=(-0.6, -0.7))
    # gold crown trim
    gold = PAL["gold"]; gold_r = ramp(gold, 5)
    c.hline(cx - r + 1, cx + r - 1, cy - 1, gold_r[3])
    # horns
    hc = ramp(PAL["bone"], 5)
    for side in (-1, 1):
        hx = cx + side * (r - 1)
        c.line(hx, cy - r + 1, hx + side * 3, cy - r - 4, hc[3])
        c.line(hx, cy - r + 1, hx + side * 2, cy - r - 4, hc[1])
        c.put(hx + side * 3, cy - r - 5, hc[4])
    # glowing eyes (red)
    if direction == DOWN:
        c.put(cx - 2, cy + 1, rgb(255, 70, 60)); c.put(cx + 2, cy + 1, rgb(255, 70, 60))
        c.put(cx - 2, cy, rgb(255, 150, 120)); c.put(cx + 2, cy, rgb(255, 150, 120))
    elif direction != UP:
        s = -1 if direction == LEFT else 1
        c.put(cx + s * 2, cy + 1, rgb(255, 70, 60))
    c.put(cx + r - 1, cy + r - 2, mix(blk, rgb(140, 60, 70), 0.6))


def head_skeleton(c, cx, cy, r, direction, frame, spec, scale):
    bone = PAL["bone"]; br = ramp(bone, 5)
    c.fill_ellipse_shaded(cx, cy, r, r, br, light=(-0.55, -0.6))
    # jaw
    c.fill_ellipse_shaded(cx, cy + r - 1, int(r * 0.8), int(r * 0.6), [darken(b, 0.1) for b in br])
    if direction == DOWN:
        # eye sockets - hollow with green glow
        for ex in (-2, 2):
            c.disc(cx + ex, cy, 1, rgb(10, 30, 16))
            c.put(cx + ex, cy, rgb(120, 255, 150))
            c.put(cx + ex, cy - 1, rgb(70, 200, 110))
        # nasal
        c.put(cx, cy + 2, darken(bone, 0.5))
        # teeth
        for tx in range(cx - 2, cx + 3):
            c.put(tx, cy + r, br[3] if (tx & 1) else darken(bone, 0.4))
    elif direction != UP:
        s = -1 if direction == LEFT else 1
        c.disc(cx + s * 1, cy, 1, rgb(10, 30, 16))
        c.put(cx + s * 1, cy, rgb(120, 255, 150))
        c.put(cx + s * 2, cy + r, darken(bone, 0.4))
    # cracks
    c.put(cx + 1, cy - r + 1, darken(bone, 0.5))


def head_goblin(c, cx, cy, r, direction, frame, spec, scale):
    sk = spec["skin"]; sr = ramp(sk, 5)
    c.fill_ellipse_shaded(cx, cy, r, r, sr, light=(-0.55, -0.6))
    # big pointed ears
    for side in (-1, 1):
        ex = cx + side * (r - 1)
        c.line(ex, cy, ex + side * 4, cy - 3, sr[2])
        c.line(ex, cy + 1, ex + side * 4, cy - 2, sr[1])
        c.put(ex + side * 4, cy - 3, sr[3])
    if direction == DOWN:
        # angry yellow eyes
        c.put(cx - 2, cy, rgb(240, 210, 60)); c.put(cx + 2, cy, rgb(240, 210, 60))
        c.put(cx - 2, cy - 1, rgb(20, 20, 10)); c.put(cx + 2, cy - 1, rgb(20, 20, 10))
        # snout + fang
        c.put(cx, cy + 2, darken(sk, 0.3))
        c.put(cx - 1, cy + 3, PAL["bone"]); c.put(cx + 1, cy + 3, PAL["bone"])
    elif direction != UP:
        s = -1 if direction == LEFT else 1
        c.put(cx + s * 2, cy, rgb(240, 210, 60))
        c.put(cx + s * 3, cy + 2, darken(sk, 0.3))
        c.put(cx + s * 3, cy + 3, PAL["bone"])
    # hood scrap
    c.put(cx + r - 1, cy + r - 1, lighten(sk, 0.3))


def head_gnoll(c, cx, cy, r, direction, frame, spec, scale):
    fur = spec["skin"]; fr = ramp(fur, 5)
    c.fill_ellipse_shaded(cx, cy, r, r, fr, light=(-0.55, -0.6))
    # hyena ears (rounded, up)
    for side in (-1, 1):
        ex = cx + side * (r - 1)
        c.fill_ellipse_shaded(ex, cy - r + 1, 2, 3, fr, light=(-0.5, -0.6))
    # elongated snout
    if direction == DOWN:
        for i, yy in enumerate(range(cy + 1, cy + r + 3)):
            ww = max(1, 3 - i // 2)
            shade_limb(c, cx - ww, yy, ww * 2, 1, ramp(darken(fur, 0.1), 5))
        # nose
        c.put(cx, cy + r + 2, rgb(20, 16, 18))
        # eyes amber
        c.put(cx - 2, cy, rgb(240, 170, 40)); c.put(cx + 2, cy, rgb(240, 170, 40))
        # teeth/grin
        c.put(cx - 1, cy + r + 1, PAL["bone"]); c.put(cx + 1, cy + r + 1, PAL["bone"])
    elif direction != UP:
        s = -1 if direction == LEFT else 1
        for i, xx in enumerate(range(cx, cx + s * (r + 2), s)):
            ww = max(1, 2 - i // 2)
            shade_limb(c, xx, cy + 1 - ww, 1, ww * 2, ramp(darken(fur, 0.1), 5), vert=False)
        c.put(cx + s * (r + 1), cy + 1, rgb(20, 16, 18))
        c.put(cx + s * 2, cy, rgb(240, 170, 40))
    # mane ridge
    c.put(cx, cy - r, darken(fur, 0.3))
    c.put(cx + r - 1, cy + r - 1, lighten(fur, 0.35))


# ─────────────────────────────────────────────────────────────────────────────
# WEAPON drawers
# ─────────────────────────────────────────────────────────────────────────────

def weap_spear(c, cx, torso_top, base_y, direction, frame, spec, scale):
    wood = PAL["wood"]; steel = PAL["steel"]
    sway = [0, -1, 0, 1][frame]
    if direction == DOWN:
        sx = cx + int(7 * scale)
        c.vline(sx, torso_top - 6, base_y - 4, wood)
        c.vline(sx + 1, torso_top - 6, base_y - 4, darken(wood, 0.3))
        # spearhead
        c.line(sx, torso_top - 6, sx, torso_top - 10, steel)
        c.put(sx, torso_top - 11, lighten(steel, 0.4))
        c.put(sx - 1, torso_top - 8, steel); c.put(sx + 1, torso_top - 8, darken(steel, 0.3))
    elif direction == UP:
        sx = cx - int(7 * scale)
        c.vline(sx, torso_top - 6, base_y - 4, darken(wood, 0.2))
        c.line(sx, torso_top - 6, sx, torso_top - 10, steel)
    else:
        s = -1 if direction == LEFT else 1
        sx = cx + s * int(3 * scale)
        c.vline(sx, torso_top - 7 + sway, base_y - 4, wood)
        c.line(sx, torso_top - 7 + sway, sx, torso_top - 12 + sway, steel)
        c.put(sx, torso_top - 13 + sway, lighten(steel, 0.4))


def weap_sword(c, cx, torso_top, base_y, direction, frame, spec, scale):
    steel = PAL["steel"]; sr = ramp(steel, 5); gold = PAL["gold"]
    if direction == DOWN:
        sx = cx + int(8 * scale)
        # blade
        for i, yy in enumerate(range(torso_top + 2, torso_top + 13)):
            c.put(sx, yy, sr[3]); c.put(sx + 1, yy, sr[1])
        c.put(sx, torso_top + 1, lighten(steel, 0.5))
        # guard + hilt
        c.hline(sx - 1, sx + 2, torso_top + 13, gold)
        c.vline(sx, torso_top + 13, torso_top + 16, PAL["leather"])
    elif direction == UP:
        sx = cx - int(8 * scale)
        for yy in range(torso_top + 2, torso_top + 13):
            c.put(sx, yy, sr[2])
        c.hline(sx - 1, sx + 2, torso_top + 13, gold)
    else:
        s = -1 if direction == LEFT else 1
        sx = cx + s * int(4 * scale)
        lift = [0, -1, -2, -1][frame]
        for yy in range(torso_top + 1 + lift, torso_top + 12 + lift):
            c.put(sx, yy, sr[3]); c.put(sx + s, yy, sr[1])
        c.put(sx, torso_top + lift, lighten(steel, 0.5))
        c.hline(sx - 1, sx + 1, torso_top + 12 + lift, gold)


def weap_cleaver(c, cx, torso_top, base_y, direction, frame, spec, scale):
    iron = PAL["iron"]; ir = ramp(iron, 5); wood = PAL["wood"]
    if direction == DOWN:
        sx = cx + int(8 * scale)
        # broad blade
        c.rect(sx - 1, torso_top + 1, 4, 8, ir[3])
        for yy in range(torso_top + 1, torso_top + 9):
            c.put(sx - 1, yy, ir[4])
        c.rect(sx - 1, torso_top + 1, 4, 1, lighten(iron, 0.4))
        c.vline(sx + 1, torso_top + 9, torso_top + 14, wood)
    elif direction == UP:
        sx = cx - int(8 * scale)
        c.rect(sx - 1, torso_top + 1, 4, 8, ir[2])
        c.vline(sx + 1, torso_top + 9, torso_top + 14, darken(wood, 0.2))
    else:
        s = -1 if direction == LEFT else 1
        sx = cx + s * int(5 * scale)
        lift = [0, -1, -2, -1][frame]
        c.rect(sx - 1, torso_top + 1 + lift, 4, 7, ir[3])
        c.rect(sx - 1, torso_top + 1 + lift, 4, 1, lighten(iron, 0.4))


def weap_rusty(c, cx, torso_top, base_y, direction, frame, spec, scale):
    rust = rgb(120, 78, 56); rr = ramp(rust, 5)
    if direction == DOWN:
        sx = cx + int(8 * scale)
        for yy in range(torso_top + 2, torso_top + 13):
            c.put(sx, yy, rr[3]); c.put(sx + 1, yy, rr[1])
        # chips
        c.put(sx, torso_top + 6, T); c.put(sx, torso_top + 9, darken(rust, 0.4))
        c.put(sx, torso_top + 1, lighten(rust, 0.3))
        c.hline(sx - 1, sx + 2, torso_top + 13, PAL["leather_dk"])
    elif direction == UP:
        sx = cx - int(8 * scale)
        for yy in range(torso_top + 2, torso_top + 13):
            c.put(sx, yy, rr[2])
    else:
        s = -1 if direction == LEFT else 1
        sx = cx + s * int(4 * scale)
        lift = [0, -1, -2, -1][frame]
        for yy in range(torso_top + 1 + lift, torso_top + 11 + lift):
            c.put(sx, yy, rr[3])
        c.put(sx, torso_top + 5 + lift, T)


def weap_dagger(c, cx, torso_top, base_y, direction, frame, spec, scale):
    iron = PAL["steel"]; ir = ramp(iron, 5)
    if direction == DOWN:
        sx = cx + int(7 * scale)
        for yy in range(torso_top + 4, torso_top + 12):
            c.put(sx, yy, ir[3]); c.put(sx + 1, yy, ir[1])
        c.put(sx, torso_top + 3, lighten(iron, 0.5))
        c.put(sx + 1, torso_top + 3, ir[2])
        c.hline(sx - 1, sx + 2, torso_top + 12, PAL["leather"])  # guard
        c.vline(sx, torso_top + 12, torso_top + 14, PAL["leather_dk"])
    elif direction == UP:
        sx = cx - int(7 * scale)
        for yy in range(torso_top + 4, torso_top + 12):
            c.put(sx, yy, ir[2])
        c.hline(sx - 1, sx + 1, torso_top + 12, PAL["leather"])
    else:
        s = -1 if direction == LEFT else 1
        sx = cx + s * int(4 * scale)
        lift = [0, -1, -2, -1][frame]
        for yy in range(torso_top + 3 + lift, torso_top + 11 + lift):
            c.put(sx, yy, ir[3]); c.put(sx + s, yy, ir[1])
        c.put(sx, torso_top + 2 + lift, lighten(iron, 0.5))
        c.hline(sx - 1, sx + 1, torso_top + 11 + lift, PAL["leather"])


# ─────────────────────────────────────────────────────────────────────────────
# Enemy specs
# ─────────────────────────────────────────────────────────────────────────────

def make_specs():
    return {
        "enemy_guard": dict(
            skin=PAL["skin_tan"], body=PAL["steel"], legs=PAL["iron"],
            cloth=PAL["cloth_blue"], helm=PAL["steel"], belt=PAL["leather"],
            pauldron=PAL["steel_dk"], armsleeve=True, emblem=PAL["gold"],
            scale=1.0, base_y=38,
            draw_head=head_helmet, draw_weapon=weap_spear,
        ),
        "enemy_captain": dict(
            skin=PAL["skin_tan"], body=PAL["steel"], legs=PAL["steel_dk"],
            cloth=PAL["cloth_red"], helm=PAL["steel"], belt=PAL["gold_dk"],
            pauldron=PAL["gold"], armsleeve=True, emblem=PAL["gold"],
            scale=1.08, base_y=38,
            draw_head=head_captain, draw_weapon=weap_sword,
        ),
        "enemy_boss": dict(
            skin=PAL["skin_dark"], body=PAL["cloth_black"], legs=darken(PAL["cloth_black"], 0.1),
            cape=PAL["cloth_red"], helm=PAL["cloth_black"], belt=PAL["gold_dk"],
            pauldron=darken(PAL["iron"], 0.2), armsleeve=True,
            scale=1.18, base_y=39,
            draw_head=head_boss, draw_weapon=weap_sword,
        ),
        "enemy_skeleton": dict(
            skin=PAL["bone"], body=darken(PAL["cloth_grey"], 0.25), legs=PAL["bone"],
            cloth=PAL["cloth_grey"], belt=PAL["leather_dk"],
            armsleeve=False, scale=0.98, base_y=38,
            draw_head=head_skeleton, draw_weapon=weap_rusty,
        ),
        "enemy_goblin": dict(
            skin=PAL["skin_green"], body=PAL["leather"], legs=PAL["leather_dk"],
            cloth=None, belt=PAL["leather_dk"], armsleeve=False,
            scale=0.78, base_y=38,
            draw_head=head_goblin, draw_weapon=weap_dagger,
        ),
        "enemy_gnoll": dict(
            skin=rgb(140, 100, 58), body=PAL["leather"], legs=rgb(120, 86, 50),
            cloth=None, belt=PAL["leather_dk"], pauldron=PAL["leather_dk"],
            armsleeve=False, scale=1.12, base_y=38,
            draw_head=head_gnoll, draw_weapon=weap_cleaver,
        ),
    }


# ─────────────────────────────────────────────────────────────────────────────
# HOUND quadruped (32x28)
# ─────────────────────────────────────────────────────────────────────────────

def build_hound(direction, frame, cw=32, ch=28):
    c = Canvas(cw, ch)
    cx = cw // 2
    base_y = 25
    fur = rgb(64, 60, 72)            # dark blue-grey fur
    fr = ramp(fur, 5)
    fur_dk = darken(fur, 0.25)
    c.drop_shadow(cx, base_y + 1, 11, 3, 100)

    lp = [0.0, 1.0, 0.0, -1.0][frame]   # leg phase
    bob = [0, -1, 0, -1][frame]

    if direction in (LEFT, RIGHT):
        s = -1 if direction == LEFT else 1
        # body: elongated horizontal
        bcy = base_y - 8 + bob
        c.fill_ellipse_shaded(cx, bcy, 9, 5, fr, light=(-0.5, -0.6))
        # haunch (rear)
        c.fill_ellipse_shaded(cx - s * 7, bcy, 5, 5, [darken(f, 0.08) for f in fr])
        # chest (front)
        c.fill_ellipse_shaded(cx + s * 6, bcy + 1, 4, 4, fr)
        # neck + head forward
        hx = cx + s * 11
        hy = bcy - 3
        c.fill_ellipse_shaded(hx, hy, 4, 3, fr, light=(-0.5 * s, -0.6))
        # snout
        c.fill_ellipse_shaded(hx + s * 3, hy + 1, 2, 1, [darken(f, 0.1) for f in fr])
        c.put(hx + s * 4, hy + 1, rgb(20, 16, 20))  # nose
        # ears (pointed, alert)
        c.line(hx - s * 1, hy - 3, hx - s * 1, hy - 6, fur_dk)
        c.line(hx + s * 1, hy - 3, hx + s * 2, hy - 6, fur_dk)
        # glowing eye
        c.put(hx + s * 1, hy - 1, rgb(255, 210, 60))
        c.put(hx + s * 1, hy, rgb(255, 240, 160))
        # tail (sweeps)
        tx = cx - s * 9
        tsw = [0, -2, 0, 2][frame]
        c.line(tx, bcy - 1, tx - s * 4, bcy - 4 + tsw, fur_dk)
        c.line(tx, bcy, tx - s * 4, bcy - 3 + tsw, fr[2])
        # legs: 4-leg gallop. front pair + rear pair, opposing phase
        legy = bcy + 4
        front_x = cx + s * 6
        rear_x = cx - s * 6
        # rear legs
        for off, ph in [(0, lp), (2 * s, -lp)]:
            ex = rear_x + off
            sw = int(ph * 3)
            c.line(ex, legy, ex + sw, base_y, fur_dk)
            c.put(ex + sw, base_y, fr[1])
        # front legs
        for off, ph in [(0, -lp), (2 * s, lp)]:
            ex = front_x + off
            sw = int(ph * 3)
            c.line(ex, legy, ex + sw, base_y, fr[2])
            c.put(ex + sw, base_y, fr[1])
        # back highlight
        c.line(cx - 5, bcy - 4, cx + 4, bcy - 4, lighten(fur, 0.3))

    elif direction == DOWN:  # facing viewer (front)
        bcy = base_y - 7 + bob
        c.fill_ellipse_shaded(cx, bcy, 6, 6, fr, light=(-0.5, -0.6))
        # head
        c.fill_ellipse_shaded(cx, bcy - 5, 4, 4, fr, light=(-0.5, -0.6))
        # ears
        for side in (-1, 1):
            c.line(cx + side * 3, bcy - 8, cx + side * 4, bcy - 11, fur_dk)
            c.line(cx + side * 2, bcy - 8, cx + side * 3, bcy - 11, fr[2])
        # snout + nose
        c.fill_ellipse_shaded(cx, bcy - 3, 2, 2, [darken(f, 0.1) for f in fr])
        c.put(cx, bcy - 2, rgb(20, 16, 20))
        # glowing eyes
        c.put(cx - 2, bcy - 5, rgb(255, 210, 60)); c.put(cx + 2, bcy - 5, rgb(255, 210, 60))
        c.put(cx - 2, bcy - 6, rgb(255, 240, 160)); c.put(cx + 2, bcy - 6, rgb(255, 240, 160))
        # 4 legs splayed, front pair animates
        sw = int(lp * 2)
        for side in (-1, 1):
            c.vline(cx + side * 4, bcy + 4, base_y, fr[2])
            c.vline(cx + side * 2, bcy + 4 + (sw if side < 0 else -sw), base_y, fur_dk)
        c.put(cx - 4, bcy - 1, lighten(fur, 0.3))

    else:  # UP, back view
        bcy = base_y - 7 + bob
        c.fill_ellipse_shaded(cx, bcy, 6, 6, [darken(f, 0.06) for f in fr], light=(-0.5, -0.6))
        c.fill_ellipse_shaded(cx, bcy - 5, 4, 4, [darken(f, 0.06) for f in fr])
        for side in (-1, 1):
            c.line(cx + side * 3, bcy - 8, cx + side * 4, bcy - 11, fur_dk)
        # tail up
        tsw = [0, -1, 0, 1][frame]
        c.line(cx, bcy + 4, cx + tsw, bcy + 7, fur_dk)
        sw = int(lp * 2)
        for side in (-1, 1):
            c.vline(cx + side * 4, bcy + 4, base_y, fr[1])
            c.vline(cx + side * 2, bcy + 4 + (sw if side < 0 else -sw), base_y, fur_dk)
        c.line(cx - 4, bcy - 2, cx + 3, bcy - 2, lighten(fur, 0.25))

    c.auto_outline()
    return c


# ─────────────────────────────────────────────────────────────────────────────
# Build all sheets
# ─────────────────────────────────────────────────────────────────────────────

def build_humanoid_sheet(name, spec):
    sh = Sheet(4, 4, 32, 40)
    for row, direction in enumerate([DOWN, LEFT, RIGHT, UP]):
        for col in range(4):
            cell = build_humanoid(spec, direction, col)
            cell.blit(sh.canvas, col * 32, row * 40)
    path = os.path.join(SPRITES, name + ".png")
    lib.write_png(path, sh.canvas.px, sh.W, sh.H)
    lib.save_preview(sh.canvas, os.path.join(PREV, name + "_prev.png"), factor=6)
    return path


def build_hound_sheet():
    sh = Sheet(4, 4, 32, 28)
    for row, direction in enumerate([DOWN, LEFT, RIGHT, UP]):
        for col in range(4):
            build_hound(direction, col).blit(sh.canvas, col * 32, row * 28)
    path = os.path.join(SPRITES, "enemy_hound.png")
    lib.write_png(path, sh.canvas.px, sh.W, sh.H)
    lib.save_preview(sh.canvas, os.path.join(PREV, "enemy_hound_prev.png"), factor=6)
    return path


def main():
    specs = make_specs()
    for name, spec in specs.items():
        p = build_humanoid_sheet(name, spec)
        print("wrote", p)
    p = build_hound_sheet()
    print("wrote", p)


if __name__ == "__main__":
    main()
