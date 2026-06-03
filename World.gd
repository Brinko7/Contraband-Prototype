extends Node2D

const GuardScene  := preload("res://Guard.tscn")
const HoundScene  := preload("res://Hound.tscn")
const LootScene   := preload("res://LootTarget.tscn")
const TrapScene   := preload("res://TrapTile.tscn")
const WardScene   := preload("res://MagicWard.tscn")
const PickupScene := preload("res://PickupItem.tscn")

const _torch_script      := preload("res://TorchNode.gd")
const _hiding_script     := preload("res://HidingSpot.gd")
const _glass_script      := preload("res://GlassTile.gd")
const _oil_script        := preload("res://OilSlick.gd")
const _civilian_script   := preload("res://CivilianNPC.gd")
const _locked_door_script := preload("res://LockedDoor.gd")
const _curtain_script     := preload("res://CurtainSpot.gd")
const _fog_script        := preload("res://FogOfWar.gd")

var _rng := RandomNumberGenerator.new()
var _reinforcements_spawned := 0

# ── Map coordinate reference (48×36 tiles, 16 px/tile = 768×576) ─────────────
# Vault Left  : x 16-192,  y 16-128   (cols  1-12, rows  1-8)
# Vault Centre: x 240-480, y 16-128   (cols 15-30, rows  1-8)
# Vault Right : x 528-720, y 16-128   (cols 33-45, rows  1-8) LOCKED door_id=1
# Barracks    : x 16-736,  y 176-320  (cols  1-46, rows 11-20)
# Entry Hall  : x 16-736,  y 368-528  (cols  1-46, rows 23-33)
#
# LockedDoor sits at (512, 80) — carved gap cols 31-32, rows 4-5
# Player spawn: Vector2(384, 480) — col 24, row 30

func _ready():
	GameManager.pick_floor_complication()
	GameManager.pick_floor_objective()
	GameManager.start_floor_timer()
	GameManager.alert_triggered.connect(_on_alert_triggered)
	_rng.seed = GameManager.run_seed + GameManager.current_floor * 7919

	# Override player spawn for larger map
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node:
		player_node.position = Vector2(384, 480)

	var variant: int = _rng.randi() % 3
	match GameManager.current_floor:
		1:
			if variant == 0:   _setup_floor1()
			elif variant == 1: _setup_floor1b()
			else:              _setup_floor1c()
		2:
			if variant == 0:   _setup_floor2()
			elif variant == 1: _setup_floor2b()
			else:              _setup_floor2c()
		3:
			if variant == 0:   _setup_floor3()
			elif variant == 1: _setup_floor3b()
			else:              _setup_floor3c()
		4:
			if variant == 0:   _setup_floor4()
			elif variant == 1: _setup_floor4b()
			else:              _setup_floor4c()
		_:
			_setup_floor5()

	# Optional side passage — 50% chance, adds a locked side room with elite guard + bonus loot
	if _rng.randi() % 2 == 0:
		_spawn_side_passage()

	# The locked door sits in the carved gap at cols 31-32, rows 4-5
	# Centre: x=(31+32)*16/2+16=512, y=(4+5)*16/2+8=72
	_locked_door(Vector2(512, 80), 1)

	_spawn_interactables()
	_ensure_safe_spawn()
	_apply_wanted_level_effects()

	# Fog-of-war overlay — added last so it draws above all game nodes
	var fog := Node2D.new()
	fog.set_script(_fog_script)
	add_child(fog)

# ── Returns base ± jitter snapped to 16-px grid ───────────────────────────────
func _j(base: Vector2, rx: int = 1, ry: int = 1) -> Vector2:
	var ox := _rng.randi_range(-rx, rx) * 16
	var oy := _rng.randi_range(-ry, ry) * 16
	return base + Vector2(ox, oy)

# ── Wanted level world consequences ──────────────────────────────────────────
func _apply_wanted_level_effects():
	var wl := GameManager.wanted_level
	if wl <= 0:
		return
	# Wanted 1+: guards have slightly shorter patrol wait
	if wl >= 1:
		for g in get_children():
			if g.is_in_group("guards"):
				var iv: float = g.get("move_interval") if g.get("move_interval") else 0.40
				g.set("move_interval", iv * max(0.60, 1.0 - wl * 0.06))
	# Wanted 3+: spawn one extra patrol guard at a random entry point
	if wl >= 3:
		var entry_points := [Vector2(192, 464), Vector2(576, 464), Vector2(384, 480)]
		var ep: Vector2 = entry_points[_rng.randi() % entry_points.size()]
		_prowler(_j(ep), [_j(Vector2(96, 464)), _j(Vector2(672, 464))])
	# Wanted 4+: spawn an extra hound
	if wl >= 4:
		_hound(_j(Vector2(384, 430)), [_j(Vector2(96, 430)), _j(Vector2(672, 430))])
	# Wanted 5: all guards start SUSPICIOUS
	if wl >= 5:
		for g in get_children():
			if g.is_in_group("guards"):
				g.set("alert_state", 1)   # AlertState.SUSPICIOUS
				g.set("de_escalate_timer", 99.0)

# ── Floor complication helpers ─────────────────────────────────────────────────
func _surge() -> bool:      return GameManager.floor_complication == "SURGE"
func _bounty() -> bool:     return GameManager.floor_complication == "BOUNTY"
func _sentinel_comp() -> bool: return GameManager.floor_complication == "SENTINEL"
func _escalated(level: int) -> bool: return GameManager.alert_escalation >= level

# ── Shared interactables (torches and barrel hiding-spots) ────────────────────
func _spawn_interactables():
	# Match LevelMap.TORCHES exactly
	for tp in [Vector2(64,40), Vector2(352,40), Vector2(624,40),
			   Vector2(8,256), Vector2(760,256),
			   Vector2(8,464), Vector2(760,464),
			   Vector2(192,176), Vector2(544,176),
			   Vector2(256,128), Vector2(448,128),
			   Vector2(192,368), Vector2(576,368)]:
		var tn := Node2D.new()
		tn.set_script(_torch_script)
		tn.position = tp
		add_child(tn)

	# Barrel hiding-spots
	for hp in [Vector2(80, 304), Vector2(672, 304),
			   Vector2(80, 464), Vector2(672, 464)]:
		var hs := Node2D.new()
		hs.set_script(_hiding_script)
		hs.position = hp
		add_child(hs)

	# Curtain hiding-spots — vault alcoves and barracks corners
	# Note: keep away from locked door at (512, 80)
	for cp in [Vector2(176, 96), Vector2(624, 96),
			   Vector2(144, 240), Vector2(624, 240)]:
		_curtain(cp)

# ── Floor 1A ──────────────────────────────────────────────────────────────────
func _setup_floor1():
	var vr := 100.0; var va := 80.0

	# Entry Hall
	_guard(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))],
		"SENTRY", 75.0, 55.0, 0.42)
	_hound(Vector2(384, 416), [_j(Vector2(192,416)), _j(Vector2(576,416))])

	# Barracks — captain holds key to Vault Right
	var cap := _guard(_j(Vector2(256, 256)),
		[_j(Vector2(96,256)), _j(Vector2(432,256)), _j(Vector2(432,304)), _j(Vector2(96,304))],
		"CAPTAIN", 130.0, 100.0, 0.32)
	cap.set("is_captain", true)
	cap.set("key_id", 1)

	_guard(_j(Vector2(512, 240)), [_j(Vector2(192,240)), _j(Vector2(672,240))],
		"SENTRY", vr, va, 0.40)
	_guard(_j(Vector2(96, 208)),  [_j(Vector2(96,192)),  _j(Vector2(96,288))],
		"WATCHER", 95.0, 85.0, 0.88)

	if _surge() or _escalated(2):
		_guard(_j(Vector2(384, 288)), [_j(Vector2(192,288)), _j(Vector2(576,288))],
			"PATROL", 75.0, 60.0, 0.40)
	if _bounty() or _escalated(3):
		_hound(_j(Vector2(256, 288)), [_j(Vector2(96,288)), _j(Vector2(576,288))])
	if _sentinel_comp():
		_sentinel(Vector2(352, 208))

	_goblin(_j(Vector2(576, 272)), [_j(Vector2(576,240)), _j(Vector2(576,304))])

	# Vault Left
	_guard(_j(Vector2(80, 64)), [_j(Vector2(80,32)), _j(Vector2(80,112))],
		"WATCHER", vr, va, 0.88)
	_loot(Vector2(96, 80), 200, true)

	# Vault Centre
	_guard(_j(Vector2(352, 64)), [_j(Vector2(256,64)), _j(Vector2(448,64))],
		"SENTRY", vr, va, 0.40)
	_loot(Vector2(352, 48), 400)

	# Vault Right (LOCKED — accessible only after unlocking door)
	_guard(_j(Vector2(608, 64)), [_j(Vector2(560,64)), _j(Vector2(672,64))],
		"WATCHER", 90.0, 80.0, 0.85)
	_loot(Vector2(624, 48), 650, false, 1)   # UNCOMMON inner vault reward

	_trap(Vector2(176, 208))
	_glass(Vector2(448, 272))
	_oil(Vector2(256, 416))
	_pickup(Vector2(576, 496), 0)
	_pickup(Vector2(176,  80), 1)
	# Weapon pickups — tier 1 found weapons in passageways
	var _wdrops1 := GameManager.get_floor_weapon_drops(1)
	if _wdrops1.size() >= 1:
		_spawn_weapon_pickup(_wdrops1[0], Vector2(320, 352))  # barracks passage

# ── Floor 1B ──────────────────────────────────────────────────────────────────
func _setup_floor1b():
	var vr := 90.0; var va := 75.0

	# Entry
	_guard(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))],
		"SENTRY", 75.0, 55.0, 0.44)
	_hound(Vector2(576, 432), [_j(Vector2(192,432)), _j(Vector2(576,432))])
	_hound(Vector2(192, 432), [_j(Vector2(96,432)),  _j(Vector2(384,432))])

	# Barracks — captain holds key
	var cap := _guard(_j(Vector2(352, 240)),
		[_j(Vector2(96,240)), _j(Vector2(608,240))],
		"CAPTAIN", 130.0, 100.0, 0.30)
	cap.set("is_captain", true)
	cap.set("key_id", 1)

	_guard(_j(Vector2(96, 208)),  [_j(Vector2(96,192)),  _j(Vector2(96,304))],
		"WATCHER", 95.0, 85.0, 0.88)
	_guard(_j(Vector2(608, 208)), [_j(Vector2(608,192)), _j(Vector2(608,304))],
		"WATCHER", 95.0, 85.0, 0.88)

	if _surge() or _escalated(2):
		_guard(_j(Vector2(352, 288)), [_j(Vector2(192,288)), _j(Vector2(512,288))],
			"SENTRY", vr, va, 0.40)
	if _bounty() or _escalated(3):
		_hound(_j(Vector2(352, 272)), [_j(Vector2(96,272)), _j(Vector2(608,272))])
	if _sentinel_comp():
		_sentinel(Vector2(352, 208))

	# Vault Left
	_guard(_j(Vector2(80, 64)), [_j(Vector2(80,32)), _j(Vector2(80,112))],
		"WATCHER", vr, va, 0.85)
	_loot(Vector2(112, 96), 200, true)

	# Vault Centre
	_guard(_j(Vector2(352, 64)), [_j(Vector2(256,64)), _j(Vector2(448,64))],
		"SENTRY", vr, va, 0.40)
	_loot(Vector2(352, 48), 400)
	_loot(Vector2(256, 80), 200, true)

	# Vault Right (LOCKED)
	_guard(_j(Vector2(608, 64)), [_j(Vector2(560,64)), _j(Vector2(672,64))],
		"WATCHER", 90.0, 80.0, 0.82)
	_loot(Vector2(624, 48), 600, false, 1)

	_trap(Vector2(96, 256))
	_trap(Vector2(608, 256))
	_glass(Vector2(352, 272))
	_oil(Vector2(384, 464))
	_pickup(Vector2(96, 496), 0)
	_pickup(Vector2(448,  80), 1)
	# Weapon pickups — tier 1 found weapons
	var _wdrops1b := GameManager.get_floor_weapon_drops(1)
	if _wdrops1b.size() >= 1:
		_spawn_weapon_pickup(_wdrops1b[0], Vector2(480, 352))  # barracks corridor

# ── Floor 2A ──────────────────────────────────────────────────────────────────
func _setup_floor2():
	var vr := 110.0; var va := 90.0

	# Entry
	_guard(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))],
		"SENTRY", 80.0, 60.0, 0.40)
	_guard(_j(Vector2(576, 432)), [_j(Vector2(576,400)), _j(Vector2(576,496))],
		"SENTRY", 80.0, 65.0, 0.40)
	_hound(Vector2(384, 448), [_j(Vector2(96,448)), _j(Vector2(672,448))])

	# Barracks — captain holds key
	var cap := _guard(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,288)), _j(Vector2(96,288))],
		"CAPTAIN", 140.0, 110.0, 0.28)
	cap.set("is_captain", true)
	cap.set("key_id", 1)

	_guard(_j(Vector2(96, 208)),  [_j(Vector2(96,192)),  _j(Vector2(96,304))],
		"WATCHER", vr, va, 0.80)
	_guard(_j(Vector2(608, 208)), [_j(Vector2(608,192)), _j(Vector2(608,304))],
		"WATCHER", vr, va, 0.80)
	_guard(_j(Vector2(352, 192)), [_j(Vector2(192,192)), _j(Vector2(512,192))],
		"SENTRY", 85.0, 65.0, 0.40)
	_hound(Vector2(192, 272), [_j(Vector2(96,272)), _j(Vector2(672,272))])

	_skeleton(_j(Vector2(512, 288)), [_j(Vector2(512,256)), _j(Vector2(512,304))])
	_gnoll(_j(Vector2(192, 240)),    [_j(Vector2(96,240)),  _j(Vector2(352,240))])

	if _surge() or _escalated(2):
		_guard(_j(Vector2(352, 304)), [_j(Vector2(192,304)), _j(Vector2(512,304))],
			"PATROL", 80.0, 60.0, 0.38)
	if _bounty() or _escalated(4):
		_hound(_j(Vector2(512, 256)), [_j(Vector2(192,256)), _j(Vector2(672,256))])
	if _sentinel_comp():
		_sentinel(Vector2(352, 208))

	# Vault Left
	_guard(_j(Vector2(80, 48)), [_j(Vector2(80,32)), _j(Vector2(80,112))],
		"WATCHER", vr, va, 0.80)
	_loot(Vector2(96, 80), 300, true)

	# Vault Centre
	_guard(_j(Vector2(256, 64)), [_j(Vector2(240,32)), _j(Vector2(448,64))],
		"SENTRY", vr, va, 0.40)
	_guard(_j(Vector2(432, 80)), [_j(Vector2(256,80)), _j(Vector2(464,32))],
		"SENTRY", vr, va, 0.40)
	_loot(Vector2(352, 48), 500, false, 1)  # UNCOMMON
	_loot(Vector2(256, 96), 250, true)

	# Vault Right (LOCKED)
	_guard(_j(Vector2(560, 64)), [_j(Vector2(544,32)), _j(Vector2(704,64))],
		"WATCHER", 95.0, 80.0, 0.78)
	_loot(Vector2(624, 48), 800, false, 2)  # RARE
	_loot(Vector2(672, 96), 400, true)

	_trap(Vector2(192, 208))
	_trap(Vector2(512, 192))
	_ward(Vector2(352, 240))
	_glass(Vector2(352, 272))
	_glass(Vector2(192, 192))
	_oil(Vector2(512, 288))
	_civilian(Vector2(384, 256), [Vector2(192, 256), Vector2(576, 256)])
	_pickup(Vector2(576, 496), 0)
	_pickup(Vector2(176,  80), 1)
	_pickup(Vector2(448, 288), 2)
	# Weapon pickups — tier 1-2 found weapons
	var _wdrops2 := GameManager.get_floor_weapon_drops(2)
	if _wdrops2.size() >= 1:
		_spawn_weapon_pickup(_wdrops2[0], Vector2(288, 352))
	if _wdrops2.size() >= 2:
		_spawn_weapon_pickup(_wdrops2[1], Vector2(512, 432))

# ── Floor 2B ──────────────────────────────────────────────────────────────────
func _setup_floor2b():
	var vr := 105.0; var va := 50.0

	# Entry
	_guard(_j(Vector2(384, 464)), [_j(Vector2(96,464)), _j(Vector2(672,464))],
		"SENTRY", 80.0, 60.0, 0.42)
	_hound(Vector2(192, 448), [_j(Vector2(96,448)),  _j(Vector2(576,448))])
	_hound(Vector2(576, 448), [_j(Vector2(192,448)), _j(Vector2(672,448))])

	# Barracks
	var cap := _guard(_j(Vector2(352, 240)),
		[_j(Vector2(96,240)), _j(Vector2(608,240))],
		"CAPTAIN", 140.0, 110.0, 0.28)
	cap.set("is_captain", true)
	cap.set("key_id", 1)

	_prowler(_j(Vector2(192, 256)),
		[_j(Vector2(96,240)), _j(Vector2(608,240)), _j(Vector2(608,304)), _j(Vector2(96,304))])
	_prowler(_j(Vector2(608, 304)),
		[_j(Vector2(608,192)), _j(Vector2(608,304)), _j(Vector2(96,304)), _j(Vector2(96,192))])
	_guard(_j(Vector2(96, 208)), [_j(Vector2(96,192)), _j(Vector2(96,288))],
		"WATCHER", vr, 90.0, 0.85)

	if _surge() or _escalated(2):
		_prowler(_j(Vector2(352, 288)), [_j(Vector2(96,288)), _j(Vector2(608,288))])
	if _bounty() or _escalated(4):
		_hound(_j(Vector2(352, 272)), [_j(Vector2(96,272)), _j(Vector2(608,272))])
	if _sentinel_comp():
		_sentinel(Vector2(352, 208))

	_skeleton(_j(Vector2(608, 256)), [_j(Vector2(608,192)), _j(Vector2(608,304))])
	_goblin(_j(Vector2(96, 272)),    [_j(Vector2(96,240)),  _j(Vector2(96,304))])

	# Vault Left
	_guard(_j(Vector2(80, 64)), [_j(Vector2(80,32)), _j(Vector2(80,112))],
		"WATCHER", vr, va, 0.88)
	_loot(Vector2(112, 80), 300, true)

	# Vault Centre
	_guard(_j(Vector2(352, 64)), [_j(Vector2(256,64)), _j(Vector2(464,64))],
		"SENTRY", vr, va, 0.40)
	_loot(Vector2(352, 48), 500, false, 1)
	_loot(Vector2(448, 96), 250, true)

	# Vault Right (LOCKED)
	_guard(_j(Vector2(608, 48)), [_j(Vector2(560,32)), _j(Vector2(704,80))],
		"WATCHER", 95.0, 80.0, 0.80)
	_loot(Vector2(624, 48), 750, false, 2)

	_trap(Vector2(192, 272))
	_trap(Vector2(512, 272))
	_ward(Vector2(352, 192))
	_glass(Vector2(352, 288))
	_oil(Vector2(192, 416))
	var _wdrops2b := GameManager.get_floor_weapon_drops(2)
	if _wdrops2b.size() > 0: _spawn_weapon_pickup(_wdrops2b[0], Vector2(480, 352))
	if _wdrops2b.size() > 1: _spawn_weapon_pickup(_wdrops2b[1], Vector2(256, 352))
	_pickup(Vector2(96, 496), 0)
	_pickup(Vector2(464,  80), 2)
	_pickup(Vector2(672, 304), 1)

# ── Floor 3A ──────────────────────────────────────────────────────────────────
func _setup_floor3():
	var vr := 120.0; var va := 100.0

	# Entry
	_guard(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))],
		"SENTRY", 85.0, 65.0, 0.38)
	_guard(_j(Vector2(576, 432)), [_j(Vector2(576,400)), _j(Vector2(576,496))],
		"SENTRY", 85.0, 65.0, 0.38)
	_guard(_j(Vector2(96, 432)),  [_j(Vector2(96,400)),  _j(Vector2(96,496))],
		"SENTRY", 85.0, 65.0, 0.38)
	_hound(Vector2(384, 448), [_j(Vector2(96,448)), _j(Vector2(672,448))])

	# Barracks — THE BOSS holds the key to the inner vault
	_boss(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,288)), _j(Vector2(96,288))])

	_guard(_j(Vector2(96, 208)),  [_j(Vector2(96,192)),  _j(Vector2(96,304))],
		"WATCHER", vr, va, 0.70)
	_guard(_j(Vector2(608, 208)), [_j(Vector2(608,192)), _j(Vector2(608,304))],
		"WATCHER", vr, va, 0.70)
	_guard(_j(Vector2(256, 192)), [_j(Vector2(192,192)), _j(Vector2(448,192))],
		"SENTRY", 90.0, 70.0, 0.35)
	_guard(_j(Vector2(512, 304)), [_j(Vector2(352,304)), _j(Vector2(672,304))],
		"SENTRY", 90.0, 70.0, 0.35)
	_prowler(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,304)), _j(Vector2(96,304))])
	_hound(Vector2(192, 256), [_j(Vector2(96,256)), _j(Vector2(608,256))])
	_hound(Vector2(512, 272), [_j(Vector2(192,272)), _j(Vector2(672,272))])
	_skeleton(_j(Vector2(256, 288)), [_j(Vector2(192,256)), _j(Vector2(256,304))])
	_gnoll(_j(Vector2(512, 240)),    [_j(Vector2(448,208)), _j(Vector2(608,256))])
	_goblin(_j(Vector2(192, 304)),   [_j(Vector2(96,288)),  _j(Vector2(352,304))])

	if _surge() or _escalated(2):
		_prowler(_j(Vector2(512, 192)), [_j(Vector2(192,192)), _j(Vector2(672,192))])
	if _bounty() or _escalated(5):
		_hound(_j(Vector2(384, 304)), [_j(Vector2(96,304)), _j(Vector2(672,304))])
	if _sentinel_comp() or _escalated(4):
		_sentinel(Vector2(352, 208))
	if _escalated(3):
		_gnoll(_j(Vector2(352, 272)), [_j(Vector2(192,272)), _j(Vector2(512,272))])

	# Vault Left
	_guard(_j(Vector2(64, 48)), [_j(Vector2(32,32)), _j(Vector2(64,112))],
		"WATCHER", vr, va, 0.70)
	_loot(Vector2(80, 80), 400, true, 1)

	# Vault Centre
	_guard(_j(Vector2(256, 64)), [_j(Vector2(240,32)), _j(Vector2(464,32))],
		"SENTRY", vr, va, 0.35)
	_guard(_j(Vector2(432, 80)), [_j(Vector2(240,80)), _j(Vector2(464,80))],
		"SENTRY", vr, va, 0.35)
	_loot(Vector2(352, 48), 700, false, 1)
	_loot(Vector2(256, 96), 400, true)

	# Vault Right (LOCKED)
	_guard(_j(Vector2(560, 48)), [_j(Vector2(544,32)), _j(Vector2(704,48))],
		"WATCHER", 100.0, 85.0, 0.72)
	_guard(_j(Vector2(672, 80)), [_j(Vector2(544,80)), _j(Vector2(704,96))],
		"SENTRY", 90.0, 70.0, 0.35)
	_loot(Vector2(624, 48), 1000, false, 2)  # RARE
	_loot(Vector2(672,  80), 500, true, 1)

	_trap(Vector2(192, 208))
	_trap(Vector2(512, 192))
	_trap(Vector2(352, 288))
	_trap(Vector2(192, 304))
	_ward(Vector2(256, 240))
	_ward(Vector2(448, 240))
	_ward(Vector2(352, 192))
	_glass(Vector2(352, 272))
	_glass(Vector2(192, 192))
	_oil(Vector2(512, 304))
	_civilian(Vector2(352, 256), [Vector2(192, 256), Vector2(512, 256)])
	_civilian(Vector2(192, 464), [Vector2(96, 464), Vector2(576, 464)])
	_pickup(Vector2(576, 496), 0)
	_pickup(Vector2(176,  80), 1)
	_pickup(Vector2(448, 288), 2)
	_pickup(Vector2(672, 288), 2)
	# Weapon pickups — tier 2-3 found weapons
	var _wdrops3 := GameManager.get_floor_weapon_drops(3)
	if _wdrops3.size() >= 1:
		_spawn_weapon_pickup(_wdrops3[0], Vector2(288, 352))
	if _wdrops3.size() >= 2:
		_spawn_weapon_pickup(_wdrops3[1], Vector2(544, 352))

# ── Floor 3B ──────────────────────────────────────────────────────────────────
func _setup_floor3b():
	# Entry
	_guard(_j(Vector2(384, 464)), [_j(Vector2(96,464)), _j(Vector2(672,464))],
		"SENTRY", 90.0, 70.0, 0.36)
	_hound(Vector2(192, 464), [_j(Vector2(96,432)), _j(Vector2(576,464))])
	_hound(Vector2(576, 464), [_j(Vector2(192,464)), _j(Vector2(672,432))])
	_guard(_j(Vector2(96, 496)),  [_j(Vector2(96,432)),  _j(Vector2(96,512))],
		"SENTRY", 85.0, 65.0, 0.40)

	# Barracks — THE BOSS with sentinel web
	_boss(_j(Vector2(352, 240)),
		[_j(Vector2(96,240)), _j(Vector2(608,240)), _j(Vector2(608,304)), _j(Vector2(96,304))])

	_sentinel(Vector2(96,  208))
	_sentinel(Vector2(608, 208))
	_sentinel(Vector2(96,  288))
	_sentinel(Vector2(608, 288))
	_prowler(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,288)), _j(Vector2(96,288))])
	_prowler(_j(Vector2(352, 304)),
		[_j(Vector2(96,304)), _j(Vector2(608,304))])
	_hound(Vector2(192, 272), [_j(Vector2(96,256)), _j(Vector2(608,256))])
	_hound(Vector2(512, 272), [_j(Vector2(96,272)), _j(Vector2(608,272))])

	if _surge() or _escalated(2):
		_sentinel(Vector2(352, 208))
	if _bounty() or _escalated(5):
		_hound(_j(Vector2(352, 256)), [_j(Vector2(96,256)), _j(Vector2(608,256))])
	if _sentinel_comp() or _escalated(4):
		_sentinel(Vector2(352, 288))

	_gnoll(_j(Vector2(192, 256)),    [_j(Vector2(96,240)), _j(Vector2(352,256))])
	_skeleton(_j(Vector2(512, 256)), [_j(Vector2(352,256)), _j(Vector2(608,240))])

	# Vault Left
	_guard(_j(Vector2(64, 64)), [_j(Vector2(32,32)), _j(Vector2(64,112))],
		"WATCHER", 115.0, 95.0, 0.70)
	_loot(Vector2(80, 80), 400, true, 1)
	_loot(Vector2(176, 48), 350, true)

	# Vault Centre
	_guard(_j(Vector2(256, 64)), [_j(Vector2(240,32)), _j(Vector2(464,32))],
		"SENTRY", 115.0, 95.0, 0.35)
	_guard(_j(Vector2(432, 80)), [_j(Vector2(256,80)), _j(Vector2(464,80))],
		"SENTRY", 115.0, 95.0, 0.35)
	_loot(Vector2(352, 48), 800, false, 2)  # RARE
	_loot(Vector2(256, 96), 450, true)

	# Vault Right (LOCKED)
	_guard(_j(Vector2(608, 64)), [_j(Vector2(544,32)), _j(Vector2(704,64))],
		"WATCHER", 100.0, 85.0, 0.68)
	_loot(Vector2(640, 48), 1100, false, 2)
	_loot(Vector2(688,  80), 600, true, 1)

	_trap(Vector2(192, 240))
	_trap(Vector2(512, 240))
	_trap(Vector2(192, 288))
	_trap(Vector2(512, 288))
	_trap(Vector2(352, 192))
	_ward(Vector2(256, 256))
	_ward(Vector2(448, 256))

	var _wdrops3b := GameManager.get_floor_weapon_drops(3)
	if _wdrops3b.size() > 0: _spawn_weapon_pickup(_wdrops3b[0], Vector2(480, 352))
	if _wdrops3b.size() > 1: _spawn_weapon_pickup(_wdrops3b[1], Vector2(256, 352))
	_pickup(Vector2(576, 496), 0)
	_pickup(Vector2(176,  48), 2)
	_pickup(Vector2(672, 288), 1)
	_pickup(Vector2(96, 496), 2)

# ── Floor 1C — Skeleton Watch ─────────────────────────────────────────────────
func _setup_floor1c():
	# Entry — skeleton guards replace humans; different patrol rhythm
	_skeleton(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))])
	_skeleton(_j(Vector2(576, 432)), [_j(Vector2(576,400)), _j(Vector2(576,496))])
	_hound(Vector2(384, 416), [_j(Vector2(96,416)), _j(Vector2(672,416))])

	# Barracks — captain holds key
	var cap := _guard(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256))],
		"CAPTAIN", 120.0, 95.0, 0.32)
	cap.set("is_captain", true); cap.set("key_id", 1)
	_skeleton(_j(Vector2(96, 224)),  [_j(Vector2(96,192)),  _j(Vector2(96,304))])
	_skeleton(_j(Vector2(608, 224)), [_j(Vector2(608,192)), _j(Vector2(608,304))])
	_goblin(_j(Vector2(352, 304)), [_j(Vector2(192,304)), _j(Vector2(512,304))])

	if _surge(): _skeleton(_j(Vector2(352, 240)), [_j(Vector2(192,240)), _j(Vector2(512,240))])

	# Vaults
	_guard(_j(Vector2(80, 64)), [_j(Vector2(80,32)), _j(Vector2(80,112))], "WATCHER", 90.0, 80.0, 0.88)
	_loot(Vector2(96, 80), 200, true)
	_guard(_j(Vector2(352, 64)), [_j(Vector2(256,64)), _j(Vector2(448,64))], "SENTRY", 95.0, 75.0, 0.42)
	_loot(Vector2(352, 48), 400)
	_guard(_j(Vector2(608, 64)), [_j(Vector2(560,64)), _j(Vector2(672,64))], "WATCHER", 90.0, 80.0, 0.85)
	_loot(Vector2(624, 48), 600, false, 1)
	_trap(Vector2(256, 272)); _trap(Vector2(448, 272))
	_ward(Vector2(352, 240))
	var _wdrops1c := GameManager.get_floor_weapon_drops(1)
	if _wdrops1c.size() > 0: _spawn_weapon_pickup(_wdrops1c[0], Vector2(480, 352))
	_pickup(Vector2(576, 496), 1); _pickup(Vector2(176, 80), 2)

# ── Floor 2C — Gnoll Barracks ─────────────────────────────────────────────────
func _setup_floor2c():
	var vr := 100.0; var va := 80.0
	# Entry — gnolls + heavier patrol
	_gnoll(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))])
	_gnoll(_j(Vector2(576, 464)), [_j(Vector2(576,432)), _j(Vector2(576,496))])
	_guard(_j(Vector2(384, 480)), [_j(Vector2(192,480)), _j(Vector2(576,480))],
		"SENTRY", 80.0, 60.0, 0.42)

	# Barracks — captain holds key
	var cap := _guard(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,288)), _j(Vector2(96,288))],
		"CAPTAIN", 130.0, 100.0, 0.30)
	cap.set("is_captain", true); cap.set("key_id", 1)
	_gnoll(_j(Vector2(192, 240)), [_j(Vector2(96,240)), _j(Vector2(352,240))])
	_gnoll(_j(Vector2(512, 240)), [_j(Vector2(352,240)), _j(Vector2(608,240))])
	_guard(_j(Vector2(96, 208)),  [_j(Vector2(96,192)),  _j(Vector2(96,304))], "WATCHER", vr, va, 0.88)
	_guard(_j(Vector2(608, 208)), [_j(Vector2(608,192)), _j(Vector2(608,304))], "WATCHER", vr, va, 0.88)

	if _surge():   _gnoll(_j(Vector2(352, 288)), [_j(Vector2(192,288)), _j(Vector2(512,288))])
	if _bounty():  _hound(_j(Vector2(192, 256)), [_j(Vector2(96,256)), _j(Vector2(608,256))])
	if _sentinel_comp(): _sentinel(Vector2(352, 208))

	_civilian(Vector2(384, 256), [Vector2(192, 256), Vector2(576, 256)])
	_guard(_j(Vector2(80, 64)), [_j(Vector2(80,32)), _j(Vector2(80,112))], "WATCHER", vr, va, 0.88)
	_loot(Vector2(112, 96), 250, true)
	_guard(_j(Vector2(352, 64)), [_j(Vector2(256,64)), _j(Vector2(448,64))], "SENTRY", vr, va, 0.42)
	_loot(Vector2(352, 48), 500)
	_guard(_j(Vector2(608, 64)), [_j(Vector2(560,64)), _j(Vector2(672,64))], "WATCHER", 95.0, 85.0, 0.82)
	_loot(Vector2(624, 48), 700, false, 1)
	_trap(Vector2(272, 256)); _trap(Vector2(432, 256))
	_glass(Vector2(352, 304)); _oil(Vector2(192, 416))
	var _wdrops2c := GameManager.get_floor_weapon_drops(2)
	if _wdrops2c.size() > 0: _spawn_weapon_pickup(_wdrops2c[0], Vector2(480, 352))
	if _wdrops2c.size() > 1: _spawn_weapon_pickup(_wdrops2c[1], Vector2(256, 368))
	_pickup(Vector2(576, 496), 0); _pickup(Vector2(176, 80), 2)

# ── Floor 3C — The Chancellor's Vault ─────────────────────────────────────────
func _setup_floor3c():
	# Entry — prowlers and hounds, no regular guards
	_prowler(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))])
	_prowler(_j(Vector2(576, 464)), [_j(Vector2(192,464)), _j(Vector2(672,432))])
	_hound(Vector2(384, 416), [_j(Vector2(96,416)), _j(Vector2(672,416))])
	_hound(Vector2(192, 480), [_j(Vector2(96,464)), _j(Vector2(384,464))])

	# Barracks — BOSS + prowler web
	_boss(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,288)), _j(Vector2(96,288))])
	_prowler(_j(Vector2(192, 240)), [_j(Vector2(96,240)), _j(Vector2(352,256))])
	_prowler(_j(Vector2(512, 240)), [_j(Vector2(352,256)), _j(Vector2(608,240))])
	_sentinel(Vector2(96, 208)); _sentinel(Vector2(608, 208))
	_hound(Vector2(352, 304), [_j(Vector2(96,304)), _j(Vector2(608,304))])

	if _surge():   _prowler(_j(Vector2(352, 208)), [_j(Vector2(96,208)), _j(Vector2(608,208))])
	if _bounty():  _hound(_j(Vector2(352, 240)), [_j(Vector2(96,240)), _j(Vector2(608,240))])

	_gnoll(_j(Vector2(256, 272)), [_j(Vector2(192,256)), _j(Vector2(352,272))])
	_skeleton(_j(Vector2(448, 272)), [_j(Vector2(352,272)), _j(Vector2(608,256))])

	_guard(_j(Vector2(64, 64)), [_j(Vector2(32,32)), _j(Vector2(64,112))], "WATCHER", 115.0, 95.0, 0.72)
	_loot(Vector2(80, 80), 450, true, 1)
	_guard(_j(Vector2(352, 64)), [_j(Vector2(240,32)), _j(Vector2(464,32))], "SENTRY", 110.0, 90.0, 0.36)
	_loot(Vector2(352, 48), 850, false, 2)
	_guard(_j(Vector2(608, 64)), [_j(Vector2(544,32)), _j(Vector2(704,64))], "WATCHER", 100.0, 85.0, 0.70)
	_loot(Vector2(640, 48), 1200, false, 2)
	_trap(Vector2(192, 240)); _trap(Vector2(512, 240))
	_trap(Vector2(192, 288)); _trap(Vector2(512, 288))
	_ward(Vector2(256, 256)); _ward(Vector2(448, 256))
	var _wdrops3c := GameManager.get_floor_weapon_drops(3)
	if _wdrops3c.size() > 0: _spawn_weapon_pickup(_wdrops3c[0], Vector2(480, 352))
	if _wdrops3c.size() > 1: _spawn_weapon_pickup(_wdrops3c[1], Vector2(256, 352))
	_pickup(Vector2(576, 496), 0); _pickup(Vector2(176, 48), 1)
	_pickup(Vector2(672, 288), 2); _pickup(Vector2(96, 496), 1)

# ── Floor 4A — The Inner Sanctum ─────────────────────────────────────────────
func _setup_floor4():
	var vr := 130.0; var va := 110.0

	# Entry — two wardens + gnoll patrol; lockdown active if incoming
	_guard(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))],
		"WARDEN", vr, va, 0.32)
	_guard(_j(Vector2(576, 432)), [_j(Vector2(576,400)), _j(Vector2(576,496))],
		"WARDEN", vr, va, 0.32)
	_hound(Vector2(384, 448), [_j(Vector2(96,448)), _j(Vector2(672,448))])
	_hound(Vector2(192, 480), [_j(Vector2(96,464)), _j(Vector2(384,464))])
	_gnoll(_j(Vector2(384, 400)), [_j(Vector2(192,400)), _j(Vector2(576,400))])

	# Centre hall — prowler + elite guards
	_boss(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,288)), _j(Vector2(96,288))])
	_prowler(_j(Vector2(192, 240)), [_j(Vector2(96,240)), _j(Vector2(352,256))])
	_prowler(_j(Vector2(512, 240)), [_j(Vector2(352,256)), _j(Vector2(608,240))])
	_guard(_j(Vector2(96, 208)),  [_j(Vector2(96,192)),  _j(Vector2(96,304))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(608, 208)), [_j(Vector2(608,192)), _j(Vector2(608,304))], "WARDEN", vr, va, 0.70)
	_skeleton(_j(Vector2(256, 288)), [_j(Vector2(192,256)), _j(Vector2(352,288))])
	_skeleton(_j(Vector2(448, 288)), [_j(Vector2(352,288)), _j(Vector2(608,256))])
	_gnoll(_j(Vector2(256, 240)),  [_j(Vector2(192,208)), _j(Vector2(352,256))])

	if _surge() or _escalated(2): _prowler(_j(Vector2(384, 192)), [_j(Vector2(96,192)), _j(Vector2(672,192))])
	if _bounty() or _escalated(4): _hound(_j(Vector2(384, 288)), [_j(Vector2(96,288)), _j(Vector2(672,288))])
	if GameManager._lockdown_incoming: _sentinel(Vector2(352, 192)); _sentinel(Vector2(352, 304))

	# Vault zone — three loot targets, heavy ward coverage
	_guard(_j(Vector2(64, 48)),  [_j(Vector2(32,32)), _j(Vector2(64,112))], "WATCHER", vr, va, 0.70)
	_guard(_j(Vector2(352, 64)), [_j(Vector2(240,32)), _j(Vector2(464,32))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(672, 64)), [_j(Vector2(544,32)), _j(Vector2(704,80))], "WATCHER", vr, va, 0.70)
	_loot(Vector2(80, 64), 600, true, 1)
	_loot(Vector2(352, 48), 1000, false, 2)
	_loot(Vector2(640, 64), 800, true, 2)

	_trap(Vector2(192, 208)); _trap(Vector2(512, 192)); _trap(Vector2(352, 288))
	_trap(Vector2(192, 304)); _trap(Vector2(512, 304))
	_ward(Vector2(256, 240)); _ward(Vector2(448, 240))
	_ward(Vector2(256, 288)); _ward(Vector2(448, 288))
	_glass(Vector2(352, 256)); _glass(Vector2(192, 256)); _glass(Vector2(512, 256))
	_oil(Vector2(96, 288)); _oil(Vector2(608, 288))
	_civilian(Vector2(352, 352), [Vector2(192, 352), Vector2(512, 352)])
	_pickup(Vector2(576, 496), 1); _pickup(Vector2(176, 80), 2)
	_pickup(Vector2(448, 304), 2); _pickup(Vector2(672, 304), 1)
	# Weapon pickups — tier 2-3 found weapons
	var _wdrops4 := GameManager.get_floor_weapon_drops(4)
	if _wdrops4.size() >= 1:
		_spawn_weapon_pickup(_wdrops4[0], Vector2(288, 352))
	if _wdrops4.size() >= 2:
		_spawn_weapon_pickup(_wdrops4[1], Vector2(512, 432))

# ── Floor 4B ──────────────────────────────────────────────────────────────────
func _setup_floor4b():
	var vr := 130.0; var va := 110.0

	# Entry — skeleton sentries + gnoll patrol
	_skeleton(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))])
	_skeleton(_j(Vector2(576, 432)), [_j(Vector2(576,400)), _j(Vector2(576,496))])
	_gnoll(_j(Vector2(384, 448)),    [_j(Vector2(96,448)),  _j(Vector2(672,448))])
	_hound(Vector2(192, 480), [_j(Vector2(96,464)), _j(Vector2(384,448))])

	# Centre — two prowlers flanking boss
	_boss(_j(Vector2(384, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,304)), _j(Vector2(96,304))])
	_prowler(_j(Vector2(192, 256)), [_j(Vector2(96,240)), _j(Vector2(384,256))])
	_prowler(_j(Vector2(576, 256)), [_j(Vector2(384,256)), _j(Vector2(672,240))])
	_guard(_j(Vector2(96, 192)),  [_j(Vector2(96,160)),  _j(Vector2(96,320))],  "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(608, 192)), [_j(Vector2(608,160)), _j(Vector2(608,320))], "WARDEN", vr, va, 0.70)
	_gnoll(_j(Vector2(256, 304)), [_j(Vector2(192,288)), _j(Vector2(352,304))])
	_gnoll(_j(Vector2(448, 304)), [_j(Vector2(352,304)), _j(Vector2(576,288))])
	_hound(Vector2(352, 304), [_j(Vector2(96,304)), _j(Vector2(608,304))])
	_skeleton(_j(Vector2(256, 208)), [_j(Vector2(192,192)), _j(Vector2(352,208))])
	_skeleton(_j(Vector2(448, 208)), [_j(Vector2(352,208)), _j(Vector2(576,192))])

	if _surge() or _escalated(3): _prowler(_j(Vector2(352, 192)), [_j(Vector2(96,192)), _j(Vector2(608,192))])
	if _bounty() or _escalated(5): _hound(_j(Vector2(352, 240)), [_j(Vector2(96,240)), _j(Vector2(608,240))])
	if GameManager._lockdown_incoming: _sentinel(Vector2(352, 192)); _sentinel(Vector2(192, 304))

	# Vault
	_guard(_j(Vector2(64, 64)),  [_j(Vector2(32,32)), _j(Vector2(96,112))], "WATCHER", vr, va, 0.72)
	_guard(_j(Vector2(352, 64)), [_j(Vector2(240,32)), _j(Vector2(464,32))], "WARDEN",  vr, va, 0.35)
	_guard(_j(Vector2(640, 80)), [_j(Vector2(544,32)), _j(Vector2(704,96))], "WATCHER", vr, va, 0.70)
	_loot(Vector2(80, 64), 600, true, 1)
	_loot(Vector2(352, 48), 1000, false, 2)
	_loot(Vector2(704, 64), 700, true, 2)

	_trap(Vector2(192, 208)); _trap(Vector2(512, 208))
	_trap(Vector2(192, 304)); _trap(Vector2(512, 304))
	_ward(Vector2(256, 256)); _ward(Vector2(448, 256))
	_ward(Vector2(352, 208)); _ward(Vector2(352, 304))
	_glass(Vector2(192, 256)); _glass(Vector2(512, 256))
	_oil(Vector2(256, 288)); _oil(Vector2(448, 288))
	_civilian(Vector2(352, 352), [Vector2(192, 352), Vector2(512, 352)])
	_civilian(Vector2(192, 480), [Vector2(96, 480), Vector2(384, 464)])
	var _wdrops4b := GameManager.get_floor_weapon_drops(4)
	if _wdrops4b.size() > 0: _spawn_weapon_pickup(_wdrops4b[0], Vector2(480, 368))
	if _wdrops4b.size() > 1: _spawn_weapon_pickup(_wdrops4b[1], Vector2(256, 368))
	_pickup(Vector2(672, 304), 2); _pickup(Vector2(96, 304), 1)
	_pickup(Vector2(576, 480), 0); _pickup(Vector2(176, 80), 2)

# ── Floor 4C ──────────────────────────────────────────────────────────────────
func _setup_floor4c():
	var vr := 125.0; var va := 105.0

	# Entry — gnolls and hounds; high scent threat
	_gnoll(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))])
	_gnoll(_j(Vector2(576, 464)), [_j(Vector2(576,400)), _j(Vector2(192,464))])
	_hound(Vector2(384, 448), [_j(Vector2(96,448)), _j(Vector2(672,448))])
	_hound(Vector2(192, 496), [_j(Vector2(96,480)), _j(Vector2(384,464))])
	_hound(Vector2(576, 496), [_j(Vector2(672,480)), _j(Vector2(384,464))])

	# Centre
	_boss(_j(Vector2(352, 272)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,288)), _j(Vector2(96,288))])
	_prowler(_j(Vector2(192, 240)), [_j(Vector2(96,240)), _j(Vector2(352,256))])
	_prowler(_j(Vector2(512, 240)), [_j(Vector2(352,256)), _j(Vector2(608,240))])
	_guard(_j(Vector2(96, 192)),  [_j(Vector2(96,160)),  _j(Vector2(96,304))],  "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(608, 192)), [_j(Vector2(608,160)), _j(Vector2(608,304))], "WARDEN", vr, va, 0.70)
	_skeleton(_j(Vector2(256, 272)), [_j(Vector2(192,256)), _j(Vector2(352,272))])
	_skeleton(_j(Vector2(448, 272)), [_j(Vector2(352,272)), _j(Vector2(608,256))])
	if _surge() or _escalated(2): _prowler(_j(Vector2(352, 192)), [_j(Vector2(96,192)), _j(Vector2(608,192))])
	if GameManager._lockdown_incoming: _sentinel(Vector2(352, 208)); _sentinel(Vector2(352, 304))

	# Vault
	_guard(_j(Vector2(64, 64)),  [_j(Vector2(32,32)), _j(Vector2(64,112))], "WATCHER", vr, va, 0.70)
	_guard(_j(Vector2(352, 64)), [_j(Vector2(240,32)), _j(Vector2(464,32))], "WARDEN",  vr, va, 0.35)
	_guard(_j(Vector2(608, 64)), [_j(Vector2(544,32)), _j(Vector2(704,64))], "WATCHER", vr, va, 0.70)
	_loot(Vector2(80, 64), 700, true, 2)
	_loot(Vector2(352, 48), 1100, false, 2)
	_loot(Vector2(640, 64), 900, true, 2)

	_trap(Vector2(192, 208)); _trap(Vector2(512, 208)); _trap(Vector2(352, 288))
	_ward(Vector2(256, 256)); _ward(Vector2(448, 256)); _ward(Vector2(352, 208))
	_glass(Vector2(192, 256)); _glass(Vector2(512, 256)); _glass(Vector2(352, 272))
	_oil(Vector2(256, 288)); _oil(Vector2(448, 288))
	_civilian(Vector2(352, 352), [Vector2(192, 352), Vector2(512, 352)])
	var _wdrops4c := GameManager.get_floor_weapon_drops(4)
	if _wdrops4c.size() > 0: _spawn_weapon_pickup(_wdrops4c[0], Vector2(480, 368))
	if _wdrops4c.size() > 1: _spawn_weapon_pickup(_wdrops4c[1], Vector2(256, 368))
	_pickup(Vector2(672, 288), 2); _pickup(Vector2(96, 288), 1)
	_pickup(Vector2(576, 480), 1); _pickup(Vector2(176, 80), 2)

# ── Floor 5 — The Throne Room (single layout; always max difficulty) ──────────
func _setup_floor5():
	var vr := 145.0; var va := 120.0

	# Entry — locked down; every enemy type represented
	_guard(_j(Vector2(192, 464)), [_j(Vector2(96,464)), _j(Vector2(576,464))],
		"WARDEN", vr, va, 0.28)
	_guard(_j(Vector2(576, 432)), [_j(Vector2(576,400)), _j(Vector2(576,496))],
		"WARDEN", vr, va, 0.28)
	_hound(Vector2(384, 448), [_j(Vector2(96,448)), _j(Vector2(672,448))])
	_hound(Vector2(192, 480), [_j(Vector2(96,464)), _j(Vector2(384,464))])
	_hound(Vector2(576, 480), [_j(Vector2(672,464)), _j(Vector2(384,464))])
	_gnoll(_j(Vector2(384, 400)), [_j(Vector2(96,400)), _j(Vector2(672,400))])
	_gnoll(_j(Vector2(192, 400)), [_j(Vector2(96,400)), _j(Vector2(384,400))])

	# Throne hall — BOSS flanked by full retinue
	_boss(_j(Vector2(352, 256)),
		[_j(Vector2(96,256)), _j(Vector2(608,256)), _j(Vector2(608,208)), _j(Vector2(96,208))])
	_prowler(_j(Vector2(192, 240)), [_j(Vector2(96,240)), _j(Vector2(352,256))])
	_prowler(_j(Vector2(512, 240)), [_j(Vector2(352,256)), _j(Vector2(608,240))])
	_prowler(_j(Vector2(352, 304)), [_j(Vector2(96,304)), _j(Vector2(608,304))])
	_guard(_j(Vector2(96, 192)),  [_j(Vector2(96,160)),  _j(Vector2(96,320))],  "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(608, 192)), [_j(Vector2(608,160)), _j(Vector2(608,320))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(192, 192)), [_j(Vector2(96,192)),  _j(Vector2(352,192))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(512, 192)), [_j(Vector2(352,192)), _j(Vector2(608,192))], "WARDEN", vr, va, 0.35)
	_skeleton(_j(Vector2(256, 288)), [_j(Vector2(192,256)), _j(Vector2(352,288))])
	_skeleton(_j(Vector2(448, 288)), [_j(Vector2(352,288)), _j(Vector2(608,256))])
	_gnoll(_j(Vector2(256, 208)),   [_j(Vector2(192,192)), _j(Vector2(352,208))])
	_gnoll(_j(Vector2(448, 208)),   [_j(Vector2(352,208)), _j(Vector2(576,192))])
	_goblin(_j(Vector2(192, 304)),  [_j(Vector2(96,288)),  _j(Vector2(352,304))])
	_goblin(_j(Vector2(512, 304)),  [_j(Vector2(352,304)), _j(Vector2(672,288))])
	_sentinel(Vector2(352, 192)); _sentinel(Vector2(352, 304))
	_sentinel(Vector2(96, 256));  _sentinel(Vector2(608, 256))

	if _surge() or _escalated(2): _prowler(_j(Vector2(192, 304)), [_j(Vector2(96,304)), _j(Vector2(352,304))])
	if _bounty() or _escalated(3): _hound(_j(Vector2(352, 240)), [_j(Vector2(96,240)), _j(Vector2(608,240))])

	# Throne vault — three pieces of the relic
	_guard(_j(Vector2(64, 48)),  [_j(Vector2(32,32)), _j(Vector2(64,112))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(352, 64)), [_j(Vector2(240,32)), _j(Vector2(464,32))], "WARDEN", vr, va, 0.32)
	_guard(_j(Vector2(640, 48)), [_j(Vector2(544,32)), _j(Vector2(704,80))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(192, 96)), [_j(Vector2(96,96)),  _j(Vector2(352,96))], "WATCHER", vr, va, 0.35)
	_guard(_j(Vector2(512, 96)), [_j(Vector2(352,96)), _j(Vector2(608,96))], "WATCHER", vr, va, 0.35)
	_loot(Vector2(80, 64), 800, true, 2)
	_loot(Vector2(352, 48), 1500, false, 2)   # primary — throne relic
	_loot(Vector2(704, 48), 1000, true, 2)

	_trap(Vector2(192, 208)); _trap(Vector2(512, 192))
	_trap(Vector2(192, 304)); _trap(Vector2(512, 304))
	_trap(Vector2(256, 256)); _trap(Vector2(448, 256))
	_ward(Vector2(256, 208)); _ward(Vector2(448, 208))
	_ward(Vector2(256, 288)); _ward(Vector2(448, 288))
	_ward(Vector2(352, 192)); _ward(Vector2(352, 304))
	_glass(Vector2(192, 256)); _glass(Vector2(512, 256))
	_glass(Vector2(352, 256)); _glass(Vector2(192, 304)); _glass(Vector2(512, 304))
	_oil(Vector2(96, 240));  _oil(Vector2(608, 240))
	_oil(Vector2(96, 304));  _oil(Vector2(608, 304))
	_civilian(Vector2(352, 352), [Vector2(192, 352), Vector2(512, 352)])
	_civilian(Vector2(192, 400), [Vector2(96, 400), Vector2(384, 400)])
	_civilian(Vector2(512, 400), [Vector2(384, 400), Vector2(672, 400)])
	_pickup(Vector2(176, 80), 2); _pickup(Vector2(672, 304), 2)
	_pickup(Vector2(96, 480),  1); _pickup(Vector2(576, 480), 1)
	_pickup(Vector2(352, 400), 0)
	# Weapon pickups — tier 3 found weapons
	var _wdrops5 := GameManager.get_floor_weapon_drops(5)
	if _wdrops5.size() >= 1:
		_spawn_weapon_pickup(_wdrops5[0], Vector2(288, 352))
	if _wdrops5.size() >= 2:
		_spawn_weapon_pickup(_wdrops5[1], Vector2(512, 432))

# ── Optional side passage — elite guard + bonus loot ─────────────────────────
func _spawn_side_passage():
	# Spawn a single elite watcher near the vault-right area as a side-room guard
	# Place pickup items and bonus loot in a tucked corner
	var elite := _guard(_j(Vector2(672, 64)), [_j(Vector2(640,32)), _j(Vector2(704,96))],
		"ELITE", 100.0, 90.0, 0.70)
	elite.set("vision_range", 100.0 + GameManager.current_floor * 5.0)
	var bonus_loot := _loot(Vector2(704, 48),
		200 + GameManager.current_floor * 100, true,
		mini(GameManager.current_floor - 1, 2))
	# Extra item pickup
	_pickup(Vector2(704, 80), (_rng.randi() % 3) + 1)

# ── Spawn safety ───────────────────────────────────────────────────────────────
func _ensure_safe_spawn():
	const MIN_DIST := 96.0
	var player := get_tree().get_first_node_in_group("player")
	var ppos: Vector2 = player.position if player else Vector2(384, 480)
	for node in get_children():
		if not node.is_in_group("guards"):
			continue
		var pts: Array = node.get("patrol_points") if node.get("patrol_points") else []
		# Gather all candidate positions: current spawn + all patrol points
		var candidates: Array[Vector2] = []
		candidates.append(node.position)
		for pt: Vector2 in pts:
			candidates.append(pt)
		# Find the first candidate that is clear of physics colliders AND far from player
		var placed := false
		for candidate: Vector2 in candidates:
			if _is_position_clear(candidate, node) and ppos.distance_to(candidate) >= MIN_DIST:
				node.position = candidate
				placed = true
				break
		if not placed:
			# Fallback: first clear candidate regardless of player distance
			for candidate: Vector2 in candidates:
				if _is_position_clear(candidate, node):
					node.position = candidate
					placed = true
					break
		if not placed:
			# Last resort: push perpendicular to map centre
			node.position = Vector2(ppos.x + MIN_DIST * sign(ppos.x - 384.0), ppos.y - MIN_DIST)

func _is_position_clear(pos: Vector2, exclude: Node) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = pos
	if exclude.has_method("get_rid"):
		query.exclude = [exclude.get_rid()]
	return space.intersect_point(query).size() == 0

# ── Reinforcements ─────────────────────────────────────────────────────────────
func _on_alert_triggered():
	var esc := GameManager.alert_escalation
	if esc >= 3 and _reinforcements_spawned < 1:
		_spawn_reinforcement(1)
	elif esc >= 6 and _reinforcements_spawned < 2:
		_spawn_reinforcement(2)

func _spawn_reinforcement(wave: int):
	_reinforcements_spawned = wave
	var entry := Vector2(384, 528)
	var g: Node
	if wave >= 2 or (_rng.randi() % 2 == 1 and GameManager.current_floor >= 2):
		g = _prowler(entry, [_j(Vector2(96,480)), _j(Vector2(672,480)), _j(Vector2(352,288))])
	else:
		g = _guard(entry,
			[_j(Vector2(96,480)), _j(Vector2(672,480)), _j(Vector2(352,320))],
			"REINFORCE", 90.0, 75.0, 0.30)
	if g:
		g.set("alert_state", 1)
		g.set("de_escalate_timer", 10.0)
		g.set("investigate_pos", Vector2(352, 256))
	GameManager.shake(2.5, 0.22)
	GameManager.reinforcement_incoming.emit()

# ── Spawn helpers ──────────────────────────────────────────────────────────────
func _boss(pos: Vector2, patrol: Array) -> Node:
	var g := _guard(pos, patrol, "BOSS", 120.0, 110.0, 0.28)
	g.set("is_boss", true)
	g.set("is_captain", true)
	g.set("key_id", 1)
	GameManager.pick_boss_name()
	return g

func _guard(pos: Vector2, patrol: Array, label: String,
			vrange := 80.0, vangle := 60.0, interval := 0.40) -> Node:
	var g := GuardScene.instantiate()
	g.position = pos
	var typed: Array[Vector2] = []
	for p: Vector2 in patrol:
		typed.append(p)
	g.patrol_points = typed
	g.guard_label   = label
	g.vision_range  = vrange
	g.vision_angle  = vangle
	g.move_interval = interval
	add_child(g)
	return g

func _sentinel(pos: Vector2) -> Node:
	var g := GuardScene.instantiate()
	g.position = pos
	g.patrol_points = []
	g.guard_label   = "SENTINEL"
	g.vision_range  = 90.0
	g.vision_angle  = 120.0
	g.move_interval = 0.40
	add_child(g)
	return g

func _prowler(pos: Vector2, patrol: Array) -> Node:
	var g := GuardScene.instantiate()
	g.position = pos
	var typed: Array[Vector2] = []
	for p: Vector2 in patrol:
		typed.append(p)
	g.patrol_points  = typed
	g.guard_label    = "PROWLER"
	g.vision_range   = 95.0
	g.vision_angle   = 45.0
	g.move_interval  = 0.22
	g.chase_interval = 0.14
	add_child(g)
	return g

func _skeleton(pos: Vector2, patrol: Array, label := "SKELETON") -> Node:
	var g := GuardScene.instantiate()
	g.position = pos
	var typed: Array[Vector2] = []
	for p: Vector2 in patrol:
		typed.append(p)
	g.patrol_points = typed
	g.guard_label   = label
	g.vision_range  = 90.0
	g.vision_angle  = 70.0
	g.move_interval = 0.36
	g.enemy_type    = 1
	add_child(g)
	return g

func _goblin(pos: Vector2, patrol: Array) -> Node:
	var g := GuardScene.instantiate()
	g.position = pos
	var typed: Array[Vector2] = []
	for p: Vector2 in patrol:
		typed.append(p)
	g.patrol_points  = typed
	g.guard_label    = "LOOKOUT"
	g.vision_range   = 70.0
	g.vision_angle   = 55.0
	g.move_interval  = 0.30
	g.chase_interval = 0.18
	g.enemy_type     = 2
	add_child(g)
	return g

func _gnoll(pos: Vector2, patrol: Array) -> Node:
	var g := GuardScene.instantiate()
	g.position = pos
	var typed: Array[Vector2] = []
	for p: Vector2 in patrol:
		typed.append(p)
	g.patrol_points  = typed
	g.guard_label    = "GNOLL"
	g.vision_range   = 85.0
	g.vision_angle   = 60.0
	g.move_interval  = 0.32
	g.chase_interval = 0.16
	g.enemy_type     = 3
	add_child(g)
	return g

func _hound(pos: Vector2, patrol: Array) -> Node:
	var h := HoundScene.instantiate()
	h.position = pos
	var typed: Array[Vector2] = []
	for p: Vector2 in patrol:
		typed.append(p)
	h.patrol_points = typed
	add_child(h)
	return h

func _loot(pos: Vector2, value: int, is_bonus := false, rarity := 0) -> Node:
	var l := LootScene.instantiate()
	l.position   = pos
	l.loot_value = value
	l.is_bonus   = is_bonus
	l.rarity     = rarity
	add_child(l)
	l.add_to_group("interactable")
	return l

func _trap(pos: Vector2) -> Node:
	var t := TrapScene.instantiate()
	t.position = pos
	add_child(t)
	return t

func _ward(pos: Vector2) -> Node:
	var w := WardScene.instantiate()
	w.position = pos
	add_child(w)
	return w

func _spawn_weapon_pickup(weapon_id: String, world_pos: Vector2) -> Node:
	var wp := Node2D.new()
	wp.set_script(load("res://WeaponPickup.gd"))
	wp.set("weapon_id", weapon_id)
	wp.position = world_pos
	add_child(wp)
	return wp

func _pickup(pos: Vector2, item_type: int) -> Node:
	var p := PickupScene.instantiate()
	p.position  = pos
	p.item_type = item_type
	add_child(p)
	return p

func _glass(pos: Vector2) -> Node:
	var g := Node2D.new()
	g.set_script(_glass_script)
	g.position = pos
	add_child(g)
	return g

func _oil(pos: Vector2) -> Node:
	var o := Node2D.new()
	o.set_script(_oil_script)
	o.position = pos
	add_child(o)
	return o

func _curtain(pos: Vector2) -> Node:
	var c := Node2D.new()
	c.set_script(_curtain_script)
	c.position = pos
	add_child(c)
	return c

var _informant_assigned := false

func _civilian(pos: Vector2, patrol: Array) -> Node:
	var c := Node2D.new()
	c.set_script(_civilian_script)
	c.position = pos
	var typed: Array[Vector2] = []
	for p: Vector2 in patrol:
		typed.append(p)
	c.set("patrol_points", typed)
	# INFORMANT modifier: first civilian spawned is the spy
	if GameManager.run_modifier == "INFORMANT" and not _informant_assigned:
		c.set("is_informant", true)
		_informant_assigned = true
	add_child(c)
	return c

func _locked_door(pos: Vector2, did: int) -> Node:
	var d := Node2D.new()
	d.set_script(_locked_door_script)
	d.position = pos
	d.set("door_id", did)
	add_child(d)
	return d
