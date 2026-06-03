extends Control

# Center-top threat bar: wanted stars + injury tags + heat timer
# Only draws when there is something to show.

func _draw():
	var wl    := GameManager.wanted_level
	var heat  := GameManager.floor_heat_level
	var t     := float(get_meta("hud_t", 0.0))
	var player = get_meta("player", null)

	var bl := false
	var lm := false
	if player:
		bl = player.get("is_bleeding") == true
		lm = player.get("is_limping")  == true

	var has_threat := wl > 0 or heat > 0 or bl or lm
	if not has_threat:
		return

	var font := ThemeDB.fallback_font
	var fs   := 10

	var pulse := sin(t * 3.0) * 0.5 + 0.5

	var parts: Array[String] = []
	var col := Color(0.85, 0.85, 0.75)

	if wl > 0:
		var wname := GameManager.get_wanted_name()
		var stars := "★".repeat(wl) + "☆".repeat(5 - wl)
		parts.append("%s  %s" % [wname, stars])
		col = GameManager.get_wanted_color()

	if bl:
		parts.append("[BLEEDING]")
	if lm:
		parts.append("[LIMPING]")

	if heat > 0:
		var secs_left: int = 60 - int(GameManager.floor_heat_accum)
		parts.append("HEAT+%d (%ds)" % [heat, secs_left])

	var text := "  ·  ".join(parts)

	# Measure text to center the background pill
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad_x := 10.0
	var pad_y := 4.0
	var pill_w := text_w + pad_x * 2
	var pill_h := fs + pad_y * 2
	# Centre within viewport regardless of control size
	var vp_w := get_viewport_rect().size.x
	var ox := vp_w * 0.5 - pill_w * 0.5 - get_global_rect().position.x
	var oy := 0.0

	# Pill background
	var bg_alpha := 0.70 + pulse * 0.12 if wl > 0 else 0.65
	draw_rect(Rect2(ox, oy, pill_w, pill_h), Color(0.07, 0.05, 0.10, bg_alpha), true)
	draw_rect(Rect2(ox, oy, pill_w, pill_h), Color(col.r, col.g, col.b, 0.50 + pulse * 0.25), false, 1.0)

	# Text
	draw_string(font, Vector2(ox + pad_x, oy + pad_y + fs - 2),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(col.r, col.g, col.b, 0.90 + pulse * 0.10))
