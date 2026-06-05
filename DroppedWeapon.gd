extends Node2D

# Weapon dropped by a slain guard — player can pick it up via interact

var weapon_id: String = "NONE"
var _timer: float = 28.0
var _bob_t: float = 0.0

# Entry animation: weapon slides + spins briefly on spawn
const _SLIDE_DUR: float = 0.40
var _slide_t:   float   = _SLIDE_DUR
var _slide_dir: Vector2 = Vector2.ZERO
var _slide_spin: float  = 0.0

func setup(wid: String, spawn_dir: Vector2 = Vector2.ZERO):
	weapon_id  = wid
	add_to_group("interactable")
	if spawn_dir != Vector2.ZERO:
		_slide_dir  = spawn_dir.normalized()
		_slide_t    = _SLIDE_DUR
		_slide_spin = randf_range(6.0, 12.0) * (1.0 if randf() > 0.5 else -1.0)

func _process(delta: float):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	_bob_t += delta
	if _slide_t > 0.0:
		_slide_t -= delta
		# Slide the node itself so it physically moves
		if _slide_dir != Vector2.ZERO:
			var frac: float = _slide_t / _SLIDE_DUR
			position += _slide_dir * 28.0 * delta * frac * frac
	queue_redraw()

func is_in_range(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= 22.0

func interact(player: Node):
	if not is_instance_valid(player):
		return
	var old_weapon: String = player.get("weapon")
	player.set("weapon", weapon_id)
	player.call("reset_floor_charges")
	var wdata: Dictionary = GameManager.WEAPONS.get(weapon_id, {})
	var wname: String = wdata.get("name", weapon_id.replace("_", " "))
	if old_weapon != "NONE":
		var old_data: Dictionary = GameManager.WEAPONS.get(old_weapon, {})
		player.call("_popup",
			"GRABBED %s (dropped %s)" % [wname, old_data.get("name", old_weapon)],
			Color(0.70, 0.90, 0.45))
	else:
		player.call("_popup", "GRABBED %s" % wname, Color(0.70, 0.90, 0.45))
	queue_free()

func _draw():
	var bob: float = sin(_bob_t * 2.8) * 1.8 if _slide_t <= 0.0 else 0.0
	var col: Color = _get_weapon_color()
	var alpha: float = min(1.0, _timer * 0.5)
	if _timer < 2.0:
		alpha = _timer * 0.5

	# Spin during entry slide
	if _slide_t > 0.0 and _slide_dir != Vector2.ZERO:
		var spin_frac: float = 1.0 - (_slide_t / _SLIDE_DUR)
		var spin_angle: float = _slide_spin * spin_frac * PI
		draw_set_transform(Vector2.ZERO, spin_angle, Vector2.ONE)

	var offset := Vector2(0, bob)

	# Glow halo
	draw_circle(offset, 6.0, Color(col.r, col.g, col.b, alpha * 0.22))

	# Shape depends on weapon type
	match weapon_id:
		"LONGSWORD", "BROADSWORD", "BLADESONG":
			# Sword: long diagonal blade
			draw_line(offset + Vector2(-5, 3), offset + Vector2(5, -3),
				Color(col.r, col.g, col.b, alpha), 2.0)
			draw_line(offset + Vector2(-5, 3), offset + Vector2(-5, 3) + Vector2(-2, 1),
				Color(0.45, 0.32, 0.18, alpha), 1.5)  # handle
			draw_circle(offset + Vector2(5, -3), 1.0, Color(1.0, 0.95, 0.80, alpha))
		"SPEAR":
			draw_line(offset + Vector2(-6, 2), offset + Vector2(4, -2),
				Color(0.45, 0.32, 0.18, alpha), 1.5)
			draw_line(offset + Vector2(3, -2), offset + Vector2(6, -4),
				Color(col.r, col.g, col.b, alpha), 2.0)
		"SHIV", "STILETTO", "ASSASSIN_FANG":
			draw_line(offset + Vector2(-3, 2), offset + Vector2(3, -2),
				Color(col.r, col.g, col.b, alpha), 1.5)
			draw_circle(offset + Vector2(3, -2), 0.8, Color(1.0, 0.95, 0.85, alpha))
		"SHADOW_BLADE", "GHOST_BLADE", "VOID_REAPER":
			draw_line(offset + Vector2(-5, 2), offset + Vector2(5, -2),
				Color(col.r, col.g, col.b, alpha * 0.85), 2.0)
			draw_arc(offset, 4.0, 0, TAU, 12, Color(col.r, col.g, col.b, alpha * 0.35), 1.0)
		"CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT":
			draw_line(offset + Vector2(-4, 0), offset + Vector2(4, 0),
				Color(0.40, 0.28, 0.15, alpha), 2.0)
			draw_line(offset + Vector2(0, -3), offset + Vector2(0, 3),
				Color(col.r, col.g, col.b, alpha), 1.5)
		_:
			draw_line(offset + Vector2(-3, 2), offset + Vector2(3, -2),
				Color(col.r, col.g, col.b, alpha), 1.8)

	# Pickup prompt flash (only once settled)
	if _timer > 2.0 and _slide_t <= 0.0:
		var pulse: float = (sin(_bob_t * 4.0) + 1.0) * 0.5
		draw_arc(offset, 8.0, 0, TAU, 16, Color(1.0, 1.0, 0.80, pulse * 0.18 * alpha), 1.0)

	# Reset spin transform
	if _slide_t > 0.0 and _slide_dir != Vector2.ZERO:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _get_weapon_color() -> Color:
	var wdata: Dictionary = GameManager.WEAPONS.get(weapon_id, {})
	return wdata.get("color", Color(0.70, 0.65, 0.55))
