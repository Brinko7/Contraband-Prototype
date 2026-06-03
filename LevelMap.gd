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
	# Outer wall sconces
	Vector2( 64,  40),   # Vault Left — north wall
	Vector2(352,  40),   # Vault Centre — north wall
	Vector2(624,  40),   # Vault Right — north wall (fogged until unlocked)
	Vector2(  8, 256),   # Barracks left wall
	Vector2(760, 256),   # Barracks right wall
	Vector2(  8, 464),   # Entry left wall
	Vector2(760, 464),   # Entry right wall
	# Interior sconces
	Vector2(192, 176),   # Barracks north wall, west
	Vector2(544, 176),   # Barracks north wall, east
	Vector2(256, 128),   # Vault Centre south face, west
	Vector2(448, 128),   # Vault Centre south face, east
	Vector2(192, 368),   # Entry — above west corridor exit
	Vector2(576, 368),   # Entry — above east corridor exit
]

# ── Room definitions (for fog-of-war tracking) ────────────────────────────────
# Indices must match FogOfWar.ROOM_FOG_RECTS and visited_rooms.
# 0 = Vault Left   1 = Vault Centre   2 = Vault Right
# 3 = Barracks     4 = Entry Hall
const ROOM_TILE_RECTS: Array[Rect2i] = [
	Rect2i( 1,  1, 12,  8),   # Vault Left   cols 1-12, rows 1-8
	Rect2i(15,  1, 16,  8),   # Vault Centre cols 15-30, rows 1-8
	Rect2i(33,  1, 13,  8),   # Vault Right  cols 33-45, rows 1-8
	Rect2i( 1, 11, 46, 10),   # Barracks     cols 1-46,  rows 11-20
	Rect2i( 1, 23, 46, 11),   # Entry Hall   cols 1-46,  rows 23-33
]

var map: Array = []

# visited_rooms[i] = true once the player steps inside room i.
# Room 4 (Entry Hall) starts visible since the player spawns there.
var visited_rooms: Array[bool] = [false, false, false, false, true]

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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tileset    = load("res://sprites/tileset.png")     as Texture2D
	_tex_booth  = load("res://sprites/furn_booth.png")  as Texture2D
	_tex_crate  = load("res://sprites/furn_crate.png")  as Texture2D
	_tex_board  = load("res://sprites/furn_noticeboard.png") as Texture2D
	_tex_bed    = load("res://sprites/furn_bed.png")    as Texture2D
	_tex_table  = load("res://sprites/furn_table.png")  as Texture2D
	_tex_bench  = load("res://sprites/furn_bench.png")  as Texture2D
	_tex_rack   = load("res://sprites/furn_rack.png")   as Texture2D
	_tex_plinth = load("res://sprites/furn_plinth.png") as Texture2D
	_tex_altar  = load("res://sprites/furn_altar.png")  as Texture2D
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

	# Vault chambers
	_carve(Rect2i( 1,  1, 12, 8))   # Vault Left
	_carve(Rect2i(15,  1, 16, 8))   # Vault Centre
	_carve(Rect2i(33,  1, 13, 8))   # Vault Right (LOCKED)

	# Vault Left ↔ Vault Centre — open corridor (cols 13-14, rows 4-5)
	_carve(Rect2i(13, 4, 2, 2))

	# Vault Centre ↔ Vault Right — LOCKED corridor (cols 31-32, rows 4-5)
	# Tiles are carved as floor; a LockedDoor node blocks the gap in-world.
	_carve(Rect2i(31, 4, 2, 2))

	# Vault Left  → Barracks corridor (cols 5-6, rows 9-10)
	_carve(Rect2i(5,  9, 2, 2))
	# Vault Centre → Barracks corridor (cols 20-21, rows 9-10)
	_carve(Rect2i(20, 9, 2, 2))

	# Barracks (full width)
	_carve(Rect2i(1, 11, 46, 10))

	# Barracks → Entry west corridor (cols 10-11, rows 21-22)
	_carve(Rect2i(10, 21, 2, 2))
	# Barracks → Entry east corridor (cols 35-36, rows 21-22)
	_carve(Rect2i(35, 21, 2, 2))

	# Entry Hall
	_carve(Rect2i(1, 23, 46, 11))

func _carve(rect: Rect2i):
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			if r >= 0 and r < MAP_ROWS and c >= 0 and c < MAP_COLS:
				map[r][c] = FLOOR

func _randomize_cover():
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.run_seed + GameManager.current_floor * 31337

	# Barracks pillar candidates (upper-left corner of each 2×2 block)
	var bpillars := [
		Vector2i( 3, 13), Vector2i(13, 16), Vector2i(24, 13),
		Vector2i(33, 16), Vector2i(43, 13)
	]
	for p in bpillars:
		if rng.randi_range(0, 2) != 0:   # 2/3 chance to place
			_place_pillar(p.x, p.y)

	# Entry Hall pillar candidates
	var epillars := [
		Vector2i( 5, 25), Vector2i(20, 29), Vector2i(38, 25), Vector2i(42, 29)
	]
	for p in epillars:
		if rng.randi_range(0, 2) != 0:
			_place_pillar(p.x, p.y)

	# Vault pillar cover (single-wide, 1-tile blocks)
	var vpillars := [
		Vector2i( 3, 3), Vector2i(10, 5),   # Vault Left
		Vector2i(18, 3), Vector2i(26, 6),   # Vault Centre
	]
	for p in vpillars:
		if rng.randi_range(0, 2) != 0:
			if p.y > 0 and p.y < MAP_ROWS - 1 and p.x > 0 and p.x < MAP_COLS - 1:
				map[p.y][p.x] = WALL

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
	if tc.y >= 23 and tc.y <= 33:  return 4   # Entry Hall
	if tc.y >= 11 and tc.y <= 20:  return 3   # Barracks
	if tc.y >= 1  and tc.y <= 8:
		if tc.x >= 1  and tc.x <= 12: return 0  # Vault Left
		if tc.x >= 15 and tc.x <= 30: return 1  # Vault Centre
		if tc.x >= 33 and tc.x <= 45: return 2  # Vault Right
	return -1

# ── Zone helpers ──────────────────────────────────────────────────────────────
func _get_zone(row: int) -> int:
	if row <= 10: return 0   # vault
	if row <= 22: return 1   # barracks
	return 2                  # entry

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

	# Subtle zone divider tint strips — no text, just a colour shift at the boundary
	var vault_y := 11 * TILE_SIZE
	draw_rect(Rect2(0, vault_y - 3, map_w, 3), Color(0.22, 0.10, 0.35, 0.22))
	var bar_y := 23 * TILE_SIZE
	draw_rect(Rect2(0, bar_y - 3, map_w, 3), Color(0.10, 0.25, 0.12, 0.22))

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

	# ── Entry Hall ────────────────────────────────────────────────────────────
	_add.call(Rect2(152, 368, 20, 24))
	_add.call(Rect2(528, 368, 20, 24))
	_add.call(Rect2(16,  432, 24, 36))   # west crate stack (moved down, clear of paths)
	_add.call(Rect2(704, 432, 24, 36))   # east crate stack

	# ── Barracks ──────────────────────────────────────────────────────────────
	# Beds hug the north wall — collision is just the frame (not footlocker) so
	# guards can stand beside them without clipping.
	for bx: float in [48.0, 112.0, 192.0, 368.0, 464.0, 560.0, 640.0]:
		_add.call(Rect2(bx, 180, 24, 14))
	# Weapon rack — narrow, north-west corner only
	_add.call(Rect2(18, 208, 12, 48))

# ── Zone labels ──────────────────────────────────────────────────────────────
func _draw_zone_labels(font: Font):
	var loot_name := GameManager.get_main_loot_name()
	var label_col := Color(0.55, 0.50, 0.40, 0.38)
	var loot_col  := Color(0.72, 0.60, 0.28, 0.55)
	var sz := 9
	# Entry hall label
	draw_string(font, Vector2(320, 540), "— THE ENTRY HALL —",
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	# Barracks label
	draw_string(font, Vector2(310, 345), "— THE BARRACKS —",
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	# Vault labels
	draw_string(font, Vector2(32, 145), "VAULT I",
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(288, 145), "VAULT II",
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	draw_string(font, Vector2(550, 145), "INNER VAULT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_col)
	# Named target hint near primary vault
	draw_string(font, Vector2(256, 20), loot_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, loot_col)

# ── Room furniture ────────────────────────────────────────────────────────────
func _draw_room_furniture():
	if not _tex_booth:
		return
	_draw_entry_furniture()
	_draw_barracks_furniture()
	_draw_vault_left_furniture()
	_draw_vault_centre_furniture()
	_draw_vault_right_furniture()

func _tex(tex: Texture2D, dest: Rect2):
	draw_texture_rect(tex, dest, false)

func _draw_entry_furniture():
	# Guard booths
	for bx in [152.0, 528.0]:
		_tex(_tex_booth, Rect2(bx, 368, 20, 24))
	# Crate stacks
	for cx in [16.0, 704.0]:
		_tex(_tex_crate, Rect2(cx, 432, 24, 36))
	# Notice boards
	for nx in [88.0, 640.0]:
		_tex(_tex_board, Rect2(nx, 508, 22, 16))

func _draw_barracks_furniture():
	# Beds along north wall
	for bx: float in [48, 112, 192, 368, 464, 560, 640]:
		_tex(_tex_bed, Rect2(bx, 180, 24, 22))
	# Communal table — tile the 32px sprite across 288px width
	var tx := 240.0
	while tx < 528.0:
		var tw := minf(32.0, 528.0 - tx)
		_tex(_tex_table, Rect2(tx, 262, tw, 16))
		tx += 32.0
	# Benches — tile above and below table
	for bench_y in [250.0, 280.0]:
		var bx2 := 248.0
		while bx2 < 520.0:
			var bw := minf(32.0, 520.0 - bx2)
			_tex(_tex_bench, Rect2(bx2, bench_y, bw, 8))
			bx2 += 32.0
	# Weapon rack
	_tex(_tex_rack, Rect2(18, 208, 12, 48))

func _draw_vault_left_furniture():
	# Stone plinths — placed below items so they don't block pickups at y=80
	for px2 in [48.0, 144.0]:
		_tex(_tex_plinth, Rect2(px2, 96, 18, 14))
	# Cobwebs in NW and NE corners
	var web := Color(0.45, 0.42, 0.50, 0.30)
	_draw_cobweb(Vector2(18, 18),  Vector2( 1,  1), web)
	_draw_cobweb(Vector2(190, 18), Vector2(-1,  1), web)
	# Ancient rune carvings on north wall
	var rune := Color(0.50, 0.42, 0.60, 0.45)
	for i in range(4):
		var rx := 32.0 + i * 38.0
		draw_circle(Vector2(rx, 20), 2.5, rune)
		draw_line(Vector2(rx - 3, 20), Vector2(rx + 3, 20), rune, 0.8)
		draw_line(Vector2(rx, 17), Vector2(rx, 23), rune, 0.8)

func _draw_vault_centre_furniture():
	# Animated glow aura
	var glow := Color(0.65, 0.45, 0.85, 0.18 + abs(sin(_t * 1.2)) * 0.08)
	draw_circle(Vector2(352, 72), 22.0, glow)
	# Grand plinth sprite — centred, below the loot target at y=48
	_tex(_tex_plinth, Rect2(343, 80, 18, 14))
	# Floor inlay diamond
	var inlay := Color(C_FLOOR_VAULT_A.r + 0.05, C_FLOOR_VAULT_A.g + 0.03, C_FLOOR_VAULT_A.b + 0.08, 0.70)
	var pts := PackedVector2Array([
		Vector2(352, 44), Vector2(392, 72),
		Vector2(352, 100), Vector2(312, 72),
	])
	draw_colored_polygon(pts, Color(inlay.r, inlay.g, inlay.b, 0.12))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(inlay.r, inlay.g, inlay.b, 0.30), 0.8)
	# Wall bracket sconces
	var bracket := Color(0.40, 0.30, 0.50)
	for sx in [262.0, 442.0]:
		draw_rect(Rect2(sx, 16, 10, 6), bracket)
		draw_line(Vector2(sx + 5, 16), Vector2(sx + 5, 22), bracket, 1.5)

func _draw_vault_right_furniture():
	# Animated altar glow
	var altar_glow := Color(0.85, 0.70, 0.30, 0.14 + abs(sin(_t * 0.8)) * 0.08)
	draw_circle(Vector2(624, 64), 28.0, altar_glow)
	# Altar sprite — pushed toward north wall, loot spawns at y=48 so altar at y=68
	_tex(_tex_altar, Rect2(604, 68, 40, 26))
	# Treasure pile clusters in NW and NE corners
	var gold  := Color(0.85, 0.68, 0.15)
	var gold2 := Color(0.70, 0.52, 0.10)
	for corner in [Vector2(544, 28), Vector2(700, 28)]:
		for ci in range(6):
			var cr := 2.0 + (ci % 3) * 1.2
			var co := Vector2(float(ci % 3) * 6 - 6, float(ci / 3) * 5)
			draw_circle(corner + co, cr, gold if ci % 2 == 0 else gold2)
	# Ornate floor
	var orn := Color(C_FLOOR_VAULT_A.r + 0.06, C_FLOOR_VAULT_A.g + 0.04, C_FLOOR_VAULT_A.b + 0.10, 0.25)
	for ri in range(3):
		var margin := float(ri * 10 + 8)
		draw_rect(Rect2(533 + margin, 18 + margin, 192 - margin * 2, 112 - margin * 2), orn, false, 0.8)

	# Cobwebs in corners (inner sanctum feels ancient)
	var web := Color(0.55, 0.50, 0.42, 0.28)
	_draw_cobweb(Vector2(534, 18),  Vector2( 1,  1), web)
	_draw_cobweb(Vector2(718, 18),  Vector2(-1,  1), web)

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
