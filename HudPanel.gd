extends Control

# Top-left HUD panel: accent bar → class badge → stealth rating → floor pips → HP hearts → loot

const _PANEL_BG  := Color(0.06, 0.05, 0.09, 0.88)
const _PANEL_BDR := Color(0.28, 0.24, 0.18, 0.60)

func _draw():
	var W := 224.0
	var combo := GameManager.combo_hits
	var H := 124.0 if combo > 0 else 108.0
	var font := ThemeDB.fallback_font

	var cls := GameManager.selected_class
	var cls_color: Color
	match cls:
		"CUTPURSE":     cls_color = Color(0.95, 0.75, 0.20)
		"SHADOWDANCER": cls_color = Color(0.55, 0.35, 0.95)
		"SELLSWORD":    cls_color = Color(0.90, 0.40, 0.20)
		"ASSASSIN":     cls_color = Color(0.30, 0.85, 0.55)
		_:              cls_color = Color(0.70, 0.70, 0.65)

	# Background
	draw_rect(Rect2(0, 0, W, H), _PANEL_BG, true)
	# Left accent bar (class color)
	draw_rect(Rect2(0, 0, 3, H), Color(cls_color.r, cls_color.g, cls_color.b, 0.80), true)
	# Outer border
	draw_rect(Rect2(0, 0, W, H), _PANEL_BDR, false, 1.0)
	# Inner highlight line (subtle depth)
	draw_rect(Rect2(3, 1, W - 4, H - 2), Color(1.0, 1.0, 1.0, 0.04), false, 1.0)

	# Corner ornaments (top-right + bottom-right)
	var co := Color(cls_color.r, cls_color.g, cls_color.b, 0.35)
	draw_line(Vector2(W - 9, 0), Vector2(W, 0), co, 1.0)
	draw_line(Vector2(W - 1, 0), Vector2(W - 1, 9), co, 1.0)
	draw_line(Vector2(W - 9, H - 1), Vector2(W, H - 1), co, 1.0)
	draw_line(Vector2(W - 1, H - 9), Vector2(W - 1, H), co, 1.0)

	var x0 := 8.0

	# ── Row 1: class badge + stealth rating ──────────────────────────────────
	draw_rect(Rect2(x0, 6, 60, 18), Color(cls_color.r, cls_color.g, cls_color.b, 0.22), true)
	draw_rect(Rect2(x0, 6, 60, 18), Color(cls_color.r, cls_color.g, cls_color.b, 0.50), false, 1.0)
	draw_string(font, Vector2(x0 + 4, 19), cls.left(9),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, cls_color)

	var rating := GameManager.get_rating()
	var r_col: Color
	match rating:
		"PHANTOM THIEF": r_col = Color(0.45, 0.85, 1.00)
		"SHADOWBLADE":   r_col = Color(0.65, 0.50, 1.00)
		"SELLSWORD":     r_col = Color(1.00, 0.60, 0.20)
		_:               r_col = Color(1.00, 0.30, 0.30)
	draw_string(font, Vector2(x0 + 68, 19), rating,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(r_col.r, r_col.g, r_col.b, 0.90))

	draw_line(Vector2(x0, 28), Vector2(W - 4, 28), Color(1.0, 1.0, 1.0, 0.07), 1.0)

	# ── Row 2: wanted level ───────────────────────────────────────────────────
	var wl := GameManager.wanted_level
	var wl_col: Color = GameManager.get_wanted_color()
	var wl_name: String = GameManager.get_wanted_name()
	draw_string(font, Vector2(x0, 40), "WANTED:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.55, 0.52, 0.45, 0.65))
	var star_x := x0 + 52.0
	for i in range(5):
		var sc: Color = Color(wl_col.r, wl_col.g, wl_col.b, 0.90) if i < wl else Color(0.28, 0.26, 0.22, 0.50)
		draw_string(font, Vector2(star_x + i * 14.0, 40), "★",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, sc)
	if wl > 0:
		draw_string(font, Vector2(star_x + 74.0, 40), wl_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(wl_col.r, wl_col.g, wl_col.b, 0.85))

	draw_line(Vector2(x0, 44), Vector2(W - 4, 44), Color(1.0, 1.0, 1.0, 0.07), 1.0)

	# ── Row 3: floor pips ────────────────────────────────────────────────────
	var floor_now := GameManager.current_floor
	var floor_max := GameManager.MAX_FLOORS
	var pip_r  := 4.5
	var pip_gap := 4.0
	var pip_cy := 56.0
	for i in range(floor_max):
		var cx := x0 + pip_r + i * (pip_r * 2.0 + pip_gap)
		var filled := i < floor_now
		var pcol := Color(0.85, 0.72, 0.28, 0.95) if filled else Color(0.30, 0.28, 0.24, 0.55)
		draw_circle(Vector2(cx, pip_cy), pip_r, pcol)
		if filled:
			draw_arc(Vector2(cx, pip_cy), pip_r, 0.0, TAU, 14,
				Color(1.0, 0.92, 0.50, 0.45), 1.0)
	var lbl_x := x0 + floor_max * (pip_r * 2.0 + pip_gap) + 6.0
	draw_string(font, Vector2(lbl_x, pip_cy + 4.0), "Floor %d/%d" % [floor_now, floor_max],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.60, 0.48, 0.80))

	draw_line(Vector2(x0, 66), Vector2(W - 4, 66), Color(1.0, 1.0, 1.0, 0.07), 1.0)

	# ── Row 4: HP hearts ─────────────────────────────────────────────────────
	var hp     := GameManager.player_hp
	var max_hp := GameManager.player_max_hp
	var hsz    := 12.0
	var hgap   := 2.0
	var hy     := 74.0

	draw_string(font, Vector2(x0, hy + 9), "HP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.55, 0.52, 0.45, 0.65))

	var hx := x0 + 18.0
	for i in range(max_hp):
		_draw_heart(Vector2(hx + i * (hsz + hgap), hy), hsz, i < hp)

	draw_line(Vector2(x0, 92), Vector2(W - 4, 92), Color(1.0, 1.0, 1.0, 0.07), 1.0)

	# ── Row 5: loot indicator ─────────────────────────────────────────────────
	var has_loot: bool = get_meta("has_loot", false)
	if has_loot:
		draw_rect(Rect2(x0, 95, 72, 12), Color(0.90, 0.70, 0.10, 0.22), true)
		draw_string(font, Vector2(x0 + 4, 104), "✓  LOOT SECURED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.80, 0.15, 0.95))
	else:
		draw_string(font, Vector2(x0, 104), "LOOT:  ─ ─ ─",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.38, 0.36, 0.32, 0.50))

	# ── Row 6: combo meter (only when active) ────────────────────────────────
	if combo > 0:
		draw_line(Vector2(x0, 108), Vector2(W - 4, 108), Color(1.0, 1.0, 1.0, 0.07), 1.0)
		var tier := GameManager.combo_tier
		var tier_name: String
		var tier_col: Color
		match tier:
			3: tier_name = "GHOST";      tier_col = Color(0.40, 0.90, 1.00)
			2: tier_name = "RELENTLESS"; tier_col = Color(0.35, 0.95, 0.45)
			1: tier_name = "SHARP";      tier_col = Color(1.00, 0.80, 0.15)
			_: tier_name = "";           tier_col = Color(0.80, 0.75, 0.55)
		var combo_label := "x%d  COMBO" % combo if tier == 0 else "x%d  %s" % [combo, tier_name]
		draw_rect(Rect2(x0, 111, W - x0 - 4, 12), Color(tier_col.r, tier_col.g, tier_col.b, 0.12), true)
		draw_string(font, Vector2(x0 + 4, 120), combo_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(tier_col.r, tier_col.g, tier_col.b, 0.95))

func _draw_heart(pos: Vector2, size: float, filled: bool):
	var r := size * 0.28
	var col := Color(0.95, 0.20, 0.25) if filled else Color(0.32, 0.16, 0.18, 0.55)
	draw_circle(pos + Vector2(r, r * 0.8), r, col)
	draw_circle(pos + Vector2(size - r, r * 0.8), r, col)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0.0, r * 1.2),
		pos + Vector2(size, r * 1.2),
		pos + Vector2(size * 0.5, size),
	]), col)
	draw_rect(Rect2(pos.x, pos.y + r * 0.8, size, r * 0.6), col, true)
