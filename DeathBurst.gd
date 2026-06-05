extends Node2D

# Explosive directional burst on combat kill — rays bias toward kill direction
const _DUR:   float = 0.42
const _RAYS:  int   = 12
const _LEN:   float = 32.0

var _timer:  float  = 0.0
var _color:  Color  = Color(1.0, 0.25, 0.15)
var _dir:    Vector2 = Vector2.ZERO   # kill direction — rays bias this way
var _angles: Array  = []
var _lengths: Array = []   # per-ray max length for variety

func setup(col: Color, kill_dir: Vector2 = Vector2.ZERO):
	_color = col
	_dir   = kill_dir.normalized() if kill_dir != Vector2.ZERO else Vector2.ZERO
	_timer = _DUR
	_angles.clear()
	_lengths.clear()

	for i in range(_RAYS):
		var angle: float
		if _dir != Vector2.ZERO:
			# 60% of rays spray in a forward 120° cone; 40% scatter backward
			if i < int(_RAYS * 0.6):
				var spread: float = deg_to_rad(60.0)
				angle = _dir.angle() + randf_range(-spread, spread)
			else:
				angle = randf() * TAU
		else:
			angle = randf() * TAU
		_angles.append(angle)
		_lengths.append(_LEN * randf_range(0.55, 1.25))

func _process(delta: float):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw():
	var t: float    = _timer / _DUR    # 1 → 0 as burst progresses
	var fade: float = t

	# Expanding ring — slightly elliptical along kill direction
	var ring_r: float = (1.0 - t) * _LEN * 1.5
	draw_arc(Vector2.ZERO, ring_r, 0, TAU, 28,
		Color(_color.r, _color.g, _color.b, fade * 0.55), 2.0)

	# Inner flash (only first 35% of life)
	if t > 0.65:
		var inner_alpha: float = (t - 0.65) / 0.35 * 0.35
		draw_circle(Vector2.ZERO, ring_r * 0.55, Color(1.0, 0.85, 0.60, inner_alpha))

	# Directional blood mist smear
	if _dir != Vector2.ZERO:
		var mist_frac: float = (1.0 - t)
		var mist_len: float = mist_frac * _LEN * 1.8
		var mist_w: float = mist_len * 0.35
		var mist_alpha: float = fade * 0.30
		for i in range(5):
			var offset: Vector2 = _dir.rotated(randf_range(-0.3, 0.3)) * mist_len * randf_range(0.3, 1.0)
			draw_circle(offset, randf_range(1.5, 3.5), Color(_color.r, _color.g * 0.3, _color.b * 0.3, mist_alpha))

	# Radial rays shooting outward
	for i in range(_angles.size()):
		var angle: float = _angles[i]
		var max_len: float = _lengths[i]
		var start: Vector2 = Vector2(cos(angle), sin(angle)) * ring_r * 0.25
		var end:   Vector2 = Vector2(cos(angle), sin(angle)) * (max_len * (1.0 - t * 0.25))
		var ray_fade: float = fade * fade
		var ray_width: float = 1.8
		# Rays in kill direction are thicker/brighter
		if _dir != Vector2.ZERO:
			var dot_align: float = Vector2(cos(angle), sin(angle)).dot(_dir)
			ray_width = lerp(1.2, 2.8, (dot_align + 1.0) * 0.5)
			ray_fade  = ray_fade * lerp(0.5, 1.0, (dot_align + 1.0) * 0.5)
		draw_line(start, end,
			Color(_color.r, _color.g, _color.b, ray_fade * 0.85), ray_width)
		# Bright tip
		draw_circle(end, (1.6 + ray_width * 0.3) * fade,
			Color(1.0, 0.92, 0.75, ray_fade))
