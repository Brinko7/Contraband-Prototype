extends Node2D

const INTERACT_RANGE = 4.0
const SENSE_RANGE    = 32.0

var _triggered_this_step := false
var _player_was_on := false
var _flash_timer := 0.0
var _flash_active := false

static var NoiseRippleScene = preload("res://NoiseRipple.tscn")
static var DicePopupScene   = preload("res://DicePopup.tscn")

var _disarmed := false

func _ready():
	add_to_group("traps")
	add_to_group("interactable")

func is_in_range(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= 22.0

func interact(player: Node2D):
	if _disarmed:
		return
	# DISARM_TOOL (Thieves' Tools trinket): always succeeds silently
	if GameManager.has_gear_effect("DISARM_TOOL"):
		_disarmed = true
		queue_redraw()
		AudioManager.step_quiet()
		return
	var roll: int = GameManager.roll_d20()
	# Dwarf stonecunning: always succeeds
	if GameManager.selected_race == "DWARF":
		roll = 20
	# Show dice popup
	var popup = DicePopupScene.instantiate()
	if roll >= 10:
		popup.setup("Disarm %d ✓" % roll, Color(0.30, 0.95, 0.45))
		popup.global_position = global_position + Vector2(0, -20)
		get_tree().root.add_child(popup)
		_disarmed = true
		queue_redraw()
		AudioManager.step_quiet()
	else:
		popup.setup("Disarm %d ✗" % roll, Color(1.0, 0.20, 0.20))
		popup.global_position = global_position + Vector2(0, -20)
		get_tree().root.add_child(popup)
		trigger()

func trigger():
	_show_popup("TRAP!", Color(1.0, 0.15, 0.15))
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_signal("noise_emitted"):
		player.noise_emitted.emit(2, global_position)
	_spawn_ripple(2)
	AudioManager.step_loud()
	_flash_active = true
	_flash_timer  = 0.3
	GameManager.shake(3.5, 0.3)
	queue_redraw()

func _process(delta):
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_active = false
		queue_redraw()

	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var dist = global_position.distance_to(player.global_position)
	var on_tile = dist <= INTERACT_RANGE

	if _disarmed:
		return

	if on_tile and not _player_was_on and not _triggered_this_step:
		_triggered_this_step = true
		_player_was_on = true
		var sneaking = player.get("is_sneaking") == true
		if sneaking:
			_show_popup("Trap! Careful...", Color(0.3, 1.0, 0.4))
			if player.has_signal("noise_emitted"):
				player.noise_emitted.emit(1, global_position)
			_spawn_ripple(1)
			AudioManager.step_quiet()
		else:
			_show_popup("TRAP!", Color(1.0, 0.15, 0.15))
			if player.has_signal("noise_emitted"):
				player.noise_emitted.emit(2, global_position)
			_spawn_ripple(2)
			AudioManager.step_loud()
			_flash_active = true
			_flash_timer = 0.3
			GameManager.shake(3.5, 0.3)
		queue_redraw()
	elif not on_tile:
		_player_was_on = false
		_triggered_this_step = false

func _show_popup(text: String, color: Color):
	var popup = DicePopupScene.instantiate()
	popup.setup(text, color)
	popup.global_position = global_position + Vector2(0, -20)
	get_tree().root.add_child(popup)

func _spawn_ripple(level: int):
	var ripple = NoiseRippleScene.instantiate()
	ripple.setup(level)
	ripple.global_position = global_position
	get_tree().root.add_child(ripple)

func _draw():
	var player = get_tree().get_first_node_in_group("player")
	var near_sneaking := false
	var dwarf_sense   := false
	if player:
		var dist = global_position.distance_to(player.global_position)
		near_sneaking = dist <= SENSE_RANGE and player.get("is_sneaking") == true
		dwarf_sense   = dist <= SENSE_RANGE and GameManager.selected_race == "DWARF"

	var plate_color: Color
	if _disarmed:
		plate_color = Color(0.25, 0.55, 0.30)
	elif _flash_active:
		plate_color = Color(1.0, 0.15, 0.15)
	elif near_sneaking or dwarf_sense:
		plate_color = Color(0.7, 0.65, 0.2)
	else:
		plate_color = Color(0.45, 0.45, 0.45)

	# Main pressure plate square
	draw_rect(Rect2(-6, -6, 12, 12), plate_color)
	draw_rect(Rect2(-6, -6, 12, 12), Color(plate_color.r * 0.6, plate_color.g * 0.6, plate_color.b * 0.6), false, 1.0)

	# Corner marks
	var corner_color = Color(plate_color.r * 0.7, plate_color.g * 0.7, plate_color.b * 0.7)
	draw_line(Vector2(-6, -6), Vector2(-3, -6), corner_color, 1.0)
	draw_line(Vector2(-6, -6), Vector2(-6, -3), corner_color, 1.0)
	draw_line(Vector2(6, -6), Vector2(3, -6), corner_color, 1.0)
	draw_line(Vector2(6, -6), Vector2(6, -3), corner_color, 1.0)
	draw_line(Vector2(-6, 6), Vector2(-3, 6), corner_color, 1.0)
	draw_line(Vector2(-6, 6), Vector2(-6, 3), corner_color, 1.0)
	draw_line(Vector2(6, 6), Vector2(3, 6), corner_color, 1.0)
	draw_line(Vector2(6, 6), Vector2(6, 3), corner_color, 1.0)

	# Center dot
	draw_circle(Vector2.ZERO, 1.5, Color(plate_color.r * 0.5, plate_color.g * 0.5, plate_color.b * 0.5))
