## WantedPoster.gd  (V14)
## Decorative interactable prop pinned in the Entry Foyer.
## Shows wanted-level flavor text when the player presses interact.
extends Node2D

const _dice_scene = preload("res://DicePopup.tscn")
var _t := 0.0
var _player_nearby := false

const _WANTED_LINES := [
	"",
	"WANTED (1 Star) — Minor thief. Reward: 25 gp.",
	"WANTED (2 Stars) — Known burglar. Reward: 80 gp.",
	"WANTED (3 Stars) — Dangerous felon. Reward: 200 gp. Armed & dangerous.",
	"WANTED (4 Stars) — Enemy of the Crown. Reward: 500 gp. Kill on sight.",
	"WANTED (5 Stars) — HIGH TREASON. Reward: 1500 gp. No quarter given.",
]

func _ready():
	add_to_group("interactable")

func _process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var was_nearby := _player_nearby
	_player_nearby = global_position.distance_to(player.global_position) <= 22.0
	if _player_nearby and not was_nearby:
		queue_redraw()   # highlight when entered
	elif not _player_nearby and was_nearby:
		queue_redraw()   # de-highlight when left

func interact() -> void:
	var wl: int = GameManager.wanted_level
	var line: String = _WANTED_LINES[clampi(wl, 0, _WANTED_LINES.size() - 1)]
	if wl == 0:
		line = "WANTED — No outstanding warrants. (For now.)"
	_popup(line, Color(0.90, 0.75, 0.20))

func _popup(text: String, color: Color) -> void:
	var p := _dice_scene.instantiate()
	p.setup(text, color)
	p.global_position = global_position + Vector2(0, -24)
	get_tree().root.add_child(p)

func _draw() -> void:
	var wl: int = GameManager.wanted_level
	var paper_col := Color(0.80, 0.72, 0.50)
	var text_col  := Color(0.20, 0.12, 0.06)
	var star_col  := Color(0.92, 0.65, 0.10) if wl > 0 else Color(0.50, 0.45, 0.35)
	var border_col := Color(0.60, 0.20, 0.10) if wl >= 3 else Color(0.35, 0.25, 0.12)

	# Hover highlight
	if _player_nearby:
		draw_rect(Rect2(-11, -20, 22, 26), Color(1.0, 1.0, 0.6, 0.12))

	# Paper background
	draw_rect(Rect2(-10, -19, 20, 24), paper_col)
	draw_rect(Rect2(-10, -19, 20, 24), border_col, false, 1.0)

	# Top "WANTED" header bar
	var header_col: Color = Color(0.65, 0.10, 0.08) if wl >= 1 else Color(0.40, 0.30, 0.20)
	draw_rect(Rect2(-10, -19, 20, 7), header_col)

	# Three horizontal lines (text placeholder)
	for i in range(3):
		draw_line(Vector2(-7.0, -10.0 + i * 4.0), Vector2(7.0, -10.0 + i * 4.0),
			text_col * Color(1,1,1, 0.55), 1.0)

	# Wanted-level stars at bottom
	for i in range(maxi(wl, 0)):
		var sx: float = -8.0 + i * 4.5
		draw_circle(Vector2(sx, 3.5), 1.5, star_col)

	# Pulse ring when high wanted
	if wl >= 3:
		var pa: float = 0.30 + 0.20 * abs(sin(_t * 3.5))
		draw_rect(Rect2(-11, -20, 22, 26), Color(0.90, 0.10, 0.05, pa), false, 1.2)
