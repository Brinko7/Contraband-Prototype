extends Area2D
# Glowing relic chest — player walks over to pick up.

const _RELIC_TEX_PATH := "res://sprites/pickup_relic.png"
static var _relic_tex: Texture2D = null

var relic_id: String = ""
var _gm: Node = null
var _bob_t := 0.0
var _collected := false

func _ready() -> void:
	_gm = get_node_or_null("/root/GameManager")
	add_to_group("relics")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _relic_tex == null and ResourceLoader.exists(_RELIC_TEX_PATH):
		_relic_tex = load(_RELIC_TEX_PATH)

func setup(id: String) -> void:
	relic_id = id

func _process(delta: float) -> void:
	if _collected:
		return
	_bob_t += delta
	queue_redraw()

func _draw() -> void:
	if _collected:
		return
	var bob := sin(_bob_t * 3.0) * 2.0
	var rdata: Dictionary = {}
	if _gm:
		rdata = _gm.get_relic_data_by_id(relic_id)
	var col: Color = rdata.get("color", Color(0.85, 0.70, 0.20))
	var glow_alpha := 0.18 + 0.08 * sin(_bob_t * 4.0)
	# Glow ring — kept as FX, tinted to the relic's color.
	draw_circle(Vector2(0, bob), 10.0, Color(col.r, col.g, col.b, glow_alpha))
	draw_circle(Vector2(0, bob), 7.0,  Color(col.r, col.g, col.b, glow_alpha * 1.5))
	# Relic sprite
	if _relic_tex != null:
		draw_texture_rect(_relic_tex, Rect2(Vector2(-8, bob - 10), Vector2(16, 16)), false)
	else:
		draw_rect(Rect2(-5, bob - 4, 10, 8), Color(0.30, 0.22, 0.12))
		draw_rect(Rect2(-5, bob - 4, 10, 8), Color(col.r, col.g, col.b, 0.8), false, 1.2)
		draw_circle(Vector2(0, bob - 1), 2.5, Color(col.r, col.g, col.b, 0.9))
	# Label
	var fname: String = rdata.get("name", "Relic")
	draw_string(ThemeDB.fallback_font, Vector2(-24, bob - 12), fname,
		HORIZONTAL_ALIGNMENT_CENTER, 48, 8, Color(col.r, col.g, col.b, 0.9))

func _on_body_entered(body: Node) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	if _gm:
		_gm.add_relic(relic_id)
		var rdata: Dictionary = _gm.get_relic_data_by_id(relic_id)
		_gm.shake(2.0, 0.25)
	queue_free()
