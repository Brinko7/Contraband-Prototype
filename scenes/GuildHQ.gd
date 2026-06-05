extends Node2D
# Guild Headquarters — the persistent meta hub between runs.
# Accessible after completing or failing a run.
# Shows: rep/tier, lifetime stats, heat, unlocks, quartermaster, run start.

signal start_run_requested(selected_class: String, selected_race: String, contract: String)
signal back_to_menu_requested

const QUARTERMASTER_NAMES := [
	"Tomas Halfwhistle", "Brynn Copperlock", "Sable Nightvane",
	"Orrin Dustmantle", "Vex the Fence", "Mirela Coinshadow",
]

const QM_GREETINGS := {
	"fresh": [
		"New face. Good. The guild needs new faces — the old ones are mostly in prisons.",
		"The Broker sent you? Must be desperate. Good. Desperate thieves pay attention.",
		"You look like trouble. That's a compliment here.",
	],
	"returning": [
		"Back again. Still alive, I see. The odds weren't in your favor.",
		"Thought I'd seen the last of you. I'm glad I was wrong.",
		"Every job you walk back from makes the next one harder to explain away. Good.",
	],
	"high_rep": [
		"The guild speaks your name quietly. That's the highest compliment we give.",
		"Reputation like yours opens certain doors. Careful they don't open the wrong ones.",
		"They're starting to put your description in the Watch briefings. You should be proud.",
	],
	"heat_warning": [
		"The city watch has a description. Not a name yet — but close. Mind the patrols.",
		"Word travels. The guards on the next job will be ready for someone like you.",
		"Your last job left... echoes. The next mark will have better locks.",
	],
}

const CONTRACT_DESCRIPTIONS := {
	"PHANTOM_PROTOCOL": {
		"name":   "Phantom Protocol",
		"desc":   "Trigger zero alerts across all floors. The guild wants to know you can vanish.",
		"bonus":  600,
		"color":  Color(0.85, 0.85, 1.00),
		"icon":   "ghost",
	},
	"HIRED_BLADE": {
		"name":   "Hired Blade",
		"desc":   "Take down 6 or more guards. The guild has a point to make.",
		"bonus":  500,
		"color":  Color(0.90, 0.30, 0.20),
		"icon":   "sword",
	},
	"SPEED_DEMON": {
		"name":   "Speed Demon",
		"desc":   "Escape all floors in under 4 minutes. In and out like a shadow.",
		"bonus":  700,
		"color":  Color(0.95, 0.80, 0.20),
		"icon":   "hourglass",
	},
	"CLEAN_HANDS": {
		"name":   "Clean Hands",
		"desc":   "Escape without a single takedown. The guild wants a ghost, not a butcher.",
		"bonus":  750,
		"color":  Color(0.60, 0.90, 0.70),
		"icon":   "dove",
	},
	"THE_COLLECTOR": {
		"name":   "The Collector",
		"desc":   "Loot every item on the floor. Leave nothing behind.",
		"bonus":  550,
		"color":  Color(0.85, 0.65, 0.95),
		"icon":   "gem",
	},
	"IRON_RUN": {
		"name":   "Iron Run",
		"desc":   "Complete the job without buying anything from the between-floor shop.",
		"bonus":  650,
		"color":  Color(0.75, 0.55, 0.30),
		"icon":   "shield",
	},
	"NONE": {
		"name":   "Standard Job",
		"desc":   "No special conditions. Just get the mark.",
		"bonus":  0,
		"color":  Color(0.65, 0.65, 0.65),
		"icon":   "scroll",
	},
}

# State
var _selected_class:    String = "CUTPURSE"
var _selected_race:     String = "HALFLING"
var _selected_contract: String = "NONE"
var _qm_name:           String = ""
var _qm_line:           String = ""
var _t:                 float  = 0.0
var _panel_scroll:      float  = 0.0
var _tab:               int    = 0   # 0=roster, 1=stats, 2=unlocks, 3=contract

var _class_order: Array = []
var _race_order:  Array = []
var _mp:          Node  = null
var _cd:          Node  = null

# Notification banner state
var _notif_text:  String = ""
var _notif_color: Color  = Color.WHITE
var _notif_timer: float  = 0.0

func _ready() -> void:
	_mp = get_node("/root/MetaProgress")
	_cd = get_node("/root/ClassDatabase")
	_race_order = _cd.RACE_ORDER
	_qm_name = QUARTERMASTER_NAMES[randi() % QUARTERMASTER_NAMES.size()]
	_qm_line = _get_qm_greeting()
	_selected_class = GameManager.selected_class
	_selected_race  = GameManager.selected_race
	_selected_contract = "NONE"
	_build_class_order()
	_mp.tier_reached.connect(_on_tier_reached)
	_mp.unlock_gained.connect(_on_unlock_gained)
	queue_redraw()

func _on_tier_reached(tier_data: Dictionary) -> void:
	_notif_text  = "TIER REACHED: %s" % tier_data.get("title", "")
	_notif_color = tier_data.get("color", Color.WHITE)
	_notif_timer = 4.0
	AudioManager.ui_confirm()

func _on_unlock_gained(unlock_data: Dictionary) -> void:
	_notif_text  = "UNLOCKED: %s — %s" % [unlock_data.get("name",""), unlock_data.get("desc","")]
	_notif_color = Color(0.95, 0.80, 0.40)
	_notif_timer = 5.0
	AudioManager.ability_use()

func _build_class_order() -> void:
	_class_order = ["CUTPURSE","SHADOWDANCER","ASSASSIN"]
	if _mp.has_unlock("SELLSWORD") and not "SELLSWORD" in _class_order:
		_class_order.append("SELLSWORD")

func _get_qm_greeting() -> String:
	var pool: Array
	if _mp.guild_rep >= 60:
		pool = QM_GREETINGS["high_rep"]
	elif _mp.city_heat >= 3:
		pool = QM_GREETINGS["heat_warning"]
	elif _mp.runs_completed > 0:
		pool = QM_GREETINGS["returning"]
	else:
		pool = QM_GREETINGS["fresh"]
	return pool[randi() % pool.size()]

func _process(delta: float) -> void:
	_t += delta
	if _notif_timer > 0.0:
		_notif_timer -= delta
	queue_redraw()

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	_draw_background(vp)
	_draw_header(vp)
	_draw_tabs(vp)
	match _tab:
		0: _draw_roster_tab(vp)
		1: _draw_stats_tab(vp)
		2: _draw_unlocks_tab(vp)
		3: _draw_contract_tab(vp)
	_draw_quartermaster(vp)
	_draw_start_button(vp)
	_draw_notification(vp)

# Background
func _draw_background(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.05, 0.10))
	for tx in range(0, int(vp.x / 32) + 1):
		for ty in range(0, int(vp.y / 32) + 1):
			var cx: float = tx * 32.0
			var cy: float = ty * 32.0
			if (tx + ty) % 2 == 0:
				draw_rect(Rect2(cx, cy, 32, 32), Color(0.07, 0.06, 0.11))
	_draw_vignette_torch(vp, Vector2(60, 60))
	_draw_vignette_torch(vp, Vector2(vp.x - 60, 60))
	draw_rect(Rect2(0, 0, vp.x, 8),              Color(0, 0, 0, 0.6))
	draw_rect(Rect2(0, vp.y - 8, vp.x, 8),      Color(0, 0, 0, 0.6))
	draw_rect(Rect2(0, 0, 8, vp.y),              Color(0, 0, 0, 0.6))
	draw_rect(Rect2(vp.x - 8, 0, 8, vp.y),      Color(0, 0, 0, 0.6))

func _draw_vignette_torch(vp: Vector2, center: Vector2) -> void:
	var flicker: float = 0.12 + sin(_t * 7.1 + center.x * 0.05) * 0.06
	for r in [80.0, 55.0, 35.0, 18.0]:
		var a: float = flicker * (1.0 - r / 85.0) * 0.6
		draw_circle(center, r, Color(1.0, 0.72, 0.25, a))

# Header
func _draw_header(vp: Vector2) -> void:
	draw_rect(Rect2(0, 0, vp.x, 52), Color(0.10, 0.08, 0.14))
	draw_line(Vector2(0, 52), Vector2(vp.x, 52), Color(0.45, 0.30, 0.65, 0.80), 1.5)
	_draw_text_centered("THE SHADOW GUILD", Vector2(vp.x * 0.5, 18), 22, Color(0.95, 0.80, 0.40))
	_draw_text_centered("Headquarters", Vector2(vp.x * 0.5, 38), 11, Color(0.60, 0.55, 0.70))
	var tier: Dictionary = _mp.get_guild_tier()
	var rep_str: String = "REP: %d" % _mp.guild_rep
	_draw_text(rep_str, Vector2(vp.x - 160, 14), 10, Color(0.70, 0.65, 0.80))
	_draw_text(tier.get("title", "Street Rat"), Vector2(vp.x - 160, 28), 13,
		tier.get("color", Color(0.55, 0.55, 0.55)))
	var prog: float  = _mp.get_tier_progress()
	var bar_x: float = vp.x - 160
	draw_rect(Rect2(bar_x, 43, 145, 5), Color(0.18, 0.15, 0.25))
	draw_rect(Rect2(bar_x, 43, 145.0 * prog, 5), tier.get("color", Color(0.45, 0.45, 0.60)))
	var heat: Dictionary = _mp.get_heat_data()
	_draw_text("HEAT:", Vector2(12, 14), 10, Color(0.60, 0.55, 0.70))
	_draw_text(heat.get("name","Unknown"), Vector2(12, 28), 13, heat.get("color", Color(0.55,0.55,0.55)))
	for i in range(5):
		var filled: bool = i < _mp.city_heat
		var hc: Color = heat.get("color",Color(0.55,0.55,0.55)) if filled else Color(0.25,0.22,0.30)
		draw_rect(Rect2(12 + i * 16, 43, 13, 5), hc)

# Tabs
func _draw_tabs(vp: Vector2) -> void:
	var tab_labels := ["ROSTER","STATS","UNLOCKS","CONTRACT"]
	var tab_w: float = vp.x / tab_labels.size()
	for i in range(tab_labels.size()):
		var tx: float = i * tab_w
		var is_active: bool = _tab == i
		draw_rect(Rect2(tx, 52, tab_w - 1, 26),
			Color(0.12, 0.10, 0.18) if is_active else Color(0.08, 0.07, 0.12))
		var col: Color = Color(0.95, 0.85, 0.55) if is_active else Color(0.55, 0.50, 0.65)
		_draw_text_centered(tab_labels[i], Vector2(tx + tab_w * 0.5, 62), 10, col)
		if is_active:
			draw_line(Vector2(tx, 78), Vector2(tx + tab_w, 78), Color(0.65, 0.45, 0.90, 0.90), 2.0)

# Roster tab (class + race selection)
func _draw_roster_tab(vp: Vector2) -> void:
	var cx: float = 24.0
	var cy: float = 92.0
	_draw_text("SELECT CLASS", Vector2(cx, cy), 11, Color(0.65, 0.55, 0.80))
	cy += 18.0
	for class_id in _class_order:
		var cdata: Dictionary = _cd.get_class_data(class_id)
		var is_sel: bool = _selected_class == class_id
		var bg: Color = Color(0.20, 0.14, 0.28) if is_sel else Color(0.10, 0.08, 0.15)
		draw_rect(Rect2(cx, cy, vp.x * 0.42, 42), bg)
		if is_sel:
			draw_rect(Rect2(cx, cy, 3, 42), cdata.get("color", Color(0.85,0.65,0.20)))
		_draw_text(cdata.get("title", class_id), Vector2(cx + 10, cy + 8), 14,
			cdata.get("color", Color(0.85, 0.65, 0.20)) if is_sel else Color(0.75,0.72,0.80))
		_draw_text(cdata.get("passive", ""), Vector2(cx + 10, cy + 26), 9,
			Color(0.55, 0.50, 0.65), true, int(vp.x * 0.40 - 14))
		cy += 50.0

	var rx: float = vp.x * 0.48
	cy = 92.0
	_draw_text("SELECT RACE", Vector2(rx, cy), 11, Color(0.65, 0.55, 0.80))
	cy += 18.0
	for race_id in _race_order:
		var rdata: Dictionary = _cd.get_race(race_id)
		var is_sel: bool = _selected_race == race_id
		var bg: Color = Color(0.14, 0.20, 0.28) if is_sel else Color(0.10, 0.08, 0.15)
		draw_rect(Rect2(rx, cy, vp.x * 0.48, 42), bg)
		if is_sel:
			draw_rect(Rect2(rx, cy, 3, 42), rdata.get("color", Color(0.55,0.75,0.85)))
		_draw_text(rdata.get("title", race_id), Vector2(rx + 10, cy + 8), 14,
			rdata.get("color", Color(0.55,0.75,0.85)) if is_sel else Color(0.75,0.72,0.80))
		_draw_text(rdata.get("passive", ""), Vector2(rx + 10, cy + 26), 9,
			Color(0.55, 0.50, 0.65), true, int(vp.x * 0.46 - 14))
		cy += 50.0

	cy = max(cy, 92.0 + _class_order.size() * 50.0 + 18.0) + 12.0
	_draw_loadout_summary(vp, cx, cy)

func _draw_loadout_summary(vp: Vector2, x: float, y: float) -> void:
	var cdata: Dictionary = _cd.get_class_data(_selected_class)
	var rdata: Dictionary = _cd.get_race(_selected_race)
	draw_rect(Rect2(x, y, vp.x - x * 2, 58), Color(0.10, 0.08, 0.16))
	draw_rect(Rect2(x, y, vp.x - x * 2, 58), Color(0.30, 0.22, 0.48, 0.30), false, 1.0)
	_draw_text("%s %s" % [rdata.get("title",""), cdata.get("title","")],
		Vector2(x + 10, y + 10), 14, cdata.get("color", Color(0.85,0.65,0.20)))
	_draw_text("Starting weapon: %s" % WeaponDatabase.WEAPONS.get(
		WeaponDatabase.CLASS_STARTING.get(_selected_class,"NONE"),{}).get("name","Unarmed"),
		Vector2(x + 10, y + 28), 10, Color(0.65,0.60,0.75))
	var hp_base: int = cdata.get("hp_base", 6)
	_draw_text("HP: %d  |  %s" % [hp_base, rdata.get("ability_name","")],
		Vector2(x + 10, y + 44), 10, Color(0.65,0.60,0.75))

# Stats tab
func _draw_stats_tab(vp: Vector2) -> void:
	var cx: float = 24.0
	var cy: float = 92.0
	var rows: Array = [
		["Runs Completed",  str(_mp.runs_completed)],
		["Runs Attempted",  str(_mp.runs_attempted)],
		["Ghost Runs",      str(_mp.ghost_runs)],
		["Citadel Clears",  str(_mp.citadel_clears)],
		["Lifetime Gold",   "%d gp" % _mp.lifetime_gold],
		["Takedowns",       str(_mp.lifetime_takedowns)],
		["Alerts Caused",   str(_mp.lifetime_alerts)],
		["Best Rating",     _mp.best_rating if not _mp.best_rating.is_empty() else "None"],
	]
	for row in rows:
		draw_rect(Rect2(cx, cy, vp.x - 48, 22), Color(0.09, 0.07, 0.13))
		_draw_text(row[0], Vector2(cx + 10, cy + 6), 11, Color(0.60, 0.56, 0.72))
		_draw_text(row[1], Vector2(cx + vp.x * 0.6, cy + 6), 11, Color(0.92, 0.88, 0.75))
		cy += 26.0

	# Lay Low button — spend 15 rep to reduce heat by 1
	if _mp.city_heat > 0:
		var lbx: float = cx
		var lby: float = cy + 8.0
		var can_afford: bool = _mp.guild_rep >= 15
		var lbg: Color = Color(0.12, 0.10, 0.18) if can_afford else Color(0.08, 0.07, 0.10)
		var lbc: Color = Color(0.55, 0.80, 0.55, 0.80) if can_afford else Color(0.30, 0.30, 0.30, 0.60)
		draw_rect(Rect2(lbx, lby, vp.x - 48, 32), lbg)
		draw_rect(Rect2(lbx, lby, vp.x - 48, 32), lbc, false, 1.0)
		var heat_d: Dictionary = _mp.get_heat_data()
		_draw_text("[L] Lay Low  —  -15 rep → Heat: %s → %s" % [
			heat_d.get("name","?"),
			_mp.HEAT_LEVELS[max(0, _mp.city_heat - 1)].get("name","?")],
			Vector2(lbx + 12, lby + 10), 11, lbc)

# Unlocks tab
func _draw_unlocks_tab(vp: Vector2) -> void:
	var cx: float = 24.0
	var cy: float = 92.0
	_draw_text("GUILD UNLOCKS", Vector2(cx, cy), 11, Color(0.65, 0.55, 0.80))
	cy += 18.0
	for unlock in _mp.GUILD_UNLOCKS:
		var earned: bool = _mp.guild_rep >= unlock["rep"]
		var bg: Color = Color(0.12, 0.10, 0.20) if earned else Color(0.08, 0.07, 0.11)
		draw_rect(Rect2(cx, cy, vp.x - 48, 36), bg)
		var name_col: Color = Color(0.92, 0.80, 0.40) if earned else Color(0.35, 0.32, 0.42)
		var desc_col: Color = Color(0.65, 0.60, 0.75) if earned else Color(0.30, 0.28, 0.38)
		_draw_text(unlock["name"], Vector2(cx + 10, cy + 6), 12, name_col)
		_draw_text(unlock["desc"], Vector2(cx + 10, cy + 22), 9, desc_col)
		var rep_str: String = "%d REP" % unlock["rep"] if not earned else "✓"
		var rep_col: Color = Color(0.55, 0.50, 0.65) if not earned else Color(0.40, 0.85, 0.45)
		_draw_text(rep_str, Vector2(vp.x - 80, cy + 14), 10, rep_col)
		cy += 42.0

# Contract tab
func _draw_contract_tab(vp: Vector2) -> void:
	var cx: float = 24.0
	var cy: float = 92.0
	_draw_text("CHALLENGE CONTRACT", Vector2(cx, cy), 11, Color(0.65, 0.55, 0.80))
	_draw_text("(Optional — harder, pays more)", Vector2(cx + 220, cy + 1), 9, Color(0.45,0.42,0.58))
	cy += 18.0
	var contracts: Array = ["NONE","PHANTOM_PROTOCOL","HIRED_BLADE","SPEED_DEMON","CLEAN_HANDS","THE_COLLECTOR","IRON_RUN"]
	for cid in contracts:
		var cdata: Dictionary = CONTRACT_DESCRIPTIONS.get(cid, CONTRACT_DESCRIPTIONS["NONE"])
		var is_sel: bool = _selected_contract == cid
		draw_rect(Rect2(cx, cy, vp.x - 48, 56),
			Color(0.16, 0.12, 0.24) if is_sel else Color(0.09, 0.07, 0.13))
		if is_sel:
			draw_rect(Rect2(cx, cy, vp.x - 48, 56),
				Color(cdata.get("color",Color(0.5,0.5,0.5)).r,
					  cdata.get("color",Color(0.5,0.5,0.5)).g,
					  cdata.get("color",Color(0.5,0.5,0.5)).b, 0.30), false, 1.5)
		_draw_text(cdata.get("name",""), Vector2(cx + 10, cy + 10), 13,
			cdata.get("color", Color(0.75,0.72,0.80)) if is_sel else Color(0.65,0.62,0.72))
		_draw_text(cdata.get("desc",""), Vector2(cx + 10, cy + 28), 9,
			Color(0.60, 0.55, 0.70), true, int(vp.x * 0.65))
		if cdata.get("bonus", 0) > 0:
			_draw_text("+%d gp BONUS" % cdata["bonus"], Vector2(vp.x - 120, cy + 22), 10,
				Color(0.95, 0.80, 0.25))
		cy += 64.0

# Quartermaster panel
func _draw_quartermaster(vp: Vector2) -> void:
	var qy: float = vp.y - 88.0
	draw_rect(Rect2(0, qy, vp.x, 88), Color(0.08, 0.07, 0.13))
	draw_line(Vector2(0, qy), Vector2(vp.x, qy), Color(0.35, 0.28, 0.55, 0.70), 1.0)
	var ic: Vector2 = Vector2(40, qy + 44)
	draw_circle(ic + Vector2(0, -16), 10, Color(0.55, 0.45, 0.35))
	draw_rect(Rect2(ic.x - 10, ic.y - 12, 20, 28), Color(0.30, 0.24, 0.18))
	_draw_text(_qm_name, Vector2(65, qy + 10), 11, Color(0.80, 0.70, 0.45))
	_draw_text("\"%s\"" % _qm_line, Vector2(65, qy + 28), 9, Color(0.72, 0.68, 0.78), true, int(vp.x - 220))

# Start button
func _draw_start_button(vp: Vector2) -> void:
	var bx: float = vp.x - 175.0
	var by: float = vp.y - 62.0
	var pulse: float = 0.10 + sin(_t * 2.2) * 0.06
	draw_rect(Rect2(bx, by, 160, 42), Color(0.20 + pulse * 0.1, 0.14, 0.30 + pulse * 0.1))
	draw_rect(Rect2(bx, by, 160, 42), Color(0.65, 0.40, 0.95, 0.70 + pulse), false, 1.5)
	_draw_text_centered("BEGIN JOB", Vector2(bx + 80, by + 14), 15, Color(0.95, 0.88, 1.00))
	var contract_bonus_str: String = ""
	if _selected_contract != "NONE":
		var cd: Dictionary = CONTRACT_DESCRIPTIONS.get(_selected_contract, {})
		contract_bonus_str = "+%d" % cd.get("bonus", 0)
		_draw_text_centered(contract_bonus_str, Vector2(bx + 80, by + 30), 9, Color(0.95,0.80,0.25))

# Text helpers
func _draw_notification(vp: Vector2) -> void:
	if _notif_timer <= 0.0 or _notif_text.is_empty():
		return
	var alpha: float = clampf(_notif_timer / 0.6, 0.0, 1.0)
	var bw: float = 440.0
	var bh: float = 36.0
	var bx: float = (vp.x - bw) * 0.5
	var by: float = vp.y - 120.0
	draw_rect(Rect2(bx, by, bw, bh), Color(0.06, 0.04, 0.10, alpha * 0.92))
	draw_rect(Rect2(bx, by, bw, bh), Color(_notif_color.r, _notif_color.g, _notif_color.b, alpha * 0.65), false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(vp.x * 0.5, by + 24.0),
		_notif_text, HORIZONTAL_ALIGNMENT_CENTER, bw - 12, 13,
		Color(_notif_color.r, _notif_color.g, _notif_color.b, alpha))

func _draw_text(text: String, pos: Vector2, size: int, color: Color,
		wrap: bool = false, wrap_width: int = 400) -> void:
	if text.is_empty():
		return
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT,
		wrap_width if wrap else -1, size, color)

func _draw_text_centered(text: String, pos: Vector2, size: int, color: Color) -> void:
	if text.is_empty():
		return
	var w: float = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(ThemeDB.fallback_font, pos - Vector2(w * 0.5, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

# Input
func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		pressed = event.pressed
	if not pressed:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)
		return

	if event is InputEventKey:
		match event.keycode:
			KEY_TAB:
				_tab = (_tab + 1) % 4
			KEY_ESCAPE:
				back_to_menu_requested.emit()
			KEY_ENTER, KEY_KP_ENTER:
				_begin_run()
			KEY_L:
				if _tab == 1:
					_try_lay_low()

func _handle_click(pos: Vector2) -> void:
	var vp: Vector2 = get_viewport_rect().size

	var tab_w: float = vp.x / 4.0
	if pos.y >= 52 and pos.y <= 78:
		_tab = int(pos.x / tab_w)
		queue_redraw()
		return

	var bx: float = vp.x - 175.0
	var by: float = vp.y - 62.0
	if Rect2(bx, by, 160, 42).has_point(pos):
		_begin_run()
		return

	if _tab == 0:
		_handle_roster_click(pos, vp)

	if _tab == 1:
		_handle_stats_click(pos, vp)

	if _tab == 3:
		_handle_contract_click(pos, vp)

func _handle_roster_click(pos: Vector2, vp: Vector2) -> void:
	var cx: float = 24.0; var cy: float = 110.0
	for class_id in _class_order:
		if Rect2(cx, cy, vp.x * 0.42, 42).has_point(pos):
			_selected_class = class_id
			queue_redraw()
			return
		cy += 50.0
	var rx: float = vp.x * 0.48; cy = 110.0
	for race_id in _race_order:
		if Rect2(rx, cy, vp.x * 0.48, 42).has_point(pos):
			_selected_race = race_id
			queue_redraw()
			return
		cy += 50.0

func _handle_contract_click(pos: Vector2, vp: Vector2) -> void:
	var cx: float = 24.0; var cy: float = 110.0
	var contracts: Array = ["NONE","PHANTOM_PROTOCOL","HIRED_BLADE","SPEED_DEMON","CLEAN_HANDS","THE_COLLECTOR","IRON_RUN"]
	for cid in contracts:
		if Rect2(cx, cy, vp.x - 48, 56).has_point(pos):
			_selected_contract = cid
			queue_redraw()
			return
		cy += 64.0

func _begin_run() -> void:
	GameManager.selected_class    = _selected_class
	GameManager.selected_race     = _selected_race
	GameManager.active_contract   = _selected_contract
	GameManager.contract_name     = CONTRACT_DESCRIPTIONS.get(_selected_contract,{}).get("name","")
	GameManager.contract_desc     = CONTRACT_DESCRIPTIONS.get(_selected_contract,{}).get("desc","")
	GameManager.contract_bonus    = CONTRACT_DESCRIPTIONS.get(_selected_contract,{}).get("bonus",0)
	GameManager.run_seed          = randi()
	_mp.runs_attempted  += 1
	start_run_requested.emit(_selected_class, _selected_race, _selected_contract)
	GameManager.go_to_preheist()

func _handle_stats_click(pos: Vector2, vp: Vector2) -> void:
	if _mp.city_heat <= 0:
		return
	var lby: float = 92.0 + 7 * 26.0 + 8.0  # below the 7 stat rows
	if Rect2(24.0, lby, vp.x - 48, 32).has_point(pos):
		_try_lay_low()

func _try_lay_low() -> void:
	if _mp.city_heat <= 0:
		return
	if _mp.guild_rep < 15:
		_notif_text  = "Need 15 Guild Rep to Lay Low (have %d)" % _mp.guild_rep
		_notif_color = Color(0.90, 0.40, 0.20)
		_notif_timer = 3.0
		return
	_mp.guild_rep = max(0, _mp.guild_rep - 15)
	_mp.decay_heat()  # also calls save_progress()
	GameManager.guild_rep = _mp.guild_rep
	_notif_text  = "Laid Low — Heat reduced. Rep: %d" % _mp.guild_rep
	_notif_color = Color(0.55, 0.80, 0.55)
	_notif_timer = 3.5
	AudioManager.ui_confirm()
	queue_redraw()
