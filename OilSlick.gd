extends Node2D

# Oil Slick tile — crossing at full speed stumbles the player (0.4s stun + noise).

var _t := 0.0

func _ready():
	add_to_group("hazard_tiles")

func _process(delta):
	_t += delta
	queue_redraw()
	var player = get_tree().get_first_node_in_group("player")
	if player and not player.get("is_hidden"):
		if global_position.distance_to(player.global_position) <= 10.0:
			_on_player_step(player)

func _on_player_step(player):
	var sneaking: bool = player.get("is_sneaking") == true
	if sneaking:
		return  # Sneaking = careful — no stumble
	# Apply stumble: lock movement briefly and emit quiet noise
	var cooldown = player.get("_move_cooldown")
	if cooldown != null and float(cooldown) < 0.08:
		player.set("_move_cooldown", 0.4)
		if player.has_method("emit_noise"):
			player.emit_noise(player.NoiseLevel.QUIET)
		# DicePopup feedback
		if player.has_method("_popup"):
			player._popup("Stumbled! (oil)", Color(0.60, 0.50, 0.25))

func _draw():
	var pulse: float = sin(_t * 0.8) * 0.5 + 0.5
	# Shimmering dark oil pool
	draw_ellipse_arc_approx(Vector2.ZERO, Vector2(10, 6),
		Color(0.15, 0.12, 0.05, 0.65 + pulse * 0.15))
	# Rainbow sheen highlights
	var sheen_cols := [
		Color(0.80, 0.45, 0.10, 0.25),
		Color(0.30, 0.70, 0.80, 0.20),
		Color(0.70, 0.20, 0.80, 0.20),
	]
	for i in range(sheen_cols.size()):
		var off := Vector2(float(i) - 1.0, 0.0)
		draw_ellipse_arc_approx(off, Vector2(7 - i, 4 - i), sheen_cols[i])

# Helper — draw filled ellipse via polygon approximation
func draw_ellipse_arc_approx(center: Vector2, radii: Vector2, color: Color):
	var pts := PackedVector2Array()
	var steps := 16
	for s in range(steps):
		var angle: float = TAU * float(s) / float(steps)
		pts.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(pts, color)
