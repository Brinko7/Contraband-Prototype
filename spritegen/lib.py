"""
Shared pixel-art toolkit for the Contraband sprite pipeline.
Pure stdlib (struct + zlib) — no PIL/numpy required.

Style target: elite SNES (Final Fantasy VI / Secret of Mana). Key rules the
helpers encode:
  * Hard dark outline around every silhouette (call Canvas.auto_outline()).
  * 4-5 tone shading ramp per material (base + 2 shadows + 1-2 highlights).
  * Light comes from the UPPER-LEFT — highlights on top-left faces, core
    shadow on bottom-right, plus a thin rim/bounce light on the lower-right.
  * Limited, harmonious palette (use PAL below; nudge with ramp()).
  * Ordered dithering for soft gradients between two tones.

A Canvas is an RGBA pixel buffer. Colors are (r, g, b, a) tuples, 0-255.
"""
import struct, zlib, os, math

# ── PNG writer ────────────────────────────────────────────────────────────────

def _chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

def write_png(path, px, w, h):
    """px is a flat list of (r,g,b,a) length w*h, row-major top-to-bottom."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b, a = px[y * w + x]
            raw += bytes((r & 255, g & 255, b & 255, a & 255))
    sig  = b"\x89PNG\r\n\x1a\n"
    ihdr = _chunk(b"IHDR", struct.pack(">II", w, h) + bytes([8, 6, 0, 0, 0]))
    idat = _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    iend = _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(sig + ihdr + idat + iend)

# ── Color helpers ─────────────────────────────────────────────────────────────

T = (0, 0, 0, 0)                 # transparent
OUTLINE = (20, 14, 22, 255)      # near-black violet outline (warmer than pure black)

def _cl(v): return max(0, min(255, int(round(v))))

def rgb(r, g, b, a=255):
    return (_cl(r), _cl(g), _cl(b), _cl(a))

def lighten(c, amt):
    """amt 0..1 toward white."""
    r, g, b, a = c
    return (_cl(r + (255 - r) * amt), _cl(g + (255 - g) * amt), _cl(b + (255 - b) * amt), a)

def darken(c, amt):
    """amt 0..1 toward black."""
    r, g, b, a = c
    return (_cl(r * (1 - amt)), _cl(g * (1 - amt)), _cl(b * (1 - amt)), a)

def mix(c1, c2, t):
    return (_cl(c1[0] + (c2[0]-c1[0])*t), _cl(c1[1] + (c2[1]-c1[1])*t),
            _cl(c1[2] + (c2[2]-c1[2])*t), _cl(c1[3] + (c2[3]-c1[3])*t))

def shift_hue_warm(c, amt):
    """Push a color warmer (amt>0) or cooler (amt<0) — handy for torch grading."""
    r, g, b, a = c
    return (_cl(r + 30*amt), _cl(g + 8*amt), _cl(b - 24*amt), a)

def ramp(base, n=5):
    """Return an n-tone shading ramp [darkest ... base ... lightest].
    Shadows cool slightly, highlights warm slightly — SNES convention."""
    out = []
    half = (n - 1) // 2
    for i in range(n):
        d = i - half
        if d < 0:
            c = darken(base, -d * 0.27)
            c = mix(c, (38, 46, 86, c[3]), 0.14)      # cool the shadows
        elif d > 0:
            c = lighten(base, d * 0.30)
            c = mix(c, (255, 238, 198, c[3]), 0.10)   # warm the highlights
        else:
            c = base
        out.append(c)
    return out

# ── Curated palette (reuse for harmony across all sheets) ─────────────────────

PAL = {
    # skin
    "skin_pale":   rgb(232, 196, 160), "skin_tan": rgb(206, 158, 116),
    "skin_dark":   rgb(150, 102, 70),  "skin_grey": rgb(176, 188, 180),
    "skin_green":  rgb(150, 176, 110),
    # leather / cloth
    "leather":     rgb(108, 72, 38),   "leather_dk": rgb(70, 44, 22),
    "cloth_blue":  rgb(56, 70, 120),   "cloth_purple": rgb(78, 48, 116),
    "cloth_black": rgb(38, 34, 48),    "cloth_red":  rgb(150, 40, 44),
    "cloth_grey":  rgb(86, 86, 98),
    # metal
    "steel":       rgb(168, 174, 190), "steel_dk":  rgb(96, 100, 118),
    "iron":        rgb(96, 98, 110),   "gold":      rgb(226, 184, 70),
    "gold_dk":     rgb(160, 116, 36),  "bronze":    rgb(170, 110, 58),
    # stone (per-floor)
    "sand":        rgb(196, 168, 116), "sand_dk":   rgb(146, 120, 78),
    "slate":       rgb(96, 110, 128),  "slate_dk":  rgb(58, 70, 88),
    "obsidian":    rgb(70, 58, 86),    "obsidian_dk": rgb(40, 32, 54),
    "grout":       rgb(44, 38, 34),
    # misc
    "wood":        rgb(120, 80, 42),   "wood_dk":   rgb(78, 50, 26),
    "wood_lt":     rgb(158, 112, 64),
    "flame":       rgb(255, 196, 70),  "flame_hot": rgb(255, 240, 180),
    "flame_dk":    rgb(214, 110, 30),
    "gem_blue":    rgb(80, 180, 230),  "gem_red":   rgb(230, 70, 80),
    "gem_green":   rgb(90, 210, 130),  "gem_purple": rgb(180, 110, 230),
    "bone":        rgb(224, 218, 196),
}

# ── Canvas ────────────────────────────────────────────────────────────────────

class Canvas:
    def __init__(self, w, h, fill=T):
        self.w = w
        self.h = h
        self.px = [fill] * (w * h)

    def inb(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def get(self, x, y):
        if not self.inb(x, y):
            return T
        return self.px[y * self.w + x]

    def put(self, x, y, c, blend=True):
        if not self.inb(x, y):
            return
        if c[3] == 0:
            return
        if blend and c[3] < 255:
            d = self.px[y * self.w + x]
            a = c[3] / 255.0
            self.px[y * self.w + x] = (
                _cl(c[0]*a + d[0]*(1-a)), _cl(c[1]*a + d[1]*(1-a)),
                _cl(c[2]*a + d[2]*(1-a)), max(d[3], c[3]))
        else:
            self.px[y * self.w + x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.put(xx, yy, c)

    def frame(self, x, y, w, h, c):
        self.hline(x, x + w - 1, y, c)
        self.hline(x, x + w - 1, y + h - 1, c)
        self.vline(x, y, y + h - 1, c)
        self.vline(x + w - 1, y, y + h - 1, c)

    def hline(self, x0, x1, y, c):
        if x1 < x0: x0, x1 = x1, x0
        for x in range(x0, x1 + 1):
            self.put(x, y, c)

    def vline(self, x, y0, y1, c):
        if y1 < y0: y0, y1 = y1, y0
        for y in range(y0, y1 + 1):
            self.put(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        dx = abs(x1 - x0); dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.put(x0, y0, c)
            if x0 == x1 and y0 == y1: break
            e2 = 2 * err
            if e2 >= dy: err += dy; x0 += sx
            if e2 <= dx: err += dx; y0 += sy

    def disc(self, cx, cy, r, c):
        rr = r * r + r * 0.4
        for yy in range(int(cy - r - 1), int(cy + r + 2)):
            for xx in range(int(cx - r - 1), int(cx + r + 2)):
                if (xx - cx) ** 2 + (yy - cy) ** 2 <= rr:
                    self.put(xx, yy, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for yy in range(int(cy - ry - 1), int(cy + ry + 2)):
            for xx in range(int(cx - rx - 1), int(cx + rx + 2)):
                if rx > 0 and ry > 0 and ((xx-cx)/rx)**2 + ((yy-cy)/ry)**2 <= 1.0:
                    self.put(xx, yy, c)

    def fill_ellipse_shaded(self, cx, cy, rx, ry, ramp_cols, light=(-0.5, -0.6)):
        """Draw a sphere-ish form lit from `light` direction using a ramp."""
        n = len(ramp_cols)
        lx, ly = light
        ln = math.hypot(lx, ly) or 1
        lx, ly = lx/ln, ly/ln
        for yy in range(int(cy - ry - 1), int(cy + ry + 2)):
            for xx in range(int(cx - rx - 1), int(cx + rx + 2)):
                nx = (xx - cx) / rx if rx else 0
                ny = (yy - cy) / ry if ry else 0
                if nx*nx + ny*ny <= 1.0:
                    d = nx*lx + ny*ly            # -1 lit .. +1 shadow
                    idx = int(round((1 - (d + 1) / 2) * (n - 1)))
                    idx = max(0, min(n - 1, idx))
                    self.put(xx, yy, ramp_cols[idx])

    def dither(self, x, y, w, h, c, density=0.5):
        """Ordered 2x2 dither of color c over a region (for soft gradients)."""
        bayer = [[0, 2], [3, 1]]
        thr = density * 4
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if bayer[yy & 1][xx & 1] < thr:
                    self.put(xx, yy, c)

    def auto_outline(self, color=OUTLINE, diag=False):
        """Add a 1px outline around every opaque cluster (transparent edge cells)."""
        adds = []
        nb = [(-1,0),(1,0),(0,-1),(0,1)]
        if diag: nb += [(-1,-1),(1,-1),(-1,1),(1,1)]
        for y in range(self.h):
            for x in range(self.w):
                if self.get(x, y)[3] != 0:
                    continue
                for dx, dy in nb:
                    if self.get(x+dx, y+dy)[3] >= 200:
                        adds.append((x, y)); break
        for x, y in adds:
            self.put(x, y, color, blend=False)

    def drop_shadow(self, cx, cy, rx, ry, alpha=110):
        self.ellipse(cx, cy, rx, ry, (0, 0, 0, alpha))

    def blit(self, dst, ox, oy):
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y * self.w + x]
                if c[3]:
                    dst.put(ox + x, oy + y, c, blend=False)

    def scaled(self, f):
        """Nearest-neighbour upscale by integer factor f (for previews)."""
        out = Canvas(self.w * f, self.h * f)
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y * self.w + x]
                for dy in range(f):
                    for dx in range(f):
                        out.px[(y*f+dy)*out.w + (x*f+dx)] = c
        return out


def save_preview(canvas, path, factor=6, checker=True):
    """Write an upscaled preview with a checker background so transparency reads."""
    src = canvas
    if checker:
        bg = Canvas(src.w, src.h)
        for y in range(src.h):
            for x in range(src.w):
                base = (90,90,96,255) if ((x>>1)+(y>>1)) & 1 else (60,60,66,255)
                bg.px[y*src.w+x] = base
        for y in range(src.h):
            for x in range(src.w):
                c = src.px[y*src.w+x]
                if c[3]:
                    bg.put(x, y, c)
        src = bg
    up = src.scaled(factor)
    write_png(path, up.px, up.w, up.h)


# ── Sheet assembly ────────────────────────────────────────────────────────────

class Sheet:
    """A grid of equal cells. Build cells as Canvas, place by (col,row)."""
    def __init__(self, cols, rows, cw, ch, pad=0):
        self.cols, self.rows = cols, rows
        self.cw, self.ch, self.pad = cw, ch, pad
        self.W = cols * (cw + pad) - (pad if pad else 0)
        self.H = rows * (ch + pad) - (pad if pad else 0)
        self.canvas = Canvas(self.W, self.H, T)

    def place(self, col, row, cell):
        cell.blit(self.canvas, col * (self.cw + self.pad), row * (self.ch + self.pad))

    def save(self, path):
        write_png(path, self.canvas.px, self.canvas.W, self.canvas.H)
        return (self.canvas.W, self.canvas.H)
