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
	Vector2(256,  20),   # Vault west — north wall
	Vector2(384,  20),   # Vault centre — north wall
	Vector2(512,  20),   # Vault east — north wall
	Vector2(144, 132),   # Captain's Office north wall
	Vector2(456, 132),   # Antechamber north wall
	Vector2(680, 132),   # Armory north wall
	Vector2(160, 308),   # Barracks north wall
	Vector2(600, 308),   # Storeroom north wall
	Vector2(384, 468),   # Entry centre north wall
	Vector2(256, 556),   # Entry south-west
	Vector2(512, 556),   # Entry south-east
]

# ── Room definitions (for fog-of-war tracking) ────────────────────────────────
# 0 = Entry Foyer   1 = Barracks   2 = Storeroom
# 3 = Captain's Office   4 = Antechamber   5 = Vault   6 = Armory
const ROOM_TILE_RECTS: Array[Rect2i] = [
	Rect2i(14, 29, 20,  6),   # Entry Foyer       cols 14-33, rows 29-34
	Rect2i( 1, 19, 18,  9),   # Barracks          cols 1-18,  rows 19-27
	Rect2i(29, 19, 17,  9),   # Storeroom         cols 29-45, rows 19-27
	Rect2i( 1,  8, 16,  9),   # Captain's Office  cols 1-16,  rows 8-16
	Rect2i(20,  8, 17,  9),   # Antechamber       cols 20-36, rows 8-16
	Rect2i( 8,  1, 32,  6),   # Vault             cols 8-39,  rows 1-6
	Rect2i(39,  8,  7,  9),   # Armory            cols 39-45, rows 8-16
]

var map: Array = []

# visited_rooms[i] = true once the player steps inside room i.
# Room 4 (Entry Hall) starts visible since the player spawns there.
var visited_rooms: Array[bool] = [true, false, false, false, false, false, false]

var _t := 0.0
var _tileset: Texture2D = null

# Furniture textures
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
	# V7: all art is procedural SVG-style — no textures needed
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
	# Fill with walls
	map = []
	for r in range(MAP_ROWS):
		var row: Array = []
		for c in range(MAP_COLS):
			row.append(WALL)
		map.append(row)

	# ── Top: single vault room
	_carve(Rect2i( 8,  1, 32,  6))   # Vault (cols 8-39, rows 1-6)

	# Vault ↔ mid-level corridors
	_carve(Rect2i( 8,  6,  2,  3))   # Captain's Office → Vault (cols 8-9, rows 6-8)
	_carve(Rect2i(26,  6,  2,  3))   # Antechamber → Vault LOCKED (cols 26-27, rows 6-8)

	# ── Mid level: three rooms
	_carve(Rect2i( 1,  8, 16,  9))   # Captain's Office (cols 1-16, rows 8-16)
	_carve(Rect2i(20,  8, 17,  9))   # Antechamber (cols 20-36, rows 8-16)
	_carve(Rect2i(39,  8,  7,  9))   # Armory (cols 39-45, rows 8-16)

	# Mid-level lateral corridors
	_carve(Rect2i(17, 11,  3,  3))   # Captain's ↔ Antechamber (cols 17-19, rows 11-13)
	_carve(Rect2i(37, 11,  2,  3))   # Antechamber → Armory (cols 37-38, rows 11-13)

	# Mid-level ↔ lower-level corridors
	_carve(Rect2i( 8, 17,  2,  2))   # Captain's → Barracks (cols 8-9, rows 17-18)
	_carve(Rect2i(35, 17,  2,  2))   # Antechamber → Storeroom (cols 35-36, rows 17-18)

	# ── Lower level: two rooms
	_carve(Rect2i( 1, 19, 18,  9))   # Barracks (cols 1-18, rows 19-27)
	_carve(Rect2i(29, 19, 17,  9))   # Storeroom (cols 29-45, rows 19-27)

	# Lower-level ↔ entry corridors
	_carve(Rect2i(15, 27,  2,  2))   # Barracks → Entry (cols 15-16, rows 27-28)
	_carve(Rect2i(31, 27,  2,  2))   # Storeroom → Entry (cols 31-32, rows 27-28)

	# ── Bottom: entry foyer
	_carve(Rect2i(14, 29, 20,  6))   # Entry Foyer (cols 14-33, rows 29-34)

func _carve(rect: Rect2i):
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			if r >= 0 and r < MAP_ROWS and c >= 0 and c < MAP_COLS:
				map[r][c] = FLOOR

func _randomize_cover():
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.run_seed + GameManager.current_floor * 31337

	# Vault single-tile pillars (sparse, to preserve line-of-sight gameplay)
	var vpillars := [
		Vector2i(13, 3), Vector2i(21, 4), Vector2i(29, 3), Vector2i(37, 4)
	]
	for p in vpillars:
		if rng.randi_range(0, 2) != 0:
			if p.y > 0 and p.y < MAP_ROWS - 1 and p.x > 0 and p.x < MAP_COLS - 1:
				map[p.y][p.x] = WALL

	# Captain's Office 2×2 pillars
	var capillars := [Vector2i(4, 10), Vector2i(11, 13)]
	for p in capillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Antechamber 2×2 pillars
	var antipillars := [Vector2i(22, 10), Vector2i(30, 13)]
	for p in antipillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Barracks pillars
	var bpillars := [Vector2i(3, 21), Vector2i(10, 24), Vector2i(15, 21)]
	for p in bpillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Storeroom pillars
	var spillars := [Vector2i(31, 21), Vector2i(38, 24), Vector2i(43, 21)]
	for p in spillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Entry Foyer pillars (wide spacing for clear sightlines at start)
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
	if tc.y >= 29 and tc.y <= 34 and tc.x >= 14 and tc.x <= 33: return 0  # Entry Foyer
	if tc.y >= 19 and tc.y <= 27 and tc.x >=  1 and tc.x <= 18: return 1  # Barracks
	if tc.y >= 19 and tc.y <= 27 and tc.x >= 29 and tc.x <= 45: return 2  # Storeroom
	if tc.y >=  8 and tc.y <= 16 and tc.x >=  1 and tc.x <= 16: return 3  # Captain's Office
	if tc.y >=  8 and tc.y <= 16 and tc.x >= 20 and tc.x <= 36: return 4  # Antechamber
	if tc.y >=  1 and tc.y <=  6 and tc.x >=  8 and tc.x <= 39: return 5  # Vault
	if tc.y >=  8 and tc.y <= 16 and tc.x >= 39 and tc.x <= 45: return 6  # Armory
	return -1

# ── Zone helpers ──────────────────────────────────────────────────────────────
func _get_zone(row: int) -> int:
	if row <=  7: return 0   # vault (top)
	if row <= 28: return 1   # mid floors
	return 2                  # entry (bottom)

func _apply_floor_theme():
	match GameManager.current_floor:
		1:  # The Cellars — warm sandstone, amber torchlight
			C_FLOOR_VAULT_A  = Color(0.14, 0.11, 0.07); C_FLOOR_VAULT_B  = Color(0.16, 0.13, 0.09)
			C_FLOOR_MID_A    = Color(0.12, 0.10, 0.07); C_FLOOR_MID_B    = Color(0.14, 0.12, 0.08)
			C_FLOOR_ENTRY_A  = Color(0.16, 0.12, 0.08); C_FLOOR_ENTRY_B  = Color(0.19, 0.14, 0.09)
			C_WALL_VAULT     = Color(0.42, 0.30, 0.18); C_WALL_VAULT_E   = Color(0.62, 0.46, 0.28)
			C_WALL_MID       = Color(0.36, 0.28, 0.18); C_WALL_MID_E     = Color(0.54, 0.40, 0.26)
			C_WALL_ENTRY     = Color(0.38, 0.28, 0.18); C_WALL_ENTRY_E   = Color(0.56, 0.42, 0.26)
		2:  # The Barracks — military stone, cool green-grey shadows
			C_FLOOR_VAULT_A  = Color(0.08, 0.07, 0.13); C_FLOOR_VAULT_B  = Color(0.10, 0.09, 0.16)
			C_FLOOR_MID_A    = Color(0.08, 0.10, 0.08); C_FLOOR_MID_B    = Color(0.10, 0.12, 0.09)
			C_FLOOR_ENTRY_A  = Color(0.11, 0.09, 0.07); C_FLOOR_ENTRY_B  = Color(0.13, 0.11, 0.08)
			C_WALL_VAULT     = Color(0.18, 0.14, 0.28); C_WALL_VAULT_E   = Color(0.32, 0.24, 0.48)
			C_WALL_MID       = Color(0.20, 0.18, 0.14); C_WALL_MID_E     = Color(0.36, 0.30, 0.22)
			C_WALL_ENTRY     = Color(0.28, 0.22, 0.16); C_WALL_ENTRY_E   = Color(0.44, 0.34, 0.24)
		_:  # The Inner Vault — ceremonially cold, near-black blue stone
			C_FLOOR_VAULT_A  = Color(0.05, 0.06, 0.10); C_FLOOR_VAULT_B  = Color(0.07, 0.08, 0.13)
			C_FLOOR_MID_A    = Color(0.07, 0.08, 0.08); C_FLOOR_MID_B    = Color(0.08, 0.09, 0.10)
			C_FLOOR_ENTRY_A  = Color(0.08, 0.08, 0.09); C_FLOOR_ENTRY_B  = Color(0.10, 0.10, 0.11)
			C_WALL_VAULT     = Color(0.14, 0.16, 0.28); C_WALL_VAULT_E   = Color(0.24, 0.28, 0.46)
			C_WALL_MID       = Color(0.16, 0.18, 0.22); C_WALL_MID_E     = Color(0.26, 0.30, 0.38)
			C_WALL_ENTRY     = Color(0.18, 0.18, 0.22); C_WALL_ENTRY_E   = Color(0.28, 0.28, 0.36)

# ── Drawing ───────────────────────────────────────────────────────────────────
func _draw():
	var font    := ThemeDB.fallback_font
	var map_w   := MAP_COLS * TILE_SIZE
	var map_h   := MAP_ROWS * TILE_SIZE

	# Floor tiles
	for row in range(map.size()):
		for col in range(map[row].size()):
			if map[row][col] != FLOOR:
				continue
			var x    := float(col * TILE_SIZE)
			var y    := float(row * TILE_SIZE)
			var zone := _get_zone(row)
			var dest := Rect2(x, y, TILE_SIZE, TILE_SIZE)
			if _tileset != null:
				# Tileset row 0 = floors; columns 0/1/2 = vault/barracks/entry
				var src := Rect2(zone * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE)
				draw_texture_rect_region(_tileset, dest, src)
				# Subtle grout-edge overlay preserved from original style
				draw_rect(dest, Color(0, 0, 0, 0.18), false, 0.5)
			else:
				var alt  := (row + col) % 4 == 0
				var fa: Color; var fb: Color
				match zone:
					0: fa = C_FLOOR_VAULT_A;  fb = C_FLOOR_VAULT_B
					1: fa = C_FLOOR_MID_A;    fb = C_FLOOR_MID_B
					_: fa = C_FLOOR_ENTRY_A;  fb = C_FLOOR_ENTRY_B
				draw_rect(dest, fb if alt else fa)
				draw_rect(dest, Color(0, 0, 0, 0.25), false, 0.5)

	# Torch glow pools (behind walls, drawn before walls)
	for i in range(TORCHES.size()):
		var tp := TORCHES[i]
		if _is_torch_lit(tp):
			_draw_torch_glow(tp, i)

	# Wall tiles
	for row in range(map.size()):
		for col in range(map[row].size()):
			if map[row][col] != WALL:
				continue
			var x    := float(col * TILE_SIZE)
			var y    := float(row * TILE_SIZE)
			var zone := _get_zone(row)
			var dest := Rect2(x, y, TILE_SIZE, TILE_SIZE)
			if _tileset != null:
				# Tileset row 1 = walls; columns 0/1/2 = vault/barracks/entry
				var src := Rect2(zone * TILE_SIZE, TILE_SIZE, TILE_SIZE, TILE_SIZE)
				draw_texture_rect_region(_tileset, dest, src)
				# Preserve depth cues from original style
				var ce: Color
				match zone:
					0: ce = C_WALL_VAULT_E
					1: ce = C_WALL_MID_E
					_: ce = C_WALL_ENTRY_E
				draw_rect(Rect2(x, y, TILE_SIZE, 2), Color(ce.r, ce.g, ce.b, 0.55))
				draw_rect(Rect2(x + TILE_SIZE - 1, y + 2, 1, TILE_SIZE - 2), Color(0, 0, 0, 0.28))
				if row + 1 < map.size() and map[row + 1][col] == FLOOR:
					draw_rect(Rect2(x, y + TILE_SIZE - 2, TILE_SIZE, 2), Color(0, 0, 0, 0.45))
			else:
				var cw: Color; var ce: Color
				match zone:
					0: cw = C_WALL_VAULT;  ce = C_WALL_VAULT_E
					1: cw = C_WALL_MID;    ce = C_WALL_MID_E
					_: cw = C_WALL_ENTRY;  ce = C_WALL_ENTRY_E
				var v  := ((row * 7 + col * 3) % 6) * 0.013
				var wc := Color(cw.r - v, cw.g - v * 0.5, cw.b - v * 0.3)
				draw_rect(dest, wc)
				draw_rect(Rect2(x, y, TILE_SIZE, 2), ce)
				draw_rect(Rect2(x + TILE_SIZE - 1, y + 2, 1, TILE_SIZE - 2), Color(0, 0, 0, 0.28))
				if row + 1 < map.size() and map[row + 1][col] == FLOOR:
					draw_rect(Rect2(x, y + TILE_SIZE - 2, TILE_SIZE, 2), Color(0, 0, 0, 0.40))
				draw_rect(Rect2(x, y + TILE_SIZE * 0.5 - 0.5, TILE_SIZE, 1.0), Color(0, 0, 0, 0.18))

	# Room-specific furniture (drawn after walls, before torch flames)
	_draw_room_furniture()

	# Zone name labels — faint, etched-stone style
	_draw_zone_labels(font)

	# Torch flame dots
	for i in range(TORCHES.size()):
		var tp := TORCHES[i]
		if not _is_torch_lit(tp):
			continue
		var flicker  := sin(_t * 5.3 + i * 1.7) * 0.3 + sin(_t * 11.1 + i * 0.9) * 0.15
		var flame_r  := 2.5 + flicker * 0.6
		var flame_c  := Color(1.0, 0.48 + flicker * 0.12, 0.04 + flicker * 0.06)
		draw_circle(tp, flame_r + 1.2, Color(0, 0, 0, 0.25))
		draw_circle(tp, flame_r, flame_c)
		draw_circle(tp, flame_r * 0.55, Color(1.0, 0.92, 0.60 + flicker * 0.1))

	# Edge vignette
	var vw := 40.0
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

	# Subtle zone divider tint strips at room boundaries
	var vault_y := 8 * TILE_SIZE    # row 8 — top of mid-level rooms
	draw_rect(Rect2(0, vault_y - 3, map_w, 3), Color(0.22, 0.10, 0.35, 0.22))
	var bar_y := 19 * TILE_SIZE     # row 19 — top of barracks/storeroom
	draw_rect(Rect2(0, bar_y - 3, map_w, 3), Color(0.10, 0.25, 0.12, 0.22))
	var entry_y := 29 * TILE_SIZE   # row 29 — top of entry foyer
	draw_rect(Rect2(0, entry_y - 3, map_w, 3), Color(0.15, 0.15, 0.25, 0.22))

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

	# ── Entry Foyer — guard booths
	_add.call(Rect2(280, 472, 20, 24))
	_add.call(Rect2(444, 472, 20, 24))

	# ── Barracks — beds along north wall
	for bx: float in [32.0, 80.0, 128.0, 176.0, 240.0]:
		_add.call(Rect2(bx, 316, 24, 14))
	_add.call(Rect2(20, 340, 12, 48))   # weapon rack

	# ── Storeroom — crate stacks
	for cx: float in [480.0, 544.0, 608.0, 672.0]:
		_add.call(Rect2(cx, 340, 24, 24))

	# ── Captain's Office — desk
	_add.call(Rect2(80, 200, 32, 16))

	# ── Armory — weapon racks
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

# ── Room furniture (full SVG procedural art) ──────────────────────────────────
func _draw_room_furniture():
	_draw_entry_furniture()
	_draw_barracks_furniture()
	_draw_storeroom_furniture()
	_draw_captain_furniture()
	_draw_vault_furniture()
	_draw_armory_furniture()

func _svg_bed(x: float, y: float, w: float, h: float):
	var frame  := Color(0.28, 0.20, 0.10)
	var mattress := Color(0.52, 0.40, 0.28)
	var pillow := Color(0.82, 0.76, 0.65)
	var sheet  := Color(0.62, 0.52, 0.38)
	draw_rect(Rect2(x, y, w, h), frame)
	draw_rect(Rect2(x + 1, y + 1, w - 2, h - 2), mattress)
	draw_rect(Rect2(x + 1, y + 1, w - 2, h * 0.55), sheet)
	draw_rect(Rect2(x + 2, y + 2, (w - 4) * 0.55, h * 0.28), pillow)
	# Pillow seam
	draw_line(Vector2(x + 2 + (w - 4) * 0.275, y + 2), Vector2(x + 2 + (w - 4) * 0.275, y + 2 + h * 0.28),
		Color(pillow.r * 0.80, pillow.g * 0.80, pillow.b * 0.80, 0.60), 0.7)

func _svg_crate(x: float, y: float, w: float, h: float):
	var wood  := Color(0.42, 0.28, 0.14)
	var plank := Color(0.55, 0.38, 0.20)
	var band  := Color(0.30, 0.22, 0.10)
	draw_rect(Rect2(x, y, w, h), wood)
	draw_rect(Rect2(x + 1, y + 1, w - 2, h - 2), plank)
	# Plank lines
	draw_line(Vector2(x + 1, y + h * 0.33), Vector2(x + w - 1, y + h * 0.33), band, 0.7)
	draw_line(Vector2(x + 1, y + h * 0.66), Vector2(x + w - 1, y + h * 0.66), band, 0.7)
	# Metal bands
	draw_rect(Rect2(x, y, w, 2), band)
	draw_rect(Rect2(x, y + h - 2, w, 2), band)

func _svg_table(x: float, y: float, w: float, h: float):
	var leg   := Color(0.32, 0.22, 0.10)
	var top   := Color(0.50, 0.36, 0.18)
	var edge  := Color(0.38, 0.26, 0.12)
	draw_rect(Rect2(x, y, w, h), leg)
	draw_rect(Rect2(x + 1, y + 1, w - 2, h - 3), top)
	draw_rect(Rect2(x + 1, y + 1, w - 2, 1), Color(top.r * 1.3, top.g * 1.3, top.b * 1.2, 0.60))

func _svg_bench(x: float, y: float, w: float, h: float):
	var wood := Color(0.38, 0.26, 0.12)
	var seat := Color(0.50, 0.36, 0.18)
	draw_rect(Rect2(x, y, w, h), wood)
	draw_rect(Rect2(x + 1, y + 1, w - 2, h - 2), seat)

func _svg_rack(x: float, y: float, w: float, h: float):
	var frame := Color(0.30, 0.20, 0.08)
	var bar   := Color(0.48, 0.35, 0.18)
	draw_rect(Rect2(x, y, w, h), frame)
	# Horizontal pegs at intervals
	var peg_y := y + 6.0
	while peg_y < y + h - 4:
		draw_rect(Rect2(x - 3, peg_y, w + 6, 2), bar)
		# Weapon silhouettes on pegs
		draw_line(Vector2(x - 4, peg_y + 1), Vector2(x - 12, peg_y - 4), Color(0.60, 0.58, 0.65), 0.8)
		peg_y += 10.0

func _svg_plinth(x: float, y: float, w: float, h: float):
	var stone := Color(0.38, 0.32, 0.28)
	var top   := Color(0.50, 0.42, 0.36)
	var base  := Color(0.28, 0.22, 0.18)
	draw_rect(Rect2(x, y + 2, w, h - 2), stone)
	draw_rect(Rect2(x + 1, y + 2, w - 2, h - 4), top)
	draw_rect(Rect2(x - 1, y + h - 3, w + 2, 3), base)
	draw_rect(Rect2(x - 1, y, w + 2, 3), base)

func _svg_booth(x: float, y: float, w: float, h: float):
	var wood   := Color(0.32, 0.24, 0.12)
	var face   := Color(0.42, 0.32, 0.16)
	var ledge  := Color(0.50, 0.38, 0.20)
	draw_rect(Rect2(x, y, w, h), wood)
	draw_rect(Rect2(x + 1, y + 1, w - 2, h - 2), face)
	# Counter ledge
	draw_rect(Rect2(x - 1, y + h * 0.35, w + 2, 3), ledge)
	draw_rect(Rect2(x - 1, y + h * 0.35, w + 2, 1), Color(ledge.r * 1.3, ledge.g * 1.3, ledge.b * 1.2, 0.55))

func _svg_noticeboard(x: float, y: float, w: float, h: float):
	var frame   := Color(0.32, 0.22, 0.10)
	var cork    := Color(0.60, 0.45, 0.28)
	var note1   := Color(0.88, 0.82, 0.65)
	var note2   := Color(0.75, 0.72, 0.55)
	draw_rect(Rect2(x, y, w, h), frame)
	draw_rect(Rect2(x + 1, y + 1, w - 2, h - 2), cork)
	draw_rect(Rect2(x + 2, y + 2, 7, 5), note1)
	draw_rect(Rect2(x + 11, y + 3, 8, 4), note2)
	draw_rect(Rect2(x + 3, y + 9, 12, 3), note1)

func _draw_entry_furniture():
	# Guard booths
	_svg_booth(280, 472, 20, 24)
	_svg_booth(444, 472, 20, 24)
	# Notice boards on south wall
	for nx: float in [252.0, 472.0]:
		_svg_noticeboard(nx, 544, 22, 16)

func _draw_barracks_furniture():
	# Beds along north wall
	for bx: float in [32, 80, 128, 176, 240]:
		_svg_bed(bx, 316, 24, 22)
	# Communal table
	var tx := 40.0
	while tx < 280.0:
		var tw := minf(32.0, 280.0 - tx)
		_svg_table(tx, 388, tw, 16)
		tx += 32.0
	# Benches above and below table
	for bench_y: float in [376.0, 406.0]:
		var bx2 := 48.0
		while bx2 < 272.0:
			_svg_bench(bx2, bench_y, minf(32.0, 272.0 - bx2), 8)
			bx2 += 32.0
	# Weapon rack in NW corner
	_svg_rack(20, 340, 12, 48)

func _draw_storeroom_furniture():
	# Crate stacks in rows
	for cx: float in [480, 544, 608, 672]:
		_svg_crate(cx, 340, 24, 24)
	for cx: float in [496, 560, 624]:
		_svg_crate(cx, 406, 24, 24)
	# Additional scattered crates
	_svg_crate(466, 374, 18, 18)
	_svg_crate(658, 380, 18, 18)

func _draw_captain_furniture():
	# Captain's ornate desk
	_svg_table(72, 196, 40, 18)
	_svg_bench(80, 216, 20, 8)
	# Evidence plinth with glow
	_svg_plinth(28, 156, 18, 16)
	var plinth_glow := Color(0.55, 0.40, 0.25, 0.22 + abs(sin(_t * 0.9)) * 0.10)
	draw_circle(Vector2(37, 158), 8.0, plinth_glow)
	# Rune carvings on north wall
	var rune := Color(0.50, 0.38, 0.28, 0.42)
	for i in range(4):
		var rx := 30.0 + i * 40.0
		draw_circle(Vector2(rx, 136), 2.2, rune)
		draw_line(Vector2(rx - 3.5, 136), Vector2(rx + 3.5, 136), rune, 0.7)
		draw_line(Vector2(rx, 132.5), Vector2(rx, 139.5), rune, 0.7)
		draw_arc(Vector2(rx, 136), 2.2, 0, TAU, 8, Color(rune.r, rune.g, rune.b, 0.25), 0.5)
	# Bookcase along east wall
	var bc_col := Color(0.28, 0.18, 0.08)
	draw_rect(Rect2(226, 132, 16, 64), bc_col)
	for by2 in range(4):
		var row_y2 := 136.0 + by2 * 14.0
		draw_rect(Rect2(227, row_y2, 14, 10), Color(0.18, 0.28, 0.45))
		draw_rect(Rect2(228, row_y2 + 1, 12, 8), Color(0.22, 0.32, 0.50))
		# Book spines
		for bi in range(4):
			var bk_cols := [Color(0.72, 0.22, 0.18), Color(0.22, 0.55, 0.28), Color(0.45, 0.35, 0.65), Color(0.75, 0.65, 0.18)]
			draw_rect(Rect2(228 + bi * 3, row_y2 + 1, 2, 8), bk_cols[bi])

func _draw_vault_furniture():
	# Animated arcane glow at vault centre
	var pulse: float = abs(sin(_t * 1.5))
	var glow  := Color(0.58, 0.35, 0.88, 0.16 + pulse * 0.10)
	draw_circle(Vector2(384, 56), 32.0, glow)
	draw_circle(Vector2(384, 56), 18.0, Color(0.70, 0.50, 1.00, 0.08 + pulse * 0.06))
	# Grand plinth
	_svg_plinth(374, 62, 20, 16)
	# Glowing artifact on plinth
	var art_col := Color(0.80, 0.60, 1.00, 0.72 + pulse * 0.20)
	draw_circle(Vector2(384, 64), 3.5, art_col)
	draw_arc(Vector2(384, 64), 5.0, 0, TAU, 14, Color(art_col.r, art_col.g, art_col.b, 0.45), 1.0)
	# Floor inlay diamond mosaic
	var inlay := Color(C_FLOOR_VAULT_A.r + 0.08, C_FLOOR_VAULT_A.g + 0.04, C_FLOOR_VAULT_A.b + 0.12, 0.75)
	var pts := PackedVector2Array([
		Vector2(384, 22), Vector2(448, 56),
		Vector2(384, 90), Vector2(320, 56),
	])
	draw_colored_polygon(pts, Color(inlay.r, inlay.g, inlay.b, 0.10))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color(inlay.r, inlay.g, inlay.b, 0.28), 0.8)
	# Inner diamond
	var inner := [Vector2(384, 38), Vector2(416, 56), Vector2(384, 74), Vector2(352, 56)]
	draw_polyline(PackedVector2Array(inner + [inner[0]]),
		Color(inlay.r * 1.5, inlay.g * 1.5, inlay.b * 2.0, 0.40 + pulse * 0.10), 0.7)
	# Side altar to the east
	var altar_pulse := Color(0.88, 0.72, 0.28, 0.14 + abs(sin(_t * 0.85)) * 0.08)
	draw_circle(Vector2(572, 56), 22.0, altar_pulse)
	_svg_plinth(558, 44, 28, 22)
	draw_circle(Vector2(572, 46), 5.5, Color(0.95, 0.82, 0.35, 0.65 + abs(sin(_t * 2.2)) * 0.22))
	# Wall bracket sconces (decorative)
	var bracket := Color(0.42, 0.30, 0.50)
	for sx: float in [162.0, 590.0]:
		draw_rect(Rect2(sx, 18, 12, 8), bracket)
		draw_rect(Rect2(sx + 2, 16, 8, 4), Color(bracket.r * 1.3, bracket.g * 1.2, bracket.b * 1.4))
		draw_line(Vector2(sx + 6, 18), Vector2(sx + 6, 24), bracket, 1.5)
	# Cobwebs in vault corners
	var web := Color(0.48, 0.44, 0.52, 0.32)
	_draw_cobweb(Vector2(132, 18), Vector2(1, 1), web)
	_draw_cobweb(Vector2(636, 18), Vector2(-1, 1), web)
	# Gold treasure pile clusters near altar and vault edge
	var gold_a := Color(0.88, 0.70, 0.15)
	var gold_b := Color(0.72, 0.54, 0.10)
	for corner in [Vector2(166, 28), Vector2(598, 28), Vector2(228, 78), Vector2(540, 78)]:
		for ci in range(6):
			var cr := 1.6 + (ci % 3) * 0.9
			var co := Vector2(float(ci % 3) * 5 - 5, float(ci / 3) * 4 - 2)
			draw_circle(corner + co, cr, gold_a if ci % 2 == 0 else gold_b)
			if ci == 0:
				draw_circle(corner + co - Vector2(0.5, 0.5), cr * 0.4, Color(1.0, 0.96, 0.80, 0.55))

func _draw_armory_furniture():
	# Weapon racks along east wall
	_svg_rack(636, 148, 12, 52)
	_svg_rack(636, 216, 12, 52)
	# Storage crate
	_svg_crate(646, 196, 28, 22)
	# Armor stand (simple silhouette)
	var as_x := 644.0; var as_y := 150.0
	draw_circle(Vector2(as_x + 8, as_y + 8), 5.0, Color(0.45, 0.42, 0.48))  # helm
	draw_rect(Rect2(as_x + 3, as_y + 13, 10, 14), Color(0.40, 0.38, 0.42))  # torso
	draw_line(Vector2(as_x + 3, as_y + 16), Vector2(as_x - 3, as_y + 24), Color(0.40, 0.38, 0.42), 2.0)  # arm L
	draw_line(Vector2(as_x + 13, as_y + 16), Vector2(as_x + 19, as_y + 24), Color(0.40, 0.38, 0.42), 2.0)  # arm R

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
	var flicker    := sin(_t * 5.3 + idx * 1.7) * 0.3 + sin(_t * 11.1 + idx * 0.9) * 0.15
	var gs         := 1.0 + flicker * 0.08
	draw_circle(center, 44.0 * gs, Color(1.0, 0.62, 0.12, 0.045))
	draw_circle(center, 28.0 * gs, Color(1.0, 0.68, 0.18, 0.085 + flicker * 0.02))
	draw_circle(center, 15.0 * gs, Color(1.0, 0.78, 0.28, 0.150 + flicker * 0.03))
	draw_circle(center,  7.0 * gs, Color(1.0, 0.88, 0.44, 0.220 + flicker * 0.04))
