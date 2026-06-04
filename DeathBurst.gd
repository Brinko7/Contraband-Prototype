extends Node2D

# Explosive radial burst on combat kill — 8 lines + ring flash
const _DUR:   float = 0.38
const _RAYS:  int   = 8
const _LEN:   float = 28.0

var _timer:  float  = 0.0
var _color:  Color  = Color(1.0, 0.25, 0.15)
var _angles: Array  = []

func setup(col: Color):
	_color = col
	_timer = _DUR
	for i in range(_RAYS):
		_angles.append(randf() * TAU)

func _process(delta: float):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw():
	var t: float    = _timer / _DUR    # 1 → 0
	var fade: float = t

	# Expanding ring
	var ring_r: float = (1.0 - t) * _LEN * 1.4
	draw_arc(Vector2.ZERO, ring_r, 0, TAU, 28,
		Color(_color.r, _color.g, _color.b, fade * 0.55), 2.0)

	# Inner fill flash (only first 40% of life)
	if t > 0.60:
		var inner_alpha: float = (t - 0.60) / 0.40 * 0.30
		draw_circle(Vector2.ZERO, ring_r * 0.6, Color(1.0, 0.85, 0.60, inner_alpha))

	# Radial rays that shoot outward
	for angle in _angles:
		var start: Vector2 = Vector2(cos(angle), sin(angle)) * ring_r * 0.3
		var end:   Vector2 = Vector2(cos(angle), sin(angle)) * (_LEN * (1.0 - t * 0.3))
		var ray_fade: float = fade * fade
		draw_line(start, end,
			Color(_color.r, _color.g, _color.b, ray_fade * 0.80), 1.8)
		# Bright tip
		draw_circle(end, 1.8 * fade, Color(1.0, 0.95, 0.80, ray_fade))
