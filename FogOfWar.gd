extends Node2D

# Drawn on top of all game elements (z_index = 10).
# Only covers FLOOR tiles inside unvisited rooms — wall tiles are always
# visible so the player can see room outlines, corridor gaps, and door frames.

const TILE_SIZE := 16

# Interior tile rects for each room (must match LevelMap.ROOM_TILE_RECTS).
const ROOM_TILE_RECTS: Array[Rect2i] = [
	Rect2i( 1,  1, 12,  8),   # 0  Vault Left
	Rect2i(15,  1, 16,  8),   # 1  Vault Centre
	Rect2i(33,  1, 13,  8),   # 2  Vault Right (locked)
	Rect2i( 1, 11, 46, 10),   # 3  Barracks
	Rect2i( 1, 23, 46, 11),   # 4  Entry Hall
]

# Corridor floor tiles that connect rooms — also fogged so the player can't
# see into an unvisited room through the gap.
# Each entry: [rect, room_index_it_leads_to]
const CORRIDOR_RECTS: Array[Dictionary] = [
	{"rect": Rect2i(13, 4, 2, 2), "room": 0},   # Vault L ↔ Vault C  (fog from Left side)
	{"rect": Rect2i(13, 4, 2, 2), "room": 1},   # same gap, fog from Centre side
	{"rect": Rect2i(31, 4, 2, 2), "room": 2},   # Vault C ↔ Vault R locked gap
	{"rect": Rect2i( 5, 9, 2, 2), "room": 0},   # Vault L → Barracks
	{"rect": Rect2i(20, 9, 2, 2), "room": 1},   # Vault C → Barracks
	{"rect": Rect2i(10,21, 2, 2), "room": 3},   # Barracks → Entry west
	{"rect": Rect2i(35,21, 2, 2), "room": 3},   # Barracks → Entry east
]

func _ready():
	z_index = 10

func _process(_delta):
	queue_redraw()

func _draw():
	var lmap := get_tree().get_first_node_in_group("levelmap")
	if not lmap:
		return
	var visited: Array = lmap.get("visited_rooms")
	var map_data: Array = lmap.get("map")
	if not visited or not map_data:
		return

	# Black out floor tiles of each unvisited room
	for i in range(min(visited.size(), ROOM_TILE_RECTS.size())):
		if visited[i]:
			continue
		_fog_rect(ROOM_TILE_RECTS[i], map_data)

	# Also fog corridor tiles that lead into an unvisited room
	for entry in CORRIDOR_RECTS:
		var room_idx: int = entry["room"]
		if room_idx < visited.size() and not visited[room_idx]:
			_fog_rect(entry["rect"], map_data)

func _fog_rect(rect: Rect2i, map_data: Array):
	for r in range(rect.position.y, rect.position.y + rect.size.y):
		if r < 0 or r >= map_data.size():
			continue
		for c in range(rect.position.x, rect.position.x + rect.size.x):
			if c < 0 or c >= (map_data[r] as Array).size():
				continue
			if (map_data[r] as Array)[c] == 0:   # FLOOR tile only
				draw_rect(Rect2(c * TILE_SIZE, r * TILE_SIZE, TILE_SIZE, TILE_SIZE),
					Color(0.0, 0.0, 0.0, 1.0))
