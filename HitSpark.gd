extends Node2D

const _DUR:        float = 0.28
const _COUNT:      int   = 12
const _SPEED_MIN:  float = 28.0
const _SPEED_MAX:  float = 72.0
const _SIZE_MIN:   float = 1.2
const _SIZE_MAX:   float = 2.8

var _timer:    float   = 0.0
var _color:    Color   = Color(1.0, 0.70, 0.20)
var _sparks:   Array   = []   # Array of {vel: Vector2, pos: Vector2, size: float}

func setup(col: Color, dir: Vector2):
	_color = col
	_timer = _DUR
	# Bias sparks in the hit direction with a wide spread
	for i in range(_COUNT):
		var base_angle: float = dir.angle() + randf_range(-PI * 0.65, PI * 0.65)
		var speed: float = randf_range(_SPEED_MIN, _SPEED_MAX)
		_sparks.append({
			"vel":  Vector2(cos(base_angle), sin(base_angle)) * speed,
			"pos":  Vector2.ZERO,
			"size": randf_range(_SIZE_MIN, _SIZE_MAX),
		})

func _process(delta: float):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	for s in _sparks:
		s["pos"] += s["vel"] * delta
		s["vel"] *= 0.82   # drag
	queue_redraw()

func _draw():
	var t: float    = _timer / _DUR    # 1 → 0
	var fade: float = t * t

	for s in _sparks:
		var c := Color(_color.r, _color.g, _color.b, fade * 0.90)
		draw_circle(s["pos"], s["size"] * (0.4 + t * 0.6), c)
		# Streak line back toward origin for speed feel
		var streak_end: Vector2 = s["pos"] - s["vel"].normalized() * s["size"] * 2.5
		draw_line(s["pos"], streak_end, Color(_color.r, _color.g, _color.b, fade * 0.45), s["size"] * 0.6)
