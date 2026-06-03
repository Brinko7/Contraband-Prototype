extends Node2D

const DURATION := 6.0
const RADIUS   := 40.0

var _t := 0.0

func _ready():
	add_to_group("silence_zones")

func _process(delta):
	_t += delta
	if _t >= DURATION:
		queue_free()
	queue_redraw()

func contains(world_pos: Vector2) -> bool:
	return global_position.distance_to(world_pos) <= RADIUS

func _draw():
	var fade: float = 1.0 - (_t / DURATION)
	var a: float = fade * 0.55
	draw_circle(Vector2.ZERO, RADIUS, Color(0.28, 0.10, 0.45, a))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, Color(0.60, 0.30, 0.90, a * 0.80), 1.5)
	# Inner shimmer rings
	var pulse: float = sin(_t * 3.0) * 0.5 + 0.5
	draw_arc(Vector2.ZERO, RADIUS * 0.55, 0, TAU, 24, Color(0.50, 0.20, 0.80, a * pulse * 0.45), 1.0)
	draw_arc(Vector2.ZERO, RADIUS * 0.30, 0, TAU, 16, Color(0.70, 0.40, 1.00, a * 0.35), 0.8)
