extends Node2D

var _value:    int     = 1
var _color:    Color   = Color(1.0, 0.25, 0.25)
var _timer:    float   = 0.0
const _DUR:    float   = 0.65
const _RISE:   float   = 22.0   # px upward travel over lifetime
const _FONT_SIZE: int  = 14

func setup(damage: int, col: Color):
	_value = damage
	_color = col
	_timer = _DUR

func _process(delta: float):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw():
	var t: float     = _timer / _DUR          # 1 → 0
	var fade: float  = t * t                  # ease-out alpha
	var rise: float  = (1.0 - t) * _RISE      # drifts upward
	var pop: float   = 1.0 + max(0.0, (t - 0.75) * 1.8)  # brief scale pop at birth

	var font := ThemeDB.fallback_font
	var label: String = "-%d" % _value

	draw_set_transform(Vector2(0, -rise), 0.0, Vector2.ONE * pop)

	# Shadow for contrast at any background
	draw_string(font, Vector2(1, 1), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE,
		Color(0.0, 0.0, 0.0, fade * 0.70))
	# Main number
	draw_string(font, Vector2.ZERO, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE,
		Color(_color.r, _color.g, _color.b, fade))
