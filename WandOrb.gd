extends Node2D

var _direction: Vector2 = Vector2.RIGHT
var _damage: int = 1
var _speed: float = 80.0
var _max_range: float = 160.0
var _traveled: float = 0.0
var _anim_t: float = 0.0
var _hit: bool = false
var _bounces: int = 0
const _MAX_BOUNCES := 2

func setup(dir: Vector2, dmg: int):
	_direction = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	_damage = dmg

func _process(delta: float):
	if _hit:
		queue_free()
		return

	_anim_t += delta
	var step: Vector2 = _direction * _speed * delta

	# Wall bounce: probe ahead using physics
	if get_world_2d() != null and _bounces < _MAX_BOUNCES:
		var space := get_world_2d().direct_space_state
		var probe_x := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(step.x, 0))
		var probe_y := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, step.y))
		var hit_x := space.intersect_ray(probe_x)
		var hit_y := space.intersect_ray(probe_y)
		if not hit_x.is_empty() and hit_x.get("collider") != null and not hit_x.collider.is_in_group("guards"):
			_direction.x *= -1.0
			_bounces += 1
			step.x *= -1.0
		if not hit_y.is_empty() and hit_y.get("collider") != null and not hit_y.collider.is_in_group("guards"):
			_direction.y *= -1.0
			_bounces += 1
			step.y *= -1.0

	global_position += step
	_traveled += step.length()

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
