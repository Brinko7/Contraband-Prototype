extends Node2D

# Spawned when a guard is taken down. Nearby unaware guards who approach will
# notice the body and become suspicious — a core stealth-game mechanic.
#
# V11: Hotline Miami-style tumble death animation — body flies in kill direction,
#      spins, leaves blood trail, then settles into final prone pose.

const DETECT_RANGE   = 36.0
const FADE_DURATION  = 180.0
const INTERACT_RANGE = 28.0

const _dice_scene = preload("res://DicePopup.tscn")

# SET_IRON bonus: extra discovery window (+6s reaction time before guards notice)
var _set_iron_grace := 0.0

var body_facing  := Vector2.RIGHT
var _discovered  := false
var _age         := 0.0
var _loot_pulse  := 0.0

# ── Hotline Miami death tumble ────────────────────────────────────────────────
const _TUMBLE_DUR: float = 0.55
var _tumble_t:      float   = 0.0   # counts down from TUMBLE_DUR
var _tumble_dir:    Vector2 = Vector2.ZERO
var _tumble_spin:   float   = 0.0   # radians/sec
var _trail:         Array   = []    # blood trail positions (local offsets)
var _trail_timer:   float   = 0.0

func _ready():
	add_to_group("bodies")
	add_to_group("interactable")
	if has_meta("body_facing"):
		body_facing = get_meta("body_facing")
	if get_meta("no_body", false):
		queue_free()
		return
	if GameManager.has_set_bonus("SET_IRON"):
		_set_iron_grace = 6.0

	# Start tumble animation if we have a kill direction
	if has_meta("kill_dir"):
		var kd: Vector2 = Vector2(get_meta("kill_dir"))
		if kd != Vector2.ZERO:
			_tumble_dir  = kd.normalized()
			_tumble_t    = _TUMBLE_DUR
			_tumble_spin = randf_range(9.0, 16.0) * (1.0 if randf() > 0.5 else -1.0)

func is_in_range(player_pos: Vector2) -> bool:
	return global_position.distance_to(player_pos) <= INTERACT_RANGE

func interact(player: Node2D):
	if get_meta("being_carried", false):
		return
	if get_meta("body_looted", false):
		return
	var loot: Array = get_meta("body_loot", [])
	if loot.is_empty():
		return
	set_meta("body_looted", true)
	var pop_offset := 0.0
	for entry in loot:
		var item_id: String = entry.get("id", "GOLD_PIECE")
		var val: int = entry.get("value", 0)
		var col: Color = entry.get("color", Color(0.95, 0.80, 0.10))
		var label: String
		if item_id == "GOLD_PIECE":
			label = "+%d gp" % val
		else:
			label = "%s (+%dgp)" % [entry.get("name", item_id), val]
		GameManager.add_gold(val)
		var popup = _dice_scene.instantiate()
		popup.setup(label, col)
		popup.global_position = global_position + Vector2(0, -18 - pop_offset)
		get_tree().root.add_child(popup)
		pop_offset += 14.0
	if player.has_method("emit_noise"):
		player.emit_noise(player.NoiseLevel.SILENT)
	queue_redraw()

func _process(delta):
	_age += delta

	# ── Tumble animation ──────────────────────────────────────────────────────
	if _tumble_t > 0.0:
		_tumble_t -= delta
		# Slide the node's actual position so body lands where it falls
		if _tumble_dir != Vector2.ZERO:
			var speed: float = 48.0 * (_tumble_t / _TUMBLE_DUR)  # decelerating
			position += _tumble_dir * speed * delta
		# Emit blood trail dots as world-space positions
		_trail_timer += delta
		if _trail_timer >= 0.05:
			_trail_timer = 0.0
			_trail.append(global_position)   # world pos at this moment
			if _trail.size() > 12:
				_trail.pop_front()
		queue_redraw()
		return   # skip guard-detection during tumble

	if _set_iron_grace > 0.0:
		_set_iron_grace -= delta
		queue_redraw()
		return
	queue_redraw()
	if _discovered:
		return
	if get_meta("being_carried", false):
		return
	for guard in get_tree().get_nodes_in_group("guards"):
		if guard.global_position.distance_to(global_position) <= DETECT_RANGE:
			var gs: int = guard.get("alert_state")
			if gs == 0:  # UNAWARE
				if guard.has_method("_find_body"):
					guard._find_body(global_position)
				_discovered = true
				break

func _draw():
	var alpha: float = clamp(1.0 - (_age / FADE_DURATION), 0.2, 0.85)
	var f: Vector2 = body_facing.normalized()
	var perp: Vector2 = f.rotated(PI * 0.5)

	# ── Blood trail during / after tumble ────────────────────────────────────
	# Draw world-space trail dots behind where the body slid (baked at emit time)
	if not _trail.is_empty() and _tumble_dir != Vector2.ZERO:
		var trail_count: int = _trail.size()
		for i in range(trail_count):
			var trail_alpha: float = float(i + 1) / float(trail_count) * 0.55 * alpha
			# Convert world position to local draw space
			var tpos: Vector2 = _trail[i] - global_position
			draw_circle(tpos, 1.8, Color(0.55, 0.06, 0.06, trail_alpha))
			# Fixed satellite droplets (deterministic offsets)
			if i % 3 == 0:
				var side: float = float(i % 2) * 2.0 - 1.0
				draw_circle(tpos + Vector2(side * 2.5, float(i % 5) - 2.0), 0.9,
					Color(0.45, 0.04, 0.04, trail_alpha * 0.70))

	# ── Tumble transform: spin rotation during death animation ────────────────
	# Node position moves during _process; here we just apply spin rotation.
	var tumbling: bool = _tumble_t > 0.0 and _tumble_dir != Vector2.ZERO
	if tumbling:
		var frac: float = clamp(1.0 - (_tumble_t / _TUMBLE_DUR), 0.0, 1.0)
		var spin_angle: float = _tumble_spin * frac * (PI * 1.5)  # up to 1.5 rotations
		draw_set_transform(Vector2.ZERO, spin_angle, Vector2.ONE)
		alpha = clamp(alpha, 0.70, 1.0)  # stay bright during tumble

	# Blood pool — outer dark spread
	var outer_pool: PackedVector2Array = PackedVector2Array()
	var n_outer: int = 16
	for i in range(n_outer):
		var a: float = float(i) / float(n_outer) * TAU
		var jitter: float = 1.0 + sin(float(i) * 2.3) * 0.18
		var rx: float = 9.5 * jitter
		var ry: float = 5.5 * jitter
		outer_pool.append(f * cos(a) * rx + perp * sin(a) * ry)
	draw_colored_polygon(outer_pool, Color(0.18, 0.04, 0.04, alpha * 0.35))

	# Blood pool — inner bright
	var inner_pool: PackedVector2Array = PackedVector2Array()
	var n_inner: int = 14
	for i in range(n_inner):
		var a: float = float(i) / float(n_inner) * TAU
		var jitter: float = 1.0 + cos(float(i) * 1.7) * 0.15
		var rx: float = 7.0 * jitter
		var ry: float = 4.0 * jitter
		inner_pool.append(f * cos(a) * rx + perp * sin(a) * ry + f * 0.5)
	draw_colored_polygon(inner_pool, Color(0.55, 0.08, 0.08, alpha * 0.65))

	# Blood splatter droplets
	for i in range(5):
		var sa: float = float(i) * 1.3
		var sd: Vector2 = f * cos(sa) * (9.0 + float(i)) + perp * sin(sa) * (5.0 + float(i) * 0.5)
		draw_circle(sd, 0.8, Color(0.45, 0.06, 0.06, alpha * 0.60))

	# Prone body — elongated polygon lying flat along facing
	var body_base: Color = Color(0.32, 0.30, 0.36, alpha * 0.92)
	var body_pts: PackedVector2Array = PackedVector2Array([
		f * 4.5 + perp * 2.0,
		f * 6.0 + perp * 1.0,
		f * 6.0 - perp * 1.0,
		f * 4.5 - perp * 2.0,
		-f * 5.0 - perp * 2.2,
		-f * 5.5 - perp * 1.0,
		-f * 5.5 + perp * 1.0,
		-f * 5.0 + perp * 2.2,
	])
	draw_colored_polygon(body_pts, body_base)
	# Tabard front stripe
	draw_colored_polygon(PackedVector2Array([
		f * 3.5 + perp * 0.8,
		f * 3.5 - perp * 0.8,
		-f * 4.5 - perp * 0.8,
		-f * 4.5 + perp * 0.8,
	]), Color(0.45, 0.12, 0.12, alpha * 0.85))
	# Chainmail dots
	for i in range(6):
		var dy: float = -3.5 + float(i) * 1.4
		draw_circle(f * dy + perp * 0.8, 0.3, Color(0.55, 0.50, 0.55, alpha * 0.6))
		draw_circle(f * dy - perp * 0.8, 0.3, Color(0.55, 0.50, 0.55, alpha * 0.6))

	# Outstretched arm
	var arm_shoulder: Vector2 = f * 3.5 + perp * 1.8
	var arm_hand: Vector2 = f * 5.0 + perp * 5.5
	draw_line(arm_shoulder, arm_hand, body_base, 1.6)
	draw_circle(arm_hand, 1.0, Color(0.75, 0.62, 0.50, alpha * 0.85))
	# Other arm tucked
	draw_line(f * 3.0 - perp * 1.8, f * 4.5 - perp * 3.5, body_base, 1.4)
	draw_circle(f * 4.5 - perp * 3.5, 0.9, Color(0.75, 0.62, 0.50, alpha * 0.85))

	# Legs splayed
	draw_line(-f * 3.0 + perp * 1.5, -f * 6.5 + perp * 3.5, body_base.darkened(0.15), 1.8)
	draw_line(-f * 3.0 - perp * 1.5, -f * 6.5 - perp * 3.0, body_base.darkened(0.15), 1.8)
	draw_circle(-f * 6.5 + perp * 3.5, 1.0, Color(0.16, 0.12, 0.08, alpha * 0.90))
	draw_circle(-f * 6.5 - perp * 3.0, 1.0, Color(0.16, 0.12, 0.08, alpha * 0.90))

	# Hair tuft at head position
	var head_pos: Vector2 = f * 5.5
	draw_circle(head_pos + perp * 0.3, 1.3, Color(0.30, 0.18, 0.08, alpha * 0.85))

	# Fallen helmet — knocked off, off to one side of head
	var helm_pos: Vector2 = f * 7.5 - perp * 2.5
	var helm_col: Color = Color(0.30, 0.28, 0.34, alpha * 0.92)
	draw_colored_polygon(PackedVector2Array([
		helm_pos + Vector2(-2.0, 0.5),
		helm_pos + Vector2(2.0, 0.5),
		helm_pos + Vector2(1.5, -1.8),
		helm_pos + Vector2(-1.5, -1.8),
	]), helm_col)
	# Helmet rim
	draw_line(helm_pos + Vector2(-2.0, 0.5), helm_pos + Vector2(2.0, 0.5), helm_col.darkened(0.30), 0.8)
	# Visor slit
	draw_rect(Rect2(helm_pos.x - 1.2, helm_pos.y - 0.6, 2.4, 0.6), Color(0.05, 0.04, 0.06, alpha * 0.95))
	# Helmet top highlight
	draw_line(helm_pos + Vector2(-1.5, -1.8), helm_pos + Vector2(1.5, -1.8), helm_col.lightened(0.20), 0.5)

	# "Discovered" glow when a guard has already noticed it
	if _discovered:
		var d_pulse: float = 0.30 + sin(_age * 3.0) * 0.10
		draw_arc(Vector2.ZERO, 10.5, 0, TAU, 22, Color(1.0, 0.55, 0.05, d_pulse), 1.4)
		draw_arc(Vector2.ZERO, 12.5, 0, TAU, 22, Color(1.0, 0.40, 0.05, d_pulse * 0.5), 0.8)

	# SET_IRON grace ring
	if _set_iron_grace > 0.0:
		var g: float = _set_iron_grace / 6.0
		draw_arc(Vector2.ZERO, 11.0, 0, TAU * g, 20, Color(0.55, 0.75, 0.95, 0.55), 1.4)

	# Loot indicator — pulsing gold coin
	var has_loot: bool = has_meta("body_loot") and not get_meta("body_looted", false)
	if has_loot:
		var pulse: float = sin(_age * 3.5) * 0.5 + 0.5
		var lift: float = -10.0 - pulse * 1.5
		var coin_pos: Vector2 = Vector2(0, lift)
		# Glow
		draw_arc(coin_pos, 4.5, 0, TAU, 14, Color(1.0, 0.85, 0.20, 0.20 + pulse * 0.20), 1.4)
		# Coin body
		draw_circle(coin_pos, 2.5, Color(0.95, 0.80, 0.15, 0.85 + pulse * 0.15))
		# Coin highlight
		draw_circle(coin_pos + Vector2(-0.7, -0.7), 1.0, Color(1.0, 0.95, 0.55, 0.90))
		# Coin rim
		draw_arc(coin_pos, 2.5, 0, TAU, 14, Color(0.65, 0.50, 0.08, 0.85), 0.4)
		# Star/sparkle
		var sp: float = pulse * 1.2
		draw_line(coin_pos + Vector2(0, -3.5 - sp), coin_pos + Vector2(0, -2.0 - sp), Color(1.0, 1.0, 0.70, 0.85), 0.6)
		draw_line(coin_pos + Vector2(-2.0, -2.5 - sp * 0.5), coin_pos + Vector2(2.0, -2.5 - sp * 0.5), Color(1.0, 1.0, 0.70, 0.6), 0.4)

	# Reset tumble transform at very end so UI indicators aren't offset
	if tumbling:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
