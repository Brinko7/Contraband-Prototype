extends Node2D

const INTERACT_RANGE = 22.0
const _TORCH_SHEET = preload("res://sprites/torch_sheet.png")

var is_lit := true
var _anim_t := 0.0
var _sprite: Sprite2D

func _ready():
	add_to_group("torches")
	add_to_group("interactable")
	_sprite = Sprite2D.new()
	_sprite.texture = _TORCH_SHEET
	_sprite.hframes = 3
	_sprite.vframes = 1
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(2.0, 2.0)
	add_child(_sprite)

func _process(delta):
	_anim_t += delta
	if is_lit:
		_sprite.frame = int(_anim_t * 6.0) % 2  # alternate frames 0-1
	else:
		_sprite.frame = 2  # unlit frame
	queue_redraw()

func is_in_range(player_pos: Vector2) -> bool:
	return global_position.distance_to(player_pos) <= INTERACT_RANGE

func interact(_player):
	if not is_lit:
		return
	is_lit = false
	queue_redraw()
	for lm in get_tree().get_nodes_in_group("levelmap"):
		lm.queue_redraw()

func _draw():
	var player = get_tree().get_first_node_in_group("player")
	var in_range := player != null and is_in_range(player.global_position)
	if not is_lit:
		if in_range:
			draw_arc(Vector2.ZERO, 10.0, 0, TAU * 0.65, 10, Color(0.45, 0.38, 0.28, 0.50), 1.0)
	elif in_range:
		draw_arc(Vector2.ZERO, 12.0, 0, TAU, 16, Color(0.95, 0.88, 0.50, 0.70), 1.5)
