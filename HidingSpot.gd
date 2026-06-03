extends Node2D

const INTERACT_RANGE = 18.0
const _BARREL_TEX = preload("res://sprites/barrel_sprite.png")

var is_occupied := false

func _ready():
	add_to_group("interactable")
	add_to_group("hiding_spots")
	var sp := Sprite2D.new()
	sp.texture = _BARREL_TEX
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.scale = Vector2(1.5, 1.5)
	add_child(sp)

func _process(_delta):
	queue_redraw()

func is_in_range(player_pos: Vector2) -> bool:
	return global_position.distance_to(player_pos) <= INTERACT_RANGE

func interact(player):
	if is_occupied:
		return
	if player.has_method("enter_hiding_spot"):
		player.enter_hiding_spot(self)
		is_occupied = true
		queue_redraw()

func release(player):
	is_occupied = false
	if player.has_method("exit_hiding_spot"):
		player.exit_hiding_spot()
	queue_redraw()

func accept_body(body: Node):
	if body and is_instance_valid(body):
		body.queue_free()
	queue_redraw()

func _draw():
	if is_occupied:
		draw_arc(Vector2.ZERO, 9.0, 0, TAU, 16, Color(0.55, 0.30, 0.95, 0.40), 1.2)
	else:
		var player = get_tree().get_first_node_in_group("player")
		if player and is_in_range(player.global_position):
			# Proximity cue: pulsing ring — brighter gold when carrying a body
			var carrying: bool = player.get("is_carrying_body") == true
			var rc := Color(0.95, 0.88, 0.50, 0.80) if carrying else Color(0.70, 0.60, 0.35, 0.60)
			draw_arc(Vector2.ZERO, 9.0, 0, TAU, 16, rc, 1.5)
