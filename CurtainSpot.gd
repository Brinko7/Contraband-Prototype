extends Node2D

# Curtain hiding spot — better cover than a barrel (works even while walking).
# Downside: guards become suspicious if they pass near a disturbed curtain.

const INTERACT_RANGE  = 20.0
const DISTURB_RADIUS  = 55.0
const _CURTAIN_TEX    = preload("res://sprites/curtain_sprite.png")

var is_occupied   := false
var _disturbed    := false
var _disturb_t    := 0.0
var _t            := 0.0

var _sprite: Sprite2D

func _ready():
	add_to_group("interactable")
	add_to_group("hiding_spots")
	_sprite = Sprite2D.new()
	_sprite.texture = _CURTAIN_TEX
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(1.0, 1.0)
	add_child(_sprite)

func _process(delta):
	_t += delta
	if _disturbed:
		_disturb_t -= delta
		if _disturb_t <= 0.0:
			_disturbed = false
		else:
			# Alert nearby guards to SUSPICIOUS
			for g in get_tree().get_nodes_in_group("guards"):
				if global_position.distance_to(g.global_position) <= DISTURB_RADIUS:
					if g.get("alert_state") == 0:  # UNAWARE
						g.set("alert_state", 1)    # SUSPICIOUS
						g.set("investigate_pos", global_position)
						g.set("de_escalate_timer", 5.0)
	queue_redraw()

func is_in_range(player_pos: Vector2) -> bool:
	return global_position.distance_to(player_pos) <= INTERACT_RANGE

func interact(player):
	if is_occupied:
		return
	if player.has_method("enter_hiding_spot"):
		player.enter_hiding_spot(self)
		is_occupied  = true
		_disturbed   = true
		_disturb_t   = 4.0
		queue_redraw()

func release(player):
	is_occupied = false
	_disturbed  = true
	_disturb_t  = 4.0
	if player.has_method("exit_hiding_spot"):
		player.exit_hiding_spot()
	queue_redraw()

func accept_body(body: Node):
	if body and is_instance_valid(body):
		body.queue_free()
	queue_redraw()

func _draw():
	var pulse := sin(_t * 2.5) * 0.5 + 0.5
	# Tint sprite by state
	if _sprite != null:
		if is_occupied:
			_sprite.modulate = Color(0.75, 0.55, 0.90, 1.0)
		elif _disturbed:
			_sprite.modulate = Color(1.0, 0.80, 0.60, 1.0)
		else:
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if is_occupied:
		draw_arc(Vector2.ZERO, 14.0, 0, TAU, 16, Color(0.65, 0.35, 0.90, 0.45), 1.5)
	elif _disturbed:
		draw_arc(Vector2.ZERO, 14.0, 0, TAU, 16, Color(1.0, 0.65, 0.15, 0.30 + pulse * 0.25), 1.2)
	else:
		var player = get_tree().get_first_node_in_group("player")
		if player and is_in_range(player.global_position):
			draw_arc(Vector2.ZERO, 14.0, 0, TAU, 16, Color(0.70, 0.55, 0.85, 0.55), 1.5)
