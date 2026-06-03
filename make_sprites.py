"""
SNES-quality pixel art sprite generator — Secret of Mana style.
Pure stdlib (struct + zlib).

Outputs:
  sprites/player_sheet.png   16×24px, 8 cols × 12 rows
  sprites/tileset.png        16×16px, 8 cols × 6 rows
"""
import struct, zlib, os

os.makedirs("sprites", exist_ok=True)

# ── PNG writer ────────────────────────────────────────────────────────────────

def _chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

def write_png(path, pixels, w, h):
    raw = b""
    for y in range(h):
        raw += b"\x00"
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            raw += bytes([r, g, b, a])
    sig  = b"\x89PNG\r\n\x1a\n"
    ihdr = _chunk(b"IHDR", struct.pack(">II", w, h) + bytes([8, 6, 0, 0, 0]))
    idat = _chunk(b"IDAT", zlib.compress(raw, 9))
    iend = _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(sig + ihdr + idat + iend)

T  = (0, 0, 0, 0)
OL = (8, 6, 4, 255)      # universal dark outline

def blank(w, h, col=T):
    return [col] * (w * h)

def put(px, w, x, y, col):
    if 0 <= x < w and 0 <= y < len(px) // w:
        px[y * w + x] = col

def fill(px, w, x1, y1, x2, y2, col):
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            put(px, w, x, y, col)

def hline(px, w, x1, x2, y, col):
    for x in range(x1, x2 + 1):
        put(px, w, x, y, col)

def vline(px, w, x, y1, y2, col):
    for y in range(y1, y2 + 1):
        put(px, w, x, y, col)

def outline_shape(px, w, h):
    """Add 1-pixel OL outline around all non-transparent pixels."""
    snap = px[:]
    for y in range(h):
        for x in range(w):
            if snap[y * w + x][3] > 0:
                for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]:
                    nx, ny = x+dx, y+dy
                    if 0 <= nx < w and 0 <= ny < h and snap[ny*w+nx][3] == 0:
                        px[ny*w+nx] = OL


# ─────────────────────────────────────────────────────────────────────────────
# TILESET  (16×16 tiles, 8 cols × 6 rows)
# ─────────────────────────────────────────────────────────────────────────────

# Zone palettes: 0=grout, 1=shadow, 2=dark, 3=mid, 4=light, 5=hilight, cap, wall
ZONE_PALS = {
    "vault": {
        "grout": ( 8,  4, 14, 255), "shadow": (18, 10, 30, 255),
        "dark":  (30, 20, 50, 255), "mid":    (46, 34, 74, 255),
        "light": (64, 50, 98, 255), "hilit":  (86, 70,126, 255),
        "cap":   (72, 58,106, 255), "caphi":  (96, 80,136, 255),
        "mort":  ( 8,  4, 14, 255), "brick":  (38, 28, 62, 255),
        "bklt":  (56, 44, 86, 255), "bkdk":   (22, 14, 38, 255),
    },
    "barracks": {
        "grout": ( 6, 10,  6, 255), "shadow": (14, 22, 12, 255),
        "dark":  (24, 38, 20, 255), "mid":    (38, 58, 32, 255),
        "light": (54, 80, 46, 255), "hilit":  (72,104, 62, 255),
        "cap":   (62, 88, 52, 255), "caphi":  (82,112, 70, 255),
        "mort":  ( 6, 10,  6, 255), "brick":  (32, 50, 26, 255),
        "bklt":  (48, 72, 40, 255), "bkdk":   (18, 30, 14, 255),
    },
    "entry": {
        "grout": (14, 10,  6, 255), "shadow": (28, 20, 12, 255),
        "dark":  (46, 34, 18, 255), "mid":    (66, 50, 28, 255),
        "light": (88, 70, 42, 255), "hilit":  (114, 92, 58, 255),
        "cap":   (96, 76, 48, 255), "caphi":  (122, 98, 64, 255),
        "mort":  (14, 10,  6, 255), "brick":  (54, 40, 22, 255),
        "bklt":  (78, 60, 34, 255), "bkdk":   (32, 24, 12, 255),
    },
    "generic": {
        "grout": ( 8,  8,  8, 255), "shadow": (18, 18, 18, 255),
        "dark":  (30, 30, 30, 255), "mid":    (46, 46, 46, 255),
        "light": (64, 64, 64, 255), "hilit":  (84, 84, 84, 255),
        "cap":   (72, 72, 72, 255), "caphi":  (96, 96, 96, 255),
        "mort":  ( 8,  8,  8, 255), "brick":  (38, 38, 38, 255),
        "bklt":  (56, 56, 56, 255), "bkdk":   (22, 22, 22, 255),
    },
}
ZONE_NAMES = ["vault", "barracks", "entry", "generic"]


def make_floor_tile(pal):
    """16×16 stone-flag floor: 2×2 stones, each 7×7 with 1-px grout."""
    px  = blank(16, 16, pal["grout"])
    G   = pal["grout"]
    shd = [pal["shadow"], pal["dark"], pal["mid"], pal["light"], pal["hilit"]]
    # Stone A shading (rows top-left lit): 7×7 ramp
    def stone(ox, oy, flip=False):
        ramp = [
            [4,4,3,3,2,1,1],
            [4,4,3,2,2,1,0],
            [4,3,3,2,1,1,0],
            [3,3,2,2,1,0,0],
            [3,2,2,1,1,0,0],
            [2,2,1,1,0,0,0],
            [1,1,0,0,0,0,0],
        ]
        if flip:
            ramp = [row[::-1] for row in ramp[::-1]]
        for sy in range(7):
            for sx in range(7):
                put(px, 16, ox + sx, oy + sy, shd[ramp[sy][sx]])
    stone(1, 1, False)   # top-left
    stone(9, 1, True)    # top-right (inverted for visual variety)
    stone(1, 9, True)    # bottom-left
    stone(9, 9, False)   # bottom-right
    return px


def make_wall_tile(pal):
    """16×16 wall: 3-row lit cap + brick body with offset mortar."""
    px   = blank(16, 16, pal["mort"])
    mort = pal["mort"]
    # Top cap (rows 0-2) — lit from above
    hline(px, 16, 0, 15, 0, pal["caphi"])
    hline(px, 16, 0, 15, 1, pal["cap"])
    hline(px, 16, 0, 15, 2, pal["cap"])
    # Brick courses (rows 3-15): horizontal mortar every 4 rows, offset per course
    course = 0
    for r in range(3, 16):
        if (r - 3) % 4 == 0:
            hline(px, 16, 0, 15, r, mort)  # mortar row
            course += 1
        else:
            off = (course % 2) * 8
            for x in range(16):
                bx = (x - off) % 8
                if bx == 0:
                    c = mort
                elif bx == 1:
                    c = pal["bklt"]
                elif bx <= 5:
                    c = pal["brick"]
                else:
                    c = pal["bkdk"]
                put(px, 16, x, r, c)
    return px


def make_wall_cap(pal):
    """16×16 top-face cap tile (appears above a wall, lit from above)."""
    px = blank(16, 16, pal["cap"])
    hline(px, 16, 0, 15, 0, pal["caphi"])
    hline(px, 16, 0, 15, 1, pal["caphi"])
    hline(px, 16, 0, 15, 2, pal["cap"])
    for r in range(3, 16):
        hline(px, 16, 0, 15, r, pal["mid"] if r % 4 < 2 else pal["dark"])
    return px


def make_shadow_edge():
    """16×16 gradient shadow strip for room edges."""
    px = blank(16, 16)
    for y in range(16):
        a = int(200 * (y / 15.0))
        hline(px, 16, 0, 15, y, (0, 0, 0, a))
    return px


# Prop tiles ──────────────────────────────────────────────────────────────────

def _tile_map(rows16, pal):
    px = []
    for row in rows16:
        for ch in row:
            px.append(pal.get(ch, T))
    return px

def make_crate():
    O=(10,6,2,255); W=(118,82,38,255); L=(152,108,54,255); H=(178,130,68,255)
    D=(76,50,22,255); S=(46,28,10,255); k=(140,120,70,255)
    rows = [
        "OOOOOOOOOOOOOOOO",
        "OLLLLLLLLLLLLLHO",
        "OLFLLLLLLLLLFLO",  # 15 chars - needs fixing
        "OLFLWWWWWWWFLHO",
        "OLFLWWKWWWWFLHO",
        "OLWWWWKWWWWWWHO",
        "OLFLWWWWWWWFLHO",
        "OLOOOOOOOOOOOLO",
        "OLFLWWWWWWWFLHO",
        "OLWWWWWWWWWWWHO",
        "OLFLWWWWWWWFLHO",
        "OLFLLLLLLLLFLLO",
        "OLHDDDDDDDDDHLO",
        "OLDDDDDDDDDDDSO",
        "OSSSSSSSSSSSSSO",
        "OOOOOOOOOOOOOOOO",
    ]
    # Fix row 2: must be 16 chars
    rows[2]  = "OLFLLLLLLLLFLHO"  # 15...
    # Just hand-craft all rows carefully to be exactly 16 chars:
    rows = [
        "OOOOOOOOOOOOOOOO",  # 16
        "OLLLLLLLLLLLLLHO",  # 16
        "OLHLLLLLLLLLHLLO",  # 16  <- H=highlight top-left corner
        "OLHLWWWWWWLHLHO",   # 15, needs 1 more
        "OLHLWWWWWWLHLHO",
        "OLWWWWKWWWWWWHO",
        "OLHLWWWWWWLHLHO",
        "OLOOOOOOOOOOOHO",
        "OLHLWWWWWWLHLHO",
        "OLWWWWWWWWWWWHO",
        "OLHLWWWWWWLHLHO",
        "OLFLLLLLLLLFLHO",
        "OLHDDDDDDDDDHLO",
        "OLDDDDDDDDDDDSO",
        "OSSSSSSSSSSSSSO",
        "OOOOOOOOOOOOOOOO",
    ]
    # Ugh, let me build it properly with direct pixel placement
    px = blank(16, 16, O)
    # Face
    fill(px, 16, 1, 1, 14, 14, W)
    # Top highlight
    fill(px, 16, 1, 1, 14,  2, L)
    put(px, 16, 1, 1, H); put(px, 16, 2, 1, H)
    # Cross brace
    hline(px, 16, 1, 14, 7, D)
    vline(px, 16, 7, 1, 14, D)
    # Corners of each quadrant (highlight/shadow)
    fill(px, 16, 1, 1, 6, 1, L)    # top brace highlight
    fill(px, 16, 8, 1, 14, 1, L)
    # Bottom/right shadow
    fill(px, 16, 1, 13, 14, 14, S)
    fill(px, 16, 14, 1, 14, 14, D)
    # Brackets (decorative metal strips at corners)
    for bx, by in [(1,1),(8,1),(1,8),(8,8)]:
        put(px, 16, bx, by, k); put(px, 16, bx+1, by, k)
        put(px, 16, bx, by+1, k)
    return px


def make_barrel():
    O=(10,6,2,255); W=(104,68,28,255); L=(140,96,44,255); D=(64,40,14,255)
    H=(164,120,58,255); IR=(104,90,64,255); IH=(136,120,90,255)
    px = blank(16, 16, T)
    # Oval body rows
    widths = [0,0,0,6,7,7,7,7,7,7,7,7,6,0,0,0]
    for y, hw in enumerate(widths):
        if hw == 0: continue
        x0 = 8 - hw
        fill(px, 16, x0, y, 15-x0, y, W)
        put(px, 16, x0, y, D)    # left shadow edge
        put(px, 16, 15-x0, y, D) # right shadow edge
        if y < 4: put(px, 16, x0+1, y, L)  # top highlight
    # Iron hoops
    for r in [3, 7, 11]:
        for x in range(3, 13):
            put(px, 16, x, r, IR)
        put(px, 16, 4, r, IH); put(px, 16, 5, r, IH)  # hoop highlight
    # Top highlight
    hline(px, 16, 4, 11, 4, H)
    outline_shape(px, 16, 16)
    return px


def make_gold_pile():
    O=(80,55,8,255); G=(215,168,35,255); L=(248,210,75,255); H=(255,238,130,255); S=(145,108,16,255)
    px = blank(16, 16, T)
    coins = [(4,9),(7,8),(10,9),(5,11),(9,11),(7,13),(3,12),(11,12),(6,7),(10,7)]
    for cx, cy in coins:
        fill(px, 16, cx-1, cy, cx+1, cy, G)
        fill(px, 16, cx-1, cy-1, cx+1, cy-1, G)
        put(px, 16, cx, cy-1, L)      # top highlight
        put(px, 16, cx-1, cy, S)      # left shadow
        put(px, 16, cx+1, cy, S)      # right shadow
    # A few sparkle highlights
    for sx, sy in [(6,7),(10,9),(7,12)]:
        put(px, 16, sx, sy-1, H)
    outline_shape(px, 16, 16)
    return px


def make_torch(lit):
    O=(10,8,4,255); W=(92,60,22,255); WL=(122,84,36,255); IR=(88,76,56,255); IH=(118,104,78,255)
    F1=(255,210,50,255); F2=(255,140,25,255); F3=(210,60,12,255); FC=(255,250,210,255)
    C=(52,44,34,255)
    px = blank(16, 16, T)
    # Stick
    vline(px, 16, 7, 4, 15, W)
    vline(px, 16, 8, 4, 15, WL)
    # Bracket
    fill(px, 16, 5, 9, 10, 10, IR)
    put(px, 16, 5, 9, IH); put(px, 16, 6, 9, IH)
    if lit:
        # Flame
        fill(px, 16, 6, 2, 9, 4, F2)
        fill(px, 16, 7, 1, 8, 3, F1)
        put(px, 16, 7, 0, FC); put(px, 16, 8, 0, FC)
        put(px, 16, 7, 1, FC)
        fill(px, 16, 5, 3, 10, 5, F3)
        # Glow halo
        for hx, hy in [(5,1),(10,1),(4,3),(11,3),(4,5),(11,5)]:
            put(px, 16, hx, hy, (255,180,40,60))
    else:
        fill(px, 16, 6, 1, 9, 4, C)
    outline_shape(px, 16, 16)
    return px


def make_stairs(pal):
    px = blank(16, 16, pal["grout"])
    steps = [(0,14,1,pal["hilit"]),(2,12,3,pal["light"]),(4,10,5,pal["mid"]),(6,8,7,pal["dark"])]
    for x0, x1, w_step, c in steps:
        fill(px, 16, x0, x0, 15-x0, 15-x0, c)
        hline(px, 16, x0, 15-x0, x0, pal["hilit"] if x0 == 0 else c)
    # Simpler: draw as descending strips
    for i in range(8):
        x = i * 2
        y = i * 2
        shade_idx = min(i, 4)
        shades = [pal["hilit"],pal["hilit"],pal["light"],pal["light"],pal["mid"],pal["mid"],pal["dark"],pal["dark"]]
        hline(px, 16, x, 15, y, shades[i])
        hline(px, 16, x, 15, y+1, shades[min(i+1,7)])
    return px


# ── Build tileset ─────────────────────────────────────────────────────────────
TCOLS, TROWS, TW = 8, 6, 16
ts = blank(TCOLS * TW, TROWS * TW)

def paint_tile(col, row, tile_px, tw=16):
    ox, oy = col * tw, row * tw
    for y in range(tw):
        for x in range(tw):
            ts[(oy + y) * (TCOLS * tw) + (ox + x)] = tile_px[y * tw + x]

for z, zn in enumerate(ZONE_NAMES):
    paint_tile(z, 0, make_floor_tile(ZONE_PALS[zn]))
    paint_tile(z, 1, make_wall_tile(ZONE_PALS[zn]))
    paint_tile(z, 2, make_wall_cap(ZONE_PALS[zn]))

paint_tile(0, 3, make_crate())
paint_tile(1, 3, make_barrel())
paint_tile(2, 3, make_gold_pile())
paint_tile(3, 3, make_stairs(ZONE_PALS["vault"]))
paint_tile(4, 3, make_shadow_edge())
paint_tile(0, 4, make_torch(False))
paint_tile(1, 4, make_torch(True))

TSW, TSH = TCOLS * TW, TROWS * TW
write_png("sprites/tileset.png", ts, TSW, TSH)
print(f"Wrote sprites/tileset.png  ({TSW}×{TSH})")


# ─────────────────────────────────────────────────────────────────────────────
# PLAYER SPRITES  — SNES quality, 16×24 px per frame
# 8 cols (DOWN×2, LEFT×2, RIGHT×2, UP×2) × 12 rows (3 classes × 4 races)
# ─────────────────────────────────────────────────────────────────────────────

FW, FH = 16, 24

# ── Shared constants ──────────────────────────────────────────────────────────
MOUTH_D  = (140,  80,  55, 255)
MOUTH_L  = (200, 120,  90, 255)
TOOTH_C  = (230, 220, 200, 255)
BOOT_S   = ( 24,  16,   8, 255)
BOOT_M   = ( 50,  36,  18, 255)
BOOT_L   = ( 78,  58,  30, 255)
BOOT_H   = (108,  84,  46, 255)
LEG_S    = ( 32,  22,  12, 255)
LEG_M    = ( 56,  42,  24, 255)
LEG_H    = ( 82,  64,  38, 255)
BELT_S   = ( 38,  24,  10, 255)
BELT_M   = ( 66,  44,  18, 255)
BELT_H   = ( 98,  68,  28, 255)
BUCKLE   = (185, 150,  50, 255)
IRON_L   = (195, 192, 185, 255)
IRON_M   = (148, 144, 138, 255)
IRON_S   = ( 96,  92,  88, 255)

# ── Race palettes ─────────────────────────────────────────────────────────────
# skin: [shadow, dark, mid, light, hilit]
# hair: [shadow, dark, mid, light]
# eye:  main colour
# accent: special feature colour (horns / beard / ear / bare-foot)

RACE = {
    "HALFLING": {
        "skin": [(72,44,22,255),(112,74,40,255),(158,112,68,255),(202,158,108,255),(232,196,152,255)],
        "hair": [(58,34,12,255),(102,64,24,255),(154,104,46,255),(196,152, 82,255)],
        "eye":  (52, 32, 14, 255),
        "acc":  (198,158,110,255),   # bare-foot skin
    },
    "TIEFLING": {
        "skin": [(88,18,18,255),(132,38,38,255),(178,68,68,255),(212,110,110,255),(238,158,158,255)],
        "hair": [(18, 8,38,255),(36,18,68,255),(60,32,102,255),(90,56,140,255)],
        "eye":  (230,180,  0, 255),  # glowing gold
        "acc":  (80, 22, 22, 255),   # dark horn
    },
    "WOOD_ELF": {
        "skin": [(58,68,34,255),(96,112,58,255),(140,162,98,255),(186,208,148,255),(220,238,190,255)],
        "hair": [(18,44,10,255),(36,78,18,255),(62,118,32,255),(96,158,56,255)],
        "eye":  (30, 130, 50, 255),  # forest green
        "acc":  (186,208,148,255),   # ear (same as skin hilit)
    },
    "DWARF": {
        "skin": [(58,36,18,255),(96,62,32,255),(138, 96,56,255),(180,136,92,255),(214,176,130,255)],
        "hair": [(52,30,10,255),(96,58,20,255),(148, 96,38,255),(190,142,72,255)],
        "eye":  (48,  80, 148, 255),  # steel blue
        "acc":  (158,106, 46, 255),   # beard/brow
    },
}

# ── Class palettes ────────────────────────────────────────────────────────────
# cloak: [shadow, dark, mid, light, hilit]
# tunic: [shadow, mid, light]
# trim:  accent stripe/buckle/button colour

CLASS_PAL = {
    "CUTPURSE": {
        "cloak": [(32,20, 6,255),(60,38,14,255),(96,64,26,255),(136, 96,46,255),(172,130,70,255)],
        "tunic": [(96,68,34,255),(140,104,58,255),(184,148,96,255)],
        "trim":  (188,148, 58,255),
    },
    "SHADOWDANCER": {
        "cloak": [(14, 6,32,255),(28,12,56,255),(52,26,90,255),(80,52,132,255),(118,86,178,255)],
        "tunic": [(20,12,30,255),(38,22,54,255),(60,38,80,255)],
        "trim":  (145,100,220,255),
    },
    "ASSASSIN": {
        "cloak": [(16, 6, 6,255),(32,10,10,255),(54,16,16,255),(82,26,26,255),(118,42,42,255)],
        "tunic": [(22, 8, 8,255),(42,16,16,255),(68,26,26,255)],
        "trim":  (168, 60, 60,255),
    },
}

# ── Helper: clamp colour channel ─────────────────────────────────────────────
def _c(r,g,b,a=255): return (min(255,max(0,r)),min(255,max(0,g)),min(255,max(0,b)),a)
def _bright(col, amt):
    return _c(col[0]+amt, col[1]+amt, col[2]+amt)

# ── Head drawing ──────────────────────────────────────────────────────────────

def _head_front(px, sk, hr, ey, race):
    """16×9 head block, top-left at (3,1). DOWN-facing."""
    s0,s1,s2,s3,s4 = sk
    h0,h1,h2,h3 = hr
    # ── Hair ──
    fill(px, FW, 4, 1, 11, 2, h2)        # hair top band
    hline(px, FW, 4, 11, 1, h3)          # top highlight
    fill(px, FW, 3, 2, 3, 7, h1)         # left fringe
    fill(px, FW, 12, 2, 12, 7, h1)       # right fringe
    fill(px, FW, 4, 2, 5, 3, h3)         # left highlight tuft
    # ── Face ──
    fill(px, FW, 4, 3, 11, 8, s2)        # base face
    fill(px, FW, 4, 3, 8, 3, s3)         # forehead highlight
    fill(px, FW, 4, 7, 11, 8, s0)        # jaw shadow
    vline(px, FW, 11, 3, 7, s1)          # right-face shadow
    # ── Eyes ──
    put(px, FW, 5, 5, ey); put(px, FW, 6, 5, ey)    # left eye
    put(px, FW, 9, 5, ey); put(px, FW, 10, 5, ey)   # right eye
    put(px, FW, 5, 4, s4); put(px, FW, 9, 4, s4)    # brow highlight
    put(px, FW, 6, 4, h0); put(px, FW, 10, 4, h0)   # eyebrow
    # ── Nose ──
    put(px, FW, 7, 6, s1); put(px, FW, 8, 6, s1)
    # ── Mouth ──
    put(px, FW, 6, 7, MOUTH_D); put(px, FW, 7, 7, MOUTH_L)
    put(px, FW, 8, 7, MOUTH_L); put(px, FW, 9, 7, MOUTH_D)
    # ── Chin ──
    fill(px, FW, 5, 8, 10, 8, s1)
    # ── Ears ──
    put(px, FW, 3, 5, s2); put(px, FW, 12, 5, s2)

def _head_side(px, sk, hr, ey, race, right):
    """Profile head. right=True → facing right."""
    s0,s1,s2,s3,s4 = sk
    h0,h1,h2,h3 = hr
    if right:
        fx, bx = 10, 4   # face side x, back-of-head x
    else:
        fx, bx = 5, 11
    cx0 = min(fx,bx); cx1 = max(fx,bx)
    # Hair (back and top)
    fill(px, FW, cx0, 2, cx1, 3, h2)
    hline(px, FW, cx0, cx1, 2, h3)
    vline(px, FW, bx, 2, 7, h1)
    vline(px, FW, bx-(1 if right else -1), 3, 7, h0)
    # Face
    fill(px, FW, cx0, 3, cx1, 8, s2)
    fill(px, FW, cx0, 3, cx0+3, 4, s3)
    vline(px, FW, cx1, 3, 8, s1)
    fill(px, FW, cx0, 7, cx1, 8, s0)
    # Eye (facing side only)
    ey_x = fx - (1 if right else -1)
    put(px, FW, ey_x, 5, ey); put(px, FW, ey_x-(1 if right else -1), 5, ey)
    put(px, FW, ey_x, 4, h0)   # eyebrow
    # Nose (tip pointing forward)
    nose_x = fx + (1 if right else -1)
    put(px, FW, nose_x, 6, s1)
    # Mouth
    put(px, FW, nose_x, 7, MOUTH_D)
    put(px, FW, nose_x - (1 if right else -1), 7, MOUTH_L)
    # Ear on visible side
    put(px, FW, bx + (1 if right else -1), 5, s2)

def _head_back(px, sk, hr):
    """Back of head (UP-facing)."""
    s0,s1,s2,s3,s4 = sk
    h0,h1,h2,h3 = hr
    fill(px, FW, 4, 1, 11, 7, h1)
    hline(px, FW, 4, 11, 1, h3)
    hline(px, FW, 4, 11, 2, h2)
    hline(px, FW, 4, 11, 7, h0)
    vline(px, FW, 3, 2, 7, h0)
    vline(px, FW, 12, 2, 7, h0)
    # Nape skin
    fill(px, FW, 6, 7, 9, 8, s2)
    hline(px, FW, 6, 9, 7, s3)

# ── Body drawing ──────────────────────────────────────────────────────────────

def _body_front(px, cl, walk):
    c0,c1,c2,c3,c4 = cl["cloak"]
    t0,t1,t2 = cl["tunic"]
    tr = cl["trim"]
    # Neck
    fill(px, FW, 7, 8, 8, 9, (140,100,60,255))
    # Collar / hood bottom
    fill(px, FW, 4, 9, 11, 9, c3)
    hline(px, FW, 5, 10, 9, c4)
    # Shoulders (x 2-13)
    fill(px, FW, 2, 10, 13, 11, c2)
    hline(px, FW, 2, 13, 10, c3)
    put(px, FW, 2, 10, c1); put(px, FW, 13, 10, c1)
    # Chest
    fill(px, FW, 3, 11, 12, 14, c2)
    vline(px, FW, 3, 11, 14, c1)
    vline(px, FW, 12, 11, 14, c1)
    # Tunic opening (V)
    fill(px, FW, 6, 10, 9, 14, t1)
    put(px, FW, 6, 10, t2); put(px, FW, 9, 10, t2)
    vline(px, FW, 5, 11, 14, t0)
    vline(px, FW, 10, 11, 14, t0)
    # Trim line on chest
    vline(px, FW, 4, 11, 13, tr)
    vline(px, FW, 11, 11, 13, tr)
    # Belt
    fill(px, FW, 3, 14, 12, 14, BELT_H)
    fill(px, FW, 3, 15, 12, 15, BELT_M)
    fill(px, FW, 7, 14, 8, 15, BUCKLE)
    put(px, FW, 3, 14, BELT_S); put(px, FW, 12, 14, BELT_S)
    # Lower body (hip flare)
    fill(px, FW, 3, 16, 12, 18, c1)
    fill(px, FW, 4, 16, 11, 17, c2)
    vline(px, FW, 5, 16, 18, c0)
    vline(px, FW, 10, 16, 18, c0)
    hline(px, FW, 4, 11, 18, c0)
    # Walk sway
    if walk:
        put(px, FW, 3, 17, c2); put(px, FW, 12, 17, c0)
    # Legs
    l0 = 19 + (1 if walk else 0)
    r0 = 19 + (0 if walk else 1)
    fill(px, FW, 4, 19, 6, l0+1, LEG_M)
    fill(px, FW, 9, 19, 11, r0+1, LEG_M)
    put(px, FW, 4, 19, LEG_H); put(px, FW, 9, 19, LEG_H)
    # Boots
    fill(px, FW, 4, l0+1, 6, 22, BOOT_M)
    fill(px, FW, 9, r0+1, 11, 22, BOOT_M)
    hline(px, FW, 4, 6, l0+1, BOOT_L)
    hline(px, FW, 9, 11, r0+1, BOOT_L)
    hline(px, FW, 3, 7, 22, BOOT_H)    # left boot toe
    hline(px, FW, 8, 12, 22, BOOT_H)   # right boot toe

def _body_side(px, cl, right, walk):
    c0,c1,c2,c3,c4 = cl["cloak"]
    t0,t1,t2 = cl["tunic"]
    tr = cl["trim"]
    if right:
        x0, x1 = 4, 11   # body spans x4-x11, facing right
    else:
        x0, x1 = 4, 11   # same span, just mirrored drawing
    # Neck
    nx = 7 if not right else 8
    fill(px, FW, nx, 8, nx+1, 9, (140,100,60,255))
    # Collar
    fill(px, FW, x0, 9, x1, 9, c3)
    # Shoulder
    fill(px, FW, x0, 10, x1, 10, c3)
    fill(px, FW, x0, 11, x1, 13, c2)
    vline(px, FW, x0, 10, 13, c1)
    vline(px, FW, x1, 10, 13, c1)
    # Tunic peek at front edge
    tx = x0+1 if right else x1-1
    vline(px, FW, tx, 10, 13, t1)
    put(px, FW, tx, 10, t2)
    # Trim
    vline(px, FW, tx+1 if right else tx-1, 11, 13, tr)
    # Belt
    fill(px, FW, x0, 14, x1, 14, BELT_H)
    fill(px, FW, x0, 15, x1, 15, BELT_M)
    bk_x = x0+2 if right else x1-2
    fill(px, FW, bk_x, 14, bk_x+1, 15, BUCKLE)
    # Lower body
    fill(px, FW, x0, 16, x1, 18, c1)
    fill(px, FW, x0+1, 16, x1-1, 17, c2)
    # Trailing edge billow
    if right:
        fill(px, FW, x1, 16, x1+1, 18, c0)
    else:
        fill(px, FW, x0-1, 16, x0, 18, c0)
    # Legs (profile — front and back)
    if right:
        f_x, b_x = 9, 6
    else:
        f_x, b_x = 6, 9
    if walk:
        f_x, b_x = b_x, f_x
    # Back leg (darker)
    fill(px, FW, b_x, 19, b_x+1, 21, LEG_S)
    fill(px, FW, b_x, 21, b_x+2, 22, BOOT_S)
    # Front leg
    fill(px, FW, f_x, 19, f_x+1, 21, LEG_M)
    put(px, FW, f_x, 19, LEG_H)
    fill(px, FW, f_x, 21, f_x+2, 22, BOOT_M)
    put(px, FW, f_x, 21, BOOT_L)
    put(px, FW, f_x+1, 22, BOOT_H)  # toe

def _body_back(px, cl, walk):
    c0,c1,c2,c3,c4 = cl["cloak"]
    tr = cl["trim"]
    # Hood back
    fill(px, FW, 4, 9, 11, 9, c1)
    fill(px, FW, 5, 9, 10, 9, c2)
    # Back of cloak — wider, spans x2-x13
    fill(px, FW, 2, 10, 13, 18, c2)
    hline(px, FW, 2, 13, 10, c3)   # shoulder top highlight
    vline(px, FW, 2, 10, 18, c1)
    vline(px, FW, 13, 10, 18, c1)
    # Spine detail (vertical highlight)
    vline(px, FW, 7, 11, 17, c3)
    vline(px, FW, 8, 11, 17, c3)
    # Trim lines on back
    vline(px, FW, 4, 10, 17, tr)
    vline(px, FW, 11, 10, 17, tr)
    # Belt (back)
    fill(px, FW, 2, 14, 13, 15, BELT_M)
    hline(px, FW, 2, 13, 14, BELT_H)
    # Cloak folds
    hline(px, FW, 3, 12, 13, c1)
    hline(px, FW, 3, 12, 16, c1)
    # Hem
    fill(px, FW, 3, 18, 12, 18, c1)
    fill(px, FW, 4, 19, 11, 19, c0)
    # Legs
    l0 = 20 + (1 if walk else 0)
    r0 = 20 + (0 if walk else 1)
    fill(px, FW, 4, 20, 6, l0, LEG_M)
    fill(px, FW, 9, 20, 11, r0, LEG_M)
    fill(px, FW, 4, l0, 7, 22, BOOT_M)
    fill(px, FW, 8, r0, 12, 22, BOOT_M)
    hline(px, FW, 4, 7, l0, BOOT_L)
    hline(px, FW, 8, 12, r0, BOOT_L)

# ── Race feature overlays ─────────────────────────────────────────────────────

def _race_features(px, race, facing, walk):
    pal = RACE[race]
    sk  = pal["skin"]
    hr  = pal["hair"]
    acc = pal["acc"]

    if race == "HALFLING":
        # Extra hair poof above head
        fill(px, FW, 5, 0, 10, 1, hr[2])
        hline(px, FW, 5, 10, 0, hr[3])
        put(px, FW, 5, 0, hr[1]); put(px, FW, 10, 0, hr[1])
        # Rounder wider face: widen face 1px each side
        if facing == "DOWN":
            for y in range(3, 8):
                if px[y*FW+4][3] > 0: px[y*FW+3] = px[y*FW+4]
                if px[y*FW+11][3] > 0: px[y*FW+12] = px[y*FW+11]
        # Bare feet (replace boots with skin)
        toe = _bright(acc, 20)
        for y in range(20, 23):
            for x in range(FW):
                c = px[y*FW+x]
                if c[3] > 0 and c in (BOOT_M, BOOT_L, BOOT_H, BOOT_S,
                                       (BOOT_M[0],BOOT_M[1],BOOT_M[2],255)):
                    px[y*FW+x] = toe if y == 22 else acc

    elif race == "TIEFLING":
        horn  = acc
        horn2 = _bright(acc, 35)
        tail  = _c(acc[0]+30, acc[1]+10, acc[2]+10)
        if facing == "DOWN":
            # Two curved horns above head
            put(px, FW, 5, 0, horn2); put(px, FW, 4, 0, horn)
            put(px, FW, 4, 1, horn);  put(px, FW, 5, 1, horn2)
            put(px, FW, 10, 0, horn2); put(px, FW, 11, 0, horn)
            put(px, FW, 11, 1, horn);  put(px, FW, 10, 1, horn2)
        elif facing == "LEFT":
            put(px, FW, 4, 0, horn2); put(px, FW, 3, 0, horn)
            put(px, FW, 4, 1, horn);  put(px, FW, 5, 1, horn2)
            # Tail tip visible behind
            put(px, FW, 13, 17, tail); put(px, FW, 14, 18, tail)
        elif facing == "RIGHT":
            put(px, FW, 11, 0, horn2); put(px, FW, 12, 0, horn)
            put(px, FW, 11, 1, horn);  put(px, FW, 10, 1, horn2)
            put(px, FW, 2, 17, tail); put(px, FW, 1, 18, tail)
        elif facing == "UP":
            put(px, FW, 5, 0, horn2); put(px, FW, 4, 0, horn)
            put(px, FW, 4, 1, horn)
            put(px, FW, 10, 0, horn2); put(px, FW, 11, 0, horn)
            put(px, FW, 11, 1, horn)
        # Glowing eye whites
        ey = pal["eye"]
        glow = _c(ey[0], ey[1], ey[2], 160)
        if facing == "DOWN":
            for dx in [-1,0,1]:
                for dy in [-1,0,1]:
                    for ex in [5,9]:
                        nx,ny = ex+dx, 5+dy
                        if 0<=nx<FW and 0<=ny<FH and px[ny*FW+nx][3]==0:
                            px[ny*FW+nx] = glow

    elif race == "WOOD_ELF":
        ear = acc
        ear_d = _c(acc[0]-30, acc[1]-28, acc[2]-20)
        # Pointed ears
        if facing == "DOWN":
            put(px, FW, 2, 3, ear); put(px, FW, 1, 2, ear_d)
            put(px, FW, 13, 3, ear); put(px, FW, 14, 2, ear_d)
        elif facing == "LEFT":
            put(px, FW, 2, 3, ear); put(px, FW, 1, 2, ear_d)
            put(px, FW, 2, 4, ear)
        elif facing == "RIGHT":
            put(px, FW, 13, 3, ear); put(px, FW, 14, 2, ear_d)
            put(px, FW, 13, 4, ear)
        # Slightly taller — shift legs down 1px (body stays, just extend legs)
        for y in range(22, 23):
            for x in range(FW):
                px[(y+1)*FW+x] = px[y*FW+x] if y+1 < FH else px[y*FW+x]

    elif race == "DWARF":
        beard = acc
        beard_hi = _bright(acc, 30)
        # Wider stocky body: extend shoulders
        for y in range(10, 19):
            if px[y*FW+2][3] > 0 and px[y*FW+1][3] == 0:
                px[y*FW+1] = px[y*FW+2]
            if px[y*FW+13][3] > 0 and px[y*FW+14][3] == 0:
                px[y*FW+14] = px[y*FW+13]
        # Beard covers lower face and neck
        if facing == "DOWN":
            fill(px, FW, 4, 7, 11, 9, beard)
            hline(px, FW, 5, 10, 7, beard_hi)
            fill(px, FW, 5, 9, 10, 10, beard)
            fill(px, FW, 6, 10, 9, 11, beard)
            # Beard texture lines
            vline(px, FW, 6, 8, 10, _c(acc[0]-20, acc[1]-18, acc[2]-12))
            vline(px, FW, 9, 8, 10, _c(acc[0]-20, acc[1]-18, acc[2]-12))
        elif facing == "LEFT":
            fill(px, FW, 3, 7, 8, 10, beard)
            hline(px, FW, 4, 8, 7, beard_hi)
            fill(px, FW, 4, 10, 7, 11, beard)
        elif facing == "RIGHT":
            fill(px, FW, 7, 7, 12, 10, beard)
            hline(px, FW, 7, 11, 7, beard_hi)
            fill(px, FW, 8, 10, 11, 11, beard)
        # Armoured bracers / pauldron hint on shoulders
        pr = IRON_M
        pr_hi = IRON_L
        if facing in ("DOWN",):
            fill(px, FW, 2, 10, 3, 11, pr); put(px, FW, 2, 10, pr_hi)
            fill(px, FW, 12, 10, 13, 11, pr); put(px, FW, 13, 10, pr_hi)

# ── Class weapon overlays ─────────────────────────────────────────────────────

def _class_weapon(px, cls, facing, walk):
    if cls == "CUTPURSE":
        # Dagger at right hip — visible from sides and front
        blade = IRON_L; edge = IRON_S
        hilt  = (160,120,48,255); hilt_d = (110,80,28,255)
        if facing == "DOWN":
            put(px, FW, 12, 14, hilt)
            put(px, FW, 12, 15, hilt_d)
            put(px, FW, 13, 14, blade)
        elif facing == "LEFT":
            # Dagger horizontal at back hip
            put(px, FW, 11, 14, hilt); put(px, FW, 12, 14, hilt_d)
            hline(px, FW, 9, 11, 15, blade)
            put(px, FW, 9, 15, edge)
        elif facing == "RIGHT":
            put(px, FW, 3, 14, hilt); put(px, FW, 2, 14, hilt_d)
            hline(px, FW, 3, 5, 15, blade)
            put(px, FW, 5, 15, edge)

    elif cls == "SHADOWDANCER":
        # Twin shadow blades — glowing purple tips at hips
        blade = (100,45,175,255); glow = (68,22,130,180); edge = (160,90,230,255)
        if facing == "LEFT":
            put(px, FW, 2, 14, glow); put(px, FW, 2, 15, blade)
            put(px, FW, 1, 15, glow); put(px, FW, 2, 16, edge)
            put(px, FW, 11, 14, glow); put(px, FW, 12, 15, blade)
        elif facing == "RIGHT":
            put(px, FW, 13, 14, glow); put(px, FW, 13, 15, blade)
            put(px, FW, 14, 15, glow); put(px, FW, 13, 16, edge)
            put(px, FW, 3, 14, glow); put(px, FW, 2, 15, blade)
        elif facing == "DOWN":
            put(px, FW, 2, 15, glow); put(px, FW, 2, 16, blade)
            put(px, FW, 13, 15, glow); put(px, FW, 13, 16, blade)
        # Wisp particles (1px dots orbiting character)
        wisp = (100,45,175,160)
        wisp_pts = [(2,10),(14,12),(1,17),(14,19)] if not walk else [(1,11),(13,10),(2,18),(13,17)]
        for wx,wy in wisp_pts:
            if 0<=wx<FW and 0<=wy<FH: put(px, FW, wx, wy, wisp)

    elif cls == "ASSASSIN":
        # Hand crossbow — visible from side
        stock = (68,44,18,255); stock_l = (96,64,28,255)
        bolt  = IRON_M; string = (88,72,52,255)
        if facing == "LEFT":
            fill(px, FW, 2, 12, 4, 13, stock)
            put(px, FW, 2, 12, stock_l); put(px, FW, 4, 12, bolt)
            put(px, FW, 3, 11, string)
        elif facing == "RIGHT":
            fill(px, FW, 11, 12, 13, 13, stock)
            put(px, FW, 13, 12, stock_l); put(px, FW, 11, 12, bolt)
            put(px, FW, 12, 11, string)
        elif facing == "DOWN":
            fill(px, FW, 13, 12, 14, 13, stock)
            put(px, FW, 13, 11, bolt)

# ── Render one frame ──────────────────────────────────────────────────────────

def render_frame(facing, walk, cls, race):
    px   = blank(FW, FH)
    pal  = RACE[race]
    sk   = pal["skin"]
    hr   = pal["hair"]
    ey   = pal["eye"]
    cl   = CLASS_PAL[cls]

    # Draw body first (back layer), then head on top
    if facing == "DOWN":
        _body_front(px, cl, walk)
        _head_front(px, sk, hr, ey, race)
    elif facing == "LEFT":
        _body_side(px, cl, False, walk)
        _head_side(px, sk, hr, ey, race, False)
    elif facing == "RIGHT":
        _body_side(px, cl, True, walk)
        _head_side(px, sk, hr, ey, race, True)
    elif facing == "UP":
        _body_back(px, cl, walk)
        _head_back(px, sk, hr)

    _race_features(px, race, facing, walk)
    _class_weapon(px, cls, facing, walk)

    # Soft ground shadow ellipse
    for x in range(3, 13):
        d = abs(x - 7.5) / 5.0
        a = int(80 * max(0.0, 1.0 - d*d))
        if a > 0:
            cur = px[23*FW+x]
            if cur[3] < a:
                px[23*FW+x] = (0, 0, 0, a)

    # Dark outline pass
    outline_shape(px, FW, FH)
    return px


# ── Build sheet ───────────────────────────────────────────────────────────────
CLASSES = ["CUTPURSE", "SHADOWDANCER", "ASSASSIN"]
RACES   = ["HALFLING", "TIEFLING", "WOOD_ELF", "DWARF"]
DIRS    = ["DOWN", "LEFT", "RIGHT", "UP"]

SW = 8 * FW   # 128
SH = 12 * FH  # 288
sheet = blank(SW, SH)

row_idx = 0
for cls in CLASSES:
    for race in RACES:
        col_idx = 0
        for facing in DIRS:
            for wf in range(2):
                frame = render_frame(facing, wf, cls, race)
                ox, oy = col_idx * FW, row_idx * FH
                for y in range(FH):
                    for x in range(FW):
                        sheet[(oy+y)*SW+(ox+x)] = frame[y*FW+x]
                col_idx += 1
        row_idx += 1

write_png("sprites/player_sheet.png", sheet, SW, SH)
print(f"Wrote sprites/player_sheet.png  ({SW}×{SH})")

# ─────────────────────────────────────────────────────────────────────────────
# FURNITURE SPRITES
# ─────────────────────────────────────────────────────────────────────────────

def write_furn(name, w, h, draw_fn):
    px = blank(w, h)
    draw_fn(px, w, h)
    outline_shape(px, w, h)
    write_png(f"sprites/{name}.png", px, w, h)
    print(f"Wrote sprites/{name}.png  ({w}×{h})")

# ── Guard booth (20×24) ───────────────────────────────────────────────────────
def draw_booth(px, w, h):
    WOOD_D = (38, 25, 10, 255)
    WOOD_M = (62, 42, 18, 255)
    WOOD_L = (88, 62, 28, 255)
    IRON   = (55, 50, 45, 255)
    WINDOW = (10,  8,  6, 255)
    # Main body
    fill(px, w, 0, 0, w-1, h-1, WOOD_M)
    # Top cap
    fill(px, w, 0, 0, w-1, 2, WOOD_L)
    # Left edge shadow
    fill(px, w, 0, 3, 1, h-1, WOOD_D)
    # Horizontal plank lines
    for py in [6, 12, 18]:
        hline(px, w, 2, w-1, py, WOOD_D)
    # Slit window
    fill(px, w, 5, 8, 13, 12, WINDOW)
    hline(px, w, 5, 13, 8, IRON)
    hline(px, w, 5, 13, 12, IRON)
    # Iron corner brackets
    fill(px, w, 2, 2, 4, 4, IRON)
    fill(px, w, w-5, 2, w-3, 4, IRON)
    fill(px, w, 2, h-5, 4, h-3, IRON)
    fill(px, w, w-5, h-5, w-3, h-3, IRON)
    # Bottom edge
    hline(px, w, 0, w-1, h-1, WOOD_D)

write_furn("furn_booth", 20, 24, draw_booth)

# ── Crate stack (24×36) ───────────────────────────────────────────────────────
def draw_crate(px, w, h):
    WOOD_D = (42, 28, 12, 255)
    WOOD_M = (68, 46, 20, 255)
    WOOD_L = (96, 68, 32, 255)
    IRON   = (52, 46, 40, 255)
    # Lower large crate (0-19)
    fill(px, w, 0, 16, w-1, h-1, WOOD_M)
    fill(px, w, 0, 16, w-1, 18, WOOD_L)      # top face
    fill(px, w, 0, 17, 1, h-1, WOOD_D)        # left shadow
    hline(px, w, 0, w-1, h-1, WOOD_D)         # bottom edge
    vline(px, w, w//2, 16, h-1, WOOD_D)       # centre split
    hline(px, w, 0, w-1, h//2+2, WOOD_D)     # horizontal plank line
    # Iron straps on lower crate
    for ix in [2, w-3]:
        vline(px, w, ix, 16, h-1, IRON)
    hline(px, w, 0, w-1, 26, IRON)
    # Upper smaller crate (3 px inset each side)
    fill(px, w, 3, 0, w-4, 15, WOOD_M)
    fill(px, w, 3, 0, w-4, 2, WOOD_L)         # top face
    fill(px, w, 3, 1, 4, 15, WOOD_D)           # left shadow
    hline(px, w, 3, w-4, 15, WOOD_D)           # bottom edge
    vline(px, w, (3+w-4)//2, 0, 15, WOOD_D)   # centre split
    hline(px, w, 3, w-4, 8, WOOD_D)
    # Iron straps on upper crate
    for ix in [5, w-6]:
        vline(px, w, ix, 0, 15, IRON)

write_furn("furn_crate", 24, 36, draw_crate)

# ── Notice board (22×16) ──────────────────────────────────────────────────────
def draw_noticeboard(px, w, h):
    FRAME  = (42, 28, 12, 255)
    PAPER  = (188, 174, 140, 255)
    PAPER2 = (162, 148, 116, 255)
    INK    = (60, 50, 36, 255)
    PIN    = (160, 40, 20, 255)
    # Frame
    fill(px, w, 0, 0, w-1, h-1, FRAME)
    # Paper inset
    fill(px, w, 2, 2, w-3, h-3, PAPER)
    fill(px, w, 2, 2, w-3, 3, PAPER2)  # top shadow on paper
    # Ruled lines
    for li in range(3):
        hline(px, w, 4, w-5, 5 + li*3, INK)
    # Pin tacks
    put(px, w, 4,   2, PIN); put(px, w, w-5, 2, PIN)
    put(px, w, 4,   h-3, PIN); put(px, w, w-5, h-3, PIN)

write_furn("furn_noticeboard", 22, 16, draw_noticeboard)

# ── Bed + footlocker (24×22) ──────────────────────────────────────────────────
def draw_bed(px, w, h):
    FRAME  = (36, 22, 10, 255)
    FRAME_L= (56, 36, 18, 255)
    MATT   = (72, 52, 38, 255)
    MATT_L = (96, 72, 54, 255)
    PILLOW = (168, 148, 110, 255)
    PILLOW2= (140, 122, 88, 255)
    LOCKER = (48, 40, 30, 255)
    LOCKER_L=(72, 60, 44, 255)
    HASP   = (90, 82, 70, 255)
    # Bed frame
    fill(px, w, 0, 0, w-1, 13, FRAME)
    # Mattress
    fill(px, w, 1, 1, w-2, 12, MATT)
    hline(px, w, 1, w-2, 1, MATT_L)
    vline(px, w, 1, 1, 12, MATT_L)
    # Pillow
    fill(px, w, 2, 2, 10, 7, PILLOW)
    fill(px, w, 2, 2, 10, 3, PILLOW2)
    vline(px, w, 2, 2, 7, PILLOW2)
    # Blanket fold hint
    hline(px, w, 11, w-2, 9, MATT_L)
    # Footlocker
    fill(px, w, 1, 15, w-3, h-1, LOCKER)
    hline(px, w, 1, w-3, 15, LOCKER_L)
    hline(px, w, 1, w-3, 16, LOCKER_L)
    vline(px, w, 1, 15, h-1, LOCKER)
    # Hasp / latch
    fill(px, w, 7, 17, 10, 19, HASP)
    put(px, w, 8, 18, (110, 100, 84, 255))

write_furn("furn_bed", 24, 22, draw_bed)

# ── Communal table segment (32×16) ────────────────────────────────────────────
def draw_table(px, w, h):
    TOP_L  = (108, 76, 34, 255)
    TOP_M  = (84, 58, 24, 255)
    TOP_D  = (58, 38, 14, 255)
    LEG    = (46, 30, 12, 255)
    GRAIN  = (66, 44, 18, 255)
    # Table top surface
    fill(px, w, 0, 0, w-1, 3, TOP_L)
    fill(px, w, 0, 4, w-1, h-4, TOP_M)
    # Grain lines
    for gx in range(4, w-4, 6):
        vline(px, w, gx, 1, h-4, GRAIN)
    # Front face (shadow)
    fill(px, w, 0, h-3, w-1, h-1, TOP_D)
    hline(px, w, 0, w-1, h-3, TOP_M)
    # Legs
    fill(px, w, 2,  h-3, 4,  h-1, LEG)
    fill(px, w, w-5, h-3, w-3, h-1, LEG)

write_furn("furn_table", 32, 16, draw_table)

# ── Bench segment (32×8) ──────────────────────────────────────────────────────
def draw_bench(px, w, h):
    TOP_L = (82, 56, 24, 255)
    TOP_M = (62, 42, 16, 255)
    LEG   = (44, 28, 10, 255)
    # Seat
    fill(px, w, 0, 0, w-1, 3, TOP_L)
    fill(px, w, 0, 4, w-1, h-3, TOP_M)
    hline(px, w, 0, w-1, h-2, LEG)
    # Legs
    fill(px, w, 2, h-3, 4, h-1, LEG)
    fill(px, w, w-5, h-3, w-3, h-1, LEG)

write_furn("furn_bench", 32, 8, draw_bench)

# ── Weapon rack (12×48) ───────────────────────────────────────────────────────
def draw_rack(px, w, h):
    WOOD_D = (36, 22, 8, 255)
    WOOD_M = (58, 38, 16, 255)
    WOOD_L = (80, 56, 26, 255)
    IRON   = (58, 52, 46, 255)
    IRON_L = (82, 76, 68, 255)
    BLADE  = (178, 172, 162, 255)
    BLADE_L= (220, 216, 208, 255)
    HILT   = (130, 96, 42, 255)
    # Rack backing
    fill(px, w, 0, 0, w-1, h-1, WOOD_D)
    fill(px, w, 1, 1, w-2, h-2, WOOD_M)
    # Horizontal bars
    for by in [3, h//3, h*2//3, h-4]:
        fill(px, w, 0, by, w-1, by+2, IRON)
        hline(px, w, 0, w-1, by, IRON_L)
    # Four weapons (spear/sword shapes)
    for wi in range(4):
        wx = 1 + wi * 3
        wy = 5 + wi * 10
        # Blade
        vline(px, w, wx, wy, wy+16, BLADE)
        put(px, w, wx, wy, BLADE_L)
        put(px, w, wx, wy+1, BLADE_L)
        # Hilt
        fill(px, w, wx-1, wy+16, wx+1, wy+18, HILT)

write_furn("furn_rack", 12, 48, draw_rack)

# ── Stone pedestal / plinth (18×14) ───────────────────────────────────────────
def draw_plinth(px, w, h):
    BASE_D = (48, 36, 62, 255)
    BASE_M = (72, 58, 92, 255)
    BASE_L = (98, 82, 122, 255)
    TOP_F  = (118,100, 145, 255)
    GLOW   = (140, 90, 200, 100)
    # Base block
    fill(px, w, 0, 3, w-1, h-1, BASE_D)
    fill(px, w, 1, 3, w-2, h-2, BASE_M)
    # Top face
    fill(px, w, 0, 0, w-1, 3, BASE_L)
    hline(px, w, 0, w-1, 0, TOP_F)
    # Side face highlight
    vline(px, w, 0, 3, h-1, BASE_L)
    vline(px, w, 1, 3, h-1, BASE_M)
    # Rune glow on top
    fill(px, w, 5, 1, w-6, 2, GLOW)

write_furn("furn_plinth", 18, 14, draw_plinth)

# ── Altar platform (40×26) ────────────────────────────────────────────────────
def draw_altar(px, w, h):
    BASE_D = (44, 32, 18, 255)
    BASE_M = (72, 54, 28, 255)
    BASE_L = (102, 78, 42, 255)
    TOP_F  = (138, 108, 58, 255)
    GOLD   = (200, 162, 50, 255)
    GOLD_D = (150, 112, 28, 255)
    STEP   = (38, 28, 14, 255)
    STEP_L = (62, 46, 22, 255)
    # Step base
    fill(px, w, 0, h-5, w-1, h-1, STEP)
    hline(px, w, 0, w-1, h-5, STEP_L)
    hline(px, w, 0, w-1, h-4, STEP_L)
    # Main altar block
    fill(px, w, 4, 4, w-5, h-6, BASE_D)
    fill(px, w, 5, 4, w-6, h-7, BASE_M)
    # Top face
    fill(px, w, 4, 0, w-5, 4, BASE_L)
    hline(px, w, 4, w-5, 0, TOP_F)
    hline(px, w, 4, w-5, 1, TOP_F)
    # Side highlight
    vline(px, w, 4, 0, h-6, BASE_L)
    vline(px, w, 5, 0, h-6, BASE_M)
    # Gold trim on top face
    hline(px, w, 5, w-6, 0, GOLD)
    hline(px, w, 5, w-6, 1, GOLD)
    for gx in [6, w-7]:
        vline(px, w, gx, 0, 3, GOLD)
    # Ritual circle on top
    put(px, w, w//2,   2, GOLD)
    put(px, w, w//2-1, 2, GOLD_D)
    put(px, w, w//2+1, 2, GOLD_D)
    put(px, w, w//2,   1, GOLD_D)
    put(px, w, w//2,   3, GOLD_D)

write_furn("furn_altar", 40, 26, draw_altar)


# =============================================================================
# ENEMY SHEET  128×120 px  (8 cols × 6 rows, each cell 16×20)
# =============================================================================
# Colour constants shared across enemy types
_IRON_L  = (195, 192, 185, 255)
_IRON_M  = (148, 144, 138, 255)
_IRON_S  = ( 96,  92,  88, 255)
_IRON_D  = ( 58,  54,  50, 255)
_GOLD_L  = (234, 196,  68, 255)
_GOLD_M  = (188, 150,  38, 255)
_GOLD_D  = (130, 100,  20, 255)
_RED_M   = (148,  28,  28, 255)
_RED_D   = ( 88,  12,  12, 255)
_RED_L   = (200,  60,  60, 255)
_BURG_L  = (172,  56,  72, 255)
_BURG_M  = (128,  32,  48, 255)
_BURG_D  = ( 76,  14,  26, 255)
_BONE_L  = (234, 230, 212, 255)
_BONE_M  = (196, 192, 170, 255)
_BONE_D  = (142, 138, 118, 255)
_SK_EYE  = ( 32, 200,  64, 255)   # green glow inside socket
_TATTER  = ( 38,  28,  18, 255)
_GOB_SK  = (130, 200,  60, 255)   # goblin lime skin
_GOB_D   = ( 78, 130,  28, 255)
_GOB_L   = (172, 228,  90, 255)
_GOB_EYE = (200,  30,  30, 255)
_GOB_IRON= ( 78,  70,  62, 255)   # scrap helmet
_GOB_LTH = ( 88,  58,  24, 255)   # leather vest
_GNOLL_B = (175, 140,  85, 255)   # tan fur
_GNOLL_D = (120,  90,  50, 255)   # spot/shadow
_GNOLL_L = (210, 175, 115, 255)   # highlight
_GNOLL_E = (210, 165,  20, 255)   # amber eye
_GNOLL_ST= ( 72,  58,  38, 255)   # studded leather
_HOUND_D = ( 38,  34,  30, 255)   # dark grey-black fur
_HOUND_M = ( 70,  64,  56, 255)
_HOUND_L = (108, 100,  88, 255)
_HOUND_UB= (148, 134, 110, 255)   # underbelly
_HOUND_E = (200, 160,  20, 255)   # amber eye


def _ecell(etype, facing, walk):
    """Return a 16×20 pixel list for one enemy cell."""
    EW, EH = 16, 20
    px = blank(EW, EH)

    if etype == "HUMAN" or etype == "BOSS":
        _draw_guard(px, facing, walk, etype == "BOSS")
    elif etype == "SKELETON":
        _draw_skeleton(px, facing, walk)
    elif etype == "GOBLIN":
        _draw_goblin(px, facing, walk)
    elif etype == "GNOLL":
        _draw_gnoll(px, facing, walk)
    elif etype == "HOUND":
        _draw_hound(px, facing, walk)

    outline_shape(px, EW, EH)
    return px


def _draw_guard(px, facing, walk, boss=False):
    EW, EH = 16, 20
    pauldron = _GOLD_M if boss else _IRON_M
    pauldron_l = _GOLD_L if boss else _IRON_L
    pauldron_s = _GOLD_D if boss else _IRON_S
    # leg offset for walk
    loff = 1 if walk else 0

    if facing == "DOWN":
        # --- Helmet ---
        # Dome (rows 0-3)
        fill(px, EW, 4, 0, 11, 4, _IRON_M)
        hline(px, EW, 5, 10, 0, _IRON_L)   # dome highlight
        hline(px, EW, 4, 11, 1, _IRON_L)
        if boss:
            # Red plume above helm
            fill(px, EW, 7, 0, 8, 0, _RED_M)
            put(px, EW, 7, 0, _RED_L)
        # Visor slit y=3-4
        hline(px, EW, 5, 10, 3, _IRON_D)
        hline(px, EW, 5, 10, 4, _IRON_D)
        # Cheek guards
        fill(px, EW, 3, 2, 4, 5, _IRON_S)
        fill(px, EW, 11, 2, 12, 5, _IRON_S)
        # --- Breastplate ---
        fill(px, EW, 3, 5, 12, 9, _IRON_M)
        hline(px, EW, 3, 12, 5, _IRON_L)
        vline(px, EW, 3, 5, 9, _IRON_S)
        vline(px, EW, 12, 5, 9, _IRON_S)
        if boss:
            # Gold trim on breastplate
            hline(px, EW, 4, 11, 6, _GOLD_M)
            vline(px, EW, 5, 6, 9, _GOLD_D)
            vline(px, EW, 10, 6, 9, _GOLD_D)
        # Tabard (burgundy/red over body, y6-10)
        fill(px, EW, 5, 6, 10, 10, _BURG_M)
        vline(px, EW, 5, 6, 10, _BURG_D)
        vline(px, EW, 10, 6, 10, _BURG_D)
        hline(px, EW, 5, 10, 6, _BURG_L)
        # Pauldrons
        fill(px, EW, 1, 5, 3, 7, pauldron)
        put(px, EW, 1, 5, pauldron_l); put(px, EW, 2, 5, pauldron_l)
        fill(px, EW, 12, 5, 14, 7, pauldron)
        put(px, EW, 14, 5, pauldron_s)
        # Gold belt buckle
        fill(px, EW, 6, 10, 9, 11, _GOLD_M)
        put(px, EW, 7, 10, _GOLD_L); put(px, EW, 8, 10, _GOLD_L)
        # Greaves
        fill(px, EW, 4, 12, 6, 15, _IRON_M)
        fill(px, EW, 9, 12, 11, 15, _IRON_M)
        hline(px, EW, 4, 6, 12, _IRON_L)
        hline(px, EW, 9, 11, 12, _IRON_L)
        # Boots
        fill(px, EW, 4, 16+loff, 6, 19, _IRON_S)
        fill(px, EW, 9, 16+(1-loff), 11, 19, _IRON_S)

    elif facing in ("LEFT", "RIGHT"):
        r = (facing == "RIGHT")
        bx = 10 if r else 5   # face side x
        # Helmet dome
        fill(px, EW, 4, 0, 11, 4, _IRON_M)
        hline(px, EW, 4, 11, 0, _IRON_L)
        if boss:
            put(px, EW, 7, 0, _RED_M); put(px, EW, 8, 0, _RED_L)
        # Visor slit (profile = single slot on face side)
        put(px, EW, bx, 3, _IRON_D); put(px, EW, bx, 4, _IRON_D)
        # Cheek guard facing direction
        fill(px, EW, bx, 2, bx+(1 if r else -1), 5, _IRON_S)
        # Body
        fill(px, EW, 4, 5, 11, 9, _IRON_M)
        hline(px, EW, 4, 11, 5, _IRON_L)
        # Tabard stripe down front
        tx = 9 if r else 6
        vline(px, EW, tx, 5, 10, _BURG_M)
        # Pauldron (near shoulder)
        px0, px1 = (11, 14) if r else (1, 4)
        fill(px, EW, px0, 5, px1, 7, pauldron)
        put(px, EW, px0 if not r else px1, 5, pauldron_l)
        # Belt
        fill(px, EW, 4, 10, 11, 11, _GOLD_D)
        put(px, EW, 7, 10, _GOLD_L)
        # Greaves
        fill(px, EW, 5, 12, 10, 15, _IRON_M)
        hline(px, EW, 5, 10, 12, _IRON_L)
        # Legs / boots (profile — two positions)
        fl = (9 if r else 6) if not walk else (6 if r else 9)
        bl = (6 if r else 9) if not walk else (9 if r else 6)
        fill(px, EW, bl, 16, bl+1, 19, _IRON_S)
        fill(px, EW, fl, 16, fl+1, 19, _IRON_M)
        put(px, EW, fl, 16, _IRON_L)

    elif facing == "UP":
        # Back of helmet + cape hint
        fill(px, EW, 4, 0, 11, 4, _IRON_M)
        hline(px, EW, 4, 11, 0, _IRON_L)
        if boss:
            # Floor-length cape visible from behind
            fill(px, EW, 2, 5, 13, 13, _RED_M)
            vline(px, EW, 2, 5, 13, _RED_D)
            vline(px, EW, 13, 5, 13, _RED_D)
            hline(px, EW, 3, 12, 5, _RED_L)
            # Plume from top of helm
            fill(px, EW, 7, 0, 8, 0, _RED_M)
            put(px, EW, 7, 0, _RED_L)
        else:
            # Cape hint in burgundy
            fill(px, EW, 4, 5, 11, 11, _BURG_D)
            hline(px, EW, 4, 11, 5, _BURG_M)
        # Pauldrons from behind
        fill(px, EW, 1, 5, 3, 7, pauldron); fill(px, EW, 12, 5, 14, 7, pauldron)
        # Greaves back
        fill(px, EW, 4, 12, 6, 15, _IRON_M)
        fill(px, EW, 9, 12, 11, 15, _IRON_M)
        # Boots
        fill(px, EW, 4, 16+loff, 6, 19, _IRON_S)
        fill(px, EW, 9, 16+(1-loff), 11, 19, _IRON_S)


def _draw_skeleton(px, facing, walk):
    EW, EH = 16, 20
    loff = 1 if walk else 0

    if facing == "DOWN":
        # Skull dome
        fill(px, EW, 4, 0, 11, 5, _BONE_M)
        hline(px, EW, 5, 10, 0, _BONE_L)
        hline(px, EW, 4, 11, 1, _BONE_L)
        # Eye sockets (black with green glow dot)
        fill(px, EW, 5, 2, 6, 4, (10, 10, 10, 255))
        fill(px, EW, 9, 2, 10, 4, (10, 10, 10, 255))
        put(px, EW, 5, 3, _SK_EYE); put(px, EW, 9, 3, _SK_EYE)
        # Jaw
        fill(px, EW, 5, 5, 10, 6, _BONE_M)
        hline(px, EW, 5, 10, 5, _BONE_D)
        # Tattered cloth at waist
        fill(px, EW, 4, 10, 11, 12, _TATTER)
        hline(px, EW, 4, 11, 10, (58, 46, 32, 255))
        # Ribcage (3 rows of bone struts)
        for ry in [7, 8, 9]:
            hline(px, EW, 5, 10, ry, _BONE_D)
            put(px, EW, 5, ry, _BONE_M); put(px, EW, 10, ry, _BONE_M)
        # Spine
        vline(px, EW, 7, 7, 9, _BONE_L); vline(px, EW, 8, 7, 9, _BONE_L)
        # Shoulder bone joints (circles)
        put(px, EW, 3, 6, _BONE_L); put(px, EW, 4, 6, _BONE_M)
        put(px, EW, 11, 6, _BONE_L); put(px, EW, 12, 6, _BONE_M)
        # Leg bones
        vline(px, EW, 5, 13, 16+loff, _BONE_M)
        vline(px, EW, 6, 13, 16+loff, _BONE_D)
        vline(px, EW, 9, 13, 16+(1-loff), _BONE_M)
        vline(px, EW, 10, 13, 16+(1-loff), _BONE_D)
        # Foot bones
        hline(px, EW, 4, 7, 17+loff, _BONE_M)
        hline(px, EW, 8, 11, 17+(1-loff), _BONE_M)

    elif facing in ("LEFT", "RIGHT"):
        r = (facing == "RIGHT")
        bx = 9 if r else 6
        # Profile skull
        fill(px, EW, 4, 0, 11, 5, _BONE_M)
        hline(px, EW, 4, 11, 0, _BONE_L)
        # Single eye socket
        ex = 9 if r else 5
        fill(px, EW, ex, 2, ex+1, 4, (10, 10, 10, 255))
        put(px, EW, ex, 3, _SK_EYE)
        # Jaw forward
        jx = 11 if r else 4
        fill(px, EW, jx, 5, jx+(1 if r else -1), 6, _BONE_M)
        # Ribcage struts
        for ry in [7, 8, 9]:
            hline(px, EW, 5, 10, ry, _BONE_D)
        # Spine
        vline(px, EW, 7, 7, 9, _BONE_L); vline(px, EW, 8, 7, 9, _BONE_L)
        # Cloth
        fill(px, EW, 5, 10, 10, 12, _TATTER)
        # Sword arm hint from side (bone arm + blade suggestion)
        ax = 12 if r else 3
        vline(px, EW, ax, 6, 10, _BONE_M)
        put(px, EW, ax, 5, _BONE_L)
        # Leg bones
        fl = (9 if r else 6) if not walk else (6 if r else 9)
        bl = (6 if r else 9) if not walk else (9 if r else 6)
        vline(px, EW, bl, 13, 17, _BONE_D)
        vline(px, EW, fl, 13, 17, _BONE_M)
        hline(px, EW, fl, fl+2, 17, _BONE_M)

    elif facing == "UP":
        # Back of skull
        fill(px, EW, 4, 0, 11, 5, _BONE_M)
        hline(px, EW, 4, 11, 0, _BONE_L)
        hline(px, EW, 4, 11, 5, _BONE_D)
        # Spine + ribs from behind
        vline(px, EW, 7, 6, 9, _BONE_L); vline(px, EW, 8, 6, 9, _BONE_L)
        for ry in [7, 8, 9]:
            put(px, EW, 5, ry, _BONE_D); put(px, EW, 10, ry, _BONE_D)
        fill(px, EW, 4, 10, 11, 12, _TATTER)
        # Legs
        vline(px, EW, 5, 13, 16+loff, _BONE_M)
        vline(px, EW, 9, 13, 16+(1-loff), _BONE_M)
        hline(px, EW, 4, 7, 17+loff, _BONE_M)
        hline(px, EW, 8, 11, 17+(1-loff), _BONE_M)


def _draw_goblin(px, facing, walk):
    EW, EH = 16, 20
    # Goblin: short — head top 10px, body bottom 10px (offset +2 to start body at y=10)
    loff = 1 if walk else 0

    if facing == "DOWN":
        # Big pointed ears
        put(px, EW, 2, 3, _GOB_SK); put(px, EW, 1, 2, _GOB_D)
        put(px, EW, 2, 4, _GOB_SK)
        put(px, EW, 13, 3, _GOB_SK); put(px, EW, 14, 2, _GOB_D)
        put(px, EW, 13, 4, _GOB_SK)
        # Scrap helmet (askew, slightly off-centre)
        fill(px, EW, 4, 1, 12, 4, _GOB_IRON)
        hline(px, EW, 5, 12, 1, (100, 92, 82, 255))
        # shift askew
        put(px, EW, 3, 2, _GOB_IRON); put(px, EW, 13, 3, _GOB_IRON)
        # Face
        fill(px, EW, 4, 3, 11, 8, _GOB_SK)
        hline(px, EW, 4, 11, 3, _GOB_L)
        fill(px, EW, 4, 7, 11, 8, _GOB_D)
        # Red eyes
        put(px, EW, 5, 5, _GOB_EYE); put(px, EW, 6, 5, _GOB_EYE)
        put(px, EW, 9, 5, _GOB_EYE); put(px, EW, 10, 5, _GOB_EYE)
        # Nose
        put(px, EW, 7, 6, _GOB_D); put(px, EW, 8, 6, _GOB_D)
        # Patch leather vest with rivets
        fill(px, EW, 4, 9, 11, 13, _GOB_LTH)
        hline(px, EW, 4, 11, 9, (110, 80, 36, 255))
        put(px, EW, 4, 10, _IRON_M); put(px, EW, 11, 10, _IRON_M)  # rivets
        put(px, EW, 5, 13, _IRON_M); put(px, EW, 10, 13, _IRON_M)
        # Belt
        hline(px, EW, 4, 11, 13, _IRON_S)
        # Bare clawed legs
        vline(px, EW, 5, 14, 16+loff, _GOB_SK)
        vline(px, EW, 6, 14, 16+loff, _GOB_D)
        vline(px, EW, 9, 14, 16+(1-loff), _GOB_SK)
        vline(px, EW, 10, 14, 16+(1-loff), _GOB_D)
        # Clawed toes
        put(px, EW, 4, 17+loff, _GOB_D); put(px, EW, 7, 17+loff, _GOB_D)
        put(px, EW, 8, 17+(1-loff), _GOB_D); put(px, EW, 11, 17+(1-loff), _GOB_D)

    elif facing in ("LEFT", "RIGHT"):
        r = (facing == "RIGHT")
        ex = 9 if r else 5
        # Big ear on visible side
        ex_ear = 13 if r else 2
        put(px, EW, ex_ear, 3, _GOB_SK)
        put(px, EW, ex_ear + (1 if r else -1), 2, _GOB_D)
        put(px, EW, ex_ear, 4, _GOB_SK)
        # Helmet
        fill(px, EW, 4, 1, 11, 4, _GOB_IRON)
        hline(px, EW, 4, 11, 1, (100, 92, 82, 255))
        # Face
        fill(px, EW, 4, 3, 11, 8, _GOB_SK)
        hline(px, EW, 4, 11, 3, _GOB_L)
        # Red eye (facing side)
        put(px, EW, ex, 5, _GOB_EYE); put(px, EW, ex-(1 if r else -1), 5, _GOB_EYE)
        # Nose tip
        nx = 11 if r else 4
        put(px, EW, nx, 6, _GOB_D)
        # Vest
        fill(px, EW, 4, 9, 11, 13, _GOB_LTH)
        hline(px, EW, 4, 11, 9, (110, 80, 36, 255))
        put(px, EW, 5, 11, _IRON_M); put(px, EW, 10, 11, _IRON_M)
        # Legs
        fl = (9 if r else 6) if not walk else (6 if r else 9)
        bl = (6 if r else 9) if not walk else (9 if r else 6)
        vline(px, EW, bl, 14, 17, _GOB_D)
        vline(px, EW, fl, 14, 17, _GOB_SK)
        put(px, EW, fl+1, 18, _GOB_D)

    elif facing == "UP":
        # Big ears from behind
        put(px, EW, 2, 3, _GOB_SK); put(px, EW, 13, 3, _GOB_SK)
        # Helmet back
        fill(px, EW, 4, 1, 11, 4, _GOB_IRON)
        hline(px, EW, 4, 11, 1, (100, 92, 82, 255))
        # Back of head
        fill(px, EW, 4, 3, 11, 8, _GOB_SK)
        fill(px, EW, 4, 7, 11, 8, _GOB_D)
        # Vest back
        fill(px, EW, 4, 9, 11, 13, _GOB_LTH)
        # Legs
        vline(px, EW, 5, 14, 16+loff, _GOB_SK)
        vline(px, EW, 9, 14, 16+(1-loff), _GOB_SK)
        put(px, EW, 4, 17+loff, _GOB_D); put(px, EW, 7, 17+loff, _GOB_D)
        put(px, EW, 8, 17+(1-loff), _GOB_D); put(px, EW, 11, 17+(1-loff), _GOB_D)


def _draw_gnoll(px, facing, walk):
    EW, EH = 16, 20
    loff = 1 if walk else 0

    if facing == "DOWN":
        # Large round ears on top
        fill(px, EW, 3, 0, 5, 2, _GNOLL_B)
        fill(px, EW, 10, 0, 12, 2, _GNOLL_B)
        put(px, EW, 3, 0, _GNOLL_L); put(px, EW, 10, 0, _GNOLL_L)
        # Head / elongated snout area
        fill(px, EW, 3, 1, 12, 6, _GNOLL_B)
        hline(px, EW, 3, 12, 1, _GNOLL_L)
        fill(px, EW, 4, 5, 11, 7, _GNOLL_D)   # elongated snout (lower face darker)
        # Spots
        for sx, sy in [(5,2),(9,2),(7,3),(4,4),(11,4)]:
            put(px, EW, sx, sy, _GNOLL_D)
        # Amber eyes
        put(px, EW, 5, 3, _GNOLL_E); put(px, EW, 6, 3, _GNOLL_E)
        put(px, EW, 9, 3, _GNOLL_E); put(px, EW, 10, 3, _GNOLL_E)
        # Nostril dots
        put(px, EW, 7, 6, (80,60,40,255)); put(px, EW, 8, 6, (80,60,40,255))
        # Thick muscular shoulders + studded vest
        fill(px, EW, 1, 7, 14, 12, _GNOLL_ST)
        hline(px, EW, 1, 14, 7, _GNOLL_B)
        vline(px, EW, 1, 7, 12, _GNOLL_D)
        vline(px, EW, 14, 7, 12, _GNOLL_D)
        # Studs
        for sx in [3, 7, 11]:
            for sy in [8, 10]:
                put(px, EW, sx, sy, _IRON_M)
        # Waist/belt
        hline(px, EW, 2, 13, 12, _GNOLL_D)
        fill(px, EW, 6, 12, 9, 13, _GOLD_D)
        # Legs (gnoll fills more of frame)
        fill(px, EW, 3, 13, 6, 16+loff, _GNOLL_B)
        fill(px, EW, 9, 13, 12, 16+(1-loff), _GNOLL_B)
        fill(px, EW, 3, 17+loff, 7, 19, _GNOLL_D)
        fill(px, EW, 8, 17+(1-loff), 12, 19, _GNOLL_D)

    elif facing in ("LEFT", "RIGHT"):
        r = (facing == "RIGHT")
        # Ear on top
        ex0, ex1 = (10, 12) if r else (3, 5)
        fill(px, EW, ex0, 0, ex1, 2, _GNOLL_B)
        put(px, EW, ex0 if r else ex1, 0, _GNOLL_L)
        # Head
        fill(px, EW, 3, 1, 12, 6, _GNOLL_B)
        hline(px, EW, 3, 12, 1, _GNOLL_L)
        # Snout (forward direction)
        sx = 11 if r else 3
        fill(px, EW, sx, 4, sx+(2 if r else -2), 6, _GNOLL_D)
        # Eye
        ex = 9 if r else 6
        put(px, EW, ex, 3, _GNOLL_E); put(px, EW, ex+(1 if r else -1), 3, _GNOLL_E)
        # Body
        fill(px, EW, 2, 7, 13, 12, _GNOLL_ST)
        hline(px, EW, 2, 13, 7, _GNOLL_B)
        vline(px, EW, 2, 7, 12, _GNOLL_D)
        vline(px, EW, 13, 7, 12, _GNOLL_D)
        for sy in [8, 10]:
            put(px, EW, 6, sy, _IRON_M); put(px, EW, 9, sy, _IRON_M)
        hline(px, EW, 3, 12, 12, _GNOLL_D)
        # Legs (profile)
        fl = (9 if r else 6) if not walk else (6 if r else 9)
        bl = (6 if r else 9) if not walk else (9 if r else 6)
        fill(px, EW, bl, 13, bl+2, 17, _GNOLL_D)
        fill(px, EW, fl, 13, fl+2, 17, _GNOLL_B)
        hline(px, EW, fl, fl+3, 17, _GNOLL_D)

    elif facing == "UP":
        # Round ears
        fill(px, EW, 3, 0, 5, 2, _GNOLL_B); fill(px, EW, 10, 0, 12, 2, _GNOLL_B)
        # Head back
        fill(px, EW, 3, 1, 12, 6, _GNOLL_B)
        hline(px, EW, 3, 12, 1, _GNOLL_L)
        fill(px, EW, 3, 5, 12, 6, _GNOLL_D)
        # Spots
        for sx, sy in [(6,2),(10,3),(4,3)]:
            put(px, EW, sx, sy, _GNOLL_D)
        # Vest back
        fill(px, EW, 2, 7, 13, 12, _GNOLL_ST)
        hline(px, EW, 2, 13, 7, _GNOLL_B)
        for sx in [4, 8, 12]:
            for sy in [8, 10]:
                put(px, EW, sx, sy, _IRON_M)
        hline(px, EW, 2, 13, 12, _GNOLL_D)
        # Legs
        fill(px, EW, 3, 13, 6, 16+loff, _GNOLL_B)
        fill(px, EW, 9, 13, 12, 16+(1-loff), _GNOLL_B)
        fill(px, EW, 3, 17+loff, 7, 19, _GNOLL_D)
        fill(px, EW, 8, 17+(1-loff), 12, 19, _GNOLL_D)


def _draw_hound(px, facing, walk):
    """Dog/wolf shape drawn in 16×16 centred at y offset 2 inside 16×20 cell."""
    EW = 16
    oy = 2  # vertical offset inside 20-tall cell
    loff = 1 if walk else 0

    # Helper lambdas that apply the y-offset
    def hput(x, y, c): put(px, EW, x, y + oy, c)
    def hfill(x1, y1, x2, y2, c): fill(px, EW, x1, y1 + oy, x2, y2 + oy, c)
    def hhline(x1, x2, y, c): hline(px, EW, x1, x2, y + oy, c)
    def hvline(x, y1, y2, c): vline(px, EW, x, y1 + oy, y2 + oy, c)

    if facing == "DOWN":
        # Head at top centre, snout pointed down
        hfill(5, 0, 10, 3, _HOUND_M)
        hhline(5, 10, 0, _HOUND_L)
        # Amber eyes
        hput(6, 1, _HOUND_E); hput(9, 1, _HOUND_E)
        # Snout
        hfill(6, 3, 9, 5, _HOUND_D)
        hhline(6, 9, 5, _HOUND_L)  # nose highlight
        # Body
        hfill(3, 4, 12, 11, _HOUND_M)
        hhline(3, 12, 4, _HOUND_L)
        hvline(3, 4, 11, _HOUND_D); hvline(12, 4, 11, _HOUND_D)
        # Underbelly strip
        hfill(6, 5, 9, 11, _HOUND_UB)
        # Tail stub (top, at back)
        hput(7, 0, _HOUND_D); hput(8, 0, _HOUND_D)
        # Four legs (spread for walk, together for idle)
        leg_spread = loff
        hfill(3, 12, 5, 13+leg_spread, _HOUND_D)
        hfill(10, 12, 12, 13+leg_spread, _HOUND_D)
        hfill(4, 12, 6, 13+(1-leg_spread), _HOUND_M)
        hfill(9, 12, 11, 13+(1-leg_spread), _HOUND_M)

    elif facing in ("LEFT", "RIGHT"):
        r = (facing == "RIGHT")
        # Body — elongated horizontally
        hfill(2, 4, 13, 10, _HOUND_M)
        hhline(2, 13, 4, _HOUND_L)
        hvline(2, 4, 10, _HOUND_D if not r else _HOUND_M)
        hvline(13, 4, 10, _HOUND_D if r else _HOUND_M)
        # Underbelly
        hfill(3, 7, 12, 10, _HOUND_UB)
        # Head in facing direction
        hx0, hx1 = (10, 15) if r else (0, 5)
        hfill(hx0, 1, min(hx1,15), 6, _HOUND_M)
        hhline(hx0, min(hx1,15), 1, _HOUND_L)
        # Eye
        ex = 13 if r else 2
        hput(ex, 2, _HOUND_E); hput(ex, 3, _HOUND_E)
        # Snout tip
        sx = 15 if r else 0
        if sx < 16: hput(sx, 3, _HOUND_D); hput(sx, 4, _HOUND_D)
        # Tail at back
        tx = 0 if r else 15
        if tx < 16: hput(tx, 5, _HOUND_D); hput(tx, 6, _HOUND_D)
        # Legs (front pair and back pair)
        fl = 10 if r else 4
        bl = 4 if r else 10
        if walk: fl, bl = bl, fl
        hfill(fl, 11, fl+1, 13, _HOUND_M)
        hfill(fl+1, 11, fl+2, 13, _HOUND_D)
        hfill(bl, 11, bl+1, 13, _HOUND_D)
        hfill(bl+1, 11, bl+2, 12, _HOUND_M)

    elif facing == "UP":
        # Mirror of DOWN — tail at bottom, snout at top (pointed away)
        # Body
        hfill(3, 3, 12, 11, _HOUND_M)
        hhline(3, 12, 3, _HOUND_L)
        hvline(3, 3, 11, _HOUND_D); hvline(12, 3, 11, _HOUND_D)
        hfill(6, 4, 9, 10, _HOUND_UB)
        # Head/nape at top
        hfill(5, 0, 10, 3, _HOUND_M)
        hhline(5, 10, 0, _HOUND_L)
        # Tail stub at bottom
        hput(7, 11, _HOUND_D); hput(8, 11, _HOUND_D)
        # Legs
        leg_spread = loff
        hfill(3, 12, 5, 13+leg_spread, _HOUND_D)
        hfill(10, 12, 12, 13+leg_spread, _HOUND_D)
        hfill(4, 12, 6, 13+(1-leg_spread), _HOUND_M)
        hfill(9, 12, 11, 13+(1-leg_spread), _HOUND_M)


# Build enemy_sheet.png  128×120
_ENEMY_TYPES = ["HUMAN", "SKELETON", "GOBLIN", "GNOLL", "BOSS", "HOUND"]
_E_DIRS = ["DOWN", "DOWN", "LEFT", "LEFT", "RIGHT", "RIGHT", "UP", "UP"]
_E_WALKS= [    0,      1,      0,      1,       0,       1,    0,    1]
ESW, ESH = 128, 120
enemy_sheet = blank(ESW, ESH)
for row, etype in enumerate(_ENEMY_TYPES):
    for col in range(8):
        facing = _E_DIRS[col]
        wf     = _E_WALKS[col]
        cell   = _ecell(etype, facing, wf)
        ox, oy = col * 16, row * 20
        for cy in range(20):
            for cx in range(16):
                enemy_sheet[(oy + cy) * ESW + (ox + cx)] = cell[cy * 16 + cx]
write_png("sprites/enemy_sheet.png", enemy_sheet, ESW, ESH)
print(f"Wrote sprites/enemy_sheet.png  ({ESW}×{ESH})")


# =============================================================================
# TORCH SHEET  24×12 px  (3 frames of 8×12)
# =============================================================================
def make_torch_sheet():
    TW, TH, FW2 = 24, 12, 8
    px = blank(TW, TH)

    IR_B = ( 52,  46,  40, 255)
    IR_L = ( 78,  72,  64, 255)
    BRACKET_D = ( 34,  28,  22, 255)
    FLAME1= (255, 200,  40, 255)
    FLAME2= (255, 140,  20, 255)
    FLAME3= (220,  60,  10, 255)
    FLARE = (255, 248, 200, 255)
    FLAME1B=(255, 220,  70, 255)
    SMOKE = ( 60,  54,  48, 180)

    def draw_bracket(ox):
        # Iron bracket bottom 5 rows (y=7..11)
        fill(px, TW, ox+2, 7, ox+5, 11, IR_B)
        hline(px, TW, ox+2, ox+5, 7, IR_L)
        vline(px, TW, ox+2, 7, 11, IR_L)
        put(px, TW, ox+3, 8, IR_L)
        # Peg on wall (darker)
        fill(px, TW, ox+1, 9, ox+2, 10, BRACKET_D)

    # Frame 0 — lit1
    draw_bracket(0)
    fill(px, TW, 1, 3, 6, 6, FLAME2)
    fill(px, TW, 2, 1, 5, 4, FLAME1)
    put(px, TW, 3, 0, FLARE); put(px, TW, 4, 0, FLARE)
    put(px, TW, 3, 1, FLARE)
    fill(px, TW, 1, 5, 6, 7, FLAME3)
    put(px, TW, 2, 2, FLAME1B); put(px, TW, 4, 1, FLAME1B)

    # Frame 1 — lit2 (taller brighter flame)
    ox = 8
    draw_bracket(ox)
    fill(px, TW, ox+1, 2, ox+6, 6, FLAME2)
    fill(px, TW, ox+2, 0, ox+5, 4, FLAME1)
    put(px, TW, ox+3, 0, FLARE); put(px, TW, ox+4, 0, FLARE)
    fill(px, TW, ox+1, 5, ox+6, 7, FLAME3)
    put(px, TW, ox+2, 1, FLARE); put(px, TW, ox+5, 1, FLAME1B)
    put(px, TW, ox+3, 0, FLARE); put(px, TW, ox+4, 0, FLARE)

    # Frame 2 — unlit, smoke smudge
    ox = 16
    draw_bracket(ox)
    put(px, TW, ox+3, 5, SMOKE); put(px, TW, ox+4, 5, SMOKE)
    put(px, TW, ox+3, 4, SMOKE); put(px, TW, ox+2, 3, SMOKE)
    put(px, TW, ox+4, 3, SMOKE)

    outline_shape(px, TW, TH)
    write_png("sprites/torch_sheet.png", px, TW, TH)
    print(f"Wrote sprites/torch_sheet.png  ({TW}×{TH})")

make_torch_sheet()


# =============================================================================
# CHEST SHEET  28×14 px  (2 frames of 14×14)
# =============================================================================
def make_chest_sheet():
    CW, CH = 28, 14
    px = blank(CW, CH)

    WD_D = ( 58,  36,  14, 255)
    WD_M = ( 94,  62,  24, 255)
    WD_L = (136,  94,  40, 255)
    LID_L= (162, 118,  52, 255)
    LID_M= (120,  84,  30, 255)
    IRON = ( 62,  56,  50, 255)
    IRON_H=( 96,  88,  78, 255)
    GOLD = (210, 168,  44, 255)
    GOLD_D=(148, 112,  22, 255)
    GLINT= (255, 248, 160, 255)

    # Frame 0 — closed chest (x 0..13)
    fill(px, CW, 0, 5, 13, 13, WD_M)       # body
    fill(px, CW, 0, 5, 13, 6, WD_L)        # body top face
    fill(px, CW, 0, 5, 0, 13, WD_D)        # left shadow
    hline(px, CW, 0, 13, 13, WD_D)         # bottom edge
    # Lid
    fill(px, CW, 0, 0, 13, 4, LID_M)
    hline(px, CW, 0, 13, 0, LID_L)
    hline(px, CW, 0, 13, 1, LID_L)
    vline(px, CW, 0, 0, 4, WD_D)
    # Iron corner fittings
    fill(px, CW, 0, 0, 1, 1, IRON); fill(px, CW, 12, 0, 13, 1, IRON)
    fill(px, CW, 0, 11, 1, 13, IRON); fill(px, CW, 12, 11, 13, 13, IRON)
    put(px, CW, 0, 0, IRON_H); put(px, CW, 12, 0, IRON_H)
    # Gold trim on lid
    hline(px, CW, 1, 12, 0, GOLD)
    hline(px, CW, 1, 12, 4, GOLD)
    vline(px, CW, 1, 0, 4, GOLD)
    vline(px, CW, 12, 0, 4, GOLD)
    # Gold lock hasp centre
    fill(px, CW, 5, 3, 8, 6, GOLD_D)
    fill(px, CW, 6, 4, 7, 5, GOLD)
    put(px, CW, 6, 5, GOLD_D)

    # Frame 1 — open chest (x 14..27)
    ox = 14
    fill(px, CW, ox, 5, ox+13, 13, WD_M)
    fill(px, CW, ox, 5, ox+13, 6, WD_L)
    fill(px, CW, ox, 5, ox, 13, WD_D)
    hline(px, CW, ox, ox+13, 13, WD_D)
    # Iron fittings
    fill(px, CW, ox, 11, ox+1, 13, IRON); fill(px, CW, ox+12, 11, ox+13, 13, IRON)
    # Lid tilted open (shifted up 3 rows, slight slant)
    fill(px, CW, ox+1, 0, ox+12, 2, LID_M)
    hline(px, CW, ox+1, ox+12, 0, LID_L)
    vline(px, CW, ox+1, 0, 2, GOLD)
    vline(px, CW, ox+12, 0, 2, GOLD)
    hline(px, CW, ox+2, ox+11, 0, GOLD)
    hline(px, CW, ox+2, ox+11, 2, GOLD)
    # Inside cavity (dark)
    fill(px, CW, ox+1, 3, ox+12, 6, WD_D)
    # Gold glint items inside
    put(px, CW, ox+3, 4, GOLD); put(px, CW, ox+7, 3, GLINT)
    put(px, CW, ox+10, 5, GOLD); put(px, CW, ox+5, 5, GLINT)
    put(px, CW, ox+9, 4, GOLD_D)

    outline_shape(px, CW, CH)
    write_png("sprites/chest_sheet.png", px, CW, CH)
    print(f"Wrote sprites/chest_sheet.png  ({CW}×{CH})")

make_chest_sheet()


# =============================================================================
# BARREL SPRITE  12×16 px
# =============================================================================
def make_barrel_sprite():
    BW, BH = 12, 16
    px = blank(BW, BH)

    STV_D = ( 72,  46,  16, 255)  # dark stave
    STV_M = (108,  72,  26, 255)  # mid stave
    STV_L = (148, 102,  40, 255)  # light stave
    STV_H = (178, 130,  58, 255)  # highlight
    SHD   = ( 46,  28,   8, 255)  # right shadow
    BAND  = ( 62,  56,  50, 255)  # iron band
    BAND_L= ( 94,  86,  76, 255)  # iron band highlight
    TOP_M = ( 88,  58,  18, 255)  # top oval mid
    TOP_L = (118,  82,  30, 255)  # top oval light

    # Barrel body — oval profile using widths
    widths = [4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 4, 3, 0]
    for y, hw in enumerate(widths):
        if hw == 0:
            continue
        x0 = (BW - hw * 2) // 2
        x1 = BW - 1 - x0
        hline(px, BW, x0, x1, y, STV_M)
        put(px, BW, x0, y, STV_D)      # left shadow edge
        put(px, BW, x1, y, SHD)        # right shadow edge
        if x0 + 1 <= x1 - 1:
            put(px, BW, x0 + 1, y, STV_L)  # highlight left of centre
        if y < 3:
            hline(px, BW, x0+1, x0+2, y, STV_H)  # top highlight

    # Top oval face (y=0..2 approximate)
    hline(px, BW, 2, 9, 0, TOP_L)
    hline(px, BW, 2, 9, 1, TOP_M)

    # Two iron bands
    for ry in [3, 10]:
        hline(px, BW, 1, BW-2, ry, BAND)
        hline(px, BW, 1, BW-2, ry+1, BAND)
        put(px, BW, 2, ry, BAND_L); put(px, BW, 3, ry, BAND_L)

    # Vertical stave lines (2 lines creating 3 staves)
    for sx in [4, 8]:
        for y in range(2, 15):
            c = px[y * BW + sx]
            if c[3] > 0 and c != BAND and c != BAND_L:
                put(px, BW, sx, y, STV_D)

    outline_shape(px, BW, BH)
    write_png("sprites/barrel_sprite.png", px, BW, BH)
    print(f"Wrote sprites/barrel_sprite.png  ({BW}×{BH})")

make_barrel_sprite()


# =============================================================================
# CURTAIN SPRITE  18×24 px
# =============================================================================
def make_curtain_sprite():
    CRW, CRH = 18, 24
    px = blank(CRW, CRH)

    # Mid-purple base tones (GDScript will modulate colour)
    ROD_D = ( 40,  36,  32, 255)   # iron rod
    ROD_L = ( 72,  66,  58, 255)
    CRT_D = ( 54,  34,  86, 255)   # curtain fold dark
    CRT_M = ( 90,  58, 140, 255)   # curtain fold mid
    CRT_L = (130,  90, 188, 255)   # curtain fold front
    CRT_H = (160, 120, 220, 255)   # fold highlight
    HEM_D = ( 42,  26,  66, 255)
    HEM_M = ( 70,  46, 108, 255)

    # Rod at top (y=0..1)
    hline(px, CRW, 0, CRW-1, 0, ROD_D)
    hline(px, CRW, 0, CRW-1, 1, ROD_L)
    # Ring hooks on rod
    for rx in [2, 8, 14]:
        put(px, CRW, rx, 1, ROD_D)

    # Three fabric folds — each fold is ~6px wide
    # Fold 1 (x 0..5): dark left edge, light front, dark right edge
    fill(px, CRW, 0, 2, 1, 21, CRT_D)
    fill(px, CRW, 2, 2, 4, 21, CRT_L)
    put(px, CRW, 2, 2, CRT_H); put(px, CRW, 3, 2, CRT_H)
    vline(px, CRW, 5, 2, 21, CRT_M)

    # Fold 2 (x 6..11)
    fill(px, CRW, 6, 2, 7, 21, CRT_D)
    fill(px, CRW, 8, 2, 10, 21, CRT_L)
    put(px, CRW, 8, 2, CRT_H); put(px, CRW, 9, 2, CRT_H)
    vline(px, CRW, 11, 2, 21, CRT_M)

    # Fold 3 (x 12..17)
    fill(px, CRW, 12, 2, 13, 21, CRT_D)
    fill(px, CRW, 14, 2, 16, 21, CRT_L)
    put(px, CRW, 14, 2, CRT_H); put(px, CRW, 15, 2, CRT_H)
    fill(px, CRW, 17, 2, CRW-1, 21, CRT_M)

    # Fold wrinkle lines (horizontal shadow hints)
    for wy in [8, 14]:
        hline(px, CRW, 1, CRW-2, wy, CRT_D)

    # Hem at bottom (y=22..23)
    hline(px, CRW, 0, CRW-1, 22, HEM_M)
    hline(px, CRW, 0, CRW-1, 23, HEM_D)
    # Small scallops on hem
    for hx in [3, 9, 15]:
        put(px, CRW, hx, 22, CRT_L)

    outline_shape(px, CRW, CRH)
    write_png("sprites/curtain_sprite.png", px, CRW, CRH)
    print(f"Wrote sprites/curtain_sprite.png  ({CRW}×{CRH})")

make_curtain_sprite()

print("Done.")

