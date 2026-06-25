import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import Canvas, PAL, rgb, lighten, darken, mix, ramp, save_preview, write_png

# ──────────────────────────────────────────────────────────────────────────────
# Seamless value noise.
# Lookups are done on coordinates taken MODULO the tile size, so any noise
# field sampled this way wraps perfectly across tile edges (and across
# neighbouring copies of the same tile). This is the backbone of seamless floors.
# ──────────────────────────────────────────────────────────────────────────────

def _hash(x, y, seed):
    h = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    h ^= h >> 16
    return h

def vnoise(x, y, size, seed):
    """Smooth, tileable value noise in [0,1) over a `size`x`size` torus."""
    # integer lattice value, bilinearly smoothed, wrapped at `size`
    def lat(ix, iy):
        return (_hash(ix % size, iy % size, seed) & 0xFFFF) / 65535.0
    x0, y0 = int(math.floor(x)), int(math.floor(y))
    fx, fy = x - x0, y - y0
    # smoothstep
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    v00 = lat(x0, y0);     v10 = lat(x0 + 1, y0)
    v01 = lat(x0, y0 + 1); v11 = lat(x0 + 1, y0 + 1)
    a = v00 + (v10 - v00) * sx
    b = v01 + (v11 - v01) * sx
    return a + (b - a) * sy

def tileable_grain(cx, cy, size, seed, scale=4.0):
    """Two octaves of tileable noise centered ~0.5, value -1..1-ish."""
    n = vnoise(cx / size * scale, cy / size * scale, int(size / size * scale + 0.5) or scale, seed)
    # second octave at double frequency, also wrapping
    s2 = scale * 2
    n2 = vnoise(cx / size * s2, cy / size * s2, int(s2) or 1, seed + 99)
    return (n - 0.5) * 1.4 + (n2 - 0.5) * 0.6

# Simpler integer-lattice tileable noise keyed directly per-pixel (cheap speckle)
def speckle(x, y, size, seed):
    return (_hash(x % size, y % size, seed) & 0xFF) / 255.0


# ──────────────────────────────────────────────────────────────────────────────
# FLOOR builders
# Each floor is 16x16 and tiles seamlessly. We base everything on a 5-tone ramp.
# Mortar/flagstone joints are placed so the seam lines fall consistently across
# tiles (joints at fixed local coords -> repeats cleanly).
# ──────────────────────────────────────────────────────────────────────────────

S = 16  # tile size

def floor_base(theme, vshift=0.0):
    """A plain flagstone floor with seamless grain. vshift nudges overall value."""
    base = theme['floor']
    r = ramp(base, 5)               # [dk2, dk1, base, lt1, lt2]
    grout = theme['grout']
    c = Canvas(S, S)
    seed = theme['seed']
    for y in range(S):
        for x in range(S):
            # tileable grain
            g = tileable_grain(x + 0.5, y + 0.5, S, seed, scale=4.0)
            sp = (speckle(x, y, S, seed + 7) - 0.5) * 0.30
            v = g + sp + vshift
            if v < -0.55:   col = r[0]
            elif v < -0.18: col = r[1]
            elif v <  0.18: col = r[2]
            elif v <  0.55: col = r[3]
            else:           col = r[4]
            c.put(x, y, col)
    # Flagstone joints: a cross of mortar lines. Placed at the tile boundary band
    # so when tiled, two half-joints meet to form one continuous groove.
    # Vertical joint along x=0 (wraps with x=15 of the neighbour) and a mid joint.
    _flagstone_joints(c, theme, base)
    return c

def _joint_px(c, x, y, theme, base, depth=0.55, light=False):
    if not c.inb(x, y):
        return
    if light:
        c.put(x, y, lighten(base, 0.22))
    else:
        c.put(x, y, mix(c.get(x, y), theme['grout'], depth))

def _flagstone_joints(c, theme, base):
    # A 2x2 block of stones per tile -> joints at the tile edges (x=0,y=0) and
    # the centre (x=8,y=8). Edge joints are HALF-width so neighbours complete them.
    grout = theme['grout']
    # top edge groove (y=0) + catch light just below
    for x in range(S):
        _joint_px(c, x, 0, theme, base, 0.42)
    for x in range(S):
        c.put(x, 1, lighten(c.get(x, 1), 0.08))   # subtle catch-light below joint
    # left edge groove (x=0)
    for y in range(S):
        _joint_px(c, 0, y, theme, base, 0.42)
    for y in range(S):
        c.put(1, y, lighten(c.get(1, y), 0.08))
    # centre cross at x=8 / y=8 (groove with a soft catch-light on the lit side)
    for y in range(S):
        _joint_px(c, 8, y, theme, base, 0.45)
        c.put(9, y, lighten(c.get(9, y), 0.08))
    for x in range(S):
        _joint_px(c, x, 8, theme, base, 0.45)
        c.put(x, 9, lighten(c.get(x, 9), 0.08))
    # corner shadow pooling (bottom-right of each sub-stone reads slightly deeper)
    for (sx, sy) in ((7, 7), (15, 7), (7, 15), (15, 15)):
        c.put(sx, sy, darken(c.get(sx, sy), 0.12))


def floor_cracked(theme):
    c = floor_base(theme, vshift=-0.03)
    base = theme['floor']
    crk = darken(theme['grout'], 0.1)
    # A branching crack that ENTERS and EXITS the tile at matching edge points so
    # it continues across copies. Enter left edge mid, exit right edge, plus a
    # vertical branch that enters top and exits bottom at the same x -> wraps.
    pts = [(0, 6), (3, 7), (6, 6), (9, 8), (12, 7), (15, 8)]
    for i in range(len(pts) - 1):
        c.line(pts[i][0], pts[i][1], pts[i+1][0], pts[i+1][1], crk)
    # vertical wrap branch at x=11 from top(0) to bottom(15)
    vpts = [(11, 0), (10, 4), (12, 8), (11, 12), (11, 15)]
    for i in range(len(vpts) - 1):
        c.line(vpts[i][0], vpts[i][1], vpts[i+1][0], vpts[i+1][1], crk)
    # tiny highlight on upper lip of crack
    for (x, y) in pts:
        c.put(x, y - 1, lighten(c.get(x, y - 1), 0.12))
    return c


def floor_mossy(theme):
    c = floor_base(theme, vshift=-0.02)
    moss = rgb(86, 120, 64)
    moss_dk = rgb(58, 86, 44)
    moss_lt = rgb(120, 150, 88)
    seed = theme['seed'] + 31
    # moss grows in the joints / corners; tileable patch noise keeps it wrapping
    for y in range(S):
        for x in range(S):
            m = vnoise(x / S * 3.0, y / S * 3.0, 3, seed)
            # bias only toward the centre joints where damp collects (keep patchy)
            jointbias = 0.0
            if x in (0, 8) or y in (0, 8):
                jointbias = 0.08
            if m + jointbias > 0.78:
                sp = speckle(x, y, S, seed + 3)
                col = moss_lt if sp > 0.72 else (moss if sp > 0.3 else moss_dk)
                # keep moss slightly transparent so floor texture shows through
                c.put(x, y, mix(c.get(x, y), col, 0.78))
    return c


def floor_inlay(theme):
    """A subtle arcane diamond/rune inlay centred in the tile. Brightest on
    obsidian (glowing veins). Tiles because it sits fully inside and the floor
    field around it wraps."""
    c = floor_base(theme, vshift=0.0)
    glow = theme['inlay']
    glow_core = lighten(glow, 0.35)
    cx, cy = 8, 8
    # diamond outline
    dpts = [(8, 2), (14, 8), (8, 14), (2, 8)]
    for i in range(4):
        a = dpts[i]; b = dpts[(i + 1) % 4]
        c.line(a[0], a[1], b[0], b[1], glow)
    # inner rune: a small vertical bar + cross-tick (calm, readable)
    c.vline(8, 5, 11, glow_core)
    c.hline(6, 10, 8, glow)
    c.put(8, 8, glow_core)
    # faint inner diamond glow fill (dithered) — strongest on obsidian
    strength = theme.get('inlay_glow', 0.0)
    if strength > 0:
        for y in range(4, 13):
            for x in range(4, 13):
                if abs(x - cx) + abs(y - cy) <= 5:
                    if (x + y) & 1:
                        c.put(x, y, mix(c.get(x, y), glow, 0.18 * strength))
    return c


def floor_glint(theme):
    """plain-ish floor with a small specular accent glint (a flake of mineral).
    Kept calm so it doesn't read as an item."""
    c = floor_base(theme, vshift=0.02)
    base = theme['floor']
    # a couple of tiny highlight flecks; positioned away from edges so tiling
    # never doubles them up at a seam
    flecks = [(5, 5), (11, 10), (6, 12)]
    for (x, y) in flecks:
        c.put(x, y, lighten(base, 0.55))
        c.put(x + 1, y, lighten(base, 0.28))
        c.put(x, y + 1, lighten(base, 0.20))
    return c


# ──────────────────────────────────────────────────────────────────────────────
# WALL CAP — the flat lit top surface of a wall (16x16). Reads as the top of a
# stone block lit from upper-left. Tiles horizontally with copies of itself.
# ──────────────────────────────────────────────────────────────────────────────

def wall_cap(theme):
    base = theme['wall']
    r = ramp(base, 5)
    c = Canvas(S, S)
    seed = theme['seed'] + 200
    for y in range(S):
        for x in range(S):
            g = tileable_grain(x + 0.5, y + 0.5, S, seed, scale=3.0)
            v = g
            if v < -0.4:   col = r[1]
            elif v < 0.2:  col = r[2]
            else:          col = r[3]
            c.put(x, y, col)
    # top-left catch light, bottom-right core shadow -> reads as a raised cap
    for x in range(S):
        c.put(x, 0, lighten(base, 0.42))
        c.put(x, 1, lighten(base, 0.20))
    for y in range(S):
        c.put(0, y, lighten(base, 0.34))
        c.put(1, y, lighten(base, 0.16))
    for x in range(S):
        c.put(x, S - 1, darken(base, 0.42))
        c.put(x, S - 2, darken(base, 0.22))
    for y in range(S):
        c.put(S - 1, y, darken(base, 0.38))
        c.put(S - 2, y, darken(base, 0.18))
    # restore corners cleanly
    c.put(0, 0, lighten(base, 0.5))
    c.put(S - 1, S - 1, darken(base, 0.5))
    return c


# ──────────────────────────────────────────────────────────────────────────────
# WALL FACE — tall hanging brick face, 16 wide x 48 tall. Horizontal brick
# courses with running-bond offset, mortar lines, per-brick value variation,
# top-edge catch-light, bottom darkening. Tiles horizontally.
# ──────────────────────────────────────────────────────────────────────────────

FW, FH = 16, 48
COURSE = 6   # brick course height in px
BRICKW = 8   # nominal brick width

def wall_face(theme):
    base = theme['wall']
    mortar = darken(theme['grout'], 0.08)
    mortar_lt = lighten(mortar, 0.18)
    c = Canvas(FW, FH)
    seed = theme['seed'] + 300
    # fill background with mortar first
    for y in range(FH):
        for x in range(FW):
            c.put(x, y, mortar)
    course = 0
    y = 0
    while y < FH:
        ch = COURSE
        # running-bond: alternate horizontal offset each course
        off = (BRICKW // 2) if (course & 1) else 0
        # walk bricks across the row, wrapping so left/right edges meet
        bx = -off
        while bx < FW:
            bw = BRICKW
            # per-brick value variation (deterministic, wraps via modulo course)
            bseed = _hash((bx % FW), course, seed)
            tone = ((bseed & 0xFF) / 255.0 - 0.5) * 0.30
            bcol = mix(base, lighten(base, 0.5) if tone > 0 else darken(base, 0.5), abs(tone))
            # depth gradient: bricks get darker toward the bottom of the face
            depthf = y / FH
            bcol = darken(bcol, depthf * 0.30)
            # draw the brick body inside mortar (leave 1px mortar gap below/right)
            for yy in range(y, min(y + ch - 1, FH)):
                for xx in range(bx, bx + bw - 1):
                    px = xx % FW
                    # mild within-brick grain
                    gg = tileable_grain(px + 0.5, yy + 0.5, FW, seed + course, scale=3.0)
                    cc = bcol
                    if gg > 0.45:   cc = lighten(bcol, 0.10)
                    elif gg < -0.45: cc = darken(bcol, 0.10)
                    c.put(px, yy, cc)
            # top catch-light on each brick's top edge
            for xx in range(bx, bx + bw - 1):
                px = xx % FW
                c.put(px, y, lighten(bcol, 0.30))
            # left bevel highlight
            c.put(bx % FW, min(y + 1, FH - 1), lighten(bcol, 0.18))
            # bottom-right ambient occlusion within brick
            yyb = min(y + ch - 2, FH - 1)
            for xx in range(bx, bx + bw - 1):
                c.put(xx % FW, yyb, darken(c.get(xx % FW, yyb), 0.14))
            bx += bw
        course += 1
        y += ch
    # top edge of the whole face: strong catch-light (it meets the cap)
    for x in range(FW):
        c.put(x, 0, lighten(base, 0.48))
    # bottom darkening (the face recedes into floor shadow)
    for x in range(FW):
        c.put(x, FH - 1, darken(theme['grout'], 0.25))
        c.put(x, FH - 2, darken(base, 0.55))
        c.put(x, FH - 3, darken(base, 0.40))
    # mortar catch-light: a faint lit pixel on the upper side of horizontal joints
    for course_y in range(COURSE, FH, COURSE):
        for x in range(FW):
            if c.get(x, course_y)[0:3] == mortar[0:3]:
                pass
    # arcane vein option (obsidian)
    if theme.get('face_vein'):
        glow = theme['inlay']
        vpts = [(3, 0), (5, 8), (4, 18), (7, 28), (5, 38), (6, 47)]
        for i in range(len(vpts) - 1):
            c.line(vpts[i][0], vpts[i][1], vpts[i+1][0], vpts[i+1][1], mix(base, glow, 0.5))
        for (x, y) in vpts:
            c.put(x, y, glow)
    return c


# ──────────────────────────────────────────────────────────────────────────────
# Extra pieces: floor->wall base-shadow strip (16x16) & corner cap (16x16)
# ──────────────────────────────────────────────────────────────────────────────

def base_shadow(theme):
    """A 16x16 strip: transparent except a soft gradient shadow along the TOP,
    meant to be drawn on the floor cell directly south of a wall face so the
    wall casts onto the floor. Tiles horizontally."""
    c = Canvas(S, S)
    for y in range(S):
        a = max(0, 150 - y * 22)   # fade downward
        if a <= 0:
            break
        for x in range(S):
            c.put(x, y, (0, 0, 0, a))
    return c

def corner_cap(theme):
    """A 16x16 wall-cap corner variant: lit on two outer edges (top + left),
    for the upper-left exposed corner of a wall block."""
    c = wall_cap(theme)
    base = theme['wall']
    # extra rounding highlight at the top-left corner
    c.put(0, 0, lighten(base, 0.6))
    c.put(1, 0, lighten(base, 0.4))
    c.put(0, 1, lighten(base, 0.4))
    return c


# ──────────────────────────────────────────────────────────────────────────────
# THEME DEFINITIONS
# ──────────────────────────────────────────────────────────────────────────────

THEMES = {
    'sandstone': {
        'floor': PAL['sand'],   'wall': PAL['sand'],
        'grout': PAL['grout'],  'seed': 1001,
        'inlay': rgb(210, 180, 110), 'inlay_glow': 0.0,
        'face_vein': False,
    },
    'slate': {
        'floor': PAL['slate'],  'wall': PAL['slate'],
        'grout': PAL['slate_dk'], 'seed': 2002,
        'inlay': rgb(120, 170, 210), 'inlay_glow': 0.4,
        'face_vein': False,
    },
    'obsidian': {
        'floor': PAL['obsidian'], 'wall': PAL['obsidian'],
        'grout': PAL['obsidian_dk'], 'seed': 3003,
        'inlay': rgb(150, 110, 230), 'inlay_glow': 1.0,
        'face_vein': True,
    },
}


# ──────────────────────────────────────────────────────────────────────────────
# SHEET ASSEMBLY
# Layout (per theme):
#   Top band row (y=0..15): 8 cells of 16x16, x = col*16
#     col0 floor_plain_a, col1 floor_plain_b, col2 cracked, col3 mossy,
#     col4 inlay, col5 glint, col6 wall_cap, col7 corner_cap
#   Second band (y=16..31): col0 base_shadow strip (16x16)
#   Face region: x=0..15, y=32..79  -> wall face 16x48
# Sheet size: 128 wide x 80 tall.
# ──────────────────────────────────────────────────────────────────────────────

SHEET_W, SHEET_H = 128, 80

def build_floor_set(theme):
    return [
        ('floor_plain_a', floor_base(theme, vshift=0.04)),
        ('floor_plain_b', floor_base(theme, vshift=-0.05)),
        ('floor_cracked', floor_cracked(theme)),
        ('floor_mossy',   floor_mossy(theme)),
        ('floor_inlay',   floor_inlay(theme)),
        ('floor_glint',   floor_glint(theme)),
    ]

def build_sheet(name, theme):
    sheet = Canvas(SHEET_W, SHEET_H, lib.T)
    floors = build_floor_set(theme)
    rects = {}
    for i, (label, cell) in enumerate(floors):
        cell.blit(sheet, i * S, 0)
        rects[label] = (i * S, 0, S, S)
    cap = wall_cap(theme)
    cap.blit(sheet, 6 * S, 0); rects['wall_cap'] = (6 * S, 0, S, S)
    ccap = corner_cap(theme)
    ccap.blit(sheet, 7 * S, 0); rects['corner_cap'] = (7 * S, 0, S, S)
    bsh = base_shadow(theme)
    bsh.blit(sheet, 0, S); rects['base_shadow'] = (0, S, S, S)
    face = wall_face(theme)
    face.blit(sheet, 0, 2 * S); rects['wall_face'] = (0, 2 * S, FW, FH)
    write_png(f"sprites/tiles_{name}.png", sheet.px, sheet.w, sheet.h)
    return sheet, rects, floors, cap, ccap, face


# ──────────────────────────────────────────────────────────────────────────────
# PREVIEWS
# ──────────────────────────────────────────────────────────────────────────────

def tile_3x3(cell):
    out = Canvas(cell.w * 3, cell.h * 3)
    for ty in range(3):
        for tx in range(3):
            cell.blit(out, tx * cell.w, ty * cell.h)
    return out

def assemble_wall_mockup(theme, floors, cap, face):
    """Cap row on top, face hanging below, floor beneath the face overhang.
    Width = 3 cells; shows caps tiling and faces tiling."""
    w = S * 3
    h = S + FH + S   # cap + face + a strip of floor below
    out = Canvas(w, h, rgb(20, 18, 26))
    floor = floors[0][1]
    # floor everywhere first (under everything)
    for ty in range(h // S + 1):
        for tx in range(3):
            floor.blit(out, tx * S, ty * S)
    # caps on top row, faces hanging from row 1 (faces overwrite the floor below)
    for tx in range(3):
        cap.blit(out, tx * S, 0)
    for tx in range(3):
        face.blit(out, tx * S, S)
    return out

def make_previews():
    for name, theme in THEMES.items():
        sheet, rects, floors, cap, ccap, face = build_sheet(name, theme)
        save_preview(sheet, f"spritegen/previews/sheet_{name}.png", factor=6)
        # 3x3 tile tests for each floor variant
        for label, cell in floors:
            save_preview(tile_3x3(cell), f"spritegen/previews/tile3x3_{name}_{label}.png", factor=5, checker=False)
        # wall mockup
        mock = assemble_wall_mockup(theme, floors, cap, face)
        save_preview(mock, f"spritegen/previews/wallmock_{name}.png", factor=6, checker=False)
    print("done")

if __name__ == '__main__':
    make_previews()
