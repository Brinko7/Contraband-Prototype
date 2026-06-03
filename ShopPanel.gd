extends Node2D

# Procedurally drawn shop — 3 random fantasy item cards per floor visit.

const ITEM_COLORS := {
	0: Color(0.95, 0.80, 0.10),
	1: Color(0.55, 0.90, 0.45),
	2: Color(0.30, 0.70, 0.95),
	3: Color(0.75, 0.55, 0.95),
	4: Color(1.00, 0.95, 0.70),
	5: Color(0.55, 0.35, 0.90),
	6: Color(0.28, 0.18, 0.52),
}

const ITEM_RUNES := { 0: "G", 1: "S", 2: "D", 3: "R", 4: "F", 5: "H", 6: "Z" }

var _t := 0.0
var hovered := -1
var player  = null

signal buy_requested(slot: int)
signal close_requested

func _ready():
	player = get_tree().get_first_node_in_group("player")

func _process(delta):
	_t += delta
	queue_redraw()

func _input(event):
	if event is InputEventMouseMotion:
		var prev := hovered
		hovered = _card_at(event.position)
		if hovered != prev:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var c := _card_at(event.position)
		if c >= 0:
			buy_requested.emit(c)

func _card_at(mouse: Vector2) -> int:
	var vp   := get_viewport().get_visible_rect().size
	var cw   := 210.0
	var ch   := 310.0
	var gap  := 32.0
	var tot  := 3.0 * cw + 2.0 * gap
	var cx0  := (vp.x - tot) * 0.5
	var cy   := vp.y * 0.5 - ch * 0.5 + 20.0
	for i in range(3):
		var cx := cx0 + i * (cw + gap)
		if mouse.x >= cx and mouse.x < cx + cw \
				and mouse.y >= cy and mouse.y < cy + ch:
			return i
	return -1

func _draw():
	var vp   := get_viewport().get_visible_rect().size
	var W    := vp.x
	var H    := vp.y
	var font := ThemeDB.fallback_font
	var gp   := GameManager.gold_available()
	var mult := GameManager.get_shop_cost_multiplier()
	var items := GameManager.floor_shop_items

	# ── Dark parchment backdrop ───────────────────────────────────────────────
	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.01, 0.035, 0.97))
	for i in range(0, int(H), 5):
		draw_line(Vector2(0, i), Vector2(W, i), Color(0, 0, 0, 0.06), 1.0)

	# ── Header banner ─────────────────────────────────────────────────────────
	var bx  := W * 0.12
	var bw  := W * 0.76
	var by  := H * 0.08
	var bh  := 90.0
	draw_rect(Rect2(bx, by, bw, bh), Color(0.10, 0.065, 0.035, 0.95))
	draw_rect(Rect2(bx, by, bw, bh), Color(0.70, 0.54, 0.20, 0.70), false, 2.0)
	# Double inner border
	draw_rect(Rect2(bx + 5, by + 5, bw - 10, bh - 10),
		Color(0.70, 0.54, 0.20, 0.25), false, 1.0)

	# Corner diamonds
	for cx2 in [bx + 8, bx + bw - 8]:
		for cy2 in [by + 8, by + bh - 8]:
			draw_circle(Vector2(cx2, cy2), 3.5, Color(0.70, 0.54, 0.20, 0.65))

	var qm: String = GameManager.get("quartermaster_name")
	if qm.is_empty(): qm = "The Fence"
	draw_string(font, Vector2(bx + 14, by + 22),
		qm.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.50, 0.22, 0.90))
	# Contextual dialogue line
	var qm_line: String = GameManager.get_contextual_qm_line()
	draw_string(font, Vector2(bx + 14, by + 36),
		"\"%s\"" % qm_line, HORIZONTAL_ALIGNMENT_LEFT, int(bw - 28), 9,
		Color(0.70, 0.60, 0.38, 0.80))
	draw_string(font, Vector2(W * 0.5 - 150, by + 64),
		"—  S U P P L Y   C A C H E  —",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.95, 0.80, 0.22))

	# Floor + gold strip
	var strip_y := by + bh + 12.0
	draw_string(font, Vector2(W * 0.5 - 120, strip_y),
		"Floor %d  ·  %d gold in purse" % [GameManager.current_floor, gp],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.78, 0.65, 0.32))

	# ── Cards ─────────────────────────────────────────────────────────────────
	var cw   := 210.0
	var ch   := 310.0
	var gap  := 32.0
	var tot  := 3.0 * cw + 2.0 * gap
	var cx0  := (W - tot) * 0.5
	var cy   := H * 0.5 - ch * 0.5 + 20.0

	const BTNS := ["[1 / X]", "[2 / Y]", "[3 / B]"]

	for i in range(min(3, items.size())):
		var si: Dictionary  = items[i]
		var itype: int      = si.get("type", -1)
		var is_gear: bool        = itype == -1
		var is_weapon_upg: bool  = itype == -2
		var is_heal: bool        = itype == -3
		# Cards use stored color when available; consumables use ITEM_COLORS
		var col: Color
		if is_gear or is_weapon_upg:
			col = si.get("color", Color(0.65, 0.50, 0.28))
		elif is_heal:
			col = Color(0.30, 0.80, 0.55)
		else:
			col = ITEM_COLORS.get(itype, Color(0.7, 0.7, 0.7))
		var cost: int       = int(si.get("cost", 0) * mult)
		var can_afford      := gp >= cost
		var is_hov          := (i == hovered)
		var cx              := cx0 + i * (cw + gap)
		var pulse: float    = sin(_t * 2.0 + i * 1.2) * 0.5 + 0.5

		# Drop shadow
		draw_rect(Rect2(cx + 5, cy + 7, cw, ch), Color(0, 0, 0, 0.50))

		# Card body — aged parchment
		var bg := Color(0.14, 0.095, 0.055) if not is_hov else Color(0.19, 0.13, 0.075)
		draw_rect(Rect2(cx, cy, cw, ch), bg)
		# Inner warm highlight
		draw_rect(Rect2(cx + 3, cy + 3, cw - 6, ch - 6), Color(1.0, 0.85, 0.55, 0.04))

		# Hover outer glow
		if is_hov:
			draw_rect(Rect2(cx - 4, cy - 4, cw + 8, ch + 8),
				Color(col.r, col.g, col.b, 0.20 + pulse * 0.08), false, 4.5)

		# Outer border
		draw_rect(Rect2(cx, cy, cw, ch),
			Color(col.r, col.g, col.b, 0.85 if is_hov else 0.55), false, 2.0)
		# Inner border
		draw_rect(Rect2(cx + 5, cy + 5, cw - 10, ch - 10),
			Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.28), false, 1.0)

		# Top color stripe
		draw_rect(Rect2(cx, cy, cw, 5), Color(col.r, col.g, col.b, 0.95))

		# Corner ornament circles
		for ox in [cx + 8, cx + cw - 8]:
			for oy in [cy + 12, cy + ch - 8]:
				draw_circle(Vector2(ox, oy), 3.0, Color(col.r, col.g, col.b, 0.50))

		# Key hint (top-left)
		draw_string(font, Vector2(cx + 12, cy + 24),
			BTNS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.50, 0.38))

		# ── Medallion (rune for items, slot symbol for gear) ─────────────────────
		var med_cx := cx + cw * 0.5
		var med_cy := cy + 80.0
		var med_r  := 26.0
		draw_arc(Vector2(med_cx, med_cy), med_r + 5.0 + pulse * 4.0,
			0, TAU, 32, Color(col.r, col.g, col.b, 0.15 + pulse * 0.12), 1.5)
		draw_circle(Vector2(med_cx, med_cy), med_r,
			Color(col.r * 0.14, col.g * 0.14, col.b * 0.14))
		draw_arc(Vector2(med_cx, med_cy), med_r,
			0, TAU, 32, Color(col.r, col.g, col.b, 0.65), 2.0)
		draw_arc(Vector2(med_cx, med_cy), med_r - 7.0,
			0, TAU, 24, Color(col.r, col.g, col.b, 0.30), 1.0)
		if is_gear:
			var slot_sym: String = { "boots": "B", "cloak": "C", "offhand": "O", "trinket": "T" }.get(
				si.get("gear_slot", ""), "G")
			draw_string(font, Vector2(med_cx - 5, med_cy + 7),
				slot_sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(col.r, col.g, col.b, 0.95))
			draw_string(font, Vector2(med_cx - 16, med_cy - med_r - 8),
				"GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col.r, col.g, col.b, 0.70))
		elif is_weapon_upg:
			draw_string(font, Vector2(med_cx - 5, med_cy + 7),
				"W", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(col.r, col.g, col.b, 0.95))
			draw_string(font, Vector2(med_cx - 22, med_cy - med_r - 8),
				"UPGRADE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col.r, col.g, col.b, 0.70))
		elif is_heal:
			draw_string(font, Vector2(med_cx - 5, med_cy + 7),
				"+", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(col.r, col.g, col.b, 0.95))
			draw_string(font, Vector2(med_cx - 12, med_cy - med_r - 8),
				"HEAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col.r, col.g, col.b, 0.70))
		else:
			var rune: String = ITEM_RUNES.get(itype, "?")
			draw_string(font, Vector2(med_cx - 5, med_cy + 7),
				rune, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(col.r, col.g, col.b, 0.95))

		# ── Item name ─────────────────────────────────────────────────────────
		var name_y := cy + 122.0
		draw_string(font, Vector2(cx + 12, name_y),
			si.get("name", "").to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, int(cw - 20), 13, col)

		# Name underline
		draw_line(Vector2(cx + 12, name_y + 6), Vector2(cx + cw - 12, name_y + 6),
			Color(col.r, col.g, col.b, 0.30), 1.0)

		# ── Description ───────────────────────────────────────────────────────
		draw_string(font, Vector2(cx + 14, name_y + 22),
			si.get("desc", ""),
			HORIZONTAL_ALIGNMENT_LEFT, int(cw - 24), 10, Color(0.82, 0.78, 0.66))

		# Count badge
		var cnt: int = si.get("count", 1)
		if cnt > 1:
			draw_string(font, Vector2(cx + 14, name_y + 42),
				"Quantity: %d" % cnt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.60, 0.48))

		# Synergy tags
		var tags: Array = si.get("tags", [])
		if not tags.is_empty():
			var tag_str := "  ".join(tags)
			draw_string(font, Vector2(cx + 14, name_y + 56),
				tag_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.50, 0.70, 0.85, 0.70))

		# ── Price footer ──────────────────────────────────────────────────────
		var price_y := cy + ch - 58.0
		draw_line(Vector2(cx + 12, price_y - 4), Vector2(cx + cw - 12, price_y - 4),
			Color(col.r, col.g, col.b, 0.22), 1.0)

		var price_col := Color(0.95, 0.80, 0.22) if can_afford else Color(0.75, 0.28, 0.28)
		var price_bg  := Color(0.07, 0.04, 0.01, 0.90) if can_afford else Color(0.16, 0.04, 0.04, 0.90)
		draw_rect(Rect2(cx + 10, price_y, cw - 20, 34), price_bg)
		draw_rect(Rect2(cx + 10, price_y, cw - 20, 34),
			Color(price_col.r, price_col.g, price_col.b, 0.50), false, 1.0)

		var price_str := "%d gp" % cost
		if mult < 0.99:
			price_str += "  (was %d)" % si.get("cost", cost)
		draw_string(font, Vector2(cx + 18, price_y + 22),
			price_str, HORIZONTAL_ALIGNMENT_LEFT, int(cw - 30), 13, price_col)

		if not can_afford:
			draw_string(font, Vector2(cx + 14, cy + ch - 14),
				"insufficient gold",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.75, 0.28, 0.28, 0.85))

	# ── Inventory strip ───────────────────────────────────────────────────────
	var inv_y := cy + ch + 18.0
	draw_rect(Rect2(W * 0.18, inv_y, W * 0.64, 28), Color(0.07, 0.04, 0.02, 0.85))
	draw_rect(Rect2(W * 0.18, inv_y, W * 0.64, 28),
		Color(0.50, 0.40, 0.20, 0.40), false, 1.0)
	var inv := "CARRIED:  "
	if player and player.has_method("get_item_list"):
		for item in player.get_item_list():
			inv += "%s ×%d   " % [_iname(item.get("type", -1)), item.get("count", 0)]
	draw_string(font, Vector2(W * 0.20, inv_y + 18),
		inv, HORIZONTAL_ALIGNMENT_LEFT, int(W * 0.62), 10, Color(0.68, 0.60, 0.40))

	# ── Item synergies ────────────────────────────────────────────────────────
	if player and player.has_method("get_item_list"):
		var syns := GameManager.get_owned_synergies(player.get_item_list())
		if not syns.is_empty():
			var syn_y := inv_y + 18.0
			draw_string(font, Vector2(W * 0.20, syn_y + 18),
				"SYNERGY: " + syns[0], HORIZONTAL_ALIGNMENT_LEFT, int(W * 0.62), 10,
				Color(0.55, 0.90, 0.65, 0.90))

	# ── Objective ─────────────────────────────────────────────────────────────
	if GameManager.floor_objective != "NONE":
		var done := GameManager.check_objective_complete()
		var obj_col := Color(0.35, 0.90, 0.45) if done else Color(0.90, 0.40, 0.30)
		draw_string(font, Vector2(W * 0.5 - 160, inv_y + 46),
			"Objective: %s — %s  (+%d gp)" % [
				GameManager.floor_objective_name,
				"COMPLETED" if done else "FAILED",
				GameManager.floor_objective_bonus],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, obj_col)

	# ── Footer ────────────────────────────────────────────────────────────────
	draw_string(font, Vector2(W * 0.5 - 120, H - 18),
		"[Enter / A]  Descend to Floor %d" % (GameManager.current_floor + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.42, 0.38, 0.28))

func _iname(t: int) -> String:
	match t:
		0: return "Coins"
		1: return "Smoke"
		2: return "Dart"
		3: return "Rope"
		4: return "Flash"
		5: return "Hold"
		6: return "Silence"
		7: return "Tools"
		8: return "Shadow Oil"
		9: return "Iron Key"
	return "?"
