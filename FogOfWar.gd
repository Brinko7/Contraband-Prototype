extends Node2D

# Drawn on top of all game elements (z_index = 10).
# Covers floor tiles of unvisited rooms.  Visited rooms are revealed permanently.
# Room rects must match LevelMap.ROOM_TILE_RECTS and _tile_to_room exactly.

const TILE_SIZE := 16

# Must stay in sync with LevelMap.ROOM_TILE_RECTS
const ROOM_TILE_RECTS: Array[Rect2i] = [
	Rect2i(14, 29, 20,  6),   # 0  Entry Foyer
	Rect2i( 1, 19, 18,  9),   # 1  Barracks
	Rect2i(29, 19, 17,  9),   # 2  Storeroom
	Rect2i( 1,  8, 16,  9),   # 3  Captain's Office
	Rect2i(20,  8, 17,  9),   # 4  Antechamber
	Rect2i( 8,  1, 32,  6),   # 5  Vault
	Rect2i(39,  8,  7,  9),   # 6  Armory
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

	for i in range(min(visited.size(), ROOM_TILE_RECTS.size())):
		if visited[i]:
			continue
		_fog_rect(ROOM_TILE_RECTS[i], map_data)

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
