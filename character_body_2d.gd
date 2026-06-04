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
var _battle_shout_active := false  # SELLSWORD: next melee hit deals double damage

# Movement slide — sprite visually slides from old tile to new while position snaps
var _slide_from:   Vector2 = Vector2.ZERO   # sprite-local offset at slide start
var _slide_t:      float   = 0.0            # 0→1 progress; 0 = idle
const _SLIDE_DUR:  float   = 0.14           # seconds to complete one tile slide

# Attack lunge + hitstop
var _lunge_t:      float   = 0.0            # 0→1 progress; drives sprite offset forward then back
const _LUNGE_DUR:  float   = 0.10           # total lunge animation duration
const _LUNGE_PX:   float   = 5.0            # max pixel offset in facing direction
var _hitstop_t:    float   = 0.0            # > 0 = freeze _process logic (visual pause only)

# Room tracking — triggers patrol preview on first entry
var _last_room: int = -1

# Pebble throw — free distraction, quiet noise, 6s cooldown
var _pebble_cooldown: float = 0.0
const _PEBBLE_CD: float = 6.0
const _PEBBLE_RANGE: int = 6   # tiles

# Dodge roll
var _dodge_cooldown: float = 0.0
var _dodge_iframes:  float = 0.0            # > 0 = invincible; guards can't fill detection
const _DODGE_CD:      float = 1.5
const _DODGE_IFRAMES: float = 0.22
const _DODGE_TILES:   int   = 2

# Charge attack — hold attack button to power up
var _attack_held:    bool  = false
var _attack_hold_t:  float = 0.0
const _CHARGE_THRESHOLD: float = 0.38     # seconds held to trigger charge
const _CHARGE_MAX:        float = 0.70     # caps hold time

# Parry window — active briefly after pressing attack near an ALERT guard
var _parry_t: float = 0.0
const _PARRY_WINDOW: float = 0.30

const ABILITY_COOLDOWNS := { "CUTPURSE": 8.0, "SHADOWDANCER": 12.0, "ASSASSIN": 15.0, "SELLSWORD": 10.0 }
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
var _anim_t        := 0.0   # continuously advancing timer for smooth SVG animation

func _ready():
	_init_items()
	gear = GameManager.get_start_gear()
	reset_floor_charges()
	GameManager.screen_shake.connect(_on_screen_shake)
	_setup_sprite()
	_setup_camera()
	# Load injury state carried from previous floor
	is_bleeding = GameManager.player_is_bleeding
	is_limping  = GameManager.player_is_limping
	# Assassin: reveal patrol paths on floor start
	if GameManager.selected_class == "ASSASSIN":
		_patrol_reveal_timer = PATROL_REVEAL_DURATION
		_popup("RECONNAISSANCE: patrol routes revealed", Color(0.85, 0.15, 0.15))

func _setup_camera():
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.zoom = Vector2(2.5, 2.5)
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed   = 8.0

func _setup_sprite():
	# V7: pure SVG procedural art — no sprite sheet needed
	_sprite = null

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
	GameManager._wand_charges  = 5
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
	_anim_t += delta
	is_sneaking = Input.is_key_pressed(KEY_SHIFT) or Input.is_action_pressed("game_sneak")
	if not is_sneaking:
		for joypad in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(joypad, JOY_BUTTON_LEFT_SHOULDER):
				is_sneaking = true
				break

	# Charge attack tracking — must run before hitstop so release is detected immediately
	if GameManager.state == GameManager.State.PLAYING and not is_hidden:
		var attack_down: bool = Input.is_action_pressed("game_takedown")
		if attack_down and not _attack_held:
			_attack_held   = true
			_attack_hold_t = 0.0
		elif attack_down and _attack_held:
			_attack_hold_t = min(_attack_hold_t + delta, _CHARGE_MAX)
		elif not attack_down and _attack_held:
			_attack_held = false
			var was_charged: bool = _attack_hold_t >= _CHARGE_THRESHOLD
			_attack_hold_t = 0.0
			if was_charged:
				_do_charged_attack()
			else:
				_try_takedown()

	# Hitstop: freeze gameplay timers for a frame-freeze effect on hit
	if _hitstop_t > 0.0:
		_hitstop_t -= delta
		return

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
	if _dodge_cooldown > 0.0:
		_dodge_cooldown -= delta
	if _pebble_cooldown > 0.0:
		_pebble_cooldown -= delta
	# Room entry: trigger patrol preview for guards in the newly entered room
	_check_room_entry()
	if _dodge_iframes > 0.0:
		_dodge_iframes -= delta
	if _parry_t > 0.0:
		_parry_t -= delta
	# SPEAR passive parry: small always-on window when attack is ready
	if weapon == "SPEAR" and _attack_cooldown <= 0.0 and _parry_t <= 0.0:
		_parry_t = 0.10
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
					_start_slide(dir)
					position = target
					_emit_movement_noise()
				var base_walk: float  = WALK_COOLDOWN  * (0.80 if GameManager.has_passive("QUICK_HANDS") else 1.0)
				var base_sneak: float = SNEAK_COOLDOWN * (0.80 if GameManager.has_passive("QUICK_HANDS") else 1.0)
				var no_slow: bool = GameManager.has_passive("DEAD_WEIGHT") or has_gear("BODY_CARRY")
				var body_mult := (1.0 if no_slow else 1.4) if is_carrying_body else 1.0
				var limp_mult   := 1.4 if is_limping else 1.0
				var speed_mult  := 0.55 if _quicksilver_active else 1.0
				# RELENTLESS tier: +20% move speed
				if GameManager.combo_tier >= 2:
					speed_mult *= 0.80
				_move_cooldown = (base_sneak if (is_sneaking or is_carrying_body) else base_walk) * body_mult * limp_mult * speed_mult
				_walk_frame = (_walk_frame + 1) % 2

	# ── Slide animation ───────────────────────────────────────────────────────
	if _slide_t > 0.0:
		_slide_t = max(0.0, _slide_t - delta / _SLIDE_DUR)
		if _sprite != null:
			# ease-out: t² gives a snappy deceleration feel
			var ease: float = _slide_t * _slide_t
			_sprite.position = _slide_from * ease
	elif _sprite != null and not _lunge_t > 0.0:
		_sprite.position = Vector2.ZERO

	# ── Lunge animation ───────────────────────────────────────────────────────
	if _lunge_t > 0.0:
		_lunge_t = max(0.0, _lunge_t - delta / _LUNGE_DUR)
		if _sprite != null:
			# Sharp push forward then snap back: peaks at t=1, returns to 0
			var env: float = sin(_lunge_t * PI)   # 0→1→0 envelope
			_sprite.position = facing * _LUNGE_PX * env

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
		if event.is_action_pressed("game_pebble"):         _throw_pebble();           return
		if event.is_action_pressed("game_dodge"):          _try_dodge();              return
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
			_start_slide(direction)
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
	# Check for nearby bodies — loot first, then pick up
	for body in get_tree().get_nodes_in_group("bodies"):
		if not is_instance_valid(body):
			continue
		if global_position.distance_to(body.global_position) <= 28.0:
			if not body.get_meta("being_carried", false):
				# Loot body if it has unlooted items
				if body.has_meta("body_loot") and not body.get_meta("body_looted", false):
					if body.has_method("interact"):
						body.interact(self)
					return
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
	# Sneaking drops are silent; walking drops thud
	if is_sneaking:
		emit_noise(NoiseLevel.SILENT)
		_popup("Body lowered", Color(0.55, 0.75, 0.45))
	else:
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
			# Activate parry window — GHOST tier doubles the window
			_parry_t = _PARRY_WINDOW * (2.0 if GameManager.combo_tier >= 3 else 1.0)
			_do_combat_attack()
			return
		_resolve_takedown(guard)
		return
	# No adjacent guard — always show weapon animation (like Stardew/Hotline Miami)
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

func _parry_riposte(guard: Node):
	# Called by guard when player's _parry_t > 0 at the moment the guard's attack fires.
	# Deals 2× weapon damage and stuns the guard for 0.6s.
	_parry_t = 0.0
	var cdata: Dictionary = GameManager.WEAPON_COMBAT.get(weapon, GameManager.WEAPON_COMBAT["NONE"])
	var riposte_dmg: int = cdata["damage"] * 2
	_popup("RIPOSTE!  -%d" % riposte_dmg, Color(0.35, 0.95, 0.55))
	guard.hurt(riposte_dmg, (guard.global_position - global_position).normalized())
	if is_instance_valid(guard):
		guard.set("_is_stunned", true)
		guard.set("_stun_timer", 0.60)
	_start_lunge()
	_spawn_attack_anim(true)
	_trigger_hitstop()
	GameManager.shake(2.0, 0.16)

func _do_combat_attack():
	var cdata: Dictionary = GameManager.WEAPON_COMBAT.get(weapon, GameManager.WEAPON_COMBAT["NONE"])
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = cdata["cooldown"]

	var shape: String = cdata["shape"]
	var base_dmg: int = cdata["damage"] * (2 if _battle_shout_active else 1)
	# SHARP tier: +20% damage (rounds up)
	var damage: int = ceili(base_dmg * 1.2) if GameManager.combo_tier >= 1 else base_dmg
	_battle_shout_active = false

	if shape == "orb":
		_fire_wand_orb()
		_spawn_attack_anim(true)
		return

	if shape == "bolt":
		_fire_crossbow()
		return

	# Melee shapes: jab / slash / thrust
	_start_lunge()
	var hit_guards := _get_attack_tiles(shape)
	var hit_any := false
	for guard in hit_guards:
		if not guard.has_method("hurt"):
			continue
		var was_alive := is_instance_valid(guard)
		var hit_dir: Vector2 = (guard.global_position - global_position).normalized()
		var slammed: bool = _is_guard_against_wall(guard, hit_dir)
		guard.hurt(damage, hit_dir)
		GameManager.record_combo_hit()
		hit_any = true
		# Wall slam: guard knocked into wall = bonus 1 damage
		if slammed and is_instance_valid(guard):
			guard.hurt(1, hit_dir)
			_popup("WALL SLAM!", Color(1.0, 0.70, 0.20))
		if was_alive and not is_instance_valid(guard):
			GameManager.record_takedown(true)
			_post_kill_effects(guard, false)
			var noise_r2: float = cdata["noise_r"]
			if noise_r2 > 0.0:
				GameManager.raise_wanted_level(1)
			GameManager.check_wanted_decay(get_tree())
			# Shadow blade: Ghost Strike — kill resets cooldown instantly
			if weapon in ["SHADOW_BLADE", "GHOST_BLADE", "VOID_REAPER"]:
				_attack_cooldown = 0.0
				_popup("GHOST STRIKE!", Color(0.45, 0.90, 0.65))
			# Sword: Kill Momentum — each kill reduces remaining cooldown
			elif weapon in ["LONGSWORD", "BROADSWORD", "BLADESONG"]:
				_attack_cooldown = max(0.0, _attack_cooldown - 0.20)

	# Jab weapons: Quick Combo — every 3rd combo hit resets cooldown
	if shape == "jab" and hit_any and GameManager.combo_hits > 0 and GameManager.combo_hits % 3 == 0:
		_attack_cooldown = 0.0
		_popup("QUICK COMBO!", Color(0.95, 0.80, 0.20))

	var noise_r: float = cdata["noise_r"]
	if noise_r > 0.0:
		emit_noise(NoiseLevel.LOUD)
	else:
		emit_noise(NoiseLevel.QUIET)

	_spawn_attack_anim(noise_r == 0.0)
	if hit_any:
		_trigger_hitstop()
		GameManager.shake(2.5, 0.16)

func _get_attack_tiles(shape: String) -> Array:
	var guards_hit: Array = []
	var tile := TILE_SIZE

	for guard in get_tree().get_nodes_in_group("guards"):
		var to_g: Vector2 = guard.global_position - global_position

		match shape:
			"jab":
				var dist: float = to_g.dot(facing)
				var perp: float = absf(to_g.dot(facing.rotated(PI * 0.5)))
				if dist >= 0.0 and dist <= tile * 1.2 and perp <= tile * 0.7:
					guards_hit.append(guard)
			"slash":
				if to_g.length() <= tile * 1.6:
					var angle: float = facing.angle_to(to_g.normalized())
					if absf(angle) <= deg_to_rad(70.0):
						guards_hit.append(guard)
			"thrust":
				var dist: float = to_g.dot(facing)
				var perp: float = absf(to_g.dot(facing.rotated(PI * 0.5)))
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

func _try_dodge():
	if _dodge_cooldown > 0.0 or is_carrying_body:
		if _dodge_cooldown > 0.0:
			_popup("Roll not ready (%.1fs)" % _dodge_cooldown, Color(0.55, 0.50, 0.45))
		return
	# Slide forward up to _DODGE_TILES tiles, stopping before any wall
	var final_pos: Vector2 = position
	for step in range(1, _DODGE_TILES + 1):
		var target: Vector2 = position + facing * TILE_SIZE * step
		if is_position_blocked(target):
			break
		final_pos = target
	position       = final_pos
	_dodge_cooldown = _DODGE_CD
	_dodge_iframes  = _DODGE_IFRAMES
	_start_slide(facing)
	emit_noise(NoiseLevel.SILENT)
	_popup("ROLL", Color(0.45, 0.75, 1.0))
	GameManager.shake(0.8, 0.06)

func _do_charged_attack():
	var cdata: Dictionary = GameManager.WEAPON_COMBAT.get(weapon, GameManager.WEAPON_COMBAT["NONE"])
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = cdata["cooldown"] * 1.5   # slower recovery after big swing

	var shape: String = cdata["shape"]
	var base_dmg: int = cdata["damage"] * (2 if _battle_shout_active else 1)
	var damage: int   = base_dmg * 2             # charged = double base
	_battle_shout_active = false

	if shape == "orb":
		_fire_wand_orb()
		_spawn_attack_anim(true)
		_popup("CHARGED ORB!", Color(0.70, 0.30, 1.00))
		return

	if shape == "bolt":
		_fire_crossbow()
		return

	# Melee — charged shapes expand one tier: jab→slash, slash→wider, thrust→longer
	var charged_shape: String = shape
	match shape:
		"jab":   charged_shape = "slash"
		"slash": charged_shape = "slash"   # wider handled via damage; same tile check
		"thrust": charged_shape = "thrust"

	_start_lunge()
	GameManager.shake(4.0, 0.22)
	var hit_guards := _get_attack_tiles_charged(charged_shape)
	var hit_any := false
	for guard in hit_guards:
		if not guard.has_method("hurt"):
			continue
		var was_alive: bool = is_instance_valid(guard)
		var hit_dir: Vector2 = (guard.global_position - global_position).normalized()
		# Check wall position BEFORE hurt (guard may be freed after)
		var against_wall: bool = was_alive and _is_guard_against_wall(guard, hit_dir)
		guard.hurt(damage, hit_dir)
		hit_any = true
		if against_wall and is_instance_valid(guard):
			guard.hurt(1, hit_dir)
			_popup("WALL SLAM!", Color(1.0, 0.70, 0.20))
		if was_alive and not is_instance_valid(guard):
			GameManager.record_takedown(true)
			_post_kill_effects(guard, false)
			var noise_r2: float = cdata["noise_r"]
			if noise_r2 > 0.0:
				GameManager.raise_wanted_level(1)
			GameManager.check_wanted_decay(get_tree())

	var noise_r: float = cdata["noise_r"]
	if noise_r > 0.0:
		emit_noise(NoiseLevel.LOUD)
	else:
		emit_noise(NoiseLevel.QUIET)

	_spawn_attack_anim_charged(noise_r == 0.0)
	_popup("CHARGED STRIKE!" if hit_any else "CHARGED!", Color(1.0, 0.85, 0.20))
	if hit_any:
		_trigger_hitstop()

func _get_attack_tiles_charged(shape: String) -> Array:
	var guards_hit: Array = []
	var tile := TILE_SIZE
	for guard in get_tree().get_nodes_in_group("guards"):
		var to_g: Vector2 = guard.global_position - global_position
		match shape:
			"slash":
				# Wider + longer arc for charged strikes
				if to_g.length() <= tile * 2.2:
					var angle: float = facing.angle_to(to_g.normalized())
					if absf(angle) <= deg_to_rad(90.0):
						guards_hit.append(guard)
			"thrust":
				var dist: float = to_g.dot(facing)
				var perp: float = absf(to_g.dot(facing.rotated(PI * 0.5)))
				if dist >= 0.0 and dist <= tile * 3.0 and perp <= tile * 0.7:
					guards_hit.append(guard)
			"jab":
				var dist: float = to_g.dot(facing)
				var perp: float = absf(to_g.dot(facing.rotated(PI * 0.5)))
				if dist >= 0.0 and dist <= tile * 1.8 and perp <= tile * 0.9:
					guards_hit.append(guard)
	return guards_hit

func _is_guard_against_wall(guard_node: Node, hit_dir: Vector2) -> bool:
	if not is_instance_valid(guard_node):
		return false
	var push_pos: Vector2 = guard_node.global_position + hit_dir.normalized() * TILE_SIZE
	return is_position_blocked(push_pos)

func _spawn_attack_anim_charged(was_silent: bool):
	var anim_script = load("res://WeaponAttackAnim.gd")
	var n := Node2D.new()
	n.set_script(anim_script)
	get_tree().root.add_child(n)
	n.global_position = global_position
	n.setup(weapon, facing, was_silent)
	n.scale = Vector2(1.6, 1.6)   # bigger anim for charged hit

func _start_slide(dir: Vector2):
	if _sprite == null:
		return
	# Sprite starts at the opposite end of the direction (where we came from)
	# and slides toward zero (our new tile position)
	_slide_from = -dir * float(TILE_SIZE)
	_slide_t    = 1.0

func _start_lunge():
	_lunge_t = 1.0

func _trigger_hitstop():
	_hitstop_t = 0.05

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
	# Room-clear bonus: if no living guards remain in the room of the kill, award +50 gp
	_check_room_clear_bonus()

func _check_room_entry():
	var level_map = get_tree().get_first_node_in_group("levelmap")
	if level_map == null or not level_map.has_method("_tile_to_room"):
		return
	var cur_room: int = level_map._tile_to_room(
		Vector2i(int(global_position.x / 16), int(global_position.y / 16)))
	if cur_room == _last_room or cur_room < 0:
		return
	_last_room = cur_room
	# Show patrol paths of all guards currently in this room
	for g in get_tree().get_nodes_in_group("guards"):
		if not is_instance_valid(g):
			continue
		var grm: int = level_map._tile_to_room(
			Vector2i(int(g.global_position.x / 16), int(g.global_position.y / 16)))
		if grm == cur_room and g.has_method("start_patrol_preview"):
			g.start_patrol_preview()

func _check_room_clear_bonus():
	var level_map = get_tree().get_first_node_in_group("levelmap")
	if level_map == null or not level_map.has_method("_tile_to_room"):
		return
	var room_idx: int = level_map._tile_to_room(
		Vector2i(int(global_position.x / 16), int(global_position.y / 16)))
	if room_idx < 0:
		return
	if GameManager.cleared_rooms.size() > room_idx and GameManager.cleared_rooms[room_idx]:
		return  # already awarded
	for g in get_tree().get_nodes_in_group("guards"):
		if not is_instance_valid(g):
			continue
		var grm: int = level_map._tile_to_room(
			Vector2i(int(g.global_position.x / 16), int(g.global_position.y / 16)))
		if grm == room_idx:
			return  # living guard still in room
	# All guards in room are cleared
	while GameManager.cleared_rooms.size() <= room_idx:
		GameManager.cleared_rooms.append(false)
	if GameManager.cleared_rooms[room_idx]:
		return
	GameManager.cleared_rooms[room_idx] = true
	GameManager.add_gold(50)
	_popup("ROOM CLEARED  +50gp", Color(0.85, 0.72, 0.18))
	GameManager.shake(1.5, 0.12)

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
		"SELLSWORD":    _ability_battle_shout()

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

func _ability_battle_shout():
	# Stagger all guards within 64px, force them to ALERT (pulls focus to player)
	# and grant the next melee hit double damage via a short buff
	var shout_range := 64.0
	var hit_count := 0
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= shout_range:
			if guard.has_method("stagger"):
				guard.stagger(0.8)
			if guard.has_method("_escalate_alert"):
				guard._escalate_alert()
			hit_count += 1
	if hit_count > 0:
		_popup("BATTLE SHOUT — %d guards staggered!" % hit_count, Color(0.90, 0.40, 0.20))
		_battle_shout_active = true
		GameManager.shake(3.0, 0.25)
		emit_noise(NoiseLevel.LOUD)
		GameManager.raise_wanted_level(1)
	else:
		_popup("BATTLE SHOUT — no guards in range", Color(0.55, 0.50, 0.45))
	AudioManager.ability_use()
	ability_cooldown = ABILITY_COOLDOWNS["SELLSWORD"] * (0.70 if GameManager.has_passive("COLD_BLOOD") else 1.0)

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

func _throw_pebble():
	if _pebble_cooldown > 0.0:
		_popup("Pebble ready in %.1fs" % _pebble_cooldown, Color(0.55, 0.50, 0.40))
		return
	_pebble_cooldown = _PEBBLE_CD
	var pebble := Node2D.new()
	pebble.set_script(load("res://PebbleNode.gd"))
	get_tree().root.add_child(pebble)
	pebble.global_position = global_position
	pebble.call("setup", facing, _PEBBLE_RANGE)
	_popup("[Q] Pebble thrown", Color(0.72, 0.62, 0.38))

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
		var is_alert: bool = best_guard.get("alert_state") == best_guard.AlertState.ALERT
		var is_unaware: bool = best_guard.get("alert_state") == best_guard.AlertState.UNAWARE
		var cdata: Dictionary = GameManager.WEAPON_COMBAT.get(weapon, GameManager.WEAPON_COMBAT["CROSSBOW"])
		# Headshot bonus: +1 damage on unaware targets
		var headshot_bonus: int = 1 if is_unaware else 0
		if headshot_bonus > 0:
			_popup("HEADSHOT!", Color(0.90, 0.65, 0.15))
		if is_alert:
			# Combat shot — deal HP damage, don't instant-kill
			var guard_ref: Node = best_guard
			best_guard.hurt(cdata["damage"] + headshot_bonus)
			if not is_instance_valid(guard_ref):
				GameManager.record_takedown(true)
				_post_kill_effects(guard_ref, is_silent)
				if not is_silent:
					GameManager.raise_wanted_level(1)
				GameManager.check_wanted_decay(get_tree())
		else:
			# Stealth shot — instant takedown
			best_guard.takedown(is_silent)
			GameManager.record_takedown(true)
			_post_kill_effects(best_guard, is_silent)
		if not is_silent:
			emit_noise(NoiseLevel.LOUD)
		# REPEATING_CROSSBOW: pierce on lucky shot
		if weapon == "REPEATING_CROSSBOW" and randi_range(1, 20) == 20:
			for g2 in get_tree().get_nodes_in_group("guards"):
				if g2 != best_guard and best_guard.global_position.distance_to(g2.global_position) <= 24.0:
					if g2.get("alert_state") == g2.AlertState.ALERT:
						g2.hurt(cdata["damage"])
					else:
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
	var race := GameManager.selected_race

	# Slide/lunge visual offset — body moves with sprite-like fluidity
	var vis: Vector2 = Vector2.ZERO
	if _slide_t > 0.0:
		vis = _slide_from * (_slide_t * _slide_t)
	elif _lunge_t > 0.0:
		vis = facing * _LUNGE_PX * sin(_lunge_t * PI)

	# ── Patrol route overlay ──────────────────────────────────────────────────
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

	# ── Character body ─────────────────────────────────────────────────────────
	if is_hidden:
		draw_arc(vis, 5.0, 0, TAU, 16, Color(0.55, 0.30, 0.95, 0.30), 1.0)
		draw_circle(vis, 2.0, Color(0.40, 0.20, 0.75, 0.18))
	else:
		_draw_player_svg(vis, f, perp, cls, race)

	# Wood Elf vanish shimmer
	if race == "WOOD_ELF" and GameManager._vanish_active:
		draw_arc(vis, 9.0, 0, TAU, 20, Color(0.30, 0.90, 0.45, 0.45), 1.5)

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

	# ── Weapon visual (drawn on top of body, at vis offset) ──────────────────
	_draw_weapon_svg(vis, f, perp)

	# ── Charge attack buildup ─────────────────────────────────────────────────
	if _attack_held and _attack_hold_t >= 0.12:
		var ct: float = clamp((_attack_hold_t - 0.12) / (_CHARGE_THRESHOLD - 0.12), 0.0, 1.0)
		var pulse: float = (sin(_anim_t * 18.0) + 1.0) * 0.5
		var ring_r: float = 10.0 + ct * 6.0
		draw_arc(Vector2.ZERO, ring_r + 3.0, 0, TAU, 24, Color(1.0, 0.85, 0.20, ct * 0.22), 4.0)
		draw_arc(Vector2.ZERO, ring_r, 0, TAU, 24,
			Color(1.0, 0.80, 0.10, ct * 0.60 + pulse * 0.15), 2.0)
		if ct >= 1.0:
			draw_arc(Vector2.ZERO, ring_r - 2.0, 0, TAU, 20,
				Color(1.0, 1.0, 0.70, 0.55 + pulse * 0.25), 1.5)

	# ── Parry window ─────────────────────────────────────────────────────────
	if _parry_t > 0.0:
		var pf: float = _parry_t / _PARRY_WINDOW
		draw_arc(Vector2.ZERO, 10.0 + (1.0 - pf) * 3.0, 0, TAU, 20,
			Color(0.35, 0.95, 0.45, pf * 0.70), 2.5)

	# ── Dodge i-frame shimmer ─────────────────────────────────────────────────
	if _dodge_iframes > 0.0:
		var df: float = _dodge_iframes / _DODGE_IFRAMES
		draw_arc(Vector2.ZERO, 9.0 + df * 3.0, 0, TAU, 20,
			Color(0.45, 0.75, 1.0, df * 0.55), 2.0)

	# ── Hit flash overlay ─────────────────────────────────────────────────────
	if _hit_flash_timer > 0.0:
		var hf_alpha := (_hit_flash_timer / _HIT_FLASH_DURATION) * 0.45
		draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.10, 0.10, hf_alpha))

	# ── Sneak shimmer ─────────────────────────────────────────────────────────
	if is_sneaking:
		draw_arc(Vector2.ZERO, 7.5, 0, TAU, 20, Color(0.45, 0.75, 1.0, 0.22), 1.0)
		var fa := f.angle()
		draw_arc(Vector2.ZERO, 9.0, fa - 0.9, fa + 0.9, 12, Color(0.60, 0.88, 1.0, 0.35), 1.2)
		var pulse_a := _move_cooldown / SNEAK_COOLDOWN
		draw_arc(Vector2.ZERO, 11.0 + pulse_a * 3.0, 0, TAU, 20,
			Color(0.45, 0.75, 1.0, (1.0 - pulse_a) * 0.12), 0.8)

	# ── Loot glint ────────────────────────────────────────────────────────────
	if has_loot:
		var loot_pos := vis + perp * -3.5 + f * 2.0 + Vector2(0, -3)
		var loot_bob := sin(_anim_t * 4.0) * 0.6
		draw_circle(loot_pos + Vector2(0, loot_bob), 2.5, Color(0.95, 0.80, 0.10))
		draw_circle(loot_pos + Vector2(-0.5, -0.5 + loot_bob), 1.0, Color(1.0, 0.96, 0.70))
		draw_arc(loot_pos + Vector2(0, loot_bob), 3.5, 0, TAU, 12,
			Color(0.95, 0.80, 0.10, 0.35 + abs(sin(_anim_t * 4.0)) * 0.15), 1.0)

	# ── Body carry indicator ──────────────────────────────────────────────────
	if is_carrying_body:
		var bp := vis - f * 5.0 + Vector2(0, 2)
		draw_circle(bp, 3.8, Color(0.28, 0.08, 0.08, 0.80))
		draw_arc(bp, 5.0, 0, TAU, 12, Color(0.85, 0.55, 0.30, 0.60), 1.2)

	# ── Ability charge ring ───────────────────────────────────────────────────
	var max_cd: float = ABILITY_COOLDOWNS.get(cls, 10.0)
	if ability_cooldown <= 0.0:
		draw_arc(Vector2.ZERO, 8.5, -PI * 0.5, -PI * 0.5 + TAU, 20,
			Color(0.55, 0.30, 0.95, 0.28), 1.0)
	else:
		var frac: float = 1.0 - (ability_cooldown / max_cd)
		if frac > 0.0:
			draw_arc(Vector2.ZERO, 8.5, -PI * 0.5, -PI * 0.5 + TAU * frac, 20,
				Color(0.55, 0.30, 0.95, 0.20), 1.0)

# ── SVG character drawing ─────────────────────────────────────────────────────
func _draw_player_svg(vis_in: Vector2, f: Vector2, perp: Vector2, cls: String, race: String):
	# ── Isometric 3/4 perspective character renderer ──────────────────────────
	# Painter's algorithm: shadow → back leg → boots → torso (3 faces) → cape →
	# arms → head → race features → hood/helmet
	var t: float        = _anim_t
	var moving: bool    = _move_cooldown > 0.02
	var sa: float       = 0.72 if is_sneaking else 1.0
	var lunge_t: float  = _lunge_t if "_lunge_t" in self else 0.0
	var lunge_off: Vector2 = f * sin(lunge_t * PI) * 4.0 if lunge_t > 0.0 else Vector2.ZERO
	var sneak_off: Vector2 = Vector2(0, 2.0) if is_sneaking else Vector2.ZERO
	var vis: Vector2    = vis_in + lunge_off + sneak_off

	# Walk cycle
	var swing_speed: float = 9.0
	var leg_swing: float   = sin(t * swing_speed) * 2.5
	if is_sneaking: leg_swing *= 0.5
	if not moving:  leg_swing = 0.0
	var bob: float    = (abs(sin(t * swing_speed)) * 0.7) if moving else 0.0
	if is_sneaking:   bob *= 0.4
	var arm_swing: float  = cos(t * swing_speed) * 1.5 if moving else 0.0
	var cape_flap: float  = sin(t * 3.2) * 1.5

	# Class palette
	var pants_col: Color
	var torso_front: Color
	var trim_col: Color
	var boot_col: Color
	match cls:
		"CUTPURSE":
			pants_col   = Color(0.28, 0.22, 0.12)
			torso_front = Color(0.40, 0.26, 0.12)
			trim_col    = Color(0.88, 0.68, 0.18)
			boot_col    = Color(0.32, 0.20, 0.10)
		"SHADOWDANCER":
			pants_col   = Color(0.10, 0.08, 0.18)
			torso_front = Color(0.16, 0.08, 0.28)
			trim_col    = Color(0.60, 0.18, 0.92)
			boot_col    = Color(0.16, 0.10, 0.26)
		"ASSASSIN":
			pants_col   = Color(0.08, 0.08, 0.10)
			torso_front = Color(0.10, 0.10, 0.12)
			trim_col    = Color(0.80, 0.06, 0.10)
			boot_col    = Color(0.06, 0.06, 0.08)
		_:
			pants_col   = Color(0.20, 0.16, 0.30)
			torso_front = Color(0.22, 0.18, 0.36)
			trim_col    = Color(0.55, 0.45, 0.85)
			boot_col    = Color(0.18, 0.14, 0.24)

	var rd: Dictionary = GameManager.RACES.get(race, {})
	var skin_col: Color = rd.get("skin", Color(0.82, 0.68, 0.52))

	# Lunge state
	var lunging: bool = lunge_t > 0.0

	# ── A. Ground shadow ──────────────────────────────────────────────────────
	var shadow_pos: Vector2 = vis + f * 0.6 + Vector2(0, 1.6)
	draw_colored_polygon(_iso_ellipse(shadow_pos, 6.0, 2.4, 12), Color(0, 0, 0, 0.40 * sa))

	# ── B. Legs (back leg first) ──────────────────────────────────────────────
	var leg_back_off: Vector2  = -perp * 2.5 + f * (leg_swing if not lunging else -3.0)
	var leg_front_off: Vector2 =  perp * 2.5 + f * (-leg_swing if not lunging else 1.0)
	_draw_iso_leg(vis + leg_back_off,  pants_col.darkened(0.18), bob * 0.5, sa)
	_draw_iso_leg(vis + leg_front_off, pants_col,                bob,        sa)

	# ── C. Boots (isometric boxes) ────────────────────────────────────────────
	_draw_iso_boot(vis + leg_back_off  + Vector2(0, 4.5), f, perp, boot_col.darkened(0.20), sa)
	_draw_iso_boot(vis + leg_front_off + Vector2(0, 4.5), f, perp, boot_col, sa)

	# ── D. Torso (3-face isometric box) ───────────────────────────────────────
	var tw: float = 4.5
	var td: float = 2.5
	var th: float = 8.0
	var b: float  = bob
	# Front face
	var front_face := PackedVector2Array([
		vis + Vector2(-tw, -th + b),
		vis + Vector2( tw, -th + b),
		vis + Vector2( tw + td * 0.4, -th * 0.12 + td * 0.5 + b),
		vis + Vector2(-tw + td * 0.4, -th * 0.12 + td * 0.5 + b),
	])
	# Right shadow face
	var right_face := PackedVector2Array([
		vis + Vector2(tw, -th + b),
		vis + Vector2(tw + td, -th + td * 0.5 + b),
		vis + Vector2(tw + td, td * 0.5 + b),
		vis + Vector2(tw + td * 0.4, -th * 0.12 + td * 0.5 + b),
	])
	# Top face
	var top_face := PackedVector2Array([
		vis + Vector2(-tw, -th + b),
		vis + Vector2( tw, -th + b),
		vis + Vector2( tw + td, -th + td * 0.5 + b),
		vis + Vector2(-tw + td, -th + td * 0.5 + b),
	])
	draw_colored_polygon(right_face, _shade(torso_front, -0.35, sa))
	draw_colored_polygon(front_face, _shade(torso_front,  0.00, sa))
	draw_colored_polygon(top_face,   _shade(torso_front,  0.22, sa))
	# Crisp outline
	var outline_col: Color = Color(0.04, 0.03, 0.06, 0.85 * sa)
	draw_polyline(front_face + PackedVector2Array([front_face[0]]), outline_col, 0.6)
	draw_polyline(top_face   + PackedVector2Array([top_face[0]]),   outline_col, 0.6)

	# Class-specific torso details
	match cls:
		"CUTPURSE":
			# Vest seam down the middle
			draw_line(vis + Vector2(td * 0.2, -th + b + 0.5),
				vis + Vector2(td * 0.3, -th * 0.15 + b), Color(0.18, 0.12, 0.05, 0.85 * sa), 0.6)
			# Belt
			draw_line(vis + Vector2(-tw + 0.5, -th * 0.25 + b),
				vis + Vector2( tw - 0.5, -th * 0.25 + b), Color(0.20, 0.13, 0.05, sa), 1.0)
			# Buckle
			draw_circle(vis + Vector2(td * 0.2, -th * 0.25 + b), 0.7, trim_col)
		"SHADOWDANCER":
			# Purple trim on top edge
			draw_line(vis + Vector2(-tw, -th + b),
				vis + Vector2( tw, -th + b), Color(trim_col.r, trim_col.g, trim_col.b, 0.85 * sa), 0.9)
			# Rune sigil
			var r_p: Vector2 = vis + Vector2(td * 0.2, -th * 0.45 + b)
			draw_arc(r_p, 1.6, 0, TAU, 12, Color(trim_col.r, trim_col.g, trim_col.b, 0.55 * sa), 0.6)
			draw_line(r_p - Vector2(1.2, 0), r_p + Vector2(1.2, 0), Color(trim_col.r, trim_col.g, trim_col.b, 0.55 * sa), 0.5)
		"ASSASSIN":
			# Red shoulder plate (top-left)
			var pauldron := PackedVector2Array([
				vis + Vector2(-tw - 0.5, -th + b),
				vis + Vector2(-tw + 2.0, -th + b),
				vis + Vector2(-tw + 2.4, -th + 1.4 + b),
				vis + Vector2(-tw - 0.3, -th + 1.6 + b),
			])
			draw_colored_polygon(pauldron, _shade(trim_col, 0.10, sa))
			draw_polyline(pauldron + PackedVector2Array([pauldron[0]]), outline_col, 0.5)
			# Crossbelt
			draw_line(vis + Vector2(-tw + 0.3, -th + 2.0 + b),
				vis + Vector2( tw - 0.3, -th * 0.1 + b), Color(0.20, 0.04, 0.06, 0.80 * sa), 0.7)

	# ── E. Cape (SHADOWDANCER / ASSASSIN) ─────────────────────────────────────
	if cls == "SHADOWDANCER" or cls == "ASSASSIN":
		_draw_cape(vis, f, perp, cls, t, b, cape_flap, sa, trim_col)

	# ── F. Arms ───────────────────────────────────────────────────────────────
	var inward: float = 0.8 if is_sneaking else 0.0
	# Right arm (off-hand) hangs at side
	var r_shoulder: Vector2 = vis + Vector2( tw - 0.5 - inward, -th + 1.0 + b)
	var r_hand: Vector2     = vis + Vector2( tw + 0.5 - inward, -th * 0.35 + b + arm_swing)
	_draw_iso_arm(r_shoulder, r_hand, torso_front.darkened(0.25), skin_col, sa)
	# Left arm (weapon arm) — forward & up; extended on lunge
	var l_extend: float = 3.5 if lunging else 0.0
	var l_shoulder: Vector2 = vis + Vector2(-tw + 0.5 + inward, -th + 1.0 + b)
	var l_hand: Vector2     = vis + Vector2(-tw - 1.5 + inward, -th * 0.55 + b - arm_swing) + f * l_extend
	_draw_iso_arm(l_shoulder, l_hand, torso_front.darkened(0.18), skin_col, sa)

	# ── G. Head (isometric 3/4) ───────────────────────────────────────────────
	var head_r: float = 5.5
	if race == "HALFLING": head_r *= 1.12
	if race == "DWARF":    head_r *= 1.05
	var head_pos: Vector2 = vis + Vector2(td * 0.5, -th - head_r * 1.1 + b)

	# Hood backing (drawn first so face is in front)
	var hood_back_col: Color
	match cls:
		"CUTPURSE":     hood_back_col = Color(0.18, 0.12, 0.06, 0.92 * sa)
		"SHADOWDANCER": hood_back_col = Color(0.06, 0.04, 0.14, 0.95 * sa)
		"ASSASSIN":     hood_back_col = Color(0.05, 0.05, 0.07, 0.95 * sa)
		_:              hood_back_col = Color(0.10, 0.08, 0.18, 0.90 * sa)
	draw_circle(head_pos + Vector2(-0.6, -0.4), head_r + 1.4, hood_back_col)

	# Head skin: base + shadow + highlight (3-value shading)
	draw_circle(head_pos, head_r, _shade(skin_col, 0.00, sa))
	draw_circle(head_pos + Vector2(-1.5, 1.0), head_r * 0.75, _shade(skin_col, -0.30, sa))
	draw_circle(head_pos + Vector2( 1.0, -1.5), head_r * 0.45, _shade(skin_col, 0.25, sa))
	# Crisp head outline
	draw_arc(head_pos, head_r, 0, TAU, 22, outline_col, 0.6)

	# Eyes (class-tinted glow)
	var eye_col: Color
	match cls:
		"CUTPURSE":     eye_col = Color(0.95, 0.82, 0.28)
		"SHADOWDANCER": eye_col = Color(0.82, 0.42, 1.00)
		"ASSASSIN":     eye_col = Color(0.98, 0.28, 0.18)
		_:              eye_col = Color(0.90, 0.85, 0.70)
	var eye_r_size: float = 1.5 if race == "HALFLING" else 1.1
	var eye_lp: Vector2 = head_pos + Vector2(-1.8, 0.8)
	var eye_rp: Vector2 = head_pos + Vector2( 1.4, 0.8)
	draw_circle(eye_lp, eye_r_size, Color(0.02, 0.02, 0.04, sa))
	draw_circle(eye_rp, eye_r_size, Color(0.02, 0.02, 0.04, sa))
	draw_circle(eye_lp, eye_r_size * 0.65, Color(eye_col.r, eye_col.g, eye_col.b, sa))
	draw_circle(eye_rp, eye_r_size * 0.65, Color(eye_col.r, eye_col.g, eye_col.b, sa))

	# Race features
	match race:
		"TIEFLING":
			var horn_col: Color = Color(0.16, 0.06, 0.10, sa)
			draw_arc(head_pos + Vector2(-3, -4), 3.5, PI * 0.3, PI * 1.0, 10, horn_col, 1.5)
			draw_arc(head_pos + Vector2( 3, -4), 3.5, PI * 0.0, PI * 0.7, 10, horn_col, 1.5)
			# Horn highlights
			draw_arc(head_pos + Vector2(-3, -4), 3.5, PI * 0.5, PI * 0.8, 6, Color(0.45, 0.10, 0.18, 0.7 * sa), 0.6)
		"WOOD_ELF":
			var ear_col: Color = _shade(skin_col, -0.10, sa)
			draw_colored_polygon(PackedVector2Array([
				head_pos + Vector2(-head_r * 0.9, -0.5),
				head_pos + Vector2(-head_r - 2.2, -2.5),
				head_pos + Vector2(-head_r * 0.7,  1.2),
			]), ear_col)
			draw_colored_polygon(PackedVector2Array([
				head_pos + Vector2(head_r * 0.9, -0.5),
				head_pos + Vector2(head_r + 2.2, -2.5),
				head_pos + Vector2(head_r * 0.7,  1.2),
			]), ear_col)
		"DWARF":
			var beard_col: Color = Color(0.72, 0.55, 0.28, sa)
			for i in range(3):
				var x: float = -1.6 + float(i) * 1.6
				draw_line(head_pos + Vector2(x, head_r * 0.5),
					head_pos + Vector2(x * 0.7, head_r + 2.4),
					beard_col, 1.4)
			# Wider jaw shading
			draw_circle(head_pos + Vector2(0, head_r * 0.4), head_r * 0.55, beard_col.darkened(0.15))
		"HALFLING":
			# Rosy cheeks
			draw_circle(head_pos + Vector2(-2.8, 1.8), 1.0, Color(0.92, 0.48, 0.42, 0.45 * sa))
			draw_circle(head_pos + Vector2( 2.4, 1.8), 1.0, Color(0.92, 0.48, 0.42, 0.45 * sa))

	# Hood / helmet (front overlay)
	match cls:
		"CUTPURSE":
			# Tight hood wrapping top of head down sides
			var hood_col: Color = Color(0.35, 0.22, 0.10, sa)
			draw_colored_polygon(PackedVector2Array([
				head_pos + Vector2(-head_r - 0.5, -0.8),
				head_pos + Vector2(-head_r * 0.6, -head_r - 1.4),
				head_pos + Vector2( head_r * 0.4, -head_r - 1.6),
				head_pos + Vector2( head_r + 0.4, -1.4),
				head_pos + Vector2( head_r - 0.5,  0.6),
				head_pos + Vector2( head_r * 0.2, -1.0),
				head_pos + Vector2(-head_r * 0.4, -1.2),
				head_pos + Vector2(-head_r + 0.3,  0.4),
			]), _shade(hood_col, 0.00, sa))
			# Top highlight
			draw_arc(head_pos + Vector2(-0.3, -1.0), head_r + 0.3, PI * 1.1, PI * 1.85, 10,
				_shade(hood_col, 0.30, sa), 0.8)
		"SHADOWDANCER":
			# Deep cowl extending forward
			var cowl_col: Color = Color(0.05, 0.03, 0.12, sa)
			draw_colored_polygon(PackedVector2Array([
				head_pos + Vector2(-head_r - 1.2, -1.0),
				head_pos + Vector2(-head_r * 0.4, -head_r - 2.4),
				head_pos + Vector2( head_r * 0.6, -head_r - 2.2),
				head_pos + Vector2( head_r + 1.8, -0.4),
				head_pos + Vector2( head_r + 0.6,  2.2),
				head_pos + Vector2( head_r * 0.2, -0.4),
				head_pos + Vector2(-head_r * 0.6, -0.6),
				head_pos + Vector2(-head_r - 0.4,  1.8),
			]), cowl_col)
			# Inner purple glow
			draw_arc(head_pos + Vector2(0, -0.2), head_r + 0.6, PI * 0.05, PI * 0.95, 14,
				Color(trim_col.r, trim_col.g, trim_col.b, 0.45 * sa), 0.8)
			draw_arc(head_pos + Vector2(0, -0.2), head_r + 1.6, PI * 0.1, PI * 0.9, 12,
				Color(trim_col.r, trim_col.g, trim_col.b, 0.20 * sa), 1.4)
		"ASSASSIN":
			# Half-visor across forehead+nose (eyes glow through)
			var visor: PackedVector2Array = PackedVector2Array([
				head_pos + Vector2(-head_r - 0.2, -0.4),
				head_pos + Vector2(-head_r * 0.7, -head_r * 0.95),
				head_pos + Vector2( head_r * 0.8, -head_r * 0.9),
				head_pos + Vector2( head_r + 0.2, -0.2),
				head_pos + Vector2( head_r * 0.6,  1.6),
				head_pos + Vector2(-head_r * 0.6,  1.7),
			])
			draw_colored_polygon(visor, Color(0.18, 0.18, 0.22, sa))
			# Eye slit highlight
			draw_line(head_pos + Vector2(-head_r * 0.7, 0.4),
				head_pos + Vector2( head_r * 0.7, 0.4),
				Color(trim_col.r, trim_col.g, trim_col.b, 0.55 * sa), 0.6)
			# Re-draw glowing eyes over the visor
			draw_circle(eye_lp, eye_r_size * 0.85, Color(eye_col.r, eye_col.g, eye_col.b, sa))
			draw_circle(eye_rp, eye_r_size * 0.85, Color(eye_col.r, eye_col.g, eye_col.b, sa))
			# Glow halo
			draw_circle(eye_lp, eye_r_size * 1.6, Color(eye_col.r, eye_col.g, eye_col.b, 0.25 * sa))
			draw_circle(eye_rp, eye_r_size * 1.6, Color(eye_col.r, eye_col.g, eye_col.b, 0.25 * sa))

	# Class colors
	var cloak_col: Color
	var accent_col: Color
	match cls:
		"CUTPURSE":
			cloak_col  = Color(0.28, 0.22, 0.09) if not is_sneaking else Color(0.12, 0.09, 0.04)
			accent_col = Color(0.88, 0.68, 0.18)
			boot_col   = Color(0.35, 0.22, 0.10)
		"SHADOWDANCER":
			cloak_col  = Color(0.12, 0.08, 0.22) if not is_sneaking else Color(0.05, 0.03, 0.12)
			accent_col = Color(0.55, 0.30, 0.95)
			boot_col   = Color(0.15, 0.10, 0.25)
		"ASSASSIN":
			cloak_col  = Color(0.20, 0.05, 0.05) if not is_sneaking else Color(0.08, 0.02, 0.02)
			accent_col = Color(0.88, 0.18, 0.18)
			boot_col   = Color(0.14, 0.05, 0.05)
		"SELLSWORD":
			cloak_col  = Color(0.26, 0.20, 0.10) if not is_sneaking else Color(0.14, 0.10, 0.05)
			accent_col = Color(0.92, 0.56, 0.18)
			boot_col   = Color(0.32, 0.20, 0.10)
		_:
			cloak_col  = Color(0.20, 0.16, 0.38) if not is_sneaking else Color(0.10, 0.08, 0.20)
			accent_col = Color(0.40, 0.28, 0.72)
			boot_col   = Color(0.18, 0.14, 0.28)

	var cloak_sway: float = sin(t * 5.0) * 0.4

	# ── Ground shadow ─────────────────────────────────────────────────────────
	draw_circle(vis + Vector2(0.4, 1.8), 5.2, Color(0.0, 0.0, 0.0, 0.18 * sa))

	# ── Cape trailing behind ──────────────────────────────────────────────────
	var cape_l := vis - f * 1.0 + perp * (4.8 + cloak_sway)
	var cape_r := vis - f * 1.0 - perp * (4.8 - cloak_sway)
	var cape_tip := vis - f * 11.0 + Vector2(0, bob * 0.3)
	var cape_dark := Color(cloak_col.r * 0.50, cloak_col.g * 0.50, cloak_col.b * 0.55, 0.88 * sa)
	draw_colored_polygon(PackedVector2Array([cape_l, cape_r, cape_tip]), cape_dark)
	# Cape highlight edge
	draw_line(cape_l, cape_tip, Color(cloak_col.r * 1.5, cloak_col.g * 1.5, cloak_col.b * 1.8, 0.28 * sa), 0.7)
	# Inner cape sheen
	var cape_inner_tip := vis - f * 7.0 + Vector2(0, bob * 0.2)
	draw_colored_polygon(PackedVector2Array([
		vis - f * 1.5 + perp * 2.5,
		vis - f * 1.5 - perp * 2.5,
		cape_inner_tip]),
		Color(cloak_col.r * 0.75, cloak_col.g * 0.75, cloak_col.b * 0.80, 0.45 * sa))

	# ── Legs / boots ──────────────────────────────────────────────────────────
	var leg_l_pos := vis + perp * 2.6 + f * (-3.2 + leg_swing * 0.35) + Vector2(0, bob)
	var leg_r_pos := vis - perp * 2.6 + f * (-3.2 - leg_swing * 0.35) + Vector2(0, -bob)
	# Boot shaft
	draw_circle(leg_l_pos - f * 0.5, 1.9, boot_col.darkened(0.28))
	draw_circle(leg_r_pos - f * 0.5, 1.9, boot_col.darkened(0.28))
	# Boot toe
	draw_circle(leg_l_pos + f * 1.4, 1.5, boot_col)
	draw_circle(leg_r_pos + f * 1.4, 1.5, boot_col)
	# Boot highlight
	draw_circle(leg_l_pos + f * 1.4 - perp * 0.6, 0.55, Color(boot_col.r * 1.55, boot_col.g * 1.55, boot_col.b * 1.4, 0.55 * sa))
	draw_circle(leg_r_pos + f * 1.4 + perp * 0.6, 0.55, Color(boot_col.r * 1.55, boot_col.g * 1.55, boot_col.b * 1.4, 0.55 * sa))

	# ── Body / torso ──────────────────────────────────────────────────────────
	var body_pos := vis + Vector2(0, bob * 0.18)
	draw_circle(body_pos, 4.8, cloak_col)
	# Torso highlight (specular)
	draw_circle(body_pos - f * 1.2 + perp * 1.0, 1.6,
		Color(cloak_col.r * 1.7, cloak_col.g * 1.7, cloak_col.b * 1.9, 0.28 * sa))
	# Torso rim (outline-ish effect)
	draw_arc(body_pos, 4.8, 0, TAU, 16,
		Color(cloak_col.r * 0.5, cloak_col.g * 0.5, cloak_col.b * 0.6, 0.55 * sa), 0.8)

	# ── Arms ──────────────────────────────────────────────────────────────────
	var arm_l := vis + perp * 5.4 + f * arm_swing * 0.25 + Vector2(0, bob * 0.15)
	var arm_r := vis - perp * 5.4 - f * arm_swing * 0.25 + Vector2(0, -bob * 0.15)
	var skin_d := Color(skin_col.r * 0.80, skin_col.g * 0.80, skin_col.b * 0.78, sa)
	draw_circle(arm_l, 1.6, skin_d)
	draw_circle(arm_r, 1.6, skin_d)

	# ── Class-specific torso details ──────────────────────────────────────────
	match cls:
		"CUTPURSE":
			# Gold coin pouch on belt
			draw_circle(body_pos - f * 1.0 + perp * 3.5, 1.8, Color(0.28, 0.18, 0.08))
			draw_circle(body_pos - f * 1.0 + perp * 3.5, 1.2, Color(accent_col.r * 0.85, accent_col.g * 0.85, accent_col.b * 0.5))
			# Belt buckle
			var bb := body_pos - f * 0.5
			draw_line(bb + perp * -2.8, bb + perp * 2.8, Color(accent_col.r * 0.65, accent_col.g * 0.50, accent_col.b * 0.15, 0.65), 1.0)
			draw_circle(bb, 0.9, Color(accent_col.r * 0.85, accent_col.g * 0.65, accent_col.b * 0.18))
		"SHADOWDANCER":
			# Rune sigil on chest
			var rune_p := body_pos + f * 1.2
			draw_arc(rune_p, 2.0, 0, TAU, 14, Color(accent_col.r, accent_col.g, accent_col.b, 0.45 * sa), 0.8)
			draw_line(rune_p - perp * 1.5, rune_p + perp * 1.5, Color(accent_col.r, accent_col.g, accent_col.b, 0.35 * sa), 0.7)
			draw_line(rune_p - f * 1.5, rune_p + f * 1.5, Color(accent_col.r, accent_col.g, accent_col.b, 0.35 * sa), 0.7)
		"ASSASSIN":
			# Crossbelt leather straps
			draw_line(body_pos - perp * 4.0 + f * 2.0, body_pos + perp * 4.0 - f * 2.0,
				Color(accent_col.r * 0.55, accent_col.g * 0.18, accent_col.b * 0.18, 0.65 * sa), 1.0)
			draw_line(body_pos + perp * 4.0 + f * 2.0, body_pos - perp * 4.0 - f * 2.0,
				Color(accent_col.r * 0.55, accent_col.g * 0.18, accent_col.b * 0.18, 0.65 * sa), 1.0)
		"SELLSWORD":
			# Pauldrons (shoulder pads)
			var paul_c := Color(0.58, 0.52, 0.48)
			draw_circle(body_pos + perp * 4.5, 2.4, paul_c.darkened(0.2))
			draw_circle(body_pos - perp * 4.5, 2.4, paul_c.darkened(0.2))
			draw_circle(body_pos + perp * 4.5 + f * 0.3, 1.2, paul_c.lightened(0.12))
			draw_circle(body_pos - perp * 4.5 + f * 0.3, 1.2, paul_c.lightened(0.12))

	# ── Hood / head ───────────────────────────────────────────────────────────
	head_pos = vis + f * 3.6 + Vector2(0, bob * 0.45)
	var hood_dark := cloak_col.darkened(0.2)
	draw_circle(head_pos, 3.2, hood_dark)
	# Hood fold lines
	draw_arc(head_pos - f * 1.0, 2.8, f.angle() + PI - 1.0, f.angle() + PI + 1.0, 8,
		Color(cloak_col.r * 0.65, cloak_col.g * 0.65, cloak_col.b * 0.72, 0.40 * sa), 0.8)
	# Hood opening rim — accent color
	draw_arc(head_pos, 3.2, f.angle() - 0.95, f.angle() + 0.95, 10,
		Color(accent_col.r, accent_col.g, accent_col.b, 0.60 * sa), 1.1)
	# Face (skin) visible in hood opening
	var face_pos := head_pos + f * 1.5
	draw_circle(face_pos, 1.6, skin_col)
	# Eyes
	var eye_l := face_pos + perp * 0.55 - f * 0.2
	var eye_r := face_pos - perp * 0.55 - f * 0.2
	draw_circle(eye_l, 0.45, Color(0.05, 0.04, 0.08))
	draw_circle(eye_r, 0.45, Color(0.05, 0.04, 0.08))

	# ── Race-specific details ─────────────────────────────────────────────────
	match race:
		"TIEFLING":
			# Demon horns curving back
			draw_line(head_pos + perp * 2.8 - f * 0.5,
				head_pos + perp * 3.5 - f * 3.0, Color(0.18, 0.06, 0.30), 1.6)
			draw_line(head_pos - perp * 2.8 - f * 0.5,
				head_pos - perp * 3.5 - f * 3.0, Color(0.18, 0.06, 0.30), 1.6)
			# Hellfire eye glow
			draw_circle(eye_l, 0.5, Color(0.95, 0.25, 0.05, 0.85))
			draw_circle(eye_r, 0.5, Color(0.95, 0.25, 0.05, 0.85))
		"WOOD_ELF":
			# Pointed ears extending to the sides
			draw_line(head_pos + perp * 3.0, head_pos + perp * 5.2 + f * 1.2,
				Color(skin_col.r * 0.88, skin_col.g * 0.88, skin_col.b * 0.80), 1.5)
			draw_line(head_pos - perp * 3.0, head_pos - perp * 5.2 + f * 1.2,
				Color(skin_col.r * 0.88, skin_col.g * 0.88, skin_col.b * 0.80), 1.5)
			# Leaf-green eye glow
			draw_circle(eye_l, 0.5, Color(0.28, 0.85, 0.38, 0.90))
			draw_circle(eye_r, 0.5, Color(0.28, 0.85, 0.38, 0.90))
		"HALFLING":
			# Slightly oversized head and rounder hood
			draw_circle(head_pos, 3.6, hood_dark)
			draw_circle(face_pos - f * 0.2, 1.9, skin_col)
			# Rosy cheeks
			draw_circle(face_pos + perp * 1.2 - f * 0.3, 0.7, Color(0.88, 0.48, 0.38, 0.45))
			draw_circle(face_pos - perp * 1.2 - f * 0.3, 0.7, Color(0.88, 0.48, 0.38, 0.45))
		"DWARF":
			# Broader body and proud beard
			draw_circle(body_pos + perp * 5.2, 1.4, Color(0.52, 0.42, 0.28))  # extra width
			draw_circle(body_pos - perp * 5.2, 1.4, Color(0.52, 0.42, 0.28))
			# Braided beard
			var beard_col := Color(0.72, 0.55, 0.28, 0.80)
			draw_circle(face_pos - f * 0.8 + Vector2(0, 2.0), 1.8, beard_col)
			draw_circle(face_pos - f * 0.4 + Vector2(0, 3.5), 1.2, beard_col.darkened(0.1))
			draw_circle(face_pos + Vector2(0, 4.8), 0.8, beard_col.darkened(0.2))

func _draw_weapon_svg(vis: Vector2, f: Vector2, perp: Vector2):
	var t: float = _anim_t
	var w_bob: float = sin(t * 9.0) * 0.4 if _move_cooldown > 0.02 else 0.0
	var lunge_t: float = _lunge_t if "_lunge_t" in self else 0.0
	var lunge_extend: float = sin(lunge_t * PI) * 3.5 if lunge_t > 0.0 else 0.0

	# Hold anchor: forward and up, at left hand
	var grip: Vector2 = vis + f * (5.0 + lunge_extend) + perp * 2.0 + Vector2(0, -9 + w_bob)
	var fwd: Vector2 = f
	var side: Vector2 = perp

	match weapon:
		"SHIV", "DAGGER":
			var reversed: bool = is_sneaking
			var dir_v: Vector2 = -fwd if reversed else fwd
			_draw_blade_tapered(grip, dir_v, side, 7.0, 1.6, 0.4, Color(0.82, 0.80, 0.88), Color(1.0, 0.98, 0.95))
			_draw_grip(grip, dir_v, side, 3.5, Color(0.38, 0.25, 0.12))
			if weapon == "SHIV" and _shiv_thrown:
				draw_line(grip, grip + dir_v * 6.0, Color(0.42, 0.42, 0.44, 0.60), 1.3)
		"STILETTO", "ASSASSIN_FANG":
			_draw_blade_tapered(grip, fwd, side, 8.0, 1.4, 0.3, Color(0.86, 0.84, 0.92), Color(1.0, 1.0, 1.0))
			# Small crossguard
			draw_line(grip + side * 1.2, grip - side * 1.2, Color(0.55, 0.45, 0.20), 1.0)
			_draw_grip(grip, fwd, side, 3.5, Color(0.30, 0.20, 0.08))
			var stip: Vector2 = grip + fwd * 8.0
			draw_circle(stip, 0.7, Color(1.0, 1.0, 1.0, 0.75))
			if weapon == "ASSASSIN_FANG":
				draw_arc(stip, 1.8, 0, TAU, 10, Color(0.72, 0.28, 0.85, 0.55 + abs(sin(t*4.0))*0.3), 0.8)
		"SHORTSWORD":
			_draw_blade_tapered(grip, fwd, side, 10.0, 2.0, 0.5, Color(0.82, 0.80, 0.88), Color(1.0, 0.98, 0.95))
			draw_line(grip + side * 1.8, grip - side * 1.8, Color(0.62, 0.50, 0.22), 1.2)
			_draw_grip(grip, fwd, side, 4.0, Color(0.40, 0.26, 0.12))
			draw_circle(grip - fwd * 4.2, 0.9, Color(0.85, 0.65, 0.20))
		"SHADOW_BLADE", "GHOST_BLADE", "VOID_REAPER", "SMOKE_BLADE":
			var blade_col: Color = Color(0.55, 0.20, 0.85)
			if weapon == "GHOST_BLADE": blade_col = Color(0.40, 0.85, 0.70)
			if weapon == "VOID_REAPER": blade_col = Color(0.20, 0.12, 0.32)
			if weapon == "SMOKE_BLADE": blade_col = Color(0.55, 0.20, 0.78)
			_draw_blade_tapered(grip, fwd, side, 10.0, 2.0, 0.5, blade_col, blade_col.lightened(0.35))
			_draw_grip(grip, fwd, side, 4.0, Color(0.18, 0.10, 0.20))
			var stip2: Vector2 = grip + fwd * 10.0
			var glow_a: float = 0.40 + abs(sin(t * 3.0)) * 0.20
			draw_circle(stip2, 2.0, Color(blade_col.r, blade_col.g, blade_col.b, glow_a))
			if weapon == "SMOKE_BLADE":
				for i in range(3):
					var wisp: Vector2 = stip2 + Vector2(sin(t*5.0 + float(i)*2.1)*1.5, -float(i)*2.5)
					draw_circle(wisp, 1.2 - float(i)*0.3, Color(0.5, 0.1, 0.7, 0.35 - float(i)*0.10))
			if weapon in ["GHOST_BLADE", "VOID_REAPER"] and _ghost_blade_strikes_left > 0:
				draw_line(grip - fwd * 1.5, grip, Color(blade_col.r, blade_col.g, blade_col.b, 0.30), 0.7)
		"GARROTE":
			var gr_l: Vector2 = grip + side * 3.0
			var gr_r: Vector2 = grip - side * 3.0
			draw_line(gr_l, gr_r, Color(0.85, 0.82, 0.78), 0.8)
			# Glint highlight
			draw_line(gr_l + fwd * 0.4, gr_r + fwd * 0.4, Color(1.0, 1.0, 1.0, 0.5), 0.4)
			_draw_iso_grip_handle(gr_l, fwd, side, Color(0.38, 0.25, 0.12))
			_draw_iso_grip_handle(gr_r, fwd, side, Color(0.38, 0.25, 0.12))
		"LONGSWORD":
			_draw_blade_tapered(grip, fwd, side, 14.0, 2.4, 0.6, Color(0.80, 0.80, 0.92), Color(1.0, 1.0, 1.0))
			# Fuller groove
			draw_line(grip + fwd * 1.0, grip + fwd * 13.0, Color(0.62, 0.62, 0.74), 0.5)
			# Ornate guard wings
			draw_colored_polygon(PackedVector2Array([
				grip + side * 2.6, grip + side * 1.0 + fwd * 0.6, grip + side * 1.0 - fwd * 0.6,
			]), Color(0.70, 0.55, 0.18))
			draw_colored_polygon(PackedVector2Array([
				grip - side * 2.6, grip - side * 1.0 + fwd * 0.6, grip - side * 1.0 - fwd * 0.6,
			]), Color(0.70, 0.55, 0.18))
			_draw_grip(grip, fwd, side, 5.0, Color(0.30, 0.18, 0.08))
			draw_circle(grip - fwd * 5.2, 1.0, Color(0.85, 0.65, 0.20))
		"BROADSWORD":
			_draw_blade_tapered(grip, fwd, side, 13.0, 3.0, 0.9, Color(0.55, 0.55, 0.65), Color(0.85, 0.85, 0.95))
			# Large crossguard
			draw_line(grip + side * 3.4, grip - side * 3.4, Color(0.45, 0.36, 0.18), 1.6)
			draw_line(grip + side * 3.4 + fwd * 0.3, grip - side * 3.4 + fwd * 0.3, Color(0.65, 0.52, 0.24), 0.6)
			_draw_grip(grip, fwd, side, 5.0, Color(0.28, 0.16, 0.06))
			draw_circle(grip - fwd * 5.4, 1.2, Color(0.78, 0.60, 0.20))
		"BLADESONG":
			# Translucent blade with pulsing glow
			_draw_blade_tapered(grip, fwd, side, 13.0, 2.2, 0.5, Color(0.6, 0.9, 1.0, 0.75), Color(0.9, 1.0, 1.0, 0.9))
			# 3 rune lines perpendicular
			for i in range(3):
				var rp: Vector2 = grip + fwd * (3.0 + float(i) * 3.0)
				draw_line(rp + side * 0.9, rp - side * 0.9, Color(0.5, 0.95, 1.0, 0.7), 0.5)
			var bt: Vector2 = grip + fwd * 13.0
			draw_circle(bt, 1.8, Color(0.5, 0.95, 1.0, sin(t*4.0)*0.25 + 0.35))
			draw_line(grip + side * 2.0, grip - side * 2.0, Color(0.7, 0.85, 0.95), 1.0)
			_draw_grip(grip, fwd, side, 4.5, Color(0.18, 0.30, 0.40))
		"VENOM_NEEDLE":
			draw_line(grip, grip + fwd * 7.0, Color(0.85, 0.82, 0.90), 0.8)
			draw_circle(grip + fwd * 7.0, 0.9, Color(0.2, 0.9, 0.3))
			draw_circle(grip + fwd * 7.0, 1.6, Color(0.2, 0.9, 0.3, 0.35))
			_draw_grip(grip, fwd, side, 2.5, Color(0.20, 0.18, 0.22))
		"CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT", "HAND_CROSSBOW":
			var scale: float = 0.55 if weapon == "HAND_CROSSBOW" else 1.0
			_draw_iso_crossbow(grip, fwd, side, scale, weapon, t)
			# Bolt magazine pips
			for b_i in range(min(_crossbow_bolts, 5)):
				var pip: Vector2 = grip + side * (-3.0 + float(b_i) * 1.4) * scale + fwd * -5.5 * scale
				draw_circle(pip, 0.8 * scale, Color(0.68, 0.65, 0.72))
		"RUNED_BLADE":
			# Dark blade with orange runes
			_draw_blade_tapered(grip, fwd, side, 11.0, 2.2, 0.5, Color(0.22, 0.18, 0.28), Color(0.45, 0.35, 0.55))
			for ci in range(max(_runed_blade_charges, 1)):
				var rune_p: Vector2 = grip + fwd * (2.5 + float(ci) * 2.2)
				var pulse_a: float = 0.70 + abs(sin(t * 4.0 + float(ci))) * 0.25
				draw_line(rune_p + side * 0.9, rune_p - side * 0.9, Color(0.95, 0.55, 0.12, pulse_a), 0.7)
			_draw_grip(grip, fwd, side, 4.0, Color(0.15, 0.10, 0.18))
		"STAFF":
			var staff_top: Vector2 = grip + fwd * -3.0 + Vector2(0, -4)
			var staff_bot: Vector2 = grip + fwd * 3.0 + Vector2(0, 12)
			draw_line(staff_top, staff_bot, Color(0.42, 0.28, 0.14), 1.6)
			draw_line(staff_top, staff_bot, Color(0.62, 0.45, 0.22), 0.5)
			# Ornate cap
			draw_colored_polygon(PackedVector2Array([
				staff_top + Vector2(-1.5, 0.5), staff_top + Vector2(1.5, 0.5),
				staff_top + Vector2(1.0, -1.5), staff_top + Vector2(-1.0, -1.5),
			]), Color(0.75, 0.60, 0.20))
			var orb_r: float = 3.0 + sin(t * 2.0) * 0.5
			draw_circle(staff_top + Vector2(0, -3.5), orb_r + 1.0, Color(0.6, 0.3, 0.95, 0.30))
			draw_circle(staff_top + Vector2(0, -3.5), orb_r, Color(0.6, 0.3, 0.95))
			draw_circle(staff_top + Vector2(-0.6, -4.2), orb_r * 0.4, Color(0.95, 0.80, 1.0, 0.8))
		"ARCANE_FOCUS":
			var orb: Vector2 = grip
			draw_circle(orb, 4.0, Color(0.5, 0.3, 0.9, 0.30))
			draw_circle(orb, 3.0, Color(0.5, 0.3, 0.9))
			draw_circle(orb - fwd * 0.6 + side * -0.6, 1.0, Color(0.95, 0.85, 1.0, 0.85))
			for i in range(3):
				var ang: float = t * 2.5 + float(i) * TAU / 3.0
				var part: Vector2 = orb + Vector2(cos(ang) * 5.0, sin(ang) * 2.5)
				draw_circle(part, 1.0, Color(0.7, 0.4, 1.0, 0.85))
				draw_circle(part, 1.8, Color(0.7, 0.4, 1.0, 0.30))
		"WAND":
			draw_line(grip - fwd * 2.0, grip + fwd * 5.0, Color(0.32, 0.20, 0.10), 1.4)
			draw_line(grip - fwd * 2.0, grip + fwd * 5.0, Color(0.55, 0.36, 0.18), 0.5)
			var wt: Vector2 = grip + fwd * 5.5
			draw_circle(wt, 1.4, Color(0.8, 0.3, 0.95))
			draw_circle(wt, 0.7, Color(1.0, 0.8, 1.0, 0.85))
			# Sparkle radials
			for i in range(4):
				var ang2: float = t * 1.5 + float(i) * PI * 0.5
				var s_end: Vector2 = wt + Vector2(cos(ang2), sin(ang2)) * (1.8 + sin(t*3.0 + float(i))*0.4)
				draw_line(wt, s_end, Color(1.0, 0.7, 1.0, 0.65), 0.4)
		_:
			# Generic fallback: paired daggers
			if not is_sneaking:
				var dc: Color = Color(0.62, 0.60, 0.65)
				var hc: Color = Color(0.38, 0.26, 0.14)
				for s_i in [1, -1]:
					var dbase: Vector2 = vis + perp * (float(s_i) * 4.8) - f * 0.8 + Vector2(0, w_bob)
					_draw_blade_tapered(dbase, fwd, side, 5.0, 1.2, 0.3, dc, Color(1.0, 1.0, 1.0))
					_draw_grip(dbase, fwd, side, 2.0, hc)

func take_damage_flash():
	GameManager.reset_combo()
	_hit_flash_timer = _HIT_FLASH_DURATION
	if _sprite != null:
		_sprite.modulate = Color(1.0, 0.25, 0.25)

func is_position_blocked(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = target_pos
	query.exclude  = [self]
	return space.intersect_point(query).size() > 0

# ── Drawing helpers (isometric 3/4 perspective) ───────────────────────────────

func _shade(c: Color, amount: float, a_mul: float = 1.0) -> Color:
	# amount > 0 lightens, < 0 darkens
	var r: Color = c
	if amount > 0.0:
		r = c.lightened(amount)
	elif amount < 0.0:
		r = c.darkened(-amount)
	return Color(r.r, r.g, r.b, c.a * a_mul)

func _iso_ellipse(center: Vector2, rx: float, ry: float, steps: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(steps):
		var a: float = float(i) / float(steps) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _draw_iso_leg(top: Vector2, col: Color, b: float, sa: float) -> void:
	# Tapered leg poly (4 verts): wider at hip, narrower at boot
	var hip_l: Vector2  = top + Vector2(-1.6, -2.0 + b)
	var hip_r: Vector2  = top + Vector2( 1.6, -2.0 + b)
	var boot_l: Vector2 = top + Vector2(-1.1, 4.0)
	var boot_r: Vector2 = top + Vector2( 1.1, 4.0)
	var poly: PackedVector2Array = PackedVector2Array([hip_l, hip_r, boot_r, boot_l])
	draw_colored_polygon(poly, _shade(col, 0.00, sa))
	# Front highlight strip
	draw_line(hip_l + Vector2(0.3, 0.4), boot_l + Vector2(0.2, -0.2), _shade(col, 0.25, sa * 0.8), 0.4)
	# Outline
	draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.04, 0.03, 0.06, 0.75 * sa), 0.5)

func _draw_iso_boot(pos: Vector2, fwd: Vector2, side: Vector2, col: Color, sa: float) -> void:
	var w: float = 2.0
	var d: float = 1.6
	var h: float = 1.6
	# Front face
	var front: PackedVector2Array = PackedVector2Array([
		pos + Vector2(-w, -h), pos + Vector2(w, -h),
		pos + Vector2(w, h),   pos + Vector2(-w, h),
	])
	# Top face (toe extends forward along fwd)
	var toe_ext: Vector2 = fwd * 1.8
	var top_p: PackedVector2Array = PackedVector2Array([
		pos + Vector2(-w, -h), pos + Vector2(w, -h),
		pos + Vector2(w, -h) + toe_ext, pos + Vector2(-w, -h) + toe_ext,
	])
	# Right shadow face
	var rside: PackedVector2Array = PackedVector2Array([
		pos + Vector2(w, -h), pos + Vector2(w, -h) + toe_ext,
		pos + Vector2(w, h)  + toe_ext * 0.6, pos + Vector2(w, h),
	])
	draw_colored_polygon(rside, _shade(col, -0.35, sa))
	draw_colored_polygon(front, _shade(col,  0.00, sa))
	draw_colored_polygon(top_p, _shade(col,  0.22, sa))
	draw_polyline(front + PackedVector2Array([front[0]]), Color(0.03, 0.02, 0.05, 0.85 * sa), 0.4)
	draw_polyline(top_p + PackedVector2Array([top_p[0]]), Color(0.03, 0.02, 0.05, 0.85 * sa), 0.4)

func _draw_iso_arm(shoulder: Vector2, hand: Vector2, sleeve: Color, skin: Color, sa: float) -> void:
	# Skinny arm: shoulder → elbow → hand (slight bend)
	var mid: Vector2 = shoulder.lerp(hand, 0.5) + Vector2(0, 0.6)
	var dir_v: Vector2 = (hand - shoulder).normalized() if hand != shoulder else Vector2.RIGHT
	var n: Vector2 = Vector2(-dir_v.y, dir_v.x)
	# Upper arm poly
	var ua: PackedVector2Array = PackedVector2Array([
		shoulder + n * 1.1, shoulder - n * 1.1,
		mid - n * 0.9, mid + n * 0.9,
	])
	# Forearm poly
	var fa: PackedVector2Array = PackedVector2Array([
		mid + n * 0.9, mid - n * 0.9,
		hand - n * 0.7, hand + n * 0.7,
	])
	draw_colored_polygon(ua, _shade(sleeve, 0.00, sa))
	draw_colored_polygon(fa, _shade(sleeve, -0.10, sa))
	draw_polyline(ua + PackedVector2Array([ua[0]]), Color(0.04, 0.03, 0.06, 0.7 * sa), 0.4)
	draw_polyline(fa + PackedVector2Array([fa[0]]), Color(0.04, 0.03, 0.06, 0.7 * sa), 0.4)
	# Wrist skin & hand
	draw_circle(hand, 1.2, _shade(skin, 0.00, sa))
	draw_circle(hand + Vector2(-0.3, -0.3), 0.5, _shade(skin, 0.25, sa))

func _draw_cape(vis: Vector2, fwd: Vector2, side: Vector2, cls: String, t: float, b: float, flap: float, sa: float, trim: Color) -> void:
	var back_dir: Vector2 = -fwd
	var c1: Vector2 = vis + Vector2(-4.5, -7.5 + b)
	var c2: Vector2 = vis + Vector2( 4.5, -7.5 + b)
	var c_mid_l: Vector2 = vis + Vector2(-5.5 + back_dir.x * 2.0, -2.0 + b) + back_dir * 2.0
	var c_mid_r: Vector2 = vis + Vector2( 5.5 + back_dir.x * 2.0, -2.0 + b) + back_dir * 2.0
	var c_low_l: Vector2 = vis + Vector2(-4.0, 2.0) + back_dir * (5.0 + flap)
	var c_low_r: Vector2 = vis + Vector2( 4.0, 2.0) + back_dir * (5.0 - flap * 0.5)
	var c_tip:   Vector2 = vis + Vector2(0, 3.5) + back_dir * (7.0 + flap * 0.4) + Vector2(0, sin(t * 2.4) * 0.6)
	var c_inner: Vector2 = vis + Vector2(0, -2.0 + b) + back_dir * 1.0
	var cape_col: Color
	if cls == "SHADOWDANCER":
		cape_col = Color(0.18, 0.08, 0.32, 0.92 * sa)
	else:
		cape_col = Color(0.08, 0.08, 0.12, 0.94 * sa)
	var poly: PackedVector2Array = PackedVector2Array([
		c1, c_inner, c2, c_mid_r, c_low_r, c_tip, c_low_l, c_mid_l,
	])
	draw_colored_polygon(poly, cape_col)
	# Inner sheen
	draw_colored_polygon(PackedVector2Array([
		c1, c_inner, c2,
		c2.lerp(c_tip, 0.45), c_tip.lerp(c1, 0.55),
	]), Color(cape_col.r * 1.7, cape_col.g * 1.7, cape_col.b * 1.9, 0.30 * sa))
	# Outline
	draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.02, 0.01, 0.04, 0.8 * sa), 0.5)
	if cls == "ASSASSIN":
		# Red trim along bottom edge
		draw_line(c_low_l, c_tip, Color(trim.r, trim.g, trim.b, 0.85 * sa), 0.6)
		draw_line(c_tip,   c_low_r, Color(trim.r, trim.g, trim.b, 0.85 * sa), 0.6)
	else:
		# Purple trim
		draw_line(c1, c_mid_l, Color(trim.r, trim.g, trim.b, 0.60 * sa), 0.5)
		draw_line(c2, c_mid_r, Color(trim.r, trim.g, trim.b, 0.60 * sa), 0.5)

func _draw_blade_tapered(base: Vector2, fwd: Vector2, side: Vector2, length: float, base_w: float, tip_w: float, blade_col: Color, edge_col: Color) -> void:
	var tip: Vector2 = base + fwd * length
	var bw: float = base_w * 0.5
	var tw_v: float = tip_w * 0.5
	var poly: PackedVector2Array = PackedVector2Array([
		base + side * bw, tip + side * tw_v,
		tip - side * tw_v, base - side * bw,
	])
	# Shadow half (dark)
	draw_colored_polygon(PackedVector2Array([
		base + side * bw, tip + side * tw_v, tip, base,
	]), Color(blade_col.r * 0.55, blade_col.g * 0.55, blade_col.b * 0.65, blade_col.a))
	# Light half
	draw_colored_polygon(PackedVector2Array([
		base, tip, tip - side * tw_v, base - side * bw,
	]), blade_col)
	# Bright edge highlight
	draw_line(base - side * bw * 0.9, tip - side * tw_v * 0.9, edge_col, 0.5)
	# Outline
	draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.04, 0.03, 0.06, 0.85), 0.4)

func _draw_grip(base: Vector2, fwd: Vector2, side: Vector2, length: float, col: Color) -> void:
	var back: Vector2 = base - fwd * length
	var w: float = 0.9
	var poly: PackedVector2Array = PackedVector2Array([
		base + side * w, back + side * w,
		back - side * w, base - side * w,
	])
	draw_colored_polygon(poly, col)
	draw_line(base + side * w * 0.4, back + side * w * 0.4, col.lightened(0.3), 0.4)
	draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.03, 0.02, 0.05, 0.85), 0.4)

func _draw_iso_grip_handle(pos: Vector2, fwd: Vector2, side: Vector2, col: Color) -> void:
	var poly: PackedVector2Array = PackedVector2Array([
		pos + side * 0.9 + fwd * -0.6, pos + side * 0.9 + fwd * 0.6,
		pos - side * 0.9 + fwd * 0.6,  pos - side * 0.9 + fwd * -0.6,
	])
	draw_colored_polygon(poly, col)
	draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.03, 0.02, 0.05, 0.9), 0.4)

func _draw_iso_crossbow(grip: Vector2, fwd: Vector2, side: Vector2, scale: float, kind: String, t: float) -> void:
	# Stock body (grip + body forward)
	var stock: PackedVector2Array = PackedVector2Array([
		grip + side * 0.8 * scale + fwd * -2.0 * scale,
		grip + side * 0.8 * scale + fwd *  5.5 * scale,
		grip - side * 0.8 * scale + fwd *  5.5 * scale,
		grip - side * 0.8 * scale + fwd * -2.0 * scale,
	])
	draw_colored_polygon(stock, Color(0.42, 0.28, 0.14))
	draw_polyline(stock + PackedVector2Array([stock[0]]), Color(0.05, 0.03, 0.04, 0.9), 0.4)
	# Arms (perpendicular to fwd)
	var arm_pos: Vector2 = grip + fwd * 3.0 * scale
	var arm_l: Vector2 = arm_pos + side * 4.5 * scale
	var arm_r: Vector2 = arm_pos - side * 4.5 * scale
	draw_line(arm_pos, arm_l, Color(0.38, 0.25, 0.12), 1.6 * scale)
	draw_line(arm_pos, arm_r, Color(0.38, 0.25, 0.12), 1.6 * scale)
	# Tip caps
	draw_circle(arm_l, 0.6 * scale, Color(0.62, 0.45, 0.20))
	draw_circle(arm_r, 0.6 * scale, Color(0.62, 0.45, 0.20))
	# String across arms
	draw_line(arm_l, arm_r, Color(0.85, 0.82, 0.75), 0.4)
	# Loaded bolt
	draw_line(grip + fwd * 2.0 * scale, grip + fwd * 7.0 * scale, Color(0.55, 0.42, 0.20), 0.6)
	# Magazine box for REPEATING_CROSSBOW
	if kind == "REPEATING_CROSSBOW":
		var mag: PackedVector2Array = PackedVector2Array([
			grip + side * 1.4 * scale + fwd * 1.0 * scale,
			grip + side * 1.4 * scale + fwd * 4.5 * scale,
			grip + side * 0.2 * scale + fwd * 4.5 * scale,
			grip + side * 0.2 * scale + fwd * 1.0 * scale,
		])
		draw_colored_polygon(mag, Color(0.32, 0.22, 0.10))
		draw_polyline(mag + PackedVector2Array([mag[0]]), Color(0.04, 0.03, 0.04, 0.9), 0.4)
		draw_circle(grip + fwd * 5.8 * scale, 0.9 * scale, Color(0.90, 0.55, 0.18, 0.65))
	elif kind == "SILENT_BOLT":
		# Dark cylinder at front (suppressor)
		var sup: PackedVector2Array = PackedVector2Array([
			grip + side * 0.6 * scale + fwd * 5.5 * scale,
			grip + side * 0.6 * scale + fwd * 8.0 * scale,
			grip - side * 0.6 * scale + fwd * 8.0 * scale,
			grip - side * 0.6 * scale + fwd * 5.5 * scale,
		])
		draw_colored_polygon(sup, Color(0.18, 0.18, 0.20))
		draw_polyline(sup + PackedVector2Array([sup[0]]), Color(0.04, 0.03, 0.05, 0.95), 0.4)
		draw_circle(grip + fwd * 6.7 * scale, 0.5 * scale, Color(0.42, 0.52, 0.72, 0.70))
