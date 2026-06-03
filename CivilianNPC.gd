extends Node2D

# Civilian NPC — wanders a fixed route. Runs and screams if they see the
# player carrying a body or in direct line of sight while a guard is alert.

const TILE_SIZE := 16

@export var patrol_points: Array[Vector2] = []

var _pt_idx        := 0
var _move_timer    := 0.0
var _move_interval := 1.8   # wanders slowly
var _t             := 0.0
var _spooked       := false
var _spook_timer   := 0.0
var is_informant   := false  # set true by World when INFORMANT modifier is active

var _bribed := false

func _ready():
	add_to_group("civilians")
	add_to_group("interactable")
	if patrol_points.is_empty():
		patrol_points.append(global_position)

func is_in_range(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= 28.0

func interact(player) -> void:
	if _bribed or _spooked:
		return
	# Cost: 1 coin (type 0). Cutpurse class: first bribe is free
	var dice_scene = load("res://DicePopup.tscn")
	var bribe_cost := 50
	var free_bribe: bool = GameManager.selected_class == "CUTPURSE" and not GameManager.has_passive("_bribe_used")
	if not free_bribe and GameManager.gold_available() < bribe_cost:
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Need %dgp to bribe" % bribe_cost, Color(0.85, 0.30, 0.20))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)
		return
	var roll: int = GameManager.roll_d20()
	if not free_bribe:
		GameManager.gold_spent += bribe_cost
	if free_bribe:
		GameManager.add_passive("_bribe_used")  # one-time flag per run
	if roll >= 8:
		_bribed = true
		_spooked = false
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Bribe %d ✓ — looks away" % roll, Color(0.40, 0.90, 0.45))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)
	else:
		# Failed bribe — they yell
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Bribe %d ✗ — SHOUTS!" % roll, Color(1.0, 0.20, 0.20))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)
		_spook(player)

func _process(delta):
	_t += delta
	_move_timer -= delta
	if _spooked:
		_spook_timer -= delta
		if _spook_timer <= 0.0:
			_spooked = false
	queue_redraw()

	if _move_timer <= 0.0 and not _spooked:
		_move_timer = _move_interval + randf_range(-0.3, 0.3)
		_advance_patrol()

	# Check player visibility
	_check_player()

func _advance_patrol():
	if patrol_points.size() <= 1:
		return
	_pt_idx = (_pt_idx + 1) % patrol_points.size()
	# Step one tile toward next waypoint
	var target: Vector2 = patrol_points[_pt_idx]
	var diff: Vector2   = target - global_position
	if diff.length() > 2.0:
		var step: Vector2 = diff.normalized() * TILE_SIZE
		# Clamp to one tile
		if abs(diff.x) >= abs(diff.y):
			step = Vector2(sign(diff.x) * TILE_SIZE, 0)
		else:
			step = Vector2(0, sign(diff.y) * TILE_SIZE)
		global_position += step

func _check_player():
	var player = get_tree().get_first_node_in_group("player")
	if not player or _spooked:
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist > 60.0:
		return
	# Line of sight check
	var space := get_world_2d().direct_space_state
	var ray   := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	ray.exclude = [self]
	var result := space.intersect_ray(ray)
	if not (result.is_empty() or result.collider == player):
		return  # wall between us

	var carrying: bool = player.get("is_carrying_body") == true
	var any_alert := false
	for g in get_tree().get_nodes_in_group("guards"):
		if g.get("alert_state") == 2:
			any_alert = true; break

	# Informant: always spooks on sight (eye contact = instant alert)
	if is_informant or carrying or any_alert:
		_spook(player)

func _spook(player):
	_spooked     = true
	_spook_timer = 5.0
	# Run away — move toward opposite side of map
	global_position += (global_position - player.global_position).normalized() * TILE_SIZE * 2
	# Scream — emit loud noise and alert nearby guards
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= 90.0:
			if guard.has_method("_on_noise_emitted"):
				guard._on_noise_emitted(2, global_position)  # 2 = LOUD
	GameManager.record_alert()
	GameManager.raise_wanted_level(1)   # civilian witness raises heat faster
	# Popup feedback
	var dice_scene = load("res://DicePopup.tscn")
	if dice_scene:
		var popup = dice_scene.instantiate()
		popup.setup("CIVILIAN — SCREAMS!", Color(1.0, 0.70, 0.15))
		popup.global_position = global_position + Vector2(0, -12)
		get_tree().root.add_child(popup)

func _draw():
	var pulse: float = sin(_t * 2.0) * 0.5 + 0.5
	# Informant wears a subtly different cloak color — amber/gold
	var body_col := Color(0.72, 0.60, 0.45)
	if is_informant:
		body_col = Color(0.55, 0.42, 0.20)
	if _spooked:
		body_col = Color(0.90, 0.65, 0.30)

	# Shadow
	draw_circle(Vector2(0.5, 1.5), 4.5, Color(0, 0, 0, 0.22))

	# Body — plain tunic
	draw_circle(Vector2.ZERO, 4.5, body_col)

	# Head
	draw_circle(Vector2(0, -5.5), 3.0, Color(0.85, 0.70, 0.55))

	# Spooked — agitated pulse ring, no text
	if _spooked:
		draw_arc(Vector2.ZERO, 8.0, 0, TAU, 20, Color(1.0, 0.65, 0.10, 0.40 + pulse * 0.30), 1.5)
		draw_arc(Vector2.ZERO, 5.5, 0, TAU, 20, Color(1.0, 0.65, 0.10, 0.20 + pulse * 0.20), 1.0)
