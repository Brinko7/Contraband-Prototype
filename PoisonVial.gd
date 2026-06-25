extends Node2D

# Consumable pickup — collecting adds "POISON_VIAL" to player's item inventory.
# Drawn as a small green glass vial with stopper and liquid level.

var _bob_t: float = 0.0
var _collected: bool = false
var _collect_anim: float = 0.0  # 0→1 fade-out on collect

var _gm = null

func _ready() -> void:
	add_to_group("pickups")
	_gm = get_node_or_null("/root/GameManager")

func _process(delta: float) -> void:
	if _collected:
		_collect_anim += delta * 3.0
		if _collect_anim >= 1.0:
			queue_free()
			return
		queue_redraw()
		return

	_bob_t += delta
	queue_redraw()

	# Auto-pickup when player walks over
	var player := get_tree().get_first_node_in_group("player")
	if player and global_position.distance_to(player.global_position) <= 10.0:
		_do_collect(player)

func _do_collect(player: Node) -> void:
	if _collected:
		return
	_collected = true

	# Add to player inventory
	# Try items array (Dictionary style used by character_body_2d)
	var added := false
	var inv = player.get("items")
	if inv != null and typeof(inv) == TYPE_ARRAY:
		inv.append({ "name": "Poison Vial", "type": "POISON_VIAL", "color": Color(0.25, 0.75, 0.30) })
		added = true

	# Fallback: string item list
	if not added:
		var str_items = player.get("_string_items")
		if str_items != null:
			str_items.append("POISON_VIAL")
			added = true

	if player.has_method("_popup"):
		player._popup("Poison Vial collected!", Color(0.25, 0.85, 0.32))

	queue_redraw()

func _draw() -> void:
	var t := _bob_t
	var alpha := 1.0 - _collect_anim
	if alpha <= 0.0:
		return

	# Bobbing offset
	var bob := sin(t * 2.8) * 2.5

	# Glow aura
	var pulse := sin(t * 3.5) * 0.5 + 0.5
	draw_circle(Vector2(0, bob), 8.0, Color(0.20, 0.65, 0.28, (0.15 + pulse * 0.10) * alpha))

	# Vial body (rounded rectangle approximation)
	var vial_col := Color(0.22, 0.62, 0.30, alpha)
	var glass_col := Color(0.55, 0.90, 0.60, 0.65 * alpha)
	var base := Vector2(0, bob)

	# Vial outline (tall thin shape)
	var body_pts := PackedVector2Array()
	var h := 9.0
	var w := 3.5
	var r := 2.0
	# Rounded rectangle corners — bottom
	for i in range(9):
		var a := PI + float(i) / 8.0 * PI  # bottom arc
		body_pts.append(base + Vector2(cos(a) * r, h - r + sin(a) * r))
	# Sides
	body_pts.append(base + Vector2(-w, -h + r))
	# Top arc (round top)
	for i in range(9):
		var a := -PI + float(i) / 8.0 * PI
		body_pts.append(base + Vector2(cos(a) * r, -h + r + sin(a) * r))
	body_pts.append(base + Vector2(w, h - r))

	draw_colored_polygon(body_pts, vial_col)
	draw_polyline(body_pts + PackedVector2Array([body_pts[0]]), glass_col, 0.8)

	# Liquid level (fill bottom 65% of vial)
	var liquid_top := base + Vector2(0, -h * 0.05)
	var liquid_fill := h * 1.3
	var liquid_pts := PackedVector2Array()
	# Flat top line of liquid
	liquid_pts.append(base + Vector2(-w + 0.5, -h * 0.05))
	liquid_pts.append(base + Vector2(w - 0.5, -h * 0.05))
	# Down right side to bottom
	for i in range(9):
		var a := float(i) / 8.0 * PI  # right to left along bottom
		liquid_pts.append(base + Vector2(cos(a) * (r - 0.5), h - r + sin(a) * (r - 0.5)))
	draw_colored_polygon(liquid_pts, Color(0.18, 0.75, 0.28, 0.75 * alpha))

	# Liquid shimmer bubble
	var bub := sin(t * 5.0) * 0.3 + 0.3
	draw_circle(base + Vector2(-0.8, h * 0.2), 0.8 + bub * 0.4,
		Color(0.55, 0.95, 0.60, 0.50 * alpha))

	# Cork stopper
	var cork_col := Color(0.72, 0.58, 0.35, alpha)
	draw_rect(Rect2(base.x - r + 0.3, base.y - h - 1.0, (r - 0.3) * 2, 3.5), cork_col)
	draw_rect(Rect2(base.x - r + 0.3, base.y - h - 1.0, (r - 0.3) * 2, 3.5),
		Color(0.85, 0.70, 0.45, 0.5 * alpha), false, 0.7)

	# Wax seal dot on cork
	draw_circle(base + Vector2(0, -h + 0.8), 1.0, Color(0.70, 0.20, 0.20, 0.80 * alpha))

	# Collect sparkle burst
	if _collected and _collect_anim < 0.5:
		var burst := _collect_anim * 2.0
		for i in range(6):
			var sa := TAU * float(i) / 6.0
			var sp := base + Vector2(cos(sa), sin(sa)) * (8.0 + burst * 12.0)
			draw_circle(sp, 1.5 * (1.0 - burst), Color(0.35, 0.90, 0.40, (1.0 - burst) * alpha))
