extends Node2D

const INTERACT_RANGE = 18.0
const _BARREL_TEX = preload("res://sprites/prop_barrel.png")

var is_occupied := false
var _scrounged  := false

func _ready():
	add_to_group("interactable")
	add_to_group("hiding_spots")
	var sp := Sprite2D.new()
	sp.texture = _BARREL_TEX
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.offset = Vector2(0, -14)  # baseline (y=30) sits at node origin
	sp.scale = Vector2(0.85, 0.85)
	add_child(sp)

func _process(_delta):
	queue_redraw()

func is_in_range(player_pos: Vector2) -> bool:
	return global_position.distance_to(player_pos) <= INTERACT_RANGE

func interact(player):
	if is_occupied:
		return
	# Scrounge: first interaction while not hiding yields a random small reward
	if not _scrounged:
		_scrounged = true
		_do_scrounge(player)
		queue_redraw()
		return
	if player.has_method("enter_hiding_spot"):
		player.enter_hiding_spot(self)
		is_occupied = true
		queue_redraw()

func _do_scrounge(player):
	var roll := randi_range(1, 6)
	if roll <= 2:
		var gp1 := randi_range(5, 15)
		GameManager.add_gold(gp1)
		if player.has_method("_popup"):
			player._popup("Scrounged %dgp!" % gp1, Color(0.90, 0.72, 0.18))
	elif roll <= 4:
		GameManager.heal_hp(1)
		if player.has_method("_popup"):
			player._popup("Found bandage  +1 HP", Color(0.35, 0.90, 0.45))
	else:
		# Grant 1 crossbow bolt or 1 wand charge depending on player weapon
		var pw: String = player.get("weapon") if player.get("weapon") != null else "NONE"
		if pw in ["CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT"]:
			player.set("_crossbow_bolts", player.get("_crossbow_bolts") + 1)
			if player.has_method("_popup"):
				player._popup("Found a bolt!", Color(0.75, 0.55, 0.28))
		elif pw == "WAND":
			GameManager._wand_charges = min(GameManager._wand_charges + 1, 5)
			if player.has_method("_popup"):
				player._popup("Found an orb charge!", Color(0.65, 0.30, 0.95))
		else:
			var gp2 := randi_range(8, 20)
			GameManager.add_gold(gp2)
			if player.has_method("_popup"):
				player._popup("Scrounged %dgp!" % gp2, Color(0.90, 0.72, 0.18))

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
			if _scrounged:
				draw_arc(Vector2.ZERO, 9.0, 0, TAU, 16, Color(0.40, 0.38, 0.32, 0.40), 1.0)
			else:
				# Proximity cue: pulsing ring — brighter gold when carrying a body
				var carrying: bool = player.get("is_carrying_body") == true
				var rc := Color(0.95, 0.88, 0.50, 0.80) if carrying else Color(0.70, 0.60, 0.35, 0.60)
				draw_arc(Vector2.ZERO, 9.0, 0, TAU, 16, rc, 1.5)
