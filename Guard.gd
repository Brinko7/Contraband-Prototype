extends CharacterBody2D

enum AlertState  { UNAWARE, SUSPICIOUS, ALERT }
enum EnemyType   { HUMAN, SKELETON, GOBLIN, GNOLL }

const TILE_SIZE = 16
const INVESTIGATE_DELAY = 2

const _dice_scene   = preload("res://DicePopup.tscn")
const _body_script  = preload("res://BodyMarker.gd")
const _ENEMY_SHEET  = preload("res://sprites/enemy_sheet.png")

var _sprite: Sprite2D

@export var vision_range  := 80.0
@export var vision_angle  := 60.0
@export var move_interval := 0.4
@export var chase_interval := 0.25
@export var guard_label   := "SENTRY"
@export var is_captain    := false
@export var is_boss       := false
@export var enemy_type: EnemyType = EnemyType.HUMAN

@export var patrol_points: Array[Vector2] = []

var _is_held      := false   # Hold Person spell
var _held_timer   := 0.0
var _is_stunned   := false   # Dwarf battle cry
var _stun_timer   := 0.0

# How fast the detection bar fills (seconds to fill from 0→1)
var detect_fill_rate: Dictionary = {}
const DETECT_DRAIN_RATE = 0.4  # per second when not seeing player

const HEARING_RANGE = { 0: 0.0, 1: 48.0, 2: 140.0 }
const ALERT_TIMEOUT      = 9.0
const SUSPICIOUS_TIMEOUT = 6.0
const BODY_VISION_RANGE  = 100.0

var alert_state := AlertState.UNAWARE
var facing := Vector2.RIGHT
var patrol_index := 0
var move_timer := 0.0
var patrol_wait := 0.0
var investigate_pos := Vector2.ZERO
var investigate_delay_ticks := 0
var de_escalate_timer := 0.0
var detection_progress   := 0.0
var _boss_summoned_once  := false  # boss calls reinforcements once at 50% detection
var _can_see_player := false
var _detect_tick_played := false
var player: Node2D = null
var _footprints: Array[Vector2] = []
var _anim_t := 0.0

# Body discovery — 6s window before full alert
var _spotted_body: Node = null
var _body_discovery_timer := 0.0
const BODY_DISCOVERY_WINDOW := 6.0

# Patrol shift — guards rotate to alternate waypoints at 45s / 90s intervals
var _shift_timer     := 0.0
const SHIFT_TIMES    := [45.0, 90.0]
var _shifts_done     := 0
var _original_patrol: Array[Vector2] = []  # store original for shift restore

# Guard conversation — brief pause when two guards cross paths
var _convo_timer := 0.0

# Key drop — if >= 0 the guard carries a key for the matching LockedDoor
var key_id: int = -1

# Weapon drop — weapon this guard carries; "NONE" means no drop
var dropped_weapon: String = "NONE"

# HP system
var guard_hp:     int = 2
var guard_max_hp: int = 2
var _hurt_flash_t:   float   = 0.0
var _knockback_dir:  Vector2 = Vector2.ZERO
var _knockback_t:    float   = 0.0
const _KNOCKBACK_DUR: float  = 0.14
const _KNOCKBACK_PX:  float  = 6.0

# Patrol path preview — briefly shown when player enters this guard's room
var _path_preview_t: float = 0.0
const _PATH_PREVIEW_DUR: float = 3.5

func _ready():
	add_to_group("guards")
	detect_fill_rate = { AlertState.UNAWARE: 0.9, AlertState.SUSPICIOUS: 0.5 }
	player = get_tree().get_first_node_in_group("player")
	if player and player.has_signal("noise_emitted"):
		player.noise_emitted.connect(_on_noise_emitted)
	_apply_modifier()
	_original_patrol = patrol_points.duplicate()
	guard_max_hp = 4 if is_boss else (3 if is_captain else 2)
	guard_hp     = guard_max_hp
	# Assign dropped weapon based on guard type / role
	if is_boss:
		dropped_weapon = "LONGSWORD"
	elif is_captain:
		dropped_weapon = "LONGSWORD"
	elif enemy_type == EnemyType.GNOLL:
		dropped_weapon = "SPEAR"
	elif enemy_type == EnemyType.HUMAN and randi_range(1, 10) <= 4:
		dropped_weapon = "SHIV"
	# Goblin and Skeleton drop nothing
	# V7: pure SVG procedural art — no sprite sheet
	_sprite = null

func _apply_modifier():
	match GameManager.run_modifier:
		"TIGHT_PATROLS":
			move_interval  *= 0.65
			chase_interval *= 0.65
		"UNDER_THE_MOON":
			vision_range += 30.0
		"HIGH_ALERT":
			alert_state = AlertState.SUSPICIOUS
			de_escalate_timer = SUSPICIOUS_TIMEOUT
	# Floor complication
	match GameManager.floor_complication:
		"DIM":
			vision_range = max(30.0, vision_range - 25.0)
		"LOCKDOWN":
			alert_state = AlertState.SUSPICIOUS
			de_escalate_timer = SUSPICIOUS_TIMEOUT
		"PARANOID":
			detect_fill_rate[AlertState.UNAWARE]    *= 0.60
			detect_fill_rate[AlertState.SUSPICIOUS] *= 0.60
		"DRUNK_WATCH":
			move_interval  *= 1.25
			chase_interval *= 1.25
			vision_angle   *= 0.75
		"FOG":
			vision_range = max(25.0, vision_range - 40.0)
	# Alert escalation pressure
	if GameManager.alert_escalation >= 4:
		vision_range += 10.0
	if GameManager.alert_escalation >= 6:
		move_interval  = max(0.15, move_interval  * 0.85)
		chase_interval = max(0.10, chase_interval * 0.85)

func _process(delta):
	if GameManager.state != GameManager.State.PLAYING:
		return
	_anim_t += delta
	if _path_preview_t > 0.0:
		_path_preview_t -= delta
		queue_redraw()
	if _hurt_flash_t > 0.0:
		_hurt_flash_t -= delta
		queue_redraw()
	if _knockback_t > 0.0:
		_knockback_t -= delta
		if _sprite != null:
			var env: float = _knockback_t / _KNOCKBACK_DUR
			_sprite.position = _knockback_dir * _KNOCKBACK_PX * env * env
		if _knockback_t <= 0.0 and _sprite != null:
			_sprite.position = Vector2.ZERO
		queue_redraw()
	# Hold Person
	if _is_held:
		_held_timer -= delta
		if _held_timer <= 0.0:
			_is_held = false
		queue_redraw()
		return
	# Dwarf stun
	if _is_stunned:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_is_stunned = false
		queue_redraw()
		return
	# Patrol shift timer
	if alert_state == AlertState.UNAWARE and _shifts_done < SHIFT_TIMES.size():
		_shift_timer += delta
		if _shift_timer >= SHIFT_TIMES[_shifts_done]:
			_shifts_done += 1
			_do_patrol_shift()

	# Guard conversation — pause briefly when two guards share a tile
	if _convo_timer > 0.0:
		_convo_timer -= delta
		queue_redraw()
		return

	# Body discovery countdown
	if _spotted_body != null:
		if not is_instance_valid(_spotted_body) or _spotted_body.get_meta("being_carried", false):
			# Body was picked up in time!
			_spotted_body         = null
			_body_discovery_timer = 0.0
			_popup("...where'd it go?", Color(0.70, 0.65, 0.30))
			_become_suspicious(investigate_pos)
		else:
			_body_discovery_timer -= delta
			# Pulse popup every second with countdown
			if int(_body_discovery_timer + delta) != int(_body_discovery_timer):
				_popup("BODY! — hide it! (%.0fs)" % max(0.0, _body_discovery_timer),
					Color(1.0, 0.60, 0.10))
			if _body_discovery_timer <= 0.0:
				_spotted_body = null
				_find_body(investigate_pos)

	_check_vision()
	_check_bodies()
	# Gnoll smell — proximity detection regardless of facing/vision
	if enemy_type == EnemyType.GNOLL and player != null:
		var elf_immune := GameManager.selected_race == "WOOD_ELF"
		if not elf_immune and not player.get("is_hidden"):
			var smell_dist := 52.0 + GameManager.floor_heat_level * 4.0
			if global_position.distance_to(player.global_position) <= smell_dist:
				if alert_state == AlertState.UNAWARE:
					_become_suspicious(player.global_position)
				elif alert_state == AlertState.SUSPICIOUS:
					_escalate_alert()
	_update_detection(delta)
	var old_pos := position
	match alert_state:
		AlertState.UNAWARE, AlertState.SUSPICIOUS:
			_update_patrol(delta)
		AlertState.ALERT:
			_update_chase(delta)
	if position != old_pos:
		_footprints.push_back(old_pos)
		if _footprints.size() > 4:
			_footprints.pop_front()
	_update_de_escalation(delta)
	queue_redraw()

func _get_move_interval() -> float:
	var heat := GameManager.floor_heat_level
	return max(move_interval * 0.50, move_interval - heat * move_interval * 0.12)

func _get_chase_interval() -> float:
	var heat := GameManager.floor_heat_level
	return max(chase_interval * 0.50, chase_interval - heat * chase_interval * 0.12)

func _update_detection(delta):
	if _can_see_player:
		var rate: float = detect_fill_rate.get(alert_state, 0.9)
		var fill_mult := 1.0
		if is_sneaking_player():
			if GameManager.has_passive("DARK_SHROUD"):     fill_mult *= 1.30
			if GameManager.has_gear_effect("SLOW_DETECT_SNEAK"): fill_mult *= 1.30
			if GameManager.has_gear_effect("SET_SHADOW"):  fill_mult *= 1.40
		if GameManager.get_guild_unlock("SHADOW_GUILD"):   fill_mult *= 1.20
		if GameManager.has_passive("HALFLING_SLOW_DETECT"): fill_mult *= 1.20
		if GameManager.has_gear_effect("SET_THIEF"):       fill_mult *= 1.15
		fill_mult /= GameManager.get_wanted_detection_mult()
		# Dark zone: player near snuffed torch is harder to detect
		for tn in get_tree().get_nodes_in_group("torches"):
			if not tn.get("is_lit") and player.global_position.distance_to(tn.global_position) <= 48.0:
				fill_mult *= 1.65   # detection fills ~40% slower in darkness
				break
		detection_progress = min(1.0, detection_progress + delta * (1.0 / rate) / fill_mult)
		if detection_progress > 0.5 and not _detect_tick_played:
			_detect_tick_played = true
			AudioManager.detect_tick()
			if is_boss and not _boss_summoned_once:
				_boss_summoned_once = true
				_boss_summon_backup()
		if detection_progress >= 1.0:
			detection_progress = 0.0
			_escalate_alert()
	else:
		var drain_mult := 1.0
		# FAST_RESET: detection drains 2× faster after hiding
		if GameManager.has_gear_effect("FAST_RESET") and player != null:
			var p_hidden: bool = player.get("is_hidden") == true
			if p_hidden: drain_mult = 2.0
		# SHADOW set bonus: resets instantly on LoS break
		if GameManager.has_gear_effect("SET_SHADOW"):
			detection_progress = 0.0
		else:
			detection_progress = max(0.0, detection_progress - delta * DETECT_DRAIN_RATE * drain_mult)
		if detection_progress < 0.5:
			_detect_tick_played = false

func is_sneaking_player() -> bool:
	return player != null and player.get("is_sneaking") == true

func _update_de_escalation(delta):
	if alert_state == AlertState.UNAWARE:
		return
	# CRACKDOWN: guards never de-escalate
	if GameManager.run_modifier == "CRACKDOWN":
		return
	de_escalate_timer -= delta
	if de_escalate_timer > 0.0:
		return
	match alert_state:
		AlertState.ALERT:
			alert_state = AlertState.SUSPICIOUS
			# Linger at last known position before giving up
			if player:
				investigate_pos = player.global_position
			investigate_delay_ticks = INVESTIGATE_DELAY * 2
			de_escalate_timer = SUSPICIOUS_TIMEOUT
			_popup("...", Color(1.0, 0.75, 0.20))
		AlertState.SUSPICIOUS:
			alert_state = AlertState.UNAWARE
			investigate_pos = Vector2.ZERO
			detection_progress = 0.0
			patrol_wait = 1.2  # longer pause before resuming patrol

func _do_patrol_shift():
	# Rotate patrol waypoints by half — creates a shift-change effect
	if _original_patrol.size() < 2:
		return
	var half := _original_patrol.size() / 2
	var shifted: Array[Vector2] = []
	for i in range(_original_patrol.size()):
		shifted.append(_original_patrol[(i + half) % _original_patrol.size()])
	patrol_points = shifted
	patrol_index = 0
	patrol_wait  = 2.0  # Brief pause at shift change
	_popup("...", Color(0.55, 0.55, 0.45))

func _check_guard_conversation():
	# If another guard is within 12px, pause for a brief "conversation"
	if _convo_timer > 0.0 or alert_state != AlertState.UNAWARE:
		return
	for g in get_tree().get_nodes_in_group("guards"):
		if g == self:
			continue
		if global_position.distance_to(g.global_position) <= 14.0:
			# Only start a conversation if the other guard isn't already conversing
			if g.get("_convo_timer") != null and float(g.get("_convo_timer")) <= 0.0:
				_convo_timer = 2.8
				patrol_wait  = 2.8

func _update_patrol(delta):
	if patrol_points.is_empty():
		# Sentinel: stand still and rotate vision cone on a timer
		move_timer -= delta
		if move_timer <= 0.0:
			move_timer = 1.8
			if facing == Vector2.RIGHT:        facing = Vector2.DOWN
			elif facing == Vector2.DOWN:       facing = Vector2.LEFT
			elif facing == Vector2.LEFT:       facing = Vector2.UP
			else:                              facing = Vector2.RIGHT
		return
	if patrol_wait > 0.0:
		patrol_wait -= delta
		return
	move_timer -= delta
	if move_timer > 0.0:
		return

	if alert_state == AlertState.SUSPICIOUS and investigate_pos != Vector2.ZERO:
		if investigate_delay_ticks > 0:
			investigate_delay_ticks -= 1
			move_timer = move_interval
			return
		var diff: Vector2 = investigate_pos - position
		if diff.length() < 2.0:
			investigate_pos = Vector2.ZERO
			patrol_wait = 0.8
			return
		_step_toward(investigate_pos, _get_move_interval())
		return

	var target_world: Vector2 = patrol_points[patrol_index]
	var patrol_diff: Vector2 = target_world - position
	if patrol_diff.length() < 2.0:
		patrol_index = (patrol_index + 1) % patrol_points.size()
		patrol_wait = 0.5
		_check_guard_conversation()
		return
	_step_toward(target_world, _get_move_interval())

var _hit_cooldown := 0.0   # prevents rapid multi-hit from same guard
var _pre_attack_t := 0.0   # telegraph window before guard swings (parryable)

func _update_chase(delta):
	if player == null:
		return
	if _is_stunned:
		return
	# Telegraph countdown — fires attack when it expires
	if _pre_attack_t > 0.0:
		_pre_attack_t -= delta
		if _pre_attack_t <= 0.0:
			# Check if player successfully parried
			var player_parry: float = player.get("_parry_t") if player.get("_parry_t") != null else 0.0
			if player_parry > 0.0:
				# Parried! Signal the player to riposte
				if player.has_method("_parry_riposte"):
					player.call("_parry_riposte", self)
				_popup("PARRIED!", Color(0.35, 0.95, 0.55))
			else:
				# Hit lands
				var dmg := 3 if get("is_boss") == true else 2
				if player.has_method("take_damage_flash"):
					player.take_damage_flash()
				GameManager.take_damage(dmg)
				_popup("HIT -%d HP" % dmg, Color(1.0, 0.20, 0.20))
		queue_redraw()
		return
	_hit_cooldown = max(0.0, _hit_cooldown - delta)
	if global_position.distance_to(player.global_position) <= TILE_SIZE:
		if _hit_cooldown <= 0.0:
			_hit_cooldown = 1.4   # full cooldown (telegraph time + recovery)
			_pre_attack_t = 0.22  # 0.22s telegraph window — press attack to parry
		return
	move_timer -= delta
	if move_timer > 0.0:
		return
	_step_toward(player.global_position, _get_chase_interval())

func _step_toward(target_world: Vector2, interval: float):
	var diff: Vector2 = target_world - position
	var step := Vector2(sign(diff.x), 0) if abs(diff.x) >= abs(diff.y) else Vector2(0, sign(diff.y))
	var next_pos = position + step * TILE_SIZE
	if not _is_blocked(next_pos):
		facing = step
		position = next_pos
	move_timer = interval

func _check_bodies():
	if alert_state != AlertState.UNAWARE:
		return
	if enemy_type == EnemyType.SKELETON:
		return  # Undead don't notice dead comrades
	var half_angle := vision_angle / 2.0
	for body in get_tree().get_nodes_in_group("bodies"):
		if not is_instance_valid(body):
			continue
		if body.get_meta("being_carried", false):
			continue
		var to_body: Vector2 = body.global_position - global_position
		if to_body.length() > BODY_VISION_RANGE:
			continue
		if abs(rad_to_deg(facing.angle_to(to_body))) > half_angle:
			continue
		# Raycast — don't detect through walls
		var space := get_world_2d().direct_space_state
		var ray := PhysicsRayQueryParameters2D.create(global_position, body.global_position)
		ray.exclude = [self]
		var result := space.intersect_ray(ray)
		if result.is_empty():  # no wall between guard and body
			if _spotted_body != body:
				_spotted_body          = body
				_body_discovery_timer  = BODY_DISCOVERY_WINDOW
				investigate_pos        = body.global_position
				_become_suspicious(body.global_position)
				_popup("Is that…?  (%.0fs)" % BODY_DISCOVERY_WINDOW, Color(1.0, 0.75, 0.20))
			return

func _check_vision():
	_can_see_player = false
	if player == null:
		return
	# Hidden player cannot be seen
	if player.get("is_hidden") == true:
		return
	# Dodge roll i-frames: guard can't lock on during roll
	if player.get("_dodge_iframes") != null and float(player.get("_dodge_iframes")) > 0.0:
		return
	# Wood Elf vanish
	if GameManager._vanish_active:
		return
	# Smoke clouds block vision entirely
	for cloud in get_tree().get_nodes_in_group("smoke_clouds"):
		if cloud.has_method("contains"):
			if cloud.contains(global_position) or cloud.contains(player.global_position):
				return
	# Effective vision range: base + heat bonus - extinguished nearby torches
	var effective_range: float = vision_range + GameManager.floor_heat_level * 8.0
	for tn in get_tree().get_nodes_in_group("torches"):
		if not tn.get("is_lit") and global_position.distance_to(tn.global_position) <= 60.0:
			effective_range -= 25.0
	effective_range = max(20.0, effective_range)
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length() > effective_range:
		return
	if abs(rad_to_deg(facing.angle_to(to_player))) > vision_angle / 2.0:
		return

	var space = get_world_2d().direct_space_state
	var ray = PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	ray.exclude = [self]
	var result = space.intersect_ray(ray)

	if result.is_empty() or result.collider == player:
		_can_see_player = true
		investigate_pos = player.global_position
		de_escalate_timer = ALERT_TIMEOUT if alert_state == AlertState.ALERT else SUSPICIOUS_TIMEOUT

func _on_noise_emitted(level: int, world_position: Vector2):
	# Silence zone suppresses noise detection
	for zone in get_tree().get_nodes_in_group("silence_zones"):
		if zone.has_method("contains") and zone.contains(world_position):
			return
	var hear_range: float = HEARING_RANGE[level]
	if GameManager.run_modifier == "THIN_WALLS":
		hear_range += 40.0
	if hear_range == 0.0 or global_position.distance_to(world_position) > hear_range:
		return
	# Loud noise heard by an already-suspicious guard → escalate
	if level == 2 and alert_state == AlertState.SUSPICIOUS:
		_escalate_alert()
	else:
		_become_suspicious(world_position)

func _find_body(body_pos: Vector2):
	alert_state = AlertState.ALERT
	investigate_pos = body_pos
	de_escalate_timer = ALERT_TIMEOUT
	GameManager.floor_bodies_found += 1
	GameManager.record_alert()
	_popup("BODY!", Color(1.0, 0.12, 0.12))
	AudioManager.alert_blare()
	for g in get_tree().get_nodes_in_group("guards"):
		if g != self and global_position.distance_to(g.global_position) <= 120.0:
			if g.has_method("_become_suspicious"):
				g._become_suspicious(body_pos)

func _become_suspicious(toward: Vector2):
	if alert_state == AlertState.ALERT:
		# Already alert — just update investigation target
		investigate_pos = toward
		de_escalate_timer = max(de_escalate_timer, ALERT_TIMEOUT * 0.5)
		return
	if alert_state == AlertState.SUSPICIOUS:
		# Update target and refresh timer
		investigate_pos = toward
		investigate_delay_ticks = INVESTIGATE_DELAY
		de_escalate_timer = SUSPICIOUS_TIMEOUT
		return
	alert_state = AlertState.SUSPICIOUS
	investigate_pos = toward
	investigate_delay_ticks = INVESTIGATE_DELAY
	de_escalate_timer = SUSPICIOUS_TIMEOUT
	_popup("?", Color(1.0, 0.88, 0.10))

func _escalate_alert():
	match alert_state:
		AlertState.UNAWARE:
			_become_suspicious(player.global_position if player else Vector2.ZERO)
		AlertState.SUSPICIOUS:
			alert_state = AlertState.ALERT
			de_escalate_timer = ALERT_TIMEOUT
			GameManager.record_alert()
			AudioManager.alert_blare()
			var alarm_pos := player.global_position if player else global_position
			# Goblin scream: alerts EVERY guard on the floor
			if enemy_type == EnemyType.GOBLIN:
				_popup("SHRIEK!", Color(1.0, 0.65, 0.0))
				AudioManager.goblin_shriek()
				for g in get_tree().get_nodes_in_group("guards"):
					if g != self and g.has_method("_become_suspicious"):
						g._become_suspicious(alarm_pos)
			else:
				_popup("!", Color(1.0, 0.10, 0.10))
				# Radio guards: nearby suspicious → chain escalate, wider range → suspicious
				for g in get_tree().get_nodes_in_group("guards"):
					if g == self:
						continue
					var dist := global_position.distance_to(g.global_position)
					if dist <= 80.0 and g.has_method("_escalate_alert") \
							and g.get("alert_state") == AlertState.SUSPICIOUS:
						g._escalate_alert()
					elif dist <= 180.0 and g.has_method("_become_suspicious"):
						g._become_suspicious(alarm_pos)
			# Panic lockdown: if 2+ guards in same room are now ALERT, alert all roommates
			_check_panic_lockdown(alarm_pos)

func _check_panic_lockdown(alarm_pos: Vector2):
	var level_map = get_tree().get_first_node_in_group("levelmap")
	if level_map == null:
		return
	var my_tile := Vector2i(int(global_position.x / 16), int(global_position.y / 16))
	var my_room: int = level_map._tile_to_room(my_tile) if level_map.has_method("_tile_to_room") else -1
	if my_room < 0:
		return
	var alerted_count := 0
	for g in get_tree().get_nodes_in_group("guards"):
		if not is_instance_valid(g):
			continue
		var groom: int = level_map._tile_to_room(
			Vector2i(int(g.global_position.x / 16), int(g.global_position.y / 16)))
		if groom == my_room and g.get("alert_state") == AlertState.ALERT:
			alerted_count += 1
	if alerted_count >= 2:
		for g in get_tree().get_nodes_in_group("guards"):
			if not is_instance_valid(g) or g == self:
				continue
			var groom: int = level_map._tile_to_room(
				Vector2i(int(g.global_position.x / 16), int(g.global_position.y / 16)))
			if groom == my_room and g.get("alert_state") != AlertState.ALERT:
				if g.has_method("_escalate_alert"):
					g._escalate_alert()

func start_patrol_preview():
	if not patrol_points.is_empty():
		_path_preview_t = _PATH_PREVIEW_DUR
		queue_redraw()

func resist_takedown():
	alert_state = AlertState.ALERT
	de_escalate_timer = ALERT_TIMEOUT
	GameManager.record_alert()

func apply_hold(duration: float):
	_is_held    = true
	_held_timer = duration
	_popup("HELD!", Color(0.40, 0.60, 1.0))
	AudioManager.hold_person()

func apply_stun(duration: float):
	_is_stunned  = true
	_stun_timer  = duration
	_popup("STUNNED", Color(0.80, 0.60, 0.20))

func stagger(duration: float):
	_is_stunned = true
	_stun_timer = duration
	_popup("STAGGERED", Color(0.90, 0.55, 0.15))

func hurt(damage: int, hit_dir: Vector2 = Vector2.ZERO):
	guard_hp -= damage
	_hurt_flash_t = 0.22

	# Knockback twitch away from hit direction
	if hit_dir != Vector2.ZERO:
		_knockback_dir  = hit_dir.normalized()
		_knockback_t    = _KNOCKBACK_DUR
	elif player != null:
		var away: Vector2 = (global_position - player.global_position).normalized()
		_knockback_dir  = away
		_knockback_t    = _KNOCKBACK_DUR

	stagger(0.30)
	_escalate_alert()

	# Spawn damage number
	var dmg_script = load("res://DamageNumber.gd")
	var dmg_node   := Node2D.new()
	dmg_node.set_script(dmg_script)
	get_tree().root.add_child(dmg_node)
	dmg_node.global_position = global_position + Vector2(randf_range(-4.0, 4.0), -14.0)
	var dmg_col: Color = Color(1.0, 0.20, 0.20) if guard_hp > 0 else Color(1.0, 0.90, 0.20)
	dmg_node.setup(damage, dmg_col)

	# Hit sparks at impact point
	var spark_script = load("res://HitSpark.gd")
	var spark_node   := Node2D.new()
	spark_node.set_script(spark_script)
	get_tree().root.add_child(spark_node)
	spark_node.global_position = global_position
	var spark_col: Color = Color(1.0, 0.65, 0.20)
	spark_node.setup(spark_col, _knockback_dir)

	queue_redraw()
	if guard_hp <= 0:
		takedown(false)

func takedown(attacker_is_sneaking: bool, is_dart: bool = false):
	# Skeleton is immune to dart/soporific attacks
	if is_dart and enemy_type == EnemyType.SKELETON:
		_popup("NO EFFECT", Color(0.70, 0.70, 0.70))
		return
	if has_meta("is_marked"):
		remove_meta("is_marked")
	if is_captain:
		# Captain going down alerts all nearby guards
		for g in get_tree().get_nodes_in_group("guards"):
			if g != self and global_position.distance_to(g.global_position) <= 150.0:
				if g.has_method("_escalate_alert"):
					g._escalate_alert()
	if player:
		var noise_level = player.NoiseLevel.QUIET if (attacker_is_sneaking and alert_state == AlertState.UNAWARE) \
			else player.NoiseLevel.LOUD
		player.emit_noise(noise_level)
	if key_id >= 0 and player:
		player.add_key(key_id)
		_popup("KEY DROPPED!", Color(0.90, 0.75, 0.20))
	if is_boss:
		GameManager.record_boss_kill()
		_popup("%s ELIMINATED — +300gp" % GameManager.boss_name, Color(0.95, 0.78, 0.15))
		GameManager.shake(6.0, 0.5)
	_spawn_death_effects()
	_spawn_body()
	queue_free()

func _boss_summon_backup():
	_popup("%s calls for guards!" % GameManager.boss_name, Color(1.0, 0.30, 0.10))
	GameManager.shake(3.0, 0.3)
	# Alert all guards within 200px
	for g in get_tree().get_nodes_in_group("guards"):
		if g != self and global_position.distance_to(g.global_position) <= 200.0:
			if g.has_method("_escalate_alert"):
				g._escalate_alert()

func _popup(text: String, color: Color):
	var p := _dice_scene.instantiate()
	p.setup(text, color)
	p.global_position = global_position + Vector2(0, -22)
	get_tree().root.add_child(p)

func _spawn_death_effects():
	# Dropped weapon — player can pick it up
	if dropped_weapon != "NONE":
		var drop_script = load("res://DroppedWeapon.gd")
		var drop        := Node2D.new()
		drop.set_script(drop_script)
		get_tree().root.add_child(drop)
		drop.global_position = global_position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		drop.call("setup", dropped_weapon)

	# Blood pool — persists on the floor
	var pool_script = load("res://BloodPool.gd")
	var pool        := Node2D.new()
	pool.set_script(pool_script)
	get_tree().root.add_child(pool)
	pool.global_position = global_position

	# Death burst — radial explosion
	var burst_script = load("res://DeathBurst.gd")
	var burst        := Node2D.new()
	burst.set_script(burst_script)
	get_tree().root.add_child(burst)
	burst.global_position = global_position
	var bcol := Color(1.0, 0.20, 0.10) if not is_boss else Color(1.0, 0.55, 0.05)
	burst.setup(bcol)

func _spawn_body():
	var body := Node2D.new()
	body.set_script(_body_script)
	body.set_meta("body_facing", facing)
	# Roll loot, pre-compute display data so BodyMarker needs no LootSystem reference
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var raw_loot: Array[Dictionary] = LootSystem.roll_body_loot(is_captain, is_boss, GameManager.current_floor, rng)
	var display_loot: Array[Dictionary] = []
	for entry in raw_loot:
		var item_id: String = entry.get("id", "GOLD_PIECE")
		var cnt: int = entry.get("count", 1)
		if item_id == "GOLD_PIECE":
			display_loot.append({"id": "GOLD_PIECE", "count": cnt, "name": "Gold", "value": cnt, "color": Color(0.95, 0.80, 0.10)})
		else:
			var idata: Dictionary = LootSystem.get_item(item_id)
			var ival: int = LootSystem.get_item_value(item_id, GameManager.current_floor)
			var icol: Color = LootSystem.get_rarity_color(item_id)
			display_loot.append({"id": item_id, "count": cnt, "name": idata.get("name", item_id), "value": ival, "color": icol})
	body.set_meta("body_loot", display_loot)
	body.set_meta("body_looted", false)
	var scene := get_tree().current_scene
	scene.add_child(body)
	body.global_position = global_position

func _draw():
	var f    := facing.normalized()
	var perp2 := f.rotated(PI * 0.5)

	# ── SVG Guard body ────────────────────────────────────────────────────────
	_draw_guard_svg(f, perp2)

	var half_angle    := deg_to_rad(vision_angle / 2.0)
	var facing_angle  := facing.angle()
	var perp          := facing.rotated(PI * 0.5).normalized()

	# ── Patrol path preview — faint dotted route, fades over time ────────────
	if _path_preview_t > 0.0 and patrol_points.size() >= 2:
		var fade: float = _path_preview_t / _PATH_PREVIEW_DUR
		var col := Color(0.80, 0.72, 0.28, fade * 0.55)
		for i in range(patrol_points.size()):
			var from: Vector2 = patrol_points[i] - position
			var to: Vector2   = patrol_points[(i + 1) % patrol_points.size()] - position
			# Dashed line: draw short segments
			var seg_dir: Vector2 = (to - from).normalized()
			var total_len: float = from.distance_to(to)
			var drawn: float = 0.0
			while drawn < total_len:
				var seg_start := from + seg_dir * drawn
				var seg_end: Vector2 = from + seg_dir * min(drawn + 4.0, total_len)
				draw_line(seg_start, seg_end, col, 1.0)
				drawn += 8.0
		# Waypoint dots
		for wp in patrol_points:
			draw_circle(wp - position, 2.0, Color(0.95, 0.85, 0.35, fade * 0.70))

	# ── Footprint trail ────────────────────────────────────────────────────────
	for i in range(_footprints.size()):
		var fade := float(i + 1) / float(_footprints.size() + 1) * 0.18
		var fp := _footprints[i] - position
		draw_circle(fp, 1.8, Color(0.0, 0.0, 0.0, fade))

	# ── Vision cone — two-layer gradient look ─────────────────────────────────
	var cr: float; var cg: float; var cb: float
	match alert_state:
		AlertState.UNAWARE:    cr=0.95; cg=0.95; cb=0.20
		AlertState.SUSPICIOUS: cr=1.00; cg=0.55; cb=0.05
		AlertState.ALERT:      cr=1.00; cg=0.10; cb=0.10
	# Detection pulse — cone brightens as bar fills
	var detect_boost := detection_progress * 0.15
	var cone_pulse: float = abs(sin(_anim_t * 4.0)) * detection_progress * 0.06
	# Outer dim cone (1.15× range, low alpha)
	var outer_pts := [Vector2.ZERO]
	for i in range(17):
		var a := facing_angle - half_angle + (vision_angle / 16.0) * i * PI / 180.0
		outer_pts.append(Vector2(cos(a), sin(a)) * vision_range * 1.15)
	outer_pts.append(Vector2.ZERO)
	draw_colored_polygon(PackedVector2Array(outer_pts), Color(cr, cg, cb, 0.08 + detect_boost * 0.5))
	# Inner bright cone
	var inner_pts := [Vector2.ZERO]
	for i in range(13):
		var a := facing_angle - half_angle + (vision_angle / 12.0) * i * PI / 180.0
		inner_pts.append(Vector2(cos(a), sin(a)) * vision_range)
	inner_pts.append(Vector2.ZERO)
	var inner_alpha := 0.20 if alert_state == AlertState.UNAWARE else \
					  (0.32 if alert_state == AlertState.SUSPICIOUS else 0.44)
	draw_colored_polygon(PackedVector2Array(inner_pts), Color(cr, cg, cb, inner_alpha + detect_boost + cone_pulse))

	# ── Detection meter ────────────────────────────────────────────────────────
	if detection_progress > 0.0:
		var bw := 20.0; var bh := 3.0; var by := -22.0
		draw_rect(Rect2(-bw * 0.5, by, bw, bh), Color(0.08, 0.08, 0.08, 0.92))
		var fc := Color(0.95, 0.95, 0.1) if alert_state == AlertState.UNAWARE \
				  else Color(1.0, 0.42, 0.0)
		draw_rect(Rect2(-bw * 0.5, by, bw * detection_progress, bh), fc)
		draw_rect(Rect2(-bw * 0.5, by, bw, bh), Color(0.5, 0.5, 0.5, 0.5), false, 0.5)

	# ── Parry telegraph — orange ring flashes before guard swings ─────────────
	if _pre_attack_t > 0.0:
		var frac: float = _pre_attack_t / 0.22   # 1.0→0.0 as window closes
		var pulse_r := 10.0 + (1.0 - frac) * 4.0
		draw_arc(Vector2.ZERO, pulse_r, 0, TAU, 20,
			Color(1.0, 0.45, 0.0, 0.55 + frac * 0.35), 2.5)
		draw_arc(Vector2.ZERO, pulse_r - 2.0, 0, TAU, 16,
			Color(1.0, 0.75, 0.1, frac * 0.40), 1.0)

	# ── Hold Person / Stun overlay ─────────────────────────────────────────────
	if _is_held:
		draw_arc(Vector2.ZERO, 9.0, 0, TAU, 20, Color(0.40, 0.60, 1.0, 0.55 + abs(sin(_anim_t*4))*0.2), 2.5)
	if _is_stunned:
		draw_arc(Vector2.ZERO, 9.0, 0, TAU, 20, Color(0.90, 0.70, 0.15, 0.55 + abs(sin(_anim_t*6))*0.2), 2.5)

	# (body shadow is part of SVG drawing above)

	# ── Alert indicator — diamond glyph ────────────────────────────────────────
	if alert_state == AlertState.SUSPICIOUS:
		var dc := Color(1.0, 0.60, 0.0)
		var top := Vector2(0, -16); var bot := Vector2(0, -10)
		var lft := Vector2(-2.5, -13); var rgt := Vector2(2.5, -13)
		draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]), Color(dc.r, dc.g, dc.b, 0.28))
		draw_line(top, rgt, dc, 1.2); draw_line(rgt, bot, dc, 1.2)
		draw_line(bot, lft, dc, 1.2); draw_line(lft, top, dc, 1.2)
		draw_circle(Vector2(0, -13), 1.3, dc)
	elif alert_state == AlertState.ALERT:
		var dc := Color(1.0, 0.12, 0.12)
		var top := Vector2(0, -17); var bot := Vector2(0, -9)
		var lft := Vector2(-3.5, -13); var rgt := Vector2(3.5, -13)
		draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]), Color(dc.r, dc.g, dc.b, 0.32))
		draw_line(top, rgt, dc, 1.5); draw_line(rgt, bot, dc, 1.5)
		draw_line(bot, lft, dc, 1.5); draw_line(lft, top, dc, 1.5)
		draw_circle(Vector2(0, -13), 1.5, dc)

	# ── Gnoll scent radius ────────────────────────────────────────────────────
	if enemy_type == EnemyType.GNOLL:
		var smell_r := 52.0 + GameManager.floor_heat_level * 4.0
		draw_arc(Vector2.ZERO, smell_r, 0, TAU, 32,
			Color(0.62, 0.50, 0.22, 0.05 + abs(sin(_anim_t * 1.2)) * 0.04), 1.0)

	# ── Assassin's mark ────────────────────────────────────────────────────────
	if has_meta("is_marked") and get_meta("is_marked", false):
		draw_arc(Vector2.ZERO, 10.5, 0, TAU, 20, Color(1.0, 0.15, 0.15, 0.70), 2.5)
		var font2 := ThemeDB.fallback_font
		draw_string(font2, Vector2(-4, -29), "◎",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.20, 0.20, 0.95))

	# ── Boss distinction — pulsing red/gold crown with name tag ──────────────
	if is_boss:
		var pulse := sin(_anim_t * 2.5) * 0.5 + 0.5
		draw_arc(Vector2.ZERO, 10.0, 0, TAU, 28, Color(0.95, 0.50, 0.10, 0.45 + pulse * 0.35), 2.5)
		draw_arc(Vector2.ZERO, 11.5, 0, TAU, 28, Color(0.95, 0.78, 0.15, 0.20 + pulse * 0.20), 1.5)
		var font2 := ThemeDB.fallback_font
		var bname := GameManager.boss_name
		var tw: float = font2.get_string_size(bname, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(font2, Vector2(-tw * 0.5, -24), bname,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.65, 0.15, 0.95))

	# ── HP bar (only when damaged) ───────────────────────────────────────────
	if guard_hp < guard_max_hp:
		var bw := 20.0; var bh := 3.0; var by := -28.0
		draw_rect(Rect2(-bw * 0.5, by, bw, bh), Color(0.10, 0.08, 0.08, 0.92))
		var hp_frac := float(guard_hp) / float(guard_max_hp)
		var hp_col := Color(0.20, 0.85, 0.30) if hp_frac > 0.5 else \
					  (Color(0.95, 0.70, 0.10) if hp_frac > 0.25 else Color(0.95, 0.15, 0.15))
		draw_rect(Rect2(-bw * 0.5, by, bw * hp_frac, bh), hp_col)
		draw_rect(Rect2(-bw * 0.5, by, bw, bh), Color(0.5, 0.5, 0.5, 0.5), false, 0.5)

	# ── Hurt flash ───────────────────────────────────────────────────────────
	if _hurt_flash_t > 0.0:
		draw_rect(Rect2(-8, -18, 16, 20), Color(1.0, 0.20, 0.20, _hurt_flash_t / 0.18 * 0.45), true)

	# ── Captain distinction — gold aura and crown mark ────────────────────────
	if is_captain:
		draw_arc(Vector2.ZERO, 8.5, 0, TAU, 24, Color(0.95, 0.78, 0.15, 0.65), 2.0)
		draw_arc(Vector2.ZERO, 9.5, 0, TAU, 24, Color(0.95, 0.78, 0.15, 0.22), 1.0)


func _draw_guard_svg(f: Vector2, perp: Vector2):
	var t := _anim_t
	# Alert state colors
	var alert_tint := Color.WHITE
	if alert_state == AlertState.SUSPICIOUS:
		alert_tint = Color(1.0, 0.88, 0.60)
	elif alert_state == AlertState.ALERT:
		alert_tint = Color(1.0, 0.75, 0.72)
	var hurt_flash := _hurt_flash_t > 0.0
	if hurt_flash:
		alert_tint = Color(1.0, 0.38, 0.38)

	var moving := move_timer <= 0.04 or alert_state == AlertState.ALERT
	var leg_swing := sin(t * 11.0) * 2.0 if moving else 0.0
	var bob       := sin(t * 11.0) * 0.45 if moving else 0.0
	var scale     := 1.35 if is_boss else (1.18 if is_captain else 1.0)

	match enemy_type:
		EnemyType.HUMAN:
			_draw_human_svg(f, perp, t, leg_swing, bob, scale, alert_tint)
		EnemyType.SKELETON:
			_draw_skeleton_svg(f, perp, t, leg_swing, bob, scale, alert_tint)
		EnemyType.GOBLIN:
			_draw_goblin_svg(f, perp, t, leg_swing, bob, scale, alert_tint)
		EnemyType.GNOLL:
			_draw_gnoll_svg(f, perp, t, leg_swing, bob, scale, alert_tint)
		_:
			_draw_human_svg(f, perp, t, leg_swing, bob, scale, alert_tint)

func _draw_human_svg(f: Vector2, perp: Vector2, t: float, ls: float, bob: float, sc: float, tint: Color):
	var a := tint.a
	# Shadow
	draw_circle(Vector2(0.3, 1.5) * sc, 5.0 * sc, Color(0.0, 0.0, 0.0, 0.20))
	# Cape/tabard
	var cape_l := -f * 0.8 + perp * 4.0 * sc
	var cape_r := -f * 0.8 - perp * 4.0 * sc
	var cape_tip := -f * 9.5 * sc + Vector2(0, bob * 0.2)
	var tabard_col := Color(0.25, 0.30, 0.48)  # faction dark blue
	if alert_state == AlertState.ALERT: tabard_col = Color(0.48, 0.25, 0.25)
	draw_colored_polygon(PackedVector2Array([cape_l, cape_r, cape_tip]),
		Color(tabard_col.r * 0.55, tabard_col.g * 0.55, tabard_col.b * 0.60, 0.85))
	# Legs
	var leg_l := perp * 2.5 * sc + f * (-3.5 + ls * 0.3) + Vector2(0, bob)
	var leg_r := -perp * 2.5 * sc + f * (-3.5 - ls * 0.3) + Vector2(0, -bob)
	var boot_c := Color(0.22, 0.18, 0.12)
	draw_circle(leg_l + f * 1.2, 1.5 * sc, boot_c)
	draw_circle(leg_r + f * 1.2, 1.5 * sc, boot_c)
	draw_circle(leg_l, 1.8 * sc, boot_c.darkened(0.2))
	draw_circle(leg_r, 1.8 * sc, boot_c.darkened(0.2))
	# Body — chainmail + tabard
	var body := Vector2(0, bob * 0.2) * sc
	draw_circle(body, 4.8 * sc, Color(0.40, 0.38, 0.42))  # chainmail
	draw_colored_polygon(PackedVector2Array([
		body + f * 1.5 + perp * 2.5 * sc,
		body + f * 1.5 - perp * 2.5 * sc,
		body - f * 2.5 - perp * 2.2 * sc,
		body - f * 2.5 + perp * 2.2 * sc]),
		tabard_col)  # tabard overlay
	# Chainmail highlight
	draw_circle(body - f * 1.0 + perp * 1.0, 1.4 * sc, Color(0.65, 0.63, 0.68, 0.35))
	# Arms
	draw_circle(body + perp * 5.2 * sc, 1.5 * sc, Color(0.40, 0.38, 0.42))
	draw_circle(body - perp * 5.2 * sc, 1.5 * sc, Color(0.40, 0.38, 0.42))
	# Spear/weapon in leading hand
	var spear_base := body + perp * 5.5 * sc + f * 0.5
	draw_line(spear_base, spear_base + f * 9.0 * sc, Color(0.50, 0.38, 0.20), 1.2)
	draw_line(spear_base + f * 9.0 * sc, spear_base + f * 9.0 * sc + f * 2.5 * sc,
		Color(0.72, 0.70, 0.75), 1.6)  # spearhead
	# Helmet
	var head_p := f * 3.8 * sc + Vector2(0, bob * 0.4)
	draw_circle(head_p, 3.2 * sc, Color(0.48, 0.44, 0.50))  # helmet base
	draw_arc(head_p, 3.2 * sc, f.angle() - PI * 0.85, f.angle() + PI * 0.85, 12,
		Color(0.58, 0.54, 0.62), 1.8 * sc)  # helmet rim
	# Visor slit
	draw_line(head_p + f * 2.0 - perp * 1.5 * sc,
		head_p + f * 2.0 + perp * 1.5 * sc,
		Color(0.12, 0.10, 0.12, 0.80), 0.8)
	# Alert eye-glow through visor
	if alert_state == AlertState.ALERT:
		draw_line(head_p + f * 2.0 - perp * 1.2 * sc,
			head_p + f * 2.0 + perp * 1.2 * sc,
			Color(1.0, 0.28, 0.08, 0.80), 0.7)
	# Helmet plume (Captain/Boss distinction)
	if is_captain or is_boss:
		var plume_col := Color(0.85, 0.65, 0.10) if is_boss else Color(0.82, 0.18, 0.18)
		for i in range(3):
			var pp := head_p + f * -0.5 - perp * (1.0 - i * 1.0) * sc
			draw_line(pp, pp - f * 4.0 * sc + Vector2(0, -1.0 + sin(t * 6.0 + i) * 0.5),
				plume_col, 1.2)

func _draw_skeleton_svg(f: Vector2, perp: Vector2, t: float, ls: float, bob: float, sc: float, tint: Color):
	var bone_w := Color(0.88, 0.85, 0.78)
	var bone_d := Color(0.62, 0.58, 0.52)
	var eye_c  := Color(0.90, 0.15, 0.05) if alert_state == AlertState.ALERT else Color(0.22, 0.22, 0.32)
	# Shadow
	draw_circle(Vector2(0.3, 1.5) * sc, 4.5 * sc, Color(0.0, 0.0, 0.0, 0.18))
	# Legs (bones)
	var leg_l := perp * 2.2 * sc + f * (-3.2 + ls * 0.3) + Vector2(0, bob)
	var leg_r := -perp * 2.2 * sc + f * (-3.2 - ls * 0.3) + Vector2(0, -bob)
	draw_line(leg_l - f * 2.0, leg_l + f * 1.5, bone_d, 1.4)
	draw_line(leg_r - f * 2.0, leg_r + f * 1.5, bone_d, 1.4)
	draw_circle(leg_l + f * 1.5, 1.2 * sc, bone_w)
	draw_circle(leg_r + f * 1.5, 1.2 * sc, bone_w)
	# Ribcage
	var body := Vector2(0, bob * 0.18)
	draw_circle(body, 4.5 * sc, bone_d)
	# Rib lines
	for i in range(3):
		var rib_y := body + Vector2(0, (-1.2 + i * 1.3) * sc)
		draw_line(rib_y - perp * 3.5 * sc, rib_y + perp * 3.5 * sc, bone_w, 0.9)
	# Spine
	draw_line(body + f * 2.0, body - f * 4.0, bone_d, 1.0)
	# Arms (bone rods)
	var arm_l := body + perp * 5.0 * sc
	var arm_r := body - perp * 5.0 * sc
	draw_line(arm_l - f * 1.5, arm_l + f * 2.0, bone_w, 1.2)
	draw_line(arm_r - f * 1.5, arm_r + f * 2.0, bone_w, 1.2)
	draw_circle(arm_l + f * 2.0, 1.0 * sc, bone_w)
	draw_circle(arm_r + f * 2.0, 1.0 * sc, bone_w)
	# Skull
	var skull := f * 4.0 * sc + Vector2(0, bob * 0.35)
	draw_circle(skull, 3.4 * sc, bone_d)
	draw_circle(skull + f * 0.5, 3.0 * sc, bone_w)
	# Eye sockets
	var eye_l := skull + f * 1.8 + perp * 1.3 * sc
	var eye_r := skull + f * 1.8 - perp * 1.3 * sc
	draw_circle(eye_l, 1.0 * sc, Color(0.08, 0.06, 0.08))
	draw_circle(eye_r, 1.0 * sc, Color(0.08, 0.06, 0.08))
	draw_circle(eye_l, 0.55 * sc, eye_c)
	draw_circle(eye_r, 0.55 * sc, eye_c)
	# Jaw
	draw_arc(skull + f * 1.5, 2.0 * sc, f.angle() - 0.7, f.angle() + 0.7, 8, bone_d, 1.0)
	draw_line(skull + f * 1.5 + perp * 1.0 * sc, skull + f * 3.0 + perp * 0.8 * sc, bone_w, 0.7)
	draw_line(skull + f * 1.5 - perp * 1.0 * sc, skull + f * 3.0 - perp * 0.8 * sc, bone_w, 0.7)

func _draw_goblin_svg(f: Vector2, perp: Vector2, t: float, ls: float, bob: float, sc: float, tint: Color):
	var skin_g := Color(0.28, 0.52, 0.22)
	var leather := Color(0.35, 0.22, 0.10)
	# Shadow (small and hunched)
	draw_circle(Vector2(0.3, 1.0) * sc, 4.0 * sc, Color(0.0, 0.0, 0.0, 0.18))
	# Legs
	var leg_l := perp * 2.0 * sc + f * (-2.8 + ls * 0.4) + Vector2(0, bob)
	var leg_r := -perp * 2.0 * sc + f * (-2.8 - ls * 0.4) + Vector2(0, -bob)
	draw_circle(leg_l + f * 1.0, 1.4 * sc, skin_g.darkened(0.2))
	draw_circle(leg_r + f * 1.0, 1.4 * sc, skin_g.darkened(0.2))
	# Hunched body
	var body := f * 0.6 + Vector2(0, bob * 0.2)
	draw_circle(body, 4.2 * sc, leather.darkened(0.15))
	draw_circle(body + f * 0.5, 3.5 * sc, skin_g)
	draw_circle(body + f * 0.8 - f * 2.2, 2.0 * sc, skin_g.lightened(0.08))  # belly hump
	# Arms (long and dangling)
	draw_line(body + perp * 4.2 * sc - f * 1.0, body + perp * 3.5 * sc + f * 4.0, skin_g, 1.3)
	draw_line(body - perp * 4.2 * sc - f * 1.0, body - perp * 3.5 * sc + f * 4.0, skin_g, 1.3)
	draw_circle(body + perp * 3.5 * sc + f * 4.0, 1.2 * sc, skin_g.lightened(0.08))  # claws
	draw_circle(body - perp * 3.5 * sc + f * 4.0, 1.2 * sc, skin_g.lightened(0.08))
	# Big-eared head
	var head_p := f * 3.5 * sc + Vector2(0, bob * 0.3)
	draw_circle(head_p, 3.0 * sc, skin_g)
	# Big pointy ears
	draw_colored_polygon(PackedVector2Array([
		head_p + perp * 2.5 * sc,
		head_p + perp * 6.5 * sc + f * -1.0 * sc,
		head_p + perp * 2.8 * sc - f * 1.5 * sc]),
		skin_g.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([
		head_p - perp * 2.5 * sc,
		head_p - perp * 6.5 * sc + f * -1.0 * sc,
		head_p - perp * 2.8 * sc - f * 1.5 * sc]),
		skin_g.darkened(0.12))
	# Beady eyes
	draw_circle(head_p + f * 2.0 + perp * 1.0 * sc, 0.8 * sc, Color(0.08, 0.05, 0.05))
	draw_circle(head_p + f * 2.0 - perp * 1.0 * sc, 0.8 * sc, Color(0.08, 0.05, 0.05))
	var eye_c := Color(0.95, 0.22, 0.05) if alert_state == AlertState.ALERT else Color(0.85, 0.72, 0.18)
	draw_circle(head_p + f * 2.0 + perp * 1.0 * sc, 0.45 * sc, eye_c)
	draw_circle(head_p + f * 2.0 - perp * 1.0 * sc, 0.45 * sc, eye_c)
	# Fangs
	draw_line(head_p + f * 2.5 + perp * 0.5 * sc, head_p + f * 3.5 + perp * 0.3 * sc,
		Color(0.92, 0.88, 0.82), 0.8)
	draw_line(head_p + f * 2.5 - perp * 0.5 * sc, head_p + f * 3.5 - perp * 0.3 * sc,
		Color(0.92, 0.88, 0.82), 0.8)

func _draw_gnoll_svg(f: Vector2, perp: Vector2, t: float, ls: float, bob: float, sc: float, tint: Color):
	var fur_c   := Color(0.58, 0.42, 0.22)
	var fur_d   := Color(0.42, 0.28, 0.12)
	var leather := Color(0.32, 0.20, 0.08)
	# Shadow (large)
	draw_circle(Vector2(0.3, 2.0) * sc, 6.2 * sc, Color(0.0, 0.0, 0.0, 0.22))
	# Legs (powerful haunches)
	var leg_l := perp * 3.0 * sc + f * (-3.8 + ls * 0.3) + Vector2(0, bob)
	var leg_r := -perp * 3.0 * sc + f * (-3.8 - ls * 0.3) + Vector2(0, -bob)
	draw_circle(leg_l, 2.5 * sc, fur_d)
	draw_circle(leg_r, 2.5 * sc, fur_d)
	draw_circle(leg_l + f * 1.5, 1.8 * sc, fur_c)
	draw_circle(leg_r + f * 1.5, 1.8 * sc, fur_c)
	# Massive body
	var body := Vector2(0, bob * 0.2)
	draw_circle(body, 5.8 * sc, fur_d)
	draw_circle(body + f * 0.3, 5.2 * sc, fur_c)
	# Leather harness
	draw_arc(body, 5.0 * sc, 0, TAU, 16, leather, 1.5 * sc)
	draw_line(body - perp * 4.5 * sc + f * 1.0, body + perp * 4.5 * sc + f * 1.0, leather, 1.2)
	# Broad arms
	draw_circle(body + perp * 6.2 * sc, 2.2 * sc, fur_c)
	draw_circle(body - perp * 6.2 * sc, 2.2 * sc, fur_c)
	draw_circle(body + perp * 6.2 * sc + f * 2.0, 1.5 * sc, fur_d)  # clawed hand
	draw_circle(body - perp * 6.2 * sc + f * 2.0, 1.5 * sc, fur_d)
	# Canine head with snout
	var head_p := f * 4.5 * sc + Vector2(0, bob * 0.4)
	draw_circle(head_p, 3.8 * sc, fur_d)
	draw_circle(head_p + f * 0.3, 3.4 * sc, fur_c)
	# Elongated snout
	draw_colored_polygon(PackedVector2Array([
		head_p + f * 2.0 + perp * 1.8 * sc,
		head_p + f * 2.0 - perp * 1.8 * sc,
		head_p + f * 6.0 - perp * 1.0 * sc,
		head_p + f * 6.0 + perp * 1.0 * sc]),
		fur_c.darkened(0.12))
	# Nose
	draw_circle(head_p + f * 5.5, 1.0 * sc, Color(0.22, 0.12, 0.10))
	# Eyes (amber)
	var eye_c := Color(0.95, 0.22, 0.05) if alert_state == AlertState.ALERT else Color(0.88, 0.62, 0.12)
	draw_circle(head_p + f * 2.5 + perp * 1.5 * sc, 0.9 * sc, Color(0.05, 0.04, 0.04))
	draw_circle(head_p + f * 2.5 - perp * 1.5 * sc, 0.9 * sc, Color(0.05, 0.04, 0.04))
	draw_circle(head_p + f * 2.5 + perp * 1.5 * sc, 0.55 * sc, eye_c)
	draw_circle(head_p + f * 2.5 - perp * 1.5 * sc, 0.55 * sc, eye_c)
	# Ears (pointed)
	draw_colored_polygon(PackedVector2Array([
		head_p + perp * 3.0 * sc,
		head_p + perp * 5.5 * sc - f * 2.5 * sc,
		head_p + perp * 2.5 * sc - f * 1.5 * sc]),
		fur_c)
	draw_colored_polygon(PackedVector2Array([
		head_p - perp * 3.0 * sc,
		head_p - perp * 5.5 * sc - f * 2.5 * sc,
		head_p - perp * 2.5 * sc - f * 1.5 * sc]),
		fur_c)

func _is_blocked(target_pos: Vector2) -> bool:
	var space = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = target_pos
	query.exclude = [self]
	return space.intersect_point(query).size() > 0
