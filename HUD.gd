extends CanvasLayer

@onready var loot_label: Label   = $Control/LootLabel
@onready var status_label: Label = $Control/StatusLabel
@onready var gold_label: Label   = $Control/GoldLabel
@onready var overlay: ColorRect  = $Overlay
@onready var overlay_title: Label  = $Overlay/Title
@onready var overlay_rating: Label = $Overlay/Rating
@onready var overlay_desc: Label   = $Overlay/Desc
@onready var overlay_stats: Label  = $Overlay/Stats
@onready var overlay_hint: Label   = $Overlay/Hint
@onready var item_labels: Array    = [$Control/Item1Label, $Control/Item2Label]

var _alert_flash: ColorRect  = null
var _rating_label: Label     = null
var _wanted_label: Label     = null
var _heat_label: Label       = null
var _hud_panel: Control      = null   # top-left drawn panel (class/floor/HP)
var _threat_bar: Control     = null   # threat/wanted drawn bar
var _mini_map: Control       = null   # top-right mini-map of rooms
var _item_boxes: Array       = []     # 3 styled item box Controls
var _hud_t := 0.0                     # time accumulator for animations

# ── Shop state ────────────────────────────────────────────────────────────────
var _shop_active    := false
var _shop_player    = null
var _shop_panel     = null  # ShopPanel node2D

# ── Passive pick state ────────────────────────────────────────────────────────
var _passive_active  := false
var _passive_choices: Array = []

# ── Inventory screen ─────────────────────────────────────────────────────────
var _inv_screen: CanvasLayer = null

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

func _ready():
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.alert_triggered.connect(_on_alert_triggered)
	GameManager.show_shop.connect(_on_show_shop)
	GameManager.show_passive_pick.connect(_on_show_passive_pick)
	GameManager.reinforcement_incoming.connect(_on_reinforcement_incoming)
	GameManager.death_save_rolled.connect(_on_death_save_rolled)
	overlay.visible = false
	_build_runtime_ui()
	_show_floor_intro.call_deferred()

func _build_runtime_ui():
	# ── Full-screen flash overlays ────────────────────────────────────────────
	_alert_flash = ColorRect.new()
	_alert_flash.color = Color(1.0, 0.0, 0.0, 0.0)
	_alert_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_alert_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Control.add_child(_alert_flash)

	var reinforce_flash := ColorRect.new()
	reinforce_flash.name = "ReinforceFlash"
	reinforce_flash.color = Color(1.0, 0.55, 0.0, 0.0)
	reinforce_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reinforce_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Control.add_child(reinforce_flash)

	# ── Top-left panel: class badge + floor pips + HP hearts ─────────────────
	_hud_panel = Control.new()
	_hud_panel.name = "HudPanel"
	_hud_panel.set_script(load("res://HudPanel.gd"))
	_hud_panel.position = Vector2(6, 6)
	_hud_panel.custom_minimum_size = Vector2(224, 108)
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Control.add_child(_hud_panel)

	# ── Top-right mini-map ───────────────────────────────────────────────────
	_mini_map = Control.new()
	_mini_map.name = "MiniMap"
	_mini_map.set_script(load("res://MiniMap.gd"))
	_mini_map.anchor_top    = 0.0
	_mini_map.anchor_bottom = 0.0
	_mini_map.anchor_left   = 1.0
	_mini_map.anchor_right  = 1.0
	_mini_map.offset_left   = -100.0
	_mini_map.offset_right  = -6.0
	_mini_map.offset_top    = 6.0
	_mini_map.offset_bottom = 80.0
	_mini_map.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	$Control.add_child(_mini_map)

	# ── Threat bar: wanted + heat, appears when relevant ─────────────────────
	_threat_bar = Control.new()
	_threat_bar.name = "ThreatBar"
	_threat_bar.set_script(load("res://ThreatBar.gd"))
	_threat_bar.anchor_top    = 0.0
	_threat_bar.anchor_bottom = 0.0
	_threat_bar.anchor_left   = 0.5
	_threat_bar.anchor_right  = 0.5
	_threat_bar.offset_left   = -100.0
	_threat_bar.offset_right  = 100.0
	_threat_bar.offset_top    = 6.0
	_threat_bar.offset_bottom = 34.0
	_threat_bar.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	$Control.add_child(_threat_bar)

	# ── Top-center: floor name / alert status ─────────────────────────────────
	status_label.add_theme_font_size_override("font_size", 15)
	var _sb := StyleBoxFlat.new()
	_sb.bg_color = Color(0.06, 0.05, 0.09, 0.80)
	_sb.border_width_left   = 1
	_sb.border_width_right  = 1
	_sb.border_width_top    = 1
	_sb.border_width_bottom = 1
	_sb.border_color = Color(0.28, 0.24, 0.18, 0.55)
	_sb.set_corner_radius_all(3)
	_sb.content_margin_left  = 10.0
	_sb.content_margin_right = 10.0
	_sb.content_margin_top   = 4.0
	_sb.content_margin_bottom = 4.0
	status_label.add_theme_stylebox_override("normal", _sb)

	# ── Top-right: gold ──────────────────────────────────────────────────────
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.add_theme_color_override("font_color", Color(0.95, 0.80, 0.10))

	# ── Bottom-left: 3 styled item slot boxes ────────────────────────────────
	# Hide the scene item labels — we replace them with drawn boxes
	for lbl in item_labels:
		(lbl as Label).visible = false
	loot_label.visible = false  # loot shown in panel instead

	const SLOT_X_START := 8.0
	const SLOT_W := 140.0
	const SLOT_H := 50.0
	const SLOT_GAP := 6.0
	const SLOT_BOTTOM := 54.0
	const SLOT_BTNS_ARR := ["1/LT", "2/RT", "3/R3"]
	for i in range(3):
		var box := Control.new()
		box.name = "ItemBox%d" % i
		box.set_script(load("res://ItemBox.gd"))
		box.anchor_top    = 1.0
		box.anchor_bottom = 1.0
		box.offset_left   = SLOT_X_START + i * (SLOT_W + SLOT_GAP)
		box.offset_right  = SLOT_X_START + i * (SLOT_W + SLOT_GAP) + SLOT_W
		box.offset_top    = -(SLOT_H + SLOT_BOTTOM)
		box.offset_bottom = -SLOT_BOTTOM
		box.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		box.set_meta("slot_index", i)
		box.set_meta("bind_label", SLOT_BTNS_ARR[i])
		$Control.add_child(box)
		_item_boxes.append(box)

	# ── Bottom-left sub-row: ability + weapon ─────────────────────────────────
	var ability_label := Label.new()
	ability_label.name = "AbilityLabel"
	ability_label.anchor_top    = 1.0
	ability_label.anchor_bottom = 1.0
	ability_label.offset_left   = 8.0
	ability_label.offset_right  = 430.0
	ability_label.offset_top    = -50.0
	ability_label.offset_bottom = -32.0
	ability_label.add_theme_font_size_override("font_size", 12)
	ability_label.modulate = Color(0.70, 0.55, 1.00, 0.85)
	$Control.add_child(ability_label)

	var weapon_label := Label.new()
	weapon_label.name = "WeaponLabel"
	weapon_label.anchor_top    = 1.0
	weapon_label.anchor_bottom = 1.0
	weapon_label.offset_left   = 8.0
	weapon_label.offset_right  = 460.0
	weapon_label.offset_top    = -32.0
	weapon_label.offset_bottom = -12.0
	weapon_label.add_theme_font_size_override("font_size", 12)
	weapon_label.modulate = Color(0.80, 0.75, 0.60, 0.75)
	$Control.add_child(weapon_label)

	# ── Bottom-right: objective ───────────────────────────────────────────────
	var obj_label := Label.new()
	obj_label.name = "ObjectiveLabel"
	obj_label.anchor_left   = 1.0
	obj_label.anchor_right  = 1.0
	obj_label.anchor_top    = 1.0
	obj_label.anchor_bottom = 1.0
	obj_label.offset_left   = -260.0
	obj_label.offset_right  = -8.0
	obj_label.offset_top    = -32.0
	obj_label.offset_bottom = -12.0
	obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	obj_label.add_theme_font_size_override("font_size", 11)
	obj_label.modulate = Color(0.55, 0.90, 0.55, 0.80)
	$Control.add_child(obj_label)

	# ── Minimap (top-right) ───────────────────────────────────────────────────
	var minimap := Control.new()
	minimap.set_script(load("res://MinimapPanel.gd"))
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-120, 4)
	$Control.add_child(minimap)

func _show_floor_intro():
	overlay.visible = true
	overlay.color = Color(0.0, 0.0, 0.0, 0.88)
	overlay_title.text = GameManager.get_floor_name().to_upper()
	overlay_title.modulate = Color(0.95, 0.85, 0.55)
	overlay_rating.text = "Floor %d of %d" % [GameManager.current_floor, GameManager.MAX_FLOORS]
	overlay_rating.modulate = Color(0.60, 0.60, 0.50)
	overlay_desc.text = GameManager.modifier_name
	overlay_stats.text = GameManager.modifier_desc
	# Show passives if any
	if not GameManager.active_passives.is_empty():
		var pnames: Array[String] = []
		for pid in GameManager.active_passives:
			for p in GameManager.PASSIVES:
				if p.id == pid:
					pnames.append(p.name)
		overlay_stats.text += "\nPassives: " + "  ·  ".join(pnames)
	var hint_lines := []
	if GameManager.floor_complication != "CLEAR":
		hint_lines.append("  %s  —  %s" % [GameManager.complication_name, GameManager.complication_desc])
	if GameManager.floor_objective != "NONE":
		hint_lines.append("  Objective: %s  —  %s  (+%d gp)" % [
			GameManager.floor_objective_name, GameManager.floor_objective_desc,
			GameManager.floor_objective_bonus])
	overlay_hint.text = "\n".join(hint_lines)
	overlay_hint.modulate = Color(1.0, 0.75, 0.30, 0.85)
	await get_tree().create_timer(2.2).timeout
	overlay.visible = false

func _on_alert_triggered():
	if _alert_flash == null:
		return
	var tween := create_tween()
	_alert_flash.color = Color(1.0, 0.0, 0.0, 0.30)
	tween.tween_property(_alert_flash, "color", Color(1.0, 0.0, 0.0, 0.0), 0.45)

func _on_reinforcement_incoming():
	AudioManager.reinforcement_alarm()
	var rf := $Control.get_node_or_null("ReinforceFlash") as ColorRect
	if rf:
		var tw := create_tween()
		rf.color = Color(1.0, 0.55, 0.0, 0.35)
		tw.tween_property(rf, "color", Color(1.0, 0.55, 0.0, 0.0), 0.60)
	# Brief status override text
	status_label.text = "▲ REINFORCEMENTS"
	status_label.modulate = Color(1.0, 0.55, 0.0)
	await get_tree().create_timer(2.0).timeout
	# status will be overwritten on next _process frame

func _on_death_save_rolled(roll: int, survived: bool):
	var player = get_tree().get_first_node_in_group("player")
	var pos: Vector2 = get_viewport().get_visible_rect().size * 0.5
	if player:
		pos = player.global_position + Vector2(0, -20)
	var dice_scene = preload("res://DicePopup.tscn")
	var popup = dice_scene.instantiate()
	if survived:
		popup.setup("DEATH SAVE: %d ✓ ESCAPED!" % roll, Color(0.30, 1.00, 0.50))
	else:
		popup.setup("DEATH SAVE: %d ✗ CAUGHT" % roll, Color(1.00, 0.15, 0.15))
	popup.global_position = pos
	get_tree().root.add_child(popup)

# ── Passive pick ──────────────────────────────────────────────────────────────
func _on_show_passive_pick():
	_passive_choices = GameManager.roll_passive_choices()
	_passive_active  = true
	overlay.visible  = true
	_refresh_passive_ui()

func _refresh_passive_ui():
	overlay.color = Color(0.04, 0.03, 0.08, 0.96)
	overlay_title.add_theme_font_size_override("font_size", 36)
	overlay_title.text = "━━  ADVANCEMENT  ━━"
	overlay_title.modulate = Color(0.70, 0.55, 1.00)
	var reveal: String = GameManager.get_relic_reveal()
	if not reveal.is_empty():
		overlay_rating.text = "Floor %d cleared  ·  %s" % [GameManager.current_floor, reveal]
	else:
		overlay_rating.text = "Floor %d cleared  ·  Choose a passive upgrade" % GameManager.current_floor
	overlay_rating.modulate = Color(0.72, 0.60, 0.38)

	const CHOICE_BTNS := ["X", "Y", "B"]
	var lines := ""
	for i in range(_passive_choices.size()):
		var p = _passive_choices[i]
		var btn: String = CHOICE_BTNS[i] if i < CHOICE_BTNS.size() else str(i + 1)
		lines += "[%d/%s]  %-18s  %s\n" % [i + 1, btn, p.name, p.desc]
	if _passive_choices.is_empty():
		lines = "(All passives already acquired)"
	overlay_desc.add_theme_font_size_override("font_size", 12)
	overlay_desc.set_offset(SIDE_LEFT, -320)
	overlay_desc.set_offset(SIDE_RIGHT, 320)
	overlay_desc.text = lines
	overlay_desc.modulate = Color(0.88, 0.85, 0.78)

	var cur := "ACTIVE PASSIVES:  "
	if GameManager.active_passives.is_empty():
		cur += "none"
	else:
		var names: Array[String] = []
		for pid in GameManager.active_passives:
			for p in GameManager.PASSIVES:
				if p.id == pid:
					names.append(p.name)
		cur += "  ·  ".join(names)
	overlay_stats.text = cur
	overlay_stats.modulate = Color(0.55, 0.55, 0.50)
	overlay_hint.text = "[1/X]  [2/Y]  [3/B]  Select upgrade   ·   [ENTER/A]  Skip"
	overlay_hint.modulate = Color(0.50, 0.50, 0.45)

func _pick_passive(idx: int):
	var id := ""
	if idx < _passive_choices.size():
		id = _passive_choices[idx].id
	_passive_active = false
	# Keep overlay visible — confirm_passive_pick → show_shop will refresh it immediately
	GameManager.confirm_passive_pick(id)

# ── Shop ──────────────────────────────────────────────────────────────────────
func _on_show_shop():
	_shop_player = get_tree().get_first_node_in_group("player")
	_shop_active = true
	overlay.visible = false  # shop draws itself
	_open_shop_panel()

func _open_shop_panel():
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
	var script := load("res://ShopPanel.gd")
	_shop_panel = Node2D.new()
	_shop_panel.set_script(script)
	add_child(_shop_panel)
	_shop_panel.buy_requested.connect(_shop_buy)
	_shop_panel.close_requested.connect(_leave_shop)

func _refresh_shop_ui():
	overlay.color = Color(0.04, 0.03, 0.06, 0.94)
	overlay_title.add_theme_font_size_override("font_size", 52)
	overlay_desc.add_theme_font_size_override("font_size", 14)
	overlay_desc.set_offset(SIDE_LEFT, -160)
	overlay_desc.set_offset(SIDE_RIGHT, 160)
	var qm: String = GameManager.get("quartermaster_name") if GameManager.get("quartermaster_name") else ""
	overlay_title.text = "━━  SUPPLY CACHE  ━━" if qm.is_empty() else "━━  %s's CACHE  ━━" % qm.to_upper()
	overlay_title.modulate = Color(0.95, 0.78, 0.15)

	var gp := GameManager.gold_available()
	overlay_rating.text = "Floor %d cleared  ·  %d gp available" % [GameManager.current_floor, gp]
	overlay_rating.modulate = Color(0.80, 0.70, 0.40)

	var mult := GameManager.get_shop_cost_multiplier()
	const SHOP_BTNS := ["X", "Y", "B", "LB", "RB", "6/key", "7/key"]
	var has_discount := mult < 0.99
	var lines := ""
	for i in range(GameManager.SHOP_ITEMS.size()):
		var si = GameManager.SHOP_ITEMS[i]
		var cost: int = int(si.cost * mult)
		var afford := "  " if gp >= cost else "x "
		var price_str := "%d gp" % cost
		if has_discount:
			price_str += " (was %d)" % si.cost
		var btn: String = SHOP_BTNS[i] if i < SHOP_BTNS.size() else str(i + 1)
		lines += "[%d/%s]  %s%-14s  %-18s  —  %s\n" % [i+1, btn, afford, si.name, price_str, si.desc]
	overlay_desc.text = lines
	overlay_desc.modulate = Color(0.88, 0.85, 0.78)

	var inv := "GEAR: "
	if _shop_player and _shop_player.has_method("save_items"):
		var pitems: Array = _shop_player.call("get_item_list")
		for item in pitems:
			var n: String = ITEM_NAMES.get(item.get("type", -1), "?")
			inv += "%s x%d   " % [n, item.get("count", 0)]
	overlay_stats.text = inv
	overlay_stats.modulate = Color(0.55, 0.55, 0.50)

	var next_floor := GameManager.current_floor + 1
	var obj_line := ""
	if GameManager.floor_objective != "NONE":
		var done := GameManager.check_objective_complete()
		var marker := "COMPLETED" if done else "FAILED"
		obj_line = "\nObjective: %s — %s  (+%d gp)" % [
			GameManager.floor_objective_name, marker, GameManager.floor_objective_bonus]
	overlay_hint.text = "[1/X]  [2/Y]  [3/B]  [4/LB]  [5/RB]  Purchase   ·   [ENTER/A]  Descend to Floor %d%s" % [next_floor, obj_line]
	overlay_hint.modulate = Color(0.50, 0.50, 0.45)

func _shop_buy(idx: int):
	if idx >= GameManager.floor_shop_items.size():
		return
	var si: Dictionary = GameManager.floor_shop_items[idx]
	var mult := GameManager.get_shop_cost_multiplier()
	var cost: int = int(si.get("cost", 0) * mult)
	if GameManager.gold_available() < cost:
		return
	GameManager.gold_spent += cost
	var itype: int = si.get("type", -1)
	if itype == -1:
		# Gear purchase
		var gear_id: String  = si.get("gear_id", "")
		var gear_slot: String = si.get("gear_slot", "")
		if _shop_player and not gear_id.is_empty():
			_shop_player.call("equip_gear", gear_slot, gear_id)
			_shop_player.call("save_items")
		GameManager.floor_shop_items.remove_at(idx)
	elif itype == -2:
		# Weapon upgrade purchase
		var weapon_id: String = si.get("weapon_id", "")
		if not weapon_id.is_empty():
			GameManager.floor_carry_weapon = weapon_id
			if _shop_player:
				_shop_player.set("weapon", weapon_id)
				_shop_player.call("save_items")
		GameManager.floor_shop_items.remove_at(idx)
	elif itype == -3:
		# Healer's Salve — cure injuries and restore 3 HP
		if _shop_player:
			_shop_player.set("is_bleeding", false)
			_shop_player.set("is_limping",  false)
			_shop_player.call("save_items")
		GameManager.heal_hp(3)
		GameManager.player_is_bleeding = false
		GameManager.player_is_limping  = false
		GameManager.floor_shop_items.remove_at(idx)
	else:
		# Consumable purchase
		if _shop_player and _shop_player.has_method("add_item"):
			_shop_player.add_item(itype, si.get("count", 1))
			_shop_player.call("save_items")
	# Panel redraws automatically via _process; nothing else needed

func _leave_shop():
	_shop_active = false
	overlay.visible = false
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
		_shop_panel = null
	if _shop_player and _shop_player.has_method("save_items"):
		_shop_player.call("save_items")
	_shop_player = null
	GameManager.leave_shop()

# ── Equip screen (now delegates to InventoryScreen) ──────────────────────────
func _open_equip():
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	if _inv_screen == null or not is_instance_valid(_inv_screen):
		_inv_screen = CanvasLayer.new()
		_inv_screen.set_script(load("res://InventoryScreen.gd"))
		add_child(_inv_screen)
	_inv_screen.open(player)
	GameManager.state = GameManager.State.EQUIPPING

func _close_equip():
	if _inv_screen and is_instance_valid(_inv_screen):
		_inv_screen.close()
	GameManager.state = GameManager.State.PLAYING

# ── Per-frame update ──────────────────────────────────────────────────────────
func _process(delta):
	_hud_t += delta
	if GameManager.state == GameManager.State.PASSIVE_PICK:
		return
	if GameManager.state == GameManager.State.SHOPPING:
		_refresh_shop_ui()
		return
	if GameManager.state == GameManager.State.EQUIPPING:
		return
	if GameManager.state != GameManager.State.PLAYING:
		return

	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	# ── Top-center: alert / loot / floor name ────────────────────────────────
	var has_loot: bool = player.get("has_loot") == true
	var any_alert := false
	for guard in get_tree().get_nodes_in_group("guards"):
		if guard.get("alert_state") == 2:
			any_alert = true
			break

	var is_sneaking: bool = player.get("is_sneaking") == true
	if any_alert:
		status_label.text = "!! ALERT !!"
		status_label.modulate = Color(1.0, 0.15, 0.15)
	elif has_loot:
		var is_final := GameManager.current_floor >= GameManager.MAX_FLOORS
		status_label.text = "ESCAPE NOW" if is_final else "→ SUPPLY CACHE"
		status_label.modulate = Color(0.3, 1.0, 0.5)
	elif is_sneaking:
		status_label.text = "— SNEAKING —"
		status_label.modulate = Color(0.50, 0.80, 1.0)
	else:
		status_label.text = GameManager.get_floor_name()
		status_label.modulate = Color(0.65, 0.60, 0.50)

	# ── Top-right: gold ──────────────────────────────────────────────────────
	gold_label.text = "⬡ %d gp" % GameManager.gold_collected

	# ── Left panel: trigger redraw (class/floor/HP) ──────────────────────────
	if _hud_panel:
		_hud_panel.set_meta("has_loot", has_loot)
		_hud_panel.custom_minimum_size = Vector2(224, 124 if GameManager.combo_hits > 0 else 108)
		_hud_panel.queue_redraw()

	# ── Mini-map: trigger redraw ──────────────────────────────────────────────
	if _mini_map:
		_mini_map.set_meta("player", player)
		_mini_map.queue_redraw()

	# ── Threat bar: wanted + injury + heat ───────────────────────────────────
	if _threat_bar:
		_threat_bar.set_meta("hud_t", _hud_t)
		_threat_bar.set_meta("player", player)
		_threat_bar.queue_redraw()

	# ── Styled item boxes ─────────────────────────────────────────────────────
	var equipped: Array = []
	var all_items: Array = []
	if player.has_method("get_equipped_list"):
		equipped = player.call("get_equipped_list")
		all_items = player.call("get_item_list")
	for i in range(_item_boxes.size()):
		var box = _item_boxes[i]
		var itype: int = equipped[i] if i < equipped.size() else -1
		var count := 0
		if itype != -1:
			for item in all_items:
				if item.get("type", -1) == itype:
					count = item.get("count", 0)
					break
		box.set_meta("item_type", itype)
		box.set_meta("item_count", count)
		box.set_meta("hud_t", _hud_t)
		box.queue_redraw()

	# ── Objective (bottom-right) ──────────────────────────────────────────────
	var obj_label := $Control.get_node_or_null("ObjectiveLabel") as Label
	if obj_label and GameManager.floor_objective != "NONE":
		var done := GameManager.check_objective_complete()
		var marker := "✓" if done else "○"
		obj_label.text = "%s  %s  +%d gp" % [marker, GameManager.floor_objective_name, GameManager.floor_objective_bonus]
		obj_label.modulate = Color(0.40, 1.00, 0.45, 0.90) if done else Color(0.70, 0.70, 0.55, 0.70)
	elif obj_label:
		obj_label.text = ""

	# ── Ability label (bottom-left, above item boxes) ─────────────────────────
	var ab_lbl := $Control.get_node_or_null("AbilityLabel") as Label
	if ab_lbl:
		var race_data: Dictionary = GameManager.RACES.get(GameManager.selected_race, {})
		var racial_cd = player.get("racial_cooldown")
		var class_cd  = player.get("ability_cooldown")
		var race_has_ability := not race_data.is_empty()
		if race_has_ability and racial_cd != null:
			var aname: String = race_data.get("ability_name", "Racial")
			if float(racial_cd) <= 0.0:
				ab_lbl.text = "[Q/L3] %s  — READY" % aname
				ab_lbl.modulate = Color(0.70, 0.55, 1.00, 0.90)
			else:
				ab_lbl.text = "[Q/L3] %s  — %.0fs" % [aname, float(racial_cd)]
				ab_lbl.modulate = Color(0.50, 0.42, 0.65, 0.55)
		elif class_cd != null:
			var aname := _class_ability_name()
			if float(class_cd) <= 0.0:
				ab_lbl.text = "[Q/L3] %s  — READY" % aname
				ab_lbl.modulate = Color(0.65, 0.48, 1.00, 0.80)
			else:
				ab_lbl.text = "[Q/L3] %s  — %.0fs" % [aname, float(class_cd)]
				ab_lbl.modulate = Color(0.50, 0.46, 0.55, 0.55)
		else:
			ab_lbl.text = ""

	# ── Weapon label ──────────────────────────────────────────────────────────
	var wpn_lbl := $Control.get_node_or_null("WeaponLabel") as Label
	if wpn_lbl:
		var wpn: String = player.get("weapon") if player.get("weapon") else "NONE"
		var wpn_data: Dictionary = GameManager.WEAPONS.get(wpn, {})
		var wpn_name: String = wpn_data.get("name", wpn)
		var wpn_tags: Array = wpn_data.get("tags", [])
		var extra := ""
		var special_hint := ""
		if wpn in ["CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT"]:
			var bolts = player.get("_crossbow_bolts")
			extra = "  [%d bolts]" % int(bolts) if bolts != null else ""
			special_hint = "  R:Fire"
		elif wpn == "SHIV":
			var thrown = player.get("_shiv_thrown")
			extra = "  [spent]" if thrown == true else "  [ready]"
			special_hint = "  R:Throw"
		elif wpn in ["STILETTO", "ASSASSIN_FANG"]:
			var throws_left = player.get("_stiletto_throws_left")
			extra = "  [%d throws]" % int(throws_left) if throws_left != null else ""
			special_hint = "  R:Throw"
		elif wpn == "VENOM_NEEDLE":
			var uses_left = player.get("_venom_needle_uses_left")
			extra = "  [%d uses]" % int(uses_left) if uses_left != null else ""
			special_hint = "  R:Needle"
		elif wpn == "RUNED_BLADE":
			var charges = player.get("_runed_blade_charges")
			extra = "  [%d/3 charges]" % int(charges) if charges != null else ""
			special_hint = "  R:Step(3)"
		var tag_str := ""
		if not wpn_tags.is_empty():
			var ts: Array[String] = []
			for tg in wpn_tags: ts.append(str(tg))
			tag_str = "  ·  " + "  ".join(ts)
		var key_str := "  🔑" if (player.has_method("count_item") and player.count_item(9) > 0) else ""
		wpn_lbl.text = "⚔ %s%s%s%s%s  [TAB] Loadout" % [wpn_name, extra, tag_str, key_str, special_hint]

func _input(event):
	var is_key:  bool = event is InputEventKey
	var is_joy:  bool = event is InputEventJoypadButton
	var is_axis: bool = event is InputEventJoypadMotion
	if not (is_key or is_joy or is_axis):
		return
	var pressed: bool
	if is_key:
		pressed = event.pressed and not (event as InputEventKey).echo
	elif is_joy:
		pressed = event.pressed
	else:
		pressed = true  # JoypadMotion — action_pressed handles deadzone
	if not pressed:
		return

	if GameManager.state == GameManager.State.EQUIPPING:
		# InventoryScreen handles its own input via _unhandled_input.
		# HUD only handles the close shortcut here as a fallback.
		if event.is_action_pressed("menu_equip") or event.is_action_pressed("menu_confirm"):
			_close_equip()
			AudioManager.ui_confirm()
			get_viewport().set_input_as_handled()
		return
	if _passive_active:
		if event.is_action_pressed("menu_slot_1"):   _pick_passive(0); AudioManager.ui_confirm()
		elif event.is_action_pressed("menu_slot_2"): _pick_passive(1); AudioManager.ui_confirm()
		elif event.is_action_pressed("menu_slot_3"): _pick_passive(2); AudioManager.ui_confirm()
		elif event.is_action_pressed("menu_confirm"): _pick_passive(99); AudioManager.ui_confirm()
		return
	if _shop_active:
		if event.is_action_pressed("menu_slot_1"):    _shop_buy(0); AudioManager.ui_confirm()
		elif event.is_action_pressed("menu_slot_2"):  _shop_buy(1); AudioManager.ui_confirm()
		elif event.is_action_pressed("menu_slot_3"):  _shop_buy(2); AudioManager.ui_confirm()
		elif event.is_action_pressed("menu_confirm"): _leave_shop();  AudioManager.ui_confirm()
		elif event.is_action_pressed("menu_back"):    _leave_shop();  AudioManager.ui_confirm()
		return
	if GameManager.state == GameManager.State.PLAYING:
		var open_inv: bool = event.is_action_pressed("menu_equip")
		if not open_inv and is_joy:
			open_inv = (event as InputEventJoypadButton).button_index == JOY_BUTTON_RIGHT_SHOULDER
		if open_inv:
			_open_equip()
			get_viewport().set_input_as_handled()
			return
	if GameManager.state != GameManager.State.PLAYING:
		if event.is_action_pressed("menu_back"):
			GameManager.go_to_class_select()

func _class_ability_name() -> String:
	var rd: Dictionary = GameManager.RACES.get(GameManager.selected_race, {})
	if not rd.is_empty():
		return rd.get("ability_name", "Racial")
	match GameManager.selected_class:
		"CUTPURSE":     return "Pickpocket"
		"SHADOWDANCER": return "Shadow Step"
		"ASSASSIN":     return "Mark Target"
	return "Ability"

func _on_state_changed(new_state: GameManager.State):
	if new_state in [GameManager.State.SHOPPING, GameManager.State.PASSIVE_PICK, GameManager.State.EQUIPPING]:
		return
	overlay.visible = true
	overlay_title.add_theme_font_size_override("font_size", 52)
	overlay_desc.add_theme_font_size_override("font_size", 14)
	overlay_desc.set_offset(SIDE_LEFT, -160)
	overlay_desc.set_offset(SIDE_RIGHT, 160)
	var net_gold := GameManager.gold_collected - GameManager.gold_spent
	var stats_text := "Time: %s   Takedowns: %d   Gold: %d gp" % [
		GameManager.format_time(), GameManager.takedowns, net_gold
	]

	match new_state:
		GameManager.State.CAUGHT:
			overlay.color = Color(0.5, 0.0, 0.0, 0.85)
			overlay_title.text = "CAUGHT"
			overlay_title.modulate = Color(1.0, 0.3, 0.3)
			overlay_rating.text = ""
			overlay_rating.modulate = Color(1.0, 1.0, 1.0)
			overlay_desc.text = "You didn't make it out."
			overlay_stats.text = stats_text
			overlay_hint.text = "[R / Start]  Return to Guild"
			overlay_hint.modulate = Color(0.55, 0.50, 0.45)
		GameManager.State.ESCAPED:
			var is_finale := GameManager.current_floor > GameManager.MAX_FLOORS
			overlay_rating.text = GameManager.get_rating()
			if is_finale:
				overlay.color = Color(0.08, 0.05, 0.18, 0.94)
				overlay_title.text = "THE JOB IS DONE"
				overlay_title.modulate = Color(0.95, 0.80, 0.20)
				overlay_rating.modulate = Color(1.0, 0.88, 0.20)
				var relic_name := GameManager.floor_loot_name if GameManager.floor_loot_name != "" else "the relic"
				overlay_desc.text = "You delivered \"%s\" to The Broker's contact before dawn.\n\n%s\n\n%s" % [
					relic_name,
					GameManager.get_rating_description(),
					GameManager.get_story_sign_off(),
				]
			else:
				overlay.color = Color(0.0, 0.22, 0.08, 0.88)
				overlay_title.text = "ESCAPED"
				overlay_title.modulate = Color(0.3, 1.0, 0.5)
				overlay_rating.modulate = Color(0.95, 0.85, 0.45)
				var sign_off: String = GameManager.get_story_sign_off()
				var rating_desc: String = GameManager.get_rating_description()
				overlay_desc.text = rating_desc + ("\n\n" + sign_off if not sign_off.is_empty() else "")
			var rep_gain := GameManager.get_pending_rep_gain()
			var contract_line := ""
			if GameManager.active_contract != "NONE":
				if GameManager.check_contract_complete():
					GameManager.add_gold(GameManager.contract_bonus)
					contract_line = "\n✓ CONTRACT: %s  (+%d gp)" % [
						GameManager.contract_name, GameManager.contract_bonus]
				else:
					contract_line = "\n✗ CONTRACT FAILED: %s" % GameManager.contract_name
			overlay_stats.text = stats_text + \
				"\nFloors: %d/%d   Alerts: %d   Escalation: +%d" % [
					GameManager.current_floor, GameManager.MAX_FLOORS,
					GameManager.times_alerted, GameManager.alert_escalation] + \
				"\nGuild Rep: %d  (+%d this run)" % [GameManager.guild_rep, rep_gain] + \
				contract_line
			overlay_stats.modulate = Color(0.75, 0.72, 0.65)
			var next_unlock := GameManager.get_next_guild_unlock()
			var unlock_hint := ""
			if not next_unlock.is_empty():
				unlock_hint = "\nNext unlock at %d rep: %s" % [next_unlock.rep, next_unlock.name]
			overlay_hint.text = "[R / Start]  Return to Guild" + unlock_hint
			overlay_hint.modulate = Color(0.55, 0.50, 0.45)
