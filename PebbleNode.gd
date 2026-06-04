extends Node2D

var _direction: Vector2 = Vector2.RIGHT
var _speed: float = 160.0
var _tiles_left: int = 6
var _tile_size: int = 16
var _anim_t: float = 0.0
var _landed: bool = false
var _land_flash: float = 0.0

func setup(dir: Vector2, tiles: int):
	_direction = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	_tiles_left = tiles

func _process(delta: float):
	_anim_t += delta
	if _landed:
		_land_flash = max(0.0, _land_flash - delta * 3.0)
		if _land_flash <= 0.0:
			queue_free()
		queue_redraw()
		return

	var step := _direction * _speed * delta

	# Wall check — stop before solid tile
	var space := get_world_2d().direct_space_state
	var probe := PhysicsRayQueryParameters2D.create(global_position, global_position + step * 4.0)
	var hit := space.intersect_ray(probe)
	if not hit.is_empty() and (hit.get("collider") == null or not hit.collider.is_in_group("guards")):
		_land(global_position)
		return

	global_position += step
	var dist_moved := step.length()
	_tiles_left -= int(dist_moved / _tile_size)
	if _tiles_left <= 0:
		_land(global_position)
		return

	queue_redraw()

func _land(pos: Vector2):
	_landed = true
	_land_flash = 1.0
	global_position = pos
	# Alert nearby guards with a quiet noise — they'll investigate but not go alert
	for guard in get_tree().get_nodes_in_group("guards"):
		var dist: float = guard.global_position.distance_to(global_position)
		if dist <= 96.0 and guard.has_method("_become_suspicious"):
			guard._become_suspicious(global_position)
	queue_redraw()

func _draw():
	if _landed:
		var r := 6.0 + _land_flash * 4.0
		draw_arc(Vector2.ZERO, r, 0, TAU, 16, Color(0.85, 0.72, 0.30, _land_flash * 0.80), 1.5)
		draw_arc(Vector2.ZERO, r * 0.5, 0, TAU, 8, Color(1.0, 0.90, 0.50, _land_flash * 0.60), 1.0)
	else:
		var bob := sin(_anim_t * 18.0) * 1.5
		draw_circle(Vector2(0, bob), 2.5, Color(0.72, 0.62, 0.38, 0.90))
		# Trail
		draw_line(Vector2.ZERO, -_direction * 5.0, Color(0.72, 0.62, 0.38, 0.35), 1.0)
