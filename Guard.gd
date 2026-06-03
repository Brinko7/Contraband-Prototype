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

# HP system
var guard_hp:     int = 2
var guard_max_hp: int = 2
var _hurt_flash_t: float = 0.0

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
	_sprite = Sprite2D.new()
	_sprite.texture = _ENEMY_SHEET
	_sprite.hframes = 8
	_sprite.vframes = 6
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.offset = Vector2(0, -10)
	_sprite.scale = Vector2(1.0, 1.0)
	add_child(_sprite)

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
	if _hurt_flash_t > 0.0:
		_hurt_flash_t -= delta
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
	_update_sprite()
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

func _update_chase(delta):
	if player == null:
		return
	if _is_stunned:
		return
	_hit_cooldown = max(0.0, _hit_cooldown - delta)
	if global_position.distance_to(player.global_position) <= TILE_SIZE:
		if _hit_cooldown <= 0.0:
			_hit_cooldown = 1.2   # 1.2s between hits from this guard
			var dmg := 2
			# Bosses hit harder
			if get("is_boss") == true:
				dmg = 3
			if player.has_method("take_damage_flash"):
				player.take_damage_flash()
			GameManager.take_damage(dmg)
			_popup("HIT -%d HP" % dmg, Color(1.0, 0.20, 0.20))
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

func hurt(damage: int):
	guard_hp -= damage
	_hurt_flash_t = 0.18
	stagger(0.30)
	_escalate_alert()
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

func _spawn_body():
	var body := Node2D.new()
	body.set_script(_body_script)
	body.set_meta("body_facing", facing)
	var scene := get_tree().current_scene
	scene.add_child(body)
	body.global_position = global_position

func _draw():
	var half_angle    := deg_to_rad(vision_angle / 2.0)
	var facing_angle  := facing.angle()
	var perp          := facing.rotated(PI * 0.5).normalized()

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

	# ── Hold Person / Stun overlay ─────────────────────────────────────────────
	if _is_held:
		draw_arc(Vector2.ZERO, 9.0, 0, TAU, 20, Color(0.40, 0.60, 1.0, 0.55 + abs(sin(_anim_t*4))*0.2), 2.5)
	if _is_stunned:
		draw_arc(Vector2.ZERO, 9.0, 0, TAU, 20, Color(0.90, 0.70, 0.15, 0.55 + abs(sin(_anim_t*6))*0.2), 2.5)

	# ── Body shadow — at feet (y=0 is feet level with sprite offset -10) ──────
	draw_circle(Vector2(0.5, 0.0), 5.0, Color(0.0, 0.0, 0.0, 0.28))

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


func _update_sprite():
	if _sprite == null:
		return
	# Row: HUMAN=0, SKELETON=1, GOBLIN=2, GNOLL=3, BOSS=4
	var row := 4 if is_boss else int(enemy_type)
	# Col: DOWN=0-1, LEFT=2-3, RIGHT=4-5, UP=6-7
	var col_base: int
	if facing == Vector2.DOWN:    col_base = 0
	elif facing == Vector2.LEFT:  col_base = 2
	elif facing == Vector2.RIGHT: col_base = 4
	else:                         col_base = 6
	var walk_frame := int(_anim_t * 4.0) % 2
	_sprite.frame = row * 8 + col_base + walk_frame
	# Skeleton: subtle bone pulse when unaware, red-tint when alert
	if enemy_type == EnemyType.SKELETON:
		var pulse: float = abs(sin(_anim_t * 2.5)) * 0.08
		if alert_state == AlertState.ALERT:
			_sprite.modulate = Color(1.0, 0.6 + pulse, 0.6 + pulse)
		else:
			_sprite.modulate = Color(1.0 + pulse, 1.0 + pulse, 1.0 + pulse)
	elif _sprite.modulate != Color.WHITE:
		_sprite.modulate = Color.WHITE

func _is_blocked(target_pos: Vector2) -> bool:
	var space = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = target_pos
	query.exclude = [self]
	return space.intersect_point(query).size() > 0
