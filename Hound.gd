extends CharacterBody2D

enum AlertState { UNAWARE, SUSPICIOUS, ALERT }

const _dice_scene   = preload("res://DicePopup.tscn")
const _body_script  = preload("res://BodyMarker.gd")
const _ENEMY_SHEET  = preload("res://sprites/enemy_sheet.png")

const TILE_SIZE = 16
const INVESTIGATE_DELAY = 0

@export var patrol_points: Array[Vector2] = []

const HEARING_RANGE_LOUD   = 170.0
const HEARING_RANGE_QUIET  = 65.0
const HEARING_RANGE_SILENT = 0.0

const ALERT_TIMEOUT      = 5.0
const SUSPICIOUS_TIMEOUT = 3.5
var chase_interval       := 0.22
var move_interval        := 0.42

var alert_state := AlertState.UNAWARE
var facing := Vector2.RIGHT
var patrol_index := 0
var move_timer := 0.0
var patrol_wait := 0.0
var investigate_pos := Vector2.ZERO
var de_escalate_timer := 0.0
var player: Node2D = null
var _anim_t := 0.0
var _sprite: Sprite2D

func _ready():
	add_to_group("guards")
	player = get_tree().get_first_node_in_group("player")
	if player and player.has_signal("noise_emitted"):
		player.noise_emitted.connect(_on_noise_emitted)
	if GameManager.run_modifier == "TIGHT_PATROLS":
		chase_interval *= 0.65
		move_interval  *= 0.65
	match GameManager.floor_complication:
		"LOCKDOWN":
			alert_state = AlertState.SUSPICIOUS
			investigate_pos = Vector2(256, 200)
			de_escalate_timer = SUSPICIOUS_TIMEOUT
		"PARANOID":
			pass  # hounds don't have detection bar but they react faster via LOUD threshold
	if GameManager.alert_escalation >= 4:
		chase_interval = max(0.12, chase_interval * 0.85)
	_sprite = Sprite2D.new()
	_sprite.texture = _ENEMY_SHEET
	_sprite.hframes = 8
	_sprite.vframes = 6
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.offset = Vector2(0, -10)
	_sprite.scale = Vector2(1.0, 1.0)
	add_child(_sprite)

func _process(delta):
	if GameManager.state != GameManager.State.PLAYING:
		return
	match alert_state:
		AlertState.UNAWARE, AlertState.SUSPICIOUS:
			_update_patrol(delta)
		AlertState.ALERT:
			_update_chase(delta)
	_update_de_escalation(delta)
	_anim_t += delta
	_update_sprite()
	queue_redraw()

func _update_de_escalation(delta):
	if alert_state == AlertState.UNAWARE:
		return
	de_escalate_timer -= delta
	if de_escalate_timer > 0.0:
		return
	match alert_state:
		AlertState.ALERT:
			alert_state = AlertState.SUSPICIOUS
			investigate_pos = player.global_position if player else Vector2.ZERO
			de_escalate_timer = SUSPICIOUS_TIMEOUT
		AlertState.SUSPICIOUS:
			alert_state = AlertState.UNAWARE
			investigate_pos = Vector2.ZERO
			patrol_wait = 0.5

func _update_patrol(delta):
	if patrol_points.is_empty():
		return
	if patrol_wait > 0.0:
		patrol_wait -= delta
		return
	move_timer -= delta
	if move_timer > 0.0:
		return

	if alert_state == AlertState.SUSPICIOUS and investigate_pos != Vector2.ZERO:
		var inv_diff := investigate_pos - position
		if inv_diff.length() < 2.0:
			investigate_pos = Vector2.ZERO
			patrol_wait = 0.8
			return
		_step_toward(investigate_pos, move_interval)
		return

	var target_world: Vector2 = patrol_points[patrol_index]
	var diff: Vector2 = target_world - position
	if diff.length() < 2.0:
		patrol_index = (patrol_index + 1) % patrol_points.size()
		patrol_wait = 0.5
		return
	_step_toward(target_world, move_interval)

var _hit_cooldown := 0.0

func _update_chase(delta):
	if player == null:
		return
	_hit_cooldown = max(0.0, _hit_cooldown - delta)
	if global_position.distance_to(player.global_position) <= TILE_SIZE:
		if _hit_cooldown <= 0.0:
			_hit_cooldown = 1.0
			GameManager.take_damage(2)
			_popup("MAULED -2 HP", Color(1.0, 0.25, 0.10))
		return
	move_timer -= delta
	if move_timer > 0.0:
		return
	_step_toward(player.global_position, chase_interval)

func _step_toward(target_world: Vector2, interval: float):
	var diff: Vector2 = target_world - position
	var step := Vector2(sign(diff.x), 0) if abs(diff.x) >= abs(diff.y) else Vector2(0, sign(diff.y))
	var next_pos = position + step * TILE_SIZE
	if not _is_blocked(next_pos):
		facing = step
		position = next_pos
	move_timer = interval

func _on_noise_emitted(level: int, world_position: Vector2):
	var hear_range: float
	if level == 2:
		hear_range = HEARING_RANGE_LOUD
	elif level == 1:
		hear_range = HEARING_RANGE_QUIET
	else:
		hear_range = HEARING_RANGE_SILENT

	if GameManager.run_modifier == "THIN_WALLS":
		hear_range += 40.0
	if hear_range == 0.0 or global_position.distance_to(world_position) > hear_range:
		return

	if alert_state == AlertState.UNAWARE:
		alert_state = AlertState.SUSPICIOUS
		investigate_pos = world_position
		de_escalate_timer = SUSPICIOUS_TIMEOUT
		_popup("?", Color(1.0, 0.75, 0.10))
	elif alert_state == AlertState.SUSPICIOUS:
		# Only LOUD noise escalates a hound to full ALERT — quiet noises just
		# refresh the investigate position so the hound keeps sniffing around.
		if level == 2:
			alert_state = AlertState.ALERT
			de_escalate_timer = ALERT_TIMEOUT
			GameManager.record_alert()
			_popup("!", Color(1.0, 0.10, 0.10))
		else:
			investigate_pos = world_position
			de_escalate_timer = SUSPICIOUS_TIMEOUT
	elif alert_state == AlertState.ALERT:
		investigate_pos = world_position

func resist_takedown():
	alert_state = AlertState.ALERT
	de_escalate_timer = ALERT_TIMEOUT
	GameManager.record_alert()

func takedown(attacker_is_sneaking: bool, _is_dart: bool = false):
	var noise_level = player.NoiseLevel.QUIET if (attacker_is_sneaking and alert_state == AlertState.UNAWARE) \
		else player.NoiseLevel.LOUD
	if player:
		player.emit_noise(noise_level)
	_spawn_body()
	queue_free()

func _popup(text: String, color: Color):
	var p := _dice_scene.instantiate()
	p.setup(text, color)
	p.global_position = global_position + Vector2(0, -22)
	get_tree().root.add_child(p)

func _spawn_body():
	var body := Node2D.new()
	body.set_script(_body_script)
	body.global_position = global_position
	body.set_meta("body_facing", facing)
	get_tree().root.add_child(body)

func _update_sprite():
	if _sprite == null:
		return
	# Row 5 = HOUND; col: DOWN=0-1, LEFT=2-3, RIGHT=4-5, UP=6-7
	var col_base: int
	if facing == Vector2.DOWN:    col_base = 0
	elif facing == Vector2.LEFT:  col_base = 2
	elif facing == Vector2.RIGHT: col_base = 4
	else:                         col_base = 6
	var walk_frame := int(_anim_t * 4.0) % 2
	_sprite.frame = 5 * 8 + col_base + walk_frame

func _draw():
	# Body shadow
	draw_circle(Vector2(0.5, 0.0), 5.5, Color(0.0, 0.0, 0.0, 0.28))

	# Hearing radius pulse when alert
	if alert_state == AlertState.ALERT:
		draw_arc(Vector2.ZERO, HEARING_RANGE_QUIET, 0, TAU, 24,
			Color(0.85, 0.42, 0.08, 0.10), 1.0)

	# Alert diamond indicator
	if alert_state == AlertState.SUSPICIOUS:
		var dc := Color(1.0, 0.60, 0.0)
		var top := Vector2(0, -17); var bot := Vector2(0, -11)
		var lft := Vector2(-2.5, -14); var rgt := Vector2(2.5, -14)
		draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]),
			Color(dc.r, dc.g, dc.b, 0.25))
		draw_line(top, rgt, dc, 1.2); draw_line(rgt, bot, dc, 1.2)
		draw_line(bot, lft, dc, 1.2); draw_line(lft, top, dc, 1.2)
		draw_circle(Vector2(0, -14), 1.2, dc)
	elif alert_state == AlertState.ALERT:
		var dc := Color(1.0, 0.12, 0.12)
		var top := Vector2(0, -18); var bot := Vector2(0, -10)
		var lft := Vector2(-3.5, -14); var rgt := Vector2(3.5, -14)
		draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]),
			Color(dc.r, dc.g, dc.b, 0.28))
		draw_line(top, rgt, dc, 1.5); draw_line(rgt, bot, dc, 1.5)
		draw_line(bot, lft, dc, 1.5); draw_line(lft, top, dc, 1.5)
		draw_circle(Vector2(0, -14), 1.5, dc)

	# Paw-print identity mark — two dots and a triangle instead of text
	draw_circle(Vector2(-3, -20), 1.2, Color(0.82, 0.62, 0.30, 0.60))
	draw_circle(Vector2( 3, -20), 1.2, Color(0.82, 0.62, 0.30, 0.60))
	draw_colored_polygon(PackedVector2Array([Vector2(0,-23), Vector2(-2.5,-18), Vector2(2.5,-18)]),
		Color(0.82, 0.62, 0.30, 0.45))

func _is_blocked(target_pos: Vector2) -> bool:
	var space = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = target_pos
	query.exclude = [self]
	return space.intersect_point(query).size() > 0
