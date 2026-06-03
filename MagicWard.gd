extends Node2D

# Arcane rune tile. Stepping on it triggers a silent magical alarm.
# Dart can destroy it before triggering. Dwarf's Stonecunning (passive) reveals it from range.

const INTERACT_RANGE := 4.0
const SENSE_RANGE    := 40.0

var _triggered     := false
var _destroyed     := false
var _flash_timer   := 0.0
var _pulse_t       := 0.0

static var DicePopupScene = preload("res://DicePopup.tscn")

func _ready():
	add_to_group("magic_wards")

func _process(delta):
	if _destroyed:
		return
	_pulse_t += delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
	queue_redraw()

	var player = get_tree().get_first_node_in_group("player")
	if player == null or _triggered:
		return
	if global_position.distance_to(player.global_position) <= INTERACT_RANGE:
		_trigger(player)

func _trigger(player):
	_triggered = true
	_flash_timer = 0.5
	# WARD_RESIST (Warded Mantle): first ward per floor absorbed silently
	if GameManager.has_gear_effect("WARD_RESIST") and not GameManager.get("_ward_resist_used"):
		GameManager.set("_ward_resist_used", true)
		_show_popup("WARD ABSORBED — Warded Mantle!", Color(0.35, 0.50, 0.70))
		AudioManager.ability_use()
		return
	GameManager.record_alert()
	GameManager.shake(2.5, 0.22)
	AudioManager.ward_trigger()
	_show_popup("WARD TRIGGERED!", Color(0.60, 0.20, 0.90))
	# Alert nearest guard
	var best_guard = null
	var best_dist  := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var d: float = global_position.distance_to(guard.global_position)
		if d < best_dist:
			best_dist = d
			best_guard = guard
	if best_guard and best_guard.has_method("_become_suspicious"):
		best_guard._become_suspicious(player.global_position)

func destroy_ward():
	_destroyed = true
	_show_popup("Ward dispelled!", Color(0.55, 0.80, 0.55))
	queue_free()

func _show_popup(text: String, color: Color):
	var popup = DicePopupScene.instantiate()
	popup.setup(text, color)
	popup.global_position = global_position + Vector2(0, -20)
	get_tree().root.add_child(popup)

func _draw():
	if _destroyed:
		return
	var player = get_tree().get_first_node_in_group("player")
	var is_dwarf_near := false
	if player:
		var dist: float = global_position.distance_to(player.global_position)
		is_dwarf_near = dist <= SENSE_RANGE and GameManager.selected_race == "DWARF"

	var pulse: float = sin(_pulse_t * 4.0) * 0.5 + 0.5
	var base_col := Color(0.55, 0.20, 0.90) if not _triggered else Color(0.90, 0.25, 0.90)
	var a: float = 0.75 + pulse * 0.20

	# Rune floor glyph
	draw_rect(Rect2(-6, -6, 12, 12), Color(0.08, 0.04, 0.14, 0.85))
	draw_rect(Rect2(-6, -6, 12, 12), Color(base_col.r, base_col.g, base_col.b, a * 0.60), false, 1.5)

	# Arcane rune lines (simplified star/rune)
	var r := 5.0
	for i in range(6):
		var ang := i * TAU / 6.0
		var p1  := Vector2(cos(ang), sin(ang)) * r
		var p2  := Vector2(cos(ang + TAU / 3.0), sin(ang + TAU / 3.0)) * r
		draw_line(p1, p2, Color(base_col.r, base_col.g, base_col.b, a * 0.55), 0.8)

	# Center glow dot
	draw_circle(Vector2.ZERO, 1.8 + pulse * 0.8, Color(base_col.r, base_col.g, base_col.b, a))

	# Outer pulse ring
	draw_arc(Vector2.ZERO, 7.0 + pulse * 2.0, 0, TAU, 20,
		Color(base_col.r, base_col.g, base_col.b, a * 0.35 * (1.0 - pulse)), 1.0)

	# Dwarf stonecunning: brighter, larger glow ring to signal ward presence
	if is_dwarf_near:
		draw_arc(Vector2.ZERO, 14.0, 0, TAU, 24, Color(0.80, 0.50, 1.00, 0.60 + pulse * 0.25), 2.0)
