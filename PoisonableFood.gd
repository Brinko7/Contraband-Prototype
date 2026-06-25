extends Node2D

# A food platter or drink goblet. Player can interact to poison it (costs 1 Poison Vial item).
# A guard who "eats/drinks" (passes within 16px and is UNAWARE / off-duty)
# gets POISONED status for 30s — vision_range halved, moves to nearest wall and sits.

const INTERACT_RANGE := 18.0
const CONSUME_RANGE := 16.0

var _poisoned: bool = false
var _consumed: bool = false
var food_type: String = "GOBLET"  # "GOBLET", "PLATTER", "BARREL"
var _t: float = 0.0

const _BARREL_TEX_PATH := "res://sprites/prop_barrel.png"
static var _barrel_tex: Texture2D = null

var _gm = null

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("food_sources")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _barrel_tex == null and ResourceLoader.exists(_BARREL_TEX_PATH):
		_barrel_tex = load(_BARREL_TEX_PATH)
	_gm = get_node_or_null("/root/GameManager")

func is_in_range(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= INTERACT_RANGE

func interact(player: Node) -> void:
	if _poisoned:
		if player.has_method("_popup"):
			player._popup("Already poisoned.", Color(0.35, 0.72, 0.30))
		return
	if _consumed:
		if player.has_method("_popup"):
			player._popup("Already consumed.", Color(0.55, 0.50, 0.42))
		return

	# Check: player needs a poison vial, OR is Assassin class
	var is_assassin: bool = false
	var has_vial: bool = false

	if _gm:
		is_assassin = _gm.get("selected_class") == "ASSASSIN"

	# Check player inventory for POISON_VIAL
	var inv = player.get("items")
	if inv != null:
		for i in range(inv.size()):
			var entry = inv[i]
			if typeof(entry) == TYPE_DICTIONARY and entry.get("name", "") == "Poison Vial":
				has_vial = true
				inv.remove_at(i)
				break
			elif typeof(entry) == TYPE_STRING and entry == "POISON_VIAL":
				has_vial = true
				inv.remove_at(i)
				break

	# Check string item array style
	if not has_vial and player.has_method("get"):
		var str_items = player.get("_string_items")
		if str_items != null and "POISON_VIAL" in str_items:
			str_items.erase("POISON_VIAL")
			has_vial = true

	if not is_assassin and not has_vial:
		if player.has_method("_popup"):
			player._popup("Need a Poison Vial!", Color(0.80, 0.30, 0.20))
		return

	_poisoned = true
	queue_redraw()

	var dice_scene = load("res://DicePopup.tscn")
	if dice_scene:
		var p = dice_scene.instantiate()
		p.setup("Poisoned the %s!" % food_type.to_lower(), Color(0.30, 0.80, 0.35))
		p.global_position = global_position + Vector2(0, -16)
		get_tree().root.add_child(p)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

	if _poisoned and not _consumed:
		# Check if a guard walks over it while off-duty / unaware
		for guard in get_tree().get_nodes_in_group("guards"):
			if guard.global_position.distance_to(global_position) <= CONSUME_RANGE:
				var alert_state = guard.get("alert_state")
				# 0 = PATROL / UNAWARE; consume if not actively alerted (state < 2)
				if alert_state != null and int(alert_state) < 2:
					_consume_by_guard(guard)
					break

func _consume_by_guard(guard: Node) -> void:
	_consumed = true
	_poisoned = false  # food is gone
	queue_redraw()

	# Apply poison: halve vision range, stun-walk guard to nearest wall
	var orig_vision = guard.get("vision_range")
	if orig_vision != null:
		guard.set("vision_range", float(orig_vision) * 0.5)
	var orig_alert = guard.get("alert_state")
	if orig_alert != null:
		# Force guard to wander drunken state (alert_state 0 = patrol, set wander)
		guard.set("alert_state", 0)

	# Apply poison timer on guard (if it has such a field)
	if guard.has_method("apply_poison"):
		guard.apply_poison(30.0)
	else:
		# Fallback: we manage vision_range restoration ourselves via a timer node
		var restore := Timer.new()
		restore.wait_time = 30.0
		restore.one_shot = true
		get_tree().root.add_child(restore)
		restore.start()
		restore.timeout.connect(func():
			if is_instance_valid(guard) and orig_vision != null:
				guard.set("vision_range", orig_vision)
			restore.queue_free()
		)

	# Move guard to nearest wall (sit down effect — stop patrol)
	if guard.has_method("_popup"):
		guard._popup("Urgh...", Color(0.35, 0.72, 0.25))

	var dice_scene = load("res://DicePopup.tscn")
	if dice_scene:
		var p = dice_scene.instantiate()
		p.setup("Guard POISONED! (30s)", Color(0.30, 0.80, 0.35))
		p.global_position = guard.global_position + Vector2(0, -18)
		get_tree().root.add_child(p)

func _draw() -> void:
	if _consumed:
		_draw_empty()
		return

	match food_type:
		"GOBLET":   _draw_goblet()
		"PLATTER":  _draw_platter()
		"BARREL":   _draw_barrel()
		_:          _draw_goblet()

	# Interaction prompt
	var player := get_tree().get_first_node_in_group("player")
	if player and is_in_range(player.global_position) and not _consumed:
		var rc := Color(0.30, 0.80, 0.35, 0.60) if not _poisoned else Color(0.20, 0.60, 0.25, 0.40)
		draw_arc(Vector2.ZERO, 12.0, 0, TAU, 16, rc, 1.2)

func _draw_goblet() -> void:
	var t := _t
	var cup_col := Color(0.75, 0.62, 0.28) if not _poisoned else Color(0.38, 0.62, 0.28)
	# Stem
	draw_rect(Rect2(-1.5, 2, 3, 6), cup_col)
	# Base
	draw_rect(Rect2(-5, 8, 10, 2), cup_col)
	# Bowl
	var pts := PackedVector2Array()
	var steps := 16
	for i in range(steps + 1):
		var a := PI + float(i) / steps * PI
		pts.append(Vector2(cos(a) * 5.0, sin(a) * 4.0 + 2.0))
	draw_polyline(pts, cup_col, 2.0)
	draw_line(Vector2(-5, 2), Vector2(5, 2), cup_col, 1.5)  # rim

	# Liquid level
	var liquid_col := Color(0.65, 0.22, 0.12, 0.80) if not _poisoned else Color(0.20, 0.65, 0.22, 0.85)
	var liquid_pts := PackedVector2Array()
	for i in range(steps + 1):
		var a := PI + float(i) / steps * PI
		var liquid_r_x := 4.5
		var liquid_r_y := 2.5
		liquid_pts.append(Vector2(cos(a) * liquid_r_x, sin(a) * liquid_r_y + 0.5))
	liquid_pts.append(Vector2(-4.5, 0.5))
	liquid_pts.append(Vector2(4.5, 0.5))
	draw_colored_polygon(liquid_pts, liquid_col)

	if _poisoned:
		# Green bubble pulse
		var pulse := sin(t * 4.0) * 0.5 + 0.5
		draw_circle(Vector2(0, -1.5), 1.5 + pulse, Color(0.20, 0.85, 0.30, 0.5))
		# Skull icon
		_draw_skull_icon(Vector2(0, -9), 3.5)

func _draw_platter() -> void:
	var platter_col := Color(0.75, 0.62, 0.28) if not _poisoned else Color(0.42, 0.62, 0.28)
	# Oval platter
	var pts := PackedVector2Array()
	for i in range(24):
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * 10, sin(a) * 5))
	draw_colored_polygon(pts, Color(0.55, 0.45, 0.22))
	draw_polyline(pts + PackedVector2Array([pts[0]]), platter_col, 1.5)
	# Food items on platter
	if not _poisoned:
		draw_circle(Vector2(-3, 0), 3.0, Color(0.75, 0.35, 0.20))
		draw_circle(Vector2(3, -1), 2.5, Color(0.65, 0.55, 0.25))
		draw_circle(Vector2(0, 2), 2.0, Color(0.30, 0.55, 0.22))
	else:
		draw_circle(Vector2(-3, 0), 3.0, Color(0.40, 0.55, 0.20))
		draw_circle(Vector2(3, -1), 2.5, Color(0.35, 0.50, 0.18))
		_draw_skull_icon(Vector2(0, -8), 3.5)

func _draw_barrel() -> void:
	if _barrel_tex != null:
		# 28x32 barrel scaled to ~24px, base at node-local y=10. Green tint if poisoned.
		var bmod := Color(1, 1, 1, 1) if not _poisoned else Color(0.62, 0.92, 0.55, 1)
		draw_texture_rect(_barrel_tex, Rect2(Vector2(-10.5, -14), Vector2(21, 24)), false, bmod)
		if _poisoned:
			_draw_skull_icon(Vector2(0, -16), 3.5)
		return
	var barrel_col := Color(0.50, 0.38, 0.20) if not _poisoned else Color(0.32, 0.48, 0.22)
	draw_rect(Rect2(-7, -10, 14, 20), barrel_col)
	draw_rect(Rect2(-7, -10, 14, 20), Color(0.65, 0.50, 0.28), false, 1.2)
	# Hoops
	for hy in [-6, 0, 6]:
		draw_line(Vector2(-7, hy), Vector2(7, hy), Color(0.55, 0.45, 0.22), 1.5)
	# Tap
	draw_rect(Rect2(-2, 2, 4, 4), Color(0.62, 0.48, 0.25))
	if _poisoned:
		_draw_skull_icon(Vector2(0, -14), 3.5)

func _draw_skull_icon(pos: Vector2, size: float) -> void:
	# Small skull icon to indicate poisoned state
	draw_circle(pos, size, Color(0.25, 0.70, 0.28, 0.85))
	draw_circle(pos, size, Color(0.20, 0.85, 0.30), false, 0.8)
	# Eyes
	draw_circle(pos + Vector2(-size * 0.3, -size * 0.1), size * 0.18, Color(0.10, 0.20, 0.10))
	draw_circle(pos + Vector2(size * 0.3, -size * 0.1), size * 0.18, Color(0.10, 0.20, 0.10))

func _draw_empty() -> void:
	# Just a faint outline where the food was
	match food_type:
		"GOBLET":
			draw_rect(Rect2(-5, -6, 10, 16), Color(0.35, 0.30, 0.20, 0.25), false, 0.8)
		"PLATTER":
			draw_arc(Vector2.ZERO, 8.0, 0, TAU, 16, Color(0.40, 0.35, 0.22, 0.25), 0.8)
		"BARREL":
			draw_rect(Rect2(-7, -10, 14, 20), Color(0.35, 0.28, 0.16, 0.25), false, 0.8)
