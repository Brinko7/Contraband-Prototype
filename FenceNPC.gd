## FenceNPC.gd  (V15)
## Black-market fence lurking in the Storeroom on floors 2+.
## Player can interact to sell all carried contraband loot at 150% value.
## Leaves after one transaction per floor. Draw: hooded figure in a crate alcove.
extends Node2D

const _dice_scene = preload("res://DicePopup.tscn")

var _t         := 0.0
var _sold      := false    # one transaction per floor
var _blink_t   := 0.0

func _ready() -> void:
	add_to_group("interactable")

func _process(delta: float) -> void:
	_t += delta
	_blink_t = maxf(_blink_t - delta, 0.0)
	queue_redraw()

func interact() -> void:
	if _sold:
		_popup("Already did business today. Come back next floor.", Color(0.60, 0.55, 0.45))
		return
	# Find contraband items in player inventory
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var loot_nodes := get_tree().get_nodes_in_group("carried_loot")
	# Scan LootTarget nodes that the player has picked up (marked is_contraband)
	# Simpler approach: check player's "collected_contraband" meta list
	var total_value := 0
	var sold_count  := 0
	if player.has_meta("contraband_value"):
		var cv: int = player.get_meta("contraband_value")
		if cv > 0:
			total_value = int(cv * 1.5)  # 150% fence value
			sold_count  = player.get_meta("contraband_count", 1)
			player.remove_meta("contraband_value")
			player.remove_meta("contraband_count")

	if total_value <= 0:
		_popup("Nothing to sell — bring me contraband.", Color(0.65, 0.55, 0.35))
		return

	GameManager.add_gold(total_value)
	MetaProgress.add_rep(clampi(sold_count * 8, 5, 40))
	_sold = true
	_blink_t = 0.4
	_popup("Sold! +%dgp  +rep  (fence premium)" % total_value, Color(0.90, 0.75, 0.20))
	queue_redraw()

func _popup(text: String, color: Color) -> void:
	var p := _dice_scene.instantiate()
	p.setup(text, color)
	p.global_position = global_position + Vector2(0, -28)
	get_tree().root.add_child(p)

func _draw() -> void:
	if _sold:
		# Gone — faded outline only
		draw_circle(Vector2.ZERO, 5.0, Color(0.35, 0.30, 0.25, 0.30))
		return

	var a: float = 1.0
	if _blink_t > 0.0:
		a = 0.4 + 0.6 * abs(sin(_blink_t * 25.0))

	# Crate shadow
	draw_set_transform(Vector2(1, 6), 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, 7.0, Color(0.0, 0.0, 0.0, 0.22 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Hooded cloak body
	var cloak_col := Color(0.22, 0.18, 0.15, a)
	var hood_col  := Color(0.16, 0.13, 0.10, a)
	var skin_col  := Color(0.72, 0.60, 0.48, a)
	var eye_col   := Color(0.95, 0.65, 0.10, a * (0.5 + 0.5 * abs(sin(_t * 2.5))))

	# Cloak lower body (wide triangle)
	var pts_body: PackedVector2Array = [
		Vector2(-6, 2), Vector2(6, 2), Vector2(8, 10), Vector2(-8, 10)
	]
	draw_colored_polygon(pts_body, cloak_col)

	# Torso
	draw_rect(Rect2(-4, -6, 8, 9), cloak_col)

	# Head / hood
	draw_circle(Vector2(0, -9), 5.5, hood_col)
	draw_arc(Vector2(0, -9), 5.5, 0, TAU, 16, Color(0.30, 0.25, 0.20, a * 0.6), 1.0)

	# Glowing eyes under hood
	draw_circle(Vector2(-2.0, -10.0), 1.2, eye_col)
	draw_circle(Vector2(2.0,  -10.0), 1.2, eye_col)

	# Hovering coin hint (slowly bobs)
	var coin_y: float = -18.0 + sin(_t * 3.2) * 1.5
	draw_circle(Vector2(0, coin_y), 3.0, Color(0.88, 0.72, 0.12, a * 0.75))
	draw_arc(Vector2(0, coin_y), 3.0, 0, TAU, 10, Color(0.70, 0.55, 0.05, a * 0.5), 1.0)

	# "FENCE" indicator above coin
	draw_line(Vector2(-8, coin_y - 5), Vector2(8, coin_y - 5),
		Color(0.55, 0.48, 0.22, a * 0.40), 0.8)
