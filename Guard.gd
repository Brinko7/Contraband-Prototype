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

	# ── Vision cone — three-layer atmospheric gradient ─────────────────────────
	var cr: float; var cg: float; var cb: float
	var base_alpha: float
	var pulse_speed: float
	match alert_state:
		AlertState.UNAWARE:
			cr=0.85; cg=0.78; cb=0.45; base_alpha=0.03; pulse_speed=0.0
		AlertState.SUSPICIOUS:
			cr=0.90; cg=0.70; cb=0.15; base_alpha=0.07; pulse_speed=2.0
		AlertState.ALERT:
			cr=0.90; cg=0.15; cb=0.10; base_alpha=0.12; pulse_speed=5.0
		_:
			cr=0.95; cg=0.95; cb=0.20; base_alpha=0.05; pulse_speed=0.0
	var cone_extra_pulse: float = abs(sin(_anim_t * pulse_speed)) * base_alpha * 0.6 if pulse_speed > 0.0 else 0.0
	base_alpha += cone_extra_pulse
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
	match enemy_type:
		EnemyType.HUMAN:    _draw_human_svg(f, perp)
		EnemyType.SKELETON: _draw_skeleton_svg(f, perp)
		EnemyType.GOBLIN:   _draw_goblin_svg(f, perp)
		EnemyType.GNOLL:    _draw_gnoll_svg(f, perp)
		_:                  _draw_human_svg(f, perp)

# ─────────────────────────────────────────────────────────────────────────────
# SHARED ART HELPERS — isometric 3/4 perspective primitives
# ─────────────────────────────────────────────────────────────────────────────

func _iso_box(center: Vector2, f: Vector2, perp2: Vector2, fwd_size: float, side_size: float, height: float, base_col: Color):
	# 3-face isometric box: top (lightened), front (base), shadow side (darkened)
	var top: Vector2 = Vector2(0, -height)
	var front_bl: Vector2 = center + (-perp2 * side_size) + (f * fwd_size * 0.0)
	var front_br: Vector2 = center + (perp2 * side_size)
	var front_tl: Vector2 = front_bl + top
	var front_tr: Vector2 = front_br + top
	var back_tl: Vector2 = front_tl + (f * -fwd_size)
	var back_tr: Vector2 = front_tr + (f * -fwd_size)
	# Front face
	draw_colored_polygon(PackedVector2Array([front_bl, front_br, front_tr, front_tl]), base_col)
	# Top face (lightened)
	draw_colored_polygon(PackedVector2Array([front_tl, front_tr, back_tr, back_tl]), base_col.lightened(0.20))
	# Shadow side (always perp2-positive edge gets the shadow band)
	var shadow_col: Color = base_col.darkened(0.35)
	draw_line(front_br, front_tr, shadow_col, 1.2)

# ─────────────────────────────────────────────────────────────────────────────
# HUMAN — IRON GUARD
# Heavy armored medieval sentry. Chainmail, tabard, full helm, spear.
# ─────────────────────────────────────────────────────────────────────────────

func _draw_human_svg(f: Vector2, perp2: Vector2):
	var sc: float = 1.35 if is_boss else (1.18 if is_captain else 1.0)
	var moving: bool = move_timer <= 0.04 or alert_state == AlertState.ALERT
	var leg_swing: float = (sin(_anim_t * 7.0) * 2.0 * sc) if moving else 0.0
	var bob: float = (sin(_anim_t * 7.0) * 0.4 * sc) if moving else 0.0

	# 1. Ground shadow — elongated along facing
	var shadow_pts: PackedVector2Array = PackedVector2Array()
	for i in range(14):
		var a: float = float(i) / 14.0 * TAU
		var sx: float = cos(a) * 6.5 * sc
		var sy: float = sin(a) * 3.2 * sc
		shadow_pts.append(f * sx + perp2 * sy + Vector2(0.5, 2.0) * sc)
	draw_colored_polygon(shadow_pts, Color(0.0, 0.0, 0.0, 0.30))

	# Tabard color by alert state
	var tabard_col: Color = Color(0.28, 0.32, 0.42)
	if alert_state == AlertState.SUSPICIOUS:
		tabard_col = Color(0.45, 0.38, 0.18)
	elif alert_state == AlertState.ALERT:
		tabard_col = Color(0.65, 0.12, 0.12)

	var armor_col: Color = Color(0.25, 0.25, 0.28)
	var chain_col: Color = Color(0.35, 0.33, 0.38)
	var metal_pauld: Color = Color(0.30, 0.28, 0.34)

	# 2. Back armored leg
	var back_leg_top: Vector2 = -f * 0.5 - perp2 * 2.2 * sc + Vector2(0, -2.5 * sc)
	var back_leg_bot: Vector2 = -f * (1.5 + leg_swing * 0.3) - perp2 * 2.2 * sc + Vector2(0, 3.0 * sc + bob)
	_draw_armored_leg(back_leg_top, back_leg_bot, perp2, sc, armor_col.darkened(0.15))

	# 3. Hip + tabard skirt
	var hip_c: Vector2 = Vector2(0, -1.5 * sc) + Vector2(0, bob * 0.3)
	# Tabard skirt — two flaps
	var skirt_top_l: Vector2 = hip_c + perp2 * 2.5 * sc + Vector2(0, -0.5 * sc)
	var skirt_top_r: Vector2 = hip_c - perp2 * 2.5 * sc + Vector2(0, -0.5 * sc)
	var skirt_bot_l: Vector2 = hip_c + perp2 * 3.2 * sc + Vector2(0, 3.5 * sc)
	var skirt_bot_r: Vector2 = hip_c - perp2 * 3.2 * sc + Vector2(0, 3.5 * sc)
	var skirt_mid: Vector2 = hip_c + Vector2(0, 4.0 * sc)
	draw_colored_polygon(PackedVector2Array([skirt_top_l, skirt_mid, skirt_bot_l]),
		tabard_col.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([skirt_top_r, skirt_bot_r, skirt_mid]),
		tabard_col.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([skirt_top_l, skirt_top_r, skirt_mid]),
		tabard_col)

	# 4. Torso — chainmail isometric box
	var torso_c: Vector2 = Vector2(0, -5.5 * sc) + Vector2(0, bob * 0.4)
	_draw_human_torso(torso_c, f, perp2, sc, chain_col, tabard_col)

	# 5. Front armored leg
	var front_leg_top: Vector2 = f * 0.5 + perp2 * 2.2 * sc + Vector2(0, -2.5 * sc)
	var front_leg_bot: Vector2 = f * (1.5 - leg_swing * 0.3) + perp2 * 2.2 * sc + Vector2(0, 3.0 * sc - bob)
	_draw_armored_leg(front_leg_top, front_leg_bot, perp2, sc, armor_col)

	# 6. Shoulder pauldrons
	var shoulder_l: Vector2 = torso_c + perp2 * 3.8 * sc + Vector2(0, -2.5 * sc)
	var shoulder_r: Vector2 = torso_c - perp2 * 3.8 * sc + Vector2(0, -2.5 * sc)
	_draw_pauldron(shoulder_l, f, perp2, sc, metal_pauld, true)
	_draw_pauldron(shoulder_r, f, perp2, sc, metal_pauld.darkened(0.15), false)

	# 7. Arms
	# Off-hand arm (back / left)
	var hand_l: Vector2 = shoulder_l + perp2 * 0.5 * sc + Vector2(0, 4.0 * sc)
	draw_line(shoulder_l, hand_l, chain_col.darkened(0.15), 2.0 * sc)
	draw_circle(hand_l, 1.3 * sc, metal_pauld)
	# Spear hand (front / right)
	var hand_r: Vector2 = shoulder_r - perp2 * 0.2 * sc + Vector2(0, 3.5 * sc)
	draw_line(shoulder_r, hand_r, chain_col.darkened(0.15), 2.0 * sc)
	draw_circle(hand_r, 1.4 * sc, metal_pauld.darkened(0.15))

	# 8. Helmet
	var head_c: Vector2 = Vector2(0, -10.5 * sc) + Vector2(0, bob * 0.5)
	_draw_human_helmet(head_c, f, perp2, sc, tabard_col)

	# 9. Spear in front hand
	_draw_spear(hand_r, f, perp2, sc)

	# 10. Alert aura
	if alert_state == AlertState.ALERT:
		var pulse_r: float = (8.0 + sin(_anim_t * 5.0) * 1.2) * sc
		draw_arc(head_c, pulse_r, 0, TAU, 20,
			Color(1.0, 0.12, 0.08, 0.20 + sin(_anim_t * 5.0) * 0.10), 1.8)

func _draw_armored_leg(top: Vector2, bot: Vector2, perp2: Vector2, sc: float, col: Color):
	var w_top: float = 1.6 * sc
	var w_bot: float = 1.2 * sc
	var pts := PackedVector2Array([
		top + perp2 * w_top,
		top - perp2 * w_top,
		bot - perp2 * w_bot,
		bot + perp2 * w_bot,
	])
	draw_colored_polygon(pts, col)
	# Top highlight
	draw_line(top + perp2 * w_top, top - perp2 * w_top, col.lightened(0.25), 0.8)
	# Shadow side
	draw_line(top - perp2 * w_top, bot - perp2 * w_bot, col.darkened(0.40), 0.6)
	# Boot
	var boot_pts := PackedVector2Array([
		bot + perp2 * w_bot * 1.4,
		bot - perp2 * w_bot * 1.4,
		bot - perp2 * w_bot * 1.4 + Vector2(0, 1.5 * sc),
		bot + perp2 * w_bot * 1.6 + Vector2(0, 1.5 * sc),
	])
	draw_colored_polygon(boot_pts, Color(0.16, 0.12, 0.08))
	draw_line(boot_pts[0], boot_pts[1], Color(0.30, 0.22, 0.14), 0.6)

func _draw_human_torso(c: Vector2, f: Vector2, perp2: Vector2, sc: float, chain_col: Color, tabard_col: Color):
	var w: float = 4.0 * sc
	var h: float = 5.5 * sc
	# Front chainmail face
	var fl: Vector2 = c + Vector2(-w, h * 0.5)
	var fr: Vector2 = c + Vector2(w, h * 0.5)
	var tr: Vector2 = c + Vector2(w * 0.9, -h * 0.5)
	var tl: Vector2 = c + Vector2(-w * 0.9, -h * 0.5)
	draw_colored_polygon(PackedVector2Array([fl, fr, tr, tl]), chain_col)
	# Top face (shoulders)
	draw_colored_polygon(PackedVector2Array([
		tl, tr,
		tr + f * -2.0 * sc, tl + f * -2.0 * sc,
	]), chain_col.lightened(0.20))
	# Shadow side band
	draw_line(fr, tr, chain_col.darkened(0.40), 1.4)
	# Chainmail dots — texture pattern on front
	for ix in range(3):
		for iy in range(4):
			var dot: Vector2 = c + Vector2(-w * 0.55 + ix * w * 0.55, -h * 0.35 + iy * h * 0.22)
			draw_circle(dot, 0.45, chain_col.lightened(0.30))
	# Tabard front overlay — vertical strip
	var tab_w: float = w * 0.45
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-tab_w, h * 0.5),
		c + Vector2(tab_w, h * 0.5),
		c + Vector2(tab_w * 0.9, -h * 0.4),
		c + Vector2(-tab_w * 0.9, -h * 0.4),
	]), tabard_col)
	# Tabard centerline
	draw_line(c + Vector2(0, h * 0.5), c + Vector2(0, -h * 0.4), tabard_col.darkened(0.30), 0.5)
	# Trim — boss=gold, captain=silver
	if is_boss:
		var gold: Color = Color(0.88, 0.70, 0.18)
		draw_line(fl, fr, gold, 0.8)
		draw_line(tl, tr, gold, 0.6)
		draw_line(c + Vector2(-tab_w, h * 0.5), c + Vector2(-tab_w * 0.9, -h * 0.4), gold, 0.6)
		draw_line(c + Vector2(tab_w, h * 0.5), c + Vector2(tab_w * 0.9, -h * 0.4), gold, 0.6)
	elif is_captain:
		var silver: Color = Color(0.72, 0.70, 0.78)
		draw_line(fl, fr, silver, 0.7)
		draw_line(c + Vector2(-tab_w, h * 0.5), c + Vector2(-tab_w * 0.9, -h * 0.4), silver, 0.5)
		draw_line(c + Vector2(tab_w, h * 0.5), c + Vector2(tab_w * 0.9, -h * 0.4), silver, 0.5)

func _draw_pauldron(c: Vector2, f: Vector2, perp2: Vector2, sc: float, col: Color, is_lit: bool):
	var r: float = 2.2 * sc
	var pts := PackedVector2Array([
		c + Vector2(-r, 0.2 * sc),
		c + Vector2(-r * 0.7, -r * 0.9),
		c + Vector2(r * 0.4, -r),
		c + Vector2(r, -r * 0.3),
		c + Vector2(r * 0.8, r * 0.4),
	])
	draw_colored_polygon(pts, col)
	# Top highlight
	if is_lit:
		draw_line(pts[1], pts[2], col.lightened(0.35), 0.7)
		draw_line(pts[2], pts[3], col.lightened(0.20), 0.5)
	else:
		draw_line(pts[3], pts[4], col.darkened(0.30), 0.6)
	# Rivets
	draw_circle(c + Vector2(0, -r * 0.4), 0.4, col.lightened(0.45))
	draw_circle(c + Vector2(r * 0.4, r * 0.1), 0.35, col.darkened(0.30))

func _draw_human_helmet(c: Vector2, f: Vector2, perp2: Vector2, sc: float, tabard_col: Color):
	var helm_col: Color = Color(0.28, 0.26, 0.32)
	var w: float = 3.4 * sc
	var h: float = 4.2 * sc
	# Helmet base — front face
	var fl: Vector2 = c + Vector2(-w, h * 0.5)
	var fr: Vector2 = c + Vector2(w, h * 0.5)
	var tr: Vector2 = c + Vector2(w * 0.85, -h * 0.5)
	var tl: Vector2 = c + Vector2(-w * 0.85, -h * 0.5)
	draw_colored_polygon(PackedVector2Array([fl, fr, tr, tl]), helm_col)
	# Top face
	draw_colored_polygon(PackedVector2Array([
		tl, tr,
		tr + Vector2(-0.8 * sc, -1.3 * sc),
		tl + Vector2(0.8 * sc, -1.3 * sc),
	]), helm_col.lightened(0.20))
	# Shadow side
	draw_line(fr, tr, helm_col.darkened(0.40), 1.2)
	# Visor slit
	var visor_y: float = c.y + h * 0.0
	draw_rect(Rect2(c.x - w * 0.75, visor_y - 0.6, w * 1.5, 1.2),
		Color(0.06, 0.06, 0.08))
	# Glowing eyes inside visor
	var eye_col: Color
	match alert_state:
		AlertState.UNAWARE:
			eye_col = Color(0.65, 0.58, 0.20, 0.6)
		AlertState.SUSPICIOUS:
			var p: float = 0.9 + sin(_anim_t * 4.0) * 0.1
			eye_col = Color(0.90 * p, 0.55 * p, 0.10 * p, 0.95)
		AlertState.ALERT:
			eye_col = Color(1.0, 0.15, 0.10)
			# Outer glow arc
			draw_arc(c + Vector2(0, 0), w * 1.1, 0, TAU, 16,
				Color(1.0, 0.20, 0.10, 0.25 + sin(_anim_t * 6.0) * 0.10), 1.2)
		_:
			eye_col = Color(0.5, 0.5, 0.5)
	draw_circle(c + Vector2(-w * 0.45, visor_y - c.y), 0.55 * sc, eye_col)
	draw_circle(c + Vector2(w * 0.45, visor_y - c.y), 0.55 * sc, eye_col)
	# Brow ridge (lightened top of visor)
	draw_line(fl + Vector2(0.4, -0.4), fr + Vector2(-0.4, -0.4), helm_col.lightened(0.30), 0.6)
	# Captain plume
	if is_captain and not is_boss:
		var plume_col: Color = Color(0.82, 0.18, 0.18)
		var base: Vector2 = c + Vector2(0, -h * 0.5)
		for i in range(5):
			var t_p: float = float(i) / 4.0
			var sway: float = sin(_anim_t * 5.0 + t_p * 2.0) * 1.5
			var p1: Vector2 = base + Vector2(sway * t_p, -t_p * 5.0 * sc)
			var p2: Vector2 = base + Vector2(sway * t_p - 0.8 * sc, -t_p * 5.0 * sc - 1.2 * sc)
			draw_line(p1, p2, plume_col, 1.6 - t_p)
			draw_line(p1, p2 + Vector2(1.6 * sc, 0), plume_col.darkened(0.20), 1.2 - t_p)
	# Boss crown
	if is_boss:
		var gold: Color = Color(0.92, 0.74, 0.18)
		var base: Vector2 = c + Vector2(0, -h * 0.5 - 0.6 * sc)
		# Three crown spikes
		for i in range(3):
			var off_x: float = (i - 1) * w * 0.55
			var spike := PackedVector2Array([
				base + Vector2(off_x - 0.8 * sc, 0),
				base + Vector2(off_x, -2.2 * sc),
				base + Vector2(off_x + 0.8 * sc, 0),
			])
			draw_colored_polygon(spike, gold)
			# Gem
			draw_circle(base + Vector2(off_x, -1.4 * sc), 0.5 * sc, Color(0.95, 0.15, 0.20))
		draw_line(base + Vector2(-w, 0), base + Vector2(w, 0), gold, 1.0)

func _draw_spear(hand: Vector2, f: Vector2, perp2: Vector2, sc: float):
	var shaft_col: Color = Color(0.42, 0.28, 0.14)
	var tip: Vector2 = hand + Vector2(0, -14.0 * sc)
	var butt: Vector2 = hand + Vector2(0, 4.0 * sc)
	# Shaft
	draw_line(butt, tip, shaft_col, 1.2)
	draw_line(butt + Vector2(0.4, 0), tip + Vector2(0.4, 0), shaft_col.lightened(0.20), 0.4)
	# Spearhead
	var head_col: Color = Color(0.72, 0.70, 0.78)
	var head_base: Vector2 = tip + Vector2(0, 2.0 * sc)
	var head_pts := PackedVector2Array([
		head_base + Vector2(-1.3 * sc, 0),
		tip + Vector2(0, -2.5 * sc),
		head_base + Vector2(1.3 * sc, 0),
		head_base,
	])
	draw_colored_polygon(head_pts, head_col)
	draw_line(head_pts[0], head_pts[1], head_col.lightened(0.35), 0.5)
	draw_line(head_pts[1], head_pts[2], head_col.darkened(0.30), 0.5)
	# Cross-guard
	draw_line(head_base + Vector2(-1.5 * sc, 0), head_base + Vector2(1.5 * sc, 0), Color(0.55, 0.42, 0.18), 0.6)
	# Butt cap
	draw_circle(butt, 0.7 * sc, Color(0.55, 0.42, 0.18))

# ─────────────────────────────────────────────────────────────────────────────
# SKELETON — UNDEAD GUARD
# Visible ribs, hollow eye sockets with eerie glow, tattered armor scraps.
# ─────────────────────────────────────────────────────────────────────────────

func _draw_skeleton_svg(f: Vector2, perp2: Vector2):
	var sc: float = 1.0
	var bone_col: Color = Color(0.85, 0.82, 0.72)
	var bone_dark: Color = Color(0.62, 0.58, 0.48)
	var moving: bool = move_timer <= 0.04 or alert_state == AlertState.ALERT
	var rattle: float = 0.5 if moving else 0.2

	# Independent jitter per limb
	var rattle_l: Vector2 = Vector2(sin(_anim_t * 13.5) * rattle, cos(_anim_t * 11.2) * rattle * 0.6)
	var rattle_r: Vector2 = Vector2(cos(_anim_t * 12.1) * rattle, sin(_anim_t * 14.7) * rattle * 0.6)
	var rattle_h: Vector2 = Vector2(sin(_anim_t * 9.3) * rattle * 0.4, cos(_anim_t * 7.5) * rattle * 0.4)

	# 1. Faint shadow
	var shadow_pts: PackedVector2Array = PackedVector2Array()
	for i in range(12):
		var a: float = float(i) / 12.0 * TAU
		shadow_pts.append(Vector2(cos(a) * 5.0, sin(a) * 2.4) + Vector2(0.3, 2.0))
	draw_colored_polygon(shadow_pts, Color(0.0, 0.0, 0.0, 0.18))

	# Spine anchor (center reference)
	var spine_bot: Vector2 = Vector2(0, 1.0) + rattle_h * 0.3
	var spine_top: Vector2 = Vector2(0, -7.5) + rattle_h * 0.5

	# 2. Bare leg bones
	_draw_skeleton_leg(Vector2(-1.8, -1.0) + rattle_l, Vector2(-2.2, 5.5) + rattle_l, bone_col, bone_dark)
	_draw_skeleton_leg(Vector2(1.8, -1.0) + rattle_r, Vector2(2.2, 5.5) + rattle_r, bone_col, bone_dark)

	# 3. Pelvis
	var pelvis_pts := PackedVector2Array([
		Vector2(-2.5, -2.0) + spine_bot,
		Vector2(2.5, -2.0) + spine_bot,
		Vector2(1.8, 0.5) + spine_bot,
		Vector2(-1.8, 0.5) + spine_bot,
	])
	draw_colored_polygon(pelvis_pts, bone_col)
	draw_line(pelvis_pts[0], pelvis_pts[1], bone_col.lightened(0.20), 0.6)
	# Pelvic gap
	draw_line(spine_bot + Vector2(0, -1.5), spine_bot + Vector2(0, 0.3), bone_dark.darkened(0.30), 0.6)

	# 4. RIBCAGE
	var spine_center: Vector2 = (spine_bot + spine_top) * 0.5
	_draw_skeleton_ribs(spine_center, bone_col, bone_dark)

	# Spine column
	for i in range(6):
		var sy: float = lerp(spine_top.y, spine_bot.y, float(i) / 5.0)
		draw_circle(Vector2(spine_center.x, sy), 0.6, bone_col)
		draw_line(Vector2(spine_center.x - 0.7, sy), Vector2(spine_center.x + 0.7, sy), bone_dark, 0.4)

	# 5. Shoulder girdle (clavicles)
	var neck: Vector2 = spine_top + Vector2(0, 0.5)
	draw_line(neck, neck + Vector2(-4.2, 0.3), bone_col, 1.0)
	draw_line(neck, neck + Vector2(4.2, 0.3), bone_col, 1.0)
	draw_circle(neck + Vector2(-4.2, 0.3), 0.7, bone_col)
	draw_circle(neck + Vector2(4.2, 0.3), 0.7, bone_col)

	# Decayed armor scrap on shoulder (one side only)
	var scrap_col: Color = Color(0.28, 0.26, 0.30)
	draw_colored_polygon(PackedVector2Array([
		neck + Vector2(-5.2, -0.5),
		neck + Vector2(-2.8, -1.0),
		neck + Vector2(-2.5, 1.4),
		neck + Vector2(-5.4, 1.0),
	]), scrap_col)
	draw_line(neck + Vector2(-5.2, -0.5), neck + Vector2(-2.8, -1.0), scrap_col.lightened(0.20), 0.4)

	# 6. Arm bones
	_draw_skeleton_arm(neck + Vector2(-4.2, 0.3) + rattle_l * 0.5, true, bone_col, bone_dark)
	_draw_skeleton_arm(neck + Vector2(4.2, 0.3) + rattle_r * 0.5, false, bone_col, bone_dark)

	# Cracked chestplate fragment
	draw_colored_polygon(PackedVector2Array([
		spine_center + Vector2(-2.5, -2.5),
		spine_center + Vector2(2.8, -1.8),
		spine_center + Vector2(2.0, 1.0),
		spine_center + Vector2(-1.5, 0.5),
		spine_center + Vector2(-2.8, -0.5),
	]), scrap_col.darkened(0.10))
	# Crack lines
	draw_line(spine_center + Vector2(-1.0, -2.2), spine_center + Vector2(0.5, 0.8), Color(0.10, 0.08, 0.08), 0.5)
	draw_line(spine_center + Vector2(1.2, -1.5), spine_center + Vector2(0.8, -0.3), Color(0.10, 0.08, 0.08), 0.4)

	# Tattered cloth scraps
	var cloth_col: Color = Color(0.35, 0.30, 0.20, 0.65)
	for i in range(3):
		var ox: float = (i - 1) * 2.0
		var sway: float = sin(_anim_t * 1.8 + float(i)) * 0.8
		draw_colored_polygon(PackedVector2Array([
			spine_center + Vector2(ox - 0.8, 1.5),
			spine_center + Vector2(ox + 0.8, 1.5),
			spine_center + Vector2(ox + 0.5 + sway, 4.5),
			spine_center + Vector2(ox - 0.6 + sway, 4.5),
		]), cloth_col)

	# 7. Skull
	var skull_pos: Vector2 = spine_top + Vector2(0, -5.5) + rattle_h
	_draw_skeleton_skull(skull_pos, bone_col, bone_dark)

	# 9. Rusty sword in right hand
	var hand_r: Vector2 = neck + Vector2(4.2, 0.3) + Vector2(2.5, 4.0) + rattle_r * 0.5
	_draw_rusty_sword(hand_r)

func _draw_skeleton_leg(hip: Vector2, ankle: Vector2, bone_col: Color, bone_dark: Color):
	var knee: Vector2 = (hip + ankle) * 0.5 + Vector2(sign(hip.x) * 0.3, 0)
	# Femur
	draw_line(hip, knee, bone_col, 1.5)
	# Knee joint
	draw_circle(knee, 1.1, bone_col)
	draw_circle(knee + Vector2(-0.3, -0.3), 0.4, bone_col.lightened(0.30))
	# Tibia
	draw_line(knee, ankle, bone_dark, 1.2)
	# Foot — L-shape
	var foot_pts := PackedVector2Array([
		ankle + Vector2(-0.6, 0),
		ankle + Vector2(0.6, 0),
		ankle + Vector2(2.0, 1.0),
		ankle + Vector2(2.0, 1.8),
		ankle + Vector2(-0.4, 1.5),
	])
	draw_colored_polygon(foot_pts, bone_col)
	draw_line(foot_pts[0], foot_pts[1], bone_col.lightened(0.20), 0.4)

func _draw_skeleton_arm(shoulder: Vector2, is_left: bool, bone_col: Color, bone_dark: Color):
	var side: float = -1.0 if is_left else 1.0
	var elbow: Vector2 = shoulder + Vector2(side * 1.2, 2.5)
	var wrist: Vector2 = shoulder + Vector2(side * 2.5, 4.0)
	draw_line(shoulder, elbow, bone_col, 1.2)
	draw_circle(elbow, 0.9, bone_col)
	draw_line(elbow, wrist, bone_dark, 1.0)
	# Hand — 3 phalanges
	for i in range(3):
		var fo: Vector2 = wrist + Vector2(side * (0.4 + i * 0.6), 0.6 + i * 0.3)
		draw_line(wrist, fo, bone_col, 0.6)
		draw_circle(fo, 0.35, bone_col)

func _draw_skeleton_ribs(spine_center: Vector2, bone_col: Color, bone_dark: Color):
	for i in range(5):
		var rib_y: float = -2.0 + float(i) * 1.4
		var rib_r: float = 3.0 + float(i) * 0.2
		var center: Vector2 = spine_center + Vector2(0, rib_y)
		# Dark gap behind rib (depth)
		draw_arc(center, rib_r - 0.4, PI * 0.55, PI * 1.05, 6,
			Color(0.20, 0.18, 0.16, 0.5), 1.6)
		draw_arc(center, rib_r - 0.4, -PI * 0.05, PI * 0.45, 6,
			Color(0.20, 0.18, 0.16, 0.5), 1.6)
		# Bright rib
		draw_arc(center, rib_r, PI * 0.55, PI * 1.05, 6, bone_col, 1.2)
		draw_arc(center, rib_r, -PI * 0.05, PI * 0.45, 6, bone_col, 1.2)

func _draw_skeleton_skull(c: Vector2, bone_col: Color, bone_dark: Color):
	# Cranium
	draw_circle(c, 4.5, bone_col)
	# Highlight (top-left)
	draw_circle(c + Vector2(-1.3, -1.5), 2.2, bone_col.lightened(0.25))
	# Shadow side arc
	draw_arc(c, 4.5, -PI * 0.1, PI * 0.6, 8, bone_col.darkened(0.30), 0.8)
	# Jaw — open death grin
	var jaw_pts := PackedVector2Array([
		c + Vector2(-2.8, 1.0),
		c + Vector2(2.8, 1.0),
		c + Vector2(2.2, 3.5),
		c + Vector2(-2.2, 3.5),
	])
	draw_colored_polygon(jaw_pts, bone_col.darkened(0.10))
	draw_line(jaw_pts[2], jaw_pts[3], bone_dark.darkened(0.30), 0.5)
	# Dark mouth gap
	draw_rect(Rect2(c.x - 2.4, c.y + 1.2, 4.8, 1.4), Color(0.06, 0.05, 0.06))
	# Teeth — 5 small rectangles
	for i in range(5):
		var tx: float = c.x - 2.0 + float(i) * 1.0
		draw_rect(Rect2(tx, c.y + 1.3, 0.7, 1.0), Color(0.92, 0.88, 0.78))
	# Nose cavity
	var nose := PackedVector2Array([
		c + Vector2(0, -0.5),
		c + Vector2(-0.8, 0.7),
		c + Vector2(0.8, 0.7),
	])
	draw_colored_polygon(nose, Color(0.06, 0.05, 0.06))
	# Eye sockets
	draw_circle(c + Vector2(-1.7, -1.0), 1.4, Color(0.05, 0.04, 0.05))
	draw_circle(c + Vector2(1.7, -1.0), 1.4, Color(0.05, 0.04, 0.05))
	# Glowing pupils
	var eye_col: Color
	match alert_state:
		AlertState.UNAWARE:
			eye_col = Color(0.2, 0.4, 0.8, 0.6)
		AlertState.SUSPICIOUS:
			eye_col = Color(0.15, 0.85, 0.95)
		AlertState.ALERT:
			eye_col = Color(0.05, 1.0, 0.3)
			# Outer glow
			draw_arc(c + Vector2(-1.7, -1.0), 2.4, 0, TAU, 14,
				Color(0.10, 1.0, 0.30, 0.30 + sin(_anim_t * 6.0) * 0.10), 1.2)
			draw_arc(c + Vector2(1.7, -1.0), 2.4, 0, TAU, 14,
				Color(0.10, 1.0, 0.30, 0.30 + sin(_anim_t * 6.0) * 0.10), 1.2)
		_:
			eye_col = Color(0.3, 0.5, 0.6)
	draw_circle(c + Vector2(-1.7, -1.0), 0.7, eye_col)
	draw_circle(c + Vector2(1.7, -1.0), 0.7, eye_col)
	# Cranial suture line
	draw_line(c + Vector2(-2.5, -2.5), c + Vector2(2.5, -2.5), bone_dark, 0.4)
	draw_line(c + Vector2(0, -4.0), c + Vector2(0, -2.3), bone_dark, 0.4)

func _draw_rusty_sword(hand: Vector2):
	var rust_col: Color = Color(0.55, 0.30, 0.12)
	var tip: Vector2 = hand + Vector2(0, -12.0)
	# Blade
	var blade_pts := PackedVector2Array([
		hand + Vector2(-0.9, 0),
		hand + Vector2(0.9, 0),
		tip + Vector2(0.4, 0),
		tip,
		tip + Vector2(-0.4, 0),
	])
	draw_colored_polygon(blade_pts, rust_col)
	# Blade highlight
	draw_line(hand + Vector2(0, -0.5), tip + Vector2(0, 0.5), rust_col.lightened(0.30), 0.5)
	# Rust streaks
	draw_line(hand + Vector2(-0.4, -3.0), hand + Vector2(-0.5, -7.5), rust_col.darkened(0.30), 0.4)
	draw_line(hand + Vector2(0.5, -2.0), hand + Vector2(0.3, -6.0), rust_col.darkened(0.30), 0.4)
	# Crossguard
	draw_line(hand + Vector2(-2.0, 0.5), hand + Vector2(2.0, 0.5), Color(0.42, 0.24, 0.10), 1.0)
	# Pommel
	draw_circle(hand + Vector2(0, 1.4), 0.7, Color(0.42, 0.24, 0.10))

# ─────────────────────────────────────────────────────────────────────────────
# GOBLIN — GOBLIN SCOUT
# Small, hunched, wiry. Oversized head. ENORMOUS pointed ears.
# ─────────────────────────────────────────────────────────────────────────────

func _draw_goblin_svg(f: Vector2, perp2: Vector2):
	var sc: float = 0.82
	var moving: bool = move_timer <= 0.04 or alert_state == AlertState.ALERT
	var leg_swing: float = (sin(_anim_t * 11.0) * 2.0 * sc) if moving else 0.0
	var bob: float = (sin(_anim_t * 11.0) * 0.3 * sc) if moving else 0.0

	# Constant twitchy jitter
	var jx: float = sin(_anim_t * 17.3) * 0.7 + sin(_anim_t * 7.1) * 0.3
	var jitter: Vector2 = Vector2(jx, jx * 0.3)

	var skin_col: Color = Color(0.28, 0.52, 0.18)
	var skin_light: Color = skin_col.lightened(0.12)
	var pants_col: Color = Color(0.20, 0.25, 0.10)
	var leather_col: Color = Color(0.32, 0.22, 0.10)

	# 1. Small ground shadow
	var shadow_pts: PackedVector2Array = PackedVector2Array()
	for i in range(12):
		var a: float = float(i) / 12.0 * TAU
		shadow_pts.append(Vector2(cos(a) * 4.5 * sc, sin(a) * 2.2 * sc) + Vector2(0.3, 1.5) * sc)
	draw_colored_polygon(shadow_pts, Color(0.0, 0.0, 0.0, 0.28))

	# 2. Short hunched legs (wide stance)
	_draw_goblin_leg(Vector2(-3.0 * sc, -1.0), Vector2(-3.5 * sc, 5.0 * sc + leg_swing * 0.4), pants_col, sc)
	_draw_goblin_leg(Vector2(3.0 * sc, -1.0), Vector2(3.5 * sc, 5.0 * sc - leg_swing * 0.4), pants_col, sc)

	# 3. Torso — hunched forward
	var torso_c: Vector2 = Vector2(0, -3.5 * sc) + Vector2(0, bob)
	_draw_goblin_torso(torso_c, f, perp2, sc, leather_col, skin_col)

	# 7. Arms (wiry, long)
	var sh_l: Vector2 = torso_c + Vector2(-3.5 * sc, -1.0 * sc)
	var sh_r: Vector2 = torso_c + Vector2(3.5 * sc, -1.0 * sc)
	var hand_l: Vector2 = sh_l + Vector2(-1.5 * sc, 5.0 * sc)
	var hand_r: Vector2 = sh_r + Vector2(1.0 * sc, 5.5 * sc)
	draw_line(sh_l, sh_l + Vector2(-1.0 * sc, 2.5 * sc), skin_col.darkened(0.10), 1.4 * sc)
	draw_line(sh_l + Vector2(-1.0 * sc, 2.5 * sc), hand_l, skin_col, 1.2 * sc)
	draw_line(sh_r, sh_r + Vector2(0.5 * sc, 2.8 * sc), skin_col.darkened(0.10), 1.4 * sc)
	draw_line(sh_r + Vector2(0.5 * sc, 2.8 * sc), hand_r, skin_col, 1.2 * sc)
	# Claw hands — 3 pointed polygon claws
	_draw_goblin_claws(hand_l, -1.0, skin_light, sc)
	_draw_goblin_claws(hand_r, 1.0, skin_light, sc)

	# 4-6. HEAD with enormous ears
	var head_c: Vector2 = Vector2(0, -10.5 * sc) + jitter + Vector2(0, bob * 0.6)
	_draw_goblin_head(head_c, f, perp2, sc, skin_col, skin_light)

	# 8. Crude weapon — dagger in right hand
	_draw_goblin_dagger(hand_r, sc)

	# 9. Stolen shiny at belt
	draw_circle(torso_c + Vector2(-1.8 * sc, 3.0 * sc), 0.8 * sc, Color(0.92, 0.78, 0.20))
	draw_circle(torso_c + Vector2(-1.8 * sc, 3.0 * sc), 0.3 * sc, Color(1.0, 0.95, 0.55))

func _draw_goblin_leg(hip: Vector2, foot: Vector2, pants_col: Color, sc: float):
	# Bent slightly outward — hunched posture
	var w_top: float = 1.4 * sc
	var w_bot: float = 1.1 * sc
	var leg_pts := PackedVector2Array([
		hip + Vector2(-w_top, 0),
		hip + Vector2(w_top, 0),
		foot + Vector2(w_bot, -1.0 * sc),
		foot + Vector2(-w_bot, -1.0 * sc),
	])
	draw_colored_polygon(leg_pts, pants_col)
	draw_line(leg_pts[0], leg_pts[1], pants_col.lightened(0.25), 0.5)
	draw_line(leg_pts[1], leg_pts[2], pants_col.darkened(0.30), 0.4)
	# Big bare foot
	var foot_pts := PackedVector2Array([
		foot + Vector2(-w_bot * 1.4, -1.0 * sc),
		foot + Vector2(w_bot * 1.6, -1.0 * sc),
		foot + Vector2(w_bot * 2.4, 0.8 * sc),
		foot + Vector2(-w_bot * 1.6, 1.0 * sc),
	])
	draw_colored_polygon(foot_pts, Color(0.28, 0.52, 0.18).darkened(0.15))
	# Toes
	for i in range(3):
		draw_circle(foot + Vector2(-1.0 * sc + float(i) * 1.2 * sc, 0.6 * sc), 0.35 * sc, Color(0.20, 0.40, 0.12))

func _draw_goblin_torso(c: Vector2, f: Vector2, perp2: Vector2, sc: float, leather_col: Color, skin_col: Color):
	var w: float = 3.2 * sc
	var h: float = 4.0 * sc
	# Front
	var fl: Vector2 = c + Vector2(-w, h * 0.5)
	var fr: Vector2 = c + Vector2(w, h * 0.5)
	var tr: Vector2 = c + Vector2(w * 0.7, -h * 0.5)
	var tl: Vector2 = c + Vector2(-w * 0.7, -h * 0.5)
	draw_colored_polygon(PackedVector2Array([fl, fr, tr, tl]), leather_col)
	# Top face (lightened)
	draw_colored_polygon(PackedVector2Array([
		tl, tr,
		tr + Vector2(-0.6, -1.2 * sc),
		tl + Vector2(0.6, -1.2 * sc),
	]), leather_col.lightened(0.20))
	# Shadow side
	draw_line(fr, tr, leather_col.darkened(0.40), 1.2)
	# Worn seams / stitches
	draw_line(c + Vector2(-w * 0.6, -h * 0.3), c + Vector2(-w * 0.6, h * 0.4), leather_col.darkened(0.20), 0.4)
	draw_line(c + Vector2(w * 0.5, -h * 0.3), c + Vector2(w * 0.6, h * 0.4), leather_col.darkened(0.20), 0.4)
	# Skin patch at belly
	draw_circle(c + Vector2(0, h * 0.3), 1.2 * sc, skin_col.darkened(0.10))

func _draw_goblin_claws(hand: Vector2, side: float, skin_light: Color, sc: float):
	# Palm
	draw_circle(hand, 1.0 * sc, skin_light)
	# 3 pointed claw polygons
	for i in range(3):
		var ang: float = (float(i) - 1.0) * 0.4 + PI * 0.5
		var tip: Vector2 = hand + Vector2(cos(ang) * 1.8 * sc * side * 0.7, sin(ang) * 1.8 * sc)
		var base_a: Vector2 = hand + Vector2(cos(ang + 0.3) * 0.7 * sc * side * 0.7, sin(ang + 0.3) * 0.7 * sc)
		var base_b: Vector2 = hand + Vector2(cos(ang - 0.3) * 0.7 * sc * side * 0.7, sin(ang - 0.3) * 0.7 * sc)
		draw_colored_polygon(PackedVector2Array([base_a, tip, base_b]), Color(0.92, 0.85, 0.65))
		draw_line(base_a, tip, Color(0.45, 0.35, 0.20), 0.3)

func _draw_goblin_head(c: Vector2, f: Vector2, perp2: Vector2, sc: float, skin_col: Color, skin_light: Color):
	var head_r: float = 6.5 * sc

	# HUGE pointed ears — drawn first so head overlaps
	# Left ear
	var ear_l := PackedVector2Array([
		c + Vector2(-head_r * 0.6, -1.0),
		c + Vector2(-head_r * 1.5, -head_r * 0.8),
		c + Vector2(-head_r * 1.9, -head_r * 0.2),
		c + Vector2(-head_r * 1.4, head_r * 0.5),
		c + Vector2(-head_r * 0.7, head_r * 0.2),
	])
	draw_colored_polygon(ear_l, skin_col.darkened(0.10))
	# Inner ear pink
	var ear_l_inner := PackedVector2Array([
		c + Vector2(-head_r * 0.7, -0.3),
		c + Vector2(-head_r * 1.3, -head_r * 0.5),
		c + Vector2(-head_r * 1.5, head_r * 0.1),
		c + Vector2(-head_r * 0.8, head_r * 0.1),
	])
	draw_colored_polygon(ear_l_inner, Color(0.65, 0.30, 0.25))
	# Right ear (mirror)
	var ear_r := PackedVector2Array([
		c + Vector2(head_r * 0.6, -1.0),
		c + Vector2(head_r * 1.5, -head_r * 0.8),
		c + Vector2(head_r * 1.9, -head_r * 0.2),
		c + Vector2(head_r * 1.4, head_r * 0.5),
		c + Vector2(head_r * 0.7, head_r * 0.2),
	])
	draw_colored_polygon(ear_r, skin_col.darkened(0.10))
	var ear_r_inner := PackedVector2Array([
		c + Vector2(head_r * 0.7, -0.3),
		c + Vector2(head_r * 1.3, -head_r * 0.5),
		c + Vector2(head_r * 1.5, head_r * 0.1),
		c + Vector2(head_r * 0.8, head_r * 0.1),
	])
	draw_colored_polygon(ear_r_inner, Color(0.65, 0.30, 0.25))

	# Head sphere
	draw_circle(c, head_r, skin_col)
	# Top lighter face
	draw_circle(c + Vector2(-head_r * 0.25, -head_r * 0.3), head_r * 0.65, skin_light)
	# Shadow side arc
	draw_arc(c, head_r - 0.3, -PI * 0.1, PI * 0.6, 10, skin_col.darkened(0.25), 0.8)

	# Eyes — LARGE
	var eye_r: float = 1.8 * sc
	var eye_jitter: float = 0.0
	var eye_col: Color
	match alert_state:
		AlertState.UNAWARE:
			eye_col = Color(0.85, 0.75, 0.10)
		AlertState.SUSPICIOUS:
			eye_col = Color(0.95, 0.50, 0.05)
		AlertState.ALERT:
			eye_col = Color(0.9, 0.05, 0.05)
			eye_jitter = sin(_anim_t * 20.0) * 0.5
		_:
			eye_col = Color(0.85, 0.75, 0.10)
	# Eye whites / sockets
	draw_circle(c + Vector2(-2.0 * sc, -1.0 * sc), eye_r + 0.3, Color(0.05, 0.04, 0.04))
	draw_circle(c + Vector2(2.0 * sc, -1.0 * sc), eye_r + 0.3, Color(0.05, 0.04, 0.04))
	draw_circle(c + Vector2(-2.0 * sc, -1.0 * sc), eye_r + eye_jitter, eye_col)
	draw_circle(c + Vector2(2.0 * sc, -1.0 * sc), eye_r + eye_jitter, eye_col)
	# Slit pupils
	draw_line(c + Vector2(-2.0 * sc, -1.5 * sc), c + Vector2(-2.0 * sc, -0.5 * sc), Color(0.05, 0.04, 0.04), 0.6)
	draw_line(c + Vector2(2.0 * sc, -1.5 * sc), c + Vector2(2.0 * sc, -0.5 * sc), Color(0.05, 0.04, 0.04), 0.6)
	# Eye gleam
	draw_circle(c + Vector2(-1.6 * sc, -1.5 * sc), 0.4, Color(1.0, 1.0, 0.85))
	draw_circle(c + Vector2(2.4 * sc, -1.5 * sc), 0.4, Color(1.0, 1.0, 0.85))

	# Nose
	var nose := PackedVector2Array([
		c + Vector2(0, 0.5),
		c + Vector2(-0.8 * sc, 2.0 * sc),
		c + Vector2(0.8 * sc, 2.0 * sc),
	])
	draw_colored_polygon(nose, skin_col.darkened(0.30))

	# Mouth — large grin
	draw_arc(c + Vector2(0, 3.0 * sc), 2.0 * sc, PI * 0.15, PI * 0.85, 10, Color(0.08, 0.04, 0.04), 0.9)
	# Inner mouth
	draw_arc(c + Vector2(0, 3.0 * sc), 1.6 * sc, PI * 0.2, PI * 0.80, 8, Color(0.25, 0.08, 0.08), 1.0)
	# Fangs — 3 small triangle polygons
	for i in range(3):
		var fx: float = (float(i) - 1.0) * 1.0 * sc
		var ftop: Vector2 = c + Vector2(fx, 3.0 * sc)
		draw_colored_polygon(PackedVector2Array([
			ftop + Vector2(-0.35, 0),
			ftop + Vector2(0.35, 0),
			ftop + Vector2(0, 1.2 * sc),
		]), Color(0.95, 0.90, 0.78))

	# Drool drop
	var drool_y: float = 4.5 * sc + sin(_anim_t * 2.0) * 1.0
	draw_circle(c + Vector2(1.4 * sc, drool_y), 0.55, Color(0.85, 0.92, 0.80, 0.85))

func _draw_goblin_dagger(hand: Vector2, sc: float):
	var tip: Vector2 = hand + Vector2(2.0 * sc, -5.0 * sc)
	# Blade
	draw_colored_polygon(PackedVector2Array([
		hand + Vector2(-0.6, -0.4),
		hand + Vector2(0.6, -0.4),
		tip + Vector2(0.4, 0.4),
		tip,
	]), Color(0.78, 0.80, 0.85))
	draw_line(hand + Vector2(0, -0.4), tip, Color(0.95, 0.95, 1.0), 0.4)
	# Crossguard
	draw_line(hand + Vector2(-1.2, 0.2), hand + Vector2(1.0, 0.2), Color(0.42, 0.30, 0.15), 0.8)
	# Grip
	draw_circle(hand + Vector2(-0.2, 0.8), 0.5, Color(0.30, 0.20, 0.10))

# ─────────────────────────────────────────────────────────────────────────────
# GNOLL — GNOLL BRUTE
# Massive hyena-like humanoid. Spotted fur. Bone harness. Predatory.
# ─────────────────────────────────────────────────────────────────────────────

func _draw_gnoll_svg(f: Vector2, perp2: Vector2):
	var sc: float = 1.45 if is_boss else 1.22
	var moving: bool = move_timer <= 0.04 or alert_state == AlertState.ALERT
	var leg_swing: float = (sin(_anim_t * 5.0) * 3.0 * sc) if moving else 0.0
	var bob: float = (sin(_anim_t * 5.0) * 1.2 * sc) if moving else 0.0

	var fur_col: Color = Color(0.55, 0.45, 0.25)
	var fur_dark: Color = Color(0.32, 0.25, 0.12)
	var fur_light: Color = fur_col.lightened(0.18)
	var leather_col: Color = Color(0.30, 0.18, 0.08)

	# 1. LARGE ground shadow
	var shadow_pts: PackedVector2Array = PackedVector2Array()
	for i in range(16):
		var a: float = float(i) / 16.0 * TAU
		shadow_pts.append(Vector2(cos(a) * 8.5 * sc, sin(a) * 4.0 * sc) + Vector2(0.5, 3.0) * sc)
	draw_colored_polygon(shadow_pts, Color(0.0, 0.0, 0.0, 0.35))

	# 2. Digitigrade legs
	_draw_gnoll_leg(Vector2(-3.5 * sc, -2.0 * sc), Vector2(-3.0 * sc, 6.0 * sc + leg_swing * 0.4 - bob * 0.5), fur_col, fur_dark, sc)
	_draw_gnoll_leg(Vector2(3.5 * sc, -2.0 * sc), Vector2(3.5 * sc, 6.0 * sc - leg_swing * 0.4 + bob * 0.5), fur_col, fur_dark, sc)

	# 3. MASSIVE torso
	var torso_c: Vector2 = Vector2(0, -6.0 * sc) + Vector2(0, bob * 0.3)
	_draw_gnoll_torso(torso_c, f, perp2, sc, fur_col, fur_dark, fur_light, leather_col)

	# 5. Fur mane / neck ruff
	var neck: Vector2 = torso_c + Vector2(0, -4.5 * sc)
	_draw_gnoll_mane(neck, sc, fur_col, fur_light)

	# 4. Thick arms
	var sh_l: Vector2 = torso_c + Vector2(-5.0 * sc, -3.0 * sc)
	var sh_r: Vector2 = torso_c + Vector2(5.0 * sc, -3.0 * sc)
	_draw_gnoll_arm(sh_l, true, fur_col, fur_dark, sc)
	_draw_gnoll_arm(sh_r, false, fur_col, fur_dark, sc)
	var hand_r: Vector2 = sh_r + Vector2(2.5 * sc, 6.0 * sc)

	# 6-8. Head with snout
	var head_c: Vector2 = neck + Vector2(0, -3.0 * sc)
	_draw_gnoll_head(head_c, f, perp2, sc, fur_col, fur_dark, fur_light)

	# 10. Heavy weapon — great axe
	_draw_gnoll_axe(hand_r, sc)

	# 11. Ground impact when walking
	if moving:
		var feet: Vector2 = Vector2(0, 6.5 * sc)
		var pulse_r: float = (1.5 + abs(sin(_anim_t * 5.0)) * 2.0) * sc
		draw_arc(feet, pulse_r, 0, TAU, 14, Color(0.2, 0.15, 0.08, 0.10), 1.0)

func _draw_gnoll_leg(hip: Vector2, paw: Vector2, fur_col: Color, fur_dark: Color, sc: float):
	# Digitigrade: knee forward, ankle bent backward
	var knee: Vector2 = Vector2(hip.x + (paw.x - hip.x) * 0.3, hip.y + (paw.y - hip.y) * 0.4) + Vector2(sign(hip.x) * 1.5 * sc, 0)
	var ankle: Vector2 = Vector2(hip.x + (paw.x - hip.x) * 0.7, hip.y + (paw.y - hip.y) * 0.75) + Vector2(-sign(hip.x) * 0.5 * sc, 0)
	# Thick thigh
	var thigh_pts := PackedVector2Array([
		hip + Vector2(-2.2 * sc, 0),
		hip + Vector2(2.2 * sc, 0),
		knee + Vector2(1.4 * sc, 0),
		knee + Vector2(-1.4 * sc, 0),
	])
	draw_colored_polygon(thigh_pts, fur_col)
	draw_line(thigh_pts[0], thigh_pts[1], fur_light, 0.6)
	draw_line(thigh_pts[1], thigh_pts[2], fur_dark.darkened(0.20), 0.5)
	# Shin (thinner)
	var shin_pts := PackedVector2Array([
		knee + Vector2(-1.3 * sc, 0),
		knee + Vector2(1.3 * sc, 0),
		ankle + Vector2(0.9 * sc, 0),
		ankle + Vector2(-0.9 * sc, 0),
	])
	draw_colored_polygon(shin_pts, fur_col.darkened(0.10))
	# Foot/paw — wide with 3 toe nubs
	var paw_pts := PackedVector2Array([
		ankle + Vector2(-1.5 * sc, 0),
		ankle + Vector2(1.8 * sc, 0),
		paw + Vector2(2.5 * sc, 0.4 * sc),
		paw + Vector2(-1.8 * sc, 0.6 * sc),
	])
	draw_colored_polygon(paw_pts, fur_dark)
	# Toe nubs
	for i in range(3):
		draw_circle(paw + Vector2(-0.8 * sc + float(i) * 1.3 * sc, 0.3 * sc), 0.55 * sc, fur_dark.darkened(0.15))
		# Claw
		var cl: Vector2 = paw + Vector2(-0.8 * sc + float(i) * 1.3 * sc, 1.1 * sc)
		draw_colored_polygon(PackedVector2Array([
			cl + Vector2(-0.3, -0.3),
			cl + Vector2(0.3, -0.3),
			cl + Vector2(0, 0.6),
		]), Color(0.18, 0.10, 0.06))

func _draw_gnoll_torso(c: Vector2, f: Vector2, perp2: Vector2, sc: float, fur_col: Color, fur_dark: Color, fur_light: Color, leather: Color):
	var w: float = 6.0 * sc
	var h: float = 7.0 * sc
	# Wide front face
	var fl: Vector2 = c + Vector2(-w, h * 0.5)
	var fr: Vector2 = c + Vector2(w, h * 0.5)
	var tr: Vector2 = c + Vector2(w * 0.85, -h * 0.5)
	var tl: Vector2 = c + Vector2(-w * 0.85, -h * 0.5)
	draw_colored_polygon(PackedVector2Array([fl, fr, tr, tl]), fur_col)
	# Top face
	draw_colored_polygon(PackedVector2Array([
		tl, tr,
		tr + Vector2(-1.0 * sc, -2.0 * sc),
		tl + Vector2(1.0 * sc, -2.0 * sc),
	]), fur_light)
	# Shadow side
	draw_line(fr, tr, fur_dark.darkened(0.20), 1.8)
	# Fur patches (lighter irregular polygons)
	for i in range(4):
		var px: float = -w * 0.6 + float(i) * w * 0.4
		var py: float = -h * 0.2 + sin(float(i) * 1.7) * h * 0.2
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(px - 1.2, py - 0.5),
			c + Vector2(px + 1.0, py - 0.8),
			c + Vector2(px + 1.3, py + 0.9),
			c + Vector2(px - 0.8, py + 0.7),
		]), fur_light)
	# Dark spots (signature gnoll look)
	for i in range(7):
		var sx: float = -w * 0.7 + float((i * 37) % 100) / 100.0 * w * 1.4
		var sy: float = -h * 0.4 + float((i * 53) % 100) / 100.0 * h * 0.8
		var sr: float = 0.6 + float((i * 17) % 30) / 30.0 * 0.5
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(sx - sr, sy),
			c + Vector2(sx, sy - sr),
			c + Vector2(sx + sr, sy),
			c + Vector2(sx, sy + sr),
		]), fur_dark)
	# Leather harness — two diagonal straps crossing chest
	draw_line(c + Vector2(-w * 0.85, -h * 0.4), c + Vector2(w * 0.5, h * 0.3), leather, 1.5)
	draw_line(c + Vector2(w * 0.85, -h * 0.4), c + Vector2(-w * 0.5, h * 0.3), leather, 1.5)
	# Bone trophy at harness center
	var bone_c: Vector2 = c + Vector2(0, 0)
	draw_circle(bone_c, 1.2 * sc, Color(0.92, 0.88, 0.78))
	draw_line(bone_c + Vector2(-1.0 * sc, 0), bone_c + Vector2(1.0 * sc, 0), Color(0.92, 0.88, 0.78), 1.8)
	draw_circle(bone_c + Vector2(-1.0 * sc, 0), 0.4 * sc, Color(0.92, 0.88, 0.78))
	draw_circle(bone_c + Vector2(1.0 * sc, 0), 0.4 * sc, Color(0.92, 0.88, 0.78))

func _draw_gnoll_mane(neck: Vector2, sc: float, fur_col: Color, fur_light: Color):
	# Irregular polygon ruff
	var pts := PackedVector2Array()
	var n: int = 12
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		var r: float = 4.5 * sc + sin(float(i) * 2.3) * 1.2 * sc
		# Spikier at top, flatter at bottom
		if sin(a) < 0:
			r *= 1.2
		pts.append(neck + Vector2(cos(a) * r * 1.3, sin(a) * r * 0.7))
	draw_colored_polygon(pts, fur_light)
	# Inner darker
	var inner := PackedVector2Array()
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		inner.append(neck + Vector2(cos(a) * 3.0 * sc, sin(a) * 1.8 * sc))
	draw_colored_polygon(inner, fur_col)

func _draw_gnoll_arm(shoulder: Vector2, is_left: bool, fur_col: Color, fur_dark: Color, sc: float):
	var side: float = -1.0 if is_left else 1.0
	var elbow: Vector2 = shoulder + Vector2(side * 1.5 * sc, 3.5 * sc)
	var wrist: Vector2 = shoulder + Vector2(side * 2.5 * sc, 6.0 * sc)
	# Upper arm — very wide
	var ua_pts := PackedVector2Array([
		shoulder + Vector2(-2.0 * sc, 0),
		shoulder + Vector2(2.0 * sc, 0),
		elbow + Vector2(1.4 * sc, 0),
		elbow + Vector2(-1.4 * sc, 0),
	])
	draw_colored_polygon(ua_pts, fur_col)
	draw_line(ua_pts[0], ua_pts[1], fur_col.lightened(0.20), 0.5)
	# Forearm
	var fa_pts := PackedVector2Array([
		elbow + Vector2(-1.3 * sc, 0),
		elbow + Vector2(1.3 * sc, 0),
		wrist + Vector2(1.0 * sc, 0),
		wrist + Vector2(-1.0 * sc, 0),
	])
	draw_colored_polygon(fa_pts, fur_dark)
	# Spot
	draw_circle(elbow + Vector2(0, 1.0), 0.7 * sc, fur_dark.darkened(0.20))
	# 3 large hooked claws
	for i in range(3):
		var ang: float = -0.5 + float(i) * 0.4
		var tip: Vector2 = wrist + Vector2(side * cos(ang) * 2.2 * sc, sin(ang) * 2.2 * sc + 1.5 * sc)
		var base_a: Vector2 = wrist + Vector2(side * cos(ang + 0.2) * 0.8 * sc, sin(ang + 0.2) * 0.8 * sc + 0.6 * sc)
		var base_b: Vector2 = wrist + Vector2(side * cos(ang - 0.2) * 0.8 * sc, sin(ang - 0.2) * 0.8 * sc + 0.6 * sc)
		draw_colored_polygon(PackedVector2Array([base_a, tip, base_b]), Color(0.18, 0.10, 0.06))
		draw_line(base_a, tip, Color(0.10, 0.06, 0.04), 0.3)

func _draw_gnoll_head(c: Vector2, f: Vector2, perp2: Vector2, sc: float, fur_col: Color, fur_dark: Color, fur_light: Color):
	# Elongated head shape — not a round circle
	var head_pts := PackedVector2Array([
		c + Vector2(-3.0 * sc, -2.5 * sc),
		c + Vector2(3.0 * sc, -2.5 * sc),
		c + Vector2(3.5 * sc, 0),
		c + Vector2(3.0 * sc, 2.0 * sc),
		c + Vector2(-3.0 * sc, 2.0 * sc),
		c + Vector2(-3.5 * sc, 0),
	])
	draw_colored_polygon(head_pts, fur_col)
	# Top lighter
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-3.0 * sc, -2.5 * sc),
		c + Vector2(3.0 * sc, -2.5 * sc),
		c + Vector2(2.5 * sc, -0.5 * sc),
		c + Vector2(-2.5 * sc, -0.5 * sc),
	]), fur_light)
	# Shadow side
	draw_line(c + Vector2(3.5 * sc, 0), c + Vector2(3.0 * sc, 2.0 * sc), fur_dark, 1.0)

	# Ears — large pointed, upright
	var ear_l := PackedVector2Array([
		c + Vector2(-2.5 * sc, -2.5 * sc),
		c + Vector2(-3.5 * sc, -5.5 * sc),
		c + Vector2(-1.5 * sc, -3.5 * sc),
	])
	draw_colored_polygon(ear_l, fur_col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-2.3 * sc, -2.8 * sc),
		c + Vector2(-3.0 * sc, -4.8 * sc),
		c + Vector2(-1.8 * sc, -3.5 * sc),
	]), fur_light)
	var ear_r := PackedVector2Array([
		c + Vector2(2.5 * sc, -2.5 * sc),
		c + Vector2(3.5 * sc, -5.5 * sc),
		c + Vector2(1.5 * sc, -3.5 * sc),
	])
	draw_colored_polygon(ear_r, fur_col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(2.3 * sc, -2.8 * sc),
		c + Vector2(3.0 * sc, -4.8 * sc),
		c + Vector2(1.8 * sc, -3.5 * sc),
	]), fur_light.darkened(0.10))

	# Snout — forward-projecting
	var snout_pts := PackedVector2Array([
		c + Vector2(-1.8 * sc, 0.5 * sc),
		c + Vector2(1.8 * sc, 0.5 * sc),
		c + Vector2(1.5 * sc, 4.5 * sc),
		c + Vector2(-1.5 * sc, 4.5 * sc),
	])
	draw_colored_polygon(snout_pts, fur_col.darkened(0.10))
	draw_line(snout_pts[0], snout_pts[1], fur_light, 0.5)
	draw_line(snout_pts[1], snout_pts[2], fur_dark, 0.5)

	# Wet nose
	draw_circle(c + Vector2(0, 4.2 * sc), 0.9 * sc, Color(0.10, 0.06, 0.08))
	draw_circle(c + Vector2(-0.3 * sc, 4.0 * sc), 0.3, Color(0.55, 0.50, 0.45))

	# Mouth with fangs
	draw_line(c + Vector2(-1.4 * sc, 3.0 * sc), c + Vector2(1.4 * sc, 3.0 * sc), Color(0.10, 0.06, 0.06), 0.7)
	# Upper fangs
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-1.0 * sc, 3.0 * sc),
		c + Vector2(-0.5 * sc, 3.0 * sc),
		c + Vector2(-0.75 * sc, 4.2 * sc),
	]), Color(0.96, 0.92, 0.78))
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.5 * sc, 3.0 * sc),
		c + Vector2(1.0 * sc, 3.0 * sc),
		c + Vector2(0.75 * sc, 4.2 * sc),
	]), Color(0.96, 0.92, 0.78))

	# Predatory eyes
	var eye_l_p: Vector2 = c + Vector2(-1.6 * sc, -0.5 * sc)
	var eye_r_p: Vector2 = c + Vector2(1.6 * sc, -0.5 * sc)
	var amber: Color = Color(0.85, 0.62, 0.10)
	var slit_w: float = 0.5
	match alert_state:
		AlertState.SUSPICIOUS:
			amber = Color(0.95, 0.55, 0.05)
		AlertState.ALERT:
			amber = Color(1.0, 0.30, 0.05)
			slit_w = 1.1
			# Aura around eyes
			draw_arc(eye_l_p, 2.0 * sc, 0, TAU, 12,
				Color(1.0, 0.30, 0.10, 0.30 + sin(_anim_t * 6.0) * 0.10), 1.0)
			draw_arc(eye_r_p, 2.0 * sc, 0, TAU, 12,
				Color(1.0, 0.30, 0.10, 0.30 + sin(_anim_t * 6.0) * 0.10), 1.0)
	# Eye whites
	draw_circle(eye_l_p, 1.1 * sc, Color(0.95, 0.85, 0.55))
	draw_circle(eye_r_p, 1.1 * sc, Color(0.95, 0.85, 0.55))
	draw_circle(eye_l_p, 0.9 * sc, amber)
	draw_circle(eye_r_p, 0.9 * sc, amber)
	# Slit pupil — thin or wide based on state
	draw_line(eye_l_p + Vector2(0, -0.8 * sc), eye_l_p + Vector2(0, 0.8 * sc), Color(0.05, 0.03, 0.03), slit_w)
	draw_line(eye_r_p + Vector2(0, -0.8 * sc), eye_r_p + Vector2(0, 0.8 * sc), Color(0.05, 0.03, 0.03), slit_w)

func _draw_gnoll_axe(hand: Vector2, sc: float):
	var shaft_top: Vector2 = hand + Vector2(0, -10.0 * sc)
	var shaft_bot: Vector2 = hand + Vector2(0, 4.0 * sc)
	# Wood shaft
	draw_line(shaft_bot, shaft_top, Color(0.32, 0.20, 0.10), 1.6)
	draw_line(shaft_bot + Vector2(0.5, 0), shaft_top + Vector2(0.5, 0), Color(0.45, 0.30, 0.15), 0.6)
	# Iron axe head — crescent
	var head_c: Vector2 = shaft_top + Vector2(0, -0.5 * sc)
	var axe_pts := PackedVector2Array([
		head_c + Vector2(-3.5 * sc, -1.0 * sc),
		head_c + Vector2(-3.0 * sc, -3.5 * sc),
		head_c + Vector2(-0.5 * sc, -2.5 * sc),
		head_c + Vector2(0.5 * sc, -2.5 * sc),
		head_c + Vector2(2.5 * sc, -1.5 * sc),
		head_c + Vector2(2.0 * sc, 1.5 * sc),
		head_c + Vector2(-0.5 * sc, 1.0 * sc),
		head_c + Vector2(-3.0 * sc, 2.5 * sc),
		head_c + Vector2(-3.5 * sc, 0.5 * sc),
	])
	draw_colored_polygon(axe_pts, Color(0.42, 0.40, 0.45))
	# Highlight edge
	draw_line(axe_pts[0], axe_pts[1], Color(0.75, 0.73, 0.78), 0.7)
	draw_line(axe_pts[1], axe_pts[2], Color(0.75, 0.73, 0.78), 0.5)
	# Shadow
	draw_line(axe_pts[4], axe_pts[5], Color(0.20, 0.18, 0.22), 0.7)
	# Scratches / nicks
	draw_line(head_c + Vector2(-2.0 * sc, -0.5 * sc), head_c + Vector2(-0.5 * sc, 0.5 * sc), Color(0.20, 0.18, 0.22), 0.3)
	draw_line(head_c + Vector2(-1.5 * sc, -1.8 * sc), head_c + Vector2(-1.0 * sc, -0.8 * sc), Color(0.20, 0.18, 0.22), 0.3)
	# Back spike
	draw_colored_polygon(PackedVector2Array([
		head_c + Vector2(2.0 * sc, -0.5 * sc),
		head_c + Vector2(4.0 * sc, 0),
		head_c + Vector2(2.0 * sc, 0.5 * sc),
	]), Color(0.38, 0.36, 0.40))
	# Binding rope at shaft
	draw_line(shaft_top + Vector2(-1.0, 1.5), shaft_top + Vector2(1.0, 1.5), Color(0.20, 0.14, 0.08), 0.6)
	draw_line(shaft_top + Vector2(-1.0, 2.3), shaft_top + Vector2(1.0, 2.3), Color(0.20, 0.14, 0.08), 0.6)

func _is_blocked(target_pos: Vector2) -> bool:
	var space = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = target_pos
	query.exclude = [self]
	return space.intersect_point(query).size() > 0
