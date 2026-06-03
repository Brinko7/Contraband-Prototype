extends Node2D

signal looted

const INTERACT_RANGE = 20.0
const _dice_scene   = preload("res://DicePopup.tscn")
const _CHEST_SHEET  = preload("res://sprites/chest_sheet.png")

@export var is_bonus := false
@export var loot_value := 200
@export var rarity: int = 0  # GameManager.Rarity: 0=COMMON, 1=UNCOMMON, 2=RARE

var _bob_t := 0.0
var _sprite: Sprite2D

func _ready():
	_sprite = Sprite2D.new()
	_sprite.texture = _CHEST_SHEET
	_sprite.hframes = 2
	_sprite.vframes = 1
	_sprite.frame = 0  # closed
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(1.5, 1.5)
	if is_bonus:
		_sprite.modulate = Color(0.5, 0.7, 1.0)
	add_child(_sprite)

func _process(delta):
	_bob_t += delta
	queue_redraw()

func _draw():
	var player = get_tree().get_first_node_in_group("player")
	var glow_alpha := 0.3 + sin(_bob_t * 3.0) * 0.15
	var rarity_colors: Dictionary = GameManager.RARITY_COLORS
	var glow_col: Color = Color(0.3, 0.6, 1.0) if is_bonus \
		else rarity_colors.get(rarity, Color(0.95, 0.8, 0.1))
	draw_arc(Vector2.ZERO, 16.0 + sin(_bob_t * 3.0) * 1.5, 0, TAU, 20,
		Color(glow_col.r, glow_col.g, glow_col.b, glow_alpha * 0.5), 1.0)
	draw_arc(Vector2.ZERO, 13.0, 0, TAU, 16, Color(glow_col.r, glow_col.g, glow_col.b, glow_alpha), 1.5)
	if player and is_in_range(player.global_position):
		draw_arc(Vector2.ZERO, 18.0 + sin(_bob_t * 6.0) * 1.5, 0, TAU, 20,
			Color(0.95, 0.90, 0.60, 0.70), 1.5)

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
	if _sprite:
		_sprite.frame = 1  # open chest frame
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
