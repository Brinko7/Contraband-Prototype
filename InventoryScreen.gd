extends CanvasLayer

# ── State ─────────────────────────────────────────────────────────────────────
var _player = null
var _cursor_section: int = 0   # 0=weapon, 1=gear, 2=items
var _cursor_gear: int = 0      # 0=boots, 1=cloak, 2=offhand, 3=trinket
var _cursor_item: int = 0      # index in items array
var _t: float = 0.0

var _control: Control = null

const GEAR_SLOTS := ["boots", "cloak", "offhand", "trinket"]
const GEAR_SLOT_LABELS := ["Boots", "Cloak", "Offhand", "Trinket"]

const ITEM_NAMES := {
	0: "Gold Piece",
	1: "Alch. Smoke",
	2: "Sopor. Dart",
	3: "Silk Rope",
	4: "Flash Powder",
	5: "Hold Person",
	6: "Silence",
	7: "Thieves' Tools",
	8: "Shadow Cloak",
	9: "Iron Key",
}

const ITEM_COLORS := {
	0: Color(0.95, 0.80, 0.10),
	1: Color(0.55, 0.90, 0.45),
	2: Color(0.30, 0.70, 0.95),
	3: Color(0.75, 0.55, 0.95),
	4: Color(1.00, 0.95, 0.70),
	5: Color(0.55, 0.35, 0.90),
	6: Color(0.30, 0.20, 0.55),
	7: Color(0.70, 0.55, 0.30),
	8: Color(0.20, 0.15, 0.35),
	9: Color(0.90, 0.75, 0.20),
}

# ── Public API ────────────────────────────────────────────────────────────────
func open(player: Node) -> void:
	_player = player
	_cursor_section = 0
	_cursor_gear = 0
	_cursor_item = 0
	_t = 0.0
	_control.visible = true
	_control.queue_redraw()

func close() -> void:
	_control.visible = false
	if _player and _player.has_method("save_items"):
		_player.call("save_items")
	_player = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer = 10
	_control = Control.new()
	_control.name = "InvControl"
	_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_control.visible = false
	# Attach draw script inline via callable
	_control.set_script(load("res://InventoryScreenControl.gd"))
	_control.set_meta("inv_screen", self)
	add_child(_control)

func _process(delta: float) -> void:
	if not _control.visible:
		return
	_t += delta
	_control.queue_redraw()

# ── Input ─────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not _control.visible:
		return
	var is_key: bool = event is InputEventKey
	var is_joy: bool = event is InputEventJoypadButton
	var is_axis: bool = event is InputEventJoypadMotion
	if not (is_key or is_joy or is_axis):
		return
	var pressed: bool
	if is_axis:
		pressed = true
	else:
		pressed = event.pressed and not (is_key and (event as InputEventKey).echo)
	if not pressed:
		return

	var items_arr: Array = []
	var gear_dict: Dictionary = {}
	if _player:
		if _player.has_method("get_item_list"):
			items_arr = _player.call("get_item_list")
		if _player.has_method("get_gear_list"):
			gear_dict = _player.call("get_gear_list")

	if event.is_action_pressed("ui_left"):
		_cursor_section = max(0, _cursor_section - 1)
		AudioManager.ui_nav()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("ui_right"):
		_cursor_section = min(2, _cursor_section + 1)
		AudioManager.ui_nav()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up"):
		match _cursor_section:
			0: pass
			1: _cursor_gear = max(0, _cursor_gear - 1)
			2: _cursor_item = max(0, _cursor_item - 1)
		AudioManager.ui_nav()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("ui_down"):
		match _cursor_section:
			0: pass
			1: _cursor_gear = min(3, _cursor_gear + 1)
			2:
				if not items_arr.is_empty():
					_cursor_item = min(items_arr.size() - 1, _cursor_item + 1)
		AudioManager.ui_nav()
		get_viewport().set_input_as_handled()
		return

	# Quick slot assignment
	if _cursor_section == 2 and not items_arr.is_empty() and _cursor_item < items_arr.size():
		if event.is_action_pressed("menu_slot_1"):
			_player.call("equip_type_to_slot", 0, items_arr[_cursor_item].get("type", -1))
			_player.call("save_items")
			AudioManager.ui_confirm()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("menu_slot_2"):
			_player.call("equip_type_to_slot", 1, items_arr[_cursor_item].get("type", -1))
			_player.call("save_items")
			AudioManager.ui_confirm()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("menu_slot_3"):
			_player.call("equip_type_to_slot", 2, items_arr[_cursor_item].get("type", -1))
			_player.call("save_items")
			AudioManager.ui_confirm()
			get_viewport().set_input_as_handled()
			return

	# Unequip gear
	if _cursor_section == 1:
		var is_g := is_key and (event as InputEventKey).keycode == KEY_G
		var is_bs := is_key and (event as InputEventKey).keycode == KEY_BACKSPACE
		if is_g or is_bs or event.is_action_pressed("menu_back"):
			if _cursor_section == 1:
				var slot_key: String = GEAR_SLOTS[_cursor_gear]
				if _player and gear_dict.get(slot_key, "") != "":
					_player.call("equip_gear", slot_key, "")
					_player.call("save_items")
					AudioManager.ui_confirm()
					get_viewport().set_input_as_handled()
					return

	# Close
	if event.is_action_pressed("menu_equip") or event.is_action_pressed("menu_back"):
		GameManager.state = GameManager.State.PLAYING
		close()
		AudioManager.ui_confirm()
		get_viewport().set_input_as_handled()
		return
	if is_key and (event as InputEventKey).keycode == KEY_TAB:
		GameManager.state = GameManager.State.PLAYING
		close()
		AudioManager.ui_confirm()
		get_viewport().set_input_as_handled()
		return

	get_viewport().set_input_as_handled()

# ── Draw helpers (called from InventoryScreenControl.gd) ─────────────────────
func do_draw(ctrl: Control) -> void:
	if not _player:
		return

	var vp_size: Vector2 = ctrl.get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font

	# Gather data
	var items_arr: Array = []
	var gear_dict: Dictionary = {}
	var equipped_arr: Array = []
	var weapon_id: String = "NONE"
	if _player.has_method("get_item_list"):
		items_arr = _player.call("get_item_list")
	if _player.has_method("get_gear_list"):
		gear_dict = _player.call("get_gear_list")
	if _player.has_method("get_equipped_list"):
		equipped_arr = _player.call("get_equipped_list")
	if _player.get("weapon") != null:
		weapon_id = _player.get("weapon")

	# Layout constants
	var PAD: float = 16.0
	var PANEL_W: float = vp_size.x - PAD * 2.0
	var PANEL_H: float = vp_size.y - PAD * 2.0
	var PX: float = PAD
	var PY: float = PAD

	# Background overlay
	ctrl.draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.04, 0.03, 0.08, 0.96))
	# Outer border
	_draw_border(ctrl, Rect2(PX, PY, PANEL_W, PANEL_H), Color(0.28, 0.25, 0.20, 0.60))

	# ── Header ──────────────────────────────────────────────────────────────
	var header_h: float = 42.0
	_draw_section_bg(ctrl, Rect2(PX, PY, PANEL_W, header_h), Color(0.07, 0.06, 0.12, 0.92))

	# Title
	ctrl.draw_string(font, Vector2(PX + 14, PY + 27), "━━  LOADOUT  ━━",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.80, 0.40))

	# Class / floor
	var cls: String = GameManager.selected_class
	var floor_str: String = "Floor %d/%d" % [GameManager.current_floor, GameManager.MAX_FLOORS]
	var hp: int = GameManager.player_hp
	var max_hp: int = GameManager.player_max_hp
	var gold: int = GameManager.gold_collected

	var meta_str: String = "%s   %s" % [cls, floor_str]
	ctrl.draw_string(font, Vector2(PX + 210, PY + 27), meta_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.70, 0.65, 0.55))

	# HP hearts
	_draw_hp_hearts(ctrl, font, Vector2(PX + 420, PY + 27), hp, max_hp)

	# Gold
	ctrl.draw_string(font, Vector2(PX + PANEL_W - 130, PY + 27), "⬡ %d gp" % gold,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.80, 0.10))

	# Close hint top-right
	ctrl.draw_string(font, Vector2(PX + PANEL_W - 150, PY + 14), "[TAB/ESC] Close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.50, 0.48, 0.42, 0.70))

	# ── Three-column layout ──────────────────────────────────────────────────
	var content_y: float = PY + header_h + 1.0
	# Divider heights
	var top_h: float = 160.0    # weapon + gear + desc row
	var divider_y: float = content_y + top_h

	# Column widths
	var col_left_w: float = 180.0
	var col_mid_w: float = 240.0
	var col_right_w: float = PANEL_W - col_left_w - col_mid_w - 4.0

	var col_left_x: float = PX
	var col_mid_x: float = PX + col_left_w + 1.0
	var col_right_x: float = PX + col_left_w + col_mid_w + 2.0

	# Column backgrounds
	_draw_section_bg(ctrl, Rect2(col_left_x, content_y, col_left_w, top_h), Color(0.06, 0.05, 0.10, 0.70))
	_draw_section_bg(ctrl, Rect2(col_mid_x, content_y, col_mid_w, top_h), Color(0.05, 0.05, 0.09, 0.70))
	_draw_section_bg(ctrl, Rect2(col_right_x, content_y, col_right_w, top_h), Color(0.05, 0.04, 0.09, 0.70))

	# Vertical dividers
	ctrl.draw_line(Vector2(col_mid_x, content_y), Vector2(col_mid_x, divider_y), Color(0.28, 0.25, 0.20, 0.50))
	ctrl.draw_line(Vector2(col_right_x, content_y), Vector2(col_right_x, divider_y), Color(0.28, 0.25, 0.20, 0.50))
	# Horizontal divider
	ctrl.draw_line(Vector2(PX, divider_y), Vector2(PX + PANEL_W, divider_y), Color(0.28, 0.25, 0.20, 0.50))

	# ── WEAPON column ────────────────────────────────────────────────────────
	_draw_weapon_section(ctrl, font, col_left_x, content_y, col_left_w, top_h, weapon_id)

	# ── GEAR column ──────────────────────────────────────────────────────────
	_draw_gear_section(ctrl, font, col_mid_x, content_y, col_mid_w, top_h, gear_dict, weapon_id)

	# ── DESC column ──────────────────────────────────────────────────────────
	_draw_desc_section(ctrl, font, col_right_x, content_y, col_right_w, top_h,
		weapon_id, gear_dict, items_arr, equipped_arr)

	# ── Bottom area: quick slots + inventory ─────────────────────────────────
	var bot_y: float = divider_y + 1.0
	var bot_h: float = PY + PANEL_H - bot_y - 22.0   # leave room for hint bar

	var qs_w: float = 180.0
	var inv_x: float = PX + qs_w + 1.0
	var inv_w: float = PANEL_W - qs_w - 1.0

	_draw_section_bg(ctrl, Rect2(PX, bot_y, qs_w, bot_h), Color(0.05, 0.05, 0.09, 0.70))
	_draw_section_bg(ctrl, Rect2(inv_x, bot_y, inv_w, bot_h), Color(0.05, 0.04, 0.08, 0.70))
	ctrl.draw_line(Vector2(inv_x, bot_y), Vector2(inv_x, bot_y + bot_h), Color(0.28, 0.25, 0.20, 0.50))

	_draw_quickslots(ctrl, font, PX, bot_y, qs_w, bot_h, equipped_arr, items_arr)
	_draw_inventory(ctrl, font, inv_x, bot_y, inv_w, bot_h, items_arr, equipped_arr)

	# ── Hint bar ─────────────────────────────────────────────────────────────
	var hint_y: float = PY + PANEL_H - 20.0
	ctrl.draw_string(font, Vector2(PX + 8, hint_y + 12),
		"[↑↓] Navigate   [←→] Section   [1/2/3] Assign slot   [G/BKSP] Unequip gear   [TAB] Close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.48, 0.45, 0.40, 0.75))

func _draw_weapon_section(ctrl: Control, font: Font, x: float, y: float, w: float, h: float,
		weapon_id: String) -> void:
	var is_active: bool = _cursor_section == 0
	ctrl.draw_string(font, Vector2(x + 8, y + 17), "WEAPON",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.80, 0.72, 0.55) if is_active else Color(0.55, 0.52, 0.42))
	ctrl.draw_line(Vector2(x + 4, y + 21), Vector2(x + w - 4, y + 21),
		Color(1.0, 1.0, 1.0, 0.07), 1.0)

	if is_active:
		ctrl.draw_line(Vector2(x, y), Vector2(x, y + h), Color(0.65, 0.50, 1.00), 2.0)

	var wpn_data: Dictionary = GameManager.WEAPONS.get(weapon_id, {})
	var wpn_name: String = wpn_data.get("name", weapon_id)
	var wpn_color: Color = wpn_data.get("color", Color(0.55, 0.55, 0.55))
	var wpn_tags: Array = wpn_data.get("tags", [])
	var wpn_tier: int = int(wpn_data.get("tier", 0))

	# Weapon box
	var box_x: float = x + 8.0
	var box_y: float = y + 26.0
	var box_w: float = w - 16.0
	var box_h: float = 52.0
	var box_bg: Color = wpn_color
	box_bg.a = 0.18
	ctrl.draw_rect(Rect2(box_x, box_y, box_w, box_h), box_bg)
	ctrl.draw_rect(Rect2(box_x, box_y, box_w, box_h), wpn_color * Color(1,1,1,0.45), false, 1.0)

	# Icon
	ctrl.draw_string(font, Vector2(box_x + 6, box_y + 18), "⚔",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, wpn_color)

	# Name
	ctrl.draw_string(font, Vector2(box_x + 26, box_y + 17), wpn_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.92, 0.85))

	# Tier pips
	for i in range(3):
		var pip_color: Color = wpn_color if i < wpn_tier else Color(0.30, 0.28, 0.25)
		ctrl.draw_circle(Vector2(box_x + 26 + i * 9, box_y + 30), 3.0, pip_color)

	# Tags
	var tag_str: String = ""
	for tg in wpn_tags:
		tag_str += str(tg) + "  "
	ctrl.draw_string(font, Vector2(box_x + 6, box_y + 46), tag_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.62, 0.52, 0.80))

	# Upgrade hint
	var next_wpn: String = GameManager.WEAPON_UPGRADES.get(weapon_id, "")
	if not next_wpn.is_empty():
		var next_data: Dictionary = GameManager.WEAPONS.get(next_wpn, {})
		var next_name: String = next_data.get("name", next_wpn)
		ctrl.draw_string(font, Vector2(x + 8, y + h - 16),
			"→ " + next_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.55, 0.30, 0.80))

func _draw_gear_section(ctrl: Control, font: Font, x: float, y: float, w: float, h: float,
		gear_dict: Dictionary, weapon_id: String) -> void:
	var is_active: bool = _cursor_section == 1
	ctrl.draw_string(font, Vector2(x + 8, y + 17), "GEAR SLOTS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.80, 0.72, 0.55) if is_active else Color(0.55, 0.52, 0.42))
	ctrl.draw_line(Vector2(x + 4, y + 21), Vector2(x + w - 4, y + 21),
		Color(1.0, 1.0, 1.0, 0.07), 1.0)

	if is_active:
		ctrl.draw_line(Vector2(x, y), Vector2(x, y + h), Color(0.65, 0.50, 1.00), 2.0)

	var row_h: float = 20.0
	var row_start_y: float = y + 26.0

	for i in range(4):
		var slot_key: String = GEAR_SLOTS[i]
		var slot_label: String = GEAR_SLOT_LABELS[i]
		var gear_id: String = gear_dict.get(slot_key, "")
		var gear_data: Dictionary = GameManager.GEAR.get(gear_id, {}) if not gear_id.is_empty() else {}
		var gear_name: String = gear_data.get("name", "") if not gear_id.is_empty() else ""
		var gear_color: Color = gear_data.get("color", Color(0.55, 0.55, 0.55)) if not gear_id.is_empty() else Color(0.55, 0.55, 0.55)

		var ry: float = row_start_y + i * (row_h + 2.0)
		var is_selected: bool = is_active and i == _cursor_gear

		if is_selected:
			ctrl.draw_rect(Rect2(x + 1, ry - 2, w - 2, row_h + 2), Color(0.20, 0.18, 0.30, 0.85))
			ctrl.draw_line(Vector2(x + 1, ry - 2), Vector2(x + 1, ry + row_h), Color(0.65, 0.50, 1.00), 2.0)

		# Slot bracket label (full label, not truncated)
		ctrl.draw_string(font, Vector2(x + 6, ry + 13),
			"[%s]" % slot_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.50, 0.48, 0.40))

		# Gear name
		if gear_name.is_empty():
			ctrl.draw_string(font, Vector2(x + 72, ry + 13), "─ empty ─",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.38, 0.35, 0.30, 0.70))
		else:
			ctrl.draw_string(font, Vector2(x + 72, ry + 13), gear_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gear_color)

	# Set bonus display
	var set_counts: Dictionary = {"shadow": 0, "thief": 0, "iron": 0}
	for slot in gear_dict:
		var gid: String = gear_dict[slot]
		if not gid.is_empty():
			var s: String = GameManager.GEAR.get(gid, {}).get("set", "")
			if s in set_counts:
				set_counts[s] += 1
	var wtags: Array = GameManager.WEAPONS.get(weapon_id, {}).get("tags", [])
	if "shadow" in wtags: set_counts["shadow"] += 1
	if "piercing" in wtags or "silent" in wtags: set_counts["thief"] += 1

	var set_y: float = row_start_y + 4 * (row_h + 2.0) + 8.0
	ctrl.draw_string(font, Vector2(x + 8, set_y), "SET BONUSES",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.52, 0.42))
	set_y += 15.0

	for set_key in ["shadow", "thief", "iron"]:
		var cnt: int = set_counts[set_key]
		var sdata: Dictionary = GameManager.SET_BONUSES.get(set_key, {})
		var sname: String = sdata.get("name", set_key)
		var scolor: Color = sdata.get("color", Color(0.65, 0.65, 0.65))
		var display_color: Color
		if cnt >= 3:
			display_color = scolor
		elif cnt == 2:
			display_color = Color(0.85, 0.72, 0.25)
		else:
			display_color = Color(0.40, 0.38, 0.34)
		var label_str: String = "%s %d/3" % [sname.to_upper(), cnt]
		if cnt >= 3:
			label_str += " ✓"
		ctrl.draw_string(font, Vector2(x + 8, set_y), label_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, display_color)
		set_y += 14.0

func _draw_desc_section(ctrl: Control, font: Font, x: float, y: float, w: float, h: float,
		weapon_id: String, gear_dict: Dictionary, items_arr: Array, equipped_arr: Array) -> void:
	ctrl.draw_string(font, Vector2(x + 8, y + 17), "DESCRIPTION",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.52, 0.42))
	ctrl.draw_line(Vector2(x + 4, y + 21), Vector2(x + w - 4, y + 21),
		Color(1.0, 1.0, 1.0, 0.07), 1.0)

	var desc_lines: Array = []
	var title_str: String = ""
	var title_color: Color = Color(0.88, 0.85, 0.78)

	match _cursor_section:
		0:  # Weapon
			var wpn_data: Dictionary = GameManager.WEAPONS.get(weapon_id, {})
			title_str = wpn_data.get("name", "Weapon")
			title_color = wpn_data.get("color", Color(0.88, 0.85, 0.78))
			desc_lines.append(wpn_data.get("desc", "No description."))
			var tags: Array = wpn_data.get("tags", [])
			if not tags.is_empty():
				var ts: Array[String] = []
				for tg in tags: ts.append(str(tg))
				desc_lines.append("Tags: " + ", ".join(ts))
			var tier: int = int(wpn_data.get("tier", 0))
			desc_lines.append("Tier %d" % tier)
			var cls_req: String = wpn_data.get("class", "")
			if not cls_req.is_empty():
				desc_lines.append("Class: " + cls_req)

		1:  # Gear slot
			var slot_key: String = GEAR_SLOTS[_cursor_gear]
			var gear_id: String = gear_dict.get(slot_key, "")
			if gear_id.is_empty():
				title_str = GEAR_SLOT_LABELS[_cursor_gear] + " — Empty"
				desc_lines.append("No gear equipped in this slot.")
				desc_lines.append("Purchase gear from the Supply Cache.")
			else:
				var gdata: Dictionary = GameManager.GEAR.get(gear_id, {})
				title_str = gdata.get("name", gear_id)
				title_color = gdata.get("color", Color(0.88, 0.85, 0.78))
				desc_lines.append(gdata.get("desc", "No description."))
				var gtags: Array = gdata.get("tags", [])
				if not gtags.is_empty():
					var ts: Array[String] = []
					for tg in gtags: ts.append(str(tg))
					desc_lines.append("Tags: " + ", ".join(ts))
				var gset: String = gdata.get("set", "")
				if not gset.is_empty():
					var sdata: Dictionary = GameManager.SET_BONUSES.get(gset, {})
					desc_lines.append("Set: " + sdata.get("name", gset))
				desc_lines.append("Effect: " + gdata.get("effect", "none"))
			desc_lines.append("[G/BKSP] Unequip")

		2:  # Item
			if items_arr.is_empty() or _cursor_item >= items_arr.size():
				title_str = "No items"
				desc_lines.append("Collect items from the floor.")
			else:
				var item: Dictionary = items_arr[_cursor_item]
				var itype: int = item.get("type", -1)
				title_str = ITEM_NAMES.get(itype, "Unknown")
				title_color = ITEM_COLORS.get(itype, Color(0.88, 0.85, 0.78))
				desc_lines.append("Count: %d" % item.get("count", 0))
				desc_lines.append("[1/2/3] Assign to quick slot")

	# Draw title
	ctrl.draw_string(font, Vector2(x + 8, y + 33), title_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, title_color)

	# Draw description lines (word-wrap manually at ~char limit)
	var line_y: float = y + 50.0
	for line in desc_lines:
		var max_chars: int = int((w - 16.0) / 6.5)
		var remaining: String = line
		while remaining.length() > 0:
			var chunk: String = remaining.substr(0, max_chars)
			if remaining.length() > max_chars:
				var last_space: int = chunk.rfind(" ")
				if last_space > 0:
					chunk = remaining.substr(0, last_space)
				remaining = remaining.substr(chunk.length()).strip_edges(true, false)
			else:
				remaining = ""
			ctrl.draw_string(font, Vector2(x + 8, line_y), chunk,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.72, 0.65))
			line_y += 14.0
		line_y += 4.0

func _draw_quickslots(ctrl: Control, font: Font, x: float, y: float, w: float, h: float,
		equipped_arr: Array, items_arr: Array) -> void:
	ctrl.draw_string(font, Vector2(x + 8, y + 15), "QUICK SLOTS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.52, 0.42))
	ctrl.draw_line(Vector2(x + 4, y + 19), Vector2(x + w - 4, y + 19),
		Color(1.0, 1.0, 1.0, 0.07), 1.0)

	for i in range(3):
		var row_y: float = y + 26.0 + i * 24.0
		var itype: int = equipped_arr[i] if i < equipped_arr.size() else -1
		var iname: String = ITEM_NAMES.get(itype, "─ empty ─") if itype != -1 else "─ empty ─"
		var icolor: Color = ITEM_COLORS.get(itype, Color(0.55, 0.52, 0.42)) if itype != -1 else Color(0.38, 0.35, 0.30)
		var cnt: int = 0
		if itype != -1:
			for item in items_arr:
				if item.get("type", -1) == itype:
					cnt = item.get("count", 0)

		ctrl.draw_string(font, Vector2(x + 6, row_y + 13),
			"[%d]" % (i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.50, 0.48, 0.40))

		if itype == -1:
			ctrl.draw_string(font, Vector2(x + 36, row_y + 13), "─ empty ─",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.38, 0.35, 0.30, 0.70))
		else:
			ctrl.draw_string(font, Vector2(x + 36, row_y + 13), iname,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, icolor)
			ctrl.draw_string(font, Vector2(x + 36 + 108, row_y + 13), "×%d" % cnt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.60, 0.58, 0.50))

func _draw_inventory(ctrl: Control, font: Font, x: float, y: float, w: float, h: float,
		items_arr: Array, equipped_arr: Array) -> void:
	var is_active: bool = _cursor_section == 2
	ctrl.draw_string(font, Vector2(x + 8, y + 15), "ITEM INVENTORY",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.80, 0.72, 0.55) if is_active else Color(0.55, 0.52, 0.42))
	ctrl.draw_line(Vector2(x + 4, y + 19), Vector2(x + w - 4, y + 19),
		Color(1.0, 1.0, 1.0, 0.07), 1.0)

	if is_active:
		ctrl.draw_line(Vector2(x, y), Vector2(x, y + h), Color(0.65, 0.50, 1.00), 2.0)

	if items_arr.is_empty():
		ctrl.draw_string(font, Vector2(x + 8, y + 36), "(no items)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.38, 0.35, 0.30, 0.70))
		return

	const SLOT_BTNS := ["[1]", "[2]", "[3]"]
	for i in range(items_arr.size()):
		var item: Dictionary = items_arr[i]
		var itype: int = item.get("type", -1)
		var icount: int = item.get("count", 0)
		var iname: String = ITEM_NAMES.get(itype, "?")
		var icolor: Color = ITEM_COLORS.get(itype, Color(0.75, 0.72, 0.65))

		var row_y: float = y + 26.0 + i * 22.0
		if row_y + 22.0 > y + h:
			break

		var is_selected: bool = is_active and i == _cursor_item
		if is_selected:
			ctrl.draw_rect(Rect2(x + 1, row_y - 2, w - 2, 20), Color(0.20, 0.18, 0.30, 0.85))
			ctrl.draw_line(Vector2(x + 1, row_y - 2), Vector2(x + 1, row_y + 18), Color(0.65, 0.50, 1.00), 2.0)

		var cursor_mark: String = "▶ " if is_selected else "  "
		ctrl.draw_string(font, Vector2(x + 6, row_y + 13), cursor_mark,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.50, 1.00))

		ctrl.draw_string(font, Vector2(x + 22, row_y + 13), iname,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, icolor)

		ctrl.draw_string(font, Vector2(x + 168, row_y + 13), "×%d" % icount,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.60, 0.58, 0.50))

		# Show slot assignment
		for s in range(3):
			if s < equipped_arr.size() and equipped_arr[s] == itype:
				ctrl.draw_string(font, Vector2(x + 210, row_y + 13), SLOT_BTNS[s],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.50, 0.48, 0.40))
				break

func _draw_hp_hearts(ctrl: Control, font: Font, pos: Vector2, hp: int, max_hp: int) -> void:
	var HEART_W: float = 15.0
	for i in range(max_hp):
		var hx: float = pos.x + i * HEART_W
		var hy: float = pos.y - 11.0
		var filled: bool = i < hp
		var col: Color = Color(0.90, 0.20, 0.25) if filled else Color(0.30, 0.18, 0.20, 0.60)
		ctrl.draw_circle(Vector2(hx + 3.5, hy + 4.5), 3.5, col)
		ctrl.draw_circle(Vector2(hx + 8.5, hy + 4.5), 3.5, col)
		var pts := PackedVector2Array([
			Vector2(hx + 0.5, hy + 7.0),
			Vector2(hx + 11.5, hy + 7.0),
			Vector2(hx + 6.0, hy + 13.0),
		])
		ctrl.draw_colored_polygon(pts, col)
		ctrl.draw_rect(Rect2(hx + 0.5, hy + 5.5, 11.0, 3.5), col, true)

func _draw_section_bg(ctrl: Control, rect: Rect2, color: Color) -> void:
	ctrl.draw_rect(rect, color)

func _draw_border(ctrl: Control, rect: Rect2, color: Color) -> void:
	ctrl.draw_rect(rect, color, false, 1.0)
