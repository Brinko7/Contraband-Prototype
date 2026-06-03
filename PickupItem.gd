extends Node2D

const PICKUP_RANGE = 10.0

@export var item_type := 0  # 0=COIN 1=SMOKE 2=DART

const COLORS := {
	0: Color(0.95, 0.80, 0.10),
	1: Color(0.55, 0.90, 0.45),
	2: Color(0.30, 0.70, 0.95),
	4: Color(1.00, 0.95, 0.70),
	5: Color(0.55, 0.35, 0.90),
	6: Color(0.30, 0.20, 0.55),
}

var _bob_t     := 0.0
var _collected := false

func _process(delta):
	if _collected:
		return
	_bob_t += delta
	var player = get_tree().get_first_node_in_group("player")
	if player and global_position.distance_to(player.global_position) <= PICKUP_RANGE:
		_collect(player)
	queue_redraw()

func _collect(player: Node2D):
	_collected = true
	var count: int = 2 if GameManager.has_passive("SCAVENGER") else 1
	if player.has_method("add_item"):
		player.add_item(item_type, count)
	AudioManager.loot_collect()
	queue_free()

func _draw():
	var col: Color = COLORS.get(item_type, Color.WHITE)
	var bob := sin(_bob_t * 3.5) * 1.5
	# Glow ring
	draw_arc(Vector2(0, bob), 6.5, 0, TAU, 16, Color(col.r, col.g, col.b, 0.35), 1.0)
	# Body dot
	draw_circle(Vector2(0, bob), 3.5, col)
	# Inner shape — distinct per item type instead of a letter
	var inner := Color(0.0, 0.0, 0.0, 0.65)
	match item_type:
		0: # COIN — small circle (coin edge)
			draw_arc(Vector2(0, bob), 1.8, 0, TAU, 10, inner, 1.0)
		1: # SMOKE — three tiny dots in triangle
			draw_circle(Vector2(0,   bob - 1.8), 0.9, inner)
			draw_circle(Vector2(-1.5, bob + 1.0), 0.9, inner)
			draw_circle(Vector2( 1.5, bob + 1.0), 0.9, inner)
		2: # DART — thin vertical line (needle)
			draw_line(Vector2(0, bob - 2.0), Vector2(0, bob + 2.0), inner, 1.0)
		4: # FLASH — four-pointed star cross
			draw_line(Vector2(-2.0, bob), Vector2(2.0, bob), inner, 1.0)
			draw_line(Vector2(0, bob - 2.0), Vector2(0, bob + 2.0), inner, 1.0)
		5: # HOLD — concentric rings (binding)
			draw_arc(Vector2(0, bob), 1.2, 0, TAU, 10, inner, 1.0)
			draw_arc(Vector2(0, bob), 2.2, 0, TAU, 10, inner, 0.5)
		6: # SILENCE — horizontal dash (muted)
			draw_line(Vector2(-2.0, bob), Vector2(2.0, bob), inner, 1.2)
