extends Node2D

var _direction: Vector2 = Vector2.RIGHT
var _damage: int = 1
var _speed: float = 80.0
var _max_range: float = 96.0
var _traveled: float = 0.0
var _anim_t: float = 0.0
var _hit: bool = false

func setup(dir: Vector2, dmg: int):
	_direction = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	_damage = dmg

func _process(delta):
	if _hit:
		queue_free()
		return

	_anim_t += delta
	var move := _direction * _speed * delta
	global_position += move
	_traveled += move.length()

	# Check guard collision
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= 8.0:
			if guard.has_method("hurt"):
				guard.hurt(_damage)
			_hit = true
			return

	if _traveled >= _max_range:
		queue_free()
		return

	queue_redraw()

func _draw():
	var pulse := sin(_anim_t * 12.0) * 0.5 + 0.5
	var col := Color(0.65, 0.25, 1.00, 0.90)
	draw_circle(Vector2.ZERO, 4.0 + pulse * 1.5, col)
	draw_arc(Vector2.ZERO, 7.0, 0, TAU, 16, Color(col.r, col.g, col.b, 0.35 + pulse * 0.15), 1.5)
	# Trail
	draw_line(Vector2.ZERO, -_direction * 8.0, Color(col.r, col.g, col.b, 0.25), 2.0)
