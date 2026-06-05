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
const _bell_script       := preload("res://AlarmBell.gd")

var _rng := RandomNumberGenerator.new()
var _reinforcements_spawned := 0

# ── Map coordinate reference (48×36 tiles, 16 px/tile = 768×576) ─────────────
# Vault          : x 128-640, y 16-96    (cols  8-39, rows  1-6)
# Captain's Office: x 16-272, y 128-272  (cols  1-16, rows  8-16)
# Antechamber    : x 320-592, y 128-272  (cols 20-36, rows  8-16)
# Armory         : x 624-736, y 128-272  (cols 39-45, rows  8-16)
# Barracks       : x 16-304,  y 304-448  (cols  1-18, rows 19-27)
# Storeroom      : x 464-736, y 304-448  (cols 29-45, rows 19-27)
# Entry Foyer    : x 224-544, y 464-560  (cols 14-33, rows 29-34)
#
# LockedDoor sits at (432, 112) — Antechamber→Vault corridor cols 26-27, rows 6-7
# Player spawn: Vector2(384, 512) — col 24, row 32 (Entry Foyer centre)

func _ready():
	y_sort_enabled = true  # children render in Y order for 2.5D depth sorting
	GameManager.pick_floor_complication()
	GameManager.pick_floor_objective()
	GameManager.start_floor_timer()
	GameManager.alert_triggered.connect(_on_alert_triggered)
	_rng.seed = GameManager.run_seed + GameManager.current_floor * 7919

	# Entry spawn position — varies by preheist entry selection
	const ENTRY_SPAWNS: Dictionary = {
		"FRONT_DOOR":  Vector2(384, 536), "SIDE_WINDOW": Vector2(560, 400),
		"SEWER":       Vector2(200, 450), "GUARD_POST":  Vector2(384, 536),
		"ROOF":        Vector2(384,  60), "SERVANT":     Vector2(480, 536),
		"NOBLE_PARTY": Vector2(384, 500), "VAULT_SHAFT": Vector2(384,  56),
		"SHADOW_ENTRY":Vector2(150, 400), "DIPLOMATIC":  Vector2(384, 536),
		"WARD_BYPASS": Vector2(300, 200), "CHAOS":       Vector2(550, 510),
		"TUNNEL":      Vector2(200, 510), "BOLD":        Vector2(384, 536),
		"PHANTOM":     Vector2(150, 380),
	}
	var spawn_pos: Vector2 = ENTRY_SPAWNS.get(GameManager.preheist_entry, Vector2(384, 512))
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node:
		player_node.position = spawn_pos
		# SEWER/SHADOW_ENTRY/PHANTOM/TUNNEL — start crouched and undetected
		if GameManager.preheist_entry in ["SEWER", "SHADOW_ENTRY", "PHANTOM", "TUNNEL"]:
			player_node.set("is_sneaking", true)
		# CHAOS — distract all entry-room guards (start them SUSPICIOUS in opposite direction)
		if GameManager.preheist_entry == "CHAOS":
			for guard in get_tree().get_nodes_in_group("guards"):
				var to_player: Vector2 = spawn_pos - (guard as Node2D).global_position
				if to_player.length() < 200.0:
					# Turn guards away from player — face away from the entry
					guard.set("facing", -to_player.normalized() if to_player.length() > 0 else Vector2(0, -1))
					guard.set("alert_state", 1)    # SUSPICIOUS — drawn toward distraction
					guard.set("de_escalate_timer", 8.0)
		# NOBLE_PARTY — start with detection fill rate halved (player is disguised as a guest)
		elif GameManager.preheist_entry == "NOBLE_PARTY":
			player_node.set_meta("disguised", true)   # Guard.gd reads this to halve detection
		# SERVANT — start with a coin in hand and one free item use
		elif GameManager.preheist_entry == "SERVANT":
			if player_node.has_method("add_item"):
				player_node.call("add_item", 0, 2)  # ItemType.COIN = 0, count 2 (servant's cover)
		# ROOF — all guards start looking down (away from roof entry direction)
		elif GameManager.preheist_entry == "ROOF":
			for guard in get_tree().get_nodes_in_group("guards"):
				if guard.global_position.y < 200.0:   # only vault-level guards
					guard.set("facing", Vector2(0, 1))  # looking down, not at roof entry
		# DIPLOMATIC — start with reduced wanted level (credentials cleared one strike)
		elif GameManager.preheist_entry == "DIPLOMATIC":
			GameManager.wanted_level = maxi(0, GameManager.wanted_level - 1)
		# BOLD — all nearby guards start ALERT (direct assault; player gets +50gp per takedown bonus)
		elif GameManager.preheist_entry == "BOLD":
			for guard in get_tree().get_nodes_in_group("guards"):
				if guard.global_position.distance_to(spawn_pos) < 300.0:
					guard.set("alert_state", 2)  # AlertState.ALERT
					guard.set("_alert_target", spawn_pos)
			GameManager.wanted_level = mini(5, GameManager.wanted_level + 1)
		# VAULT_SHAFT — player starts crouched + first ward is auto-disabled
		elif GameManager.preheist_entry == "VAULT_SHAFT":
			player_node.set("is_sneaking", true)
			for ward in get_tree().get_nodes_in_group("magic_wards"):
				if ward.global_position.distance_to(spawn_pos) < 150.0:
					if ward.has_method("destroy_ward"):
						ward.destroy_ward()
					break
		# PHANTOM — player invisible for 3s on entry; detection doesn't build
		elif GameManager.preheist_entry == "PHANTOM":
			player_node.set("is_sneaking", true)
			player_node.set_meta("phantom_entry_timer", 3.0)

	# Apply purchased intel effects
	if "patrol_schedule" in GameManager.preheist_intel:
		for guard in get_tree().get_nodes_in_group("guards"):
			guard.set("show_patrol_path", true)
	if "guard_weakness" in GameManager.preheist_intel:
		for guard in get_tree().get_nodes_in_group("guards"):
			guard.set("show_stats", true)
	# entry_map intel: FogOfWar._reveal_entry_room() handles this via call_deferred

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
		5:
			if variant == 0:   _setup_floor5()
			elif variant == 1: _setup_floor5b()
			else:              _setup_floor5c()
		_:
			if variant == 0:   _setup_floor6()
			elif variant == 1: _setup_floor6b()
			else:              _setup_floor6c()

	# Optional side passage — 50% chance, adds a locked side room with elite guard + bonus loot
	if _rng.randi() % 2 == 0:
		_spawn_side_passage()

	# Locked door — Antechamber → Vault corridor (cols 26-27, rows 6-7), requires captain's key
	_locked_door(Vector2(432, 112), 1)

	_spawn_interactables()
	_spawn_floor_relic()
	_ensure_safe_spawn()
	_apply_wanted_level_effects()
	_spawn_archetype_guards()

	# Fog-of-war overlay — high z_index keeps it above all game nodes regardless of Y sort
	var fog := Node2D.new()
	fog.set_script(_fog_script)
	fog.z_index = 100
	add_child(fog)

# ── Returns base ± jitter snapped to 16-px grid ───────────────────────────────
func _j(base: Vector2, rx: int = 1, ry: int = 1) -> Vector2:
	var ox := _rng.randi_range(-rx, rx) * 16
	var oy := _rng.randi_range(-ry, ry) * 16
	return base + Vector2(ox, oy)

# ── Wanted level world consequences ──────────────────────────────────────────
func _apply_wanted_level_effects():
	var wl := GameManager.wanted_level
	# Apply MetaProgress city heat — guards get harder proportional to persistent heat
	var heat_bonus: int   = MetaProgress.get_heat_guard_bonus()
	var heat_patrol: float = MetaProgress.get_heat_patrol_mult()
	if heat_bonus > 0 or heat_patrol != 1.0:
		for g in get_tree().get_nodes_in_group("guards"):
			var iv: float = g.get("move_interval") if g.get("move_interval") else 0.40
			g.set("move_interval", iv / heat_patrol)   # smaller interval = faster patrol
			var vr: float = g.get("vision_range") if g.get("vision_range") else 80.0
			g.set("vision_range", vr + heat_bonus * 8.0)
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
		var entry_points := [Vector2(272, 512), Vector2(496, 512), Vector2(384, 512)]
		var ep: Vector2 = entry_points[_rng.randi() % entry_points.size()]
		_prowler(_j(ep), [_j(Vector2(256,512)), _j(Vector2(512,512))])
	# Wanted 4+: spawn an extra hound
	if wl >= 4:
		_hound(_j(Vector2(384, 500)), [_j(Vector2(256,500)), _j(Vector2(512,500))])
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
	for tp in [Vector2(256,20), Vector2(384,20), Vector2(512,20),
			   Vector2(144,132), Vector2(456,132), Vector2(680,132),
			   Vector2(160,308), Vector2(600,308),
			   Vector2(384,468), Vector2(256,556), Vector2(512,556)]:
		var tn := Node2D.new()
		tn.set_script(_torch_script)
		tn.position = tp
		add_child(tn)

	# Barrel hiding-spots — tucked in room corners
	for hp in [Vector2( 64, 432), Vector2(272, 432),   # Barracks
			   Vector2(480, 432), Vector2(704, 432)]:   # Storeroom
		var hs := Node2D.new()
		hs.set_script(_hiding_script)
		hs.position = hp
		add_child(hs)

	# Curtain hiding-spots — vault alcoves and mid-room passages
	for cp in [Vector2(200, 72), Vector2(544, 72),      # Vault sides
			   Vector2( 64, 256), Vector2(480, 256)]:   # Captain / Antechamber south
		_curtain(cp)

# ── Floor 1A ──────────────────────────────────────────────────────────────────
func _setup_floor1():
	var vr := 100.0; var va := 80.0

	# Entry Foyer — sentry sweeps width + checks both corridor mouths; hound patrols a loop
	_guard(_j(Vector2(384, 516)), [
		_j(Vector2(224,516)), _j(Vector2(224,492)), _j(Vector2(272,484)),
		_j(Vector2(496,484)), _j(Vector2(560,492)), _j(Vector2(560,516))],
		"SENTRY", 75.0, 55.0, 0.42)
	_hound(Vector2(384, 500), [_j(Vector2(272,496)), _j(Vector2(384,492)), _j(Vector2(496,496))])

	# Captain's Office — captain patrols room loop + peeks toward vault
	var cap := _guard(_j(Vector2(144, 200)),
		[_j(Vector2(48,160)), _j(Vector2(192,144)), _j(Vector2(240,160)),
		 _j(Vector2(240,240)), _j(Vector2(48,240))],
		"CAPTAIN", 130.0, 100.0, 0.32)
	cap.set("is_captain", true)
	cap.set("key_id", 1)
	# Watcher sweeps office south wall + dips into barracks passage
	_guard(_j(Vector2(80, 200)), [
		_j(Vector2(32,148)), _j(Vector2(240,148)), _j(Vector2(240,272)),
		_j(Vector2(136,320)), _j(Vector2(32,272))],
		"WATCHER", 95.0, 85.0, 0.88)

	# Antechamber — sentry patrols the full antechamber width
	_guard(_j(Vector2(408, 200)), [
		_j(Vector2(320,148)), _j(Vector2(496,148)), _j(Vector2(500,260)),
		_j(Vector2(320,260))],
		"SENTRY", vr, va, 0.40)

	# Barracks — foot soldier sweeps full room + checks entry corridor mouth
	_guard(_j(Vector2(160, 376)), [
		_j(Vector2(48,320)), _j(Vector2(272,320)), _j(Vector2(256,432)),
		_j(Vector2(256,464)), _j(Vector2(48,432))],
		"SENTRY", vr, va, 0.40)

	# Storeroom — goblin sweeps full storeroom + checks entry corridor mouth
	_goblin(_j(Vector2(600, 376)), [
		_j(Vector2(480,320)), _j(Vector2(720,320)), _j(Vector2(720,432)),
		_j(Vector2(496,464)), _j(Vector2(480,432))])

	if _surge() or _escalated(2):
		_guard(_j(Vector2(160, 420)), [_j(Vector2(48,420)), _j(Vector2(272,420))],
			"PATROL", 75.0, 60.0, 0.40)
	if _bounty() or _escalated(3):
		_hound(_j(Vector2(600, 400)), [_j(Vector2(480,400)), _j(Vector2(720,400))])
	if _sentinel_comp():
		_sentinel(Vector2(456, 168))

	# Vault — watcher sweeps west half, sentry sweeps full width in a slow loop
	_guard(_j(Vector2(224, 56)), [
		_j(Vector2(144,32)), _j(Vector2(320,32)), _j(Vector2(320,80)), _j(Vector2(144,80))],
		"WATCHER", vr, va, 0.88)
	_guard(_j(Vector2(384, 56)), [
		_j(Vector2(144,56)), _j(Vector2(608,56)), _j(Vector2(608,80)), _j(Vector2(144,80))],
		"SENTRY", vr, va, 0.40)
	# Armory guard loops the armory room
	_guard(_j(Vector2(680, 200)), [
		_j(Vector2(640,160)), _j(Vector2(720,160)), _j(Vector2(720,240)), _j(Vector2(640,240))],
		"WATCHER", 90.0, 80.0, 0.85)

	_loot(Vector2(224, 48), 200, true)
	_loot(Vector2(384, 40), 400)
	_loot(Vector2(576, 48), 650, false, 1)

	_trap(Vector2(160, 192))
	_glass(Vector2(456, 232))
	_oil(Vector2(160, 432))
	_pickup(Vector2(384, 544), 0)
	_pickup(Vector2(224, 56), 1)
	var _wdrops1 := GameManager.get_floor_weapon_drops(1)
	if _wdrops1.size() >= 1:
		_spawn_weapon_pickup(_wdrops1[0], Vector2(144, 292))  # cap→barracks corridor

# ── Floor 1B ──────────────────────────────────────────────────────────────────
func _setup_floor1b():
	var vr := 90.0; var va := 75.0

	# Entry — sentry checks both corridor mouths; hounds patrol opposite halves
	_guard(_j(Vector2(384, 512)), [
		_j(Vector2(256,480)), _j(Vector2(304,464)), _j(Vector2(496,464)), _j(Vector2(512,480))],
		"SENTRY", 75.0, 55.0, 0.44)
	_hound(Vector2(304, 500), [_j(Vector2(256,496)), _j(Vector2(384,464))])
	_hound(Vector2(464, 500), [_j(Vector2(384,464)), _j(Vector2(512,496))])

	# Captain's Office — captain room loop + vault peek
	var cap := _guard(_j(Vector2(144, 200)),
		[_j(Vector2(48,160)), _j(Vector2(192,144)), _j(Vector2(240,160)), _j(Vector2(240,240)), _j(Vector2(48,240))],
		"CAPTAIN", 130.0, 100.0, 0.30)
	cap.set("is_captain", true)
	cap.set("key_id", 1)
	_guard(_j(Vector2(80, 168)), [
		_j(Vector2(32,160)), _j(Vector2(240,160)), _j(Vector2(256,304)), _j(Vector2(32,304))],
		"WATCHER", 95.0, 85.0, 0.88)
	_guard(_j(Vector2(224, 240)), [_j(Vector2(48,240)), _j(Vector2(240,160)), _j(Vector2(48,160))],
		"WATCHER", 95.0, 85.0, 0.88)

	# Antechamber — sweeps room + storeroom corridor mouth
	_guard(_j(Vector2(456, 200)), [
		_j(Vector2(336,160)), _j(Vector2(576,160)), _j(Vector2(576,248)),
		_j(Vector2(480,304)), _j(Vector2(336,248))],
		"SENTRY", vr, va, 0.40)

	# Barracks / Storeroom — full room sweeps + corridor checks
	_guard(_j(Vector2(160, 376)), [
		_j(Vector2(48,320)), _j(Vector2(272,320)), _j(Vector2(256,432)),
		_j(Vector2(256,464)), _j(Vector2(48,432))],
		"SENTRY", vr, va, 0.40)
	_guard(_j(Vector2(600, 376)), [
		_j(Vector2(480,320)), _j(Vector2(720,320)), _j(Vector2(720,432)),
		_j(Vector2(496,464)), _j(Vector2(480,432))],
		"SENTRY", vr, va, 0.40)

	if _surge() or _escalated(2):
		_guard(_j(Vector2(160, 420)), [_j(Vector2(48,420)), _j(Vector2(272,420))],
			"SENTRY", vr, va, 0.40)
	if _bounty() or _escalated(3):
		_hound(_j(Vector2(600, 400)), [_j(Vector2(480,400)), _j(Vector2(720,400))])
	if _sentinel_comp():
		_sentinel(Vector2(456, 168))

	# Vault
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))],
		"WATCHER", vr, va, 0.85)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(256,56)), _j(Vector2(512,56))],
		"SENTRY", vr, va, 0.40)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))],
		"WATCHER", 90.0, 80.0, 0.82)

	_loot(Vector2(256, 72), 200, true)
	_loot(Vector2(384, 40), 400)
	_loot(Vector2(320, 72), 200, true)
	_loot(Vector2(576, 48), 600, false, 1)

	_trap(Vector2(80, 184))
	_trap(Vector2(224, 256))
	_glass(Vector2(456, 232))
	_oil(Vector2(384, 540))
	_pickup(Vector2(256, 544), 0)
	_pickup(Vector2(448, 56), 1)
	var _wdrops1b := GameManager.get_floor_weapon_drops(1)
	if _wdrops1b.size() >= 1:
		_spawn_weapon_pickup(_wdrops1b[0], Vector2(592, 292))  # storeroom→antechamber corridor

# ── Floor 2A ──────────────────────────────────────────────────────────────────
func _setup_floor2():
	var vr := 110.0; var va := 90.0

	# Entry — two sentries cover different halves, hound does a loop
	_guard(_j(Vector2(320, 512)), [
		_j(Vector2(256,480)), _j(Vector2(304,464)), _j(Vector2(384,512)), _j(Vector2(384,480))],
		"SENTRY", 80.0, 60.0, 0.40)
	_guard(_j(Vector2(448, 512)), [
		_j(Vector2(496,464)), _j(Vector2(512,480)), _j(Vector2(384,480)), _j(Vector2(384,512))],
		"SENTRY", 80.0, 65.0, 0.40)
	_hound(Vector2(384, 496), [
		_j(Vector2(256,480)), _j(Vector2(304,464)), _j(Vector2(496,464)), _j(Vector2(512,480))])

	# Captain's Office — captain loops room + vault peek
	var cap := _guard(_j(Vector2(144, 200)),
		[_j(Vector2(48,160)), _j(Vector2(192,144)), _j(Vector2(240,160)),
		 _j(Vector2(240,240)), _j(Vector2(48,240))],
		"CAPTAIN", 140.0, 110.0, 0.28)
	cap.set("is_captain", true)
	cap.set("key_id", 1)
	_guard(_j(Vector2(80, 168)), [
		_j(Vector2(32,160)), _j(Vector2(240,160)), _j(Vector2(256,304)), _j(Vector2(32,304))],
		"WATCHER", vr, va, 0.80)
	_guard(_j(Vector2(224, 168)), [
		_j(Vector2(48,160)), _j(Vector2(240,160)), _j(Vector2(240,240)), _j(Vector2(48,240))],
		"SENTRY", 85.0, 65.0, 0.40)
	_gnoll(_j(Vector2(80, 232)), [
		_j(Vector2(32,200)), _j(Vector2(256,304)), _j(Vector2(256,200))])

	# Antechamber — sweeps room + both corridor mouths
	_guard(_j(Vector2(456, 200)), [
		_j(Vector2(336,160)), _j(Vector2(576,160)), _j(Vector2(576,248)),
		_j(Vector2(480,304)), _j(Vector2(336,248))],
		"WATCHER", vr, va, 0.80)
	_hound(Vector2(160, 400), [
		_j(Vector2(48,368)), _j(Vector2(272,368)), _j(Vector2(256,464))])

	# Barracks / Storeroom — full room loops
	_guard(_j(Vector2(160, 344)), [
		_j(Vector2(48,320)), _j(Vector2(272,320)), _j(Vector2(256,432)),
		_j(Vector2(256,464)), _j(Vector2(48,432))],
		"SENTRY", vr, va, 0.40)
	_skeleton(_j(Vector2(600, 376)), [
		_j(Vector2(480,320)), _j(Vector2(720,320)), _j(Vector2(720,432)),
		_j(Vector2(496,464)), _j(Vector2(480,432))])

	if _surge() or _escalated(2):
		_guard(_j(Vector2(160, 420)), [_j(Vector2(48,420)), _j(Vector2(272,420))],
			"PATROL", 80.0, 60.0, 0.38)
	if _bounty() or _escalated(4):
		_hound(_j(Vector2(600, 400)), [_j(Vector2(480,400)), _j(Vector2(720,400))])
	if _sentinel_comp():
		_sentinel(Vector2(456, 168))

	# Vault — three guards
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))],
		"WATCHER", vr, va, 0.80)
	_guard(_j(Vector2(320, 56)), [_j(Vector2(192,32)), _j(Vector2(448,56))],
		"SENTRY", vr, va, 0.40)
	_guard(_j(Vector2(464, 72)), [_j(Vector2(256,72)), _j(Vector2(512,32))],
		"SENTRY", vr, va, 0.40)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))],
		"WATCHER", 95.0, 80.0, 0.78)

	_loot(Vector2(224, 48), 300, true)
	_loot(Vector2(384, 40), 500, false, 1)
	_loot(Vector2(320, 72), 250, true)
	_loot(Vector2(576, 48), 800, false, 2)
	_loot(Vector2(544, 72), 400, true)

	_trap(Vector2(80, 184))
	_trap(Vector2(456, 168))
	_ward(Vector2(144, 232))
	_glass(Vector2(456, 216))
	_glass(Vector2(80, 168))
	_oil(Vector2(600, 400))
	_civilian(Vector2(456, 200), [Vector2(336, 200), Vector2(576, 200)])
	_pickup(Vector2(512, 544), 0)
	_pickup(Vector2(224, 56), 1)
	_pickup(Vector2(600, 376), 2)
	var _wdrops2 := GameManager.get_floor_weapon_drops(2)
	if _wdrops2.size() >= 1:
		_spawn_weapon_pickup(_wdrops2[0], Vector2(144, 292))
	if _wdrops2.size() >= 2:
		_spawn_weapon_pickup(_wdrops2[1], Vector2(592, 292))

# ── Floor 2B ──────────────────────────────────────────────────────────────────
func _setup_floor2b():
	var vr := 105.0; var va := 50.0

	# Entry — double hound
	_guard(_j(Vector2(384, 512)), [_j(Vector2(256,512)), _j(Vector2(512,512))],
		"SENTRY", 80.0, 60.0, 0.42)
	_hound(Vector2(320, 496), [_j(Vector2(256,496)), _j(Vector2(384,496))])
	_hound(Vector2(448, 496), [_j(Vector2(384,496)), _j(Vector2(512,496))])

	# Captain's Office — captain + prowlers
	var cap := _guard(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168))],
		"CAPTAIN", 140.0, 110.0, 0.28)
	cap.set("is_captain", true)
	cap.set("key_id", 1)
	_prowler(_j(Vector2(80, 216)),
		[_j(Vector2(32,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(32,248))])
	_guard(_j(Vector2(80, 168)), [_j(Vector2(32,148)), _j(Vector2(80,256))],
		"WATCHER", vr, 90.0, 0.85)

	# Antechamber — prowler
	_prowler(_j(Vector2(456, 216)),
		[_j(Vector2(336,168)), _j(Vector2(576,168)), _j(Vector2(576,248)), _j(Vector2(336,248))])

	# Barracks / Storeroom
	_skeleton(_j(Vector2(600, 376)), [_j(Vector2(480,344)), _j(Vector2(600,432))])
	_goblin(_j(Vector2(160, 376)), [_j(Vector2(48,344)), _j(Vector2(160,432))])

	if _surge() or _escalated(2):
		_prowler(_j(Vector2(160, 420)), [_j(Vector2(48,420)), _j(Vector2(272,420))])
	if _bounty() or _escalated(4):
		_hound(_j(Vector2(600, 400)), [_j(Vector2(480,400)), _j(Vector2(720,400))])
	if _sentinel_comp():
		_sentinel(Vector2(456, 168))

	# Vault
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))],
		"WATCHER", vr, va, 0.88)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(256,56)), _j(Vector2(480,56))],
		"SENTRY", vr, va, 0.40)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))],
		"WATCHER", 95.0, 80.0, 0.80)

	_loot(Vector2(240, 72), 300, true)
	_loot(Vector2(384, 40), 500, false, 1)
	_loot(Vector2(464, 80), 250, true)
	_loot(Vector2(576, 48), 750, false, 2)

	_trap(Vector2(80, 232))
	_trap(Vector2(600, 376))
	_ward(Vector2(456, 168))
	_glass(Vector2(456, 216))
	_oil(Vector2(160, 432))
	var _wdrops2b := GameManager.get_floor_weapon_drops(2)
	if _wdrops2b.size() > 0: _spawn_weapon_pickup(_wdrops2b[0], Vector2(592, 292))
	if _wdrops2b.size() > 1: _spawn_weapon_pickup(_wdrops2b[1], Vector2(144, 292))
	_pickup(Vector2(256, 544), 0)
	_pickup(Vector2(480, 56), 2)
	_pickup(Vector2(720, 376), 1)

# ── Floor 3A ──────────────────────────────────────────────────────────────────
func _setup_floor3():
	var vr := 120.0; var va := 100.0

	# Entry — double sentry + hound
	_guard(_j(Vector2(320, 512)), [_j(Vector2(256,512)), _j(Vector2(384,512))],
		"SENTRY", 85.0, 65.0, 0.38)
	_guard(_j(Vector2(448, 512)), [_j(Vector2(384,512)), _j(Vector2(512,512))],
		"SENTRY", 85.0, 65.0, 0.38)
	_guard(_j(Vector2(272, 512)), [_j(Vector2(240,480)), _j(Vector2(272,544))],
		"SENTRY", 85.0, 65.0, 0.38)
	_hound(Vector2(384, 496), [_j(Vector2(256,496)), _j(Vector2(512,496))])

	# Captain's Office — BOSS holds vault key
	_boss(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_guard(_j(Vector2(80, 168)),  [_j(Vector2(32,148)), _j(Vector2(80,256))], "WATCHER", vr, va, 0.70)
	_guard(_j(Vector2(224, 240)), [_j(Vector2(48,240)), _j(Vector2(240,248))], "SENTRY", 90.0, 70.0, 0.35)
	_prowler(_j(Vector2(144, 216)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_hound(Vector2(80, 216), [_j(Vector2(32,200)), _j(Vector2(240,200))])
	_skeleton(_j(Vector2(80, 248)), [_j(Vector2(32,200)), _j(Vector2(80,256))])
	_gnoll(_j(Vector2(224, 168)), [_j(Vector2(144,168)), _j(Vector2(240,168))])

	# Antechamber
	_guard(_j(Vector2(456, 168)), [_j(Vector2(336,168)), _j(Vector2(576,168))],
		"SENTRY", 90.0, 70.0, 0.35)
	_guard(_j(Vector2(456, 248)), [_j(Vector2(336,248)), _j(Vector2(576,248))],
		"SENTRY", 90.0, 70.0, 0.35)
	_goblin(_j(Vector2(336, 200)), [_j(Vector2(336,168)), _j(Vector2(336,248))])
	_hound(Vector2(576, 200), [_j(Vector2(336,200)), _j(Vector2(576,200))])

	# Barracks / Storeroom
	_guard(_j(Vector2(160, 344)), [_j(Vector2(48,344)), _j(Vector2(272,344))],
		"SENTRY", vr, va, 0.40)
	_guard(_j(Vector2(600, 344)), [_j(Vector2(480,344)), _j(Vector2(720,344))],
		"SENTRY", vr, va, 0.40)

	if _surge() or _escalated(2):
		_prowler(_j(Vector2(600, 400)), [_j(Vector2(480,376)), _j(Vector2(720,376))])
	if _bounty() or _escalated(5):
		_hound(_j(Vector2(160, 400)), [_j(Vector2(48,400)), _j(Vector2(272,400))])
	if _sentinel_comp() or _escalated(4):
		_sentinel(Vector2(456, 168))
	if _escalated(3):
		_gnoll(_j(Vector2(456, 216)), [_j(Vector2(336,200)), _j(Vector2(576,200))])

	# Vault
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))], "WATCHER", vr, va, 0.70)
	_guard(_j(Vector2(320, 56)), [_j(Vector2(192,32)), _j(Vector2(480,32))], "SENTRY", vr, va, 0.35)
	_guard(_j(Vector2(464, 72)), [_j(Vector2(256,72)), _j(Vector2(512,32))], "SENTRY", vr, va, 0.35)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", 100.0, 85.0, 0.72)
	_guard(_j(Vector2(680, 240)), [_j(Vector2(640,200)), _j(Vector2(720,256))], "SENTRY", 90.0, 70.0, 0.35)

	_loot(Vector2(192, 56), 400, true, 1)
	_loot(Vector2(384, 40), 700, false, 1)
	_loot(Vector2(320, 72), 400, true)
	_loot(Vector2(576, 40), 1000, false, 2)
	_loot(Vector2(544, 72), 500, true, 1)

	_trap(Vector2(80, 184))
	_trap(Vector2(456, 184))
	_trap(Vector2(144, 248))
	_trap(Vector2(80, 248))
	_ward(Vector2(80, 216))
	_ward(Vector2(456, 216))
	_ward(Vector2(456, 168))
	_glass(Vector2(456, 232))
	_glass(Vector2(80, 168))
	_oil(Vector2(600, 432))
	_civilian(Vector2(456, 200), [Vector2(336, 200), Vector2(576, 200)])
	_civilian(Vector2(384, 512), [Vector2(256, 512), Vector2(512, 512)])
	_pickup(Vector2(512, 544), 0)
	_pickup(Vector2(192, 56), 1)
	_pickup(Vector2(600, 376), 2)
	_pickup(Vector2(720, 376), 2)
	var _wdrops3 := GameManager.get_floor_weapon_drops(3)
	if _wdrops3.size() >= 1:
		_spawn_weapon_pickup(_wdrops3[0], Vector2(144, 292))
	if _wdrops3.size() >= 2:
		_spawn_weapon_pickup(_wdrops3[1], Vector2(592, 292))
	# Alarm bells — vault corridor and entry checkpoint
	_bell(Vector2(320, 112))   # vault corridor mouth
	_bell(Vector2(448, 480))   # entry checkpoint

# ── Floor 3B ──────────────────────────────────────────────────────────────────
func _setup_floor3b():
	# Entry — two hounds + sentry
	_guard(_j(Vector2(384, 512)), [_j(Vector2(256,512)), _j(Vector2(512,512))],
		"SENTRY", 90.0, 70.0, 0.36)
	_hound(Vector2(304, 496), [_j(Vector2(256,480)), _j(Vector2(384,480))])
	_hound(Vector2(464, 496), [_j(Vector2(384,480)), _j(Vector2(512,480))])
	_guard(_j(Vector2(256, 512)), [_j(Vector2(240,480)), _j(Vector2(256,544))],
		"SENTRY", 85.0, 65.0, 0.40)

	# Captain's Office — BOSS with sentinel web
	_boss(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_sentinel(Vector2(32,  168))
	_sentinel(Vector2(240, 168))
	_sentinel(Vector2(32,  248))
	_sentinel(Vector2(240, 248))
	_prowler(_j(Vector2(144, 216)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_hound(Vector2(80, 200), [_j(Vector2(32,200)), _j(Vector2(240,200))])
	_hound(Vector2(80, 232), [_j(Vector2(32,216)), _j(Vector2(240,216))])

	# Antechamber — prowler + sentinels
	_prowler(_j(Vector2(456, 216)),
		[_j(Vector2(336,168)), _j(Vector2(576,168)), _j(Vector2(576,248)), _j(Vector2(336,248))])
	_sentinel(Vector2(336, 168))
	_sentinel(Vector2(576, 168))

	if _surge() or _escalated(2):
		_sentinel(Vector2(144, 168))
	if _bounty() or _escalated(5):
		_hound(_j(Vector2(144, 200)), [_j(Vector2(32,200)), _j(Vector2(240,200))])
	if _sentinel_comp() or _escalated(4):
		_sentinel(Vector2(456, 216))

	_gnoll(_j(Vector2(80, 216)),     [_j(Vector2(32,200)), _j(Vector2(144,216))])
	_skeleton(_j(Vector2(576, 216)), [_j(Vector2(456,216)), _j(Vector2(576,200))])

	# Barracks / Storeroom
	_guard(_j(Vector2(160, 376)), [_j(Vector2(48,344)), _j(Vector2(272,344))],
		"SENTRY", 115.0, 95.0, 0.40)
	_guard(_j(Vector2(600, 376)), [_j(Vector2(480,344)), _j(Vector2(720,344))],
		"SENTRY", 115.0, 95.0, 0.40)

	# Vault
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))], "WATCHER", 115.0, 95.0, 0.70)
	_guard(_j(Vector2(320, 56)), [_j(Vector2(192,32)), _j(Vector2(480,32))], "SENTRY", 115.0, 95.0, 0.35)
	_guard(_j(Vector2(464, 72)), [_j(Vector2(256,72)), _j(Vector2(512,32))], "SENTRY", 115.0, 95.0, 0.35)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", 100.0, 85.0, 0.68)

	_loot(Vector2(192, 56), 400, true, 1)
	_loot(Vector2(352, 40), 350, true)
	_loot(Vector2(384, 40), 800, false, 2)
	_loot(Vector2(320, 72), 450, true)
	_loot(Vector2(576, 40), 1100, false, 2)
	_loot(Vector2(544, 72), 600, true, 1)

	_trap(Vector2(80, 184))
	_trap(Vector2(600, 184))
	_trap(Vector2(80, 248))
	_trap(Vector2(600, 248))
	_trap(Vector2(456, 168))
	_ward(Vector2(144, 216))
	_ward(Vector2(456, 216))

	var _wdrops3b := GameManager.get_floor_weapon_drops(3)
	if _wdrops3b.size() > 0: _spawn_weapon_pickup(_wdrops3b[0], Vector2(592, 292))
	if _wdrops3b.size() > 1: _spawn_weapon_pickup(_wdrops3b[1], Vector2(144, 292))
	_pickup(Vector2(512, 544), 0)
	_pickup(Vector2(192, 56), 2)
	_pickup(Vector2(720, 376), 1)
	_pickup(Vector2(256, 544), 2)

# ── Floor 1C — Skeleton Watch ─────────────────────────────────────────────────
func _setup_floor1c():
	# Entry — skeleton guards replace humans
	_skeleton(_j(Vector2(320, 512)), [_j(Vector2(256,512)), _j(Vector2(384,512))])
	_skeleton(_j(Vector2(448, 512)), [_j(Vector2(384,496)), _j(Vector2(512,512))])
	_hound(Vector2(384, 496), [_j(Vector2(256,496)), _j(Vector2(512,496))])

	# Captain's Office — captain holds key
	var cap := _guard(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168))],
		"CAPTAIN", 120.0, 95.0, 0.32)
	cap.set("is_captain", true); cap.set("key_id", 1)
	_skeleton(_j(Vector2(80, 168)),  [_j(Vector2(32,148)),  _j(Vector2(80,256))])
	_skeleton(_j(Vector2(224, 168)), [_j(Vector2(144,168)), _j(Vector2(240,248))])
	_goblin(_j(Vector2(160, 232)), [_j(Vector2(48,232)), _j(Vector2(240,232))])

	if _surge(): _skeleton(_j(Vector2(160, 200)), [_j(Vector2(48,200)), _j(Vector2(240,200))])

	# Antechamber / Armory
	_guard(_j(Vector2(456, 200)), [_j(Vector2(336,168)), _j(Vector2(576,168))], "SENTRY", 95.0, 75.0, 0.42)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", 90.0, 80.0, 0.85)

	# Vault
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))], "WATCHER", 90.0, 80.0, 0.88)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(256,56)), _j(Vector2(512,56))], "SENTRY", 95.0, 75.0, 0.42)
	_loot(Vector2(224, 48), 200, true)
	_loot(Vector2(384, 40), 400)
	_loot(Vector2(576, 48), 600, false, 1)
	_trap(Vector2(80, 232)); _trap(Vector2(600, 232))
	_ward(Vector2(456, 200))
	var _wdrops1c := GameManager.get_floor_weapon_drops(1)
	if _wdrops1c.size() > 0: _spawn_weapon_pickup(_wdrops1c[0], Vector2(592, 292))
	_pickup(Vector2(512, 544), 1); _pickup(Vector2(224, 56), 2)

# ── Floor 2C — Gnoll Barracks ─────────────────────────────────────────────────
func _setup_floor2c():
	var vr := 100.0; var va := 80.0
	# Entry — gnolls + heavier patrol
	_gnoll(_j(Vector2(320, 512)), [_j(Vector2(256,512)), _j(Vector2(384,512))])
	_gnoll(_j(Vector2(448, 512)), [_j(Vector2(384,496)), _j(Vector2(512,512))])
	_guard(_j(Vector2(384, 540)), [_j(Vector2(256,540)), _j(Vector2(512,540))],
		"SENTRY", 80.0, 60.0, 0.42)

	# Captain's Office — captain holds key
	var cap := _guard(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))],
		"CAPTAIN", 130.0, 100.0, 0.30)
	cap.set("is_captain", true); cap.set("key_id", 1)
	_gnoll(_j(Vector2(80, 200)),  [_j(Vector2(32,168)), _j(Vector2(144,200))])
	_gnoll(_j(Vector2(224, 200)), [_j(Vector2(144,200)), _j(Vector2(240,168))])
	_guard(_j(Vector2(80, 168)),  [_j(Vector2(32,148)), _j(Vector2(80,256))], "WATCHER", vr, va, 0.88)
	_guard(_j(Vector2(224, 248)), [_j(Vector2(80,248)), _j(Vector2(240,248))], "WATCHER", vr, va, 0.88)

	if _surge():   _gnoll(_j(Vector2(160, 232)), [_j(Vector2(48,232)), _j(Vector2(240,232))])
	if _bounty():  _hound(_j(Vector2(80, 216)),  [_j(Vector2(32,200)), _j(Vector2(240,200))])
	if _sentinel_comp(): _sentinel(Vector2(456, 168))

	_civilian(Vector2(456, 200), [Vector2(336, 200), Vector2(576, 200)])

	# Antechamber / Armory
	_guard(_j(Vector2(456, 200)), [_j(Vector2(336,168)), _j(Vector2(576,168))], "SENTRY", vr, va, 0.42)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", 95.0, 85.0, 0.82)

	# Vault
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))], "WATCHER", vr, va, 0.88)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(256,56)), _j(Vector2(512,56))], "SENTRY", vr, va, 0.42)
	_loot(Vector2(256, 72), 250, true)
	_loot(Vector2(384, 40), 500)
	_loot(Vector2(576, 48), 700, false, 1)
	_trap(Vector2(80, 200)); _trap(Vector2(456, 200))
	_glass(Vector2(456, 232)); _oil(Vector2(160, 432))
	var _wdrops2c := GameManager.get_floor_weapon_drops(2)
	if _wdrops2c.size() > 0: _spawn_weapon_pickup(_wdrops2c[0], Vector2(592, 292))
	if _wdrops2c.size() > 1: _spawn_weapon_pickup(_wdrops2c[1], Vector2(144, 292))
	_pickup(Vector2(512, 544), 0); _pickup(Vector2(224, 56), 2)

# ── Floor 3C — The Chancellor's Vault ─────────────────────────────────────────
func _setup_floor3c():
	# Entry — prowlers and hounds, no regular guards
	_prowler(_j(Vector2(320, 512)), [_j(Vector2(256,512)), _j(Vector2(384,512))])
	_prowler(_j(Vector2(448, 512)), [_j(Vector2(384,480)), _j(Vector2(512,512))])
	_hound(Vector2(384, 496), [_j(Vector2(256,496)), _j(Vector2(512,496))])
	_hound(Vector2(304, 512), [_j(Vector2(256,480)), _j(Vector2(384,480))])

	# Captain's Office — BOSS + prowler web
	_boss(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_prowler(_j(Vector2(80, 184)),  [_j(Vector2(32,168)), _j(Vector2(144,200))])
	_prowler(_j(Vector2(224, 232)), [_j(Vector2(144,200)), _j(Vector2(240,248))])
	_sentinel(Vector2(32,  168)); _sentinel(Vector2(240, 168))
	_hound(Vector2(80, 232), [_j(Vector2(32,232)), _j(Vector2(240,232))])

	# Antechamber
	_guard(_j(Vector2(456, 200)), [_j(Vector2(336,168)), _j(Vector2(576,168))], "SENTRY", 110.0, 90.0, 0.36)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", 100.0, 85.0, 0.70)

	if _surge():   _prowler(_j(Vector2(160, 216)), [_j(Vector2(32,200)), _j(Vector2(240,200))])
	if _bounty():  _hound(_j(Vector2(144, 216)), [_j(Vector2(32,216)), _j(Vector2(240,216))])

	_gnoll(_j(Vector2(80, 248)),     [_j(Vector2(32,232)), _j(Vector2(144,248))])
	_skeleton(_j(Vector2(576, 216)), [_j(Vector2(456,216)), _j(Vector2(576,248))])

	# Vault — three guards
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))], "WATCHER", 115.0, 95.0, 0.72)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(192,32)), _j(Vector2(480,32))], "SENTRY", 110.0, 90.0, 0.36)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", 100.0, 85.0, 0.70)

	_loot(Vector2(192, 56), 450, true, 1)
	_loot(Vector2(384, 40), 850, false, 2)
	_loot(Vector2(576, 40), 1200, false, 2)
	_trap(Vector2(80, 184)); _trap(Vector2(600, 184))
	_trap(Vector2(80, 248)); _trap(Vector2(600, 248))
	_ward(Vector2(144, 216)); _ward(Vector2(456, 216))
	var _wdrops3c := GameManager.get_floor_weapon_drops(3)
	if _wdrops3c.size() > 0: _spawn_weapon_pickup(_wdrops3c[0], Vector2(592, 292))
	if _wdrops3c.size() > 1: _spawn_weapon_pickup(_wdrops3c[1], Vector2(144, 292))
	_pickup(Vector2(512, 544), 0); _pickup(Vector2(192, 56), 1)
	_pickup(Vector2(720, 376), 2); _pickup(Vector2(256, 544), 1)

# ── Floor 4A — The Inner Sanctum ─────────────────────────────────────────────
func _setup_floor4():
	var vr := 130.0; var va := 110.0

	# Entry — two wardens + gnoll patrol
	_guard(_j(Vector2(320, 512)), [_j(Vector2(256,512)), _j(Vector2(384,512))],
		"WARDEN", vr, va, 0.32)
	_guard(_j(Vector2(448, 512)), [_j(Vector2(384,512)), _j(Vector2(512,512))],
		"WARDEN", vr, va, 0.32)
	_hound(Vector2(384, 496), [_j(Vector2(256,496)), _j(Vector2(512,496))])
	_hound(Vector2(304, 512), [_j(Vector2(256,480)), _j(Vector2(384,480))])
	_gnoll(_j(Vector2(384, 540)), [_j(Vector2(256,540)), _j(Vector2(512,540))])

	# Captain's Office — BOSS + prowlers
	_boss(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_prowler(_j(Vector2(80, 184)),  [_j(Vector2(32,168)), _j(Vector2(144,200))])
	_prowler(_j(Vector2(224, 232)), [_j(Vector2(144,200)), _j(Vector2(240,248))])
	_guard(_j(Vector2(80, 168)),  [_j(Vector2(32,148)), _j(Vector2(80,256))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(224, 168)), [_j(Vector2(144,168)), _j(Vector2(240,248))], "WARDEN", vr, va, 0.70)
	_skeleton(_j(Vector2(80, 248)),  [_j(Vector2(32,216)), _j(Vector2(144,248))])
	_skeleton(_j(Vector2(224, 248)), [_j(Vector2(144,248)), _j(Vector2(240,248))])
	_gnoll(_j(Vector2(144, 216)), [_j(Vector2(32,200)), _j(Vector2(144,200))])

	# Antechamber
	_guard(_j(Vector2(456, 168)), [_j(Vector2(336,168)), _j(Vector2(576,168))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(456, 248)), [_j(Vector2(336,248)), _j(Vector2(576,248))], "WARDEN", vr, va, 0.35)

	if _surge() or _escalated(2): _prowler(_j(Vector2(456, 200)), [_j(Vector2(336,200)), _j(Vector2(576,200))])
	if _bounty() or _escalated(4): _hound(_j(Vector2(456, 216)), [_j(Vector2(336,216)), _j(Vector2(576,216))])
	if GameManager._lockdown_incoming:
		_sentinel(Vector2(144, 168))
		_sentinel(Vector2(144, 248))

	# Vault zone
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))], "WATCHER", vr, va, 0.70)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(192,32)), _j(Vector2(480,32))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", vr, va, 0.70)
	_loot(Vector2(192, 48), 600, true, 1)
	_loot(Vector2(384, 40), 1000, false, 2)
	_loot(Vector2(576, 48), 800, true, 2)

	_trap(Vector2(80, 184)); _trap(Vector2(456, 168)); _trap(Vector2(144, 248))
	_trap(Vector2(80, 248)); _trap(Vector2(600, 248))
	_ward(Vector2(144, 216)); _ward(Vector2(456, 216))
	_ward(Vector2(80, 248)); _ward(Vector2(224, 248))
	_glass(Vector2(144, 200)); _glass(Vector2(80, 216)); _glass(Vector2(224, 216))
	_oil(Vector2(32, 248)); _oil(Vector2(576, 248))
	_civilian(Vector2(456, 376), [Vector2(336, 376), Vector2(576, 376)])
	_pickup(Vector2(512, 544), 1); _pickup(Vector2(192, 56), 2)
	_pickup(Vector2(600, 376), 2); _pickup(Vector2(720, 376), 1)
	var _wdrops4 := GameManager.get_floor_weapon_drops(4)
	if _wdrops4.size() >= 1:
		_spawn_weapon_pickup(_wdrops4[0], Vector2(144, 292))
	if _wdrops4.size() >= 2:
		_spawn_weapon_pickup(_wdrops4[1], Vector2(592, 292))
	# Three alarm bells — vault, corridor split, entry arch
	_bell(Vector2(320, 112))
	_bell(Vector2(352, 272))
	_bell(Vector2(384, 480))

# ── Floor 4B ──────────────────────────────────────────────────────────────────
func _setup_floor4b():
	var vr := 130.0; var va := 110.0

	# Entry — skeleton sentries + gnoll patrol
	_skeleton(_j(Vector2(320, 512)), [_j(Vector2(256,512)), _j(Vector2(384,512))])
	_skeleton(_j(Vector2(448, 512)), [_j(Vector2(384,496)), _j(Vector2(512,512))])
	_gnoll(_j(Vector2(384, 540)),    [_j(Vector2(256,540)), _j(Vector2(512,540))])
	_hound(Vector2(304, 496), [_j(Vector2(256,480)), _j(Vector2(384,480))])

	# Captain's Office — two prowlers flanking boss
	_boss(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_prowler(_j(Vector2(80, 184)),  [_j(Vector2(32,168)), _j(Vector2(144,200))])
	_prowler(_j(Vector2(224, 216)), [_j(Vector2(144,200)), _j(Vector2(240,168))])
	_guard(_j(Vector2(32, 200)),  [_j(Vector2(32,160)), _j(Vector2(32,248))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(240, 200)), [_j(Vector2(240,160)), _j(Vector2(240,248))], "WARDEN", vr, va, 0.70)
	_gnoll(_j(Vector2(80, 248)),  [_j(Vector2(32,232)), _j(Vector2(144,248))])
	_gnoll(_j(Vector2(224, 248)), [_j(Vector2(144,248)), _j(Vector2(240,232))])
	_hound(Vector2(144, 232), [_j(Vector2(32,216)), _j(Vector2(240,216))])
	_skeleton(_j(Vector2(80, 200)), [_j(Vector2(32,184)), _j(Vector2(144,200))])
	_skeleton(_j(Vector2(224, 184)), [_j(Vector2(144,184)), _j(Vector2(240,200))])

	if _surge() or _escalated(3): _prowler(_j(Vector2(144, 168)), [_j(Vector2(32,168)), _j(Vector2(240,168))])
	if _bounty() or _escalated(5): _hound(_j(Vector2(144, 200)), [_j(Vector2(32,200)), _j(Vector2(240,200))])
	if GameManager._lockdown_incoming:
		_sentinel(Vector2(144, 168))
		_sentinel(Vector2(80, 248))

	# Antechamber / Vault
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(240,80))], "WATCHER", vr, va, 0.72)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(192,32)), _j(Vector2(480,32))], "WARDEN",  vr, va, 0.35)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", vr, va, 0.70)
	_loot(Vector2(192, 48), 600, true, 1)
	_loot(Vector2(384, 40), 1000, false, 2)
	_loot(Vector2(544, 48), 700, true, 2)

	_trap(Vector2(80, 184)); _trap(Vector2(240, 184))
	_trap(Vector2(80, 248)); _trap(Vector2(240, 248))
	_ward(Vector2(144, 216)); _ward(Vector2(456, 216))
	_ward(Vector2(144, 168)); _ward(Vector2(144, 248))
	_glass(Vector2(80, 216)); _glass(Vector2(224, 216))
	_oil(Vector2(144, 248)); _oil(Vector2(456, 248))
	_civilian(Vector2(456, 376), [Vector2(336, 376), Vector2(576, 376)])
	_civilian(Vector2(304, 512), [_j(Vector2(256,496)), _j(Vector2(384,480))])
	var _wdrops4b := GameManager.get_floor_weapon_drops(4)
	if _wdrops4b.size() > 0: _spawn_weapon_pickup(_wdrops4b[0], Vector2(592, 292))
	if _wdrops4b.size() > 1: _spawn_weapon_pickup(_wdrops4b[1], Vector2(144, 292))
	_pickup(Vector2(720, 376), 2); _pickup(Vector2(32, 376), 1)
	_pickup(Vector2(512, 544), 0); _pickup(Vector2(192, 56), 2)

# ── Floor 4C ──────────────────────────────────────────────────────────────────
func _setup_floor4c():
	var vr := 125.0; var va := 105.0

	# Entry — gnolls and triple hounds; high scent threat
	_gnoll(_j(Vector2(320, 512)), [_j(Vector2(256,512)), _j(Vector2(384,512))])
	_gnoll(_j(Vector2(448, 512)), [_j(Vector2(384,496)), _j(Vector2(512,512))])
	_hound(Vector2(384, 496), [_j(Vector2(256,496)), _j(Vector2(512,496))])
	_hound(Vector2(272, 512), [_j(Vector2(240,480)), _j(Vector2(384,480))])
	_hound(Vector2(496, 512), [_j(Vector2(384,480)), _j(Vector2(512,480))])

	# Captain's Office — BOSS + prowler web
	_boss(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_prowler(_j(Vector2(80, 184)),  [_j(Vector2(32,168)), _j(Vector2(144,200))])
	_prowler(_j(Vector2(224, 232)), [_j(Vector2(144,200)), _j(Vector2(240,248))])
	_guard(_j(Vector2(32, 200)),  [_j(Vector2(32,160)), _j(Vector2(32,248))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(240, 200)), [_j(Vector2(240,160)), _j(Vector2(240,248))], "WARDEN", vr, va, 0.70)
	_skeleton(_j(Vector2(80, 248)),  [_j(Vector2(32,216)), _j(Vector2(144,248))])
	_skeleton(_j(Vector2(224, 248)), [_j(Vector2(144,248)), _j(Vector2(240,232))])
	if _surge() or _escalated(2): _prowler(_j(Vector2(144, 168)), [_j(Vector2(32,168)), _j(Vector2(240,168))])
	if GameManager._lockdown_incoming:
		_sentinel(Vector2(144, 168))
		_sentinel(Vector2(144, 248))

	# Antechamber
	_guard(_j(Vector2(456, 168)), [_j(Vector2(336,168)), _j(Vector2(576,168))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WATCHER", vr, va, 0.70)

	# Vault
	_guard(_j(Vector2(224, 56)), [_j(Vector2(144,32)), _j(Vector2(224,80))], "WATCHER", vr, va, 0.70)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(192,32)), _j(Vector2(480,32))], "WARDEN",  vr, va, 0.35)
	_guard(_j(Vector2(576, 56)), [_j(Vector2(512,32)), _j(Vector2(624,80))], "WATCHER", vr, va, 0.70)
	_loot(Vector2(192, 48), 700, true, 2)
	_loot(Vector2(384, 40), 1100, false, 2)
	_loot(Vector2(576, 48), 900, true, 2)

	_trap(Vector2(80, 184)); _trap(Vector2(456, 168)); _trap(Vector2(144, 248))
	_ward(Vector2(144, 216)); _ward(Vector2(456, 216)); _ward(Vector2(144, 168))
	_glass(Vector2(80, 216)); _glass(Vector2(224, 216)); _glass(Vector2(144, 216))
	_oil(Vector2(144, 248)); _oil(Vector2(456, 248))
	_civilian(Vector2(456, 376), [Vector2(336, 376), Vector2(576, 376)])
	var _wdrops4c := GameManager.get_floor_weapon_drops(4)
	if _wdrops4c.size() > 0: _spawn_weapon_pickup(_wdrops4c[0], Vector2(592, 292))
	if _wdrops4c.size() > 1: _spawn_weapon_pickup(_wdrops4c[1], Vector2(144, 292))
	_pickup(Vector2(720, 376), 2); _pickup(Vector2(32, 376), 1)
	_pickup(Vector2(512, 544), 1); _pickup(Vector2(192, 56), 2)

# ── Floor 5 — The Throne Room (single layout; always max difficulty) ──────────
func _setup_floor5():
	var vr := 145.0; var va := 120.0

	# Entry — locked down; every enemy type represented
	_guard(_j(Vector2(320, 512)), [_j(Vector2(256,512)), _j(Vector2(384,512))], "WARDEN", vr, va, 0.28)
	_guard(_j(Vector2(448, 512)), [_j(Vector2(384,512)), _j(Vector2(512,512))], "WARDEN", vr, va, 0.28)
	_hound(Vector2(384, 496), [_j(Vector2(256,496)), _j(Vector2(512,496))])
	_hound(Vector2(304, 512), [_j(Vector2(256,480)), _j(Vector2(384,480))])
	_hound(Vector2(464, 512), [_j(Vector2(384,480)), _j(Vector2(512,480))])
	_gnoll(_j(Vector2(384, 540)), [_j(Vector2(256,540)), _j(Vector2(512,540))])
	_gnoll(_j(Vector2(272, 540)), [_j(Vector2(256,540)), _j(Vector2(384,540))])

	# Captain's Office — BOSS flanked by full retinue
	_boss(_j(Vector2(144, 200)),
		[_j(Vector2(48,168)), _j(Vector2(240,168)), _j(Vector2(240,248)), _j(Vector2(48,248))])
	_prowler(_j(Vector2(80, 184)),  [_j(Vector2(32,168)), _j(Vector2(144,200))])
	_prowler(_j(Vector2(224, 232)), [_j(Vector2(144,200)), _j(Vector2(240,248))])
	_prowler(_j(Vector2(144, 248)), [_j(Vector2(32,248)), _j(Vector2(240,248))])
	_guard(_j(Vector2(32, 200)),  [_j(Vector2(32,160)), _j(Vector2(32,248))],   "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(240, 200)), [_j(Vector2(240,160)), _j(Vector2(240,248))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(80, 168)),  [_j(Vector2(32,168)), _j(Vector2(144,168))],  "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(224, 168)), [_j(Vector2(144,168)), _j(Vector2(240,168))], "WARDEN", vr, va, 0.35)
	_skeleton(_j(Vector2(80, 248)),  [_j(Vector2(32,232)), _j(Vector2(144,248))])
	_skeleton(_j(Vector2(224, 248)), [_j(Vector2(144,248)), _j(Vector2(240,232))])
	_gnoll(_j(Vector2(80, 200)),   [_j(Vector2(32,184)), _j(Vector2(144,200))])
	_gnoll(_j(Vector2(224, 216)),  [_j(Vector2(144,216)), _j(Vector2(240,200))])
	_goblin(_j(Vector2(80, 232)),  [_j(Vector2(32,232)), _j(Vector2(144,248))])
	_goblin(_j(Vector2(224, 200)), [_j(Vector2(144,200)), _j(Vector2(240,216))])
	_sentinel(Vector2(144, 168)); _sentinel(Vector2(144, 248))
	_sentinel(Vector2(32,  216)); _sentinel(Vector2(240, 216))

	# Antechamber
	_guard(_j(Vector2(456, 168)), [_j(Vector2(336,168)), _j(Vector2(576,168))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(456, 248)), [_j(Vector2(336,248)), _j(Vector2(576,248))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))], "WARDEN", vr, va, 0.70)

	if _surge() or _escalated(2): _prowler(_j(Vector2(80, 248)), [_j(Vector2(32,248)), _j(Vector2(144,248))])
	if _bounty() or _escalated(3): _hound(_j(Vector2(144, 216)), [_j(Vector2(32,200)), _j(Vector2(240,200))])

	# Throne vault — three pieces of the relic
	_guard(_j(Vector2(192, 56)), [_j(Vector2(144,32)), _j(Vector2(240,80))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(384, 56)), [_j(Vector2(192,32)), _j(Vector2(480,32))], "WARDEN", vr, va, 0.32)
	_guard(_j(Vector2(576, 56)), [_j(Vector2(512,32)), _j(Vector2(624,80))], "WARDEN", vr, va, 0.70)
	_guard(_j(Vector2(288, 80)), [_j(Vector2(192,80)), _j(Vector2(384,80))],  "WATCHER", vr, va, 0.35)
	_guard(_j(Vector2(480, 80)), [_j(Vector2(384,80)), _j(Vector2(576,80))],  "WATCHER", vr, va, 0.35)
	_loot(Vector2(192, 40), 800, true, 2)
	_loot(Vector2(384, 32), 1500, false, 2)   # primary — throne relic
	_loot(Vector2(576, 40), 1000, true, 2)

	_trap(Vector2(80, 184)); _trap(Vector2(456, 168))
	_trap(Vector2(80, 248)); _trap(Vector2(600, 248))
	_trap(Vector2(144, 200)); _trap(Vector2(456, 216))
	_ward(Vector2(144, 184)); _ward(Vector2(456, 184))
	_ward(Vector2(80, 248)); _ward(Vector2(224, 248))
	_ward(Vector2(144, 168)); _ward(Vector2(144, 248))
	_glass(Vector2(80, 216)); _glass(Vector2(224, 216))
	_glass(Vector2(144, 216)); _glass(Vector2(80, 248)); _glass(Vector2(224, 248))
	_oil(Vector2(32, 216)); _oil(Vector2(576, 216))
	_oil(Vector2(32, 248)); _oil(Vector2(576, 248))
	_civilian(Vector2(456, 376), [Vector2(336, 376), Vector2(576, 376)])
	_civilian(Vector2(160, 420), [Vector2(48, 420), Vector2(272, 420)])
	_civilian(Vector2(600, 420), [Vector2(480, 420), Vector2(720, 420)])
	_pickup(Vector2(192, 56), 2); _pickup(Vector2(720, 376), 2)
	_pickup(Vector2(256, 544), 1); _pickup(Vector2(512, 544), 1)
	_pickup(Vector2(384, 540), 0)
	var _wdrops5 := GameManager.get_floor_weapon_drops(5)
	if _wdrops5.size() >= 1:
		_spawn_weapon_pickup(_wdrops5[0], Vector2(144, 292))
	if _wdrops5.size() >= 2:
		_spawn_weapon_pickup(_wdrops5[1], Vector2(592, 292))
	# Four alarm bells — vault mouth, both corridors, entry
	_bell(Vector2(320, 96))
	_bell(Vector2(192, 272))
	_bell(Vector2(560, 272))
	_bell(Vector2(384, 480))

# Floor 5 variant B — The Vault Siege: Boss holds the vault with a smaller, elite guard ring
func _setup_floor5b():
	var vr := 135.0; var va := 110.0

	# Entry — lighter than 5a but still dangerous
	_guard(_j(Vector2(352, 512)), [_j(Vector2(272,512)), _j(Vector2(432,512))], "WARDEN", vr, va, 0.30)
	_guard(_j(Vector2(448, 496)), [_j(Vector2(384,496)), _j(Vector2(512,496))], "WARDEN", vr, va, 0.30)
	_hound(Vector2(384, 480),  [_j(Vector2(240,480)), _j(Vector2(528,480))])
	_gnoll(_j(Vector2(288, 540)), [_j(Vector2(224,540)), _j(Vector2(384,540))])
	_gnoll(_j(Vector2(480, 540)), [_j(Vector2(384,540)), _j(Vector2(544,540))])

	# Barracks — prowlers on tight circuit
	_prowler(_j(Vector2(96,  368)), [_j(Vector2(48,336)),  _j(Vector2(160,368)), _j(Vector2(96,416))])
	_prowler(_j(Vector2(240, 368)), [_j(Vector2(160,336)), _j(Vector2(288,400))])
	_skeleton(_j(Vector2(48,  400)), [_j(Vector2(32,368)), _j(Vector2(96,416))])
	_skeleton(_j(Vector2(256, 400)), [_j(Vector2(192,400)), _j(Vector2(288,416))])

	# Storeroom — goblin pack
	_goblin(_j(Vector2(544, 368)), [_j(Vector2(480,336)), _j(Vector2(608,400))])
	_goblin(_j(Vector2(608, 368)), [_j(Vector2(544,336)), _j(Vector2(672,400))])
	_goblin(_j(Vector2(576, 416)), [_j(Vector2(480,416)), _j(Vector2(672,400))])
	_guard(_j(Vector2(704, 368)), [_j(Vector2(672,336)), _j(Vector2(720,416))], "WATCHER", vr, va, 0.50)

	# Captain's Office — heavily trapped, prowler patrols
	_prowler(_j(Vector2(80, 200)),  [_j(Vector2(32,168)), _j(Vector2(240,200)), _j(Vector2(80,248))])
	_prowler(_j(Vector2(200, 168)), [_j(Vector2(48,168)), _j(Vector2(240,168))])
	_guard(_j(Vector2(144, 216)),   [_j(Vector2(48,200)), _j(Vector2(240,200))], "WARDEN", vr, va, 0.60)
	_gnoll(_j(Vector2(80, 248)),    [_j(Vector2(32,232)), _j(Vector2(144,248))])
	_sentinel(Vector2(48, 168)); _sentinel(Vector2(240, 168))
	_sentinel(Vector2(48, 248)); _sentinel(Vector2(240, 248))

	# Antechamber — BOSS here (variant: boss has come forward with vault guard)
	_boss(_j(Vector2(456, 200)),
		[_j(Vector2(336,168)), _j(Vector2(576,168)), _j(Vector2(576,248)), _j(Vector2(336,248))])
	_guard(_j(Vector2(360, 168)), [_j(Vector2(336,160)), _j(Vector2(408,168))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(576, 168)), [_j(Vector2(544,160)), _j(Vector2(608,200))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(360, 248)), [_j(Vector2(336,240)), _j(Vector2(408,248))], "WARDEN", vr, va, 0.35)
	_guard(_j(Vector2(576, 248)), [_j(Vector2(544,240)), _j(Vector2(608,200))], "WARDEN", vr, va, 0.35)
	_prowler(_j(Vector2(336, 200)), [_j(Vector2(336,168)), _j(Vector2(336,248))])
	_gnoll(_j(Vector2(576, 216)),   [_j(Vector2(544,200)), _j(Vector2(608,232))])
	_hound(Vector2(504, 168), [_j(Vector2(336,168)), _j(Vector2(576,168))])

	# Vault — lighter with boss displaced but still two relics
	_guard(_j(Vector2(256, 56)), [_j(Vector2(160,32)), _j(Vector2(352,32))], "WATCHER", vr, va, 0.35)
	_guard(_j(Vector2(512, 56)), [_j(Vector2(416,32)), _j(Vector2(608,32))], "WATCHER", vr, va, 0.35)
	_guard(_j(Vector2(384, 80)), [_j(Vector2(192,80)), _j(Vector2(576,80))], "WARDEN",  vr, va, 0.60)
	_skeleton(_j(Vector2(192, 48)), [_j(Vector2(128,32)), _j(Vector2(256,64))])
	_skeleton(_j(Vector2(576, 48)), [_j(Vector2(512,32)), _j(Vector2(640,64))])
	_loot(Vector2(384, 32), 2000, false, 2)   # primary relic — now unguarded by boss
	_loot(Vector2(192, 40), 700,  true,  2)
	_loot(Vector2(576, 40), 900,  true,  2)

	_trap(Vector2(80, 200)); _trap(Vector2(456, 200))
	_trap(Vector2(80, 248)); _trap(Vector2(456, 248))
	_trap(Vector2(144, 168)); _trap(Vector2(144, 248))
	_ward(Vector2(80, 184)); _ward(Vector2(240, 184))
	_ward(Vector2(456, 184)); _ward(Vector2(576, 184))
	_glass(Vector2(144, 216)); _glass(Vector2(456, 216))
	_glass(Vector2(80, 232));  _glass(Vector2(576, 232))
	_oil(Vector2(32, 216)); _oil(Vector2(240, 216))
	_oil(Vector2(32, 248)); _oil(Vector2(240, 248))
	_civilian(Vector2(160, 376), [Vector2(48, 376), Vector2(272, 376)])
	_civilian(Vector2(576, 376), [Vector2(464, 376), Vector2(688, 376)])
	_civilian(Vector2(384, 420), [Vector2(240, 420), Vector2(528, 420)])
	_pickup(Vector2(240, 56), 2); _pickup(Vector2(528, 56), 2)
	_pickup(Vector2(256, 544), 1); _pickup(Vector2(512, 544), 1)
	_pickup(Vector2(384, 540), 0)
	var _wdrops5b := GameManager.get_floor_weapon_drops(5)
	if _wdrops5b.size() >= 1:
		_spawn_weapon_pickup(_wdrops5b[0], Vector2(144, 296))
	if _wdrops5b.size() >= 2:
		_spawn_weapon_pickup(_wdrops5b[1], Vector2(608, 296))
	if _surge() or _escalated(2):
		_prowler(_j(Vector2(240, 168)), [_j(Vector2(144,168)), _j(Vector2(240,248))])
	if _bounty() or _escalated(3):
		_hound(_j(Vector2(144, 216)), [_j(Vector2(32,200)), _j(Vector2(240,200))])

# Floor 5 variant C — The Shadow Court: Dispersed stealth specialists, no retinue wall, boss
# lurks in the darkened throne room flanked by prowlers and a web of sentinels + wards
func _setup_floor5c():
	var vr := 130.0; var va := 105.0

	# Entry — gnoll pack; fewer wardens but tight hound net
	_gnoll(_j(Vector2(320, 512)), [_j(Vector2(224,512)), _j(Vector2(416,512))])
	_gnoll(_j(Vector2(448, 512)), [_j(Vector2(352,512)), _j(Vector2(544,512))])
	_gnoll(_j(Vector2(384, 540)), [_j(Vector2(256,540)), _j(Vector2(512,540))])
	_hound(Vector2(256, 480), [_j(Vector2(192,480)), _j(Vector2(352,480))])
	_hound(Vector2(512, 480), [_j(Vector2(416,480)), _j(Vector2(608,480))])
	_hound(Vector2(384, 496), [_j(Vector2(240,496)), _j(Vector2(528,496))])

	# Mid corridor — prowlers weaving between ward lines
	_prowler(_j(Vector2(384, 368)), [_j(Vector2(240,368)), _j(Vector2(528,368)), _j(Vector2(384,416))])
	_prowler(_j(Vector2(176, 400)), [_j(Vector2(112,368)), _j(Vector2(240,416))])
	_prowler(_j(Vector2(592, 400)), [_j(Vector2(528,368)), _j(Vector2(656,416))])
	_skeleton(_j(Vector2(112, 368)), [_j(Vector2(48,352)), _j(Vector2(176,384))])
	_skeleton(_j(Vector2(656, 368)), [_j(Vector2(592,352)), _j(Vector2(720,384))])

	# Antechamber — goblin scouts + sentinel tripwire web
	_goblin(_j(Vector2(384, 248)), [_j(Vector2(288,248)), _j(Vector2(480,248))])
	_goblin(_j(Vector2(272, 216)), [_j(Vector2(192,200)), _j(Vector2(336,248))])
	_goblin(_j(Vector2(496, 216)), [_j(Vector2(432,200)), _j(Vector2(576,248))])
	_guard(_j(Vector2(192, 168)), [_j(Vector2(144,144)), _j(Vector2(240,200))], "WATCHER", vr, va, 0.40)
	_guard(_j(Vector2(576, 168)), [_j(Vector2(528,144)), _j(Vector2(624,200))], "WATCHER", vr, va, 0.40)
	_sentinel(Vector2(288, 168)); _sentinel(Vector2(480, 168))
	_sentinel(Vector2(288, 248)); _sentinel(Vector2(480, 248))
	_sentinel(Vector2(192, 216)); _sentinel(Vector2(576, 216))

	# Throne Room — BOSS hidden deep; prowler guards and no retinue wall
	_boss(_j(Vector2(384, 56)),
		[_j(Vector2(240,32)), _j(Vector2(528,32)), _j(Vector2(528,80)), _j(Vector2(240,80))])
	_prowler(_j(Vector2(192, 80)),  [_j(Vector2(144,32)), _j(Vector2(240,80)), _j(Vector2(192,128))])
	_prowler(_j(Vector2(576, 80)),  [_j(Vector2(528,32)), _j(Vector2(624,80)), _j(Vector2(576,128))])
	_prowler(_j(Vector2(384, 80)),  [_j(Vector2(288,64)), _j(Vector2(480,64))])
	_guard(_j(Vector2(240, 56)),  [_j(Vector2(192,32)), _j(Vector2(288,80))], "WARDEN", vr, va, 0.55)
	_guard(_j(Vector2(528, 56)),  [_j(Vector2(480,32)), _j(Vector2(576,80))], "WARDEN", vr, va, 0.55)
	_gnoll(_j(Vector2(288, 80)),  [_j(Vector2(240,64)), _j(Vector2(336,80))])
	_gnoll(_j(Vector2(480, 80)),  [_j(Vector2(432,64)), _j(Vector2(528,80))])

	# Three relics — primary on the throne, two flanking
	_loot(Vector2(384, 32), 1800, false, 2)   # primary — throne relic
	_loot(Vector2(192, 40), 750, true, 2)
	_loot(Vector2(576, 40), 950, true, 2)

	# Dense hazard web — wards gate every corridor, oil + glass punish noise
	_ward(Vector2(288, 168)); _ward(Vector2(480, 168))
	_ward(Vector2(192, 248)); _ward(Vector2(576, 248))
	_ward(Vector2(288, 80));  _ward(Vector2(480, 80))
	_ward(Vector2(192, 56));  _ward(Vector2(576, 56))
	_trap(Vector2(384, 216)); _trap(Vector2(192, 216)); _trap(Vector2(576, 216))
	_trap(Vector2(384, 368)); _trap(Vector2(176, 400)); _trap(Vector2(592, 400))
	_glass(Vector2(336, 248)); _glass(Vector2(432, 248))
	_glass(Vector2(192, 200)); _glass(Vector2(576, 200))
	_glass(Vector2(240, 80));  _glass(Vector2(528, 80))
	_oil(Vector2(144, 248)); _oil(Vector2(624, 248))
	_oil(Vector2(144, 80));  _oil(Vector2(624, 80))

	# Civilians huddled near entry — witnesses if combat erupts
	_civilian(Vector2(112, 420), [Vector2(48, 420), Vector2(240, 420)])
	_civilian(Vector2(656, 420), [Vector2(528, 420), Vector2(720, 420)])
	_civilian(Vector2(384, 296), [Vector2(256, 296), Vector2(512, 296)])

	_pickup(Vector2(240, 56), 2); _pickup(Vector2(528, 56), 2)
	_pickup(Vector2(256, 544), 1); _pickup(Vector2(512, 544), 1)
	_pickup(Vector2(384, 540), 0)

	var _wdrops5c := GameManager.get_floor_weapon_drops(5)
	if _wdrops5c.size() >= 1:
		_spawn_weapon_pickup(_wdrops5c[0], Vector2(144, 296))
	if _wdrops5c.size() >= 2:
		_spawn_weapon_pickup(_wdrops5c[1], Vector2(608, 296))

	if _surge() or _escalated(2):
		_hound(_j(Vector2(384, 216)), [_j(Vector2(288,216)), _j(Vector2(480,216))])
	if _bounty() or _escalated(3):
		_guard(_j(Vector2(384, 128)), [_j(Vector2(288,128)), _j(Vector2(480,128))], "ELITE", vr + 20.0, va + 15.0, 0.55)

# ── Floor 6 — The Citadel ─────────────────────────────────────────────────────
func _setup_floor6():
	var vr := 150.0; var va := 130.0

	# Entry — the full garrison; no weak links
	_guard(_j(Vector2(320, 512)), [_j(Vector2(224,512)), _j(Vector2(416,512))], "WARDEN", vr, va, 0.26)
	_guard(_j(Vector2(448, 512)), [_j(Vector2(352,512)), _j(Vector2(544,512))], "WARDEN", vr, va, 0.26)
	_guard(_j(Vector2(384, 496)), [_j(Vector2(256,496)), _j(Vector2(512,496))], "WARDEN", vr, va, 0.26)
	_hound(Vector2(256, 480),  [_j(Vector2(192,480)), _j(Vector2(352,480))])
	_hound(Vector2(512, 480),  [_j(Vector2(416,480)), _j(Vector2(608,480))])
	_gnoll(_j(Vector2(288, 544)), [_j(Vector2(224,544)), _j(Vector2(384,544))])
	_gnoll(_j(Vector2(480, 544)), [_j(Vector2(384,544)), _j(Vector2(544,544))])

	# Mid — prowler vanguard; captain covers corridor
	_prowler(_j(Vector2(384, 368)), [_j(Vector2(240,368)), _j(Vector2(528,368)), _j(Vector2(384,416))])
	_prowler(_j(Vector2(192, 384)), [_j(Vector2(144,352)), _j(Vector2(240,416))])
	_prowler(_j(Vector2(576, 384)), [_j(Vector2(528,352)), _j(Vector2(656,416))])
	_captain(_j(Vector2(384, 320)), [_j(Vector2(256,320)), _j(Vector2(512,320)), _j(Vector2(512,416)), _j(Vector2(256,416))])

	# Antechamber — sentinel grid; goblins on tripwires
	_goblin(_j(Vector2(288, 248)), [_j(Vector2(224,248)), _j(Vector2(352,248))])
	_goblin(_j(Vector2(480, 248)), [_j(Vector2(416,248)), _j(Vector2(544,248))])
	_skeleton(_j(Vector2(144, 200)), [_j(Vector2(96,160)), _j(Vector2(192,240))])
	_skeleton(_j(Vector2(624, 200)), [_j(Vector2(576,160)), _j(Vector2(672,240))])
	_sentinel(Vector2(240, 168)); _sentinel(Vector2(528, 168))
	_sentinel(Vector2(288, 248)); _sentinel(Vector2(480, 248))
	_sentinel(Vector2(384, 200))

	# Inner Sanctum — BOSS + full retinue; two captains flank
	_boss(_j(Vector2(384, 48)),
		[_j(Vector2(288,32)), _j(Vector2(480,32)), _j(Vector2(480,80)), _j(Vector2(288,80))])
	_captain(_j(Vector2(224, 80)),
		[_j(Vector2(160,48)), _j(Vector2(288,80)), _j(Vector2(224,128))])
	_captain(_j(Vector2(544, 80)),
		[_j(Vector2(480,48)), _j(Vector2(608,80)), _j(Vector2(544,128))])
	_prowler(_j(Vector2(384, 80)),  [_j(Vector2(288,64)), _j(Vector2(480,64)), _j(Vector2(384,112))])
	_guard(_j(Vector2(288, 56)),  [_j(Vector2(240,32)), _j(Vector2(336,80))], "ELITE", vr + 10, va + 10, 0.50)
	_guard(_j(Vector2(480, 56)),  [_j(Vector2(432,32)), _j(Vector2(528,80))], "ELITE", vr + 10, va + 10, 0.50)

	# Grand vault — maximum haul
	_loot(Vector2(384, 32), 2500, false, 2)
	_loot(Vector2(160, 40), 900, true, 2)
	_loot(Vector2(608, 40), 900, true, 2)
	_loot(Vector2(288, 56), 600, true, 1)
	_loot(Vector2(480, 56), 600, true, 1)

	# Hazard grid — maximum density
	_ward(Vector2(240, 168)); _ward(Vector2(528, 168))
	_ward(Vector2(384, 200)); _ward(Vector2(288, 248)); _ward(Vector2(480, 248))
	_ward(Vector2(224, 80));  _ward(Vector2(544, 80))
	_ward(Vector2(288, 48));  _ward(Vector2(480, 48))
	_trap(Vector2(384, 320)); _trap(Vector2(192, 384)); _trap(Vector2(576, 384))
	_trap(Vector2(288, 248)); _trap(Vector2(480, 248))
	_trap(Vector2(288, 80));  _trap(Vector2(480, 80))
	_glass(Vector2(336, 248)); _glass(Vector2(432, 248))
	_glass(Vector2(240, 80));  _glass(Vector2(528, 80))
	_glass(Vector2(288, 32));  _glass(Vector2(480, 32))
	_oil(Vector2(144, 248)); _oil(Vector2(624, 248))
	_oil(Vector2(144, 80));  _oil(Vector2(624, 80))
	_oil(Vector2(384, 128))

	# Alarm bells everywhere
	_bell(Vector2(320, 96));   _bell(Vector2(448, 96))
	_bell(Vector2(192, 272));  _bell(Vector2(576, 272))
	_bell(Vector2(384, 368));  _bell(Vector2(384, 480))

	_civilian(Vector2(384, 296), [Vector2(256, 296), Vector2(512, 296)])
	_pickup(Vector2(240, 56), 2); _pickup(Vector2(528, 56), 2)
	_pickup(Vector2(256, 544), 1); _pickup(Vector2(512, 544), 1)

	var _wdrops6 := GameManager.get_floor_weapon_drops(6)
	if _wdrops6.size() >= 1:
		_spawn_weapon_pickup(_wdrops6[0], Vector2(144, 296))
	if _wdrops6.size() >= 2:
		_spawn_weapon_pickup(_wdrops6[1], Vector2(608, 296))
	if _surge() or _escalated(2):
		_hound(_j(Vector2(384, 212)), [_j(Vector2(288,212)), _j(Vector2(480,212))])
	if _bounty() or _escalated(4):
		_captain(_j(Vector2(384, 448)), [_j(Vector2(256,448)), _j(Vector2(512,448))])

func _setup_floor6b():
	# Floor 6 variant B — The Iron Vault: Fewer captains, more sentinels and skeleton patrols
	var vr := 148.0; var va := 125.0

	# Entry — skeleton wall
	_skeleton(_j(Vector2(320, 512)), [_j(Vector2(224,512)), _j(Vector2(416,512))])
	_skeleton(_j(Vector2(448, 512)), [_j(Vector2(352,512)), _j(Vector2(544,512))])
	_skeleton(_j(Vector2(384, 496)), [_j(Vector2(256,496)), _j(Vector2(512,496))])
	_hound(Vector2(256, 480),  [_j(Vector2(192,480)), _j(Vector2(352,480))])
	_hound(Vector2(512, 480),  [_j(Vector2(416,480)), _j(Vector2(608,480))])
	_gnoll(_j(Vector2(288, 544)), [_j(Vector2(224,544)), _j(Vector2(384,544))])
	_gnoll(_j(Vector2(480, 544)), [_j(Vector2(384,544)), _j(Vector2(544,544))])

	# Mid — sentinel maze with interlocking arcs
	_sentinel(Vector2(192, 368)); _sentinel(Vector2(384, 368)); _sentinel(Vector2(576, 368))
	_sentinel(Vector2(288, 416)); _sentinel(Vector2(480, 416))
	_prowler(_j(Vector2(144, 352)), [_j(Vector2(96,320)), _j(Vector2(192,384))])
	_prowler(_j(Vector2(624, 352)), [_j(Vector2(576,320)), _j(Vector2(672,384))])
	_goblin(_j(Vector2(384, 416)), [_j(Vector2(288,416)), _j(Vector2(480,416))])

	# Antechamber — captain pair + warden ring
	_captain(_j(Vector2(240, 200)),
		[_j(Vector2(160,160)), _j(Vector2(320,240))])
	_captain(_j(Vector2(528, 200)),
		[_j(Vector2(448,160)), _j(Vector2(608,240))])
	_skeleton(_j(Vector2(384, 248)), [_j(Vector2(288,248)), _j(Vector2(480,248))])
	_sentinel(Vector2(288, 168)); _sentinel(Vector2(480, 168))
	_sentinel(Vector2(384, 200))

	# Boss chamber — prowler guard ring around vault
	_boss(_j(Vector2(384, 48)),
		[_j(Vector2(288,32)), _j(Vector2(480,32)), _j(Vector2(480,80)), _j(Vector2(288,80))])
	_prowler(_j(Vector2(224, 64)),  [_j(Vector2(160,32)), _j(Vector2(288,80))])
	_prowler(_j(Vector2(544, 64)),  [_j(Vector2(480,32)), _j(Vector2(608,80))])
	_prowler(_j(Vector2(384, 80)),  [_j(Vector2(288,64)), _j(Vector2(480,64))])
	_prowler(_j(Vector2(288, 112)), [_j(Vector2(224,96)), _j(Vector2(352,128))])
	_prowler(_j(Vector2(480, 112)), [_j(Vector2(416,96)), _j(Vector2(544,128))])
	_guard(_j(Vector2(384, 112)), [_j(Vector2(304,96)), _j(Vector2(464,96))], "WARDEN", vr, va, 0.45)

	_loot(Vector2(384, 32), 2500, false, 2)
	_loot(Vector2(176, 40), 850, true, 2)
	_loot(Vector2(592, 40), 850, true, 2)

	_ward(Vector2(288, 168)); _ward(Vector2(480, 168))
	_ward(Vector2(384, 200)); _ward(Vector2(192, 368)); _ward(Vector2(576, 368))
	_ward(Vector2(288, 80));  _ward(Vector2(480, 80))
	_trap(Vector2(384, 368)); _trap(Vector2(288, 416)); _trap(Vector2(480, 416))
	_trap(Vector2(288, 80));  _trap(Vector2(480, 80))
	_glass(Vector2(336, 248)); _glass(Vector2(432, 248))
	_glass(Vector2(288, 32));  _glass(Vector2(480, 32))
	_oil(Vector2(144, 248)); _oil(Vector2(624, 248))
	_oil(Vector2(144, 80));  _oil(Vector2(624, 80))

	_bell(Vector2(320, 96));   _bell(Vector2(448, 96))
	_bell(Vector2(192, 368));  _bell(Vector2(576, 368))
	_bell(Vector2(384, 480))

	_pickup(Vector2(240, 56), 2); _pickup(Vector2(528, 56), 2)
	_pickup(Vector2(256, 544), 1); _pickup(Vector2(512, 544), 1)
	var _wdrops6b := GameManager.get_floor_weapon_drops(6)
	if _wdrops6b.size() >= 1:
		_spawn_weapon_pickup(_wdrops6b[0], Vector2(144, 296))
	if _wdrops6b.size() >= 2:
		_spawn_weapon_pickup(_wdrops6b[1], Vector2(608, 296))
	if _surge() or _escalated(2):
		_gnoll(_j(Vector2(384, 368)), [_j(Vector2(288,368)), _j(Vector2(480,368))])

func _setup_floor6c():
	# Floor 6 variant C — Siege Protocol: All guards pre-alert; no patrols, pure static
	var vr := 145.0; var va := 120.0

	# Entry — gnolls and hounds in a killzone
	_gnoll(_j(Vector2(288, 512)), [_j(Vector2(224,512)), _j(Vector2(384,512))])
	_gnoll(_j(Vector2(480, 512)), [_j(Vector2(384,512)), _j(Vector2(544,512))])
	_gnoll(_j(Vector2(384, 540)), [_j(Vector2(256,540)), _j(Vector2(512,540))])
	_hound(Vector2(224, 480), [_j(Vector2(160,480)), _j(Vector2(320,480))])
	_hound(Vector2(544, 480), [_j(Vector2(448,480)), _j(Vector2(608,480))])
	_hound(Vector2(384, 496), [_j(Vector2(256,496)), _j(Vector2(512,496))])
	_hound(Vector2(384, 464), [_j(Vector2(288,464)), _j(Vector2(480,464))])

	# Mid corridor — prowler + captain ambush
	_prowler(_j(Vector2(192, 368)), [_j(Vector2(144,320)), _j(Vector2(240,416))])
	_prowler(_j(Vector2(576, 368)), [_j(Vector2(528,320)), _j(Vector2(624,416))])
	_prowler(_j(Vector2(384, 400)), [_j(Vector2(288,384)), _j(Vector2(480,384)), _j(Vector2(384,448))])
	_captain(_j(Vector2(384, 320)), [_j(Vector2(256,320)), _j(Vector2(512,320)), _j(Vector2(384,368))])
	_captain(_j(Vector2(176, 320)), [_j(Vector2(128,288)), _j(Vector2(240,352))])
	_captain(_j(Vector2(592, 320)), [_j(Vector2(544,288)), _j(Vector2(640,352))])

	# Antechamber — everything; sentinels, goblins, skeletons
	_goblin(_j(Vector2(288, 248)), [_j(Vector2(224,248)), _j(Vector2(352,248))])
	_goblin(_j(Vector2(480, 248)), [_j(Vector2(416,248)), _j(Vector2(544,248))])
	_goblin(_j(Vector2(384, 216)), [_j(Vector2(320,200)), _j(Vector2(448,200))])
	_skeleton(_j(Vector2(144, 200)), [_j(Vector2(96,160)), _j(Vector2(192,240))])
	_skeleton(_j(Vector2(624, 200)), [_j(Vector2(576,160)), _j(Vector2(672,240))])
	_sentinel(Vector2(240, 168)); _sentinel(Vector2(528, 168))
	_sentinel(Vector2(192, 248)); _sentinel(Vector2(576, 248))
	_sentinel(Vector2(384, 168))

	# Boss — solo in the deepest sanctum, heavily warded
	_boss(_j(Vector2(384, 48)),
		[_j(Vector2(240,32)), _j(Vector2(528,32)), _j(Vector2(528,80)), _j(Vector2(240,80))])
	_captain(_j(Vector2(240, 80)),
		[_j(Vector2(176,48)), _j(Vector2(304,96))])
	_captain(_j(Vector2(528, 80)),
		[_j(Vector2(464,48)), _j(Vector2(592,96))])
	_guard(_j(Vector2(384, 80)),  [_j(Vector2(288,64)), _j(Vector2(480,64))], "ELITE", vr + 15, va + 15, 0.48)

	# Loot
	_loot(Vector2(384, 32), 2800, false, 2)
	_loot(Vector2(192, 40), 1000, true, 2)
	_loot(Vector2(576, 40), 1000, true, 2)

	# Max hazards
	_ward(Vector2(240, 168)); _ward(Vector2(528, 168))
	_ward(Vector2(384, 168)); _ward(Vector2(192, 248)); _ward(Vector2(576, 248))
	_ward(Vector2(240, 80));  _ward(Vector2(528, 80))
	_ward(Vector2(288, 48));  _ward(Vector2(480, 48))
	_trap(Vector2(384, 320)); _trap(Vector2(176, 320)); _trap(Vector2(592, 320))
	_trap(Vector2(288, 248)); _trap(Vector2(480, 248)); _trap(Vector2(384, 216))
	_trap(Vector2(288, 80));  _trap(Vector2(480, 80))
	_glass(Vector2(336, 248)); _glass(Vector2(432, 248))
	_glass(Vector2(240, 80));  _glass(Vector2(528, 80))
	_glass(Vector2(288, 32));  _glass(Vector2(480, 32))
	_oil(Vector2(144, 248)); _oil(Vector2(624, 248))
	_oil(Vector2(144, 80));  _oil(Vector2(624, 80))

	# Six alarm bells — the densest alarm network
	_bell(Vector2(320, 96));   _bell(Vector2(448, 96))
	_bell(Vector2(192, 272));  _bell(Vector2(576, 272))
	_bell(Vector2(192, 368));  _bell(Vector2(576, 368))
	_bell(Vector2(384, 480))

	# Pre-alert the entire garrison
	for g in get_tree().get_nodes_in_group("guards"):
		g.set("alert_state", 1)
		g.set("de_escalate_timer", 99.0)

	_pickup(Vector2(240, 56), 2); _pickup(Vector2(528, 56), 2)
	_pickup(Vector2(256, 544), 1); _pickup(Vector2(512, 544), 1)
	var _wdrops6c := GameManager.get_floor_weapon_drops(6)
	if _wdrops6c.size() >= 1:
		_spawn_weapon_pickup(_wdrops6c[0], Vector2(144, 296))
	if _wdrops6c.size() >= 2:
		_spawn_weapon_pickup(_wdrops6c[1], Vector2(608, 296))

# ── V10 Archetype guard spawning (floors 3+) ─────────────────────────────────
func _spawn_archetype_guards() -> void:
	var floor := GameManager.current_floor
	# Floor 3+: one INQUISITOR in vault area
	if floor >= 3:
		_inquisitor(Vector2(480, 56), [Vector2(336, 32), Vector2(608, 32), Vector2(608, 80), Vector2(336, 80)])
	# Floor 4+: BRUTE in antechamber
	if floor >= 4:
		_brute(Vector2(408, 200), [Vector2(336, 160), Vector2(496, 160), Vector2(496, 256), Vector2(336, 256)])
	# Floor 5+: HEX_CASTER in captain's office area
	if floor >= 5:
		_hex_caster(Vector2(144, 240), [Vector2(48, 240), Vector2(240, 240)])
	# Floor 6: second INQUISITOR + HEX_CASTER in foyer
	if floor >= 6:
		_inquisitor(Vector2(304, 512), [Vector2(256, 496), Vector2(384, 512)])
		_hex_caster(Vector2(464, 512), [Vector2(384, 512), Vector2(512, 496)])

# ── Optional side passage — elite guard + bonus loot ─────────────────────────
func _spawn_side_passage():
	# Elite guard in Armory — bonus loot tucked in corner
	var elite := _guard(_j(Vector2(680, 200)), [_j(Vector2(640,160)), _j(Vector2(720,240))],
		"ELITE", 100.0, 90.0, 0.70)
	elite.set("vision_range", 100.0 + GameManager.current_floor * 5.0)
	_loot(Vector2(720, 160),
		200 + GameManager.current_floor * 100, true,
		mini(GameManager.current_floor - 1, 2))
	_pickup(Vector2(720, 240), (_rng.randi() % 3) + 1)

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
			# Last resort: push perpendicular to Entry Foyer centre
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
	var entry := Vector2(384, 570)   # south edge of Entry Foyer
	var g: Node
	if wave >= 2 or (_rng.randi() % 2 == 1 and GameManager.current_floor >= 2):
		g = _prowler(entry, [_j(Vector2(256,512)), _j(Vector2(512,512)), _j(Vector2(384,200))])
	else:
		g = _guard(entry,
			[_j(Vector2(256,512)), _j(Vector2(512,512)), _j(Vector2(384,376))],
			"REINFORCE", 90.0, 75.0, 0.30)
	if g:
		g.set("alert_state", 1)
		g.set("de_escalate_timer", 10.0)
		g.set("investigate_pos", Vector2(384, 200))
		# Propagate intel effects to newly spawned reinforcement
		if "patrol_schedule" in GameManager.preheist_intel:
			g.set("show_patrol_path", true)
		if "guard_weakness" in GameManager.preheist_intel:
			g.set("show_stats", true)
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

func _captain(pos: Vector2, patrol: Array, vrange := 135.0, vangle := 110.0) -> Node:
	var g := _guard(pos, patrol, "CAPTAIN", vrange, vangle, 0.30)
	g.set("is_captain", true)
	return g

func _sentinel(pos: Vector2) -> Node:
	var g := GuardScene.instantiate()
	g.position = pos
	g.patrol_points = Array([], TYPE_VECTOR2, &"", null)
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

func _bell(pos: Vector2) -> Node:
	var b := Node2D.new()
	b.set_script(_bell_script)
	b.position = pos
	add_child(b)
	return b

# ── V10 Relic chest spawn ───────────────────────────────────────────────────
const _relic_script := preload("res://RelicPickup.gd")

func _spawn_relic(pos: Vector2, relic_id: String) -> Node:
	var r := Area2D.new()
	r.set_script(_relic_script)
	r.position = pos
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	col.shape = shape
	r.add_child(col)
	r.body_entered.connect(r._on_body_entered)
	add_child(r)
	r.call("setup", relic_id)
	return r

func _spawn_floor_relic() -> void:
	# Choose a relic the player doesn't have yet; prefer rarity 1, then 2, then 3
	var pool: Array = []
	for rd in GameManager.RELICS:
		if not GameManager.has_relic(rd.id):
			pool.append(rd)
	if pool.is_empty():
		return
	pool.sort_custom(func(a, b): return a.rarity < b.rarity)
	# Pick from lowest-rarity available with some randomness
	var eligible: Array = pool.filter(func(x): return x.rarity == pool[0].rarity)
	var chosen: Dictionary = eligible[_rng.randi() % eligible.size()]
	# Spawn at vault loot alcove (always in accessible area)
	var pos := Vector2(192.0 + _rng.randi_range(0, 3) * 16.0, 48.0)
	_spawn_relic(pos, chosen.id)

# ── V10 New guard archetype helpers ────────────────────────────────────────
func _inquisitor(pos: Vector2, patrol: Array) -> Node:
	var g := _guard(pos, patrol, "INQUISITOR", 90.0, 90.0, 0.35)
	g.set("is_inquisitor", true)
	return g

func _brute(pos: Vector2, patrol: Array) -> Node:
	var g := _guard(pos, patrol, "BRUTE", 75.0, 65.0, 0.50)
	g.set("is_brute", true)
	return g

func _hex_caster(pos: Vector2, patrol: Array) -> Node:
	var g := _guard(pos, patrol, "HEX CASTER", 85.0, 70.0, 0.45)
	g.set("is_hex_caster", true)
	return g

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
