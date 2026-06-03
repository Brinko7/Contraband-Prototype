extends Node2D

var DURATION := 5.0
const RADIUS   := 34.0

var _t := 0.0

func _ready():
	add_to_group("smoke_clouds")
	if GameManager.has_passive("LOCKSMITH"):
		DURATION *= 1.5

func _process(delta):
	_t += delta
	if _t >= DURATION:
		queue_free()
	queue_redraw()

func contains(world_pos: Vector2) -> bool:
	return global_position.distance_to(world_pos) <= RADIUS

func _draw():
	var fade = 1.0 - (_t / DURATION)
	var a = fade * 0.72
	draw_circle(Vector2.ZERO,        RADIUS,        Color(0.55, 0.75, 0.45, a))
	draw_circle(Vector2(-9, -6),     RADIUS * 0.68, Color(0.60, 0.80, 0.50, a * 0.85))
	draw_circle(Vector2(11,  4),     RADIUS * 0.58, Color(0.65, 0.85, 0.55, a * 0.75))
	draw_circle(Vector2( 3, -10),    RADIUS * 0.50, Color(0.70, 0.90, 0.60, a * 0.65))
