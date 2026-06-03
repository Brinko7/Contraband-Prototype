extends Node2D

# Broken Glass tile — stepping on it while not sneaking emits loud noise.

var _t := 0.0
var _triggered := false   # permanently triggered after first step (glass breaks visually)

func _ready():
	add_to_group("hazard_tiles")

func _process(delta):
	_t += delta
	queue_redraw()
	# Check if player is on this tile
	var player = get_tree().get_first_node_in_group("player")
	if player and not player.get("is_hidden"):
		if global_position.distance_to(player.global_position) <= 10.0:
			_on_player_step(player)

func _on_player_step(player):
	var sneaking: bool = player.get("is_sneaking") == true
	if sneaking:
		return
	# GLASS_IMMUNE (Ironshod Boots): don't shatter
	if GameManager.has_gear_effect("GLASS_IMMUNE"):
		return
	# IRON set bonus: no effect
	if GameManager.has_gear_effect("SET_IRON"):
		return
	if not _triggered:
		_triggered = true
	# Emit loud noise from this position
	if player.has_method("emit_noise"):
		player.emit_noise(player.NoiseLevel.LOUD)
	# Also direct signal to guards
	for guard in get_tree().get_nodes_in_group("guards"):
		if guard.has_method("_on_noise_emitted"):
			guard._on_noise_emitted(player.NoiseLevel.LOUD, global_position)

func _draw():
	var pulse: float = abs(sin(_t * 1.5)) * 0.4
	if _triggered:
		# Shattered state — scattered shards
		var shard_positions := [
			Vector2(-4, -2), Vector2(2, -4), Vector2(5, 1),
			Vector2(-2, 3), Vector2(0, 0), Vector2(3, -2),
		]
		for sp in shard_positions:
			var sp_vec: Vector2 = sp
			draw_line(sp_vec, sp_vec + Vector2(2, 1), Color(0.75, 0.88, 0.95, 0.55), 1.0)
		draw_circle(Vector2.ZERO, 2.0, Color(0.65, 0.80, 0.90, 0.20))
	else:
		# Intact glass — faint sheen
		draw_rect(Rect2(-5, -3, 10, 6), Color(0.70, 0.85, 0.95, 0.12 + pulse * 0.08))
		draw_rect(Rect2(-5, -3, 10, 6), Color(0.75, 0.90, 1.00, 0.30), false, 1.0)
		# Glint lines
		draw_line(Vector2(-3, -2), Vector2(1, 2), Color(1.0, 1.0, 1.0, 0.35), 0.8)
		draw_line(Vector2(2, -2), Vector2(4, 0), Color(1.0, 1.0, 1.0, 0.25), 0.8)
