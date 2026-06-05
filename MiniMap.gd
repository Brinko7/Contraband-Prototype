extends Control

# Abstract mini-map of the 7-room layout
# Room indices: 0=Entry, 1=Barracks, 2=Storeroom, 3=Captain, 4=Antechamber, 5=Vault, 6=Armory

const _BG    := Color(0.06, 0.05, 0.09, 0.85)
const _BDR   := Color(0.28, 0.24, 0.18, 0.50)

# Room rects within the mini-map (x, y, w, h) in local pixels
# Panel is 94×74. Rooms are drawn at 2px scale from the abstract layout.
# Layout (each unit = ~12px wide, ~10px tall):
#   Vault:      cols 1-7, row 0    → x=4, y=4, w=78, h=12
#   Captain:    cols 0-2, rows 1-2 → x=4, y=18, w=24, h=20
#   Antechamber:cols 3-5, rows 1-2 → x=30, y=18, w=30, h=20
#   Armory:     cols 6-7, rows 1-2 → x=62, y=18, w=20, h=20
#   Barracks:   cols 0-2, rows 3-4 → x=4, y=40, w=24, h=18
#   Storeroom:  cols 3-7, rows 3-4 → x=30, y=40, w=52, h=18
#   Entry:      cols 2-5, row 5    → x=22, y=60, w=42, h=10
const ROOM_RECTS := [
	Rect2( 22,  60, 42, 10),   # 0 Entry
	Rect2(  4,  40, 24, 18),   # 1 Barracks
	Rect2( 30,  40, 52, 18),   # 2 Storeroom
	Rect2(  4,  18, 24, 20),   # 3 Captain's Office
	Rect2( 30,  18, 30, 20),   # 4 Antechamber
	Rect2(  4,   4, 78, 12),   # 5 Vault
	Rect2( 62,  18, 20, 20),   # 6 Armory
]

# Corridor connector dots between rooms (centre-to-centre)
const CORRIDORS := [
	[0, 1],   # Entry → Barracks
	[0, 2],   # Entry → Storeroom
	[1, 3],   # Barracks → Captain
	[2, 4],   # Storeroom → Antechamber
	[3, 5],   # Captain → Vault
	[4, 5],   # Antechamber → Vault (locked)
	[6, 5],   # Armory → Vault
]

const ROOM_NAMES := ["ENTRY", "BRKS", "STORE", "CAPT", "ANTE", "VAULT", "ARMO"]

func _draw():
	var W := 94.0
	var H := 74.0
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(0, 0, W, H), _BG, true)
	draw_rect(Rect2(0, 0, W, H), _BDR, false, 1.0)

	var lm = get_tree().get_first_node_in_group("levelmap")
	var visited: Array = []
	if lm and lm.get("visited_rooms") != null:
		visited = lm.visited_rooms
	while visited.size() < 7:
		visited.append(false)

	var cleared: Array = GameManager.cleared_rooms
	while cleared.size() < 7:
		cleared.append(false)

	# Player position → current room
	var player = get_meta("player", null)
	var player_room := -1
	if player != null and lm != null and lm.has_method("_tile_to_room"):
		var px: int = int(player.global_position.x / 16)
		var py: int = int(player.global_position.y / 16)
		player_room = lm._tile_to_room(Vector2i(px, py))

	# Draw corridor lines first (behind rooms)
	for pair in CORRIDORS:
		var ra: Rect2 = ROOM_RECTS[pair[0]]
		var rb: Rect2 = ROOM_RECTS[pair[1]]
		var ca := ra.get_center()
		var cb := rb.get_center()
		var vis_a: bool = visited[pair[0]] if pair[0] < visited.size() else false
		var vis_b: bool = visited[pair[1]] if pair[1] < visited.size() else false
		var alpha := 0.50 if (vis_a or vis_b) else 0.15
		draw_line(ca, cb, Color(0.45, 0.40, 0.32, alpha), 1.0)

	# Draw room boxes
	for i in range(7):
		var r: Rect2 = ROOM_RECTS[i]
		var vis: bool = visited[i] if i < visited.size() else false
		var clr: bool = cleared[i] if i < cleared.size() else false
		var is_current: bool = (i == player_room)

		var bg_col: Color
		if is_current:
			bg_col = Color(0.35, 0.75, 0.45, 0.55)
		elif clr:
			bg_col = Color(0.25, 0.50, 0.30, 0.35)
		elif vis:
			bg_col = Color(0.22, 0.20, 0.28, 0.55)
		else:
			bg_col = Color(0.10, 0.09, 0.12, 0.40)

		draw_rect(r, bg_col, true)

		var bdr_col: Color
		if is_current:
			bdr_col = Color(0.45, 0.95, 0.55, 0.90)
		elif vis:
			bdr_col = Color(0.40, 0.35, 0.28, 0.70)
		else:
			bdr_col = Color(0.22, 0.20, 0.18, 0.35)
		draw_rect(r, bdr_col, false, 1.0)

		# Room label (small, only if visited)
		if vis and r.size.x >= 18:
			var lbl: String = ROOM_NAMES[i]
			var font_size := 6 if r.size.x < 28 else 7
			draw_string(font, r.position + Vector2(2, r.size.y - 2), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2, font_size,
				Color(0.75, 0.70, 0.55, 0.80 if vis else 0.30))

		# Cleared checkmark
		if clr:
			draw_string(font, r.get_center() + Vector2(-3, 3), "✓",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.35, 0.95, 0.45, 0.80))

		# vault_location intel: mark Vault (room 5) with a gold star regardless of visit state
		if i == 5 and "vault_location" in GameManager.preheist_intel:
			draw_string(font, r.get_center() + Vector2(-4, 4), "★",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.85, 0.20, 0.95))
			draw_rect(r, Color(0.85, 0.70, 0.15, 0.18), true)

	# Pebble cooldown indicator (bottom strip)
	var player_node = get_meta("player", null)
	if player_node:
		var pc: float = player_node.get("_pebble_cooldown") if player_node.get("_pebble_cooldown") != null else 0.0
		var pcd: float = player_node.get("_PEBBLE_CD") if player_node.get("_PEBBLE_CD") != null else 6.0
		if pc > 0.0:
			var frac := pc / pcd
			draw_rect(Rect2(2, H - 4, (W - 4) * (1.0 - frac), 2), Color(0.72, 0.62, 0.38, 0.70), true)
			draw_string(font, Vector2(2, H - 6), "[Q] pebble",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.72, 0.62, 0.38, 0.55))
		else:
			draw_string(font, Vector2(2, H - 6), "[Q] pebble ready",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.55, 0.75, 0.40, 0.70))
			draw_rect(Rect2(2, H - 4, W - 4, 2), Color(0.55, 0.75, 0.40, 0.60), true)
