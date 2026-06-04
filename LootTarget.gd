extends Node2D

signal looted

const INTERACT_RANGE = 20.0
const _dice_scene = preload("res://DicePopup.tscn")

@export var is_bonus := false
@export var loot_value := 200
@export var rarity: int = 0  # GameManager.Rarity: 0=COMMON, 1=UNCOMMON, 2=RARE

# Chest type: 0=iron, 1=ornate, 2=arcane
@export var chest_type: int = 0

var _bob_t := 0.0
var _opened := false

func _ready():
	# Auto-select chest visual based on rarity
	if is_bonus: chest_type = 2
	elif rarity >= 2: chest_type = 1
	else: chest_type = 0

func _process(delta):
	_bob_t += delta
	queue_redraw()

func _draw():
	var player = get_tree().get_first_node_in_group("player")
	var in_range := player != null and is_in_range(player.global_position)
	var pulse := sin(_bob_t * 3.2) * 0.5 + 0.5
	var glow_col := _get_glow_color()

	# Outer glow
	var glow_r := 14.0 + sin(_bob_t * 2.8) * 1.2
	draw_circle(Vector2(0.5, 1.0), glow_r, Color(glow_col.r, glow_col.g, glow_col.b, 0.06 + pulse * 0.04))

	# Draw the chest body
	if _opened:
		_draw_chest_open(glow_col, pulse)
	else:
		_draw_chest_closed(glow_col, pulse)

	# Interaction prompt ring
	if in_range and not _opened:
		draw_arc(Vector2.ZERO, 16.0 + pulse * 1.5, 0, TAU, 24,
			Color(0.95, 0.90, 0.60, 0.65 + pulse * 0.20), 1.5)

func _get_glow_color() -> Color:
	if is_bonus: return Color(0.35, 0.65, 1.00)
	match rarity:
		2: return Color(0.28, 0.55, 1.00)
		1: return Color(0.28, 0.82, 0.45)
		_: return Color(0.92, 0.75, 0.18)

func _draw_chest_closed(glow_col: Color, pulse: float):
	var t := _bob_t
	match chest_type:
		0:  # Iron chest — sturdy, dark metal
			var metal := Color(0.35, 0.32, 0.38)
			var band  := Color(0.28, 0.26, 0.30)
			var rivet := Color(0.55, 0.50, 0.58)
			# Body
			draw_rect(Rect2(-8, -5, 16, 11), metal)
			draw_rect(Rect2(-7, -4, 14, 9), Color(metal.r * 1.15, metal.g * 1.12, metal.b * 1.18))
			# Lid
			draw_rect(Rect2(-8, -8, 16, 4), band)
			draw_rect(Rect2(-7, -7, 14, 3), Color(band.r * 1.2, band.g * 1.2, band.b * 1.2))
			# Metal bands
			draw_rect(Rect2(-8, -1, 16, 2), band)
			draw_rect(Rect2(-1, -8, 2, 11), band)
			# Rivets
			for rx: float in [-6, 4]:
				draw_circle(Vector2(rx, -6), 1.0, rivet)
				draw_circle(Vector2(rx, 3), 1.0, rivet)
			# Lock
			draw_circle(Vector2(0, -1), 2.0, Color(0.68, 0.62, 0.28))
			draw_circle(Vector2(0, -1), 1.0, Color(0.45, 0.40, 0.18))
			# Glow from lock keyhole
			draw_circle(Vector2(0, -1), 2.5, Color(glow_col.r, glow_col.g, glow_col.b, 0.22 + pulse * 0.12))
		1:  # Ornate chest — noble wood with gold trim
			var wood  := Color(0.45, 0.28, 0.12)
			var gold  := Color(0.88, 0.68, 0.18)
			var gem_c := Color(0.85, 0.18, 0.18)
			# Wood body
			draw_rect(Rect2(-9, -6, 18, 12), wood.darkened(0.2))
			draw_rect(Rect2(-8, -5, 16, 10), wood)
			# Wood grain lines
			for gy: float in [-2.0, 1.0]:
				draw_line(Vector2(-7, gy), Vector2(7, gy), Color(wood.r * 0.8, wood.g * 0.8, wood.b * 0.75, 0.45), 0.7)
			# Gold trim
			draw_rect(Rect2(-9, -6, 18, 2), gold)
			draw_rect(Rect2(-9, 4, 18, 2), gold.darkened(0.1))
			draw_rect(Rect2(-9, -6, 2, 12), gold)
			draw_rect(Rect2(7, -6, 2, 12), gold)
			# Center clasp with gem
			draw_circle(Vector2(0, -1.5), 3.5, gold)
			draw_circle(Vector2(0, -1.5), 2.2, gem_c)
			draw_circle(Vector2(0, -1.5), 1.0, Color(1.0, 0.45, 0.45, 0.80))
			# Shimmer around gem
			draw_arc(Vector2(0, -1.5), 3.0, 0, TAU, 14,
				Color(glow_col.r, glow_col.g, glow_col.b, 0.30 + pulse * 0.20), 1.0)
		2:  # Arcane chest — glowing rune-inscribed vault
			var stone := Color(0.18, 0.14, 0.28)
			var rune  := Color(glow_col.r, glow_col.g, glow_col.b)
			# Stone body
			draw_rect(Rect2(-10, -7, 20, 14), stone.darkened(0.2))
			draw_rect(Rect2(-9, -6, 18, 12), stone)
			# Rune inscriptions
			var rune_a := 0.45 + pulse * 0.30
			for rx: float in [-6, 0, 6]:
				draw_circle(Vector2(rx, -1), 1.5, Color(rune.r, rune.g, rune.b, rune_a))
				draw_line(Vector2(rx - 1.5, -1), Vector2(rx + 1.5, -1), Color(rune.r, rune.g, rune.b, rune_a * 0.7), 0.6)
				draw_line(Vector2(rx, -2.5), Vector2(rx, 0.5), Color(rune.r, rune.g, rune.b, rune_a * 0.7), 0.6)
			# Arcane border glow
			draw_rect(Rect2(-10, -7, 20, 2), Color(rune.r, rune.g, rune.b, rune_a * 0.6))
			draw_rect(Rect2(-10, 5, 20, 2), Color(rune.r, rune.g, rune.b, rune_a * 0.6))
			# Corner gems pulsing
			for cx: float in [-8, 7]:
				for cy: float in [-5, 4]:
					draw_circle(Vector2(cx, cy), 1.5, Color(rune.r, rune.g, rune.b, 0.55 + pulse * 0.35))
		_:
			draw_rect(Rect2(-8, -5, 16, 11), Color(0.35, 0.28, 0.18))

func _draw_chest_open(glow_col: Color, pulse: float):
	# Open chest — dark inside, gold spill
	var wood := Color(0.42, 0.26, 0.10) if chest_type > 0 else Color(0.32, 0.28, 0.32)
	draw_rect(Rect2(-9, -3, 18, 9), wood.darkened(0.2))
	draw_rect(Rect2(-8, -2, 16, 7), Color(0.08, 0.06, 0.10))  # dark interior
	# Lid flipped up
	draw_rect(Rect2(-8, -12, 16, 6), wood)
	# Interior glow
	draw_circle(Vector2(0, 1), 5.0, Color(glow_col.r, glow_col.g, glow_col.b, 0.18 + pulse * 0.10))
	# Gold coins spilling
	for i in range(5):
		var cx := randf_range(-5, 5) if i < 5 else 0.0
		draw_circle(Vector2(float(i) * 2.5 - 5, 2.0 + float(i % 2)), 1.2, Color(0.92, 0.75, 0.18))

func interact(player: Node2D):
	if not player.has_method("pickup_loot"):
		return
	if not is_bonus:
		# Show named loot with flavor description
		var popup := _dice_scene.instantiate()
		popup.setup(GameManager.get_main_loot_name(), Color(0.95, 0.82, 0.22))
		popup.global_position = global_position + Vector2(0, -28)
		get_tree().root.add_child(popup)
		var desc_popup := _dice_scene.instantiate()
		desc_popup.setup(GameManager.get_main_loot_desc(), Color(0.75, 0.70, 0.55))
		desc_popup.global_position = global_position + Vector2(0, -14)
		get_tree().root.add_child(desc_popup)
		# CURSED_VAULT: trigger nearest trap when grabbing primary loot
		if GameManager.run_modifier == "CURSED_VAULT":
			_trigger_nearest_trap()
	# DOUBLE_OR_NOTHING: loot worth 2×
	if GameManager.run_modifier == "DOUBLE_OR_NOTHING":
		loot_value = int(loot_value * 2.0)
	var rarity_mults := {0: 1.0, 1: 1.5, 2: 2.5}
	var value := int(loot_value * rarity_mults.get(rarity, 1.0))
	if GameManager.run_modifier == "BONUS_CONTRACT":
		value = int(value * 1.6)
	if GameManager.floor_complication == "WINDFALL":
		value = int(value * 1.4)
	if GameManager.selected_class == "CUTPURSE":
		value = int(value * 1.25)
	if is_bonus and GameManager.get_guild_unlock("SAFECRACKER"):
		value = int(value * 1.5)
	GameManager.add_gold(value)
	_gold_popup(value)
	if is_bonus:
		GameManager.collect_bonus_loot()
		player.emit_noise(player.NoiseLevel.QUIET)
	else:
		player.pickup_loot()
	AudioManager.loot_collect()
	looted.emit()
	_opened = true
	queue_redraw()
	await get_tree().create_timer(0.35).timeout
	queue_free()

func _gold_popup(value: int):
	var popup = _dice_scene.instantiate()
	popup.setup("+%d gp" % value, Color(0.95, 0.80, 0.10))
	popup.global_position = global_position + Vector2(0, -14)
	get_tree().root.add_child(popup)

func is_in_range(player_pos: Vector2) -> bool:
	return global_position.distance_to(player_pos) <= INTERACT_RANGE

func _trigger_nearest_trap():
	var nearest: Node = null
	var nearest_dist := 9999.0
	for trap in get_tree().get_nodes_in_group("traps"):
		var d: float = global_position.distance_to(trap.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = trap
	if nearest and nearest.has_method("trigger"):
		nearest.trigger()
	elif nearest:
		nearest.set("_triggered", true)
