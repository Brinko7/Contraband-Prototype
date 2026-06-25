extends Node2D

const TRIGGER_RANGE = 14.0

var _pulse_t   := 0.0
var _active    := false
var _triggered := false

func _ready():
	add_to_group("exits")
	set_process(true)

func _process(delta):
	_pulse_t += delta
	var player = get_tree().get_first_node_in_group("player")
	if player and player.get("has_loot"):
		_active = true
		if not _triggered and player.global_position.distance_to(global_position) <= TRIGGER_RANGE:
			_triggered = true
			_on_player_exits(player)
	queue_redraw()

func _on_player_exits(player: Node) -> void:
	if player.has_method("save_items"):
		player.call("save_items")

	# Collect floor rating from EvidenceSystem
	var rating_data: Dictionary = {}
	var es = get_tree().get_first_node_in_group("evidence_system")
	if es and es.has_method("get_end_of_floor_rating"):
		rating_data = es.get_end_of_floor_rating()
		# Apply bonus GP to player
		var bonus_gp: int = rating_data.get("bonus_gp", 0)
		if bonus_gp > 0:
			GameManager.add_gold(bonus_gp)
		# Apply rep bonus
		var rep: int = rating_data.get("rep_bonus", 0)
		if rep != 0 and GameManager.get("reputation") != null:
			GameManager.set("reputation", GameManager.get("reputation") + rep)

	# Show the floor results panel, then advance
	var panel_script = load("res://FloorResultsPanel.gd")
	if panel_script and not rating_data.is_empty():
		var panel := CanvasLayer.new()
		panel.set_script(panel_script)
		get_tree().root.add_child(panel)
		panel.setup(rating_data, _advance_floor)
	else:
		_advance_floor()

func _advance_floor() -> void:
	if GameManager.current_floor >= GameManager.MAX_FLOORS:
		GameManager.escaped()
	else:
		GameManager.enter_shop()

func _draw():
	var pulse := sin(_pulse_t * 4.0) * 0.15
	var is_final := GameManager.current_floor >= GameManager.MAX_FLOORS
	var font     := ThemeDB.fallback_font

	if _active:
		var gc := Color(0.1, 0.9, 0.3) if is_final else Color(0.3, 0.7, 1.0)
		# Layered glow pools
		draw_circle(Vector2.ZERO, 28.0, Color(gc.r, gc.g, gc.b, 0.06 + pulse * 0.5))
		draw_circle(Vector2.ZERO, 18.0, Color(gc.r, gc.g, gc.b, 0.14 + pulse * 0.5))
		draw_circle(Vector2.ZERO, 11.0, Color(gc.r, gc.g, gc.b, 0.30 + pulse))
		# Rotating arc ring
		var ring_a := _pulse_t * 1.2
		draw_arc(Vector2.ZERO, 14.0, ring_a, ring_a + TAU * 0.75, 24,
			Color(gc.r, gc.g, gc.b, 0.70 + pulse), 1.5)
		draw_arc(Vector2.ZERO, 14.0, ring_a + PI, ring_a + PI + TAU * 0.25, 8,
			Color(gc.r, gc.g, gc.b, 0.35), 1.0)
		# Up-arrow
		draw_line(Vector2(0,  5), Vector2(0, -7), gc, 2.5)
		draw_line(Vector2(0, -7), Vector2(-4, -3), gc, 2.0)
		draw_line(Vector2(0, -7), Vector2( 4, -3), gc, 2.0)
		# Label
		var label := "▲ ESCAPE" if is_final else "▲ SUPPLY CACHE"
		var lx := -10.0 if is_final else -18.0
		draw_string(font, Vector2(lx, -22),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(gc.r, gc.g, gc.b, 0.90))
	else:
		draw_circle(Vector2.ZERO, 10.0, Color(0.3, 0.3, 0.3, 0.18))
		draw_arc(Vector2.ZERO, 11.0, 0, TAU, 20, Color(0.5, 0.5, 0.5, 0.28), 1.0)
		draw_line(Vector2(0, 4), Vector2(0, -5), Color(0.5, 0.5, 0.5, 0.35), 1.5)
		draw_string(font, Vector2(-16, -18), "STAIRWELL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.4, 0.4, 0.4, 0.38))
