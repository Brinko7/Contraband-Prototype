extends Node2D

const LIFETIME := 1.6

var _text  := ""
var _color := Color.WHITE
var _t     := 0.0

func setup(text: String, color: Color):
	_text  = text
	_color = color

func _process(delta):
	_t += delta
	position.y -= delta * 14.0
	if _t >= LIFETIME:
		queue_free()
	queue_redraw()

func _draw():
	var alpha := 1.0 - (_t / LIFETIME)
	var font := ThemeDB.fallback_font
	# Scale up briefly on spawn (punchy entrance)
	var pop_scale: float = 1.0 + max(0.0, 0.4 - _t * 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * pop_scale)
	# Background pill for readability
	var str_w := 10.0 * _text.length()
	draw_rect(Rect2(-str_w * 0.5 - 3, -10, str_w + 6, 12),
		Color(0.0, 0.0, 0.0, alpha * 0.45))
	# Drop shadow
	draw_string(font, Vector2(-str_w * 0.5 + 1, 0), _text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, alpha * 0.7))
	# Main text
	draw_string(font, Vector2(-str_w * 0.5, -1), _text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		Color(_color.r, _color.g, _color.b, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
