extends Node2D
# Wall-mounted alarm bell. Guards that go ALERT near this bell will ring it
# (if not disabled), causing instant alert_escalation +2 and waking all nearby guards.
# Player can disable it by pressing E while adjacent.

const INTERACT_RANGE       = 24.0
const BELL_BREAKER_RANGE   = 48.0   # BELL_BREAKER passive extends this
const GUARD_RING_DIST = 64.0   # guard must be this close to ring it
const RING_COOLDOWN   = 30.0   # once rung, won't fire again this quickly

var is_disabled := false
var _ring_timer  := 0.0        # cooldown between rings
var _anim_t      := 0.0
var _ring_anim   := 0.0        # visual shake on ring

func _ready() -> void:
	add_to_group("alarm_bells")
	add_to_group("interactable")

func _process(delta: float) -> void:
	_anim_t    += delta
	_ring_timer = maxf(_ring_timer - delta, 0.0)
	if _ring_anim > 0.0:
		_ring_anim = maxf(_ring_anim - delta * 3.0, 0.0)
	queue_redraw()

func is_in_range(player_pos: Vector2) -> bool:
	var gm = get_node_or_null("/root/GameManager")
	var range := BELL_BREAKER_RANGE if (gm and gm.has_passive("BELL_BREAKER")) else INTERACT_RANGE
	return global_position.distance_to(player_pos) <= range

func interact(_player) -> void:
	if is_disabled:
		return
	is_disabled = true
	_ring_anim  = 0.0
	queue_redraw()

# Called by Guard.gd when a guard reaches ALERT state within range
func try_ring(guard: Node) -> void:
	if is_disabled or _ring_timer > 0.0:
		return
	if global_position.distance_to(guard.global_position) > GUARD_RING_DIST:
		return
	_ring_timer = RING_COOLDOWN
	_ring_anim  = 1.0
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.alert_escalation = min(gm.alert_escalation + 2, 8)
		gm.times_alerted   += 1
		gm.floor_alerts    += 1
	# Wake all guards nearby
	for g in get_tree().get_nodes_in_group("guards"):
		if is_instance_valid(g) and global_position.distance_to(g.global_position) <= 160.0:
			if g.has_method("_enter_alert"):
				g._enter_alert()
	AudioManager.noise_alert()
	queue_redraw()

func _draw() -> void:
	var player   = get_tree().get_first_node_in_group("player")
	var in_range := player != null and is_in_range(player.global_position)
	var shake_x  := sin(_ring_anim * 40.0) * _ring_anim * 5.0

	# Bell body
	var bell_col: Color
	if is_disabled:
		bell_col = Color(0.30, 0.28, 0.25)
	elif _ring_anim > 0.3:
		bell_col = Color(1.0, 0.3, 0.1)
	else:
		bell_col = Color(0.85, 0.65, 0.15)

	# Wall mount bar
	draw_rect(Rect2(-6 + shake_x, -10, 12, 4), Color(0.25, 0.22, 0.20))

	# Bell dome
	var pts: PackedVector2Array = []
	for i in 9:
		var a := PI + i * PI / 8.0
		pts.append(Vector2(shake_x + cos(a) * 7.0, sin(a) * 7.0 - 4.0))
	pts.append(Vector2(shake_x + 7.0, -4.0))
	draw_colored_polygon(pts, bell_col)

	# Bell clapper
	draw_circle(Vector2(shake_x, 2.0), 2.0, Color(0.20, 0.18, 0.15))

	# Disabled X
	if is_disabled:
		draw_line(Vector2(-6, -8), Vector2(6, 4),
			Color(0.60, 0.15, 0.10, 0.80), 1.5)
		draw_line(Vector2(6, -8), Vector2(-6, 4),
			Color(0.60, 0.15, 0.10, 0.80), 1.5)
	elif in_range:
		draw_arc(Vector2.ZERO, 14.0, 0, TAU, 16, Color(0.95, 0.80, 0.20, 0.55), 1.2)
		# Hint label
		draw_string(ThemeDB.fallback_font, Vector2(-16, 18),
			"[E] Disable", HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(0.95, 0.88, 0.70, 0.85))
	elif not is_disabled:
		# Small warning glow
		draw_arc(Vector2.ZERO, 11.0, 0, TAU, 12, Color(0.85, 0.55, 0.10, 0.25), 1.0)
