extends Node2D

const MAX_RADIUS = { 1: 40.0, 2: 120.0 }
const DURATION = 0.55

var _progress := 0.0
var _max_r := 80.0
var _color := Color.WHITE

func setup(level: int):
	_max_r = MAX_RADIUS.get(level, 80.0)
	_color = Color(1.0, 0.75, 0.2) if level == 1 else Color(1.0, 0.25, 0.1)

func _process(delta):
	_progress += delta / DURATION
	if _progress >= 1.0:
		queue_free()
		return
	queue_redraw()

func _draw():
	var alpha_base = 1.0 - _progress
	var r1 = _progress * _max_r
	draw_arc(Vector2.ZERO, r1, 0, TAU, 32,
		Color(_color.r, _color.g, _color.b, alpha_base * 0.55), 1.5)
	if _progress > 0.18:
		var r2 = (_progress - 0.18) * _max_r
		draw_arc(Vector2.ZERO, r2, 0, TAU, 24,
			Color(_color.r, _color.g, _color.b, alpha_base * 0.3), 1.0)
