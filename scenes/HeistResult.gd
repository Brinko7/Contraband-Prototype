extends Node2D
# Post-heist scoring screen — shows rating, rep gain, heat change, and narrative sign-off.
# Reads final run state from GameManager + MetaProgress.

signal continue_to_guild

const COL_BG      := Color(0.06, 0.05, 0.08)
const COL_PANEL   := Color(0.10, 0.09, 0.13)
const COL_GOLD    := Color(0.95, 0.78, 0.15)
const COL_SILVER  := Color(0.75, 0.75, 0.80)
const COL_RED     := Color(0.90, 0.25, 0.20)
const COL_GREEN   := Color(0.35, 0.88, 0.55)
const COL_SHADOW  := Color(0.55, 0.30, 0.95)
const COL_WHITE   := Color(0.95, 0.92, 0.88)
const COL_DIM     := Color(0.40, 0.38, 0.45)

var _screen_w: float
var _screen_h: float

# Cached result data built once in _ready
var _result: Dictionary = {}
var _score_lines: Array[Dictionary] = []
var _total_score: int = 0

# Animation
var _reveal_timer := 0.0
var _reveal_phase := 0   # 0=header, 1=score lines, 2=story, 3=button
var _phase_delay  := 0.0
var _line_alpha: Array[float] = []
var _story_alpha  := 0.0
var _btn_alpha    := 0.0
var _btn_hover    := false
var _btn_rect     := Rect2()

# Screen shake on reveal
var _shake_offset := Vector2.ZERO
var _shake_timer  := 0.0

func _ready() -> void:
	_screen_w = get_viewport_rect().size.x
	_screen_h = get_viewport_rect().size.y
	_build_result()
	queue_redraw()

func _build_result() -> void:
	var success: bool  = GameManager.state == GameManager.State.ESCAPED
	var gold: int      = GameManager.gold_collected - GameManager.gold_spent
	var alerts: int    = GameManager.times_alerted
	var takedowns: int = GameManager.takedowns
	var floors: int    = GameManager.current_floor - 1
	var ghost: bool    = alerts == 0
	var run_t: float   = GameManager.run_time
	var contract_id: String = GameManager.active_contract

	var contract_bonus: int = 0
	if success and GameManager.check_contract_complete():
		contract_bonus = GameManager.contract_bonus

	var score: int = MetaProgress.calculate_score(
		gold, run_t, alerts, takedowns, floors, ghost, contract_bonus)

	var rating: Dictionary = MetaProgress.calculate_rating(score)
	var run_data: Dictionary = MetaProgress.record_run_complete(
		score, gold, takedowns, alerts, ghost, floors)

	_total_score = score

	_score_lines.clear()
	_score_lines.append({"label": "Gold collected",   "value": "+ %d gp" % GameManager.gold_collected, "color": COL_GOLD})
	_score_lines.append({"label": "Gold spent",       "value": "- %d gp" % GameManager.gold_spent,    "color": COL_DIM})
	_score_lines.append({"label": "Net haul",         "value": "%d gp"   % gold,                      "color": COL_GOLD})
	_score_lines.append({"label": "",                 "value": "",                                     "color": COL_DIM})
	if run_t < 180.0:
		var spd: int = int((180.0 - run_t) * 1.5)
		_score_lines.append({"label": "Speed bonus",  "value": "+ %d" % spd,                          "color": COL_GREEN})
	if ghost:
		_score_lines.append({"label": "Ghost run!",   "value": "+ 500",                               "color": COL_SHADOW})
	if alerts > 0:
		_score_lines.append({"label": "Alert penalty","value": "- %d" % (alerts * 80),               "color": COL_RED})
	if takedowns > 0:
		_score_lines.append({"label": "Takedowns",    "value": "+ %d" % (takedowns * 15),            "color": COL_SILVER})
	_score_lines.append({"label": "Floor depth",      "value": "+ %d" % (floors * 100),              "color": COL_SILVER})
	if contract_bonus > 0:
		_score_lines.append({"label": GameManager.contract_name, "value": "+ %d" % contract_bonus,   "color": COL_GOLD})
	_score_lines.append({"label": "",                 "value": "",                                    "color": COL_DIM})
	_score_lines.append({"label": "FINAL SCORE",      "value": str(score),                           "color": rating.get("color", COL_WHITE)})

	var heat_change: int   = run_data.get("heat_gained", 0)
	var rep_gained: int    = run_data.get("rep_gained", 0)
	var new_heat: int      = MetaProgress.city_heat
	var heat_data: Dictionary = MetaProgress.get_heat_data()

	# Pull narrative context from GameManager (written by RunNarrative on floor start)
	var target_name:  String = str(GameManager.get("run_target_name")  if GameManager.get("run_target_name")  != null else "")
	var macguffin:    String = str(GameManager.get("run_macguffin")     if GameManager.get("run_macguffin")    != null else "")
	# Floor stealth rating from EvidenceSystem (if available)
	var stealth_rating: String = ""
	var stealth_color: Color   = COL_DIM
	var es = get_tree().get_first_node_in_group("evidence_system")
	if es and es.has_method("get_end_of_floor_rating"):
		var er: Dictionary = es.get_end_of_floor_rating()
		stealth_rating = er.get("rating", "")
		stealth_color  = er.get("color",  COL_DIM)
		# Include evidence bonus GP in score lines
		var bonus_gp: int = er.get("bonus_gp", 0)
		if bonus_gp > 0:
			_score_lines.append({"label": "Evidence bonus (%s)" % stealth_rating,
				"value": "+ %d gp" % bonus_gp, "color": stealth_color})

	_result = {
		"success":        success,
		"rating":         rating,
		"score":          score,
		"rep_gained":     rep_gained,
		"heat_change":    heat_change,
		"new_heat":       new_heat,
		"heat_name":      heat_data.get("name", "Unknown"),
		"heat_color":     heat_data.get("color", COL_DIM),
		"story":          GameManager.get_story_sign_off(),
		"floors":         floors,
		"ghost":          ghost,
		"target_name":    target_name,
		"macguffin":      macguffin,
		"stealth_rating": stealth_rating,
		"stealth_color":  stealth_color,
	}

	for _i in _score_lines.size():
		_line_alpha.append(0.0)

func _process(delta: float) -> void:
	_reveal_timer += delta
	_phase_delay  -= delta

	if _phase_delay > 0.0:
		return

	match _reveal_phase:
		0:  # header fades in
			if _reveal_timer > 0.3:
				_reveal_phase = 1
				_phase_delay  = 0.1
		1:  # score lines reveal one by one
			var all_shown := true
			for i in _line_alpha.size():
				if _line_alpha[i] < 1.0:
					_line_alpha[i] = minf(_line_alpha[i] + delta * 3.0, 1.0)
					if i == _line_alpha.size() - 1 and _line_alpha[i] >= 1.0:
						_reveal_phase = 2
						_phase_delay  = 0.4
						_trigger_shake(3.0, 0.4)
					all_shown = false
					break
			if all_shown and _reveal_phase == 1:
				_reveal_phase = 2
				_phase_delay  = 0.3
		2:  # story text fades in
			_story_alpha = minf(_story_alpha + delta * 1.5, 1.0)
			if _story_alpha >= 1.0:
				_reveal_phase = 3
				_phase_delay  = 0.2
		3:  # button fades in
			_btn_alpha = minf(_btn_alpha + delta * 2.0, 1.0)

	if _shake_timer > 0.0:
		_shake_timer -= delta
		_shake_offset = Vector2(randf_range(-3, 3), randf_range(-3, 3)) * (_shake_timer / 0.4)
		if _shake_timer <= 0.0:
			_shake_offset = Vector2.ZERO

	queue_redraw()

func _trigger_shake(mag: float, dur: float) -> void:
	_shake_timer = dur
	_shake_offset = Vector2(randf_range(-mag, mag), randf_range(-mag, mag))

func _draw() -> void:
	var ox: float = _shake_offset.x
	var oy: float = _shake_offset.y

	# Background
	draw_rect(Rect2(0, 0, _screen_w, _screen_h), COL_BG)

	var cx: float = _screen_w * 0.5 + ox
	var cy: float = _screen_h * 0.5 + oy

	var success: bool = _result.get("success", false)
	var rating: Dictionary = _result.get("rating", {})
	var rating_color: Color = rating.get("color", COL_WHITE)

	# ── Header ────────────────────────────────────────────────────────────────
	var header_alpha := clampf((_reveal_timer - 0.3) * 3.0, 0.0, 1.0) if _reveal_timer > 0.3 else 0.0

	# Large outcome label
	var floors_done: int = _result.get("floors", 0)
	var citadel_run: bool = success and floors_done >= 6
	var outcome_text: String
	if citadel_run:
		outcome_text = "THE CITADEL FALLS"
	elif success:
		outcome_text = "HEIST COMPLETE"
	else:
		outcome_text = "CAUGHT"
	var outcome_color: Color = (rating_color if success else COL_RED).lerp(Color(1,1,1,0), 1.0 - header_alpha)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 200, cy - 200 + oy),
		outcome_text, HORIZONTAL_ALIGNMENT_CENTER, 400,
		32 if citadel_run else 28, Color(outcome_color.r, outcome_color.g, outcome_color.b, header_alpha))
	if citadel_run and header_alpha > 0.5:
		draw_string(ThemeDB.fallback_font, Vector2(cx - 160, cy - 163 + oy),
			"A L L  S I X  F L O O R S  C L E A R E D", HORIZONTAL_ALIGNMENT_CENTER, 320,
			9, Color(1.0, 0.90, 0.20, minf((header_alpha - 0.5) * 2.0, 1.0) * 0.70))

	# Rating title
	var rating_text: String = rating.get("name", "Rogue")
	draw_string(ThemeDB.fallback_font, Vector2(cx - 150, cy - 162 + oy),
		rating_text, HORIZONTAL_ALIGNMENT_CENTER, 300,
		18, Color(rating_color.r, rating_color.g, rating_color.b, header_alpha * 0.85))

	# Separator
	draw_line(Vector2(cx - 180, cy - 145 + oy), Vector2(cx + 180, cy - 145 + oy),
		Color(rating_color.r, rating_color.g, rating_color.b, header_alpha * 0.4), 1.0)

	# ── Narrative subtitle (target + macguffin) ──────────────────────────────
	var target_name:  String = _result.get("target_name", "")
	var macguffin:    String = _result.get("macguffin", "")
	var stealth_rtg:  String = _result.get("stealth_rating", "")
	var stealth_col:  Color  = _result.get("stealth_color", COL_DIM)
	if not target_name.is_empty() and header_alpha > 0.3:
		var sub_alpha: float = clampf((header_alpha - 0.3) * 2.0, 0.0, 1.0)
		var narrative_y := cy - 140.0 + oy
		if not success:
			narrative_y = cy - 155.0 + oy
		var mark_text := "MARK: %s" % target_name.to_upper()
		draw_string(ThemeDB.fallback_font, Vector2(cx - 160, narrative_y),
			mark_text, HORIZONTAL_ALIGNMENT_LEFT, 320, 10,
			Color(COL_SILVER.r, COL_SILVER.g, COL_SILVER.b, sub_alpha * 0.65))
		if not macguffin.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(cx + 160, narrative_y),
				macguffin.to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, 200, 10,
				Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, sub_alpha * 0.65))
	if not stealth_rtg.is_empty() and header_alpha > 0.5:
		var sr_alpha: float = clampf((header_alpha - 0.5) * 3.0, 0.0, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(cx - 160, cy - 148.0 + oy),
			"EVIDENCE RATING:", HORIZONTAL_ALIGNMENT_LEFT, 160, 9,
			Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, sr_alpha * 0.70))
		draw_string(ThemeDB.fallback_font, Vector2(cx + 160, cy - 148.0 + oy),
			stealth_rtg, HORIZONTAL_ALIGNMENT_RIGHT, 80, 10,
			Color(stealth_col.r, stealth_col.g, stealth_col.b, sr_alpha * 0.90))

	# ── Score lines ───────────────────────────────────────────────────────────
	var line_y := cy - 128.0 + oy
	for i in _score_lines.size():
		if i >= _line_alpha.size():
			break
		var alpha: float = _line_alpha[i]
		if alpha <= 0.0:
			continue
		var ln: Dictionary = _score_lines[i]
		var label: String = ln.get("label", "")
		var value: String = ln.get("value", "")
		var col: Color    = ln.get("color", COL_DIM)
		if label.is_empty() and value.is_empty():
			line_y += 8.0
			continue
		var is_total: bool = label == "FINAL SCORE"
		var font_size: int = 15 if is_total else 13
		draw_string(ThemeDB.fallback_font, Vector2(cx - 160, line_y),
			label, HORIZONTAL_ALIGNMENT_LEFT, 200, font_size,
			Color(col.r, col.g, col.b, alpha * (0.9 if is_total else 0.75)))
		draw_string(ThemeDB.fallback_font, Vector2(cx + 160, line_y),
			value, HORIZONTAL_ALIGNMENT_RIGHT, 160, font_size,
			Color(col.r, col.g, col.b, alpha))
		line_y += (22.0 if is_total else 18.0)

	# ── Meta stats row (rep + heat) ───────────────────────────────────────────
	if _story_alpha > 0.0:
		var meta_y := line_y + 16.0
		var rep_gained: int    = _result.get("rep_gained", 0)
		var heat_change: int   = _result.get("heat_change", 0)
		var heat_name: String  = _result.get("heat_name", "Unknown")
		var heat_color: Color  = _result.get("heat_color", COL_DIM)
		var rep_text := "Guild Rep  + %d  →  %d" % [rep_gained, MetaProgress.guild_rep]
		draw_string(ThemeDB.fallback_font, Vector2(cx - 160, meta_y),
			rep_text, HORIZONTAL_ALIGNMENT_LEFT, 320, 13,
			Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, _story_alpha * 0.85))
		var heat_text := "City Heat  %s  (%s)" % [
			("+" + str(heat_change)) if heat_change > 0 else ("=" if heat_change == 0 else str(heat_change)),
			heat_name]
		draw_string(ThemeDB.fallback_font, Vector2(cx - 160, meta_y + 18),
			heat_text, HORIZONTAL_ALIGNMENT_LEFT, 320, 13,
			Color(heat_color.r, heat_color.g, heat_color.b, _story_alpha * 0.85))

	# ── Story sign-off ────────────────────────────────────────────────────────
	if _story_alpha > 0.0:
		var story: String = _result.get("story", "")
		if not story.is_empty():
			var story_y := cy + 95 + oy
			draw_line(Vector2(cx - 180, story_y - 12), Vector2(cx + 180, story_y - 12),
				Color(COL_SILVER.r, COL_SILVER.g, COL_SILVER.b, _story_alpha * 0.25), 1.0)
			_draw_wrapped_text(story, cx - 170, story_y, 340, 12,
				Color(COL_SILVER.r, COL_SILVER.g, COL_SILVER.b, _story_alpha * 0.70))

	# ── Continue button ───────────────────────────────────────────────────────
	if _btn_alpha > 0.0:
		var bw: float = 220.0
		var bh: float = 36.0
		var bx: float = cx - bw * 0.5
		var by: float = cy + 175 + oy
		_btn_rect = Rect2(bx, by, bw, bh)
		var btn_bg := COL_PANEL.lerp(rating_color, 0.25 if _btn_hover else 0.12)
		draw_rect(_btn_rect, Color(btn_bg.r, btn_bg.g, btn_bg.b, _btn_alpha))
		draw_rect(_btn_rect, Color(rating_color.r, rating_color.g, rating_color.b, _btn_alpha * 0.5), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(cx, by + 23),
			"Return to Guild", HORIZONTAL_ALIGNMENT_CENTER, 0, 14,
			Color(COL_WHITE.r, COL_WHITE.g, COL_WHITE.b, _btn_alpha))

func _draw_wrapped_text(text: String, x: float, y: float,
		max_w: float, font_size: int, color: Color) -> void:
	var words := text.split(" ")
	var current_line := ""
	var dy := y
	var line_h := float(font_size) + 4.0
	for word in words:
		var test_line := (current_line + " " + word).strip_edges()
		var test_w := ThemeDB.fallback_font.get_string_size(test_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if test_w > max_w and current_line != "":
			draw_string(ThemeDB.fallback_font, Vector2(x, dy),
				current_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			dy += line_h
			current_line = word
		else:
			current_line = test_line
	if current_line != "":
		draw_string(ThemeDB.fallback_font, Vector2(x, dy),
			current_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_btn_hover = _btn_alpha >= 1.0 and _btn_rect.has_point(event.position)
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _btn_hover and _btn_alpha >= 1.0:
				_go_to_guild()
	elif event is InputEventKey:
		if event.pressed and _btn_alpha >= 1.0:
			if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]:
				_go_to_guild()

func _go_to_guild() -> void:
	GameManager.go_to_guild_hq()
