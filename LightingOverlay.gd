extends Control
# Screen-space cinematic lighting: a soft radial vignette (the camera keeps the
# player centred, so this reads as a torch-lit "pool of vision") plus a gentle
# per-floor colour grade. Lives in a CanvasLayer below the HUD, so the HUD and
# world entities stay crisp while the environment gains atmosphere.

var _vignette: GradientTexture2D
var _grade: Color = Color(1, 0.85, 0.6, 0.0)
var _t: float = 0.0
var _alert_pulse: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	_build_vignette()
	_apply_grade()
	get_viewport().size_changed.connect(queue_redraw)

func _process(delta: float) -> void:
	_t += delta
	# Subtle living flicker on the vignette strength.
	queue_redraw()

func _apply_grade() -> void:
	var gm := get_node_or_null("/root/GameManager")
	var fl: int = 1
	if gm != null:
		fl = int(gm.get("current_floor"))
	match fl:
		1: _grade = Color(1.0, 0.74, 0.40, 0.10)   # warm amber cellar
		2: _grade = Color(0.55, 0.70, 1.0, 0.12)    # cold blue dungeon
		_: _grade = Color(0.66, 0.50, 1.0, 0.14)    # arcane violet vault

func _build_vignette() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.78, 1.0])
	g.colors = PackedColorArray([
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.30),
		Color(0, 0, 0, 0.72),
	])
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.0, 0.5)
	_vignette.width = 256
	_vignette.height = 256

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Per-floor colour grade wash (very subtle, additive-feel via low alpha).
	if _grade.a > 0.0:
		draw_rect(r, _grade)
	# Radial vignette, stretched to the viewport (slightly elliptical — natural).
	var flick: float = 1.0 + sin(_t * 3.3) * 0.02 + sin(_t * 7.7) * 0.015
	draw_texture_rect(_vignette, r, false, Color(1, 1, 1, clamp(flick, 0.9, 1.1)))
	# A second tighter vignette for a deeper falloff at the very corners.
	var inset := r.grow(-min(size.x, size.y) * 0.18)
	draw_texture_rect(_vignette, inset, false, Color(0, 0, 0, 0.0))
