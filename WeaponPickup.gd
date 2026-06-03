extends Node2D

const _dice_scene = preload("res://DicePopup.tscn")

var weapon_id: String = "GARROTE"
var _bob_t    := 0.0

func _ready():
	add_to_group("interactable")
	add_to_group("weapon_pickups")

func _process(delta):
	_bob_t += delta
	queue_redraw()

func is_in_range(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= 32.0

func interact(player: Node):
	# Prevent spam-swapping
	if player.get("_weapon_swap_cooldown") != null and float(player.get("_weapon_swap_cooldown")) > 0.0:
		return
	if player.has_method("set"):
		player.set("_weapon_swap_cooldown", 0.5)
	var old_weapon: String = player.weapon
	player.weapon = weapon_id
	player.reset_floor_charges()
	player.save_items()

	# Spawn old weapon as a new pickup at player position
	if old_weapon != "NONE":
		var wp := Node2D.new()
		wp.set_script(load("res://WeaponPickup.gd"))
		wp.set("weapon_id", old_weapon)
		wp.global_position = player.global_position
		get_tree().root.add_child(wp)

	# Show popup
	var wname: String = GameManager.WEAPONS.get(weapon_id, {}).get("name", weapon_id)
	var popup := _dice_scene.instantiate()
	popup.setup("EQUIPPED: " + wname, Color(0.55, 0.85, 0.55))
	popup.global_position = player.global_position + Vector2(0, -10)
	get_tree().root.add_child(popup)

	queue_free()

func _draw():
	var bob := sin(_bob_t * 3.5) * 1.5
	var bv   := Vector2(0, bob)
	var wdata: Dictionary = GameManager.WEAPONS.get(weapon_id, {})
	var wcol: Color = wdata.get("color", Color(0.70, 0.70, 0.70))

	# Glow base
	draw_arc(bv, 7.5, 0, TAU, 20, Color(wcol.r, wcol.g, wcol.b, 0.30), 1.0)
	draw_circle(bv, 4.5, Color(wcol.r * 0.5, wcol.g * 0.5, wcol.b * 0.5, 0.80))

	# Weapon-specific shape
	match weapon_id:
		"GARROTE", "GARROTE_WIRE":
			# Two circles connected by a line
			draw_circle(bv + Vector2(-3.5, 0), 1.6, wcol)
			draw_circle(bv + Vector2( 3.5, 0), 1.6, wcol)
			draw_line(bv + Vector2(-2.0, 0), bv + Vector2(2.0, 0), wcol, 1.0)
		"VENOM_NEEDLE":
			# Thin vertical line with a tip dot
			draw_line(bv + Vector2(0, -4.5), bv + Vector2(0, 3.0), wcol, 1.2)
			draw_circle(bv + Vector2(0, -5.0), 0.9, wcol)
		"RUNED_BLADE":
			# Diamond with inner glow
			var d1 := Vector2(0, -4.5); var d2 := Vector2(3.2, 0)
			var d3 := Vector2(0,  4.5); var d4 := Vector2(-3.2, 0)
			draw_colored_polygon(PackedVector2Array([d1 + bv, d2 + bv, d3 + bv, d4 + bv]),
				Color(wcol.r, wcol.g, wcol.b, 0.80))
			draw_arc(bv, 2.0, 0, TAU, 12, Color(wcol.r, wcol.g, wcol.b, 0.60), 1.0)
		"SMOKE_BLADE":
			# X cross with glow (like shadow blade)
			draw_line(bv + Vector2(-3.5, -3.5), bv + Vector2( 3.5,  3.5), wcol, 1.5)
			draw_line(bv + Vector2( 3.5, -3.5), bv + Vector2(-3.5,  3.5), wcol, 1.5)
			draw_arc(bv, 2.5, 0, TAU, 12, Color(wcol.r, wcol.g, wcol.b, 0.45), 1.0)
		"WAR_PICK":
			# Triangle pointing up (heavy pick head)
			var wp1 := bv + Vector2(0, -5.0)
			var wp2 := bv + Vector2(-3.5, 3.0)
			var wp3 := bv + Vector2( 3.5, 3.0)
			draw_colored_polygon(PackedVector2Array([wp1, wp2, wp3]), wcol)
			draw_line(bv + Vector2(0, -5.0), bv + Vector2(0, 4.5), wcol, 1.0)
		"SHIV", "STILETTO", "ASSASSIN_FANG":
			# Thin triangle pointing up (dagger/shiv)
			var t1 := bv + Vector2(0, -5.0)
			var t2 := bv + Vector2(-1.8, 3.5)
			var t3 := bv + Vector2( 1.8, 3.5)
			draw_colored_polygon(PackedVector2Array([t1, t2, t3]), wcol)
		"SHADOW_BLADE", "GHOST_BLADE", "VOID_REAPER":
			# Thin X cross with purple glow
			draw_line(bv + Vector2(-3.5, -3.5), bv + Vector2( 3.5,  3.5), wcol, 1.5)
			draw_line(bv + Vector2( 3.5, -3.5), bv + Vector2(-3.5,  3.5), wcol, 1.5)
			draw_arc(bv, 2.5, 0, TAU, 12, Color(wcol.r, wcol.g, wcol.b, 0.45), 1.0)
		"CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT":
			# Horizontal bar + vertical notch
			draw_line(bv + Vector2(-5.0, 0), bv + Vector2(5.0, 0), wcol, 2.0)
			draw_line(bv + Vector2(0, -4.0), bv + Vector2(0, 1.5), wcol, 1.2)
		_:
			# Fallback: thin triangle
			var ft1 := bv + Vector2(0, -4.5)
			var ft2 := bv + Vector2(-2.0, 3.0)
			var ft3 := bv + Vector2( 2.0, 3.0)
			draw_colored_polygon(PackedVector2Array([ft1, ft2, ft3]), wcol)

	# "[E] Pick up NAME" hint text when player is close
	var player := get_tree().get_first_node_in_group("player")
	if player and is_in_range(player.global_position):
		var wname: String = wdata.get("name", weapon_id)
		var font := ThemeDB.fallback_font
		var hint := "[E] Pick up " + wname
		var tw: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(font, Vector2(-tw * 0.5, bob - 12.0), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 1.0, 0.80, 0.90))
