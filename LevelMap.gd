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
	Vector2(256,  20),
	Vector2(384,  20),
	Vector2(512,  20),
	Vector2(144, 132),
	Vector2(456, 132),
	Vector2(680, 132),
	Vector2(160, 308),
	Vector2(600, 308),
	Vector2(384, 468),
	Vector2(256, 556),
	Vector2(512, 556),
]

const ROOM_TILE_RECTS: Array[Rect2i] = [
	Rect2i(14, 29, 20,  6),
	Rect2i( 1, 19, 18,  9),
	Rect2i(29, 19, 17,  9),
	Rect2i( 1,  8, 16,  9),
	Rect2i(20,  8, 17,  9),
	Rect2i( 8,  1, 32,  6),
	Rect2i(39,  8,  7,  9),
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

	_carve(Rect2i( 8,  1, 32,  6))
	_carve(Rect2i( 8,  6,  2,  3))
	_carve(Rect2i(26,  6,  2,  3))
	_carve(Rect2i( 1,  8, 16,  9))
	_carve(Rect2i(20,  8, 17,  9))
	_carve(Rect2i(39,  8,  7,  9))
	_carve(Rect2i(17, 11,  3,  3))
	_carve(Rect2i(37, 11,  2,  3))
	_carve(Rect2i( 8, 17,  2,  2))
	_carve(Rect2i(35, 17,  2,  2))
	_carve(Rect2i( 1, 19, 18,  9))
	_carve(Rect2i(29, 19, 17,  9))
	_carve(Rect2i(15, 27,  2,  2))
	_carve(Rect2i(31, 27,  2,  2))
	_carve(Rect2i(14, 29, 20,  6))

func _carve(rect: Rect2i):
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			if r >= 0 and r < MAP_ROWS and c >= 0 and c < MAP_COLS:
				map[r][c] = FLOOR

func _randomize_cover():
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.run_seed + GameManager.current_floor * 31337

	var vpillars := [Vector2i(13, 3), Vector2i(21, 4), Vector2i(29, 3), Vector2i(37, 4)]
	for p in vpillars:
		if rng.randi_range(0, 2) != 0:
			if p.y > 0 and p.y < MAP_ROWS - 1 and p.x > 0 and p.x < MAP_COLS - 1:
				map[p.y][p.x] = WALL

	var capillars := [Vector2i(4, 10), Vector2i(11, 13)]
	for p in capillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	var antipillars := [Vector2i(22, 10), Vector2i(30, 13)]
	for p in antipillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	var bpillars := [Vector2i(3, 21), Vector2i(10, 24), Vector2i(15, 21)]
	for p in bpillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	var spillars := [Vector2i(31, 21), Vector2i(38, 24), Vector2i(43, 21)]
	for p in spillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	var epillars := [Vector2i(17, 31), Vector2i(25, 31)]
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
	if tc.y >= 29 and tc.y <= 34 and tc.x >= 14 and tc.x <= 33: return 0
	if tc.y >= 19 and tc.y <= 27 and tc.x >=  1 and tc.x <= 18: return 1
	if tc.y >= 19 and tc.y <= 27 and tc.x >= 29 and tc.x <= 45: return 2
	if tc.y >=  8 and tc.y <= 16 and tc.x >=  1 and tc.x <= 16: return 3
	if tc.y >=  8 and tc.y <= 16 and tc.x >= 20 and tc.x <= 36: return 4
	if tc.y >=  1 and tc.y <=  6 and tc.x >=  8 and tc.x <= 39: return 5
	if tc.y >=  8 and tc.y <= 16 and tc.x >= 39 and tc.x <= 45: return 6
	return -1

# ── Zone helpers ──────────────────────────────────────────────────────────────
func _get_zone(row: int) -> int:
	if row <=  7: return 0
	if row <= 28: return 1
	return 2

func _apply_floor_theme():
	match GameManager.current_floor:
		1:
			C_FLOOR_VAULT_A  = Color(0.14, 0.11, 0.07); C_FLOOR_VAULT_B  = Color(0.16, 0.13, 0.09)
			C_FLOOR_MID_A    = Color(0.12, 0.10, 0.07); C_FLOOR_MID_B    = Color(0.14, 0.12, 0.08)
			C_FLOOR_ENTRY_A  = Color(0.16, 0.12, 0.08); C_FLOOR_ENTRY_B  = Color(0.19, 0.14, 0.09)
			C_WALL_VAULT     = Color(0.42, 0.30, 0.18); C_WALL_VAULT_E   = Color(0.62, 0.46, 0.28)
			C_WALL_MID       = Color(0.36, 0.28, 0.18); C_WALL_MID_E     = Color(0.54, 0.40, 0.26)
			C_WALL_ENTRY     = Color(0.38, 0.28, 0.18); C_WALL_ENTRY_E   = Color(0.56, 0.42, 0.26)
		2:
			C_FLOOR_VAULT_A  = Color(0.08, 0.07, 0.13); C_FLOOR_VAULT_B  = Color(0.10, 0.09, 0.16)
			C_FLOOR_MID_A    = Color(0.08, 0.10, 0.08); C_FLOOR_MID_B    = Color(0.10, 0.12, 0.09)
			C_FLOOR_ENTRY_A  = Color(0.11, 0.09, 0.07); C_FLOOR_ENTRY_B  = Color(0.13, 0.11, 0.08)
			C_WALL_VAULT     = Color(0.18, 0.14, 0.28); C_WALL_VAULT_E   = Color(0.32, 0.24, 0.48)
			C_WALL_MID       = Color(0.20, 0.18, 0.14); C_WALL_MID_E     = Color(0.36, 0.30, 0.22)
			C_WALL_ENTRY     = Color(0.28, 0.22, 0.16); C_WALL_ENTRY_E   = Color(0.44, 0.34, 0.24)
		_:
			C_FLOOR_VAULT_A  = Color(0.05, 0.06, 0.10); C_FLOOR_VAULT_B  = Color(0.07, 0.08, 0.13)
			C_FLOOR_MID_A    = Color(0.07, 0.08, 0.08); C_FLOOR_MID_B    = Color(0.08, 0.09, 0.10)
			C_FLOOR_ENTRY_A  = Color(0.08, 0.08, 0.09); C_FLOOR_ENTRY_B  = Color(0.10, 0.10, 0.11)
			C_WALL_VAULT     = Color(0.14, 0.16, 0.28); C_WALL_VAULT_E   = Color(0.24, 0.28, 0.46)
			C_WALL_MID       = Color(0.16, 0.18, 0.22); C_WALL_MID_E     = Color(0.26, 0.30, 0.38)
			C_WALL_ENTRY     = Color(0.18, 0.18, 0.22); C_WALL_ENTRY_E   = Color(0.28, 0.28, 0.36)

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
	var entry_y: float = 29 * TILE_SIZE
	draw_rect(Rect2(0, entry_y - 3, map_w, 3), Color(0.15, 0.15, 0.25, 0.22))

# ── Floor tile (textured, themed) ─────────────────────────────────────────────
func _draw_floor_tile(x: float, y: float, c: int, r: int, zone: int, floor_id: int):
	var alt: bool = (r + c) % 4 == 0
	var fa: Color; var fb: Color
	match zone:
		0: fa = C_FLOOR_VAULT_A;  fb = C_FLOOR_VAULT_B
		1: fa = C_FLOOR_MID_A;    fb = C_FLOOR_MID_B
		_: fa = C_FLOOR_ENTRY_A;  fb = C_FLOOR_ENTRY_B
	var base: Color = fb if alt else fa
	var tile_hash: int = (c * 31 + r * 17) % 100
	# Subtle per-tile shade variation
	var vshade: float = (tile_hash % 7) * 0.004
	base = Color(base.r + vshade, base.g + vshade, base.b + vshade)

	draw_rect(Rect2(x, y, TILE_SIZE, TILE_SIZE), base)

	# Bottom & right "edge depth" — 1px darker stripes
	var edge: Color = Color(0, 0, 0, 0.30)
	draw_rect(Rect2(x, y + TILE_SIZE - 1, TILE_SIZE, 1), edge)
	draw_rect(Rect2(x + TILE_SIZE - 1, y, 1, TILE_SIZE), edge)
	# Top-left subtle highlight
	draw_rect(Rect2(x, y, TILE_SIZE, 1), Color(1, 1, 1, 0.04))

	match floor_id:
		1:
			# Sandstone — occasional cracks
			if tile_hash % 11 == 0:
				var cx: float = x + 3.0 + float(tile_hash % 6)
				var cy: float = y + 4.0 + float((tile_hash / 7) % 6)
				var cdir: Vector2 = Vector2(1.0, 0.4).rotated(float(tile_hash) * 0.13)
				var clen: float = 3.0 + float(tile_hash % 4)
				draw_line(Vector2(cx, cy), Vector2(cx + cdir.x * clen, cy + cdir.y * clen),
					Color(0, 0, 0, 0.32), 0.6)
			# Occasional sand grain dots
			if tile_hash % 17 == 3:
				draw_circle(Vector2(x + 5 + float(tile_hash % 6), y + 9 + float(tile_hash % 5)),
					0.6, Color(0.85, 0.70, 0.45, 0.18))
		2:
			# Barracks — mortar grid lines forming 8px joints
			var mortar: Color = Color(base.r * 0.72, base.g * 0.72, base.b * 0.75, 0.55)
			draw_line(Vector2(x, y + 8), Vector2(x + TILE_SIZE, y + 8), mortar, 0.6)
			if c % 2 == 0:
				draw_line(Vector2(x + 8, y), Vector2(x + 8, y + 8), mortar, 0.6)
			else:
				draw_line(Vector2(x + 4, y + 8), Vector2(x + 4, y + TILE_SIZE), mortar, 0.6)
				draw_line(Vector2(x + 12, y + 8), Vector2(x + 12, y + TILE_SIZE), mortar, 0.6)
			# Occasional bootscuff
			if tile_hash % 23 == 4:
				draw_line(Vector2(x + 3, y + 12), Vector2(x + 9, y + 11),
					Color(0, 0, 0, 0.22), 0.6)
		_:
			# Vault — dark stone with occasional arcane crack-glow
			var mortar2: Color = Color(base.r * 0.60, base.g * 0.60, base.b * 0.72, 0.50)
			if (r + c) % 3 == 0:
				draw_line(Vector2(x, y + 8), Vector2(x + TILE_SIZE, y + 8), mortar2, 0.5)
			if tile_hash % 13 == 1:
				var glowp: float = 0.20 + sin(_t * 1.7 + float(tile_hash) * 0.3) * 0.12
				var gx: float = x + 4.0 + float(tile_hash % 6)
				var gy: float = y + 6.0 + float((tile_hash / 5) % 6)
				var gd: Vector2 = Vector2(1.0, 0.3).rotated(float(tile_hash) * 0.21)
				var glen: float = 4.0 + float(tile_hash % 3)
				draw_line(Vector2(gx, gy), Vector2(gx + gd.x * glen, gy + gd.y * glen),
					Color(0.45, 0.35, 0.85, glowp), 0.7)
				draw_line(Vector2(gx, gy), Vector2(gx + gd.x * glen, gy + gd.y * glen),
					Color(0.80, 0.65, 1.00, glowp * 0.5), 0.3)

# ── Wall tile (3/4 perspective stone block) ───────────────────────────────────
func _draw_wall_tile(x: float, y: float, c: int, r: int, zone: int, floor_id: int, has_floor_south: bool, has_floor_north: bool):
	var cw: Color; var ce: Color
	match zone:
		0: cw = C_WALL_VAULT;  ce = C_WALL_VAULT_E
		1: cw = C_WALL_MID;    ce = C_WALL_MID_E
		_: cw = C_WALL_ENTRY;  ce = C_WALL_ENTRY_E

	var tile_hash: int = (c * 31 + r * 17) % 100
	var v: float = float(tile_hash % 6) * 0.012
	var front_col: Color = Color(cw.r - v, cw.g - v * 0.5, cw.b - v * 0.3)
	var top_col: Color = ce
	var top_h: float = 5.0
	var front_h: float = float(TILE_SIZE) - top_h
	var shadow_col: Color = Color(front_col.r * 0.45, front_col.g * 0.45, front_col.b * 0.55)
	var hi_col: Color = front_col.lightened(0.10)

	# Top face (slightly tilted look with subtle gradient)
	draw_rect(Rect2(x, y, TILE_SIZE, top_h), top_col)
	# Top face bevel highlight
	draw_rect(Rect2(x, y, TILE_SIZE, 1), top_col.lightened(0.18))
	# Top-face stone texture noise
	if tile_hash % 5 == 0:
		draw_rect(Rect2(x + 3, y + 1, 3, 1), top_col.darkened(0.15))
	if tile_hash % 7 == 2:
		draw_rect(Rect2(x + 9, y + 2, 4, 1), top_col.darkened(0.12))

	# Front face
	draw_rect(Rect2(x, y + top_h, TILE_SIZE, front_h), front_col)

	# Block separation — vertical mortar joint (only on some tiles)
	if c % 2 == int(r / 2) % 2:
		draw_line(Vector2(x + 8, y + top_h), Vector2(x + 8, y + TILE_SIZE),
			Color(0, 0, 0, 0.35), 0.7)
	# Horizontal mortar line at base of top face
	draw_line(Vector2(x, y + top_h), Vector2(x + TILE_SIZE, y + top_h),
		shadow_col, 0.9)
	# Faint mid-block mortar
	draw_line(Vector2(x, y + top_h + front_h * 0.5),
		Vector2(x + TILE_SIZE, y + top_h + front_h * 0.5),
		Color(0, 0, 0, 0.18), 0.6)

	# Left shadow strip
	draw_rect(Rect2(x, y + top_h, 2, front_h), Color(shadow_col.r, shadow_col.g, shadow_col.b, 0.80))
	# Right highlight
	draw_rect(Rect2(x + TILE_SIZE - 1, y + top_h, 1, front_h), hi_col)

	# Stone block detail — small chipped corners on some tiles
	if tile_hash % 9 == 3:
		draw_rect(Rect2(x + 2, y + TILE_SIZE - 3, 2, 2), front_col.darkened(0.25))
	if tile_hash % 11 == 5:
		draw_rect(Rect2(x + TILE_SIZE - 4, y + top_h + 2, 2, 1), front_col.darkened(0.18))

	# Theme-specific accents
	match floor_id:
		1:
			# Sandstone — warm tint on top
			draw_rect(Rect2(x, y, TILE_SIZE, 1), Color(1.0, 0.78, 0.40, 0.18))
		3:
			# Vault — arcane purple flecks
			if tile_hash % 13 == 7:
				var ap: float = 0.20 + sin(_t * 1.5 + float(tile_hash)) * 0.10
				draw_circle(Vector2(x + 6 + float(tile_hash % 5), y + top_h + 4 + float(tile_hash % 4)),
					0.6, Color(0.55, 0.40, 0.90, ap))

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

	# Floor light pool
	draw_circle(Vector2(tp.x, tp.y + 10), 11.0, Color(1.0, 0.62, 0.18, 0.08))

# ── Furniture collision ───────────────────────────────────────────────────────
func _build_furniture_collision():
	var body := StaticBody2D.new()
	body.name = "Furniture"
	add_child(body)

	var _add := func(rect: Rect2):
		var shape := CollisionShape2D.new()
		var rs    := RectangleShape2D.new()
		rs.size        = rect.size
		shape.shape    = rs
		shape.position = rect.get_center()
		body.add_child(shape)

	_add.call(Rect2(280, 472, 20, 24))
	_add.call(Rect2(444, 472, 20, 24))
	for bx: float in [32.0, 80.0, 128.0, 176.0, 240.0]:
		_add.call(Rect2(bx, 316, 24, 14))
	_add.call(Rect2(20, 340, 12, 48))
	for cx: float in [480.0, 544.0, 608.0, 672.0]:
		_add.call(Rect2(cx, 340, 24, 24))
	_add.call(Rect2(80, 200, 32, 16))
	_add.call(Rect2(636, 148, 12, 48))
	_add.call(Rect2(636, 220, 12, 48))

# ── Zone labels ──────────────────────────────────────────────────────────────
func _draw_zone_labels(font: Font):
	var loot_name := GameManager.get_main_loot_name()
	var label_col := Color(0.55, 0.50, 0.40, 0.38)
	var loot_col  := Color(0.72, 0.60, 0.28, 0.55)
	var sz := 9
	draw_string(font, Vector2(308, 540), "— THE ENTRY FOYER —",    HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2( 32, 430), "— BARRACKS —",           HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(492, 430), "— STOREROOM —",          HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2( 22, 258), "CAPTAIN'S OFFICE",       HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(345, 258), "ANTECHAMBER",            HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(634, 258), "ARMORY",                 HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(320, 100), "— THE VAULT —",          HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(256,  20), loot_name,                HORIZONTAL_ALIGNMENT_LEFT, -1, sz, loot_col)

# ── Room furniture ────────────────────────────────────────────────────────────
func _draw_room_furniture():
	_draw_entry_furniture()
	_draw_barracks_furniture()
	_draw_storeroom_furniture()
	_draw_captain_furniture()
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
func _draw_entry_furniture():
	_svg_booth(280, 472, 20, 24)
	_svg_booth(444, 472, 20, 24)
	for nx: float in [252.0, 472.0]:
		_svg_noticeboard(nx, 544, 22, 16)

func _draw_barracks_furniture():
	for bx: float in [32, 80, 128, 176, 240]:
		_svg_bed(bx, 316, 24, 22)
	var tx: float = 40.0
	while tx < 280.0:
		var tw: float = minf(32.0, 280.0 - tx)
		_svg_table(tx, 388, tw, 16)
		tx += 32.0
	for bench_y: float in [376.0, 406.0]:
		var bx2: float = 48.0
		while bx2 < 272.0:
			_svg_bench(bx2, bench_y, minf(32.0, 272.0 - bx2), 8)
			bx2 += 32.0
	_svg_rack(20, 340, 12, 48)

func _draw_storeroom_furniture():
	for cx: float in [480, 544, 608, 672]:
		_svg_crate(cx, 340, 24, 24)
	for cx: float in [496, 560, 624]:
		_svg_crate(cx, 406, 24, 24)
	_svg_crate(466, 374, 18, 18)
	_svg_crate(658, 380, 18, 18)

func _draw_captain_furniture():
	_svg_table(72, 196, 40, 18)
	_svg_bench(80, 216, 20, 8)
	_svg_plinth(28, 156, 18, 18)
	# Rune carvings on north wall
	var rune := Color(0.50, 0.38, 0.28, 0.42)
	for i in range(4):
		var rx: float = 30.0 + float(i) * 40.0
		draw_circle(Vector2(rx, 136), 2.2, rune)
		draw_line(Vector2(rx - 3.5, 136), Vector2(rx + 3.5, 136), rune, 0.7)
		draw_line(Vector2(rx, 132.5), Vector2(rx, 139.5), rune, 0.7)
		draw_arc(Vector2(rx, 136), 2.2, 0, TAU, 8, Color(rune.r, rune.g, rune.b, 0.25), 0.5)
	# Bookcase
	var bc_col := Color(0.22, 0.14, 0.06)
	draw_rect(Rect2(226, 132, 16, 64), bc_col)
	draw_rect(Rect2(226, 132, 16, 1.2), bc_col.lightened(0.30))
	for by2 in range(4):
		var row_y2: float = 136.0 + float(by2) * 14.0
		draw_rect(Rect2(227, row_y2, 14, 10), Color(0.10, 0.08, 0.06))
		draw_rect(Rect2(226, row_y2 + 10, 16, 1), bc_col.darkened(0.30))
		var bk_cols: Array = [
			Color(0.72, 0.22, 0.18), Color(0.22, 0.55, 0.28),
			Color(0.45, 0.35, 0.65), Color(0.75, 0.65, 0.18),
			Color(0.30, 0.40, 0.65),
		]
		for bi in range(4):
			var bx_book: float = 228.0 + float(bi) * 3.0
			var col: Color = bk_cols[(bi + by2) % bk_cols.size()]
			draw_rect(Rect2(bx_book, row_y2 + 1, 2.4, 8.5), col)
			draw_rect(Rect2(bx_book, row_y2 + 1, 2.4, 0.6), col.lightened(0.30))
			# Gold band
			if (bi + by2) % 2 == 0:
				draw_rect(Rect2(bx_book, row_y2 + 4, 2.4, 0.5),
					Color(0.90, 0.72, 0.20))

func _draw_vault_furniture():
	var pulse: float = abs(sin(_t * 1.5))
	# Floor inlay diamond mosaic
	var inlay := Color(C_FLOOR_VAULT_A.r + 0.08, C_FLOOR_VAULT_A.g + 0.04, C_FLOOR_VAULT_A.b + 0.12, 0.75)
	var pts := PackedVector2Array([
		Vector2(384, 22), Vector2(448, 56),
		Vector2(384, 90), Vector2(320, 56),
	])
	draw_colored_polygon(pts, Color(inlay.r, inlay.g, inlay.b, 0.12))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color(inlay.r, inlay.g, inlay.b, 0.32), 0.8)
	var inner: Array = [Vector2(384, 38), Vector2(416, 56), Vector2(384, 74), Vector2(352, 56)]
	draw_polyline(PackedVector2Array(inner + [inner[0]]),
		Color(inlay.r * 1.5, inlay.g * 1.5, inlay.b * 2.0, 0.40 + pulse * 0.10), 0.7)
	# Arcane glow ground
	var glow: Color = Color(0.58, 0.35, 0.88, 0.16 + pulse * 0.10)
	draw_circle(Vector2(384, 56), 32.0, glow)

	# Grand plinth (artifact)
	_svg_plinth(374, 62, 20, 18)

	# Side altar east
	_svg_plinth(558, 50, 28, 22)

	# Wall bracket sconces
	var bracket := Color(0.42, 0.30, 0.50)
	for sx: float in [162.0, 590.0]:
		draw_rect(Rect2(sx, 18, 12, 8), bracket)
		draw_rect(Rect2(sx + 2, 16, 8, 4), Color(bracket.r * 1.3, bracket.g * 1.2, bracket.b * 1.4))
		draw_line(Vector2(sx + 6, 18), Vector2(sx + 6, 24), bracket, 1.5)

	# Cobwebs
	var web := Color(0.48, 0.44, 0.52, 0.32)
	_draw_cobweb(Vector2(132, 18), Vector2(1, 1), web)
	_draw_cobweb(Vector2(636, 18), Vector2(-1, 1), web)

	# Gold piles
	var gold_a := Color(0.92, 0.74, 0.18)
	var gold_b := Color(0.72, 0.54, 0.10)
	for corner in [Vector2(166, 28), Vector2(598, 28), Vector2(228, 78), Vector2(540, 78)]:
		# Pile shadow
		draw_circle(corner + Vector2(0, 2), 7.0, Color(0, 0, 0, 0.30))
		for ci in range(8):
			var cr: float = 1.4 + float(ci % 3) * 0.7
			var co: Vector2 = Vector2(float(ci % 4) * 3 - 5, float(ci / 4) * 3 - 2)
			draw_circle(corner + co, cr, gold_a if ci % 2 == 0 else gold_b)
			if ci % 3 == 0:
				draw_circle(corner + co - Vector2(0.4, 0.4), cr * 0.4,
					Color(1.0, 0.98, 0.80, 0.65))

func _draw_armory_furniture():
	_svg_rack(636, 148, 12, 52)
	_svg_rack(636, 216, 12, 52)
	_svg_crate(646, 196, 28, 22)
	# Armor stand
	var as_x := 644.0; var as_y := 150.0
	# Shadow
	draw_circle(Vector2(as_x + 8, as_y + 28), 6.0, Color(0, 0, 0, 0.35))
	# Stand pole
	draw_rect(Rect2(as_x + 7, as_y + 24, 2, 8), Color(0.22, 0.18, 0.12))
	# Helm
	draw_circle(Vector2(as_x + 8, as_y + 8), 5.0, Color(0.42, 0.42, 0.50))
	draw_circle(Vector2(as_x + 8, as_y + 7), 4.4, Color(0.52, 0.52, 0.60))
	# Visor slit
	draw_rect(Rect2(as_x + 5, as_y + 7.5, 6, 1), Color(0.10, 0.10, 0.12))
	# Plume
	draw_line(Vector2(as_x + 8, as_y + 3), Vector2(as_x + 7, as_y - 1),
		Color(0.70, 0.20, 0.20), 1.2)
	# Torso
	draw_rect(Rect2(as_x + 3, as_y + 13, 10, 14), Color(0.40, 0.40, 0.46))
	draw_rect(Rect2(as_x + 3, as_y + 13, 10, 1), Color(0.60, 0.60, 0.68))
	# Chest emblem
	draw_circle(Vector2(as_x + 8, as_y + 19), 1.8, Color(0.85, 0.70, 0.22))
	draw_circle(Vector2(as_x + 8, as_y + 19), 1.0, Color(0.60, 0.45, 0.10))
	# Arms (pauldrons)
	draw_circle(Vector2(as_x + 1, as_y + 15), 2.5, Color(0.40, 0.40, 0.46))
	draw_circle(Vector2(as_x + 15, as_y + 15), 2.5, Color(0.40, 0.40, 0.46))

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
