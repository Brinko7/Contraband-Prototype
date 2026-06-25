## RoomManager.gd
## Node that tracks all named rooms on the current floor.
## Spawned as a child of World during _register_rooms(); reset each floor.
##
## Usage:
##   var rm := RoomManager.new()
##   add_child(rm)
##   rm.name = "RoomManager"
##   rm.register_room(RoomData.make(...))
##
## Then call get_current_room(player.position) from any system that needs
## to know where the player is (HUD, guards, flavor popups, etc.).

extends Node
class_name RoomManager

## All rooms registered for this floor.
var rooms: Array[RoomData] = []

## Cached room from the last get_current_room() call.
## Avoids re-scanning the full room list every frame.
var _current_room: RoomData = null

## Track which rooms have already shown their flavor popup this floor.
var _flavor_shown: Dictionary = {}   # room_name → true

# Preload DicePopup once at class level to avoid repeated loads
const _DicePopupScene = preload("res://DicePopup.tscn")

func _ready() -> void:
	add_to_group("room_manager")

# ── Registration ──────────────────────────────────────────────────────────────

## Add a room to this floor's registry.
func register_room(room: RoomData) -> void:
	rooms.append(room)

## Remove all rooms and reset state; call this before building a new floor.
func reset() -> void:
	rooms.clear()
	_current_room = null
	_flavor_shown.clear()

# ── Lookup ────────────────────────────────────────────────────────────────────

## Return the RoomData whose world_rect contains world_pos, or null.
## Uses world_rect (pixel-space) so callers can pass player.global_position directly.
func get_room_at(world_pos: Vector2) -> RoomData:
	for room in rooms:
		if room.world_rect.has_point(world_pos):
			return room
	return null

## Cached version: only scans all rooms if the player has left the last known room.
## Call this once per frame from any system that needs the current room.
func get_current_room(player_pos: Vector2) -> RoomData:
	# Fast path: still in the same room
	if _current_room != null and _current_room.world_rect.has_point(player_pos):
		return _current_room

	# Slow path: find the new room
	var found := get_room_at(player_pos)
	if found != _current_room:
		_current_room = found
		if found != null:
			on_room_entered(found, get_tree().get_first_node_in_group("player"))
	return _current_room

# ── Room entered ──────────────────────────────────────────────────────────────

## Called automatically by get_current_room when the player crosses into a new room.
## Also safe to call directly (e.g. from Player.gd) if you track room changes there.
## Shows a flavor text popup for the first visit to each room this floor.
func on_room_entered(room: RoomData, player: Node) -> void:
	# Mark visited regardless of popup
	room.mark_visited()

	# Only show flavor popup once per room per floor
	if _flavor_shown.get(room.room_name, false):
		return
	_flavor_shown[room.room_name] = true

	# Fire GameManager signal so HUD can show room name banner
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("room_entered"):
		gm.room_entered.emit(room.room_name)

	# We need a scene tree anchor to attach the popup.
	# Use the player node if available, otherwise the root.
	var anchor: Node = player if player != null else get_tree().root

	# Show flavor text in amber (room name handled by HUD banner now)
	_show_room_popup(room.flavor_text, Color(0.90, 0.65, 0.20), anchor, -28.0)

# ── Internal helpers ──────────────────────────────────────────────────────────

## Spawn a DicePopup-style label near the player.
## offset_y nudges successive lines apart so they don't stack on one pixel.
func _show_room_popup(text: String, color: Color, anchor: Node, offset_y: float) -> void:
	if not is_instance_valid(anchor):
		return
	var popup = _DicePopupScene.instantiate()
	# DicePopup.setup(text, color) is the standard API used elsewhere
	popup.setup(text, color)
	# Position relative to the anchor's global position (player centre)
	var origin: Vector2 = Vector2.ZERO
	if anchor is Node2D:
		origin = (anchor as Node2D).global_position
	elif anchor.has_method("get_global_rect"):
		origin = (anchor.get_global_rect() as Rect2).get_center()
	popup.global_position = origin + Vector2(0.0, offset_y)
	get_tree().root.add_child(popup)
