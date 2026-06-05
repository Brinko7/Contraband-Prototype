extends Node2D

const TILE_SIZE := 16
const WALL      := 1
const FLOOR     := 0

const MAP_COLS  := 48
const MAP_ROWS  := 36

# ── Zone colour palettes ───────────────────────────────────────────────────────
var C_FLOOR_VAULT_A  := Color(0.095, 0.085, 0.130)
var C_FLOOR_VAULT_B  := Color(0.115, 0.100, 0.160)
var C_FLOOR_MID_A    := Color(0.085, 0.095, 0.085)
var C_FLOOR_MID_B    := Color(0.105, 0.115, 0.100)
var C_FLOOR_ENTRY_A  := Color(0.115, 0.095, 0.075)
var C_FLOOR_ENTRY_B  := Color(0.135, 0.110, 0.088)

var C_WALL_VAULT     := Color(0.22, 0.17, 0.30)
var C_WALL_VAULT_E   := Color(0.36, 0.28, 0.48)
var C_WALL_MID       := Color(0.26, 0.21, 0.17)
var C_WALL_MID_E     := Color(0.40, 0.32, 0.24)
var C_WALL_ENTRY     := Color(0.30, 0.23, 0.17)
var C_WALL_ENTRY_E   := Color(0.44, 0.35, 0.25)

# ── Torch sconce positions (world-pixel centres) ───────────────────────────────
const TORCHES: Array[Vector2] = [
	# Vault — three across north face
	Vector2(240,  24),
	Vector2(384,  24),
	Vector2(528,  24),
	# Captain's Office — two: north wall, south-east corner
	Vector2( 80, 140),
	Vector2(216, 270),
	# Antechamber — one center north
	Vector2(408, 140),
	# Armory — two: north, east wall
	Vector2(636, 140),
	Vector2(700, 252),
	# Barracks — north-west and south-center
	Vector2( 72, 316),
	Vector2(216, 442),
	# Storeroom — north-east
	Vector2(660, 316),
	# Entry Foyer — flanking center
	Vector2(300, 494),
	Vector2(468, 494),
]

const ROOM_TILE_RECTS: Array[Rect2i] = [
	Rect2i(11, 30, 26,  5),   # Entry Foyer
	Rect2i( 1, 19, 19, 10),   # Barracks
	Rect2i(27, 19, 19, 10),   # Storeroom
	Rect2i( 1,  8, 16, 10),   # Captain's Office
	Rect2i(19,  8, 13, 10),   # Antechamber
	Rect2i( 6,  1, 36,  6),   # The Vault
	Rect2i(35,  8, 11, 10),   # Armory
]

var map: Array = []

var visited_rooms: Array[bool] = [true, false, false, false, false, false, false]

var _t: float = 0.0
var _tileset: Texture2D = null

var _tex_booth:  Texture2D = null
var _tex_crate:  Texture2D = null
var _tex_board:  Texture2D = null
var _tex_bed:    Texture2D = null
var _tex_table:  Texture2D = null
var _tex_bench:  Texture2D = null
var _tex_rack:   Texture2D = null
var _tex_plinth: Texture2D = null
var _tex_altar:  Texture2D = null

func _ready():
	add_to_group("levelmap")
	_tileset    = null
	_tex_booth  = null; _tex_crate = null; _tex_board = null
	_tex_bed    = null; _tex_table = null; _tex_bench = null
	_tex_rack   = null; _tex_plinth = null; _tex_altar = null
	_apply_floor_theme()
	_build_map()
	_randomize_cover()
	_build_collision()
	_build_furniture_collision()

func _process(delta):
	_t += delta
	_update_fog()
	queue_redraw()

# ── Map construction ──────────────────────────────────────────────────────────
func _build_map():
	map = []
	for r in range(MAP_ROWS):
		var row: Array = []
		for c in range(MAP_COLS):
			row.append(WALL)
		map.append(row)

	# ── Vault (top, grand & wide) ────────────────────────────────────────────
	_carve(Rect2i( 6,  1, 36,  6))   # The Vault: cols 6-41, rows 1-6
	_carve(Rect2i( 8,  6,  3,  3))   # Vault-West corridor (3-wide)
	_carve(Rect2i(25,  6,  3,  3))   # Vault-East corridor (3-wide)

	# ── Upper tier ───────────────────────────────────────────────────────────
	_carve(Rect2i( 1,  8, 16, 10))   # Captain's Office: cols 1-16, rows 8-17
	_carve(Rect2i(19,  8, 13, 10))   # Antechamber: cols 19-31, rows 8-17
	_carve(Rect2i(35,  8, 11, 10))   # Armory: cols 35-45, rows 8-17

	# ── Upper corridors (all 3-4 tiles wide, furniture-proof) ────────────────
	_carve(Rect2i(16, 10,  4,  6))   # Office → Antechamber (4-wide)
	_carve(Rect2i(31, 10,  5,  6))   # Antechamber → Armory (5-wide)

	# ── Vertical passages to lower tier (3-wide) ─────────────────────────────
	_carve(Rect2i( 7, 17,  3,  3))   # Office → Barracks
	_carve(Rect2i(36, 17,  3,  3))   # Armory → Storeroom

	# ── Lower tier ───────────────────────────────────────────────────────────
	_carve(Rect2i( 1, 19, 19, 10))   # Barracks: cols 1-19, rows 19-28
	_carve(Rect2i(27, 19, 19, 10))   # Storeroom: cols 27-45, rows 19-28

	# ── Vertical corridors to Entry Foyer (3-wide) ───────────────────────────
	_carve(Rect2i(14, 28,  3,  3))   # Barracks → Entry
	_carve(Rect2i(31, 28,  3,  3))   # Storeroom → Entry

	# ── Entry Foyer (bottom, wide & grand) ───────────────────────────────────
	_carve(Rect2i(11, 30, 26,  5))   # Entry Foyer: cols 11-36, rows 30-34

func _carve(rect: Rect2i):
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			if r >= 0 and r < MAP_ROWS and c >= 0 and c < MAP_COLS:
				map[r][c] = FLOOR

func _randomize_cover():
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.run_seed + GameManager.current_floor * 31337

	# Vault — decorative corner alcoves, clear of vault corridors (cols 8-10, 25-27)
	var vpillars := [Vector2i(14, 2), Vector2i(18, 3), Vector2i(32, 2), Vector2i(36, 3)]
	for p in vpillars:
		if rng.randi_range(0, 2) != 0:
			if p.y > 0 and p.y < MAP_ROWS - 1 and p.x > 0 and p.x < MAP_COLS - 1:
				map[p.y][p.x] = WALL

	# Captain's Office — clear of north corridor (cols 7-9) and east passage (col 16+)
	var capillars := [Vector2i(3, 10), Vector2i(10, 14)]
	for p in capillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Antechamber — clear of corridors on west (cols 16-19) and east (cols 31-35)
	var antipillars := [Vector2i(21, 14), Vector2i(28, 14)]
	for p in antipillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Barracks — clear of north passage (cols 7-9) and south corridor (cols 14-16)
	var bpillars := [Vector2i(2, 22), Vector2i(9, 25), Vector2i(16, 22)]
	for p in bpillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Storeroom — clear of north passage (cols 36-38) and south corridor (cols 31-33)
	var spillars := [Vector2i(29, 22), Vector2i(40, 25), Vector2i(43, 22)]
	for p in spillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Entry Foyer — clear of north corridors (cols 14-16 and 31-33)
	var epillars := [Vector2i(18, 31), Vector2i(28, 31)]
	for p in epillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

func _place_pillar(col: int, row: int):
	for dr in range(2):
		for dc in range(2):
			var r := row + dr
			var c := col + dc
			if r > 0 and r < MAP_ROWS - 1 and c > 0 and c < MAP_COLS - 1:
				map[r][c] = WALL

func _build_collision():
	var body := StaticBody2D.new()
	body.name = "Walls"
	add_child(body)
	for row in range(map.size()):
		var col := 0
		while col < map[row].size():
			if map[row][col] == WALL:
				var run_start := col
				while col < map[row].size() and map[row][col] == WALL:
					col += 1
				var run_len := col - run_start
				var shape   := CollisionShape2D.new()
				var rect    := RectangleShape2D.new()
				rect.size      = Vector2(TILE_SIZE * run_len, TILE_SIZE)
				shape.shape    = rect
				shape.position = Vector2(
					(run_start + run_len * 0.5) * TILE_SIZE,
					(row + 0.5) * TILE_SIZE)
				body.add_child(shape)
			else:
				col += 1

# ── Fog of war ────────────────────────────────────────────────────────────────
func _update_fog():
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var tc := Vector2i(
		int(player.global_position.x / TILE_SIZE),
		int(player.global_position.y / TILE_SIZE))
	var idx := _tile_to_room(tc)
	if idx >= 0 and idx < visited_rooms.size():
		visited_rooms[idx] = true

func _tile_to_room(tc: Vector2i) -> int:
	if tc.y >= 30 and tc.y <= 34 and tc.x >= 11 and tc.x <= 36: return 0  # Entry Foyer
	if tc.y >= 19 and tc.y <= 28 and tc.x >=  1 and tc.x <= 19: return 1  # Barracks
	if tc.y >= 19 and tc.y <= 28 and tc.x >= 27 and tc.x <= 45: return 2  # Storeroom
	if tc.y >=  8 and tc.y <= 17 and tc.x >=  1 and tc.x <= 16: return 3  # Captain's Office
	if tc.y >=  8 and tc.y <= 17 and tc.x >= 19 and tc.x <= 31: return 4  # Antechamber
	if tc.y >=  1 and tc.y <=  6 and tc.x >=  6 and tc.x <= 41: return 5  # The Vault
	if tc.y >=  8 and tc.y <= 17 and tc.x >= 35 and tc.x <= 45: return 6  # Armory
	return -1

# ── Zone helpers ──────────────────────────────────────────────────────────────
func _get_zone(row: int) -> int:
	if row <=  7: return 0
	if row <= 29: return 1
	return 2

func _apply_floor_theme():
	match GameManager.current_floor:
		1:  # Warm sandstone cellar
			C_FLOOR_VAULT_A  = Color(0.10, 0.08, 0.05); C_FLOOR_VAULT_B  = Color(0.12, 0.10, 0.06)
			C_FLOOR_MID_A    = Color(0.09, 0.07, 0.05); C_FLOOR_MID_B    = Color(0.11, 0.09, 0.06)
			C_FLOOR_ENTRY_A  = Color(0.10, 0.08, 0.05); C_FLOOR_ENTRY_B  = Color(0.12, 0.10, 0.06)
			C_WALL_VAULT     = Color(0.72, 0.58, 0.38); C_WALL_VAULT_E   = Color(0.88, 0.72, 0.50)
			C_WALL_MID       = Color(0.62, 0.50, 0.34); C_WALL_MID_E     = Color(0.78, 0.62, 0.44)
			C_WALL_ENTRY     = Color(0.65, 0.52, 0.35); C_WALL_ENTRY_E   = Color(0.82, 0.66, 0.46)
		2:  # Dark slate dungeon
			C_FLOOR_VAULT_A  = Color(0.07, 0.06, 0.10); C_FLOOR_VAULT_B  = Color(0.09, 0.08, 0.13)
			C_FLOOR_MID_A    = Color(0.07, 0.08, 0.07); C_FLOOR_MID_B    = Color(0.09, 0.10, 0.08)
			C_FLOOR_ENTRY_A  = Color(0.08, 0.07, 0.06); C_FLOOR_ENTRY_B  = Color(0.10, 0.09, 0.07)
			C_WALL_VAULT     = Color(0.42, 0.38, 0.62); C_WALL_VAULT_E   = Color(0.58, 0.52, 0.82)
			C_WALL_MID       = Color(0.50, 0.46, 0.40); C_WALL_MID_E     = Color(0.68, 0.62, 0.54)
			C_WALL_ENTRY     = Color(0.55, 0.48, 0.38); C_WALL_ENTRY_E   = Color(0.72, 0.62, 0.50)
		_:  # Deep obsidian fortress
			C_FLOOR_VAULT_A  = Color(0.05, 0.05, 0.08); C_FLOOR_VAULT_B  = Color(0.07, 0.07, 0.11)
			C_FLOOR_MID_A    = Color(0.06, 0.06, 0.07); C_FLOOR_MID_B    = Color(0.08, 0.08, 0.09)
			C_FLOOR_ENTRY_A  = Color(0.06, 0.06, 0.07); C_FLOOR_ENTRY_B  = Color(0.08, 0.08, 0.09)
			C_WALL_VAULT     = Color(0.38, 0.42, 0.72); C_WALL_VAULT_E   = Color(0.52, 0.58, 0.90)
			C_WALL_MID       = Color(0.40, 0.42, 0.52); C_WALL_MID_E     = Color(0.56, 0.58, 0.72)
			C_WALL_ENTRY     = Color(0.42, 0.42, 0.50); C_WALL_ENTRY_E   = Color(0.58, 0.58, 0.68)

# ── Drawing ───────────────────────────────────────────────────────────────────
func _draw():
	var font: Font = ThemeDB.fallback_font
	var map_w: float = MAP_COLS * TILE_SIZE
	var map_h: float = MAP_ROWS * TILE_SIZE
	var floor_id: int = GameManager.current_floor

	# Floor tiles — depth, mortar, cracks, arcane glow
	for row in range(map.size()):
		for col in range(map[row].size()):
			if map[row][col] != FLOOR:
				continue
			var x: float = float(col * TILE_SIZE)
			var y: float = float(row * TILE_SIZE)
			var zone: int = _get_zone(row)
			_draw_floor_tile(x, y, col, row, zone, floor_id)

	# Torch glow pools (behind walls)
	for i in range(TORCHES.size()):
		var tp: Vector2 = TORCHES[i]
		if _is_torch_lit(tp):
			_draw_torch_glow(tp, i)

	# Wall tiles — 3/4 perspective stone blocks
	for row in range(map.size()):
		for col in range(map[row].size()):
			if map[row][col] != WALL:
				continue
			var x: float = float(col * TILE_SIZE)
			var y: float = float(row * TILE_SIZE)
			var zone: int = _get_zone(row)
			var has_floor_south: bool = (row + 1 < map.size() and map[row + 1][col] == FLOOR)
			var has_floor_north: bool = (row > 0 and map[row - 1][col] == FLOOR)
			_draw_wall_tile(x, y, col, row, zone, floor_id, has_floor_south, has_floor_north)

	# Drop shadows from walls onto floor below
	for row in range(map.size()):
		for col in range(map[row].size()):
			if map[row][col] == WALL and row + 1 < map.size() and map[row + 1][col] == FLOOR:
				var sx: float = float(col * TILE_SIZE)
				var sy: float = float((row + 1) * TILE_SIZE)
				draw_rect(Rect2(sx, sy, TILE_SIZE, 3), Color(0, 0, 0, 0.38))
				draw_rect(Rect2(sx, sy + 3, TILE_SIZE, 2), Color(0, 0, 0, 0.20))

	# Furniture
	_draw_room_furniture()

	# Zone labels
	_draw_zone_labels(font)

	# Torch flames — multi-layer
	for i in range(TORCHES.size()):
		var tp: Vector2 = TORCHES[i]
		if not _is_torch_lit(tp):
			continue
		_draw_torch_flame(tp, i)

	# Edge vignette
	var vw: float = 40.0
	draw_rect(Rect2(0,           0,      vw,     map_h), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(map_w - vw,  0,      vw,     map_h), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(0,           0,      map_w,  vw),    Color(0, 0, 0, 0.22))
	draw_rect(Rect2(0,           map_h - vw, map_w, vw), Color(0, 0, 0, 0.22))

	# Heat vignette
	var heat: int = GameManager.floor_heat_level
	if heat > 0:
		var heat_a: float = clamp(heat * 0.04, 0.0, 0.28)
		var pulse:  float = abs(sin(_t * 1.5)) * heat_a * 0.35
		draw_rect(Rect2(0, 0, map_w, map_h), Color(0.9, 0.1, 0.05, heat_a + pulse))

	# Zone divider tint strips
	var vault_y: float = 8 * TILE_SIZE
	draw_rect(Rect2(0, vault_y - 3, map_w, 3), Color(0.22, 0.10, 0.35, 0.22))
	var bar_y: float = 19 * TILE_SIZE
	draw_rect(Rect2(0, bar_y - 3, map_w, 3), Color(0.10, 0.25, 0.12, 0.22))
	var entry_y: float = 30 * TILE_SIZE
	draw_rect(Rect2(0, entry_y - 3, map_w, 3), Color(0.15, 0.15, 0.25, 0.22))

# ── Iso ellipse helper (returns polygon points for elliptical fills) ─────────
func _iso_ellipse_pts(center: Vector2, rx: float, ry: float, segments: int = 16) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.append(Vector2(center.x + cos(a) * rx, center.y + sin(a) * ry))
	return pts

# ── Floor tile (Hades-style deep charcoal stone) ──────────────────────────────
func _draw_floor_tile(x: float, y: float, c: int, r: int, zone: int, floor_id: int):
	var tile_hash: int = (r * 47 + c * 31) % 100
	# Deep charcoal base, with subtle zone tint mixed in
	var zone_tint: Color
	match zone:
		0: zone_tint = Color(0.04, 0.02, 0.06)   # vault — faintly purple
		1: zone_tint = Color(0.02, 0.03, 0.02)   # mid — faintly green
		_: zone_tint = Color(0.04, 0.03, 0.02)   # entry — faintly warm
	var base: Color = Color(0.10 + zone_tint.r, 0.09 + zone_tint.g, 0.11 + zone_tint.b)
	# Per-tile deterministic shade variation
	var vshade: float = float(tile_hash % 11) * 0.006 - 0.02
	base = Color(
		clamp(base.r + vshade, 0.04, 0.30),
		clamp(base.g + vshade, 0.04, 0.30),
		clamp(base.b + vshade + float(tile_hash % 5) * 0.002, 0.04, 0.32)
	)

	draw_rect(Rect2(x, y, TILE_SIZE, TILE_SIZE), base)

	# Tile seam lines — 1px darker on right + bottom edge (cuts deep)
	var seam: Color = Color(0, 0, 0, 0.55)
	draw_rect(Rect2(x, y + TILE_SIZE - 1, TILE_SIZE, 1), seam)
	draw_rect(Rect2(x + TILE_SIZE - 1, y, 1, TILE_SIZE), seam)
	# Top-left faint highlight (catch-light edge)
	draw_rect(Rect2(x, y, TILE_SIZE, 1), Color(1, 1, 1, 0.035))
	draw_rect(Rect2(x, y, 1, TILE_SIZE), Color(1, 1, 1, 0.025))

	# Occasional subtle crack polygon
	if tile_hash % 20 == 0:
		var cx: float = x + 3.0 + float(tile_hash % 8)
		var cy: float = y + 4.0 + float((tile_hash / 7) % 7)
		var cdir: Vector2 = Vector2(1.0, 0.3).rotated(float(tile_hash) * 0.11)
		var clen: float = 4.0 + float(tile_hash % 5)
		draw_line(Vector2(cx, cy),
			Vector2(cx + cdir.x * clen, cy + cdir.y * clen),
			Color(0, 0, 0, 0.45), 0.7)
		# Fork
		if tile_hash % 40 == 0:
			var cdir2: Vector2 = cdir.rotated(0.6)
			draw_line(Vector2(cx + cdir.x * clen * 0.5, cy + cdir.y * clen * 0.5),
				Vector2(cx + cdir.x * clen * 0.5 + cdir2.x * 2.5,
						cy + cdir.y * clen * 0.5 + cdir2.y * 2.5),
				Color(0, 0, 0, 0.38), 0.5)

	# Tiny grain speck
	if tile_hash % 13 == 5:
		draw_rect(Rect2(x + 4 + float(tile_hash % 7), y + 3 + float(tile_hash % 9), 1, 1),
			Color(0, 0, 0, 0.25))

	# Theme-specific subtle accents
	match floor_id:
		1:
			if tile_hash % 17 == 3:
				draw_circle(Vector2(x + 5 + float(tile_hash % 6), y + 9 + float(tile_hash % 5)),
					0.6, Color(0.85, 0.70, 0.45, 0.16))
		_:
			# Arcane glimmer in dark mode
			if tile_hash % 23 == 1:
				var glowp: float = 0.14 + sin(_t * 1.7 + float(tile_hash) * 0.3) * 0.08
				draw_circle(Vector2(x + 6 + float(tile_hash % 5), y + 8 + float(tile_hash % 4)),
					0.7, Color(0.55, 0.40, 0.95, glowp))

	# Warm overlay for tiles near a torch
	var tcx: float = x + TILE_SIZE * 0.5
	var tcy: float = y + TILE_SIZE * 0.5
	for tp: Vector2 in TORCHES:
		var d2: float = (tp.x - tcx) * (tp.x - tcx) + (tp.y - tcy) * (tp.y - tcy)
		if d2 < 3600.0:  # within 60px
			var falloff: float = 1.0 - sqrt(d2) / 60.0
			falloff = clamp(falloff, 0.0, 1.0)
			var warm_a: float = falloff * falloff * 0.22
			draw_rect(Rect2(x, y, TILE_SIZE, TILE_SIZE),
				Color(1.0, 0.72, 0.25, warm_a))

# ── Wall tile (Hades-style tall imposing stone block) ─────────────────────────
func _draw_wall_tile(x: float, y: float, c: int, r: int, zone: int, floor_id: int, has_floor_south: bool, has_floor_north: bool):
	var cw: Color; var ce: Color
	match zone:
		0: cw = C_WALL_VAULT;  ce = C_WALL_VAULT_E
		1: cw = C_WALL_MID;    ce = C_WALL_MID_E
		_: cw = C_WALL_ENTRY;  ce = C_WALL_ENTRY_E

	var tile_hash: int = (c * 31 + r * 17) % 100
	var v: float = float(tile_hash % 6) * 0.012

	# Hades palette: bright stone front, very dark floor — extreme contrast
	var front_col: Color = Color(
		clamp(cw.r - v * 0.5, 0.05, 1.0),
		clamp(cw.g - v * 0.3, 0.05, 1.0),
		clamp(cw.b - v * 0.2, 0.05, 1.0)
	)
	var top_col: Color = Color(
		clamp(ce.r + 0.10, 0.0, 1.0),
		clamp(ce.g + 0.10, 0.0, 1.0),
		clamp(ce.b + 0.12, 0.0, 1.0)
	)
	var shadow_col: Color = Color(front_col.r * 0.20, front_col.g * 0.18, front_col.b * 0.22)
	var hi_col: Color = front_col.lightened(0.22)

	var top_h: float = 4.0
	# Tall front face — wall feels like you can't see over it
	var front_h: float = 48.0 if has_floor_south else float(TILE_SIZE)

	# TOP face — tile footprint, drawn at y (lighter, suggests looking down at the top of the block)
	draw_rect(Rect2(x, y, TILE_SIZE, TILE_SIZE), top_col)
	# Subtle top highlight strip
	draw_rect(Rect2(x, y, TILE_SIZE, 1), top_col.lightened(0.22))
	# Stone speckles on top face
	if tile_hash % 5 == 0:
		draw_rect(Rect2(x + 3, y + 2, 3, 1), top_col.darkened(0.15))
	if tile_hash % 7 == 2:
		draw_rect(Rect2(x + 9, y + 4, 4, 1), top_col.darkened(0.12))

	# FRONT face — extends downward into the floor tile space below, giving wall depth
	# This is the classic 2.5D trick: wall face drawn over the floor tile to the south
	if has_floor_south:
		var fy: float = y + float(TILE_SIZE)
		draw_rect(Rect2(x, fy, TILE_SIZE, front_h), front_col)

		# Top of front face — brighter seam where top meets front (light hits the corner)
		draw_rect(Rect2(x, fy, TILE_SIZE, 2), front_col.lightened(0.10))
		# Bottom of front face — darkens as it falls into shadow
		draw_rect(Rect2(x, fy + front_h - 4, TILE_SIZE, 4), front_col.darkened(0.22))

		# Horizontal mortar joints
		var joint_col: Color = Color(0, 0, 0, 0.42)
		var jy: float = fy + 16.0
		while jy < fy + front_h - 2:
			draw_line(Vector2(x, jy), Vector2(x + TILE_SIZE, jy), joint_col, 0.8)
			draw_line(Vector2(x, jy + 1), Vector2(x + TILE_SIZE, jy + 1), Color(1, 1, 1, 0.04), 0.5)
			jy += 16.0

		# Vertical mortar joint (stagger by block row for brick offset)
		var block_row: int = int(fy / 16.0)
		if (c + block_row) % 2 == 0:
			draw_line(Vector2(x + 8, fy), Vector2(x + 8, fy + front_h), Color(0, 0, 0, 0.32), 0.7)

		# Dark seam at top of front face (top/front edge)
		draw_line(Vector2(x, fy), Vector2(x + TILE_SIZE, fy), Color(0, 0, 0, 0.70), 1.2)

		# Left shadow strip (wall is darker on left — ambient occlusion)
		draw_rect(Rect2(x, fy, 2, front_h),
			Color(shadow_col.r * 0.6, shadow_col.g * 0.6, shadow_col.b * 0.7, 0.80))
		# Right highlight strip
		draw_rect(Rect2(x + TILE_SIZE - 1, fy, 1, front_h), hi_col)

		# Stone chip details
		if tile_hash % 9 == 3:
			draw_rect(Rect2(x + 3, fy + 6, 2, 2), front_col.darkened(0.28))
		if tile_hash % 11 == 5:
			draw_rect(Rect2(x + TILE_SIZE - 5, fy + 14, 2, 1), front_col.darkened(0.18))
		if tile_hash % 17 == 9 and front_h > 24:
			draw_rect(Rect2(x + 7, fy + 28, 3, 1), front_col.darkened(0.22))

		# Drop shadow on floor just below the wall face
		draw_rect(Rect2(x, fy + front_h, TILE_SIZE, 5),
			Color(0, 0, 0, 0.50))
		draw_rect(Rect2(x, fy + front_h + 5, TILE_SIZE, 4),
			Color(0, 0, 0, 0.25))

		# Warm torch glow on front face
		var wcx: float = x + TILE_SIZE * 0.5
		var wcy: float = fy
		for tp: Vector2 in TORCHES:
			var d2: float = (tp.x - wcx) * (tp.x - wcx) + (tp.y - wcy) * (tp.y - wcy)
			if d2 < 4900.0:
				var falloff: float = 1.0 - sqrt(d2) / 70.0
				falloff = clamp(falloff, 0.0, 1.0)
				var warm_a: float = falloff * falloff * 0.30
				draw_rect(Rect2(x, y, TILE_SIZE, TILE_SIZE), Color(1.0, 0.72, 0.25, warm_a * 0.7))
				draw_rect(Rect2(x, fy, TILE_SIZE, 8), Color(1.0, 0.68, 0.22, warm_a * 0.55))

	# Theme accents
	match floor_id:
		1:
			draw_rect(Rect2(x, y, TILE_SIZE, 1), Color(1.0, 0.78, 0.40, 0.20))
		3:
			if tile_hash % 13 == 7:
				var ap: float = 0.22 + sin(_t * 1.5 + float(tile_hash)) * 0.10
				draw_circle(Vector2(x + 6 + float(tile_hash % 5),
					y + float(TILE_SIZE) + 6 + float(tile_hash % 8)),
					0.7, Color(0.55, 0.40, 0.90, ap))

# ── Torch flame (multi-layer animated) ────────────────────────────────────────
func _draw_torch_flame(tp: Vector2, i: int):
	# Wall bracket (small iron L)
	var br_col: Color = Color(0.20, 0.18, 0.22)
	draw_rect(Rect2(tp.x - 3, tp.y + 2, 6, 2), br_col)
	draw_rect(Rect2(tp.x - 1, tp.y + 4, 2, 4), br_col)
	# Torch handle (tapered grip)
	var grip_col: Color = Color(0.25, 0.15, 0.08)
	var grip_pts: PackedVector2Array = PackedVector2Array([
		Vector2(tp.x - 1.5, tp.y + 1),
		Vector2(tp.x + 1.5, tp.y + 1),
		Vector2(tp.x + 1.2, tp.y - 2),
		Vector2(tp.x - 1.2, tp.y - 2),
	])
	draw_colored_polygon(grip_pts, grip_col)
	draw_line(Vector2(tp.x - 1.2, tp.y - 0.5), Vector2(tp.x + 1.2, tp.y - 0.5),
		Color(0.40, 0.28, 0.15), 0.6)

	var flicker: float = sin(_t * 8.3 + tp.x * 0.07) * 0.25 + sin(_t * 13.1 + i * 1.7) * 0.12
	var flame_pos: Vector2 = Vector2(tp.x, tp.y - 3.5)

	# Outer glow halo
	draw_circle(flame_pos, 5.0 + flicker, Color(1.0, 0.55, 0.08, 0.14))
	draw_circle(flame_pos, 7.5 + flicker * 0.8, Color(1.0, 0.45, 0.05, 0.06))

	# Outer flame polygon (5-vertex teardrop)
	var fl_a: float = 0.80
	var outer_flame: PackedVector2Array = PackedVector2Array([
		Vector2(flame_pos.x, flame_pos.y + 2.5),
		Vector2(flame_pos.x - 2.6 - flicker * 0.4, flame_pos.y + 0.8),
		Vector2(flame_pos.x - 1.4, flame_pos.y - 2.0 - flicker),
		Vector2(flame_pos.x + 0.2, flame_pos.y - 4.2 - flicker * 1.5),
		Vector2(flame_pos.x + 2.0 + flicker * 0.5, flame_pos.y - 0.5),
	])
	draw_colored_polygon(outer_flame, Color(0.98, 0.52, 0.08, fl_a))

	# Mid flame
	var mid_flame: PackedVector2Array = PackedVector2Array([
		Vector2(flame_pos.x, flame_pos.y + 1.6),
		Vector2(flame_pos.x - 1.6, flame_pos.y + 0.3),
		Vector2(flame_pos.x - 0.7, flame_pos.y - 1.4),
		Vector2(flame_pos.x + 0.1, flame_pos.y - 3.0 - flicker),
		Vector2(flame_pos.x + 1.3, flame_pos.y - 0.4),
	])
	draw_colored_polygon(mid_flame, Color(1.0, 0.82, 0.18, 0.90))

	# Inner core
	draw_circle(Vector2(flame_pos.x, flame_pos.y - 0.8), 1.1 + flicker * 0.2,
		Color(1.0, 0.98, 0.85, 0.95))

	# Smoke wisp
	var smoke_y: float = flame_pos.y - 7.0 - abs(sin(_t * 1.3 + i)) * 1.5
	draw_circle(Vector2(flame_pos.x + sin(_t + i) * 1.0, smoke_y),
		1.4, Color(0.30, 0.30, 0.32, 0.15))
	draw_circle(Vector2(flame_pos.x + sin(_t * 0.7 + i) * 1.5, smoke_y - 3.0),
		1.0, Color(0.30, 0.30, 0.32, 0.08))

	# Large floor light pool (iso ellipse — wider than tall to match floor plane)
	var pool_pulse: float = sin(_t * 4.1 + i * 1.3) * 0.05
	draw_colored_polygon(
		_iso_ellipse_pts(Vector2(tp.x, tp.y + 14), 34.0 + pool_pulse * 2.0, 16.0, 20),
		Color(1.0, 0.72, 0.25, 0.10))
	draw_colored_polygon(
		_iso_ellipse_pts(Vector2(tp.x, tp.y + 14), 22.0 + pool_pulse * 1.5, 10.0, 18),
		Color(1.0, 0.68, 0.22, 0.13))
	draw_colored_polygon(
		_iso_ellipse_pts(Vector2(tp.x, tp.y + 12), 12.0, 6.0, 16),
		Color(1.0, 0.85, 0.40, 0.18))

	# Flickering halo around flame (radius pulses)
	var halo_r: float = 9.0 + sin(_t * 7.3 + i) * 1.2
	draw_circle(flame_pos, halo_r, Color(1.0, 0.55, 0.10, 0.10))

# ── Furniture collision ───────────────────────────────────────────────────────
func _build_furniture_collision():
	var body := StaticBody2D.new()
	body.name = "Furniture"
	add_child(body)

	var _add: Callable = func(rect: Rect2):
		var shape := CollisionShape2D.new()
		var rs    := RectangleShape2D.new()
		rs.size        = rect.size
		shape.shape    = rs
		shape.position = rect.get_center()
		body.add_child(shape)

	# Entry Foyer — guard booths
	_add.call(Rect2(196, 490, 20, 26))
	_add.call(Rect2(556, 490, 20, 26))

	# Barracks — beds (5), rack, tables
	for bx: float in [16.0, 48.0, 80.0, 168.0, 200.0]:
		_add.call(Rect2(bx, 308, 26, 22))
	_add.call(Rect2(16, 354, 12, 48))     # weapon rack against west wall
	_add.call(Rect2(48, 406, 148, 16))    # dining tables (merged)

	# Storeroom — crate rows
	for cx: float in [436.0, 464.0, 492.0, 516.0, 648.0, 676.0, 700.0]:
		_add.call(Rect2(cx, 324, 24, 24))
	for cx: float in [436.0, 464.0, 552.0, 660.0, 688.0]:
		_add.call(Rect2(cx, 362, 24, 24))
	for cx: float in [436.0, 576.0, 604.0, 648.0, 676.0]:
		_add.call(Rect2(cx, 400, 24, 24))

	# Captain's Office — desk, bookcase, side table
	_add.call(Rect2(192, 134, 48, 18))    # command desk
	_add.call(Rect2(16, 168, 14, 80))     # bookcase west wall
	_add.call(Rect2(20, 224, 36, 16))     # side records table

	# Antechamber — central meeting table
	_add.call(Rect2(340, 240, 100, 16))

	# Vault — three plinths
	_add.call(Rect2(374, 44, 20, 20))
	_add.call(Rect2(514, 36, 24, 22))
	_add.call(Rect2(182, 36, 24, 22))

	# Armory — racks, crate
	_add.call(Rect2(636, 136, 12, 52))
	_add.call(Rect2(636, 204, 12, 52))
	_add.call(Rect2(600, 196, 28, 24))

# ── Zone labels ──────────────────────────────────────────────────────────────
func _draw_zone_labels(font: Font):
	var loot_name := GameManager.get_main_loot_name()
	var label_col := Color(0.55, 0.50, 0.40, 0.38)
	var loot_col  := Color(0.72, 0.60, 0.28, 0.55)
	var sz := 9
	draw_string(font, Vector2(320, 548), "— THE ENTRY FOYER —",    HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2( 28, 450), "— BARRACKS —",           HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(476, 450), "— STOREROOM —",          HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2( 22, 274), "CAPTAIN'S OFFICE",       HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(330, 274), "ANTECHAMBER",            HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(568, 274), "ARMORY",                 HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(330, 100), "— THE VAULT —",          HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(264,  20), loot_name,                HORIZONTAL_ALIGNMENT_LEFT, -1, sz, loot_col)

# ── Room furniture ────────────────────────────────────────────────────────────
func _draw_room_furniture():
	_draw_entry_furniture()
	_draw_barracks_furniture()
	_draw_storeroom_furniture()
	_draw_captain_furniture()
	_draw_antechamber_furniture()
	_draw_vault_furniture()
	_draw_armory_furniture()

# ─── FURNITURE: BED (3/4 isometric) ───────────────────────────────────────────
func _svg_bed(x: float, y: float, w: float, h: float):
	# Shadow under bed
	draw_rect(Rect2(x - 1, y + h - 1, w + 2, 3), Color(0, 0, 0, 0.35))

	var frame_col: Color = Color(0.30, 0.20, 0.10)
	var frame_top: Color = frame_col.lightened(0.18)
	var mattress_col: Color = Color(0.72, 0.65, 0.52)
	var sheet_col: Color = Color(0.55, 0.30, 0.22)
	var sheet_dark: Color = Color(0.40, 0.20, 0.16)
	var pillow_col: Color = Color(0.92, 0.88, 0.80)
	var pillow_shade: Color = Color(0.78, 0.74, 0.66)

	# Footboard (bottom end, visible as a small front-facing block)
	draw_rect(Rect2(x, y + h - 4, w, 4), frame_col)
	draw_rect(Rect2(x, y + h - 4, w, 1), frame_top)

	# Side rails
	draw_rect(Rect2(x, y + 1, 1.5, h - 4), frame_col)
	draw_rect(Rect2(x + w - 1.5, y + 1, 1.5, h - 4), frame_col)

	# Headboard (taller, at top end)
	draw_rect(Rect2(x - 0.5, y - 2, w + 1, 5), frame_col)
	draw_rect(Rect2(x - 0.5, y - 2, w + 1, 1), frame_top)
	# Headboard ornamental peaks
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + 2, y - 2), Vector2(x + 4, y - 4.5), Vector2(x + 6, y - 2)
	]), frame_col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + w - 6, y - 2), Vector2(x + w - 4, y - 4.5), Vector2(x + w - 2, y - 2)
	]), frame_col)

	# Mattress (slightly inset)
	draw_rect(Rect2(x + 1.5, y + 3, w - 3, h - 8), mattress_col)
	# Top of mattress lighter (lit)
	draw_rect(Rect2(x + 1.5, y + 3, w - 3, 1.5), mattress_col.lightened(0.18))

	# Blanket folded over lower 2/3
	var bl_y: float = y + 3 + (h - 8) * 0.42
	draw_rect(Rect2(x + 1.5, bl_y, w - 3, (h - 8) * 0.58), sheet_col)
	# Blanket top edge highlight
	draw_rect(Rect2(x + 1.5, bl_y, w - 3, 1), sheet_col.lightened(0.18))
	# Blanket wrinkle lines
	draw_line(Vector2(x + 3, bl_y + 2.5), Vector2(x + w - 3, bl_y + 2.5), sheet_dark, 0.5)
	draw_line(Vector2(x + 4, bl_y + 5), Vector2(x + w - 4, bl_y + 5), sheet_dark, 0.5)

	# Pillow at head
	var pw: float = w - 6
	var ph: float = 4.0
	draw_rect(Rect2(x + 3, y + 3, pw, ph), pillow_shade)
	draw_rect(Rect2(x + 3, y + 3, pw, ph - 1), pillow_col)
	# Pillow indent (small darker oval)
	draw_circle(Vector2(x + 3 + pw * 0.5, y + 3 + ph * 0.5), 1.6, pillow_shade)
	# Pillow seam
	draw_line(Vector2(x + 3 + pw * 0.5, y + 3 + 0.5),
		Vector2(x + 3 + pw * 0.5, y + 3 + ph - 0.5),
		Color(0.65, 0.60, 0.52, 0.55), 0.5)

# ─── FURNITURE: CRATE (iconic isometric box) ──────────────────────────────────
func _svg_crate(x: float, y: float, w: float, h: float):
	# Cast shadow
	draw_rect(Rect2(x + 1, y + h, w, 2), Color(0, 0, 0, 0.40))

	var top_col: Color = Color(0.55, 0.38, 0.18).lightened(0.22)
	var front_col: Color = Color(0.52, 0.35, 0.15)
	var side_col: Color = Color(0.52, 0.35, 0.15).darkened(0.32)
	var band_col: Color = Color(0.22, 0.20, 0.24)
	var rivet_col: Color = Color(0.55, 0.55, 0.60)

	# Isometric offsets
	var d: float = 3.0  # depth offset (how much the right/top recedes)
	var th: float = 3.0  # top-face height
	# Top face (parallelogram-ish using polygon)
	var top_poly: PackedVector2Array = PackedVector2Array([
		Vector2(x, y + th),
		Vector2(x + w - d, y),
		Vector2(x + w, y),
		Vector2(x + d, y + th),
	])
	# Simpler — keep aligned-rect approach for clarity
	draw_rect(Rect2(x, y, w, th), top_col)

	# Right side face (narrow trapezoid showing depth)
	var side_poly: PackedVector2Array = PackedVector2Array([
		Vector2(x + w, y),
		Vector2(x + w + d - 1, y + th * 0.6),
		Vector2(x + w + d - 1, y + h),
		Vector2(x + w, y + h),
	])
	draw_colored_polygon(side_poly, side_col)

	# Front face
	draw_rect(Rect2(x, y + th, w, h - th), front_col)

	# Wood grain on front (3 wavy horizontal lines)
	var grain_col: Color = front_col.darkened(0.25)
	for gi in range(3):
		var gy: float = y + th + 2.0 + float(gi) * 3.2
		var px0: float = x + 1
		var px1: float = x + w - 1
		draw_line(Vector2(px0, gy + sin(px0 * 0.3 + gi) * 0.3),
			Vector2(px1, gy + sin(px1 * 0.3 + gi) * 0.3),
			grain_col, 0.5)
	# Grain on side
	for gi in range(2):
		var gy: float = y + th + 2.0 + float(gi) * 4.0
		draw_line(Vector2(x + w, gy + 0.5),
			Vector2(x + w + d - 1, gy + th * 0.3),
			grain_col.darkened(0.10), 0.4)
	# Grain on top
	draw_line(Vector2(x + 2, y + 1), Vector2(x + w - 2, y + 1.5),
		top_col.darkened(0.20), 0.4)
	draw_line(Vector2(x + 2, y + th - 0.8), Vector2(x + w - 2, y + th - 0.5),
		top_col.darkened(0.15), 0.4)

	# Iron bands across front face
	var b1y: float = y + th + 1.0
	var b2y: float = y + h - 2.5
	draw_rect(Rect2(x, b1y, w, 1.2), band_col)
	draw_rect(Rect2(x, b2y, w, 1.2), band_col)
	# Bands continue onto side
	draw_line(Vector2(x + w, b1y + 0.5), Vector2(x + w + d - 1, b1y + 0.5 + th * 0.2),
		band_col, 1.0)
	draw_line(Vector2(x + w, b2y + 0.5), Vector2(x + w + d - 1, b2y + 0.5),
		band_col, 1.0)

	# Corner reinforcements (8 corner squares)
	var cs: float = 1.5
	draw_rect(Rect2(x, y, cs, cs + th), band_col)
	draw_rect(Rect2(x + w - cs, y, cs, cs + th), band_col)
	draw_rect(Rect2(x, y + h - cs, cs, cs), band_col)
	draw_rect(Rect2(x + w - cs, y + h - cs, cs, cs), band_col)

	# Rivets at band intersections
	for ry: float in [b1y + 0.5, b2y + 0.5]:
		draw_circle(Vector2(x + 1.5, ry), 0.7, rivet_col)
		draw_circle(Vector2(x + w - 1.5, ry), 0.7, rivet_col)

	# Lock hasp center front
	var hx: float = x + w * 0.5
	var hy: float = y + h * 0.5 + 0.5
	draw_rect(Rect2(hx - 1.5, hy - 1.2, 3, 2.4), band_col.lightened(0.2))
	draw_arc(Vector2(hx, hy - 1.2), 0.9, PI, TAU, 6, band_col.lightened(0.3), 0.7)

# ─── FURNITURE: TABLE (rustic tavern) ─────────────────────────────────────────
func _svg_table(x: float, y: float, w: float, h: float):
	# Shadow under
	draw_rect(Rect2(x, y + h - 1, w, 2), Color(0, 0, 0, 0.32))

	var dark_wood: Color = Color(0.32, 0.22, 0.10)
	var top_wood: Color = Color(0.50, 0.36, 0.18)
	var top_hi: Color = top_wood.lightened(0.18)
	var edge_wood: Color = Color(0.38, 0.26, 0.12)

	# Legs at four corners (visible front-and-right)
	var leg_w: float = 2.0
	var leg_top_y: float = y + 3.0
	var leg_bot_y: float = y + h - 0.5
	# Front-left leg
	draw_rect(Rect2(x + 0.5, leg_top_y, leg_w, leg_bot_y - leg_top_y), dark_wood)
	# Front-right leg
	draw_rect(Rect2(x + w - leg_w - 0.5, leg_top_y, leg_w, leg_bot_y - leg_top_y), dark_wood)
	# Back legs (slightly inset, partially hidden behind tabletop)
	draw_rect(Rect2(x + 1.5, leg_top_y - 1, leg_w * 0.8, 2), dark_wood.darkened(0.2))
	draw_rect(Rect2(x + w - leg_w * 0.8 - 1.5, leg_top_y - 1, leg_w * 0.8, 2), dark_wood.darkened(0.2))

	# Tabletop — front edge (showing thickness)
	draw_rect(Rect2(x, y + 2.5, w, 1.5), edge_wood)
	# Tabletop top surface
	draw_rect(Rect2(x, y, w, 3), top_wood)
	# Top highlight strip
	draw_rect(Rect2(x, y, w, 0.8), top_hi)
	# Plank seams on top
	draw_line(Vector2(x, y + 1.4), Vector2(x + w, y + 1.4),
		edge_wood.darkened(0.15), 0.5)
	if w > 18:
		draw_line(Vector2(x + w * 0.5, y), Vector2(x + w * 0.5, y + 3),
			edge_wood.darkened(0.15), 0.4)

	# Worn ring stain on top
	draw_arc(Vector2(x + w * 0.32, y + 1.6), 1.4, 0, TAU, 10,
		Color(0.22, 0.14, 0.06, 0.45), 0.5)

	# Candle stub on right side
	if w > 14:
		var cx: float = x + w * 0.72
		var cy: float = y + 1.2
		draw_rect(Rect2(cx - 0.8, cy - 1.8, 1.6, 2.0), Color(0.88, 0.84, 0.70))
		# Wick
		draw_line(Vector2(cx, cy - 1.8), Vector2(cx, cy - 2.6),
			Color(0.15, 0.12, 0.08), 0.6)
		# Flame
		var f: float = sin(_t * 7.0 + x) * 0.2
		draw_circle(Vector2(cx, cy - 3.0 + f * 0.2), 1.2,
			Color(1.0, 0.65, 0.15, 0.85))
		draw_circle(Vector2(cx, cy - 3.0 + f * 0.2), 0.55,
			Color(1.0, 0.95, 0.75, 0.95))
		# Tiny glow on table
		draw_circle(Vector2(cx, cy + 0.4), 3.0,
			Color(1.0, 0.7, 0.2, 0.10))

	# Rolled scroll on left
	if w > 14:
		var sx: float = x + w * 0.18
		var sy: float = y + 1.6
		draw_rect(Rect2(sx - 2.5, sy - 0.6, 5, 1.2), Color(0.85, 0.78, 0.60))
		draw_rect(Rect2(sx - 2.5, sy - 0.6, 5, 0.3), Color(0.95, 0.88, 0.70))
		draw_line(Vector2(sx - 2.5, sy), Vector2(sx + 2.5, sy),
			Color(0.55, 0.48, 0.32), 0.4)

# ─── FURNITURE: BENCH ─────────────────────────────────────────────────────────
func _svg_bench(x: float, y: float, w: float, h: float):
	draw_rect(Rect2(x, y + h, w, 1.5), Color(0, 0, 0, 0.30))

	var wood: Color = Color(0.40, 0.28, 0.14)
	var wood_dk: Color = wood.darkened(0.25)
	var wood_hi: Color = wood.lightened(0.18)

	# Trestle supports — A-frame at ends
	var ts_w: float = 3.0
	var ts_top_y: float = y + 2.0
	var ts_bot_y: float = y + h - 0.5
	# Left trestle
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + 0.5, ts_top_y),
		Vector2(x + ts_w + 0.5, ts_top_y),
		Vector2(x + ts_w * 0.9 + 1.0, ts_bot_y),
		Vector2(x + 0.0, ts_bot_y),
	]), wood_dk)
	# Right trestle
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + w - ts_w - 0.5, ts_top_y),
		Vector2(x + w - 0.5, ts_top_y),
		Vector2(x + w, ts_bot_y),
		Vector2(x + w - ts_w * 0.9 - 1.0, ts_bot_y),
	]), wood_dk)
	# Notch detail
	draw_rect(Rect2(x + 1, ts_bot_y - 1.5, 1.5, 1), wood_dk.darkened(0.2))
	draw_rect(Rect2(x + w - 2.5, ts_bot_y - 1.5, 1.5, 1), wood_dk.darkened(0.2))

	# Seat plank (front edge showing thickness)
	draw_rect(Rect2(x, y + 1.5, w, 1.2), wood.darkened(0.2))
	draw_rect(Rect2(x, y, w, 2), wood)
	draw_rect(Rect2(x, y, w, 0.6), wood_hi)
	# Wear groove
	draw_line(Vector2(x + 1, y + 1.0), Vector2(x + w - 1, y + 1.0),
		wood_hi.darkened(0.05), 0.4)

# ─── FURNITURE: RACK (weapon rack) ────────────────────────────────────────────
func _svg_rack(x: float, y: float, w: float, h: float):
	draw_rect(Rect2(x + 1, y + h, w + 6, 2), Color(0, 0, 0, 0.35))

	var post_col: Color = Color(0.26, 0.18, 0.08)
	var arm_col: Color = Color(0.42, 0.30, 0.14)
	var arm_hi: Color = arm_col.lightened(0.18)
	var iron: Color = Color(0.55, 0.55, 0.60)
	var iron_dk: Color = Color(0.30, 0.30, 0.35)

	# Back post
	draw_rect(Rect2(x, y, w, h), post_col)
	draw_rect(Rect2(x, y, 1, h), post_col.lightened(0.15))
	draw_rect(Rect2(x + w - 1, y, 1, h), post_col.darkened(0.20))
	# Wood grain on post
	for gi in range(3):
		draw_line(Vector2(x + 1, y + 4 + gi * 14),
			Vector2(x + w - 1, y + 4 + gi * 14),
			post_col.darkened(0.25), 0.4)

	# Top cap
	draw_rect(Rect2(x - 1, y - 1, w + 2, 2), post_col.lightened(0.2))

	# Arms protruding forward (right side, since 3/4 view)
	var arms_y: Array[float] = [y + 8.0, y + 20.0, y + 32.0]
	for i in range(arms_y.size()):
		if arms_y[i] > y + h - 4:
			continue
		var ay: float = arms_y[i]
		# Arm
		draw_rect(Rect2(x + w, ay, 5, 1.5), arm_col)
		draw_rect(Rect2(x + w, ay, 5, 0.5), arm_hi)
		# Peg
		draw_circle(Vector2(x + w + 5, ay + 0.7), 0.8, iron)

		# Weapons hanging
		if i == 0:
			# Sword
			draw_rect(Rect2(x + w + 3, ay + 1.5, 0.8, 7), Color(0.78, 0.78, 0.85))
			draw_rect(Rect2(x + w + 2.5, ay + 8.5, 1.8, 0.8), iron_dk)
			draw_rect(Rect2(x + w + 3.1, ay + 9.0, 0.6, 1.6), Color(0.50, 0.35, 0.18))
			# Specular on blade
			draw_line(Vector2(x + w + 3.1, ay + 2.0), Vector2(x + w + 3.1, ay + 7.5),
				Color(1, 1, 1, 0.55), 0.3)
		elif i == 1:
			# Spear (vertical)
			draw_rect(Rect2(x + w + 3.2, ay + 1.5, 0.5, 8), Color(0.45, 0.30, 0.14))
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + w + 3.45, ay + 9.5),
				Vector2(x + w + 2.7, ay + 11.5),
				Vector2(x + w + 4.2, ay + 11.5),
			]), Color(0.80, 0.80, 0.88))
		else:
			# Shield (round, leaning)
			draw_circle(Vector2(x + w + 3.5, ay + 5.5), 3.2, Color(0.42, 0.28, 0.18))
			draw_circle(Vector2(x + w + 3.5, ay + 5.5), 2.6, Color(0.62, 0.48, 0.22))
			draw_circle(Vector2(x + w + 3.5, ay + 5.5), 1.2, iron_dk)

	# Chain from upper arm up to wall
	for i in range(3):
		draw_arc(Vector2(x + w + 5, y + 4.5 + i * 1.2), 0.6,
			0, TAU, 6, iron, 0.4)

# ─── FURNITURE: PLINTH (3-tier with artifact) ────────────────────────────────
func _svg_plinth(x: float, y: float, w: float, h: float):
	# Shadow
	draw_circle(Vector2(x + w * 0.5, y + h + 1), w * 0.65,
		Color(0, 0, 0, 0.42))

	var stone: Color = Color(0.22, 0.18, 0.32)
	var floor_id: int = GameManager.current_floor
	if floor_id == 1:
		stone = Color(0.36, 0.28, 0.18)
	elif floor_id == 2:
		stone = Color(0.22, 0.22, 0.28)
	var stone_top: Color = stone.lightened(0.28)
	var stone_dk: Color = stone.darkened(0.30)
	var stone_side: Color = stone.darkened(0.18)

	# Base tier (widest)
	var b_x: float = x - 2
	var b_y: float = y + h - 5
	var b_w: float = w + 4
	draw_rect(Rect2(b_x, b_y, b_w, 5), stone)
	draw_rect(Rect2(b_x, b_y, b_w, 1.2), stone_top)
	draw_rect(Rect2(b_x + b_w - 1, b_y + 1, 1, 4), stone_side)
	# Rune carving on base front face
	var rune_col: Color = stone_dk.lightened(0.10)
	draw_line(Vector2(b_x + 3, b_y + 3), Vector2(b_x + 5, b_y + 3), rune_col, 0.5)
	draw_line(Vector2(b_x + 4, b_y + 2), Vector2(b_x + 4, b_y + 4), rune_col, 0.5)
	draw_circle(Vector2(b_x + b_w - 4, b_y + 3), 0.7, rune_col)

	# Mid tier
	var m_x: float = x - 1
	var m_y: float = y + h - 9
	var m_w: float = w + 2
	draw_rect(Rect2(m_x, m_y, m_w, 4), stone)
	draw_rect(Rect2(m_x, m_y, m_w, 1), stone_top)
	draw_rect(Rect2(m_x + m_w - 1, m_y + 1, 1, 3), stone_side)
	# Center rune
	draw_arc(Vector2(m_x + m_w * 0.5, m_y + 2.5), 1.0, 0, TAU, 8, rune_col, 0.4)
	draw_line(Vector2(m_x + m_w * 0.5 - 1, m_y + 2.5),
		Vector2(m_x + m_w * 0.5 + 1, m_y + 2.5), rune_col, 0.4)

	# Top tier (platform)
	draw_rect(Rect2(x, y + h - 14, w, 5), stone)
	draw_rect(Rect2(x, y + h - 14, w, 1.2), stone_top.lightened(0.05))
	draw_rect(Rect2(x + w - 1, y + h - 13, 1, 4), stone_side)
	# Ornate corner arcs on top platform
	var tx: float = x; var ty: float = y + h - 14
	draw_arc(Vector2(tx + 1.5, ty + 1.5), 1.2, PI, PI * 1.5, 6, rune_col, 0.5)
	draw_arc(Vector2(tx + w - 1.5, ty + 1.5), 1.2, PI * 1.5, TAU, 6, rune_col, 0.5)

	# Artifact on top — variant by floor
	var ax: float = x + w * 0.5
	var ay: float = y + h - 16.5
	var glow_pulse: float = 0.30 + sin(_t * 2.2) * 0.18
	var relic_col: Color = Color(1.0, 0.85, 0.30)
	match floor_id:
		1:
			relic_col = Color(1.0, 0.82, 0.28)
			# Golden idol — small humanoid silhouette
			draw_circle(Vector2(ax, ay - 1.5), 1.0, relic_col)
			draw_rect(Rect2(ax - 1.2, ay - 0.5, 2.4, 2.5), relic_col)
			draw_rect(Rect2(ax - 1.6, ay + 0.2, 3.2, 0.8), relic_col)
			# Highlight
			draw_circle(Vector2(ax - 0.3, ay - 1.8), 0.3, Color(1, 1, 0.85, 0.9))
		2:
			relic_col = Color(0.55, 0.75, 1.00)
			# Tome with glowing pages
			draw_rect(Rect2(ax - 2.0, ay - 0.5, 4.0, 2.5), Color(0.30, 0.18, 0.08))
			draw_rect(Rect2(ax - 1.8, ay, 3.6, 0.6),
				Color(relic_col.r, relic_col.g, relic_col.b, 0.85))
			draw_line(Vector2(ax, ay - 0.5), Vector2(ax, ay + 2.0),
				Color(0.20, 0.12, 0.06), 0.5)
		_:
			relic_col = Color(0.78, 0.55, 1.00)
			# Void crystal
			draw_colored_polygon(PackedVector2Array([
				Vector2(ax, ay - 2.5),
				Vector2(ax + 1.5, ay - 0.5),
				Vector2(ax + 0.8, ay + 2.0),
				Vector2(ax - 0.8, ay + 2.0),
				Vector2(ax - 1.5, ay - 0.5),
			]), Color(0.15, 0.08, 0.25))
			draw_colored_polygon(PackedVector2Array([
				Vector2(ax, ay - 2.0),
				Vector2(ax + 0.8, ay - 0.5),
				Vector2(ax, ay + 1.2),
				Vector2(ax - 0.8, ay - 0.5),
			]), relic_col.lightened(0.2))
			# Inner light
			draw_circle(Vector2(ax, ay), 0.6, Color(1, 1, 1, 0.85))

	# Animated artifact glow
	draw_circle(Vector2(ax, ay),
		4.0 + sin(_t * 2.2) * 0.8,
		Color(relic_col.r, relic_col.g, relic_col.b, glow_pulse * 0.55))
	draw_circle(Vector2(ax, ay),
		7.0 + sin(_t * 2.2) * 1.2,
		Color(relic_col.r, relic_col.g, relic_col.b, glow_pulse * 0.20))

	# Ethereal wisps
	for wi in range(3):
		var wp: float = _t * 1.4 + float(wi) * 2.1
		var wx: float = ax + sin(wp) * 5.0
		var wy: float = ay + 2.0 - (fmod(wp * 2.0, 8.0))
		var wa: float = clamp(1.0 - fmod(wp * 2.0, 8.0) / 8.0, 0.0, 1.0) * 0.45
		draw_circle(Vector2(wx, wy), 0.7,
			Color(relic_col.r, relic_col.g, relic_col.b, wa))

# ─── FURNITURE: BOOTH (3-wall cubicle) ────────────────────────────────────────
func _svg_booth(x: float, y: float, w: float, h: float):
	# Shadow
	draw_rect(Rect2(x - 1, y + h, w + 2, 2), Color(0, 0, 0, 0.40))

	var wood_dk: Color = Color(0.22, 0.14, 0.06)
	var wood: Color = Color(0.32, 0.20, 0.08)
	var wood_hi: Color = Color(0.45, 0.30, 0.14)
	var ledge: Color = Color(0.50, 0.36, 0.18)
	var ledge_hi: Color = ledge.lightened(0.20)

	# Back wall (tall horizontal rectangle with plank lines)
	draw_rect(Rect2(x, y, w, h * 0.65), wood)
	draw_rect(Rect2(x, y, w, 1), wood_hi)
	# Plank lines on back wall
	for pi in range(3):
		var lx: float = x + (w / 4.0) * float(pi + 1)
		draw_line(Vector2(lx, y + 1), Vector2(lx, y + h * 0.65 - 1),
			wood_dk, 0.5)
	# Horizontal grain
	draw_line(Vector2(x + 1, y + h * 0.32), Vector2(x + w - 1, y + h * 0.32),
		wood_dk, 0.4)

	# Left side wall (3/4 perspective, narrower front face)
	var ls_poly: PackedVector2Array = PackedVector2Array([
		Vector2(x, y),
		Vector2(x, y + h),
		Vector2(x + 2.5, y + h),
		Vector2(x + 2.5, y + 2),
	])
	draw_colored_polygon(ls_poly, wood_dk)
	draw_line(Vector2(x + 2.5, y + 2), Vector2(x + 2.5, y + h),
		wood, 0.5)

	# Right side wall (mirror)
	var rs_poly: PackedVector2Array = PackedVector2Array([
		Vector2(x + w, y),
		Vector2(x + w, y + h),
		Vector2(x + w - 2.5, y + h),
		Vector2(x + w - 2.5, y + 2),
	])
	draw_colored_polygon(rs_poly, wood_dk)
	draw_line(Vector2(x + w - 2.5, y + 2), Vector2(x + w - 2.5, y + h),
		wood, 0.5)

	# Counter ledge across front
	draw_rect(Rect2(x - 1, y + h * 0.55, w + 2, 2.5), ledge)
	draw_rect(Rect2(x - 1, y + h * 0.55, w + 2, 0.8), ledge_hi)

	# Inside: small bench + table silhouette
	draw_rect(Rect2(x + 3, y + h * 0.72, w - 6, 2), wood_hi.darkened(0.20))
	draw_rect(Rect2(x + w * 0.5 - 1.5, y + h * 0.78, 3, 3), wood_hi.darkened(0.15))

	# Single candle glow inside
	var fx: float = x + w * 0.30
	var fy: float = y + h * 0.45
	draw_circle(Vector2(fx, fy), 4.0,
		Color(1.0, 0.65, 0.18, 0.18 + sin(_t * 4.0 + x) * 0.04))
	draw_circle(Vector2(fx, fy), 1.0,
		Color(1.0, 0.92, 0.55, 0.85))

# ─── FURNITURE: NOTICEBOARD ───────────────────────────────────────────────────
func _svg_noticeboard(x: float, y: float, w: float, h: float):
	draw_rect(Rect2(x, y + h, w, 1.5), Color(0, 0, 0, 0.30))

	var frame_dk: Color = Color(0.22, 0.14, 0.06)
	var frame: Color = Color(0.32, 0.22, 0.10)
	var frame_hi: Color = Color(0.45, 0.32, 0.16)
	var cork: Color = Color(0.62, 0.46, 0.26)
	var cork_hi: Color = cork.lightened(0.12)

	# Outer frame
	draw_rect(Rect2(x - 1, y - 1, w + 2, h + 2), frame_dk)
	draw_rect(Rect2(x - 0.5, y - 0.5, w + 1, h + 1), frame)
	draw_rect(Rect2(x - 0.5, y - 0.5, w + 1, 0.6), frame_hi)
	# Cork
	draw_rect(Rect2(x, y, w, h), cork)
	draw_rect(Rect2(x, y, w, 0.5), cork_hi)
	# Cork stipple
	for si in range(6):
		var sx: float = x + float(si * 17 % int(w))
		var sy: float = y + float(si * 11 % int(h))
		draw_circle(Vector2(sx, sy), 0.3, cork.darkened(0.15))

	# 4 notices at angles
	var notes: Array = [
		{"x": x + 2, "y": y + 2, "w": 7.0, "h": 6.0,
			"col": Color(0.88, 0.82, 0.62), "ang": 0.15, "pin": Color(0.95, 0.18, 0.15)},
		{"x": x + 11, "y": y + 1.5, "w": 7.0, "h": 5.5,
			"col": Color(0.82, 0.76, 0.58), "ang": -0.12, "pin": Color(0.95, 0.18, 0.15)},
		{"x": x + 2.5, "y": y + 9, "w": 8.0, "h": 5.0,
			"col": Color(0.72, 0.80, 0.65), "ang": 0.08, "pin": Color(0.20, 0.35, 0.85)},
		{"x": x + 12, "y": y + 8.5, "w": 7.0, "h": 5.5,
			"col": Color(0.86, 0.78, 0.55), "ang": -0.10, "pin": Color(0.95, 0.18, 0.15)},
	]
	for n in notes:
		var nx: float = n.x; var ny: float = n.y
		var nw: float = n.w; var nh: float = n.h
		var ang: float = n.ang
		# Polygon (rotated rectangle)
		var center: Vector2 = Vector2(nx + nw * 0.5, ny + nh * 0.5)
		var pts: PackedVector2Array = PackedVector2Array()
		var corners: Array = [
			Vector2(-nw * 0.5, -nh * 0.5),
			Vector2(nw * 0.5, -nh * 0.5),
			Vector2(nw * 0.5, nh * 0.5),
			Vector2(-nw * 0.5, nh * 0.5),
		]
		for ct in corners:
			pts.append(center + (ct as Vector2).rotated(ang))
		# Drop shadow
		var spts: PackedVector2Array = PackedVector2Array()
		for p in pts:
			spts.append(p + Vector2(0.5, 0.7))
		draw_colored_polygon(spts, Color(0, 0, 0, 0.30))
		draw_colored_polygon(pts, n.col)
		# Lines of text (faux)
		var text_col: Color = (n.col as Color).darkened(0.40)
		var tl1: Vector2 = center + Vector2(-nw * 0.35, -nh * 0.25).rotated(ang)
		var tl2: Vector2 = center + Vector2(nw * 0.30, -nh * 0.25).rotated(ang)
		draw_line(tl1, tl2, text_col, 0.4)
		var tl3: Vector2 = center + Vector2(-nw * 0.35, -nh * 0.05).rotated(ang)
		var tl4: Vector2 = center + Vector2(nw * 0.20, -nh * 0.05).rotated(ang)
		draw_line(tl3, tl4, text_col, 0.4)
		# Pin
		var pin_pos: Vector2 = center + Vector2(0, -nh * 0.42).rotated(ang)
		draw_circle(pin_pos + Vector2(0.3, 0.3), 1.0, Color(0, 0, 0, 0.40))
		draw_circle(pin_pos, 0.9, n.pin)
		draw_circle(pin_pos + Vector2(-0.25, -0.25), 0.35, Color(1, 1, 1, 0.6))

	# Red string connecting two pins
	var p_a: Vector2 = Vector2(x + 2 + 7 * 0.5, y + 2 + 6 * 0.5 - 6 * 0.42)
	var p_b: Vector2 = Vector2(x + 12 + 7 * 0.5, y + 8.5 + 5.5 * 0.5 - 5.5 * 0.42)
	draw_line(p_a, p_b, Color(0.78, 0.18, 0.15, 0.60), 0.5)

	# Guild seal on one document
	var seal_pos: Vector2 = Vector2(x + 5.5, y + 11.5)
	draw_circle(seal_pos, 1.4, Color(0.65, 0.12, 0.10))
	draw_circle(seal_pos, 1.0, Color(0.75, 0.18, 0.14))
	draw_line(seal_pos + Vector2(-0.7, 0), seal_pos + Vector2(0.7, 0),
		Color(0.45, 0.08, 0.06), 0.4)
	draw_line(seal_pos + Vector2(0, -0.7), seal_pos + Vector2(0, 0.7),
		Color(0.45, 0.08, 0.06), 0.4)

# ─── ROOM-SPECIFIC ASSEMBLIES ─────────────────────────────────────────────────

# ── Entry Foyer (x:176-592, y:480-560) ────────────────────────────────────────
# Corridors: north-left x:224-272 @ y:448-480, north-right x:496-544 @ y:448-480
func _draw_entry_furniture():
	# Guard booths flanking the entrance — clear of both north corridors
	_svg_booth(196, 490, 20, 24)    # west booth (x:196-216, west of corridor at x:224) ✓
	_svg_booth(556, 490, 20, 24)    # east booth (x:556-576, east of corridor at x:544) ✓

	# Notice boards on south wall
	_svg_noticeboard(232, 536, 22, 16)
	_svg_noticeboard(508, 536, 22, 16)

	# Central mosaic floor inlay (decorative grand foyer marker)
	var inlay := Color(0.45, 0.38, 0.22, 0.30)
	var cx: float = 384.0; var cy: float = 520.0
	draw_polyline(PackedVector2Array([
		Vector2(cx - 36, cy), Vector2(cx, cy - 20),
		Vector2(cx + 36, cy), Vector2(cx, cy + 20), Vector2(cx - 36, cy)
	]), Color(inlay.r, inlay.g, inlay.b, 0.45), 0.8)
	draw_polyline(PackedVector2Array([
		Vector2(cx - 20, cy), Vector2(cx, cy - 11),
		Vector2(cx + 20, cy), Vector2(cx, cy + 11), Vector2(cx - 20, cy)
	]), Color(inlay.r * 1.4, inlay.g * 1.4, inlay.b * 0.6, 0.55), 0.6)

# ── Barracks (x:16-320, y:304-464) ────────────────────────────────────────────
# Corridors: north x:112-160 @ y:272-320, south x:224-272 @ y:448-480
func _draw_barracks_furniture():
	# 5 bunks along north wall — 3 west of north corridor, 2 east of it
	# North corridor mouth at x:112-160, keep clear at y:304-332 in that range
	for bx: float in [16.0, 48.0, 80.0]:           # west of corridor (ends at x:108, gap before x:112) ✓
		_svg_bed(bx, 308, 26, 22)
	for bx: float in [168.0, 200.0]:               # east of corridor (starts at x:168, after x:160) ✓
		_svg_bed(bx, 308, 26, 22)

	# Weapon rack against west wall (clear of beds above and tables below)
	_svg_rack(16, 356, 12, 52)

	# Mess hall tables in lower section — clear of south corridor (x:224-272, y:448-480)
	# Tables stop well east of x:220 to leave corridor approach open
	_svg_table(48,  406, 40, 16)
	_svg_table(92,  406, 40, 16)
	_svg_table(136, 406, 40, 16)
	_svg_table(180, 406, 36, 16)   # ends at x:216, south corridor at x:224 ✓

	# Benches north and south of tables (same x bounds)
	for bx: float in [52.0, 96.0, 140.0, 182.0]:
		_svg_bench(bx, 396, 32, 8)
	for bx: float in [52.0, 96.0, 140.0, 182.0]:
		_svg_bench(bx, 424, 32, 8)

	# Rune carvings along north wall (decorative)
	var rune := Color(0.40, 0.55, 0.32, 0.35)
	for i in range(3):
		var rx: float = 32.0 + float(i) * 72.0
		draw_circle(Vector2(rx, 308), 1.8, rune)
		draw_line(Vector2(rx - 3, 308), Vector2(rx + 3, 308), rune, 0.6)
		draw_line(Vector2(rx, 305), Vector2(rx, 311), rune, 0.6)

# ── Storeroom (x:432-736, y:304-464) ──────────────────────────────────────────
# Corridors: north x:576-624 @ y:272-320, south x:496-544 @ y:448-480
func _draw_storeroom_furniture():
	# Crates in organised rows with clear navigation paths
	# Avoid: north corridor mouth x:560-640 at y:304-340
	# Avoid: south corridor mouth x:480-560 at y:432-464

	# West bank (x:436-540, clear of north corridor to the east)
	for cx: float in [436.0, 464.0, 492.0, 516.0]:
		_svg_crate(cx, 324, 24, 24)

	# East bank (x:648+, east of north corridor at x:624)
	for cx: float in [648.0, 676.0, 700.0]:
		_svg_crate(cx, 324, 24, 24)

	# Middle row (navigation path runs east-west through center)
	for cx: float in [436.0, 464.0, 552.0, 660.0, 688.0]:
		_svg_crate(cx, 362, 24, 24)

	# Lower row (clear of south corridor x:480-560)
	for cx: float in [436.0, 576.0, 604.0, 648.0, 676.0]:
		_svg_crate(cx, 400, 24, 24)

# ── Captain's Office (x:16-272, y:128-288) ────────────────────────────────────
# Corridors: vault-west x:128-176 @ y:96-144, east passage x:256-320 @ y:160-256
func _draw_captain_furniture():
	# ── Bookcase along west wall ───────────────────────────────────────────────
	var bc_col := Color(0.22, 0.14, 0.06)
	draw_rect(Rect2(16, 170, 14, 88), bc_col)
	draw_rect(Rect2(16, 170, 14, 1.2), bc_col.lightened(0.30))
	var bk_cols: Array = [
		Color(0.72, 0.22, 0.18), Color(0.22, 0.55, 0.28),
		Color(0.45, 0.35, 0.65), Color(0.75, 0.65, 0.18),
		Color(0.30, 0.40, 0.65),
	]
	for by2 in range(5):
		var row_y2: float = 174.0 + float(by2) * 16.0
		draw_rect(Rect2(17, row_y2, 12, 11), Color(0.10, 0.08, 0.06))
		draw_rect(Rect2(16, row_y2 + 11, 14, 1), bc_col.darkened(0.30))
		for bi in range(4):
			var bx_book: float = 17.5 + float(bi) * 2.8
			var col: Color = bk_cols[(bi + by2) % bk_cols.size()]
			draw_rect(Rect2(bx_book, row_y2 + 1, 2.4, 9.5), col)
			draw_rect(Rect2(bx_book, row_y2 + 1, 2.4, 0.6), col.lightened(0.30))
			if (bi + by2) % 2 == 0:
				draw_rect(Rect2(bx_book, row_y2 + 5, 2.4, 0.5), Color(0.90, 0.72, 0.20))

	# ── Command desk east of vault corridor opening ────────────────────────────
	# Vault corridor mouth at x:128-176 in north wall — desk sits east of that
	_svg_table(192, 134, 52, 18)   # x:192-244, well clear of corridor exit at x:176 ✓
	_svg_bench(200, 154, 28, 8)    # officer's chair

	# ── Records table in south-west alcove ─────────────────────────────────────
	_svg_table(20, 228, 36, 16)
	_svg_bench(24, 220, 28, 6)

	# ── Trophy plinth in north-west corner ─────────────────────────────────────
	_svg_plinth(48, 140, 16, 16)

	# ── Notice boards on south wall ────────────────────────────────────────────
	_svg_noticeboard(96, 260, 22, 16)
	_svg_noticeboard(148, 260, 22, 16)

	# ── Rune/sigil carvings along east wall (facing the corridor) ──────────────
	var rune := Color(0.50, 0.38, 0.28, 0.38)
	for i in range(4):
		var ry: float = 174.0 + float(i) * 24.0
		var rx: float = 246.0
		draw_circle(Vector2(rx, ry), 2.0, rune)
		draw_line(Vector2(rx - 3, ry), Vector2(rx + 3, ry), rune, 0.6)
		draw_line(Vector2(rx, ry - 3), Vector2(rx, ry + 3), rune, 0.6)
		draw_arc(Vector2(rx, ry), 2.0, 0, TAU, 7, Color(rune.r, rune.g, rune.b, 0.20), 0.4)

# ── Antechamber (x:304-512, y:128-288) ────────────────────────────────────────
# Corridors: west x:256-320 @ y:160-256, east x:496-576 @ y:160-256, vault x:400-432 @ y:96-144
func _draw_antechamber_furniture():
	# ── Stone columns flanking vault corridor entrance ─────────────────────────
	# Vault-East corridor is at x:400-432; columns at x:352 and x:456 (flanking both sides)
	var col_stone := Color(0.35, 0.28, 0.45)
	var col_hi    := col_stone.lightened(0.28)
	var col_dk    := col_stone.darkened(0.28)
	for cx: float in [352.0, 456.0]:
		draw_rect(Rect2(cx - 5, 140, 10, 5), col_stone.darkened(0.12))  # plinth base
		draw_rect(Rect2(cx - 4, 130, 8, 11), col_stone)                  # column shaft
		draw_rect(Rect2(cx - 4, 130, 1, 11), col_hi)                     # highlight
		draw_rect(Rect2(cx + 3, 130, 1, 11), col_dk)                     # shadow
		draw_rect(Rect2(cx - 5, 127, 10, 4), col_hi)                     # capital
		draw_rect(Rect2(cx - 5, 127, 10, 1), col_hi.lightened(0.18))     # capital top
		# Column base moulding
		draw_rect(Rect2(cx - 6, 145, 12, 2), col_stone.darkened(0.20))

	# ── Decorative shield/crest on north wall between columns ─────────────────
	var shield_x: float = 408.0; var shield_y: float = 138.0
	draw_circle(Vector2(shield_x, shield_y), 8.0, Color(0.30, 0.20, 0.12))
	draw_circle(Vector2(shield_x, shield_y), 6.5, Color(0.42, 0.30, 0.18))
	draw_circle(Vector2(shield_x, shield_y), 2.2, Color(0.85, 0.70, 0.22))
	draw_line(Vector2(shield_x - 5.5, shield_y), Vector2(shield_x + 5.5, shield_y),
		Color(0.24, 0.16, 0.08), 0.7)
	draw_line(Vector2(shield_x, shield_y - 5.5), Vector2(shield_x, shield_y + 5.5),
		Color(0.24, 0.16, 0.08), 0.7)
	# Subtle glow from the crest
	var glow_a: float = 0.12 + sin(_t * 1.8) * 0.06
	draw_circle(Vector2(shield_x, shield_y), 12.0, Color(0.85, 0.70, 0.22, glow_a))

	# ── Ceremonial meeting table in south half ─────────────────────────────────
	# Placed in y:240-270, far from all corridors (corridors at y:160-256 only at x edges)
	_svg_table(340, 240, 100, 16)   # x:340-440, y:240-256, center of room ✓

	# Flanking benches (north and south of table, same x span)
	_svg_bench(344, 228, 40, 10)    # north bench west
	_svg_bench(396, 228, 40, 10)    # north bench east
	_svg_bench(344, 258, 40, 10)    # south bench west
	_svg_bench(396, 258, 40, 10)    # south bench east

	# ── Animated floor censer in very center ──────────────────────────────────
	var censer_x: float = 408.0; var censer_y: float = 196.0
	# Censer smoke wisp
	for wi in range(3):
		var wp: float = _t * 1.2 + float(wi) * 2.1
		var wx: float = censer_x + sin(wp) * 2.5
		var wy: float = censer_y - 4.0 - fmod(wp * 1.5, 10.0)
		var wa: float = clamp(1.0 - fmod(wp * 1.5, 10.0) / 10.0, 0.0, 1.0) * 0.30
		draw_circle(Vector2(wx, wy), 1.2, Color(0.60, 0.50, 0.70, wa))
	# Censer bowl
	draw_circle(Vector2(censer_x, censer_y), 3.5, Color(0.32, 0.24, 0.40))
	draw_arc(Vector2(censer_x, censer_y), 3.5, PI, TAU, 10,
		Color(0.55, 0.45, 0.65), 0.7)
	draw_circle(Vector2(censer_x, censer_y - 1), 1.5, Color(0.70, 0.55, 0.80, 0.60))

# ── Vault (x:96-672, y:16-112) ────────────────────────────────────────────────
# Corridors: vault-west x:128-176 @ y:96-144, vault-east x:400-432 @ y:96-144
func _draw_vault_furniture():
	var pulse: float = abs(sin(_t * 1.5))

	# ── Grand floor inlay — symmetrical diamond lattice ────────────────────────
	var inlay := Color(C_FLOOR_VAULT_A.r + 0.08, C_FLOOR_VAULT_A.g + 0.04, C_FLOOR_VAULT_A.b + 0.14, 0.75)
	# Outer diamond
	var pts := PackedVector2Array([
		Vector2(384, 22), Vector2(460, 56),
		Vector2(384, 90), Vector2(308, 56),
	])
	draw_colored_polygon(pts, Color(inlay.r, inlay.g, inlay.b, 0.10))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color(inlay.r, inlay.g, inlay.b, 0.30), 0.8)
	# Inner diamond
	var inner: Array = [Vector2(384, 36), Vector2(420, 56), Vector2(384, 76), Vector2(348, 56)]
	draw_polyline(PackedVector2Array(inner + [inner[0]]),
		Color(inlay.r * 1.4, inlay.g * 1.4, inlay.b * 2.0, 0.38 + pulse * 0.10), 0.7)
	# Cross lines through diamond
	draw_line(Vector2(308, 56), Vector2(460, 56), Color(inlay.r, inlay.g, inlay.b, 0.18), 0.5)
	draw_line(Vector2(384, 22), Vector2(384, 90), Color(inlay.r, inlay.g, inlay.b, 0.18), 0.5)

	# Arcane glow pool under central plinth
	var glow: Color = Color(0.58, 0.35, 0.88, 0.18 + pulse * 0.10)
	draw_circle(Vector2(384, 56), 36.0, glow)
	draw_circle(Vector2(384, 56), 20.0, Color(glow.r, glow.g, glow.b, glow.a * 1.6))

	# ── Three plinths: grand central + two flanking altars ─────────────────────
	# Grand plinth at vault center
	_svg_plinth(374, 44, 20, 20)

	# West altar — clear of vault-west corridor (x:128-176); plinth at x:182
	_svg_plinth(182, 36, 24, 22)

	# East altar — clear of vault-east corridor (x:400-432); plinth at x:514
	_svg_plinth(514, 36, 24, 22)

	# ── Wall bracket sconces ──────────────────────────────────────────────────
	var bracket := Color(0.42, 0.30, 0.50)
	for sx: float in [112.0, 248.0, 624.0]:
		draw_rect(Rect2(sx, 18, 12, 8), bracket)
		draw_rect(Rect2(sx + 2, 16, 8, 4), Color(bracket.r * 1.3, bracket.g * 1.2, bracket.b * 1.4))
		draw_line(Vector2(sx + 6, 18), Vector2(sx + 6, 24), bracket, 1.5)

	# ── Cobwebs in far corners ─────────────────────────────────────────────────
	var web := Color(0.48, 0.44, 0.52, 0.28)
	_draw_cobweb(Vector2(100, 18), Vector2(1, 1), web)
	_draw_cobweb(Vector2(660, 18), Vector2(-1, 1), web)

	# ── Gold coin piles (symmetric around center) ──────────────────────────────
	var gold_a := Color(0.92, 0.74, 0.18)
	var gold_b := Color(0.72, 0.54, 0.10)
	for corner: Vector2 in [Vector2(148, 28), Vector2(620, 28), Vector2(240, 80), Vector2(528, 80)]:
		draw_circle(corner + Vector2(0, 2), 7.0, Color(0, 0, 0, 0.28))
		for ci in range(9):
			var cr: float = 1.4 + float(ci % 3) * 0.7
			var co: Vector2 = Vector2(float(ci % 4) * 3 - 5, float(ci / 4) * 3 - 2)
			draw_circle(corner + co, cr, gold_a if ci % 2 == 0 else gold_b)
			if ci % 3 == 0:
				draw_circle(corner + co - Vector2(0.4, 0.4), cr * 0.4,
					Color(1.0, 0.98, 0.80, 0.65))

# ── Armory (x:560-736, y:128-288) ─────────────────────────────────────────────
# Corridors: west x:496-576 @ y:160-256, north (storeroom) x:576-624 @ y:272-320
func _draw_armory_furniture():
	# Two tall weapon racks along east wall (x:720-736 region)
	_svg_rack(706, 136, 12, 52)
	_svg_rack(706, 204, 12, 52)

	# Heavy iron crate in south-east corner
	_svg_crate(672, 248, 28, 24)

	# Second crate cluster — mid east wall
	_svg_crate(676, 196, 24, 22)

	# Small crate stack against north wall (east of room, clear of west corridor at x:496-576)
	_svg_crate(596, 136, 22, 20)
	_svg_crate(622, 136, 22, 20)

	# ── Armor stand in north-west of armory (clear of west corridor x:496-576) ──
	var as_x := 584.0; var as_y := 148.0
	draw_circle(Vector2(as_x + 8, as_y + 30), 7.0, Color(0, 0, 0, 0.35))  # shadow
	draw_rect(Rect2(as_x + 7, as_y + 22, 2, 10), Color(0.22, 0.18, 0.12))  # pole
	# Helm
	draw_circle(Vector2(as_x + 8, as_y + 8), 5.5, Color(0.42, 0.42, 0.50))
	draw_circle(Vector2(as_x + 8, as_y + 7), 4.8, Color(0.54, 0.54, 0.62))
	draw_rect(Rect2(as_x + 5, as_y + 7.5, 7, 1.2), Color(0.10, 0.10, 0.12))  # visor
	draw_line(Vector2(as_x + 8, as_y + 2), Vector2(as_x + 7, as_y - 2),
		Color(0.72, 0.18, 0.18), 1.4)  # plume
	# Torso
	draw_rect(Rect2(as_x + 2, as_y + 13, 12, 12), Color(0.40, 0.40, 0.48))
	draw_rect(Rect2(as_x + 2, as_y + 13, 12, 1), Color(0.62, 0.62, 0.70))
	draw_circle(Vector2(as_x + 8, as_y + 18), 2.0, Color(0.85, 0.70, 0.22))  # emblem
	draw_circle(Vector2(as_x + 8, as_y + 18), 1.1, Color(0.60, 0.45, 0.10))
	draw_circle(Vector2(as_x,     as_y + 14), 3.0, Color(0.40, 0.40, 0.48))  # pauldrons
	draw_circle(Vector2(as_x + 16, as_y + 14), 3.0, Color(0.40, 0.40, 0.48))

	# ── Trophy shield on south wall ────────────────────────────────────────────
	var sh_x: float = 648.0; var sh_y: float = 264.0
	draw_circle(Vector2(sh_x, sh_y), 9.0, Color(0.35, 0.22, 0.12))
	draw_circle(Vector2(sh_x, sh_y), 7.0, Color(0.52, 0.38, 0.20))
	draw_colored_polygon(PackedVector2Array([
		Vector2(sh_x, sh_y - 4.5), Vector2(sh_x + 3.5, sh_y),
		Vector2(sh_x, sh_y + 4.5), Vector2(sh_x - 3.5, sh_y),
	]), Color(0.88, 0.72, 0.22))
	draw_circle(Vector2(sh_x, sh_y), 1.5, Color(0.50, 0.36, 0.10))

func _draw_cobweb(origin: Vector2, dir: Vector2, col: Color):
	for i in range(4):
		var angle := deg_to_rad(float(i) * 22.0 - 22.0)
		var d := dir.rotated(angle) * float(i + 1) * 8.0
		draw_line(origin, origin + d, col, 0.6)
	for ri in range(2):
		var r := float(ri + 1) * 9.0
		draw_arc(origin, r, deg_to_rad(-45.0 * dir.x + 90.0),
			deg_to_rad(45.0 + 45.0 * dir.x + 90.0), 6, col, 0.5)

# ── Helpers ───────────────────────────────────────────────────────────────────
func _is_torch_lit(pos: Vector2) -> bool:
	for tn in get_tree().get_nodes_in_group("torches"):
		if tn.global_position.distance_to(pos) < 8.0:
			return tn.get("is_lit") != false
	return true

func _draw_torch_glow(center: Vector2, idx: int):
	var flicker: float = sin(_t * 5.3 + idx * 1.7) * 0.3 + sin(_t * 11.1 + idx * 0.9) * 0.15
	var gs: float = 1.0 + flicker * 0.08
	draw_circle(center, 44.0 * gs, Color(1.0, 0.62, 0.12, 0.045))
	draw_circle(center, 28.0 * gs, Color(1.0, 0.68, 0.18, 0.085 + flicker * 0.02))
	draw_circle(center, 15.0 * gs, Color(1.0, 0.78, 0.28, 0.150 + flicker * 0.03))
	draw_circle(center,  7.0 * gs, Color(1.0, 0.88, 0.44, 0.220 + flicker * 0.04))
