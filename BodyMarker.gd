extends Node2D

# Spawned when a guard is taken down. Nearby unaware guards who approach will
# notice the body and become suspicious — a core stealth-game mechanic.

const DETECT_RANGE   = 36.0
const FADE_DURATION  = 180.0

# SET_IRON bonus: extra discovery window (+6s reaction time before guards notice)
var _set_iron_grace := 0.0

var body_facing  := Vector2.RIGHT
var _discovered  := false
var _age         := 0.0

func _ready():
	add_to_group("bodies")
	if has_meta("body_facing"):
		body_facing = get_meta("body_facing")
	if get_meta("no_body", false):
		queue_free()
		return
	if GameManager.has_gear_effect("SET_IRON"):
		_set_iron_grace = 6.0

func _process(delta):
	_age += delta
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
	var perp  := body_facing.rotated(PI * 0.5)

	# Ground shadow pool
	draw_circle(Vector2.ZERO, 7.0, Color(0.0, 0.0, 0.0, alpha * 0.40))

	# Prone torso (elongated along body_facing)
	var body_col := Color(0.28, 0.08, 0.08, alpha * 0.90)
	draw_colored_polygon(PackedVector2Array([
		body_facing * 6.0 + perp * 3.0,
		body_facing * 6.0 - perp * 3.0,
		-body_facing * 5.0 - perp * 2.5,
		-body_facing * 5.0 + perp * 2.5,
	]), body_col)

	# Helmet silhouette at "head" end
	draw_circle(body_facing * 5.5, 2.8, Color(0.22, 0.22, 0.26, alpha * 0.85))

	# "Discovered" glow when a guard has already noticed it
	if _discovered:
		draw_arc(Vector2.ZERO, 8.5, 0, TAU, 16, Color(1.0, 0.55, 0.05, 0.30), 1.0)
