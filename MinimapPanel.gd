extends Control

# Tactical minimap — drawn from LevelMap wall data + live entity positions.
# Walls shown as blocks; guards blip brighter the more alert they are;
# player is always a bright dot; exit glows when active.

const TILE_PX   := 1.3   # minimap pixels per world tile
const MAP_COLS  := 48
const MAP_ROWS  := 36
const WORLD_TILE := 16.0

func _ready():
	custom_minimum_size = Vector2(MAP_COLS * TILE_PX + 2, MAP_ROWS * TILE_PX + 2)
	size = custom_minimum_size
	set_process(true)

func _process(_delta):
	queue_redraw()

func _draw():
	var w := MAP_COLS * TILE_PX
	var h := MAP_ROWS * TILE_PX

	# Panel background + border
	draw_rect(Rect2(0, 0, w + 2, h + 2), Color(0.04, 0.03, 0.05, 0.88))
	draw_rect(Rect2(0, 0, w + 2, h + 2), Color(0.30, 0.24, 0.18, 0.55), false, 0.8)

	# ── Wall tiles from LevelMap ──────────────────────────────────────────────
	var lmap = get_tree().get_first_node_in_group("levelmap")
	if lmap and lmap.get("map"):
		var map = lmap.map
		for row in range(map.size()):
			for col in range(map[row].size()):
				if map[row][col] == 1:
					draw_rect(
						Rect2(1 + col * TILE_PX, 1 + row * TILE_PX, TILE_PX, TILE_PX),
						Color(0.30, 0.24, 0.18, 0.70))

	# ── Exit ─────────────────────────────────────────────────────────────────
	for exit in get_tree().get_nodes_in_group("exits"):
		var ep := _to_map(exit.global_position)
		var active: bool = exit.get("_active") == true
		var ec := Color(0.2, 1.0, 0.4, 0.9) if active else Color(0.4, 0.4, 0.4, 0.5)
		draw_circle(ep, 2.2, ec)

	# ── Bodies ────────────────────────────────────────────────────────────────
	for body in get_tree().get_nodes_in_group("bodies"):
		var bp := _to_map(body.global_position)
		draw_circle(bp, 1.2, Color(0.6, 0.15, 0.15, 0.70))

	# ── Guards (fog-aware — only show in visited rooms) ───────────────────────
	var visited: Array = []
	if lmap and lmap.get("visited_rooms"):
		visited = lmap.visited_rooms
	var room_tile_rects: Array = []
	if lmap and lmap.get("ROOM_TILE_RECTS"):
		room_tile_rects = lmap.ROOM_TILE_RECTS
	for guard in get_tree().get_nodes_in_group("guards"):
		var tc := Vector2i(int(guard.global_position.x / 16), int(guard.global_position.y / 16))
		var in_visited := false
		for i in range(room_tile_rects.size()):
			if i < visited.size() and visited[i] and room_tile_rects[i].has_point(tc):
				in_visited = true
				break
		var gs: int = guard.get("alert_state")
		# SENTINEL_EYE relic: always show all guards regardless of fog
		var sentinel_eye := GameManager.has_relic("SENTINEL_EYE")
		if not in_visited and gs != 2 and not sentinel_eye:
			continue
		var gp  := _to_map(guard.global_position)
		var gc: Color
		match gs:
			0: gc = Color(0.55, 0.55, 0.55, 0.45)   # unaware — very faint
			1: gc = Color(1.00, 0.75, 0.10, 0.80)   # suspicious — yellow
			2: gc = Color(1.00, 0.15, 0.15, 1.00)   # alert — red, bright
		draw_circle(gp, 1.8, gc)
		var gf: Vector2 = guard.get("facing") if guard.get("facing") else Vector2.RIGHT
		draw_line(gp, gp + gf * 2.5, Color(gc.r, gc.g, gc.b, gc.a * 0.7), 0.8)

	# ── Smoke clouds ─────────────────────────────────────────────────────────
	for cloud in get_tree().get_nodes_in_group("smoke_clouds"):
		var cp := _to_map(cloud.global_position)
		draw_circle(cp, 3.5, Color(0.40, 0.75, 0.35, 0.35))

	# ── Investigation markers (only for visited rooms) ────────────────────────
	for guard in get_tree().get_nodes_in_group("guards"):
		var gs: int = guard.get("alert_state")
		if gs == 1:
			var inv: Vector2 = guard.get("investigate_pos")
			if inv != Vector2.ZERO:
				var itc := Vector2i(int(inv.x / 16), int(inv.y / 16))
				var inv_visited := false
				for i in range(room_tile_rects.size()):
					if i < visited.size() and visited[i] and room_tile_rects[i].has_point(itc):
						inv_visited = true
						break
				if inv_visited:
					var ip := _to_map(inv)
					draw_circle(ip, 1.2, Color(1.0, 0.9, 0.2, 0.30))

	# ── Alarm Bells ──────────────────────────────────────────────────────────
	for bell in get_tree().get_nodes_in_group("alarm_bells"):
		var bp2 := _to_map(bell.global_position)
		var disabled: bool = bell.get("is_disabled") == true
		var col: Color = Color(0.30, 0.28, 0.22, 0.45) if disabled else Color(0.92, 0.72, 0.12, 0.75)
		draw_rect(Rect2(bp2.x - 1.2, bp2.y - 1.5, 2.4, 2.4), col)

	# ── Player ────────────────────────────────────────────────────────────────
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var pp := _to_map(player.global_position)
		draw_circle(pp, 2.4, Color(1.0, 1.0, 1.0, 1.0))
		var pf: Vector2 = player.get("facing") if player.get("facing") else Vector2.RIGHT
		draw_line(pp, pp + pf * 3.0, Color(0.7, 0.9, 1.0, 0.9), 0.8)

	# ── Label + guard count ──────────────────────────────────────────────────
	var guard_count := get_tree().get_nodes_in_group("guards").size()
	draw_string(ThemeDB.fallback_font, Vector2(2, h + 10), "RADAR  ×%d" % guard_count,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.35, 0.30, 0.22, 0.55))

func _to_map(world_pos: Vector2) -> Vector2:
	return Vector2(
		1.0 + (world_pos.x / WORLD_TILE) * TILE_PX,
		1.0 + (world_pos.y / WORLD_TILE) * TILE_PX)
