extends Node2D

# A furniture shelf/bookcase the player can search (Investigation) or topple (Athletics).
# Toppling blocks the tile, stuns adjacent guards, and makes loud noise.
# Being crouched behind it gives +1 stealth DC vs guard detection.

const TILE_SIZE := 16
const INTERACT_RANGE := 22.0
const TOPPLE_STUN_RANGE := 32.0
const TOPPLE_NOISE_RADIUS := 90.0

enum ShelfType { BOOKCASE, WEAPON_RACK, SUPPLY_CRATE, TROPHY_SHELF, WINE_RACK }

@export var shelf_type: ShelfType = ShelfType.BOOKCASE

const _SHELF_TEX_PATH := {
	ShelfType.BOOKCASE:     "res://sprites/prop_bookcase.png",
	ShelfType.WEAPON_RACK:  "res://sprites/prop_weaponrack.png",
	ShelfType.SUPPLY_CRATE: "res://sprites/prop_crate.png",
	ShelfType.TROPHY_SHELF: "res://sprites/prop_trophyshelf.png",
	ShelfType.WINE_RACK:    "res://sprites/prop_winerack.png",
}
static var _shelf_tex_cache := {}

var _searched: bool = false
var _toppled: bool = false
var _topple_dir: Vector2 = Vector2.RIGHT  # which way it fell
var _topple_t: float = 0.0               # fall animation
var _topple_progress: float = 0.0
var _search_loot: Array = []             # filled by World.gd setup
var _t: float = 0.0

var _gm = null

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("furniture")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gm = get_node_or_null("/root/GameManager")

func _shelf_tex() -> Texture2D:
	var path: String = _SHELF_TEX_PATH.get(shelf_type, "")
	if path == "":
		return null
	if _shelf_tex_cache.has(path):
		return _shelf_tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_shelf_tex_cache[path] = tex
	return tex

func is_in_range(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= INTERACT_RANGE

func interact(player: Node) -> void:
	if _toppled:
		return
	# Context-sensitive: if player's facing is TOWARD shelf strongly, offer topple
	# Otherwise default to search
	var facing: Vector2 = player.get("facing") if player.get("facing") != null else Vector2.ZERO
	var to_shelf: Vector2 = (global_position - player.global_position).normalized()
	var dot: float = facing.dot(to_shelf)

	if dot > 0.7 and not _searched:
		# Player is facing the shelf squarely — present choice:
		# Search first (natural default), topple is a secondary use
		search(player)
	elif dot > 0.7 and _searched:
		# Already searched — try topple since they're facing it
		topple(player, facing)
	else:
		search(player)

func search(player: Node) -> void:
	if _searched:
		if player.has_method("_popup"):
			player._popup("Already searched.", Color(0.55, 0.50, 0.42))
		return

	_searched = true

	# Determine DC based on class/passive
	var dc := 10
	if _gm and _gm.has_method("has_passive") and _gm.has_passive("KEEN_EYE"):
		dc = 7

	var roll: int = _roll_d20()
	var dice_scene = load("res://DicePopup.tscn")

	if roll >= dc:
		# Success — give loot or intel
		if not _search_loot.is_empty():
			var loot = _search_loot.pop_front()
			_grant_loot(player, loot)
		else:
			# Fallback random loot by shelf type
			_grant_default_loot(player, roll)
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Search %d ✓ — found something!" % roll, Color(0.40, 0.90, 0.45))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)
	else:
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Search %d ✗ — nothing useful" % roll, Color(0.55, 0.50, 0.42))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)

	queue_redraw()

func topple(player: Node, direction: Vector2) -> void:
	if _toppled:
		return

	# Athletics check
	var dc := 11
	if _gm and _gm.has_method("has_passive") and _gm.has_passive("BRUTE"):
		dc = 7

	var roll: int = _roll_d20()
	var dice_scene = load("res://DicePopup.tscn")

	if roll >= dc:
		_toppled = true
		_topple_dir = direction.normalized() if direction.length() > 0.01 else Vector2.RIGHT
		_topple_t = 0.0

		# Stun guards in range (those on the topple side)
		for guard in get_tree().get_nodes_in_group("guards"):
			var dist: float = (guard.global_position as Vector2).distance_to(global_position)
			if dist <= TOPPLE_STUN_RANGE:
				var to_g: Vector2 = (guard.global_position - global_position).normalized()
				if to_g.dot(_topple_dir) > 0.3:
					if guard.has_method("apply_stun"):
						guard.apply_stun(1.8)
					elif guard.has_method("hurt"):
						guard.hurt(1, _topple_dir)

		# Noise
		for guard in get_tree().get_nodes_in_group("guards"):
			if guard.global_position.distance_to(global_position) <= TOPPLE_NOISE_RADIUS:
				if guard.has_method("_on_noise_emitted"):
					guard._on_noise_emitted(2, global_position)

		if _gm and _gm.has_method("shake"):
			_gm.shake(3.5, 0.25)

		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Topple %d ✓ — CRASH!" % roll, Color(0.90, 0.65, 0.15))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)
	else:
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Topple %d ✗ — too heavy" % roll, Color(0.75, 0.30, 0.20))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)

	queue_redraw()

func _roll_d20() -> int:
	if _gm and _gm.has_method("roll_d20"):
		return _gm.roll_d20()
	return randi_range(1, 20)

func _grant_loot(player: Node, loot) -> void:
	# loot is a dict: { "type": String, "amount": int }
	if typeof(loot) != TYPE_DICTIONARY:
		return
	var ltype: String = loot.get("type", "gold")
	var amount: int = loot.get("amount", 10)
	if ltype == "gold" and _gm:
		_gm.add_gold(amount)
		if player.has_method("_popup"):
			player._popup("+%dgp (hidden cache)" % amount, Color(0.95, 0.80, 0.10))
	elif ltype == "intel":
		# Flash guard positions to player for 6s
		if player.has_method("set"):
			player.set("_patrol_reveal_timer", 6.0)
		if player.has_method("_popup"):
			player._popup("Intel! (patrol routes revealed)", Color(0.40, 0.80, 0.90))
	elif ltype == "item":
		# Grant a random item
		if player.has_method("_popup"):
			player._popup("Found item: %s!" % ltype, Color(0.55, 0.85, 0.55))

func _grant_default_loot(player: Node, roll: int) -> void:
	match shelf_type:
		ShelfType.BOOKCASE:
			# Notes/intel
			if player.has_method("set"):
				player.set("_patrol_reveal_timer", 5.0)
			if player.has_method("_popup"):
				player._popup("Found patrol notes!", Color(0.55, 0.75, 0.95))
		ShelfType.WEAPON_RACK:
			# Chance of dart or bolt
			if player.has_method("_popup"):
				player._popup("Weapon rack — nothing usable", Color(0.55, 0.50, 0.42))
			if roll >= 15 and _gm:
				_gm.add_gold(20)
		ShelfType.SUPPLY_CRATE:
			if _gm:
				_gm.heal_hp(2)
			if player.has_method("_popup"):
				player._popup("Supplies — +2 HP!", Color(0.35, 0.90, 0.45))
		ShelfType.TROPHY_SHELF:
			var gp := randi_range(25, 60)
			if _gm:
				_gm.add_gold(gp)
			if player.has_method("_popup"):
				player._popup("Trophy — +%dgp!" % gp, Color(0.95, 0.80, 0.10))
		ShelfType.WINE_RACK:
			# Reveal drunk guard nearby or just gold
			if _gm:
				_gm.add_gold(15)
			if player.has_method("_popup"):
				player._popup("Fine wine — +15gp!", Color(0.70, 0.25, 0.55))

func provides_cover_bonus(player_pos: Vector2, guard_pos: Vector2) -> bool:
	# Returns true if shelf is between player and guard, giving cover bonus
	if _toppled:
		return false
	var pp := player_pos
	var gp := guard_pos
	var sp := global_position
	# Simple check: shelf is within 18px of the line from player to guard
	var seg_len: float = pp.distance_to(gp)
	if seg_len < 1.0:
		return false
	var seg_dir: Vector2 = (gp - pp) / seg_len
	var to_shelf: Vector2 = sp - pp
	var proj: float = to_shelf.dot(seg_dir)
	if proj <= 0.0 or proj >= seg_len:
		return false
	var closest: Vector2 = pp + seg_dir * proj
	return closest.distance_to(sp) <= 10.0

func _process(delta: float) -> void:
	_t += delta
	if _toppled and _topple_progress < 1.0:
		_topple_t += delta
		_topple_progress = minf(_topple_t / 0.4, 1.0)
	queue_redraw()

func _draw() -> void:
	if _toppled:
		_draw_toppled()
		return

	# Grounding contact shadow — anchors the piece on the lit floor.
	draw_colored_polygon(_ground_ellipse(Vector2(1.5, 13.0), 12.0, 4.0), Color(0, 0, 0, 0.16))
	draw_colored_polygon(_ground_ellipse(Vector2(0.5, 12.5), 9.5, 3.0), Color(0, 0, 0, 0.30))

	var tex: Texture2D = _shelf_tex()
	if tex != null:
		# 28x32 frame, baseline y=30 lands on the ground point (node-local y≈13).
		draw_texture_rect(tex, Rect2(Vector2(-14, -17), Vector2(28, 32)), false)
	else:
		match shelf_type:
			ShelfType.BOOKCASE:    _draw_bookcase()
			ShelfType.WEAPON_RACK: _draw_weapon_rack()
			ShelfType.SUPPLY_CRATE: _draw_supply_crate()
			ShelfType.TROPHY_SHELF: _draw_trophy_shelf()
			ShelfType.WINE_RACK:   _draw_wine_rack()
		# Warm torch catch-light along the top edge — ties the piece to scene lighting.
		var top_y: float = -14.0 if shelf_type == ShelfType.TROPHY_SHELF else -12.0
		draw_line(Vector2(-9, top_y + 0.4), Vector2(5, top_y + 0.4), Color(1.0, 0.84, 0.56, 0.30), 0.8)

	# Interaction prompt ring
	var player := get_tree().get_first_node_in_group("player")
	if player and is_in_range(player.global_position) and not _toppled:
		var ring_col := Color(0.95, 0.88, 0.50, 0.55) if not _searched else Color(0.50, 0.48, 0.38, 0.40)
		draw_arc(Vector2.ZERO, 14.0, 0, TAU, 20, ring_col, 1.2)

func _draw_bookcase() -> void:
	var t := _t
	# Frame
	draw_rect(Rect2(-10, -12, 20, 24), Color(0.45, 0.32, 0.18))
	draw_rect(Rect2(-10, -12, 20, 24), Color(0.60, 0.44, 0.25), false, 1.0)
	# Three shelves with books
	var book_colors := [
		Color(0.80, 0.25, 0.20), Color(0.25, 0.50, 0.80),
		Color(0.22, 0.60, 0.30), Color(0.75, 0.65, 0.20),
		Color(0.55, 0.25, 0.70), Color(0.80, 0.45, 0.15)
	]
	for row in range(3):
		var ry := -8 + row * 8
		draw_line(Vector2(-10, ry + 6), Vector2(10, ry + 6), Color(0.38, 0.26, 0.14), 1.0)
		var bx := -9
		var col_idx := (row * 3) % book_colors.size()
		while bx < 8:
			var bw := randi_range(2, 4) if not Engine.is_editor_hint() else 3
			bw = (row + col_idx + bx + 3) % 3 + 2  # deterministic width
			draw_rect(Rect2(bx, ry, bw, 5), book_colors[col_idx % book_colors.size()])
			bx += bw + 1
			col_idx += 1
	if _searched:
		# Books slightly displaced / gaps visible
		draw_rect(Rect2(-4, -8, 3, 5), Color(0.30, 0.22, 0.12))  # gap
		draw_rect(Rect2(3, 0, 2, 5), Color(0.30, 0.22, 0.12))

func _draw_weapon_rack() -> void:
	# Cross frame
	draw_rect(Rect2(-10, -12, 20, 24), Color(0.35, 0.28, 0.18))
	draw_rect(Rect2(-10, -12, 20, 24), Color(0.55, 0.45, 0.28), false, 1.0)
	# Horizontal bar in middle
	draw_line(Vector2(-8, 0), Vector2(8, 0), Color(0.55, 0.45, 0.28), 2.0)
	# Weapons: two crossed swords top, spear vertical, axe bottom
	# Sword 1 (diagonal)
	draw_line(Vector2(-7, -10), Vector2(4, -2), Color(0.75, 0.75, 0.80), 1.5)
	draw_rect(Rect2(-8, -11, 3, 1.5), Color(0.55, 0.45, 0.20))  # guard
	# Sword 2 (other diagonal)
	draw_line(Vector2(7, -10), Vector2(-4, -2), Color(0.75, 0.75, 0.80), 1.5)
	draw_rect(Rect2(6, -11, 3, 1.5), Color(0.55, 0.45, 0.20))
	# Spear (vertical, lower section)
	draw_line(Vector2(0, 1), Vector2(0, 10), Color(0.60, 0.45, 0.25), 1.5)
	draw_polygon([Vector2(-2, 1), Vector2(2, 1), Vector2(0, -4)], [Color(0.70, 0.70, 0.75)])
	if _searched:
		# Gap where item was taken
		draw_line(Vector2(0, 1), Vector2(0, 10), Color(0.30, 0.22, 0.12), 2.0)

func _draw_supply_crate() -> void:
	# Crate box shape
	draw_rect(Rect2(-10, -8, 20, 16), Color(0.50, 0.38, 0.20))
	draw_rect(Rect2(-10, -8, 20, 16), Color(0.68, 0.52, 0.28), false, 1.2)
	# Cross-bands
	draw_line(Vector2(-10, 0), Vector2(10, 0), Color(0.55, 0.42, 0.22), 1.0)
	draw_line(Vector2(0, -8), Vector2(0, 8), Color(0.55, 0.42, 0.22), 1.0)
	# Metal corner brackets
	for cx in [-10, 8]:
		for cy in [-8, 6]:
			draw_rect(Rect2(cx, cy, 2, 2), Color(0.65, 0.60, 0.45))
	if _searched:
		# Lid ajar
		draw_line(Vector2(-8, -8), Vector2(8, -10), Color(0.50, 0.38, 0.20), 2.5)
		draw_line(Vector2(-8, -8), Vector2(-10, -8), Color(0.65, 0.52, 0.28), 1.0)

func _draw_trophy_shelf() -> void:
	# Wall-mounted style shelf
	draw_rect(Rect2(-12, -14, 24, 4), Color(0.45, 0.35, 0.20))
	draw_rect(Rect2(-12, -14, 24, 4), Color(0.65, 0.50, 0.28), false, 1.0)
	draw_rect(Rect2(-10, -10, 20, 3), Color(0.42, 0.32, 0.18))  # mid shelf
	draw_rect(Rect2(-10, 2, 20, 3), Color(0.42, 0.32, 0.18))    # low shelf
	# Trophy items: skull top, vase mid, coins/gems bottom
	# Skull
	draw_circle(Vector2(-5, -18), 4.0, Color(0.88, 0.85, 0.78))
	draw_circle(Vector2(-5, -18), 4.0, Color(0.65, 0.60, 0.52), false, 1.0)
	draw_circle(Vector2(-6.5, -17.5), 1.0, Color(0.20, 0.18, 0.15))
	draw_circle(Vector2(-3.5, -17.5), 1.0, Color(0.20, 0.18, 0.15))
	# Vase (mid shelf)
	draw_circle(Vector2(4, -8), 3.5, Color(0.70, 0.40, 0.20))
	draw_arc(Vector2(4, -8), 3.5, 0, TAU, 12, Color(0.85, 0.55, 0.25), 1.0)
	# Gem (bottom)
	var gem_pts := PackedVector2Array([
		Vector2(2, 5), Vector2(5, 3), Vector2(7, 5), Vector2(5, 8)
	])
	draw_colored_polygon(gem_pts, Color(0.30, 0.70, 0.90, 0.85))
	if _searched:
		draw_line(Vector2(-5, -22), Vector2(-8, -20), Color(0.65, 0.60, 0.52), 1.0)  # skull tilted

func _draw_wine_rack() -> void:
	# Grid of wine bottles
	draw_rect(Rect2(-11, -13, 22, 26), Color(0.38, 0.28, 0.18))
	draw_rect(Rect2(-11, -13, 22, 26), Color(0.52, 0.40, 0.22), false, 1.0)
	# 3x2 bottle grid
	var bottle_col := Color(0.20, 0.42, 0.22)
	var neck_col := Color(0.22, 0.48, 0.25)
	for row in range(2):
		for col in range(3):
			var bx := -8 + col * 7
			var by := -9 + row * 11
			# Bottle body circle
			draw_circle(Vector2(bx, by + 4), 3.0, bottle_col)
			draw_circle(Vector2(bx, by + 4), 3.0, neck_col, false, 0.8)
			# Neck
			draw_rect(Rect2(bx - 1.2, by - 3, 2.4, 4), neck_col)
			# Cork
			draw_rect(Rect2(bx - 1.0, by - 4, 2.0, 1.5), Color(0.72, 0.58, 0.35))
	if _searched:
		# One bottle gap / fallen bottle
		draw_circle(Vector2(-8, -5), 3.0, Color(0.30, 0.25, 0.18))
		draw_line(Vector2(-5, -7), Vector2(-1, -5), neck_col, 1.5)

func _draw_toppled() -> void:
	# Draw at rotation based on fall direction, with progress
	var angle_target := _topple_dir.angle() + PI * 0.5
	var current_angle := angle_target * _ease_out(_topple_progress)

	draw_set_transform(Vector2(_topple_dir.x * 10 * _topple_progress,
		_topple_dir.y * 10 * _topple_progress), current_angle, Vector2.ONE)

	# Draw the shelf lying flat — sprite under the fall transform.
	var ttex: Texture2D = _shelf_tex()
	if ttex != null:
		draw_texture_rect(ttex, Rect2(Vector2(-14, -17), Vector2(28, 32)), false,
			Color(0.82, 0.78, 0.74, 1.0))
	else:
		draw_rect(Rect2(-12, -10, 24, 20), Color(0.42, 0.32, 0.18))
		draw_rect(Rect2(-12, -10, 24, 20), Color(0.60, 0.46, 0.25), false, 1.2)

	# Dust cloud
	if _topple_progress < 1.0:
		draw_circle(Vector2.ZERO, 16.0 * (1.0 - _topple_progress),
			Color(0.70, 0.65, 0.55, 0.30 * (1.0 - _topple_progress)))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

func _ground_ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(14):
		var a: float = float(i) / 14.0 * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
