extends Control
# XP bar drawn below HUD panel. Also shows relic banner when active.

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var w := size.x
	if w <= 0:
		w = 224.0
	var h := 6.0

	# Background
	draw_rect(Rect2(0, 0, w, h), Color(0.10, 0.10, 0.14, 0.70))

	# XP fill
	var lvl: int  = GameManager.run_level
	var xp: int   = GameManager.run_xp
	var cap: int  = GameManager.XP_MAX_LEVEL
	if lvl >= cap:
		draw_rect(Rect2(0, 0, w, h), Color(0.40, 1.00, 0.55, 0.85))
	else:
		var frac: float = float(xp) / float(GameManager.XP_PER_LEVEL)
		draw_rect(Rect2(0, 0, w * frac, h), Color(0.30, 0.90, 0.45, 0.80))

	# Level pips
	if lvl > 0:
		for i in range(lvl):
			var px := (float(i) + 0.5) / float(cap) * w
			draw_circle(Vector2(px, h * 0.5), 2.5, Color(0.40, 1.00, 0.55, 0.90))

	# Label
	var lbl: String
	if lvl >= cap:
		lbl = "MAX LVL"
	else:
		lbl = "LVL %d  ·  %d/%d XP" % [lvl, xp, GameManager.XP_PER_LEVEL]
	draw_string(ThemeDB.fallback_font, Vector2(2, h + 9), lbl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.90, 0.55, 0.75))

	# Relic banner — overlay above bar when active
	var hud := get_parent().get_parent() as Node
	if hud and hud.get("_relic_banner_t") != null:
		var bt: float = float(hud.get("_relic_banner_t"))
		if bt > 0.0:
			var alpha := minf(bt, 1.0) * minf(bt / _RELIC_BANNER_DUR, 1.0)
			var text: String = str(hud.get("_relic_banner_text"))
			var col: Color   = hud.get("_relic_banner_color") as Color
			draw_rect(Rect2(0, h + 12, 224, 16), Color(0.06, 0.05, 0.10, alpha * 0.85))
			draw_string(ThemeDB.fallback_font, Vector2(4, h + 23), text,
				HORIZONTAL_ALIGNMENT_LEFT, 220, 9, Color(col.r, col.g, col.b, alpha))

const _RELIC_BANNER_DUR := 3.0
