extends CharacterBody2D

const TILE_SIZE = 16

const _ripple_scene   = preload("res://NoiseRipple.tscn")
const _smoke_scene    = preload("res://SmokeCloud.tscn")
const _silence_scene  = preload("res://SilenceZone.tscn")
const _dice_scene     = preload("res://DicePopup.tscn")

enum NoiseLevel { SILENT, QUIET, LOUD }
enum ItemType   { COIN, SMOKE, DART, ROPE, FLASH, HOLD, SILENCE, TOOLS, SHADOW_OIL, KEY }

const ITEM_DATA := {
	ItemType.COIN:       { "name": "Gold Piece",        "color": Color(0.95, 0.80, 0.10) },
	ItemType.SMOKE:      { "name": "Alchemist's Smoke", "color": Color(0.55, 0.90, 0.45) },
	ItemType.DART:       { "name": "Soporific Dart",    "color": Color(0.30, 0.70, 0.95) },
	ItemType.ROPE:       { "name": "Silk Rope",         "color": Color(0.75, 0.55, 0.95) },
	ItemType.FLASH:      { "name": "Flash Powder",      "color": Color(1.00, 0.95, 0.70) },
	ItemType.HOLD:       { "name": "Hold Person",       "color": Color(0.55, 0.35, 0.90) },
	ItemType.SILENCE:    { "name": "Silence Scroll",    "color": Color(0.30, 0.20, 0.55) },
	ItemType.TOOLS:      { "name": "Thieves' Tools",    "color": Color(0.70, 0.55, 0.30) },
	ItemType.SHADOW_OIL: { "name": "Shadow Cloak",      "color": Color(0.20, 0.15, 0.35) },
	ItemType.KEY:        { "name": "Iron Key",           "color": Color(0.90, 0.75, 0.20) },
}

signal noise_emitted(level: NoiseLevel, world_position: Vector2)

var is_sneaking       := false
var has_loot          := false
var is_hidden         := false
var is_carrying_body  := false
var facing            := Vector2.RIGHT
var items: Array[Dictionary] = []
var equipped: Array[int] = [-1, -1, -1]   # item type in each slot, -1 = empty
var _move_cooldown    := 0.0
var _shake_intensity  := 0.0
var _shake_timer      := 0.0
var _shake_offset     := Vector2.ZERO
var _hiding_spot      = null
var _carried_body     = null

# Class ability
var ability_cooldown  := 0.0
var racial_cooldown   := 0.0
var _assassin_mark: Node = null

# Assassin: show patrol paths for 5s at floor start
var _patrol_reveal_timer := 0.0
const PATROL_REVEAL_DURATION := 5.0

# Shadow Cloak Oil timer
var _shadow_oil_timer := 0.0

# Class balance tracking
var _shadowdancer_silent_kills := 0   # resets each floor; 3rd+ wakes nearby guard
var _cutpurse_free_item_used   := false  # Sleight of Hand — first item per floor is free

# Weapon
var weapon                   := "NONE"
var _shiv_thrown              := false   # SHIV: once-per-floor throw
var _stiletto_throws_left     := 0       # STILETTO: 2/floor
var _crossbow_bolts           := 3       # resets per floor; REPEATING=5, SILENT_BOLT=999
var _ghost_blade_strikes_left := 0       # GHOST_BLADE: 3/floor; VOID_REAPER: 5/floor
var _venom_needle_uses_left   := 2       # VENOM_NEEDLE
var _runed_blade_charges      := 0       # RUNED_BLADE: fills on kills, 3=shadow step
var _garrote_hold_timer       := 0.0     # GARROTE: requires 2s hold on target

# Gear slots
var gear: Dictionary = { "boots": "", "cloak": "", "offhand": "", "trinket": "" }

# Injury state — synced from/to GameManager across floors
var is_bleeding := false   # emits quiet noise every 3s
var is_limping  := false   # walk cooldown +40%
var _bleed_timer := 0.0
const BLEED_INTERVAL := 3.0
var _quicksilver_active := false
var _quicksilver_timer  := 0.0

# Keys collected this floor — consumed by interacting with LockedDoor nodes
var keys: Array[int] = []

# Hit flash
var _hit_flash_timer := 0.0
const _HIT_FLASH_DURATION := 0.4

# Weapon swap spam guard
var _weapon_swap_cooldown := 0.0

# Combat attack
var _attack_cooldown := 0.0

const ABILITY_COOLDOWNS := { "CUTPURSE": 8.0, "SHADOWDANCER": 12.0, "ASSASSIN": 15.0 }
const RACIAL_COOLDOWNS  := { "HALFLING": 0.0, "TIEFLING": 14.0, "WOOD_ELF": 18.0, "DWARF": 20.0 }

# Walk = fast but LOUD. Sneak = slow but QUIET (or silent with CUTPURSE passive).
const WALK_COOLDOWN  := 0.10
const SNEAK_COOLDOWN := 0.26

const SLOT_COUNT := 3

# ── Sprite animation ─────────────────────────────────────────────────────────
const _SPRITE_SHEET   := "res://sprites/player_sheet.png"
const _SPRITE_HFRAMES := 8    # 4 dirs × 2 walk frames
const _SPRITE_VFRAMES := 12   # 3 classes × 4 races
const _SPRITE_WALK_SPD := 8.0 # frames per second while moving

const _CLASS_ROW  := { "CUTPURSE": 0, "SHADOWDANCER": 4, "ASSASSIN": 8 }
const _RACE_ROW   := { "HALFLING": 0, "TIEFLING": 1, "WOOD_ELF": 2, "DWARF": 3 }
const _DIR_COL    := { "DOWN": 0, "LEFT": 2, "RIGHT": 4, "UP": 6 }

var _sprite: Sprite2D = null
var _walk_frame    := 0

func _ready():
	_init_items()
	gear = GameManager.get_start_gear()
	reset_floor_charges()
	GameManager.screen_shake.connect(_on_screen_shake)
	_setup_sprite()
	# Load injury state carried from previous floor
	is_bleeding = GameManager.player_is_bleeding
	is_limping  = GameManager.player_is_limping
	# Assassin: reveal patrol paths on floor start
	if GameManager.selected_class == "ASSASSIN":
		_patrol_reveal_timer = PATROL_REVEAL_DURATION
		_popup("RECONNAISSANCE: patrol routes revealed", Color(0.85, 0.15, 0.15))

func _setup_sprite():
	var tex := load(_SPRITE_SHEET) as Texture2D
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.texture   = tex
	_sprite.hframes   = _SPRITE_HFRAMES
	_sprite.vframes   = _SPRITE_VFRAMES
	_sprite.offset    = Vector2(0, -4)   # shift sprite up so feet align with physics body
	_sprite.centered       = true
	_sprite.z_index        = 0
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_update_sprite_frame()

func _get_facing_dir() -> String:
	var f := facing.normalized()
	if abs(f.x) >= abs(f.y):
		return "RIGHT" if f.x > 0 else "LEFT"
	else:
		return "DOWN" if f.y > 0 else "UP"

func _update_sprite_frame():
	if _sprite == null:
		return
	var cls  := GameManager.selected_class
	var race := GameManager.selected_race
	var dir  := _get_facing_dir()
	var row: int = _CLASS_ROW.get(cls, 0) + _RACE_ROW.get(race, 0)
	var col: int = _DIR_COL.get(dir, 0) + _walk_frame
	_sprite.frame = row * _SPRITE_HFRAMES + col
	# Visual state modulation
	if is_hidden:
		_sprite.modulate = Color(1, 1, 1, 0.18)
	elif is_sneaking:
		_sprite.modulate = Color(0.75, 0.80, 1.0, 0.72)
	else:
		_sprite.modulate = Color.WHITE

func _on_screen_shake(intensity: float, duration: float):
	_shake_intensity = intensity
	_shake_timer = duration

func _init_items():
	# Weapon — carry forward if returning from a previous floor
	if GameManager.floor_carry_weapon != "NONE":
		weapon = GameManager.floor_carry_weapon
	else:
		weapon = GameManager.CLASS_WEAPONS.get(GameManager.selected_class, "NONE")

	var carry := GameManager.get_start_items()
	if not carry.is_empty():
		for entry in carry:
			items.append({ "type": entry["type"], "count": entry["count"] })
		var saved_eq: Array[int] = GameManager.get_start_equipped()
		if saved_eq.size() == SLOT_COUNT:
			equipped = saved_eq.duplicate()
		else:
			_auto_equip_all()
		return
	var cls = GameManager.CLASSES.get(GameManager.selected_class, GameManager.CLASSES["CUTPURSE"])
	for entry in cls.items:
		items.append({ "type": entry["type"], "count": entry["count"] })
	_auto_equip_all()

func reset_floor_charges():
	_shiv_thrown               = false
	_stiletto_throws_left      = 2
	match weapon:
		"CROSSBOW":           _crossbow_bolts = 3
		"REPEATING_CROSSBOW": _crossbow_bolts = 5
		"SILENT_BOLT":        _crossbow_bolts = 999
		_:                    _crossbow_bolts = 3
	match weapon:
		"GHOST_BLADE":  _ghost_blade_strikes_left = 3
		"VOID_REAPER":  _ghost_blade_strikes_left = 5
		_:              _ghost_blade_strikes_left = 0
	_venom_needle_uses_left    = GameManager._venom_needle_uses
	_runed_blade_charges       = GameManager._runed_blade_charges
	_shadowdancer_silent_kills = 0
	_cutpurse_free_item_used   = false
	keys                       = []
	# QUICKSILVER FLASK: recharge per-floor active ability
	_quicksilver_active        = false
	_quicksilver_timer         = 0.0

func _auto_equip_all():
	equipped = [-1, -1, -1]
	var slot := 0
	for item in items:
		if slot >= SLOT_COUNT:
			break
		equipped[slot] = item["type"]
		slot += 1

func add_item(item_type: int, count: int):
	for item in items:
		if item["type"] == item_type:
			item["count"] += count
			_auto_equip_type(item_type)
			return
	items.append({"type": item_type, "count": count})
	_auto_equip_type(item_type)

func _auto_equip_type(item_type: int):
	# Equip to first empty slot if not already equipped anywhere
	for e in equipped:
		if e == item_type:
			return
	for i in range(SLOT_COUNT):
		if equipped[i] == -1:
			equipped[i] = item_type
			return

func equip_type_to_slot(slot: int, item_type: int):
	if slot < 0 or slot >= SLOT_COUNT:
		return
	# Swap if item_type is already in another slot
	for i in range(SLOT_COUNT):
		if equipped[i] == item_type and i != slot:
			equipped[i] = equipped[slot]
			break
	equipped[slot] = item_type

func count_item(item_type: int) -> int:
	for item in items:
		if item["type"] == item_type:
			return item["count"]
	return 0

func remove_item(item_type: int, amount: int):
	for item in items:
		if item["type"] == item_type:
			item["count"] = max(0, item["count"] - amount)
			return

func add_key(_kid: int):
	add_item(ItemType.KEY, 1)
	_popup("KEY FOUND!", Color(0.90, 0.75, 0.20))

func has_key(_kid: int) -> bool:
	return count_item(ItemType.KEY) > 0

func use_key(_kid: int):
	remove_item(ItemType.KEY, 1)

func save_items():
	GameManager.save_player_items(items)
	GameManager.save_player_equipped(equipped)
	GameManager.save_player_weapon(weapon)
	GameManager.save_player_gear(gear)
	GameManager.player_is_bleeding = is_bleeding
	GameManager.player_is_limping  = is_limping

func get_item_list() -> Array:
	return items

func get_equipped_list() -> Array:
	return equipped

func get_gear_list() -> Dictionary:
	return gear

func has_gear(effect: String) -> bool:
	for slot in gear:
		var gid: String = gear[slot]
		if not gid.is_empty():
			var gdata: Dictionary = GameManager.GEAR.get(gid, {})
			if gdata.get("effect", "") == effect:
				return true
	return false

func equip_gear(slot: String, gear_id: String):
	gear[slot] = gear_id

func _process(delta):
	is_sneaking = Input.is_key_pressed(KEY_SHIFT) or Input.is_action_pressed("game_sneak")
	if not is_sneaking:
		for joypad in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(joypad, JOY_BUTTON_LEFT_SHOULDER):
				is_sneaking = true
				break
	if _move_cooldown > 0.0:
		_move_cooldown -= delta
	if ability_cooldown > 0.0:
		ability_cooldown -= delta
	# Keep carried body attached to player
	if is_carrying_body and _carried_body and is_instance_valid(_carried_body):
		_carried_body.global_position = global_position + Vector2(4, -4)
	if racial_cooldown > 0.0:
		racial_cooldown -= delta
	if _patrol_reveal_timer > 0.0:
		_patrol_reveal_timer -= delta
		queue_redraw()
	if _quicksilver_active:
		_quicksilver_timer -= delta
		if _quicksilver_timer <= 0.0:
			_quicksilver_active = false
	if _shadow_oil_timer > 0.0:
		_shadow_oil_timer -= delta
		if _shadow_oil_timer <= 0.0:
			# Restore guard vision ranges
			for g in get_tree().get_nodes_in_group("guards"):
				g.set("vision_range", g.get("vision_range") + 20.0)
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0 and _sprite != null:
			_sprite.modulate = Color.WHITE
	if _weapon_swap_cooldown > 0.0:
		_weapon_swap_cooldown -= delta
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	# Bleeding: emit a quiet noise periodically; half-rate if BLOOD_VIAL equipped
	if is_bleeding and GameManager.state == GameManager.State.PLAYING:
		_bleed_timer -= delta
		if _bleed_timer <= 0.0:
			var interval := BLEED_INTERVAL * (2.0 if GameManager.has_gear_effect("BLEED_RESIST") else 1.0)
			_bleed_timer = interval
			if not is_hidden:
				emit_noise(NoiseLevel.QUIET)
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var r: float = _shake_intensity * (_shake_timer / max(_shake_timer + delta, 0.001))
		_shake_offset = Vector2(randf_range(-r, r), randf_range(-r, r))
		var cam := get_node_or_null("Camera2D") as Camera2D
		if cam:
			cam.offset = _shake_offset
	elif _shake_offset != Vector2.ZERO:
		_shake_offset = Vector2.ZERO
		var cam := get_node_or_null("Camera2D") as Camera2D
		if cam:
			cam.offset = Vector2.ZERO

	# Joypad held-direction movement (keyboards get echo events; joypads don't)
	if GameManager.state == GameManager.State.PLAYING and _move_cooldown <= 0.0:
		var dir := Vector2.ZERO
		if Input.is_action_pressed("ui_right"): dir = Vector2.RIGHT
		elif Input.is_action_pressed("ui_left"):  dir = Vector2.LEFT
		elif Input.is_action_pressed("ui_up"):    dir = Vector2.UP
		elif Input.is_action_pressed("ui_down"):  dir = Vector2.DOWN
		# Only apply if input came from a joypad (keyboard movement handled by echo events)
		if dir != Vector2.ZERO and Input.get_connected_joypads().size() > 0 \
				and not Input.is_key_pressed(KEY_UP) and not Input.is_key_pressed(KEY_DOWN) \
				and not Input.is_key_pressed(KEY_LEFT) and not Input.is_key_pressed(KEY_RIGHT):
			if is_hidden:
				_hiding_spot.release(self)
			else:
				facing = dir
				var target: Vector2 = position + dir * TILE_SIZE
				if not is_position_blocked(target):
					position = target
					_emit_movement_noise()
				var base_walk: float  = WALK_COOLDOWN  * (0.80 if GameManager.has_passive("QUICK_HANDS") else 1.0)
				var base_sneak: float = SNEAK_COOLDOWN * (0.80 if GameManager.has_passive("QUICK_HANDS") else 1.0)
				var no_slow: bool = GameManager.has_passive("DEAD_WEIGHT") or has_gear("BODY_CARRY")
				var body_mult := (1.0 if no_slow else 1.4) if is_carrying_body else 1.0
				var limp_mult   := 1.4 if is_limping else 1.0
				var speed_mult  := 0.55 if _quicksilver_active else 1.0
				_move_cooldown = (base_sneak if (is_sneaking or is_carrying_body) else base_walk) * body_mult * limp_mult * speed_mult
				_walk_frame = (_walk_frame + 1) % 2

	_update_sprite_frame()
	queue_redraw()

func _unhandled_input(event):
	if GameManager.state != GameManager.State.PLAYING:
		return
	var is_key_press:  bool = event is InputEventKey and event.pressed
	var is_joy_press:  bool = event is InputEventJoypadButton and event.pressed
	var is_axis_press: bool = event is InputEventJoypadMotion
	if not (is_key_press or is_joy_press or is_axis_press):
		return

	# One-shot action keys (key echoes already excluded by is_key_press; guard axis repeats via deadzone)
	if not (event is InputEventKey and (event as InputEventKey).echo):
		if event.is_action_pressed("game_interact"):
			if is_hidden:
				_hiding_spot.release(self)
			else:
				_try_interact()
			return
		if event.is_action_pressed("game_takedown"):       _try_takedown();           return
		if event.is_action_pressed("game_weapon_special"): _use_weapon_special();     return
		if event.is_action_pressed("game_item_1"):         _use_item(0);              return
		if event.is_action_pressed("game_item_2"):         _use_item(1);              return
		if event.is_action_pressed("game_item_3"):         _use_item(2);              return
		if event.is_action_pressed("game_offhand"):        _try_use_offhand_active(); return
		if event.is_action_pressed("game_ability"):        _use_class_ability();      return

	# Exit hiding on any movement attempt
	if is_hidden:
		var moved: bool = event.is_action_pressed("ui_right", true) or \
			event.is_action_pressed("ui_left", true) or \
			event.is_action_pressed("ui_up", true) or \
			event.is_action_pressed("ui_down", true)
		if moved:
			_hiding_spot.release(self)
		return

	# Movement — gated by cooldown
	if _move_cooldown > 0.0:
		return
	var direction = Vector2.ZERO
	if event.is_action_pressed("ui_right", true):  direction = Vector2.RIGHT
	elif event.is_action_pressed("ui_left",  true): direction = Vector2.LEFT
	elif event.is_action_pressed("ui_up",    true): direction = Vector2.UP
	elif event.is_action_pressed("ui_down",  true): direction = Vector2.DOWN

	if direction != Vector2.ZERO:
		facing = direction
		var target = position + direction * TILE_SIZE
		if not is_position_blocked(target):
			position = target
			_emit_movement_noise()
		var base_walk: float  = WALK_COOLDOWN  * (0.80 if GameManager.has_passive("QUICK_HANDS") else 1.0)
		var base_sneak: float = SNEAK_COOLDOWN * (0.80 if GameManager.has_passive("QUICK_HANDS") else 1.0)
		var no_slow: bool = GameManager.has_passive("DEAD_WEIGHT") or has_gear("BODY_CARRY")
		var body_mult := (1.0 if no_slow else 1.4) if is_carrying_body else 1.0
		var limp_mult := 1.4 if is_limping else 1.0
		_move_cooldown = (base_sneak if (is_sneaking or is_carrying_body) else base_walk) * body_mult * limp_mult
		_walk_frame = (_walk_frame + 1) % 2

# ── Interaction ───────────────────────────────────────────────────────────────
func _try_interact():
	if is_carrying_body:
		# While carrying: hiding spot dumps body, anywhere else drops it
		for spot in get_tree().get_nodes_in_group("hiding_spots"):
			if spot.has_method("is_in_range") and spot.is_in_range(global_position):
				if spot.has_method("accept_body"):
					spot.accept_body(_carried_body)
					_carried_body = null
					is_carrying_body = false
					_popup("Body concealed", Color(0.45, 0.80, 0.45))
					AudioManager.body_drop()
					return
		_drop_body()
		return
	# Check for nearby bodies to pick up first
	for body in get_tree().get_nodes_in_group("bodies"):
		if not is_instance_valid(body):
			continue
		if global_position.distance_to(body.global_position) <= 28.0:
			if not body.get_meta("being_carried", false):
				_pickup_body(body)
				return
	# Normal interactables — try the closest one first so doors/loot beat curtains/traps
	var in_range: Array = []
	for obj in get_tree().get_nodes_in_group("interactable"):
		if obj.has_method("is_in_range") and obj.is_in_range(global_position):
			in_range.append(obj)
	in_range.sort_custom(func(a, b):
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	for obj in in_range:
		if obj.has_method("interact"):
			obj.interact(self)
		return

func _pickup_body(body: Node):
	_carried_body = body
	is_carrying_body = true
	body.set_meta("being_carried", true)
	_popup("Seized body", Color(0.85, 0.55, 0.30))
	AudioManager.body_pickup()

func _drop_body():
	if _carried_body and is_instance_valid(_carried_body):
		_carried_body.global_position = global_position
		_carried_body.remove_meta("being_carried")
		_carried_body = null
	is_carrying_body = false
	emit_noise(NoiseLevel.QUIET)
	_popup("Body dropped", Color(0.70, 0.50, 0.30))
	AudioManager.body_drop()

func pickup_loot():
	has_loot = true
	emit_noise(NoiseLevel.QUIET)

func enter_hiding_spot(spot):
	_hiding_spot = spot
	is_hidden    = true
	queue_redraw()

func exit_hiding_spot():
	_hiding_spot = null
	is_hidden    = false
	queue_redraw()

# ── Takedown (d20 mechanic) ───────────────────────────────────────────────────
func _try_takedown():
	# Alert-state guards use combat attack instead of stealth takedown
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) > 24.0:
			continue
		if guard.alert_state == guard.AlertState.ALERT:
			_do_combat_attack()
			return
		_resolve_takedown(guard)
		return
	# No adjacent guard — still fire combat attack for ranged/AoE weapons
	var cdata: Dictionary = GameManager.WEAPON_COMBAT.get(weapon, GameManager.WEAPON_COMBAT["NONE"])
	if cdata["shape"] in ["bolt", "orb", "slash", "thrust"]:
		_do_combat_attack()

func _resolve_takedown(guard):
	var raw_behind := _is_behind_guard(guard)
	var cls        := GameManager.selected_class

	# ASSASSIN'S FANG: all attacks treated as rear
	var behind := raw_behind or (weapon == "ASSASSIN_FANG")

	# ASSASSIN mark: auto-execute regardless of position/dice
	if _assassin_mark != null and is_instance_valid(_assassin_mark) and _assassin_mark == guard:
		_assassin_mark.remove_meta("is_marked")
		_assassin_mark = null
		_popup("MARKED EXECUTION", Color(1.0, 0.15, 0.15))
		guard.takedown(true)
		GameManager.record_takedown()
		_post_kill_effects(guard, true)
		_spawn_attack_anim(true)
		GameManager.shake(2.5, 0.20)
		AudioManager.takedown()
		return

	# ── Shadow weapon line ────────────────────────────────────────────────────────
	if weapon in ["SHADOW_BLADE", "GHOST_BLADE", "VOID_REAPER"]:
		var in_darkness := true
		for g in get_tree().get_nodes_in_group("guards"):
			if g != guard and g.get("alert_state") == 2:
				in_darkness = false; break
		# Phantom strike: GHOST/VOID skip d20 regardless of light (limited uses)
		var phantom := weapon in ["GHOST_BLADE", "VOID_REAPER"] and _ghost_blade_strikes_left > 0
		if phantom: _ghost_blade_strikes_left -= 1
		if (behind and in_darkness) or phantom:
			var lbl := ("PHANTOM STRIKE (%d left)" % _ghost_blade_strikes_left) if phantom \
				else "SHADOW BLADE — Backstab!"
			_popup(lbl, Color(0.55, 0.30, 0.95))
			# VOID_REAPER: erase the body, no evidence
			var silent := true
			if weapon == "VOID_REAPER":
				# Override: tell the guard not to spawn a body marker
				guard.set_meta("no_body", true)
			guard.takedown(silent)
			GameManager.record_takedown()
			_post_kill_effects(guard, true)
			_spawn_attack_anim(true)
			GameManager.shake(2.0, 0.18)
			AudioManager.takedown()
			return

	# ── GARROTE ──────────────────────────────────────────────────────────────────
	if weapon == "GARROTE":
		if behind:
			_popup("GARROTE — silent kill", Color(0.72, 0.68, 0.60))
			guard.takedown(true)
			GameManager.record_takedown()
			_post_kill_effects(guard, true)
			_spawn_attack_anim(true)
			GameManager.shake(2.0, 0.18)
			AudioManager.takedown()
			return
		# Frontal garrote: -4 penalty handled in roll section

	# ── SHADOWDANCER class: sneak cap ────────────────────────────────────────────
	if cls == "SHADOWDANCER" and is_sneaking:
		_shadowdancer_silent_kills += 1
		if _shadowdancer_silent_kills <= 2:
			_popup("PHANTOM STRIKE  (%d/2)" % _shadowdancer_silent_kills, Color(0.55, 0.30, 0.95))
			guard.takedown(true)
			GameManager.record_takedown()
			_post_kill_effects(guard, true)
			_spawn_attack_anim(true)
			GameManager.shake(2.0, 0.18)
			AudioManager.takedown()
			return
		else:
			_popup("OVERDONE — nearby guard alerted!", Color(0.90, 0.45, 0.15))
			guard.takedown(false)
			GameManager.record_takedown()
			_spawn_attack_anim(false)
			GameManager.shake(3.5, 0.28)
			AudioManager.takedown()
			for g in get_tree().get_nodes_in_group("guards"):
				if g != guard and global_position.distance_to(g.global_position) <= 80.0:
					if g.has_method("_become_suspicious"):
						g._become_suspicious(global_position)
					break
			return

	# ── Standard silent: behind or sneaking on unaware ───────────────────────────
	if behind or (is_sneaking and guard.alert_state == 0):
		# STILETTO: rear attacks always silent (SHIV too if sneaking)
		_popup("SILENT KILL", Color(0.30, 1.00, 0.50))
		guard.takedown(true)
		GameManager.record_takedown()
		_post_kill_effects(guard, true)
		_spawn_attack_anim(true)
		GameManager.shake(2.0, 0.18)
		AudioManager.takedown()
		return

	# ── d20 roll ─────────────────────────────────────────────────────────────────
	var roll1: int = randi_range(1, 20)
	var roll2: int = randi_range(1, 20)
	var has_advantage:    bool = behind or is_sneaking
	var has_disadvantage: bool = guard.get("alert_state") == 2  # ALERT
	var raw: int
	if has_advantage and not has_disadvantage:
		raw = max(roll1, roll2)
		_popup("Advantage! [%d, %d]" % [roll1, roll2], Color(0.50, 0.90, 0.50))
	elif has_disadvantage and not has_advantage:
		raw = min(roll1, roll2)
		_popup("Disadvantage! [%d, %d]" % [roll1, roll2], Color(0.90, 0.50, 0.50))
	else:
		raw = roll1

	var roll := raw
	roll += GameManager.get_d20_bonus()
	# Weapon modifiers
	if weapon in ["SHIV", "STILETTO"] and behind:   roll = min(20, roll + 2)
	if weapon == "STILETTO" and behind:              roll = min(20, roll + 1)  # extra +1 vs unaware
	if weapon == "GARROTE" and not behind:           roll = max(1, roll - 4)
	if weapon == "ASSASSIN_FANG":                    roll = min(20, roll + 3)
	# Gear modifiers
	if has_gear("SET_THIEF"):                        roll = min(20, roll + 3)
	if has_gear("PATROL_SIGHT"):                     roll = min(20, roll + 1)
	if GameManager.get_guild_unlock("MASTERTHIEF") and raw == 1:
		roll = max(roll, 5)
	if weapon == "ASSASSIN_FANG" and raw == 1:
		roll = max(roll, 5)

	# Natural 20
	if raw == 20:
		_popup("NAT 20! PERFECT KILL +100gp", Color(1.0, 0.88, 0.10))
		guard.takedown(true)
		GameManager.record_takedown(not behind)
		GameManager.add_gold(100)
		_post_kill_effects(guard, true)
		_spawn_attack_anim(true)
		GameManager.shake(1.8, 0.15)
		return

	# Natural 1 — critical fumble
	if raw == 1 and roll < 5:
		_popup("NAT 1! FUMBLE", Color(1.00, 0.15, 0.15))
		if guard.has_method("resist_takedown"):
			guard.resist_takedown()
		for g in get_tree().get_nodes_in_group("guards"):
			if g != guard and global_position.distance_to(g.global_position) <= 80.0:
				if g.has_method("_become_suspicious"):
					g._become_suspicious(global_position)
				break
		GameManager.shake(5.0, 0.40)
		return

	var threshold_clean := 6  if cls == "ASSASSIN" else (10 if GameManager.has_passive("ASSASSINS_EYE") else 15)
	var threshold_miss  := 4  if cls == "ASSASSIN" else 8

	if roll >= threshold_clean:
		# STILETTO tier2+: rear is always silent
		var silent_kill := behind and weapon in ["STILETTO", "ASSASSIN_FANG"]
		_popup("d20: %d  ✓ Clean%s" % [roll, " (silent)" if silent_kill else ""], Color(0.30, 1.00, 0.50))
		guard.takedown(silent_kill)
		GameManager.record_takedown(not behind)
		_post_kill_effects(guard, silent_kill)
		_spawn_attack_anim(silent_kill)
		GameManager.shake(2.0, 0.18)
		AudioManager.takedown()
	elif roll >= threshold_miss:
		_popup("d20: %d  ~ Messy" % roll, Color(1.00, 0.75, 0.20))
		guard.takedown(false)
		GameManager.record_takedown(not behind)
		_post_kill_effects(guard, false)
		_spawn_attack_anim(false)
		GameManager.shake(3.5, 0.28)
		AudioManager.takedown()
	else:
		# PARRYING DAGGER: failed takedown becomes a graze (no injury, no alert)
		if has_gear("PARRY"):
			_popup("d20: %d  PARRIED — Graze!" % roll, Color(0.70, 0.70, 0.78))
			if guard.has_method("_become_suspicious"):
				guard._become_suspicious(global_position)
			if guard.has_method("stagger"):
				guard.stagger(0.8)
			return
		# Dwarf Iron Will: save once per run
		if GameManager.selected_race == "DWARF" and not GameManager.iron_will_used:
			GameManager.iron_will_used = true
			_popup("d20: %d  IRON WILL — Graze!" % roll, Color(0.75, 0.55, 0.25))
			guard.takedown(false)
			GameManager.record_takedown(not behind)
			_spawn_attack_anim(false)
			GameManager.shake(2.5, 0.20)
			AudioManager.takedown()
		elif GameManager.has_passive("SECOND_WIND") and not GameManager.second_wind_used:
			GameManager.second_wind_used = true
			_popup("d20: %d  GRAZE — Second Wind!" % roll, Color(0.30, 0.80, 0.55))
			if guard.has_method("_become_suspicious"):
				guard._become_suspicious(global_position)
			if guard.has_method("stagger"):
				guard.stagger(0.8)
		else:
			_popup("d20: %d  ✗ Failed" % roll, Color(1.00, 0.25, 0.25))
			if weapon == "WAR_PICK":
				_popup("CLANG — LOUD!", Color(1.00, 0.50, 0.10))
				emit_noise(NoiseLevel.LOUD)
			if guard.has_method("resist_takedown"):
				guard.resist_takedown()
			if guard.has_method("stagger"):
				guard.stagger(0.8)
			if not is_bleeding:
				is_bleeding = true
				_popup("Bleeding!", Color(0.90, 0.20, 0.20))
			elif not is_limping:
				is_limping = true
				_popup("Limping!", Color(0.85, 0.55, 0.15))

func _do_combat_attack():
	var cdata: Dictionary = GameManager.WEAPON_COMBAT.get(weapon, GameManager.WEAPON_COMBAT["NONE"])
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = cdata["cooldown"]

	var shape: String = cdata["shape"]
	var damage: int   = cdata["damage"]

	if shape == "orb":
		_fire_wand_orb()
		_spawn_attack_anim(true)
		return

	if shape == "bolt":
		_fire_crossbow()
		return

	# Melee shapes: jab / slash / thrust
	var hit_guards := _get_attack_tiles(shape)
	var hit_any := false
	for guard in hit_guards:
		if guard.has_method("hurt"):
			guard.hurt(damage)
			hit_any = true

	var noise_r: float = cdata["noise_r"]
	if noise_r > 0.0:
		emit_noise(NoiseLevel.LOUD)
	else:
		emit_noise(NoiseLevel.QUIET)

	_spawn_attack_anim(noise_r == 0.0)
	if hit_any:
		GameManager.shake(1.8, 0.12)

func _get_attack_tiles(shape: String) -> Array:
	var guards_hit: Array = []
	var tile := TILE_SIZE

	for guard in get_tree().get_nodes_in_group("guards"):
		var to_g: Vector2 = guard.global_position - global_position

		match shape:
			"jab":
				# 1-tile hit in facing direction
				var dist := to_g.dot(facing)
				var perp: float = abs(to_g.dot(facing.rotated(PI * 0.5)))
				if dist >= 0.0 and dist <= tile * 1.2 and perp <= tile * 0.7:
					guards_hit.append(guard)
			"slash":
				# 3-wide fan — 140° arc, 1.5 tiles range
				if to_g.length() <= tile * 1.6:
					var angle := facing.angle_to(to_g.normalized())
					if abs(angle) <= deg_to_rad(70.0):
						guards_hit.append(guard)
			"thrust":
				# 2-tile straight ahead, narrow
				var dist := to_g.dot(facing)
				var perp: float = abs(to_g.dot(facing.rotated(PI * 0.5)))
				if dist >= 0.0 and dist <= tile * 2.2 and perp <= tile * 0.5:
					guards_hit.append(guard)

	return guards_hit

func _fire_wand_orb():
	if GameManager._wand_charges <= 0:
		_popup("No charges!", Color(0.55, 0.40, 0.85))
		return
	GameManager._wand_charges -= 1
	var orb_script = load("res://WandOrb.gd")
	var orb := Node2D.new()
	orb.set_script(orb_script)
	get_tree().root.add_child(orb)
	orb.global_position = global_position
	orb.setup(facing, 1)
	_popup("Orb fired! (%d left)" % GameManager._wand_charges, Color(0.55, 0.30, 0.95))

func _spawn_attack_anim(was_silent: bool):
	var anim_script = load("res://WeaponAttackAnim.gd")
	var n := Node2D.new()
	n.set_script(anim_script)
	get_tree().root.add_child(n)
	n.global_position = global_position
	n.setup(weapon, facing, was_silent)

func _use_weapon_special():
	match weapon:
		"SHIV":
			if not _shiv_thrown:
				_throw_shiv()
			else:
				_popup("Shiv already thrown this floor", Color(0.55, 0.50, 0.45))
		"STILETTO", "ASSASSIN_FANG":
			if _stiletto_throws_left > 0:
				_stiletto_throws_left -= 1
				_fire_thrown_blade(150.0, "STILETTO THROW  (%d left)" % _stiletto_throws_left,
					Color(0.80, 0.78, 0.85), true)
			else:
				_popup("No throws left this floor", Color(0.55, 0.50, 0.45))
		"CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT":
			_fire_crossbow()
		"VENOM_NEEDLE":
			if _venom_needle_uses_left > 0:
				_venom_needle_uses_left -= 1
				_fire_venom_needle()
			else:
				_popup("No venom needles left", Color(0.55, 0.50, 0.45))
		"RUNED_BLADE":
			if _runed_blade_charges >= 3:
				_runed_blade_charges = 0
				GameManager._runed_blade_charges = 0
				_runed_blade_shadow_step()
				_popup("RUNED BLADE — Shadow Step triggered!", Color(0.50, 0.20, 0.80))
			else:
				_popup("Runed Blade: %d/3 charges" % _runed_blade_charges, Color(0.60, 0.40, 0.85))
		_:
			_popup("No special for this weapon  [R / Y]", Color(0.55, 0.50, 0.45))

func _post_kill_effects(guard, was_silent: bool):
	# SMOKE_BLADE: silent kills release a 3s smoke cloud at guard position
	if weapon == "SMOKE_BLADE" and was_silent and is_instance_valid(guard):
		var cloud := _smoke_scene.instantiate()
		cloud.global_position = guard.global_position
		get_tree().root.add_child(cloud)
	# WAR_PICK: on kill, nearby guards lose detection; on failure also handled via WAR_PICK check below
	if weapon == "WAR_PICK" and is_instance_valid(guard):
		for g in get_tree().get_nodes_in_group("guards"):
			if g != guard and global_position.distance_to(g.global_position) <= 64.0:
				var dp: float = g.get("detection_progress") if g.get("detection_progress") != null else 0.0
				g.set("detection_progress", max(0.0, dp - 0.2))
	# RUNED_BLADE: charge up; 3 charges = shadow step
	if weapon == "RUNED_BLADE":
		_runed_blade_charges += 1
		GameManager._runed_blade_charges = _runed_blade_charges
		if _runed_blade_charges >= 3:
			_runed_blade_charges = 0
			GameManager._runed_blade_charges = 0
			_runed_blade_shadow_step()
	# SILENT_BOLT: reset nearby detection bars on every kill
	if weapon == "SILENT_BOLT" and was_silent:
		for g in get_tree().get_nodes_in_group("guards"):
			if g != guard and global_position.distance_to(g.global_position) <= 100.0:
				g.set("detection_progress", 0.0)
	# VOID_REAPER: drain nearby detection bars on soul harvest
	if weapon == "VOID_REAPER":
		for g in get_tree().get_nodes_in_group("guards"):
			if g != guard and global_position.distance_to(g.global_position) <= 80.0:
				var cur: float = g.get("detection_progress")
				g.set("detection_progress", max(0.0, cur - 0.3))
	# Wanted level: clear if all aware guards are gone and no bodies discovered
	GameManager.check_wanted_decay(get_tree())

func _runed_blade_shadow_step():
	# Find a dark tile (no torch in range) 3–6 tiles away
	var candidates: Array[Vector2] = []
	for attempt in range(20):
		var angle := randf() * TAU
		var dist  := float(randi_range(3, 6)) * 16.0
		var cand  := global_position + Vector2(cos(angle), sin(angle)) * dist
		var blocked := false
		for torch in get_tree().get_nodes_in_group("torches"):
			if torch.get("lit") and cand.distance_to(torch.global_position) < 40.0:
				blocked = true; break
		if not blocked:
			candidates.append(cand)
	if not candidates.is_empty():
		global_position = candidates[randi() % candidates.size()]
		_popup("RUNED BLADE — Shadow Step!", Color(0.50, 0.20, 0.80))
		GameManager.shake(1.5, 0.10)
		AudioManager.ability_use()

# ── Class abilities ───────────────────────────────────────────────────────────
func _use_class_ability():
	# Racial abilities share the Q key with a separate cooldown
	var race := GameManager.selected_race
	var race_cd: float = RACIAL_COOLDOWNS.get(race, 0.0)
	if race_cd > 0.0 or race == "HALFLING":
		if racial_cooldown > 0.0:
			_popup("Racial: %.0fs cooldown" % racial_cooldown, Color(0.55, 0.50, 0.45))
			return
		match race:
			"HALFLING":  _ability_lucky_break(); return
			"WOOD_ELF":  _ability_vanish();      return
			"DWARF":     _ability_battle_cry();  return
			"TIEFLING":  _ability_hellish_rebuke(); return
	if ability_cooldown > 0.0:
		_popup("Ability: %.0fs cooldown" % ability_cooldown, Color(0.55, 0.50, 0.45))
		return
	match GameManager.selected_class:
		"CUTPURSE":     _ability_pickpocket()
		"SHADOWDANCER": _ability_shadow_step()
		"ASSASSIN":     _ability_mark_target()

func _ability_pickpocket():
	# Adjacent unaware guard → pickpocket
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= 26.0:
			if guard.get("alert_state") == 0:
				var gold := randi_range(18, 48)
				GameManager.add_gold(gold)
				_popup("+%d gp  (pickpocket!)" % gold, ITEM_DATA[ItemType.COIN].color)
				AudioManager.coin_throw()
				ability_cooldown = ABILITY_COOLDOWNS["CUTPURSE"] * (0.70 if GameManager.has_passive("COLD_BLOOD") else 1.0)
				return
	_popup("No unaware mark in reach  [Q / L3]", Color(0.55, 0.50, 0.45))

func _throw_shiv():
	# One-per-floor: silent 80px ranged takedown in facing direction
	var shiv_range := 80.0
	var best_guard = null
	var best_dist  := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var to_guard: Vector2 = guard.global_position - global_position
		var dist: float = to_guard.length()
		if dist > shiv_range or facing.dot(to_guard.normalized()) < 0.65:
			continue
		var space := get_world_2d().direct_space_state
		var ray   := PhysicsRayQueryParameters2D.create(global_position, guard.global_position)
		ray.exclude = [self]
		var result := space.intersect_ray(ray)
		if result.is_empty() or result.collider == guard:
			if dist < best_dist:
				best_dist  = dist
				best_guard = guard
	if best_guard:
		_shiv_thrown = true
		best_guard.takedown(true, true)
		GameManager.record_takedown()
		_popup("SHIV THROWN — once per floor!", Color(0.65, 0.65, 0.70))
		GameManager.shake(1.8, 0.14)
		AudioManager.dart_fire()
		ability_cooldown = ABILITY_COOLDOWNS["CUTPURSE"] * (0.70 if GameManager.has_passive("COLD_BLOOD") else 1.0)
	else:
		_popup("No target in shiv range (80px).", Color(0.60, 0.45, 0.30))

func _ability_shadow_step():
	var best := position
	for i in range(1, 6):
		var candidate := position + facing * TILE_SIZE * i
		var space := get_world_2d().direct_space_state
		var query := PhysicsPointQueryParameters2D.new()
		query.position = candidate
		query.exclude  = [self]
		if space.intersect_point(query).size() == 0:
			best = candidate
	if best == position:
		_popup("Path fully blocked!", Color(0.55, 0.50, 0.45))
		return
	position = best
	emit_noise(NoiseLevel.SILENT)
	_popup("SHADOW STEP", Color(0.55, 0.30, 0.95))
	GameManager.shake(1.0, 0.08)
	AudioManager.ability_use()
	ability_cooldown = ABILITY_COOLDOWNS["SHADOWDANCER"] * (0.70 if GameManager.has_passive("COLD_BLOOD") else 1.0)

func _ability_mark_target():
	if _assassin_mark != null and is_instance_valid(_assassin_mark):
		_popup("Target already marked", Color(0.85, 0.45, 0.15))
		return
	_assassin_mark = null
	var best: Node = null
	var best_dist := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var dist := global_position.distance_to(guard.global_position)
		if dist > 140.0 or dist >= best_dist:
			continue
		var space := get_world_2d().direct_space_state
		var ray   := PhysicsRayQueryParameters2D.create(global_position, guard.global_position)
		ray.exclude = [self]
		var result := space.intersect_ray(ray)
		if result.is_empty() or result.collider == guard:
			best_dist = dist
			best = guard
	if best:
		_assassin_mark = best
		best.set_meta("is_marked", true)
		_popup("TARGET MARKED", Color(1.0, 0.15, 0.15))
		AudioManager.ability_use()
		ability_cooldown = ABILITY_COOLDOWNS["ASSASSIN"] * (0.70 if GameManager.has_passive("COLD_BLOOD") else 1.0)
	else:
		_popup("No target in sight", Color(0.55, 0.50, 0.45))

func _ability_lucky_break():
	# Halfling — once per floor, negate the next alert
	if GameManager.try_use_racial_luck():
		_popup("LUCKY BREAK! Alert negated.", Color(0.95, 0.80, 0.30))
		AudioManager.ability_use()
	else:
		_popup("Lucky Break spent this floor.", Color(0.55, 0.50, 0.45))

func _ability_vanish():
	# Wood Elf — 3s invisibility (guards ignore line-of-sight)
	GameManager._vanish_active = true
	GameManager._vanish_timer  = 3.0
	_popup("VANISH!", Color(0.30, 0.80, 0.45))
	GameManager.shake(0.8, 0.07)
	AudioManager.ability_use()
	racial_cooldown = RACIAL_COOLDOWNS["WOOD_ELF"]

func _ability_battle_cry():
	# Dwarf — stun all guards within 48px for 2.5s
	var hit := 0
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= 48.0:
			if guard.has_method("apply_stun"):
				guard.apply_stun(2.5)
				hit += 1
	if hit > 0:
		_popup("BATTLE CRY! %d stunned" % hit, Color(0.90, 0.65, 0.20))
		GameManager.shake(3.0, 0.25)
		AudioManager.ability_use()
	else:
		_popup("No enemies in range.", Color(0.55, 0.50, 0.45))
	racial_cooldown = RACIAL_COOLDOWNS["DWARF"]

func _ability_hellish_rebuke():
	# Tiefling — clear all detection bars on nearby guards
	var count := 0
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= 80.0:
			guard.set("detection_progress", 0.0)
			count += 1
	_popup("HELLISH REBUKE! %d wiped" % count, Color(0.85, 0.25, 0.85))
	GameManager.shake(1.5, 0.12)
	AudioManager.ability_use()
	racial_cooldown = RACIAL_COOLDOWNS["TIEFLING"]

func _is_behind_guard(guard) -> bool:
	var to_player: Vector2 = global_position - guard.global_position
	return guard.facing.dot(to_player.normalized()) < -0.5

# ── Items ─────────────────────────────────────────────────────────────────────
func _use_item(slot: int):
	if slot >= equipped.size():
		return
	var itype: int = equipped[slot]
	if itype == -1:
		_popup("Slot %d empty" % (slot + 1), Color(0.55, 0.50, 0.45))
		return
	# Sleight of Hand (Cutpurse) — first item per floor costs nothing
	var free_use := GameManager.selected_class == "CUTPURSE" and not _cutpurse_free_item_used
	for item in items:
		if item["type"] == itype:
			if item["count"] <= 0:
				_popup("Out of %s" % ITEM_DATA.get(itype, {}).get("name", "item"), Color(0.8, 0.4, 0.3))
				return
			var consumed := true
			match itype:
				ItemType.COIN:       _throw_coin()
				ItemType.SMOKE:      _deploy_smoke()
				ItemType.DART:       consumed = _fire_dart()
				ItemType.ROPE:       consumed = _use_rope()
				ItemType.FLASH:      _deploy_flash()
				ItemType.HOLD:       consumed = _fire_hold()
				ItemType.SILENCE:    _deploy_silence()
				ItemType.TOOLS:      _use_tools()
				ItemType.SHADOW_OIL: _use_shadow_oil()
			if consumed:
				if free_use:
					_cutpurse_free_item_used = true
					_popup("Sleight of Hand — free use!", Color(0.95, 0.78, 0.15))
				else:
					item["count"] -= 1
			return

func _throw_coin():
	# Cutpurse gets +50% coin range
	var tiles := 7 if GameManager.selected_class == "CUTPURSE" else 5
	var throw_pos := global_position + facing * TILE_SIZE * tiles
	_emit_noise_at(NoiseLevel.LOUD, throw_pos)
	_popup("Coin tossed!%s" % (" (+range)" if tiles == 7 else ""), ITEM_DATA[ItemType.COIN].color)
	AudioManager.coin_throw()

func _deploy_smoke():
	var cloud := _smoke_scene.instantiate()
	cloud.global_position = global_position
	get_tree().root.add_child(cloud)
	_popup("Smoke deployed!", ITEM_DATA[ItemType.SMOKE].color)
	AudioManager.smoke_pop()

func _fire_dart() -> bool:
	var dart_range := 150.0
	# Check for magic wards in dart path first
	for ward in get_tree().get_nodes_in_group("magic_wards"):
		var to_ward: Vector2 = ward.global_position - global_position
		var dist: float = to_ward.length()
		if dist <= dart_range and facing.dot(to_ward.normalized()) >= 0.60:
			if ward.has_method("destroy_ward"):
				ward.destroy_ward()
				_popup("Ward dispelled!", ITEM_DATA[ItemType.DART].color)
				AudioManager.dart_fire()
				return true
	var best_guard = null
	var best_dist  := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var to_guard: Vector2 = guard.global_position - global_position
		var dist: float = to_guard.length()
		if dist > dart_range:
			continue
		if facing.dot(to_guard.normalized()) < 0.60:
			continue
		var space := get_world_2d().direct_space_state
		var ray   := PhysicsRayQueryParameters2D.create(global_position, guard.global_position)
		ray.exclude = [self]
		var result := space.intersect_ray(ray)
		if result.is_empty() or result.collider == guard:
			if dist < best_dist:
				best_dist  = dist
				best_guard = guard
	if best_guard:
		best_guard.takedown(true, true)
		GameManager.record_takedown()
		_popup("Dart — sweet dreams.", ITEM_DATA[ItemType.DART].color)
		GameManager.shake(1.5, 0.12)
		AudioManager.dart_fire()
		return true
	_popup("No target in range.", Color(0.60, 0.45, 0.30))
	return false

func _fire_crossbow() -> bool:
	if _crossbow_bolts <= 0:
		_popup("No bolts remaining!", Color(0.80, 0.35, 0.20))
		return false
	var bolt_range := 200.0 if weapon == "CROSSBOW" \
		else (250.0 if weapon == "REPEATING_CROSSBOW" else 300.0)
	var is_silent  := weapon == "SILENT_BOLT"
	var best_guard = null
	var best_dist  := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var to_guard: Vector2 = guard.global_position - global_position
		var dist: float = to_guard.length()
		if dist > bolt_range or facing.dot(to_guard.normalized()) < 0.55:
			continue
		var space := get_world_2d().direct_space_state
		var ray   := PhysicsRayQueryParameters2D.create(global_position, guard.global_position)
		ray.exclude = [self]
		var result := space.intersect_ray(ray)
		if result.is_empty() or result.collider == guard:
			if dist < best_dist:
				best_dist  = dist
				best_guard = guard
	if best_guard:
		_crossbow_bolts -= 1
		var bolts_left := _crossbow_bolts if weapon != "SILENT_BOLT" else -1
		best_guard.takedown(is_silent)
		GameManager.record_takedown(true)
		if not is_silent:
			emit_noise(NoiseLevel.LOUD)
		_post_kill_effects(best_guard, is_silent)
		# REPEATING_CROSSBOW: NAT20 equivalent pierce — alert adjacent guard too
		if weapon == "REPEATING_CROSSBOW" and randi_range(1, 20) == 20:
			for g2 in get_tree().get_nodes_in_group("guards"):
				if g2 != best_guard and best_guard.global_position.distance_to(g2.global_position) <= 24.0:
					g2.takedown(false)
					GameManager.record_takedown(true)
					_popup("PIERCE — double hit!", Color(0.70, 0.50, 0.28))
					break
		var lbl := "SILENT BOLT — %dpx" % int(bolt_range) if is_silent \
			else ("%s — %d left" % [weapon.replace("_", " "), bolts_left])
		_popup(lbl, Color(0.55, 0.38, 0.22) if not is_silent else Color(0.85, 0.65, 0.35))
		GameManager.shake(2.5 if not is_silent else 1.2, 0.20)
		AudioManager.dart_fire()
		return true
	_popup("No target in range (%dpx)." % int(bolt_range), Color(0.60, 0.45, 0.30))
	return false

func _fire_thrown_blade(range_px: float, label: String, color: Color, silent: bool) -> bool:
	var best_guard = null
	var best_dist  := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var to_guard: Vector2 = guard.global_position - global_position
		var dist: float = to_guard.length()
		if dist > range_px or facing.dot(to_guard.normalized()) < 0.65:
			continue
		var space := get_world_2d().direct_space_state
		var ray   := PhysicsRayQueryParameters2D.create(global_position, guard.global_position)
		ray.exclude = [self]
		var result := space.intersect_ray(ray)
		if result.is_empty() or result.collider == guard:
			if dist < best_dist:
				best_dist  = dist
				best_guard = guard
	if best_guard:
		best_guard.takedown(silent)
		GameManager.record_takedown()
		_post_kill_effects(best_guard, silent)
		_popup(label, color)
		GameManager.shake(1.8, 0.14)
		AudioManager.dart_fire()
		return true
	_popup("No target in throw range (%dpx)." % int(range_px), Color(0.60, 0.45, 0.30))
	return false

func _fire_venom_needle() -> bool:
	var best_guard = null
	var best_dist  := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var to_guard: Vector2 = guard.global_position - global_position
		var dist: float = to_guard.length()
		if dist > 120.0 or facing.dot(to_guard.normalized()) < 0.65:
			continue
		var space := get_world_2d().direct_space_state
		var ray   := PhysicsRayQueryParameters2D.create(global_position, guard.global_position)
		ray.exclude = [self]
		var result := space.intersect_ray(ray)
		if result.is_empty() or result.collider == guard:
			if dist < best_dist:
				best_dist  = dist
				best_guard = guard
	if best_guard:
		# Confused for 6s then silently falls — apply stun then kill via timer
		if best_guard.has_method("apply_hold"):
			best_guard.apply_hold(6.0)
		_popup("VENOM NEEDLE — %d uses left" % _venom_needle_uses_left, Color(0.30, 0.75, 0.35))
		AudioManager.dart_fire()
		# Delayed silent kill — must be called via deferred coroutine so the bool return works
		var guard_ref: Node = best_guard
		_venom_needle_delayed_kill(guard_ref)
		return true
	_popup("No target in needle range (120px).", Color(0.60, 0.45, 0.30))
	return false

func _venom_needle_delayed_kill(guard_ref: Node):
	await get_tree().create_timer(6.2).timeout
	if is_instance_valid(guard_ref):
		guard_ref.takedown(true)
		GameManager.record_takedown()

func _deploy_flash():
	var flash_range := 60.0
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= flash_range:
			guard.set("detection_progress", 0.0)
			if guard.get("alert_state") == 1:  # SUSPICIOUS
				guard.set("alert_state", 0)
				guard.set("investigate_pos", Vector2.ZERO)
	_popup("Flash!", ITEM_DATA[ItemType.FLASH].color)
	GameManager.shake(1.0, 0.08)
	AudioManager.flash_bang()

func _fire_hold() -> bool:
	# Hold Person scroll — freeze nearest guard in sight for 4s
	var best_guard = null
	var best_dist  := INF
	for guard in get_tree().get_nodes_in_group("guards"):
		var to_guard: Vector2 = guard.global_position - global_position
		var dist: float = to_guard.length()
		if dist > 120.0:
			continue
		var space := get_world_2d().direct_space_state
		var ray   := PhysicsRayQueryParameters2D.create(global_position, guard.global_position)
		ray.exclude = [self]
		var result := space.intersect_ray(ray)
		if result.is_empty() or result.collider == guard:
			if dist < best_dist:
				best_dist  = dist
				best_guard = guard
	if best_guard and best_guard.has_method("apply_hold"):
		var hold_dur := 4.0 * (1.5 if weapon == "ARCANE_FOCUS" else 1.0)
		best_guard.apply_hold(hold_dur)
		_popup("HOLD PERSON!" + (" (6s)" if weapon == "ARCANE_FOCUS" else ""), ITEM_DATA[ItemType.HOLD].color)
		GameManager.shake(1.0, 0.08)
		AudioManager.ability_use()
		return true
	_popup("No target in range.", Color(0.60, 0.45, 0.30))
	return false

func _deploy_silence():
	var zone := _silence_scene.instantiate()
	zone.global_position = global_position
	get_tree().current_scene.add_child(zone)
	_popup("Silence cast!", ITEM_DATA[ItemType.SILENCE].color)
	AudioManager.ability_use()

func _use_rope() -> bool:
	var best := position
	for i in range(1, 4):
		var candidate := position + facing * TILE_SIZE * i
		if is_position_blocked(candidate):
			break
		best = candidate
	if best == position:
		_popup("Path blocked!", Color(0.70, 0.40, 0.30))
		return false
	position = best
	emit_noise(NoiseLevel.QUIET)
	_popup("Rope dash!", ITEM_DATA[ItemType.ROPE].color)
	GameManager.shake(1.2, 0.10)
	AudioManager.rope_dash()
	return true

func _use_tools():
	# Grant +5 bonus to next lockpick roll (store as passive flag)
	GameManager.add_passive("TOOLS_BONUS")
	_popup("Thieves' Tools ready — +5 to next pick!", ITEM_DATA[ItemType.TOOLS].color)
	AudioManager.ability_use()

func _use_shadow_oil():
	# Reduce all guard vision ranges by 20 for 60 seconds via a time-limited passive
	for g in get_tree().get_nodes_in_group("guards"):
		g.set("vision_range", max(20.0, g.get("vision_range") - 20.0))
	_shadow_oil_timer = 60.0
	_popup("Shadow Cloak — guards blinded!", ITEM_DATA[ItemType.SHADOW_OIL].color)
	AudioManager.ability_use()

func _try_use_offhand_active():
	# Active offhand effects — called on a dedicated key (e.g. held E)
	if has_gear("SPEED_BURST") and not _quicksilver_active:
		_quicksilver_active = true
		_quicksilver_timer  = 8.0
		_popup("QUICKSILVER — 8s sprint!", Color(0.55, 0.85, 0.95))
		AudioManager.ability_use()
	elif has_gear("EXTENDED_SMOKE"):
		# Instant mini-smoke (one use)
		gear["offhand"] = ""   # consume the extra use
		var cloud := _smoke_scene.instantiate()
		cloud.global_position = global_position
		get_tree().root.add_child(cloud)
		_popup("MINI-SMOKE — instant!", Color(0.42, 0.58, 0.42))
		AudioManager.smoke_pop()

# ── Noise ─────────────────────────────────────────────────────────────────────
func _emit_movement_noise():
	# Wood Elf — always moves silently
	if GameManager.selected_race == "WOOD_ELF":
		return
	var level: NoiseLevel
	if is_sneaking or is_carrying_body:
		# GHOST_BOOTS (Shadowstep Boots) or GHOST_STEP passive = always silent when sneaking
		var full_silent := GameManager.has_passive("GHOST_STEP") or has_gear("GHOST_BOOTS")
		level = NoiseLevel.SILENT if full_silent else NoiseLevel.QUIET
	else:
		# SOFT_WALK (Silk Mantle) or QUIET_BOOTS (Leather Boots) = walk is quiet not loud
		var soft_walk := GameManager.selected_class == "CUTPURSE" \
			or GameManager.has_passive("SOFT_BOOTS") \
			or has_gear("SOFT_WALK") or has_gear("QUIET_BOOTS")
		level = NoiseLevel.QUIET if soft_walk else NoiseLevel.LOUD
	noise_emitted.emit(level, global_position)
	_spawn_ripple_at(level, global_position)
	if level == NoiseLevel.LOUD:
		AudioManager.step_loud()
	elif level == NoiseLevel.QUIET:
		AudioManager.step_quiet()

func emit_noise(level: NoiseLevel):
	if is_hidden and GameManager.has_passive("SHADOW_CLOAK") and level != NoiseLevel.SILENT:
		level = NoiseLevel.SILENT
	noise_emitted.emit(level, global_position)
	if level != NoiseLevel.SILENT:
		_spawn_ripple_at(level, global_position)

func _emit_noise_at(level: NoiseLevel, pos: Vector2):
	noise_emitted.emit(level, pos)
	_spawn_ripple_at(level, pos)

func _spawn_ripple_at(level: NoiseLevel, pos: Vector2):
	if level == NoiseLevel.SILENT:
		return
	var ripple := _ripple_scene.instantiate()
	ripple.setup(level)
	ripple.global_position = pos
	get_tree().root.add_child(ripple)

# ── Visuals ───────────────────────────────────────────────────────────────────
func _popup(text: String, color: Color):
	var popup := _dice_scene.instantiate()
	popup.setup(text, color)
	popup.global_position = global_position + Vector2(0, -10)
	get_tree().root.add_child(popup)

func _draw():
	var f    := facing.normalized()
	var perp := f.rotated(PI * 0.5)
	var cls  := GameManager.selected_class

	# Patrol route overlay — Assassin timed reveal OR SHADOWGLASS permanent
	var show_patrol := _patrol_reveal_timer > 0.0 or has_gear("PATROL_SIGHT")
	if show_patrol:
		var alpha: float = 0.22 if has_gear("PATROL_SIGHT") \
			else min(1.0, _patrol_reveal_timer) * 0.55
		var trail_col := Color(0.25, 0.55, 0.85, alpha) if has_gear("PATROL_SIGHT") \
			else Color(1.0, 0.15, 0.15, alpha)
		for guard in get_tree().get_nodes_in_group("guards"):
			var pts: Array = guard.get("patrol_points") if guard.get("patrol_points") else []
			if pts.size() < 2:
				continue
			for i in range(pts.size()):
				var a: Vector2 = pts[i] - global_position
				var b: Vector2 = pts[(i + 1) % pts.size()] - global_position
				draw_line(a, b, trail_col, 1.0)
				draw_circle(a, 2.5, trail_col)

	if is_hidden:
		draw_arc(Vector2.ZERO, 5.0, 0, TAU, 16, Color(0.55, 0.30, 0.95, 0.30), 1.0)
		# Weapon and overlay effects still drawn below; skip body only
	elif _sprite == null:
		# Fallback procedural body when sprite sheet isn't loaded
		var cloak_col: Color
		var cape_col:  Color
		var hood_col:  Color
		var rim_col:   Color
		match cls:
			"CUTPURSE":
				cloak_col = Color(0.28, 0.20, 0.08) if not is_sneaking else Color(0.15, 0.10, 0.04)
				cape_col  = Color(0.20, 0.14, 0.05) if not is_sneaking else Color(0.10, 0.07, 0.02)
				hood_col  = Color(0.22, 0.15, 0.06) if not is_sneaking else Color(0.11, 0.08, 0.03)
				rim_col   = Color(0.60, 0.48, 0.18)
			"ASSASSIN":
				cloak_col = Color(0.24, 0.06, 0.06) if not is_sneaking else Color(0.14, 0.03, 0.03)
				cape_col  = Color(0.18, 0.04, 0.04) if not is_sneaking else Color(0.09, 0.02, 0.02)
				hood_col  = Color(0.15, 0.04, 0.04) if not is_sneaking else Color(0.08, 0.02, 0.02)
				rim_col   = Color(0.75, 0.20, 0.20)
			_:
				cloak_col = Color(0.20, 0.16, 0.38) if not is_sneaking else Color(0.10, 0.08, 0.20)
				cape_col  = Color(0.12, 0.09, 0.26) if not is_sneaking else Color(0.06, 0.04, 0.14)
				hood_col  = Color(0.12, 0.09, 0.26) if not is_sneaking else Color(0.07, 0.05, 0.15)
				rim_col   = Color(0.32, 0.26, 0.52)
		var race_data: Dictionary = GameManager.RACES.get(GameManager.selected_race, {})
		var skin_col: Color = race_data.get("skin", Color(0.82, 0.68, 0.52))
		var hood_pos := f * 1.8 + Vector2(0, -1.0)
		var face_pos := f * 4.2 + Vector2(0, -0.5)
		draw_colored_polygon(PackedVector2Array([-f * 0.0 + perp * 5.0, -f * 0.0 - perp * 5.0, -f * 10.0 + Vector2(0,1)]), cape_col)
		draw_circle(Vector2(0.5, 1.0), 5.5, Color(0.0, 0.0, 0.0, 0.30))
		draw_circle(Vector2.ZERO, 5.5, cloak_col)
		draw_circle(hood_pos, 4.0, hood_col)
		draw_arc(hood_pos, 4.0, f.angle() - 1.2, f.angle() + 1.2, 10, Color(rim_col.r, rim_col.g, rim_col.b, 0.7), 1.0)
		draw_circle(face_pos, 1.4, skin_col)
		match GameManager.selected_race:
			"TIEFLING":
				draw_line(hood_pos + perp * 3.0 + f * -0.5, hood_pos + perp * 3.0 + f * -0.5 + perp * 2.0 + f * -3.5, Color(0.15, 0.05, 0.25), 1.5)
				draw_line(hood_pos - perp * 3.0 + f * -0.5, hood_pos - perp * 3.0 + f * -0.5 - perp * 2.0 + f * -3.5, Color(0.15, 0.05, 0.25), 1.5)
			"WOOD_ELF":
				draw_line(hood_pos + perp * 3.5, hood_pos + perp * 5.5 + f * 1.0, skin_col, 1.2)
				draw_line(hood_pos - perp * 3.5, hood_pos - perp * 5.5 + f * 1.0, skin_col, 1.2)
			"HALFLING":
				draw_circle(Vector2.ZERO, 4.8, cloak_col)
				draw_circle(perp * 2.5 + f * -5.0, 1.5, skin_col)
				draw_circle(-perp * 2.5 + f * -5.0, 1.5, skin_col)
			"DWARF":
				draw_circle(Vector2.ZERO, 6.2, cloak_col)
				draw_circle(f * -0.5 + Vector2(0, 1.5), 5.8, cloak_col)
				draw_circle(face_pos - f * 1.5, 1.8, Color(0.75, 0.60, 0.40))

	# Wood Elf vanish shimmer — always drawn as it's an effect overlay
	if GameManager.selected_race == "WOOD_ELF" and GameManager._vanish_active:
		draw_arc(Vector2.ZERO, 9.0, 0, TAU, 20, Color(0.30, 0.90, 0.45, 0.45), 1.5)

	# ── Post-move noise arc ───────────────────────────────────────────────────
	if _move_cooldown > 0.0 and not is_hidden:
		var t := _move_cooldown / (SNEAK_COOLDOWN if is_sneaking else WALK_COOLDOWN)
		if is_sneaking:
			draw_arc(Vector2.ZERO, 14.0 * (1.0 - t * 0.5), 0, TAU, 20,
				Color(0.35, 0.65, 1.0, t * 0.28), 1.0)
		else:
			var walking_loud := cls != "CUTPURSE"
			var nc := Color(1.0, 0.55, 0.15) if walking_loud else Color(0.35, 0.65, 1.0)
			draw_arc(Vector2.ZERO, 22.0 * (1.0 - t * 0.6), 0, TAU, 20,
				Color(nc.r, nc.g, nc.b, t * 0.22), 1.2)

	# ── Weapon visual ────────────────────────────────────────────────────────────
	match weapon:
		"SHIV":
			# Small blade at the hip, only visible when not sneaking
			if not is_sneaking:
				var blade_base: Vector2 = perp * 4.5 - f * 1.0
				draw_line(blade_base, blade_base + f * 5.0, Color(0.72, 0.72, 0.76), 1.2)
				draw_line(blade_base, blade_base - f * 1.5, Color(0.40, 0.28, 0.15), 1.8)
				if _shiv_thrown:  # greyed out when spent
					draw_line(blade_base, blade_base + f * 5.0, Color(0.45, 0.45, 0.48), 1.2)
		"SHADOW_BLADE":
			# Longer blade with purple aura, held out front
			var sb_base: Vector2 = perp * 3.5 + f * 1.0
			var sb_tip:  Vector2 = sb_base + f * 7.0
			draw_line(sb_base, sb_tip, Color(0.50, 0.25, 0.85, 0.90), 1.5)
			draw_line(sb_base + perp * 0.8, sb_base - perp * 0.8,
				Color(0.50, 0.25, 0.85, 0.55), 1.0)  # crossguard
			if is_sneaking:  # glow when in shadow
				draw_arc(sb_tip, 2.5, 0, TAU, 12, Color(0.50, 0.25, 0.85, 0.45), 1.0)
		"CROSSBOW":
			# Horizontal stock behind the facing direction
			var cb_center: Vector2 = -f * 3.0
			draw_line(cb_center - perp * 4.0, cb_center + perp * 4.0,
				Color(0.40, 0.28, 0.15), 2.0)   # stock
			draw_line(cb_center, cb_center + f * 5.5,
				Color(0.55, 0.42, 0.22), 1.5)   # barrel
			# Bolt indicator pips (one per remaining bolt)
			for b in range(_crossbow_bolts):
				var pip: Vector2 = cb_center + perp * (-3.0 + b * 3.0) + f * -5.0
				draw_circle(pip, 0.8, Color(0.65, 0.65, 0.70))
		"ARCANE_FOCUS":
			# Glowing orb near the chest
			var orb_pos: Vector2 = f * 2.5 + perp * -2.0
			draw_circle(orb_pos, 2.0, Color(0.35, 0.12, 0.70, 0.80))
			draw_arc(orb_pos, 2.5, 0, TAU, 16, Color(0.65, 0.35, 1.00, 0.55), 1.0)
		_:  # NONE / fallback — generic daggers
			if not is_sneaking:
				var dagger_col := Color(0.60, 0.58, 0.62)
				var handle_col := Color(0.35, 0.25, 0.15)
				for side in [1, -1]:
					var base: Vector2 = perp * (side * 4.5) - f * 1.0
					draw_line(base, base + f * 4.0, dagger_col, 1.0)
					draw_line(base, base - f * 1.5, handle_col, 1.5)

	# ── Hit flash overlay ─────────────────────────────────────────────────────
	if _hit_flash_timer > 0.0:
		var hf_alpha := (_hit_flash_timer / _HIT_FLASH_DURATION) * 0.45
		draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.10, 0.10, hf_alpha))

	# ── Sneak shimmer ──────────────────────────────────────────────────────────
	if is_sneaking:
		draw_arc(Vector2.ZERO, 7.5, 0, TAU, 20, Color(0.45, 0.75, 1.0, 0.22), 1.0)
		var fa := f.angle()
		draw_arc(Vector2.ZERO, 9.0, fa - 0.9, fa + 0.9, 12, Color(0.60, 0.88, 1.0, 0.35), 1.2)
		var pulse_a := _move_cooldown / SNEAK_COOLDOWN
		draw_arc(Vector2.ZERO, 11.0 + pulse_a * 3.0, 0, TAU, 20,
			Color(0.45, 0.75, 1.0, (1.0 - pulse_a) * 0.12), 0.8)

	# ── Loot glint (gold orb on shoulder) ─────────────────────────────────────
	if has_loot:
		var loot_pos := perp * -3.5 + f * 2.0 + Vector2(0, -3)
		draw_circle(loot_pos, 2.2, Color(0.95, 0.80, 0.10))
		draw_circle(loot_pos + Vector2(-0.5, -0.5), 0.8, Color(1.0, 0.96, 0.70))

	# ── Body carry indicator ───────────────────────────────────────────────────
	if is_carrying_body:
		var bp := -f * 5.0 + Vector2(0, 2)
		draw_circle(bp, 3.8, Color(0.28, 0.08, 0.08, 0.80))
		draw_arc(bp, 5.0, 0, TAU, 12, Color(0.85, 0.55, 0.30, 0.60), 1.2)

	# ── Ability charge ring ────────────────────────────────────────────────────
	if ability_cooldown <= 0.0:
		draw_arc(Vector2.ZERO, 8.5, -PI * 0.5, -PI * 0.5 + TAU, 20,
			Color(0.55, 0.30, 0.95, 0.28), 1.0)
	else:
		var max_cd: float = ABILITY_COOLDOWNS.get(GameManager.selected_class, 10.0)
		var frac: float   = 1.0 - (ability_cooldown / max_cd)
		if frac > 0.0:
			draw_arc(Vector2.ZERO, 8.5, -PI * 0.5, -PI * 0.5 + TAU * frac, 20,
				Color(0.55, 0.30, 0.95, 0.20), 1.0)

func take_damage_flash():
	_hit_flash_timer = _HIT_FLASH_DURATION
	if _sprite != null:
		_sprite.modulate = Color(1.0, 0.25, 0.25)

func is_position_blocked(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = target_pos
	query.exclude  = [self]
	return space.intersect_point(query).size() > 0
