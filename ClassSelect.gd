extends Control

const CLASS_ORDER := ["CUTPURSE", "SHADOWDANCER", "ASSASSIN"]
const ITEM_NAMES  := {0: "Gold Piece", 1: "Alch. Smoke", 2: "Sopor. Dart", 3: "Silk Rope"}
const MODIFIER_COLORS := {
	"NONE":          Color(0.50, 0.50, 0.50),
	"BONUS_CONTRACT":Color(0.95, 0.78, 0.15),
	"LUCKY_BREAK":   Color(0.30, 0.90, 0.40),
	"CURSED_DICE":   Color(0.70, 0.20, 0.80),
	"BLOOD_MONEY":   Color(0.90, 0.15, 0.15),
	"TIGHT_PATROLS": Color(0.90, 0.35, 0.20),
	"UNDER_THE_MOON":Color(0.40, 0.60, 1.00),
	"HIGH_ALERT":    Color(1.00, 0.20, 0.20),
	"THIN_WALLS":    Color(0.80, 0.55, 0.90),
}

var _modifier: Dictionary = {}
var _hovered         := -1
var _race_phase      := true   # phase 1: pick race
var _class_phase     := false  # phase 2: pick class
var _contract_phase  := false  # phase 3: pick contract
var _briefing_phase  := false  # phase 4: broker briefing
var _pending_race    := ""
var _pending_class   := ""

func _ready():
	anchor_right  = 1.0
	anchor_bottom = 1.0
	set_process_unhandled_input(true)
	GameManager.load_persistent()
	_modifier = GameManager.pick_modifier()
	queue_redraw()

func _input(event):
	if _contract_phase or _briefing_phase:
		return
	if event is InputEventMouseMotion:
		var prev := _hovered
		_hovered = _card_at(event.position)
		if _hovered != prev:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _hovered >= 0:
		if _race_phase:
			_select_race(_hovered)
		else:
			_select(_hovered)

func _unhandled_input(event):
	if _briefing_phase:
		var is_confirm := false
		if event is InputEventKey and event.pressed and not event.echo:
			is_confirm = event.keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]
		elif event is InputEventJoypadButton and event.pressed:
			is_confirm = event.is_action_pressed("menu_confirm") or event.is_action_pressed("menu_back")
		if is_confirm:
			AudioManager.ui_confirm()
			GameManager.restart()
		return
	if _contract_phase:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_1:              _pick_contract(0)
				KEY_2:              _pick_contract(1)
				KEY_3:              _pick_contract(2)
				KEY_ENTER, KEY_SPACE: _pick_contract(-1)
		elif event is InputEventJoypadButton and event.pressed:
			if event.is_action_pressed("menu_slot_1"):    _pick_contract(0)
			elif event.is_action_pressed("menu_slot_2"):  _pick_contract(1)
			elif event.is_action_pressed("menu_slot_3"):  _pick_contract(2)
			elif event.is_action_pressed("menu_confirm"): _pick_contract(-1)
		return
	if _race_phase:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_1: _select_race(0)
				KEY_2: _select_race(1)
				KEY_3: _select_race(2)
				KEY_4: _select_race(3)
		elif event is InputEventJoypadButton and event.pressed:
			if event.is_action_pressed("menu_slot_1"):   _select_race(0)
			elif event.is_action_pressed("menu_slot_2"): _select_race(1)
			elif event.is_action_pressed("menu_slot_3"): _select_race(2)
			elif event.is_action_pressed("menu_slot_4"): _select_race(3)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _select(0)
			KEY_2: _select(1)
			KEY_3: _select(2)
	elif event is InputEventJoypadButton and event.pressed:
		if event.is_action_pressed("menu_slot_1"):   _select(0)
		elif event.is_action_pressed("menu_slot_2"): _select(1)
		elif event.is_action_pressed("menu_slot_3"): _select(2)

func _card_at(mouse_pos: Vector2) -> int:
	var W := size.x
	if _race_phase:
		var card_w := 185.0
		var card_h := 275.0
		var gap    := 20.0
		var count  := GameManager.RACE_ORDER.size()
		var total  := count * card_w + (count - 1) * gap
		var cx0    := (W - total) * 0.5
		var cy     := 110.0
		for i in range(count):
			var cx: float = cx0 + i * (card_w + gap)
			if mouse_pos.x >= cx and mouse_pos.x < cx + card_w \
					and mouse_pos.y >= cy and mouse_pos.y < cy + card_h:
				return i
		return -1
	var card_w := 210.0
	var card_h := 275.0
	var gap    := 28.0
	var total  := 3 * card_w + 2 * gap
	var cx0    := (W - total) * 0.5
	var cy     := 110.0
	for i in range(3):
		var cx: float = cx0 + i * (card_w + gap)
		if mouse_pos.x >= cx and mouse_pos.x < cx + card_w \
				and mouse_pos.y >= cy and mouse_pos.y < cy + card_h:
			return i
	return -1

func _select_race(idx: int):
	if idx < 0 or idx >= GameManager.RACE_ORDER.size():
		return
	_pending_race = GameManager.RACE_ORDER[idx]
	GameManager.selected_race = _pending_race
	_race_phase  = false
	_class_phase = true
	_hovered     = -1
	AudioManager.ui_nav()
	queue_redraw()

func _select(idx: int):
	_pending_class  = CLASS_ORDER[idx]
	_class_phase    = false
	_contract_phase = true
	AudioManager.ui_nav()
	queue_redraw()

func _pick_contract(idx: int):
	GameManager.selected_race  = _pending_race
	GameManager.selected_class = _pending_class
	var contracts := GameManager.CHALLENGE_CONTRACTS
	if idx >= 0 and idx < contracts.size():
		var c: Dictionary = contracts[idx]
		GameManager.active_contract = c.id
		GameManager.contract_name   = c.name
		GameManager.contract_desc   = c.desc
		GameManager.contract_bonus  = c.bonus
	else:
		GameManager.active_contract = "NONE"
		GameManager.contract_name   = ""
		GameManager.contract_desc   = ""
		GameManager.contract_bonus  = 0
	AudioManager.ui_nav()
	_contract_phase = false
	_briefing_phase = true
	queue_redraw()

func _draw():
	var W := size.x
	var H := size.y
	var font := ThemeDB.fallback_font

	# ── Background ───────────────────────────────────────────────────────────
	draw_rect(Rect2(0, 0, W, H), Color(0.055, 0.040, 0.055))
	for i in range(0, int(H), 4):
		draw_line(Vector2(0, i), Vector2(W, i), Color(0, 0, 0, 0.12), 1.0)

	if _briefing_phase:
		_draw_briefing_screen(W, H, font)
		return

	if _contract_phase:
		_draw_contract_screen(W, H, font)
		return

	if _race_phase:
		_draw_race_screen(W, H, font)
		return

	# ── Title ─────────────────────────────────────────────────────────────────
	var title := "C O N T R A B A N D"
	draw_string(font, Vector2(W * 0.5 - 130, 58), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.95, 0.75, 0.18))
	var race_data: Dictionary = GameManager.RACES.get(_pending_race, {})
	var race_col: Color = race_data.get("color", Color(0.6, 0.6, 0.6))
	draw_string(font, Vector2(W * 0.5 - 118, 80),
		"Race: %s  —  Select Your Class" % race_data.get("title", _pending_race),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, race_col)
	draw_line(Vector2(W * 0.15, 92), Vector2(W * 0.85, 92), Color(0.3, 0.22, 0.1, 0.6), 1.0)

	# ── Class cards ───────────────────────────────────────────────────────────
	var card_w := 210.0
	var card_h := 275.0
	var gap    := 28.0
	var total  := 3 * card_w + 2 * gap
	var cx0    := (W - total) * 0.5
	var cy     := 110.0

	for i in range(3):
		var cid: String = CLASS_ORDER[i]
		var cd: Dictionary = GameManager.CLASSES[cid]
		var cx  := cx0 + i * (card_w + gap)
		var col: Color = cd.color

		var hov := (i == _hovered)
		# Card fill
		var fill := Color(0.16, 0.11, 0.19) if hov else Color(0.10, 0.07, 0.12)
		draw_rect(Rect2(cx, cy, card_w, card_h), fill)
		# Outer glow on hover
		if hov:
			draw_rect(Rect2(cx - 2, cy - 2, card_w + 4, card_h + 4),
				Color(col.r, col.g, col.b, 0.18), false, 3.0)
		# Border
		var border_a := 1.0 if hov else 0.70
		var border_w := 2.0 if hov else 1.5
		draw_rect(Rect2(cx, cy, card_w, card_h), Color(col.r, col.g, col.b, border_a), false, border_w)
		# Top accent bar
		draw_rect(Rect2(cx, cy, card_w, 4), Color(col.r, col.g, col.b, 0.85))

		# Key hint
		const CARD_BTNS := ["X", "Y", "B"]
		var cbtn: String = CARD_BTNS[i] if i < CARD_BTNS.size() else str(i + 1)
		draw_string(font, Vector2(cx + 8, cy + 22),
			"[%d / %s]" % [i + 1, cbtn], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.6))

		# Class title
		draw_string(font, Vector2(cx + 8, cy + 44),
			cd.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)

		# Divider
		draw_line(Vector2(cx + 8, cy + 52), Vector2(cx + card_w - 8, cy + 52),
			Color(col.r, col.g, col.b, 0.3), 1.0)

		# Items
		draw_string(font, Vector2(cx + 8, cy + 70),
			"STARTING ITEMS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.45, 0.45))
		var iy := cy + 86.0
		for item in cd.items:
			var iname: String = ITEM_NAMES.get(item.type, "?")
			draw_string(font, Vector2(cx + 14, iy),
				"× %d  %s" % [item.count, iname],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.80, 0.78, 0.72))
			iy += 16.0

		# Passive
		draw_string(font, Vector2(cx + 8, iy + 8),
			"PASSIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.45, 0.45))
		var passive: String = cd.passive
		draw_multiline_string(font, Vector2(cx + 14, iy + 24),
			passive, HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 20), 10, 3, Color(0.85, 0.85, 0.75))

		draw_string(font, Vector2(cx + 8, iy + 68),
			"ABILITY [Q / L3]", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.45, 0.45))
		draw_string(font, Vector2(cx + 14, iy + 82),
			_class_ability_name(cid), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(col.r * 0.9, col.g * 0.9, col.b * 0.9))
		draw_multiline_string(font, Vector2(cx + 14, iy + 94),
			_class_ability_desc(cid), HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 20), 9, 2,
			Color(0.75, 0.75, 0.70))

		# Flavor quote
		var quote_y := cy + card_h - 26.0
		draw_line(Vector2(cx + 8, quote_y - 8), Vector2(cx + card_w - 8, quote_y - 8),
			Color(col.r, col.g, col.b, 0.2), 1.0)
		draw_multiline_string(font, Vector2(cx + 10, quote_y + 4),
			"\"%s\"" % cd.flavor,
			HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 16), 9, 2, Color(col.r * 0.8, col.g * 0.8, col.b * 0.8, 0.8))

	# ── Run modifier ──────────────────────────────────────────────────────────
	var mod_y := cy + card_h + 32.0
	var mod_col: Color = MODIFIER_COLORS.get(_modifier.get("id", "NONE"), Color(0.5, 0.5, 0.5))
	var box_w := 380.0
	var box_x := (W - box_w) * 0.5
	draw_rect(Rect2(box_x, mod_y, box_w, 52), Color(0.08, 0.06, 0.10))
	draw_rect(Rect2(box_x, mod_y, box_w, 52), Color(mod_col.r, mod_col.g, mod_col.b, 0.6), false, 1.5)
	draw_string(font, Vector2(box_x + 12, mod_y + 18),
		"JOB CONDITION:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5))
	draw_string(font, Vector2(box_x + 12, mod_y + 34),
		"%s  —  %s" % [_modifier.get("name", ""), _modifier.get("desc", "")],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, mod_col)

	# ── Lifetime stats ────────────────────────────────────────────────────────
	var stats_y := mod_y + 68.0
	var st_col  := Color(0.42, 0.38, 0.30)
	draw_string(font, Vector2(W * 0.5 - 200, stats_y),
		"Runs: %d   Completed: %d   Lifetime Gold: %d gp   Best: %s" % [
			GameManager.runs_attempted, GameManager.runs_completed,
			GameManager.lifetime_gold,
			GameManager.best_rating if GameManager.best_rating != "" else "—"
		],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, st_col)

	# ── Guild reputation ──────────────────────────────────────────────────────
	var rep := GameManager.guild_rep
	var tier := GameManager.get_guild_tier()
	var rep_col: Color = tier.color
	draw_string(font, Vector2(W * 0.5 - 200, stats_y + 18),
		"%s  |  Rep: %d  |  Ghost Runs: %d  |  Takedowns: %d" % [
			tier.title, rep, GameManager.ghost_runs, GameManager.lifetime_takedowns],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, rep_col)
	var next_u := GameManager.get_next_guild_unlock()
	if not next_u.is_empty():
		draw_string(font, Vector2(W * 0.5 - 200 + 120, stats_y + 18),
			"  —  next unlock at %d: %s" % [next_u.rep, next_u.name],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.45, 0.28))
	# Show active unlocks
	var unlock_strs: Array[String] = []
	for u in GameManager.GUILD_UNLOCKS:
		if rep >= u.rep:
			unlock_strs.append(u.name)
	if not unlock_strs.is_empty():
		draw_string(font, Vector2(W * 0.5 - 200, stats_y + 34),
			"Guild perks: " + "  ·  ".join(unlock_strs),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.55, 0.35))

	# ── Hint ──────────────────────────────────────────────────────────────────
	draw_string(font, Vector2(W * 0.5 - 140, H - 18),
		"Press  [1/X]  [2/Y]  [3/B]  to begin",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.38, 0.34, 0.28))

func _draw_race_screen(W: float, H: float, font: Font):
	draw_string(font, Vector2(W * 0.5 - 130, 58), "C O N T R A B A N D",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.95, 0.75, 0.18))
	draw_string(font, Vector2(W * 0.5 - 118, 80), "Thieves' Guild  —  Choose Your Race",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.44, 0.28))
	draw_line(Vector2(W * 0.15, 92), Vector2(W * 0.85, 92), Color(0.3, 0.22, 0.1, 0.6), 1.0)

	var card_w := 185.0
	var card_h := 275.0
	var gap    := 20.0
	var count  := GameManager.RACE_ORDER.size()
	var total  := count * card_w + (count - 1) * gap
	var cx0    := (W - total) * 0.5
	var cy     := 110.0
	const R_BTNS := ["X", "Y", "B", "LB"]

	for i in range(count):
		var rid: String = GameManager.RACE_ORDER[i]
		var rd: Dictionary = GameManager.RACES[rid]
		var col: Color = rd.get("color", Color(0.6, 0.6, 0.6))
		var skin: Color = rd.get("skin", Color(0.82, 0.68, 0.52))
		var cx := cx0 + i * (card_w + gap)
		var hov := (i == _hovered)

		var fill := Color(0.16, 0.11, 0.19) if hov else Color(0.10, 0.07, 0.12)
		draw_rect(Rect2(cx, cy, card_w, card_h), fill)
		if hov:
			draw_rect(Rect2(cx - 2, cy - 2, card_w + 4, card_h + 4),
				Color(col.r, col.g, col.b, 0.18), false, 3.0)
		draw_rect(Rect2(cx, cy, card_w, card_h), Color(col.r, col.g, col.b, 0.75 if hov else 0.55), false, 2.0 if hov else 1.5)
		draw_rect(Rect2(cx, cy, card_w, 4), Color(col.r, col.g, col.b, 0.90))

		# Key hint
		var rbtn: String = R_BTNS[i] if i < R_BTNS.size() else str(i + 1)
		draw_string(font, Vector2(cx + 8, cy + 22),
			"[%d / %s]" % [i + 1, rbtn], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.6))

		# Race title
		draw_string(font, Vector2(cx + 8, cy + 44),
			rd.get("title", rid).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
		draw_line(Vector2(cx + 8, cy + 52), Vector2(cx + card_w - 8, cy + 52),
			Color(col.r, col.g, col.b, 0.3), 1.0)

		# Racial passive
		var iy := cy + 70.0
		draw_string(font, Vector2(cx + 8, iy), "PASSIVE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.45, 0.45))
		draw_multiline_string(font, Vector2(cx + 14, iy + 16),
			rd.get("passive", ""), HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 20), 10, 3,
			Color(0.85, 0.85, 0.75))

		# Racial ability
		var ay := iy + 72.0
		draw_string(font, Vector2(cx + 8, ay), "ABILITY [Q / L3]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.45, 0.45))
		draw_string(font, Vector2(cx + 14, ay + 16),
			rd.get("ability_name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(col.r * 0.9, col.g * 0.9, col.b * 0.9))
		draw_multiline_string(font, Vector2(cx + 14, ay + 30),
			rd.get("ability_desc", ""), HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 20), 9, 3,
			Color(0.75, 0.75, 0.70))

		# Skin swatch
		draw_circle(Vector2(cx + card_w - 18, cy + 22), 6.0, skin)
		draw_arc(Vector2(cx + card_w - 18, cy + 22), 6.0, 0, TAU, 16,
			Color(col.r, col.g, col.b, 0.60), 1.0)

		# Flavor quote
		var quote_y := cy + card_h - 26.0
		draw_line(Vector2(cx + 8, quote_y - 8), Vector2(cx + card_w - 8, quote_y - 8),
			Color(col.r, col.g, col.b, 0.2), 1.0)
		draw_multiline_string(font, Vector2(cx + 10, quote_y + 4),
			"\"%s\"" % rd.get("flavor", ""),
			HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 16), 9, 2,
			Color(col.r * 0.8, col.g * 0.8, col.b * 0.8, 0.8))

	draw_string(font, Vector2(W * 0.5 - 170, H - 18),
		"Press  [1/X]  [2/Y]  [3/B]  [4/LB]  to choose your lineage",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.38, 0.34, 0.28))

func _draw_contract_screen(W: float, H: float, font: Font):
	var cls_data: Dictionary = GameManager.CLASSES.get(_pending_class, {})
	var cls_col: Color = cls_data.get("color", Color(0.6, 0.6, 0.6))

	# Header
	draw_string(font, Vector2(W * 0.5 - 100, 56),
		"C O N T R A B A N D", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(0.95, 0.75, 0.18))
	var rdat: Dictionary = GameManager.RACES.get(_pending_race, {})
	draw_string(font, Vector2(W * 0.5 - 125, 80),
		"%s %s  —  Accept a contract?" % [rdat.get("title", ""), cls_data.get("title", _pending_class)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.55, 0.35))
	draw_line(Vector2(W * 0.15, 92), Vector2(W * 0.85, 92),
		Color(cls_col.r, cls_col.g, cls_col.b, 0.4), 1.0)

	var contracts := GameManager.CHALLENGE_CONTRACTS
	const C_BTNS := ["X", "Y", "B"]
	var card_w := 240.0
	var gap := 24.0
	var total := contracts.size() * card_w + (contracts.size() - 1) * gap
	var cx0 := (W - total) * 0.5
	var cy  := 120.0

	for i in range(contracts.size()):
		var c: Dictionary = contracts[i]
		var cx := cx0 + i * (card_w + gap)
		var btn: String = C_BTNS[i] if i < C_BTNS.size() else str(i + 1)
		draw_rect(Rect2(cx, cy, card_w, 160), Color(0.10, 0.07, 0.14))
		draw_rect(Rect2(cx, cy, card_w, 160), Color(1.0, 0.65, 0.15, 0.55), false, 1.5)
		draw_rect(Rect2(cx, cy, card_w, 4), Color(1.0, 0.65, 0.15, 0.85))
		draw_string(font, Vector2(cx + 8, cy + 22),
			"[%d / %s]" % [i + 1, btn], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.6, 0.6, 0.6))
		draw_string(font, Vector2(cx + 8, cy + 44),
			c.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(1.0, 0.65, 0.15))
		draw_line(Vector2(cx + 8, cy + 52), Vector2(cx + card_w - 8, cy + 52),
			Color(1.0, 0.65, 0.15, 0.25), 1.0)
		draw_multiline_string(font, Vector2(cx + 10, cy + 72),
			c.desc, HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 16), 10, 3,
			Color(0.85, 0.82, 0.72))
		draw_string(font, Vector2(cx + 8, cy + 130),
			"REWARD: +%d gp" % c.bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.95, 0.80, 0.10))

	# No contract option
	var skip_y := cy + 180.0
	draw_rect(Rect2(cx0, skip_y, total, 44), Color(0.08, 0.06, 0.10))
	draw_rect(Rect2(cx0, skip_y, total, 44), Color(0.45, 0.42, 0.38, 0.50), false, 1.0)
	draw_string(font, Vector2(W * 0.5 - 140, skip_y + 28),
		"[ENTER / A]  No Contract  —  Standard run, no terms",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.50, 0.48, 0.42))

	# Mission brief from quartermaster
	var brief_y := skip_y + 60.0
	var qm: String = GameManager.get("quartermaster_name") if GameManager.get("quartermaster_name") else "The Client"
	draw_string(font, Vector2(W * 0.5 - 180, brief_y),
		"%s says:" % qm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.45, 0.28))
	var brief: String = GameManager.get_mission_brief()
	draw_string(font, Vector2(W * 0.5 - 180, brief_y + 16),
		"\"%s\"" % brief, HORIZONTAL_ALIGNMENT_LEFT, int(W * 0.7), 11,
		Color(0.75, 0.65, 0.42, 0.90))

func _draw_briefing_screen(W: float, H: float, font: Font):
	var cls_data: Dictionary = GameManager.CLASSES.get(_pending_class, {})
	var cls_col: Color = cls_data.get("color", Color(0.85, 0.65, 0.15))
	var race_data: Dictionary = GameManager.RACES.get(_pending_race, {})
	var race_col: Color = race_data.get("color", Color(0.7, 0.7, 0.7))

	# Vignette overlay — dark edges
	draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.008, 0.018))
	for i in range(0, int(H), 4):
		draw_line(Vector2(0, i), Vector2(W, i), Color(0, 0, 0, 0.10), 1.0)

	# Central parchment panel
	var pw := minf(W * 0.72, 640.0)
	var ph := 360.0
	var px := (W - pw) * 0.5
	var py := (H - ph) * 0.5 - 20.0
	draw_rect(Rect2(px, py, pw, ph), Color(0.09, 0.065, 0.04, 0.97))
	draw_rect(Rect2(px, py, pw, ph), Color(0.65, 0.50, 0.20, 0.65), false, 2.0)
	draw_rect(Rect2(px + 6, py + 6, pw - 12, ph - 12),
		Color(0.65, 0.50, 0.20, 0.18), false, 1.0)
	# Top gold stripe
	draw_rect(Rect2(px, py, pw, 4), Color(0.65, 0.50, 0.20, 0.90))
	# Corner diamonds
	for cx2 in [px + 10, px + pw - 10]:
		for cy2 in [py + 10, py + ph - 10]:
			draw_circle(Vector2(cx2, cy2), 3.5, Color(0.65, 0.50, 0.20, 0.55))

	# "THE BROKER" header chip
	var chip_w := 180.0
	var chip_x := (W - chip_w) * 0.5
	draw_rect(Rect2(chip_x, py - 20.0, chip_w, 28),
		Color(0.06, 0.04, 0.02, 0.95))
	draw_rect(Rect2(chip_x, py - 20.0, chip_w, 28),
		Color(0.65, 0.50, 0.20, 0.70), false, 1.5)
	draw_string(font, Vector2(chip_x + 14, py - 2),
		"— BROKER TRANSMISSION —",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.50, 0.20, 0.90))

	# Character identity line
	var identity := "%s  %s" % [race_data.get("title", ""), cls_data.get("title", _pending_class)]
	draw_string(font, Vector2(px + 20, py + 32),
		identity.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, race_col)
	draw_line(Vector2(px + 20, py + 40), Vector2(px + pw - 20, py + 40),
		Color(0.65, 0.50, 0.20, 0.25), 1.0)

	# Contract line (if any)
	if GameManager.active_contract != "NONE":
		var contract_col := Color(1.0, 0.65, 0.15)
		draw_string(font, Vector2(px + 20, py + 56),
			"CONTRACT:  %s" % GameManager.contract_name.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, contract_col)

	# Broker briefing text — main body (multiline with word wrap)
	var briefing: String = GameManager.get_broker_briefing()
	var text_y := py + 76.0
	draw_multiline_string(font, Vector2(px + 22, text_y),
		briefing, HORIZONTAL_ALIGNMENT_LEFT, int(pw - 44), 12, -1,
		Color(0.88, 0.82, 0.68))

	# Signature block
	var sig_y := py + ph - 62.0
	draw_line(Vector2(px + 20, sig_y), Vector2(px + pw - 20, sig_y),
		Color(0.65, 0.50, 0.20, 0.22), 1.0)
	draw_string(font, Vector2(px + 22, sig_y + 18),
		"— The Broker", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.65, 0.50, 0.20, 0.75))
	draw_string(font, Vector2(px + 22, sig_y + 34),
		"Sealed. No return address.", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		Color(0.50, 0.44, 0.32, 0.55))

	# Floor target pip row
	var pip_y := py + ph + 18.0
	for f in range(3):
		var pip_x := W * 0.5 - 28.0 + f * 28.0
		var active := f < GameManager.current_floor
		draw_circle(Vector2(pip_x, pip_y), 5.0,
			cls_col if active else Color(0.25, 0.22, 0.18))
		draw_arc(Vector2(pip_x, pip_y), 5.0, 0, TAU, 16,
			Color(cls_col.r, cls_col.g, cls_col.b, 0.55), 1.0)

	# Continue hint
	draw_string(font, Vector2(W * 0.5 - 110, H - 18),
		"[ENTER / A]  Begin the job",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.40, 0.30))

func _class_ability_name(cid: String) -> String:
	match cid:
		"CUTPURSE":     return "Pickpocket"
		"SHADOWDANCER": return "Shadow Step"
		"ASSASSIN":     return "Mark Target"
	return ""

func _class_ability_desc(cid: String) -> String:
	match cid:
		"CUTPURSE":     return "Steal gold from an unaware guard."
		"SHADOWDANCER": return "Teleport up to 5 tiles in facing dir."
		"ASSASSIN":     return "Mark a guard for auto-execution."
	return ""
