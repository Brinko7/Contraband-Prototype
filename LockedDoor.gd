extends Node2D

# Locked door — sits in a carved doorway gap, blocks movement until the player
# uses the matching key (key_id). Spawned by World.gd at setup time.

var door_id: int = 0
var is_locked: bool = true
var _body: StaticBody2D = null
var _t := 0.0

func _ready():
	add_to_group("interactable")
	_build_collision()
	queue_redraw()

func _build_collision():
	_body = StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size = Vector2(32, 32)   # covers the 2×2-tile carved gap
	shape.shape    = rect
	_body.add_child(shape)
	add_child(_body)

func is_in_range(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= 40.0

var _pick_attempts := 0

func interact(player) -> void:
	if not is_locked:
		return
	if player.has_method("has_key") and player.has_key(door_id):
		player.use_key(door_id)
		_unlock()
	elif GameManager.has_gear_effect("LOCKPICK"):
		# Lockpick Kit: open any lock silently, no item needed
		_popup("Lockpick Kit — opened silently", Color(0.70, 0.55, 0.28))
		_unlock()
	else:
		_try_lockpick(player)

func _try_lockpick(player) -> void:
	# Costs 1 smoke item to attempt; no item = hint only
	if not player.has_method("remove_item") or not player.has_method("count_item"):
		_popup("LOCKED — need key", Color(0.85, 0.30, 0.20))
		return
	if player.count_item(1) < 1:  # smoke = type 1
		_popup("Need key or 1 Smoke to pick", Color(0.85, 0.30, 0.20))
		return
	# Consume item and roll
	player.remove_item(1, 1)
	_pick_attempts += 1
	var roll: int = GameManager.roll_d20()
	# Cutpurse +3, Thieves' Tools +5
	if GameManager.selected_class == "CUTPURSE":
		roll = mini(roll + 3, 20)
	if GameManager.has_passive("TOOLS_BONUS"):
		roll = mini(roll + 5, 20)
		GameManager.active_passives.erase("TOOLS_BONUS")
	if GameManager.has_gear_effect("LOCKPICK"):
		roll = mini(roll + 4, 20)
	# Difficulty rises with each attempt
	var dc := 10 + (_pick_attempts - 1) * 4
	if roll >= dc:
		_popup("Pick %d ✓ (DC%d)" % [roll, dc], Color(0.40, 0.90, 0.45))
		_unlock()
	else:
		_popup("Pick %d ✗ (DC%d) — noise!" % [roll, dc], Color(1.0, 0.20, 0.20))
		if player.has_signal("noise_emitted"):
			player.noise_emitted.emit(1, global_position)

func _unlock():
	is_locked = false
	if is_instance_valid(_body):
		_body.queue_free()
		_body = null
	_popup("UNLOCKED!", Color(0.50, 0.90, 0.50))
	queue_redraw()

func _popup(text: String, col: Color):
	var ds := load("res://DicePopup.tscn")
	if ds:
		var p: Node = ds.instantiate()
		p.setup(text, col)
		p.global_position = global_position + Vector2(0, -20)
		get_tree().root.add_child(p)

func _process(delta):
	_t += delta
	queue_redraw()

func _draw():
	if is_locked:
		var pulse := sin(_t * 2.0) * 0.5 + 0.5
		# Door body — dark wood panels
		draw_rect(Rect2(-16, -16, 32, 32), Color(0.28, 0.18, 0.08))
		# Horizontal planks
		for i in range(4):
			var by := -13.0 + i * 9.0
			draw_rect(Rect2(-14, by, 28, 5), Color(0.42, 0.28, 0.10))
			draw_rect(Rect2(-14, by, 28, 1), Color(0.55, 0.38, 0.14))
		# Iron crossbar
		draw_rect(Rect2(-14, -2, 28, 4), Color(0.48, 0.44, 0.40))
		draw_rect(Rect2(-14, -2, 28, 1), Color(0.62, 0.58, 0.52))
		# Lock glow
		draw_circle(Vector2.ZERO, 5.5, Color(0.90, 0.72, 0.10, 0.35 + pulse * 0.30))
		draw_circle(Vector2.ZERO, 3.0, Color(0.95, 0.85, 0.30))
		draw_circle(Vector2.ZERO, 1.2, Color(1.00, 0.95, 0.60))
		# Proximity hint — show key icon and "USE KEY" when player is close
		var player = get_tree().get_first_node_in_group("player")
		if player and is_in_range(player.global_position):
			var has_key: bool = player.has_method("has_key") and player.has_key(door_id)
			var font := ThemeDB.fallback_font
			if has_key:
				draw_arc(Vector2.ZERO, 20.0, 0, TAU, 24, Color(0.40, 0.95, 0.45, 0.55 + pulse * 0.30), 2.0)
				draw_string(font, Vector2(-18, -22), "[E] Unlock",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 1.0, 0.50, 0.95))
			else:
				draw_string(font, Vector2(-22, -22), "[E] Pick lock",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.78, 0.20, 0.85))
	else:
		# Open doorway — just door-frame posts on each side
		draw_rect(Rect2(-16, -16, 4, 32), Color(0.35, 0.22, 0.10, 0.70))
		draw_rect(Rect2( 12, -16, 4, 32), Color(0.35, 0.22, 0.10, 0.70))
