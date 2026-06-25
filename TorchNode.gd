extends Node2D

const INTERACT_RANGE = 22.0
const _TORCH_SHEET = preload("res://sprites/prop_torch.png")

var is_lit := true
var _anim_t := 0.0
var _sprite: Sprite2D

func _ready():
	add_to_group("torches")
	add_to_group("interactable")
	_sprite = Sprite2D.new()
	_sprite.texture = _TORCH_SHEET
	_sprite.hframes = 4
	_sprite.vframes = 1
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.offset = Vector2(0, -10)  # baseline (y=24) sits at node origin
	add_child(_sprite)

func _process(delta):
	_anim_t += delta
	if is_lit:
		_sprite.modulate = Color(1, 1, 1, 1)
		_sprite.frame = int(_anim_t * 8.0) % 4  # 4-frame flicker loop
	else:
		_sprite.modulate = Color(0.4, 0.4, 0.45, 1)  # dim, extinguished
		_sprite.frame = 0
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
