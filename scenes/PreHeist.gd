extends Node2D
# Pre-Heist Planning — shown before each floor.
# Player sees: target briefing, intel (if unlocked), loadout review, modifier,
# complication, and can spend gold on shop items before entering.

signal ready_to_enter
signal open_shop_requested

# ── Heist targets per floor ────────────────────────────────────────────────────
const HEIST_TARGETS: Dictionary = {
	1: {
		"name":     "The Merchant Quarter Cellar",
		"location": "Lower City — Merchant District",
		"security": "Light guard rotation. Civilian staff. Old locks.",
		"guards":   "2-3 sentries, 1 roaming",
		"loot_type":"Documents, coin, light valuables",
		"threat":   1,
		"flavor":   "The ledger is somewhere in the vault alcove. The guards change shift at midnight — I've arranged it.",
		"entry_options": [
			{"name": "Front Door",    "desc": "Walk in. Riskiest. No gear required.", "icon": "FRONT_DOOR"},
			{"name": "Side Window",   "desc": "Second-floor window. Requires Silk Rope.", "icon": "SIDE_WINDOW", "requires": "SILK_ROPE"},
			{"name": "Sewer Access",  "desc": "Quiet, messy. No detection on entry.", "icon": "SEWER"},
		],
	},
	2: {
		"name":     "The Garrison Barracks",
		"location": "Middle City — Military Quarter",
		"security": "Active patrol rotation. Armed guards. Iron locks.",
		"guards":   "3-4 sentries, 1 captain, patrol shifts",
		"loot_type":"Military documents, weapons, coin",
		"threat":   2,
		"flavor":   "Barracks guards are jumpy tonight — word got out about the cellar job. Move quiet or move fast.",
		"entry_options": [
			{"name": "Guard Post",    "desc": "Bluff entry. High risk. Tiefling bonus.", "icon": "GUARD_POST"},
			{"name": "Roof Access",   "desc": "Climb over. Requires Silk Rope.", "icon": "ROOF", "requires": "SILK_ROPE"},
			{"name": "Servant Entry", "desc": "Blend in. Forged Papers reduce detection.", "icon": "SERVANT"},
		],
	},
	3: {
		"name":     "The Inner Vault",
		"location": "Upper City — Noble District",
		"security": "Elite guard rotation. Magic wards. Masterwork locks.",
		"guards":   "4-5 elite guards, boss, magic wards",
		"loot_type":"Arcane relics, royal documents, priceless valuables",
		"threat":   3,
		"flavor":   "The inner vault. The guild has waited ten years for this contract. Don't embarrass us.",
		"entry_options": [
			{"name": "Noble Party",   "desc": "Blend with guests. Lowest alert start.", "icon": "NOBLE_PARTY"},
			{"name": "Vault Shaft",   "desc": "Maintenance access. Technical. Thieves' Tools required.", "icon": "VAULT_SHAFT", "requires": "THIEVES_TOOLS"},
			{"name": "Shadow Entry",  "desc": "Night approach. SHADOWDANCER/ASSASSIN only.", "icon": "SHADOW_ENTRY"},
		],
	},
	4: {
		"name":     "The Archduke's Sanctum",
		"location": "Palace District — Inner Keep",
		"security": "Royal guard. Warden mages. Two layers of wards.",
		"guards":   "5-6 guards, 2 captains, magical sentinels",
		"loot_type":"State documents, crown relics, treasury",
		"threat":   4,
		"flavor":   "The sanctum hasn't been breached in forty years. Tonight that changes.",
		"entry_options": [
			{"name": "Diplomatic Pass","desc": "Forged credentials. Reduces starting wanted.", "icon": "DIPLOMATIC"},
			{"name": "Ward Bypass",    "desc": "Use Thieves' Tools to disable entry ward.", "icon": "WARD_BYPASS", "requires": "THIEVES_TOOLS"},
			{"name": "Chaos Approach", "desc": "Create a distraction outside. Smoke Bomb required.", "icon": "CHAOS", "requires": "SMOKE_BOMB"},
		],
	},
	5: {
		"name":     "The Throne Vault",
		"location": "Palace District — Throne Chamber",
		"security": "City Watch reinforcement. Elite Wardens. The Archduke is present.",
		"guards":   "Full patrol, Watch officers, boss Warden",
		"loot_type":"The Grand Compact — one artifact, worth everything",
		"threat":   5,
		"flavor":   "City Watch has been called in. This is what wanted level 5 looks like. Get the relic and get out.",
		"entry_options": [
			{"name": "The Long Way",  "desc": "Through the servant tunnels. Safest path.", "icon": "TUNNEL"},
			{"name": "The Bold Move", "desc": "Direct. All guards alert on entry. Fast exit critical.", "icon": "BOLD"},
			{"name": "The Phantom",   "desc": "Requires: Silk Rope + Smoke Bomb. No alarm on entry.", "icon": "PHANTOM"},
		],
	},
}

const INTEL_CARDS: Dictionary = {
	"patrol_schedule": {
		"name":  "Patrol Schedule",
		"desc":  "Reveals all patrol routes on this floor at run start.",
		"cost":  50,
		"color": Color(0.82, 0.72, 0.42),
	},
	"vault_location": {
		"name":  "Vault Location",
		"desc":  "Marks the primary objective on your minimap from the start.",
		"cost":  40,
		"color": Color(0.78, 0.68, 0.38),
	},
	"guard_weakness": {
		"name":  "Guard Profile",
		"desc":  "Reveals enemy HP and detection range to all guards.",
		"cost":  60,
		"color": Color(0.65, 0.55, 0.85),
	},
	"entry_map": {
		"name":  "Entry Map",
		"desc":  "Reveals fog-of-war for the first room on entry.",
		"cost":  35,
		"color": Color(0.55, 0.75, 0.65),
	},
}

# State
var _t:            float  = 0.0
var _selected_entry: int  = 0
var _purchased_intel: Array = []
var _floor:        int    = 1
var _target:       Dictionary = {}
var _broker_line:  String = ""
var _panel:        int    = 0   # 0=briefing, 1=intel, 2=loadout
var _meta_progress: Node  = null  # cached to avoid editor autoload resolution
var _weapon_db:     Node  = null
var _class_db:      Node  = null

func _ready() -> void:
	_meta_progress = get_node_or_null("/root/MetaProgress")
	_weapon_db     = get_node_or_null("/root/WeaponDatabase")
	_class_db      = get_node_or_null("/root/ClassDatabase")
	_floor   = GameManager.current_floor
	_target  = HEIST_TARGETS.get(_floor, HEIST_TARGETS[1])
	_broker_line = GameManager.get_broker_briefing()
	_purchased_intel.clear()
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	_draw_background(vp)
	_draw_header(vp)
	_draw_panels(vp)
	_draw_broker_quote(vp)
	_draw_bottom_bar(vp)

func _draw_background(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.04, 0.08))
	for tx in range(0, int(vp.x / 48) + 2):
		for ty in range(0, int(vp.y / 48) + 2):
			var noise: float = abs(sin(float(tx) * 2.31 + float(ty) * 1.78)) * 0.025
			draw_rect(Rect2(tx * 48, ty * 48, 47, 47),
				Color(0.06 + noise, 0.05 + noise * 0.5, 0.10 + noise))
	for r in [300.0, 200.0, 120.0, 60.0]:
		var a: float = (1.0 - r / 310.0) * 0.08
		draw_circle(vp * 0.5, r, Color(0.9, 0.7, 0.3, a))

func _draw_header(vp: Vector2) -> void:
	draw_rect(Rect2(0, 0, vp.x, 60), Color(0.06, 0.05, 0.10, 0.95))
	draw_line(Vector2(0, 60), Vector2(vp.x, 60), Color(0.55, 0.35, 0.75, 0.70), 1.5)
	_draw_text_centered("MISSION BRIEFING", Vector2(vp.x * 0.5, 18), 18, Color(0.95, 0.80, 0.40))
	_draw_text_centered("Floor %d of %d — %s" % [_floor, GameManager.MAX_FLOORS, _target.get("name","")],
		Vector2(vp.x * 0.5, 40), 11, Color(0.65, 0.60, 0.80))
	var threat: int = _target.get("threat", 1)
	_draw_text("THREAT:", Vector2(vp.x - 160, 16), 9, Color(0.55, 0.50, 0.70))
	for i in range(5):
		var filled: bool = i < threat
		var tc: Color = Color(0.90, 0.25, 0.15) if filled else Color(0.20, 0.18, 0.25)
		draw_rect(Rect2(vp.x - 160 + i * 18, 30, 15, 8), tc)
	_draw_text("GOLD: %d gp" % GameManager.gold_available(), Vector2(12, 22), 11,
		Color(0.95, 0.80, 0.20))
	if GameManager.floor_complication != "CLEAR":
		var comp_col: Color = Color(0.95, 0.50, 0.20)
		draw_rect(Rect2(12, 36, 130, 18), Color(0.15, 0.08, 0.05))
		draw_rect(Rect2(12, 36, 130, 18), comp_col, false, 1.0)
		_draw_text("! %s" % GameManager.complication_name, Vector2(16, 48), 9, comp_col)

func _draw_panels(vp: Vector2) -> void:
	var tab_labels: Array = ["BRIEFING","INTEL","LOADOUT"]
	var tab_w: float = vp.x / 3.0
	for i in range(3):
		var tx: float = i * tab_w
		var is_active: bool = _panel == i
		draw_rect(Rect2(tx, 60, tab_w - 1, 22),
			Color(0.10, 0.08, 0.16) if is_active else Color(0.06, 0.05, 0.10))
		_draw_text_centered(tab_labels[i], Vector2(tx + tab_w * 0.5, 70), 9,
			Color(0.92, 0.85, 0.55) if is_active else Color(0.45, 0.42, 0.58))
		if is_active:
			draw_line(Vector2(tx, 82), Vector2(tx + tab_w, 82), Color(0.65, 0.40, 0.95, 0.90), 2.0)
	match _panel:
		0: _draw_briefing_panel(vp)
		1: _draw_intel_panel(vp)
		2: _draw_loadout_panel(vp)

func _draw_briefing_panel(vp: Vector2) -> void:
	var cx: float = 24.0
	var cy: float = 98.0
	draw_rect(Rect2(cx, cy, vp.x - 48, 78), Color(0.08, 0.06, 0.13))
	_draw_text(_target.get("location",""), Vector2(cx + 10, cy + 10), 10, Color(0.60, 0.75, 0.90))
	_draw_text("Security: " + _target.get("security",""), Vector2(cx + 10, cy + 28), 9,
		Color(0.70, 0.65, 0.75), true, int(vp.x - 68))
	_draw_text("Guards: " + _target.get("guards",""), Vector2(cx + 10, cy + 46), 9,
		Color(0.75, 0.60, 0.60), true, int(vp.x - 68))
	_draw_text("Loot: " + _target.get("loot_type",""), Vector2(cx + 10, cy + 62), 9,
		Color(0.75, 0.75, 0.45), true, int(vp.x - 68))
	cy += 90.0

	_draw_text("ENTRY OPTIONS", Vector2(cx, cy), 10, Color(0.60, 0.55, 0.78))
	cy += 14.0
	var entries: Array = _target.get("entry_options", [])
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var is_sel: bool = _selected_entry == i
		draw_rect(Rect2(cx, cy, vp.x - 48, 40),
			Color(0.14, 0.10, 0.22) if is_sel else Color(0.08, 0.06, 0.12))
		if is_sel:
			draw_rect(Rect2(cx, cy, 3, 40), Color(0.70, 0.45, 0.95))
		_draw_text(entry.get("name",""), Vector2(cx + 10, cy + 8), 12,
			Color(0.92, 0.85, 1.00) if is_sel else Color(0.65, 0.62, 0.75))
		_draw_text(entry.get("desc",""), Vector2(cx + 10, cy + 24), 9,
			Color(0.60, 0.55, 0.70), true, int(vp.x - 68))
		if entry.has("requires"):
			_draw_text("Requires: " + entry["requires"], Vector2(vp.x - 180, cy + 24), 9,
				Color(0.90, 0.60, 0.25))
		cy += 48.0

	if GameManager.run_modifier != "NONE":
		cy += 8.0
		draw_rect(Rect2(cx, cy, vp.x - 48, 36), Color(0.10, 0.08, 0.06))
		draw_rect(Rect2(cx, cy, vp.x - 48, 36), Color(0.90, 0.55, 0.15, 0.35), false, 1.0)
		_draw_text("RUN MODIFIER: %s" % GameManager.modifier_name, Vector2(cx + 10, cy + 8), 10,
			Color(0.95, 0.70, 0.20))
		_draw_text(GameManager.modifier_desc, Vector2(cx + 10, cy + 24), 9,
			Color(0.72, 0.62, 0.50), true, int(vp.x - 68))

func _draw_intel_panel(vp: Vector2) -> void:
	var cx: float = 24.0
	var cy: float = 98.0
	var intel_unlocked: bool = _meta_progress != null and _meta_progress.has_unlock("INTEL_SYSTEM")
	if not intel_unlocked:
		draw_rect(Rect2(cx, cy, vp.x - 48, 80), Color(0.08, 0.06, 0.12))
		_draw_text_centered("Intel network unlocked at 80 Guild Rep",
			Vector2(vp.x * 0.5, cy + 30), 11, Color(0.45, 0.42, 0.58))
		_draw_text_centered("Current Rep: %d" % (_meta_progress.guild_rep if _meta_progress else 0),
			Vector2(vp.x * 0.5, cy + 50), 10, Color(0.55, 0.50, 0.68))
		return
	_draw_text("AVAILABLE INTEL  (spent from current floor gold)",
		Vector2(cx, cy), 10, Color(0.60, 0.55, 0.78))
	cy += 16.0
	for ikey in INTEL_CARDS:
		var idata: Dictionary = INTEL_CARDS[ikey]
		var purchased: bool = ikey in _purchased_intel
		var can_afford: bool = GameManager.gold_available() >= idata["cost"]
		draw_rect(Rect2(cx, cy, vp.x - 48, 44),
			Color(0.14, 0.12, 0.08) if purchased else Color(0.08, 0.06, 0.12))
		if purchased:
			draw_rect(Rect2(cx, cy, vp.x - 48, 44), Color(0.45, 0.80, 0.35, 0.25), false, 1.0)
		_draw_text(idata["name"], Vector2(cx + 10, cy + 8), 12,
			idata.get("color", Color(0.80, 0.75, 0.55)))
		_draw_text(idata["desc"], Vector2(cx + 10, cy + 26), 9,
			Color(0.60, 0.55, 0.70), true, int(vp.x * 0.70))
		var cost_str: String = "PURCHASED" if purchased else "%d gp" % idata["cost"]
		var cost_col: Color = Color(0.40, 0.85, 0.40) if purchased else \
			(Color(0.95, 0.80, 0.20) if can_afford else Color(0.50, 0.45, 0.55))
		_draw_text(cost_str, Vector2(vp.x - 110, cy + 16), 10, cost_col)
		cy += 52.0

func _draw_loadout_panel(vp: Vector2) -> void:
	var cx: float = 24.0
	var cy: float = 98.0
	draw_rect(Rect2(cx, cy, vp.x - 48, 44), Color(0.09, 0.07, 0.14))
	var wdata: Dictionary = _weapon_db.WEAPONS.get(GameManager.floor_carry_weapon, {}) if _weapon_db else {}
	_draw_text("WEAPON", Vector2(cx + 10, cy + 8), 9, Color(0.50, 0.45, 0.65))
	_draw_text(wdata.get("name","None"), Vector2(cx + 10, cy + 22), 13,
		wdata.get("color", Color(0.75, 0.72, 0.80)))
	_draw_text(wdata.get("desc",""), Vector2(cx + 10, cy + 34), 8,
		Color(0.55, 0.50, 0.65), true, int(vp.x - 68))
	cy += 52.0
	var gear_dict: Dictionary = GameManager.floor_carry_gear
	for slot in ["boots","cloak","offhand","trinket"]:
		var gid: String = gear_dict.get(slot, "")
		draw_rect(Rect2(cx, cy, vp.x - 48, 38), Color(0.08, 0.06, 0.12))
		_draw_text(slot.to_upper(), Vector2(cx + 10, cy + 6), 8, Color(0.45, 0.42, 0.58))
		if gid.is_empty():
			_draw_text("Empty", Vector2(cx + 10, cy + 20), 10, Color(0.35, 0.32, 0.42))
		else:
			var gdata: Dictionary = _class_db.get_gear(gid) if _class_db else {}
			_draw_text(gdata.get("name", gid), Vector2(cx + 10, cy + 20), 10,
				gdata.get("color", Color(0.70, 0.68, 0.75)))
		cy += 44.0
	cy += 4.0
	_draw_text("ITEMS", Vector2(cx, cy), 9, Color(0.50, 0.45, 0.65))
	cy += 14.0
	var item_str: String = ""
	if GameManager.floor_carry_items.is_empty():
		item_str = "No items"
	else:
		var names: PackedStringArray = []
		for item in GameManager.floor_carry_items:
			names.append(item.get("name", "?"))
		item_str = ", ".join(names)
	_draw_text(item_str, Vector2(cx + 10, cy), 10, Color(0.65, 0.62, 0.72), true, int(vp.x - 68))

func _draw_broker_quote(vp: Vector2) -> void:
	var qy: float = vp.y - 90.0
	draw_rect(Rect2(0, qy, vp.x, 52), Color(0.05, 0.04, 0.09, 0.95))
	draw_line(Vector2(0, qy), Vector2(vp.x, qy), Color(0.35, 0.28, 0.55, 0.60), 1.0)
	_draw_text("THE BROKER:", Vector2(14, qy + 10), 9, Color(0.60, 0.55, 0.75))
	_draw_text("\"%s\"" % _broker_line, Vector2(14, qy + 26), 9,
		Color(0.80, 0.75, 0.88), true, int(vp.x - 200))

func _draw_bottom_bar(vp: Vector2) -> void:
	var by: float = vp.y - 38.0
	draw_rect(Rect2(0, by, vp.x, 38), Color(0.07, 0.06, 0.12))
	draw_line(Vector2(0, by), Vector2(vp.x, by), Color(0.30, 0.24, 0.48, 0.70), 1.0)
	draw_rect(Rect2(12, by + 6, 110, 26), Color(0.12, 0.10, 0.18))
	draw_rect(Rect2(12, by + 6, 110, 26), Color(0.50, 0.40, 0.70, 0.55), false, 1.0)
	_draw_text_centered("SHOP [S]", Vector2(67, by + 16), 10, Color(0.80, 0.75, 0.90))
	var pulse: float = abs(sin(_t * 1.8)) * 0.12
	draw_rect(Rect2(vp.x - 135, by + 4, 122, 30),
		Color(0.18 + pulse * 0.1, 0.12, 0.28 + pulse * 0.1))
	draw_rect(Rect2(vp.x - 135, by + 4, 122, 30), Color(0.65, 0.42, 0.95, 0.75 + pulse), false, 1.5)
	_draw_text_centered("ENTER [ENTER]", Vector2(vp.x - 74, by + 16), 10, Color(0.95, 0.88, 1.00))
	if not _purchased_intel.is_empty():
		_draw_text("Intel: %d active" % _purchased_intel.size(),
			Vector2(140, by + 14), 9, Color(0.82, 0.72, 0.42))

func _draw_text(text: String, pos: Vector2, size: int, color: Color,
		do_wrap: bool = false, wrap_width: int = 400) -> void:
	if text.is_empty(): return
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT,
		wrap_width if do_wrap else -1, size, color)

func _draw_text_centered(text: String, pos: Vector2, size: int, color: Color) -> void:
	if text.is_empty(): return
	var w: float = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	draw_string(ThemeDB.fallback_font, pos - Vector2(w * 0.5, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

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
				_panel = (_panel + 1) % 3
			KEY_S:
				open_shop_requested.emit()
			KEY_ENTER, KEY_KP_ENTER:
				_apply_intel_and_enter()
			KEY_LEFT, KEY_A:
				_selected_entry = max(0, _selected_entry - 1)
			KEY_RIGHT, KEY_D:
				var max_entries: int = _target.get("entry_options",[]).size() - 1
				_selected_entry = min(max_entries, _selected_entry + 1)
		queue_redraw()

func _handle_click(pos: Vector2) -> void:
	var vp: Vector2 = get_viewport_rect().size
	var by: float = vp.y - 38.0
	if Rect2(12, by + 6, 110, 26).has_point(pos):
		open_shop_requested.emit()
		return
	if Rect2(vp.x - 135, by + 4, 122, 30).has_point(pos):
		_apply_intel_and_enter()
		return
	var tab_w: float = vp.x / 3.0
	if pos.y >= 60 and pos.y <= 82:
		_panel = int(pos.x / tab_w)
		queue_redraw()
		return
	if _panel == 0:
		var cx: float = 24.0
		var cy: float = 228.0
		for i in range(_target.get("entry_options",[]).size()):
			if Rect2(cx, cy, vp.x - 48, 40).has_point(pos):
				_selected_entry = i
				queue_redraw()
				return
			cy += 48.0
	if _panel == 1 and _meta_progress != null and _meta_progress.has_unlock("INTEL_SYSTEM"):
		var cx: float = 24.0; var cy: float = 114.0
		var keys: Array = INTEL_CARDS.keys()
		for i in range(keys.size()):
			var ikey: String = keys[i]
			if Rect2(cx, cy, vp.x - 48, 44).has_point(pos):
				_try_purchase_intel(ikey)
				return
			cy += 52.0

func _try_purchase_intel(key: String) -> void:
	if key in _purchased_intel:
		return
	var idata: Dictionary = INTEL_CARDS.get(key, {})
	var cost: int = idata.get("cost", 999)
	if GameManager.gold_available() < cost:
		return
	GameManager.gold_spent += cost
	_purchased_intel.append(key)
	queue_redraw()

func _apply_intel_and_enter() -> void:
	GameManager.preheist_intel = _purchased_intel.duplicate()
	var entries: Array = _target.get("entry_options", [])
	if _selected_entry < entries.size():
		GameManager.preheist_entry = entries[_selected_entry].get("icon", "FRONT_DOOR")
	else:
		GameManager.preheist_entry = "FRONT_DOOR"
	ready_to_enter.emit()
	get_tree().change_scene_to_file("res://World.tscn")
