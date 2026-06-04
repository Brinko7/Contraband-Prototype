extends Node2D

signal looted

const INTERACT_RANGE = 20.0
const _dice_scene = preload("res://DicePopup.tscn")

@export var is_bonus := false
@export var loot_value := 200
@export var rarity: int = 0  # GameManager.Rarity: 0=COMMON, 1=UNCOMMON, 2=RARE

# Chest type: 0=iron, 1=ornate, 2=arcane
@export var chest_type: int = 0

var _bob_t := 0.0
var _opened := false

func _ready():
	# Auto-select chest visual based on rarity
	if is_bonus: chest_type = 2
	elif rarity >= 2: chest_type = 1
	else: chest_type = 0

func _process(delta):
	_bob_t += delta
	queue_redraw()

func _draw():
	var player = get_tree().get_first_node_in_group("player")
	var in_range := player != null and is_in_range(player.global_position)
	var pulse := sin(_bob_t * 3.2) * 0.5 + 0.5
	var glow_col := _get_glow_color()

	# Outer glow
	var glow_r := 14.0 + sin(_bob_t * 2.8) * 1.2
	draw_circle(Vector2(0.5, 1.0), glow_r, Color(glow_col.r, glow_col.g, glow_col.b, 0.06 + pulse * 0.04))

	# Draw the chest body
	if _opened:
		_draw_chest_open(glow_col, pulse)
	else:
		_draw_chest_closed(glow_col, pulse)

	# Interaction prompt ring
	if in_range and not _opened:
		draw_arc(Vector2.ZERO, 16.0 + pulse * 1.5, 0, TAU, 24,
			Color(0.95, 0.90, 0.60, 0.65 + pulse * 0.20), 1.5)

func _get_glow_color() -> Color:
	if is_bonus: return Color(0.35, 0.65, 1.00)
	match rarity:
		2: return Color(0.28, 0.55, 1.00)
		1: return Color(0.28, 0.82, 0.45)
		_: return Color(0.92, 0.75, 0.18)

func _draw_chest_closed(glow_col: Color, pulse: float):
	# Ground shadow for all chest types
	draw_ellipse_filled(Vector2(0, 7), 11.0, 2.4, Color(0, 0, 0, 0.50))

	match chest_type:
		0: _draw_iron_chest(glow_col, pulse)
		1: _draw_ornate_chest(glow_col, pulse)
		2: _draw_arcane_chest(glow_col, pulse)
		_: draw_rect(Rect2(-8, -5, 16, 11), Color(0.35, 0.28, 0.18))

func _draw_iron_chest(glow_col: Color, pulse: float):
	var front: Color = Color(0.32, 0.30, 0.36)
	var side: Color = front.darkened(0.35)
	var top: Color = front.lightened(0.20)
	var band: Color = Color(0.18, 0.16, 0.22)
	var rivet: Color = Color(0.55, 0.55, 0.62)
	var d: float = 2.5  # depth offset

	# Box body — front face
	draw_rect(Rect2(-8, -2, 16, 8), front)
	# Right side face (3/4)
	var side_poly: PackedVector2Array = PackedVector2Array([
		Vector2(8, -2),
		Vector2(8 + d, -2 - d * 0.6),
		Vector2(8 + d, 6 - d * 0.6),
		Vector2(8, 6),
	])
	draw_colored_polygon(side_poly, side)

	# Lid (slightly raised box on top)
	draw_rect(Rect2(-8, -7, 16, 5), top.darkened(0.05))
	# Lid top face slim
	draw_rect(Rect2(-8, -7, 16, 1.5), top.lightened(0.10))
	# Lid right face
	var lid_side: PackedVector2Array = PackedVector2Array([
		Vector2(8, -7),
		Vector2(8 + d, -7 - d * 0.6),
		Vector2(8 + d, -2 - d * 0.6),
		Vector2(8, -2),
	])
	draw_colored_polygon(lid_side, side.darkened(0.10))

	# Lid separation line
	draw_line(Vector2(-8, -2), Vector2(8 + d, -2 - d * 0.6),
		Color(0, 0, 0, 0.55), 0.6)

	# Metal bands across front face (vertical)
	for bx: float in [-5.5, 0.0, 5.5]:
		draw_rect(Rect2(bx - 0.7, -7, 1.4, 13), band)
	# Bands across right side
	for bxi in [-5.5, 0.0, 5.5]:
		var pos: float = float(bxi)
		var t: float = (pos + 8.0) / 16.0
		# Skip — would obscure shape. Just one band on side:
		pass
	draw_line(Vector2(8, -2), Vector2(8 + d, -2 - d * 0.6), band, 1.2)

	# Top edges of front (highlight)
	draw_rect(Rect2(-8, -7, 16, 0.5), Color(1, 1, 1, 0.12))

	# Corner rivets
	var rivet_pts: Array = [
		Vector2(-6.5, -5.8), Vector2(-1.2, -5.8), Vector2(1.2, -5.8), Vector2(6.5, -5.8),
		Vector2(-6.5, -3.2), Vector2(6.5, -3.2),
		Vector2(-6.5, 4.5), Vector2(-1.2, 4.5), Vector2(1.2, 4.5), Vector2(6.5, 4.5),
	]
	for rp in rivet_pts:
		draw_circle(rp + Vector2(0.15, 0.15), 0.7, Color(0, 0, 0, 0.45))
		draw_circle(rp, 0.6, rivet)
		draw_circle(rp + Vector2(-0.15, -0.15), 0.25, Color(1, 1, 1, 0.7))

	# Padlock on front center
	var lx: float = 0.0; var ly: float = 1.3
	# U-shackle
	draw_arc(Vector2(lx, ly - 1.6), 1.4, PI, TAU, 10, Color(0.45, 0.45, 0.52), 1.0)
	# Lock body
	draw_rect(Rect2(lx - 1.8, ly - 1.0, 3.6, 3.2), Color(0.40, 0.38, 0.46))
	draw_rect(Rect2(lx - 1.8, ly - 1.0, 3.6, 0.5), Color(0.60, 0.58, 0.66))
	draw_rect(Rect2(lx - 1.8, ly + 1.8, 3.6, 0.4), Color(0.20, 0.18, 0.24))
	# Keyhole
	draw_circle(Vector2(lx, ly + 0.4), 0.6, Color(0.08, 0.06, 0.10))
	draw_rect(Rect2(lx - 0.2, ly + 0.4, 0.4, 1.2), Color(0.08, 0.06, 0.10))
	# Keyhole reflection
	draw_circle(Vector2(lx - 0.18, ly + 0.22), 0.18, Color(1, 1, 1, 0.6))

	# Rarity glow around lock
	draw_arc(Vector2(lx, ly + 0.4), 3.2, 0, TAU, 16,
		Color(glow_col.r, glow_col.g, glow_col.b, 0.30 + pulse * 0.20), 0.9)
	draw_circle(Vector2(lx, ly + 0.4), 1.4,
		Color(glow_col.r, glow_col.g, glow_col.b, 0.18 + pulse * 0.10))

func _draw_ornate_chest(glow_col: Color, pulse: float):
	var wood: Color = Color(0.40, 0.24, 0.10)
	var wood_dk: Color = wood.darkened(0.30)
	var wood_top: Color = wood.lightened(0.22)
	var gold: Color = Color(0.92, 0.72, 0.20)
	var gold_dk: Color = Color(0.62, 0.46, 0.10)
	var gold_hi: Color = Color(1.0, 0.92, 0.55)
	var d: float = 2.8

	# Front face
	draw_rect(Rect2(-9, -2, 18, 8), wood)
	# Wood grain
	for gy: float in [-0.5, 1.5, 3.5]:
		draw_line(Vector2(-8, gy), Vector2(8, gy + sin(gy) * 0.2),
			wood_dk, 0.5)
	# Right side
	var side_poly: PackedVector2Array = PackedVector2Array([
		Vector2(9, -2), Vector2(9 + d, -2 - d * 0.6),
		Vector2(9 + d, 6 - d * 0.6), Vector2(9, 6),
	])
	draw_colored_polygon(side_poly, wood_dk)
	# Side grain
	draw_line(Vector2(9, 0.5), Vector2(9 + d, 0.5 - d * 0.6),
		wood_dk.darkened(0.20), 0.4)
	draw_line(Vector2(9, 3), Vector2(9 + d, 3 - d * 0.6),
		wood_dk.darkened(0.20), 0.4)

	# Lid — domed (slightly arched top)
	# Lid front
	draw_rect(Rect2(-9, -7, 18, 5), wood)
	# Lid arch (top curve via polygon)
	var arch_pts: PackedVector2Array = PackedVector2Array()
	for i in range(12):
		var t: float = float(i) / 11.0
		var px: float = -9.0 + t * 18.0
		var py: float = -7.0 - sin(t * PI) * 1.5
		arch_pts.append(Vector2(px, py))
	arch_pts.append(Vector2(9, -7))
	arch_pts.append(Vector2(-9, -7))
	draw_colored_polygon(arch_pts, wood_top)
	# Lid side
	var lid_side: PackedVector2Array = PackedVector2Array([
		Vector2(9, -7), Vector2(9 + d, -7 - d * 0.6),
		Vector2(9 + d, -2 - d * 0.6), Vector2(9, -2),
	])
	draw_colored_polygon(lid_side, wood_dk.darkened(0.10))
	# Lid grain
	for gy: float in [-5.5, -3.5]:
		draw_line(Vector2(-8, gy), Vector2(8, gy), wood_dk, 0.4)

	# Lid separation
	draw_line(Vector2(-9, -2), Vector2(9 + d, -2 - d * 0.6),
		wood_dk.darkened(0.40), 0.6)

	# Gold edge trim — ALL visible edges gleam
	# Top arch outline
	for i in range(arch_pts.size() - 2):
		draw_line(arch_pts[i], arch_pts[i + 1], gold, 0.7)
	# Front bottom
	draw_line(Vector2(-9, 6), Vector2(9, 6), gold, 0.8)
	# Front sides
	draw_line(Vector2(-9, -7), Vector2(-9, 6), gold, 0.8)
	draw_line(Vector2(9, -7), Vector2(9, 6), gold, 0.7)
	# Lid sep
	draw_line(Vector2(-9, -2), Vector2(9, -2), gold_dk, 0.6)
	# Side bottom and back
	draw_line(Vector2(9 + d, 6 - d * 0.6), Vector2(9, 6), gold, 0.6)
	draw_line(Vector2(9 + d, -7 - d * 0.6), Vector2(9 + d, 6 - d * 0.6), gold_dk, 0.5)

	# Corner clasps (L-shaped)
	for cx in [-9.0, 9.0]:
		for cy in [-7.0, 6.0]:
			var sx: float = 1.0 if cx > 0 else -1.0
			var sy: float = 1.0 if cy > 0 else -1.0
			draw_rect(Rect2(cx - (1.5 if cx < 0 else 0), cy - (1.5 if cy < 0 else 0), 1.5, 1.5), gold)
			draw_rect(Rect2(cx - (1.5 if cx < 0 else 0) + 0.3,
				cy - (1.5 if cy < 0 else 0) + 0.3, 0.6, 0.6), gold_hi)

	# Decorative hinges on lid sep
	for hx: float in [-5.5, 5.5]:
		draw_rect(Rect2(hx - 1.0, -2.5, 2.0, 1.5), gold_dk)
		draw_circle(Vector2(hx, -1.8), 0.5, gold_hi)

	# Center front medallion
	var mx: float = 0.0; var my: float = 2.0
	draw_circle(Vector2(mx + 0.2, my + 0.3), 2.6, Color(0, 0, 0, 0.50))
	draw_circle(Vector2(mx, my), 2.5, gold_dk)
	draw_circle(Vector2(mx, my), 2.1, gold)
	# Inner geometric design
	for ai in range(8):
		var ang: float = float(ai) * PI / 4.0
		draw_line(Vector2(mx, my),
			Vector2(mx + cos(ang) * 2.0, my + sin(ang) * 2.0),
			gold_dk, 0.4)
	# Gem center (layered)
	var gem_color: Color = Color(0.85, 0.18, 0.18)
	draw_circle(Vector2(mx, my), 1.3, Color(0.50, 0.05, 0.05))
	draw_circle(Vector2(mx, my), 1.0, gem_color)
	draw_circle(Vector2(mx - 0.3, my - 0.3), 0.4, Color(1, 0.75, 0.75, 0.9))
	# Specular dot
	draw_circle(Vector2(mx - 0.45, my - 0.45), 0.16, Color(1, 1, 1, 1))

	# Gem shimmer arc
	draw_arc(Vector2(mx, my), 1.9, 0, TAU, 14,
		Color(glow_col.r, glow_col.g, glow_col.b, 0.32 + pulse * 0.22), 0.7)

	# Top arch highlight
	draw_line(Vector2(-7, -7.5), Vector2(7, -7.5), gold_hi, 0.5)

func _draw_arcane_chest(glow_col: Color, pulse: float):
	var stone: Color = Color(0.16, 0.13, 0.26)
	var stone_dk: Color = stone.darkened(0.40)
	var stone_top: Color = stone.lightened(0.18)
	var stone_side: Color = stone.darkened(0.25)
	var rune: Color = glow_col
	var rune_a: float = 0.50 + sin(_bob_t * 2.2) * 0.32
	var d: float = 3.0

	# Outer ethereal glow (largest)
	draw_circle(Vector2(0, 0), 16.0 + pulse * 1.5,
		Color(rune.r, rune.g, rune.b, 0.07))
	draw_circle(Vector2(0, 0), 11.0 + pulse * 1.0,
		Color(rune.r, rune.g, rune.b, 0.10))

	# Front face
	draw_rect(Rect2(-10, -2, 20, 9), stone)
	# Front face stone texture (cracks)
	for ci in range(3):
		var cx: float = -7.0 + float(ci) * 5.0
		draw_line(Vector2(cx, -1), Vector2(cx + 0.7, 1.5),
			stone_dk, 0.4)
	# Right side
	var side_poly: PackedVector2Array = PackedVector2Array([
		Vector2(10, -2), Vector2(10 + d, -2 - d * 0.6),
		Vector2(10 + d, 7 - d * 0.6), Vector2(10, 7),
	])
	draw_colored_polygon(side_poly, stone_side)
	# Side cracks
	draw_line(Vector2(10 + d * 0.4, 0), Vector2(10 + d * 0.4, 4),
		stone_dk, 0.4)

	# Lid
	draw_rect(Rect2(-10, -8, 20, 6), stone.lightened(0.05))
	# Lid top thin
	draw_rect(Rect2(-10, -8, 20, 1.2), stone_top)
	# Lid side
	var lid_side: PackedVector2Array = PackedVector2Array([
		Vector2(10, -8), Vector2(10 + d, -8 - d * 0.6),
		Vector2(10 + d, -2 - d * 0.6), Vector2(10, -2),
	])
	draw_colored_polygon(lid_side, stone_side.darkened(0.10))

	# Lid separation
	draw_line(Vector2(-10, -2), Vector2(10 + d, -2 - d * 0.6),
		Color(0, 0, 0, 0.55), 0.6)

	# Central arcane seal on front face (large circular glyph)
	var sx: float = 0.0; var sy: float = 2.5
	for ri in range(3):
		var rd: float = 2.0 + float(ri) * 0.9
		draw_arc(Vector2(sx, sy), rd, 0, TAU, 24,
			Color(rune.r, rune.g, rune.b, rune_a * (0.7 - float(ri) * 0.15)), 0.5)
	# Radial lines
	for ai in range(8):
		var ang: float = float(ai) * PI / 4.0 + _bob_t * 0.3
		var p0: Vector2 = Vector2(sx + cos(ang) * 1.6, sy + sin(ang) * 1.6)
		var p1: Vector2 = Vector2(sx + cos(ang) * 3.6, sy + sin(ang) * 3.6)
		draw_line(p0, p1, Color(rune.r, rune.g, rune.b, rune_a * 0.5), 0.4)
	# Inner glyph (triangle within circle)
	for ti in range(3):
		var a1: float = float(ti) * TAU / 3.0 - PI * 0.5
		var a2: float = float(ti + 1) * TAU / 3.0 - PI * 0.5
		draw_line(Vector2(sx + cos(a1) * 1.6, sy + sin(a1) * 1.6),
			Vector2(sx + cos(a2) * 1.6, sy + sin(a2) * 1.6),
			Color(rune.r, rune.g, rune.b, rune_a), 0.7)
	# Center dot
	draw_circle(Vector2(sx, sy), 0.7, Color(rune.r, rune.g, rune.b, rune_a))
	draw_circle(Vector2(sx, sy), 0.3, Color(1, 1, 1, rune_a))

	# Additional runes on lid
	for ri in range(3):
		var rx: float = -6.0 + float(ri) * 6.0
		var ry: float = -5.0
		var ph: float = _bob_t * 1.8 + float(ri) * 1.5
		var ra: float = 0.4 + sin(ph) * 0.3
		# Cross-and-dots rune
		draw_line(Vector2(rx - 1, ry), Vector2(rx + 1, ry),
			Color(rune.r, rune.g, rune.b, ra), 0.5)
		draw_line(Vector2(rx, ry - 1), Vector2(rx, ry + 1),
			Color(rune.r, rune.g, rune.b, ra), 0.5)
		draw_circle(Vector2(rx + 0.7, ry + 0.7), 0.3,
			Color(rune.r, rune.g, rune.b, ra))
		draw_circle(Vector2(rx - 0.7, ry - 0.7), 0.3,
			Color(rune.r, rune.g, rune.b, ra))

	# Corner gems — each pulsing individually
	var corners: Array = [
		Vector2(-9, -6.5), Vector2(9, -6.5),
		Vector2(-9, 5.5), Vector2(9, 5.5),
	]
	for i in range(corners.size()):
		var cp: Vector2 = corners[i]
		var phase: float = _bob_t * 2.0 + float(i) * 0.8
		var gp: float = 0.55 + sin(phase) * 0.40
		draw_arc(cp, 2.0 + sin(phase) * 0.3, 0, TAU, 12,
			Color(rune.r, rune.g, rune.b, gp * 0.4), 0.5)
		draw_circle(cp, 1.0, Color(rune.r, rune.g, rune.b, gp))
		draw_circle(cp, 0.5, Color(1, 1, 1, gp * 0.9))

	# Floating particles in elliptical orbit
	for pi in range(4):
		var pph: float = _bob_t * 1.2 + float(pi) * PI * 0.5
		var px: float = cos(pph) * 12.0
		var py: float = sin(pph) * 7.0
		var pa: float = 0.35 + sin(pph * 2.0) * 0.25
		draw_circle(Vector2(px, py), 0.7,
			Color(rune.r, rune.g, rune.b, pa))
		draw_circle(Vector2(px, py), 0.3,
			Color(1, 1, 1, pa))

func _draw_chest_open(glow_col: Color, pulse: float):
	# Ground shadow
	draw_ellipse_filled(Vector2(0, 7), 12.0, 2.6, Color(0, 0, 0, 0.55))

	var wood: Color
	var wood_dk: Color
	var trim: Color = Color(0.92, 0.72, 0.20)
	match chest_type:
		0:
			wood = Color(0.32, 0.30, 0.36); wood_dk = wood.darkened(0.35); trim = Color(0.55, 0.55, 0.62)
		1:
			wood = Color(0.40, 0.24, 0.10); wood_dk = wood.darkened(0.30)
		2:
			wood = Color(0.16, 0.13, 0.26); wood_dk = wood.darkened(0.40); trim = glow_col
		_:
			wood = Color(0.35, 0.28, 0.18); wood_dk = wood.darkened(0.30)

	var d: float = 2.8

	# Box body (front + side)
	draw_rect(Rect2(-9, -2, 18, 8), wood)
	var side_poly: PackedVector2Array = PackedVector2Array([
		Vector2(9, -2), Vector2(9 + d, -2 - d * 0.6),
		Vector2(9 + d, 6 - d * 0.6), Vector2(9, 6),
	])
	draw_colored_polygon(side_poly, wood_dk)

	# Dark hollow interior (top rim of opening)
	var interior: PackedVector2Array = PackedVector2Array([
		Vector2(-8, -2),
		Vector2(8, -2),
		Vector2(8 + d * 0.8, -2 - d * 0.4),
		Vector2(-8 + d * 0.1, -2 - d * 0.4),
	])
	draw_colored_polygon(interior, Color(0.04, 0.03, 0.06))
	# Inner glow rim
	draw_line(Vector2(-8, -2), Vector2(8, -2),
		Color(glow_col.r, glow_col.g, glow_col.b, 0.85), 0.8)

	# Lid hinged open (flipped back) — drawn as polygon angled away
	var lid_pts: PackedVector2Array = PackedVector2Array([
		Vector2(-9, -2.5),
		Vector2(9, -2.5),
		Vector2(9 + d * 0.4, -10 - d * 0.4),
		Vector2(-9 + d * 0.4, -10 - d * 0.4),
	])
	# Lid shadow under
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8.5, -2.7), Vector2(8.5, -2.7),
		Vector2(8.5 + d * 0.4, -9.5 - d * 0.4),
		Vector2(-8.5 + d * 0.4, -9.5 - d * 0.4),
	]), wood_dk.darkened(0.20))
	draw_colored_polygon(lid_pts, wood)
	# Lid inner face (showing it's hinged)
	draw_line(Vector2(-9, -2.5), Vector2(9, -2.5), trim.darkened(0.20), 0.6)
	draw_line(Vector2(-9 + d * 0.4, -10 - d * 0.4),
		Vector2(9 + d * 0.4, -10 - d * 0.4), trim, 0.6)
	# Lid edge trim
	draw_line(Vector2(-9, -2.5), Vector2(-9 + d * 0.4, -10 - d * 0.4), trim, 0.5)
	draw_line(Vector2(9, -2.5), Vector2(9 + d * 0.4, -10 - d * 0.4), trim, 0.5)

	# Radiant loot glow from opening
	var glow_y: float = -0.5
	draw_circle(Vector2(0, glow_y), 8.0 + pulse * 1.5,
		Color(glow_col.r, glow_col.g, glow_col.b, 0.20))
	draw_circle(Vector2(0, glow_y), 5.0 + pulse * 1.0,
		Color(glow_col.r, glow_col.g, glow_col.b, 0.35))
	draw_circle(Vector2(0, glow_y), 2.5,
		Color(1, 1, 0.85, 0.65))

	# Light rays shooting upward
	for ri in range(5):
		var ang: float = -PI * 0.5 + (float(ri) - 2.0) * 0.18
		var rlen: float = 7.0 + sin(_bob_t * 3.0 + ri) * 1.0
		var pa: float = 0.30 + sin(_bob_t * 2.0 + ri) * 0.10
		draw_line(Vector2(0, glow_y),
			Vector2(cos(ang) * rlen, glow_y + sin(ang) * rlen),
			Color(1, 0.95, 0.65, pa), 0.5)

	# Gold coins spilling
	var coin_data: Array = [
		Vector2(-5, 3), Vector2(-3, 4), Vector2(-1, 3.5),
		Vector2(2, 4), Vector2(4, 3), Vector2(6, 4.5), Vector2(0, 4.8),
	]
	for i in range(coin_data.size()):
		var cp: Vector2 = coin_data[i]
		var cr: float = 1.0 + float(i % 3) * 0.25
		# Shadow
		draw_circle(cp + Vector2(0.2, 0.3), cr * 1.05, Color(0, 0, 0, 0.40))
		# Coin
		draw_circle(cp, cr, Color(0.92, 0.72, 0.18))
		draw_circle(cp + Vector2(-0.2, -0.2), cr * 0.45, Color(1.0, 0.92, 0.55))
		# Edge stamp
		draw_arc(cp, cr - 0.15, 0, TAU, 8, Color(0.65, 0.45, 0.08, 0.7), 0.3)

	# Gemstones (2)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2.5, 1.5), Vector2(-1.2, 0.8),
		Vector2(-0.5, 1.8), Vector2(-1.8, 2.5),
	]), Color(0.30, 0.65, 0.95))
	draw_circle(Vector2(-1.7, 1.5), 0.35, Color(0.85, 0.95, 1.0))

	draw_colored_polygon(PackedVector2Array([
		Vector2(2.8, 2.0), Vector2(4.0, 1.4),
		Vector2(4.6, 2.4), Vector2(3.4, 3.0),
	]), Color(0.85, 0.20, 0.30))
	draw_circle(Vector2(3.5, 2.0), 0.3, Color(1.0, 0.75, 0.80))

# Helper for filled ellipse
func draw_ellipse_filled(center: Vector2, rx: float, ry: float, col: Color):
	var pts: PackedVector2Array = PackedVector2Array()
	var segs: int = 18
	for i in range(segs):
		var a: float = float(i) / float(segs) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

func interact(player: Node2D):
	if not player.has_method("pickup_loot"):
		return
	if not is_bonus:
		# Show named loot with flavor description
		var popup := _dice_scene.instantiate()
		popup.setup(GameManager.get_main_loot_name(), Color(0.95, 0.82, 0.22))
		popup.global_position = global_position + Vector2(0, -28)
		get_tree().root.add_child(popup)
		var desc_popup := _dice_scene.instantiate()
		desc_popup.setup(GameManager.get_main_loot_desc(), Color(0.75, 0.70, 0.55))
		desc_popup.global_position = global_position + Vector2(0, -14)
		get_tree().root.add_child(desc_popup)
		# CURSED_VAULT: trigger nearest trap when grabbing primary loot
		if GameManager.run_modifier == "CURSED_VAULT":
			_trigger_nearest_trap()
	# DOUBLE_OR_NOTHING: loot worth 2×
	if GameManager.run_modifier == "DOUBLE_OR_NOTHING":
		loot_value = int(loot_value * 2.0)
	var rarity_mults := {0: 1.0, 1: 1.5, 2: 2.5}
	var value := int(loot_value * rarity_mults.get(rarity, 1.0))
	if GameManager.run_modifier == "BONUS_CONTRACT":
		value = int(value * 1.6)
	if GameManager.floor_complication == "WINDFALL":
		value = int(value * 1.4)
	if GameManager.selected_class == "CUTPURSE":
		value = int(value * 1.25)
	if is_bonus and GameManager.get_guild_unlock("SAFECRACKER"):
		value = int(value * 1.5)
	GameManager.add_gold(value)
	_gold_popup(value)
	if is_bonus:
		GameManager.collect_bonus_loot()
		player.emit_noise(player.NoiseLevel.QUIET)
	else:
		player.pickup_loot()
	AudioManager.loot_collect()
	looted.emit()
	_opened = true
	queue_redraw()
	await get_tree().create_timer(0.35).timeout
	queue_free()

func _gold_popup(value: int):
	var popup = _dice_scene.instantiate()
	popup.setup("+%d gp" % value, Color(0.95, 0.80, 0.10))
	popup.global_position = global_position + Vector2(0, -14)
	get_tree().root.add_child(popup)

func is_in_range(player_pos: Vector2) -> bool:
	return global_position.distance_to(player_pos) <= INTERACT_RANGE

func _trigger_nearest_trap():
	var nearest: Node = null
	var nearest_dist := 9999.0
	for trap in get_tree().get_nodes_in_group("traps"):
		var d: float = global_position.distance_to(trap.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = trap
	if nearest and nearest.has_method("trigger"):
		nearest.trigger()
	elif nearest:
		nearest.set("_triggered", true)
