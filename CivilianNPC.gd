extends Node2D

# Civilian NPC — V12 overhaul with NPC types, disposition system,
# context-sensitive interactions, pickpocketing, and distinct visuals.

const TILE_SIZE := 16

@export var patrol_points: Array[Vector2] = []

enum NPCType { SERVANT, NOBLE, MERCHANT, PRISONER, DRUNK_GUARD, INFORMANT }

@export var npc_type: NPCType = NPCType.SERVANT

# Legacy compatibility: reading is_informant sets npc_type
var is_informant: bool:
	get: return npc_type == NPCType.INFORMANT
	set(v):
		if v: npc_type = NPCType.INFORMANT

# Disposition: 0.0 = hostile, 0.5 = neutral, 1.0 = friendly
var disposition: float = 0.5

var _pt_idx        := 0
var _move_timer    := 0.0
var _move_interval := 1.8
var _t             := 0.0
var _spooked       := false
var _spook_timer   := 0.0
var _bribed        := false
var _freed         := false         # PRISONER: freed by player
var _freed_timer   := 0.0          # wander distraction timer
var _distract_t    := 0.0          # how long freed prisoner distracts
var _pickpocketed  := false        # item already stolen
var _merchant_offered := false     # merchant interaction happened
var _drunk_sway    := 0.0          # drunk guard sway state
var _prisoner_chain_t := 0.0      # chain jingle animation

# Merchant inventory for mid-run sales
var _merchant_items: Array = []

var _gm = null

func _ready() -> void:
	add_to_group("civilians")
	add_to_group("interactable")
	_gm = get_node_or_null("/root/GameManager")

	if patrol_points.is_empty():
		patrol_points.append(global_position)

	# Set type-based defaults
	match npc_type:
		NPCType.SERVANT:
			_move_interval = 1.4
		NPCType.NOBLE:
			_move_interval = 2.2
		NPCType.MERCHANT:
			_move_interval = 999.0  # stays put
			_setup_merchant_items()
		NPCType.PRISONER:
			_move_interval = 999.0
			disposition = 0.8  # friendly, wants to be freed
		NPCType.DRUNK_GUARD:
			_move_interval = 0.9
		NPCType.INFORMANT:
			_move_interval = 1.6

func _setup_merchant_items() -> void:
	# Randomise 2-3 items to sell
	var pool := ["SMOKE", "DART", "ROPE", "FLASH", "SILENCE"]
	pool.shuffle()
	for i in range(min(3, pool.size())):
		var item_name: String = pool[i]
		var price := randi_range(40, 90)
		_merchant_items.append({ "name": item_name, "price": price })

func is_in_range(pos: Vector2) -> bool:
	var range := 28.0
	if npc_type == NPCType.MERCHANT:
		range = 32.0
	return global_position.distance_to(pos) <= range

# ──────────────── INTERACT ────────────────

func interact(player: Node) -> void:
	if _spooked:
		return
	if _bribed:
		_on_already_bribed(player)
		return

	match npc_type:
		NPCType.SERVANT:   _interact_servant(player)
		NPCType.NOBLE:     _interact_noble(player)
		NPCType.MERCHANT:  _interact_merchant(player)
		NPCType.PRISONER:  _interact_prisoner(player)
		NPCType.DRUNK_GUARD: _interact_drunk_guard(player)
		NPCType.INFORMANT: _interact_informant(player)

func _on_already_bribed(player: Node) -> void:
	if player.has_method("_popup"):
		player._popup("(nods quietly)", Color(0.55, 0.72, 0.42))

# SERVANT — Question (Persuasion for intel) or Bribe (look away)
func _interact_servant(player: Node) -> void:
	# Default action: bribe (E). Player can call interact_secondary for question.
	_do_bribe(player, 30)  # cheaper to bribe a servant

func interact_question(player: Node) -> void:
	# Called when player presses Q near servant
	if npc_type != NPCType.SERVANT:
		return
	var roll := _roll_d20_with_class_bonus(player, "persuasion")
	var dc := 10
	var dice_scene = load("res://DicePopup.tscn")
	if roll >= dc:
		# Reveal patrol path — set patrol_reveal_timer on player
		if player.has_method("set"):
			player.set("_patrol_reveal_timer", 8.0)
		disposition = minf(disposition + 0.1, 1.0)
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Question %d ✓ — patrol routes revealed!" % roll, Color(0.45, 0.85, 0.90))
			p.global_position = global_position + Vector2(0, -18)
			get_tree().root.add_child(p)
	else:
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Question %d ✗ — they don't know" % roll, Color(0.55, 0.50, 0.42))
			p.global_position = global_position + Vector2(0, -18)
			get_tree().root.add_child(p)

# NOBLE — Persuasion or Intimidation: success = stays quiet, fail = screams
func _interact_noble(player: Node) -> void:
	var roll := _roll_d20_with_class_bonus(player, "persuasion")
	var dc := 14  # Nobles are hard to convince
	var dice_scene = load("res://DicePopup.tscn")
	if roll >= dc:
		_bribed = true
		disposition = minf(disposition + 0.15, 1.0)
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Persuade %d ✓ — noble stays quiet" % roll, Color(0.60, 0.88, 0.50))
			p.global_position = global_position + Vector2(0, -18)
			get_tree().root.add_child(p)
	else:
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Persuade %d ✗ — SCREAMS!" % roll, Color(1.0, 0.20, 0.20))
			p.global_position = global_position + Vector2(0, -18)
			get_tree().root.add_child(p)
		_spook(player)

func interact_intimidate(player: Node) -> void:
	# Called when player presses intimidation action (varies by implementation)
	if npc_type != NPCType.NOBLE:
		return
	var roll := _roll_d20_with_class_bonus(player, "intimidation")
	var dc := 11
	var dice_scene = load("res://DicePopup.tscn")
	if roll >= dc:
		_bribed = true
		disposition = maxf(disposition - 0.1, 0.0)
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Intimidate %d ✓ — noble cowers" % roll, Color(0.90, 0.55, 0.20))
			p.global_position = global_position + Vector2(0, -18)
			get_tree().root.add_child(p)
	else:
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Intimidate %d ✗ — SCREAMS!" % roll, Color(1.0, 0.20, 0.20))
			p.global_position = global_position + Vector2(0, -18)
			get_tree().root.add_child(p)
		_spook(player)

func interact_pickpocket_noble(player: Node) -> void:
	if npc_type != NPCType.NOBLE or _pickpocketed:
		return
	var roll := _roll_d20_with_class_bonus(player, "pickpocket")
	var dc := 12
	var dice_scene = load("res://DicePopup.tscn")
	if roll >= dc:
		_pickpocketed = true
		var gold := randi_range(30, 80)
		if _gm: _gm.add_gold(gold)
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Pickpocket %d ✓ — +%dgp!" % [roll, gold], Color(0.95, 0.80, 0.10))
			p.global_position = global_position + Vector2(0, -18)
			get_tree().root.add_child(p)
	else:
		disposition = maxf(disposition - 0.3, 0.0)
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Pickpocket %d ✗ — caught!" % roll, Color(1.0, 0.30, 0.20))
			p.global_position = global_position + Vector2(0, -18)
			get_tree().root.add_child(p)
		_spook(player)

# MERCHANT — show 2-3 item offers
func _interact_merchant(player: Node) -> void:
	if _merchant_items.is_empty():
		if player.has_method("_popup"):
			player._popup("Sold out!", Color(0.55, 0.50, 0.42))
		return

	# Check for discount via Persuasion
	if not _merchant_offered:
		_merchant_offered = true
		var roll := _roll_d20_with_class_bonus(player, "persuasion")
		var discount_factor := 1.0
		var dice_scene = load("res://DicePopup.tscn")
		if roll >= 13:
			discount_factor = 0.5
			if dice_scene:
				var p = dice_scene.instantiate()
				p.setup("Haggle %d ✓ — 50% discount!" % roll, Color(0.95, 0.80, 0.10))
				p.global_position = global_position + Vector2(0, -20)
				get_tree().root.add_child(p)
		# Auto-buy first available item the player can afford
		for offer in _merchant_items:
			var price: int = int(float(offer["price"]) * discount_factor)
			if _gm and _gm.gold_available() >= price:
				if _gm: _gm.gold_spent += price
				_merchant_items.erase(offer)
				if player.has_method("_popup"):
					player._popup("Bought %s for %dgp!" % [offer["name"], price], Color(0.70, 0.90, 0.40))
				return
		if player.has_method("_popup"):
			player._popup("Can't afford anything! (need %dgp)" % _merchant_items[0].get("price", 99),
				Color(0.80, 0.30, 0.20))

# PRISONER — free them (no roll), they wander and distract for 20s
func _interact_prisoner(player: Node) -> void:
	if _freed:
		if player.has_method("_popup"):
			player._popup("(following you...)", Color(0.55, 0.72, 0.42))
		return
	_freed = true
	_freed_timer = 20.0
	_move_interval = 1.2  # now wanders quickly
	disposition = 1.0

	var dice_scene = load("res://DicePopup.tscn")
	if dice_scene:
		var p = dice_scene.instantiate()
		p.setup("Prisoner FREED! (20s distraction)", Color(0.75, 0.90, 0.50))
		p.global_position = global_position + Vector2(0, -18)
		get_tree().root.add_child(p)

	# Yell to draw guard attention away
	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= 100.0:
			if guard.has_method("_on_noise_emitted"):
				guard._on_noise_emitted(1, global_position)  # medium noise

# DRUNK GUARD — can be pickpocketed for key item
func _interact_drunk_guard(player: Node) -> void:
	if _pickpocketed:
		if player.has_method("_popup"):
			player._popup("(already checked pockets)", Color(0.55, 0.50, 0.42))
		return
	# Drunk guard = easy pickpocket, DC 6
	var roll := _roll_d20_with_class_bonus(player, "pickpocket")
	var dc := 6
	var dice_scene = load("res://DicePopup.tscn")
	if roll >= dc:
		_pickpocketed = true
		# 50% chance of a key item, otherwise gold
		var dice_scene2 = load("res://DicePopup.tscn")
		if randf() < 0.5:
			# Give player a key
			var k = player.get("keys")
			if k != null: k.append(randi_range(0, 2))
			if dice_scene:
				var p = dice_scene.instantiate()
				p.setup("Pickpocket %d ✓ — found a KEY!" % roll, Color(0.90, 0.75, 0.20))
				p.global_position = global_position + Vector2(0, -18)
				get_tree().root.add_child(p)
		else:
			var gold := randi_range(15, 35)
			if _gm: _gm.add_gold(gold)
			if dice_scene:
				var p = dice_scene.instantiate()
				p.setup("Pickpocket %d ✓ — +%dgp" % [roll, gold], Color(0.95, 0.80, 0.10))
				p.global_position = global_position + Vector2(0, -18)
				get_tree().root.add_child(p)
	else:
		# Even drunk guards wake up if you're really clumsy
		if roll <= 3:
			_spook(player)
		else:
			if dice_scene:
				var p = dice_scene.instantiate()
				p.setup("Pickpocket %d ✗ — missed" % roll, Color(0.55, 0.50, 0.42))
				p.global_position = global_position + Vector2(0, -18)
				get_tree().root.add_child(p)

# INFORMANT — legacy bribe behavior
func _interact_informant(player: Node) -> void:
	_do_bribe(player, 50)

# ──────────────── SHARED BRIBE ────────────────

func _do_bribe(player: Node, bribe_cost: int) -> void:
	var dice_scene = load("res://DicePopup.tscn")
	var free_bribe: bool = false
	if _gm:
		free_bribe = _gm.get("selected_class") == "CUTPURSE" and not _gm.has_passive("_bribe_used")

	if not free_bribe and _gm and _gm.gold_available() < bribe_cost:
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Need %dgp to bribe" % bribe_cost, Color(0.85, 0.30, 0.20))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)
		return

	var roll := _roll_d20_with_class_bonus(player, "persuasion")
	var dc := 8 if disposition >= 0.5 else 13  # hostile NPCs harder to bribe

	if not free_bribe and _gm:
		_gm.gold_spent += bribe_cost
	if free_bribe and _gm:
		_gm.add_passive("_bribe_used")

	if roll >= dc:
		_bribed = true
		_spooked = false
		disposition = minf(disposition + 0.15, 1.0)
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Bribe %d ✓ — looks away" % roll, Color(0.40, 0.90, 0.45))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)
	else:
		disposition = maxf(disposition - 0.15, 0.0)
		if dice_scene:
			var p = dice_scene.instantiate()
			p.setup("Bribe %d ✗ — SHOUTS!" % roll, Color(1.0, 0.20, 0.20))
			p.global_position = global_position + Vector2(0, -16)
			get_tree().root.add_child(p)
		_spook(player)

# ──────────────── PROCESS ────────────────

func _process(delta: float) -> void:
	_t += delta
	_move_timer -= delta
	_drunk_sway += delta * 1.8
	_prisoner_chain_t += delta

	if _spooked:
		_spook_timer -= delta
		if _spook_timer <= 0.0:
			_spooked = false

	if _freed:
		_freed_timer -= delta
		_distract_t += delta
		if _freed_timer <= 0.0:
			_freed = false
			queue_free()
			return

	queue_redraw()

	if _move_timer <= 0.0 and not _spooked:
		_move_timer = _move_interval + randf_range(-0.3, 0.3)
		if npc_type == NPCType.DRUNK_GUARD:
			_advance_drunk()
		elif _freed:
			_advance_freed_prisoner()
		else:
			_advance_patrol()

	_check_player()

func _advance_patrol() -> void:
	if patrol_points.size() <= 1:
		return
	_pt_idx = (_pt_idx + 1) % patrol_points.size()
	var target: Vector2 = patrol_points[_pt_idx]
	var diff: Vector2   = target - global_position
	if diff.length() > 2.0:
		var step: Vector2
		if abs(diff.x) >= abs(diff.y):
			step = Vector2(sign(diff.x) * TILE_SIZE, 0)
		else:
			step = Vector2(0, sign(diff.y) * TILE_SIZE)
		global_position += step

func _advance_drunk() -> void:
	# Stumbles randomly
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var d: Vector2 = dirs[randi() % dirs.size()]
	global_position += d * TILE_SIZE * 0.5

func _advance_freed_prisoner() -> void:
	# Wander somewhat randomly, emitting noise occasionally
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var d: Vector2 = dirs[randi() % dirs.size()]
	global_position += d * TILE_SIZE
	# Shout periodically to draw guard attention
	if fmod(_distract_t, 4.0) < 0.2:
		for guard in get_tree().get_nodes_in_group("guards"):
			if global_position.distance_to(guard.global_position) <= 80.0:
				if guard.has_method("_on_noise_emitted"):
					guard._on_noise_emitted(1, global_position)

# ──────────────── PLAYER CHECK ────────────────

func _check_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player or _spooked or _bribed or _freed:
		return
	var dist: float = global_position.distance_to(player.global_position)

	# Disposition-based sight range
	var sight_range := 60.0
	if disposition <= 0.0:
		sight_range = 40.0  # hostile — skittish, shorter aggro range
	elif disposition >= 1.0:
		return  # fully friendly — don't spook

	if dist > sight_range:
		return

	# Line of sight
	var space := get_world_2d().direct_space_state
	var ray   := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	ray.exclude = [self]
	var result := space.intersect_ray(ray)
	if not (result.is_empty() or result.collider == player):
		return

	var carrying: bool = player.get("is_carrying_body") == true
	var any_alert := false
	for g in get_tree().get_nodes_in_group("guards"):
		if g.get("alert_state") == 2:
			any_alert = true
			break

	match npc_type:
		NPCType.SERVANT:
			# Won't alert unless physically confronted; only if carrying
			if carrying:
				_spook(player)
		NPCType.NOBLE:
			# Immediately screams if close and guards are alert
			if dist < 40.0 and any_alert:
				_spook(player)
			elif carrying:
				_spook(player)
		NPCType.MERCHANT:
			# Doesn't alert unless attacked (handled by hurt())
			pass
		NPCType.PRISONER:
			pass  # wants to be near player
		NPCType.DRUNK_GUARD:
			pass  # vision_range near zero — never alerts
		NPCType.INFORMANT:
			# Always spooks on eye contact
			_spook(player)
		_:
			if is_informant or carrying or any_alert:
				_spook(player)

func _spook(player: Node) -> void:
	if _spooked:
		return
	_spooked     = true
	_spook_timer = 5.0
	global_position += (global_position - player.global_position).normalized() * TILE_SIZE * 2

	for guard in get_tree().get_nodes_in_group("guards"):
		if global_position.distance_to(guard.global_position) <= 90.0:
			if guard.has_method("_on_noise_emitted"):
				guard._on_noise_emitted(2, global_position)

	if _gm:
		_gm.record_alert()
		_gm.raise_wanted_level(1)

	var dice_scene = load("res://DicePopup.tscn")
	if dice_scene:
		var popup = dice_scene.instantiate()
		var msg := _get_spook_message()
		popup.setup(msg, Color(1.0, 0.70, 0.15))
		popup.global_position = global_position + Vector2(0, -12)
		get_tree().root.add_child(popup)

func _get_spook_message() -> String:
	match npc_type:
		NPCType.NOBLE:    return "NOBLE — SHRIEKS!"
		NPCType.SERVANT:  return "SERVANT — SCREAMS!"
		NPCType.MERCHANT: return "MERCHANT — SHOUTS THIEF!"
		NPCType.PRISONER: return "PRISONER — PANICS!"
		NPCType.INFORMANT: return "INFORMANT — SCREAMS!"
		_:                return "CIVILIAN — SCREAMS!"

# ──────────────── UTILITY ────────────────

func _roll_d20_with_class_bonus(player: Node, skill_type: String) -> int:
	var base := 0
	if _gm and _gm.has_method("roll_d20"):
		base = _gm.roll_d20()
	else:
		base = randi_range(1, 20)

	var bonus := 0
	if _gm:
		match skill_type:
			"persuasion":
				if _gm.get("selected_class") in ["CUTPURSE", "TRICKSTER"]:
					bonus = 3
			"pickpocket":
				if _gm.get("selected_class") == "CUTPURSE":
					bonus = 4
				elif _gm.has_passive("LIGHT_FINGERS"):
					bonus = 2
			"intimidation":
				if _gm.get("selected_class") in ["SELLSWORD", "ENFORCER"]:
					bonus = 3

	return base + bonus

# ──────────────── DRAW ────────────────

func _draw() -> void:
	var pulse: float = sin(_t * 2.0) * 0.5 + 0.5

	match npc_type:
		NPCType.SERVANT:     _draw_servant(pulse)
		NPCType.NOBLE:       _draw_noble(pulse)
		NPCType.MERCHANT:    _draw_merchant(pulse)
		NPCType.PRISONER:    _draw_prisoner(pulse)
		NPCType.DRUNK_GUARD: _draw_drunk_guard(pulse)
		NPCType.INFORMANT:   _draw_informant(pulse)

	# Spooked ring
	if _spooked:
		draw_arc(Vector2.ZERO, 8.0, 0, TAU, 20,
			Color(1.0, 0.65, 0.10, 0.40 + pulse * 0.30), 1.5)
		draw_arc(Vector2.ZERO, 5.5, 0, TAU, 20,
			Color(1.0, 0.65, 0.10, 0.20 + pulse * 0.20), 1.0)

	# Disposition indicator (subtle color dot above head for friendly/hostile)
	if disposition >= 0.85 and not _spooked:
		draw_circle(Vector2(0, -12), 1.5, Color(0.35, 0.90, 0.42, 0.70))
	elif disposition <= 0.15 and not _spooked:
		draw_circle(Vector2(0, -12), 1.5, Color(0.90, 0.25, 0.20, 0.70))

func _draw_servant(pulse: float) -> void:
	# Shadow
	draw_circle(Vector2(0.5, 1.5), 4.5, Color(0, 0, 0, 0.22))
	# Plain tunic (muted gray-brown)
	var col := Color(0.62, 0.55, 0.40) if not _spooked else Color(0.80, 0.60, 0.30)
	if _bribed: col = Color(0.50, 0.55, 0.42)
	draw_circle(Vector2.ZERO, 4.5, col)
	draw_arc(Vector2.ZERO, 4.5, 0, TAU, 12,
		Color(col.r * 0.75, col.g * 0.75, col.b * 0.75), 0.8)  # tunic hem line
	# Head
	draw_circle(Vector2(0, -5.5), 3.0, Color(0.82, 0.68, 0.52))
	# Prop: broom handle (diagonal line)
	if not _spooked:
		draw_line(Vector2(3, -1), Vector2(7, 8), Color(0.55, 0.42, 0.25), 1.5)
		# Bristles
		draw_line(Vector2(7, 8), Vector2(5, 10), Color(0.60, 0.50, 0.30), 1.2)
		draw_line(Vector2(7, 8), Vector2(8, 10), Color(0.60, 0.50, 0.30), 1.2)
		draw_line(Vector2(7, 8), Vector2(9, 10), Color(0.60, 0.50, 0.30), 1.2)
	# Cap
	draw_arc(Vector2(0, -7.5), 3.5, PI, TAU, 10, Color(0.40, 0.35, 0.28), 2.0)

func _draw_noble(pulse: float) -> void:
	draw_circle(Vector2(0.5, 1.5), 5.0, Color(0, 0, 0, 0.25))
	# Ornate robe — rich purple/crimson
	var robe_col := Color(0.62, 0.18, 0.45) if not _spooked else Color(0.80, 0.25, 0.25)
	if _bribed: robe_col = Color(0.50, 0.15, 0.38)
	# Wide robe body
	var robe_pts := PackedVector2Array([
		Vector2(-6, -2), Vector2(6, -2), Vector2(7, 6), Vector2(-7, 6)
	])
	draw_colored_polygon(robe_pts, robe_col)
	draw_polyline(robe_pts + PackedVector2Array([robe_pts[0]]),
		Color(robe_col.r + 0.15, robe_col.g + 0.05, robe_col.b + 0.10), 0.9)
	# Gold trim
	draw_line(Vector2(-6, -2), Vector2(6, -2), Color(0.90, 0.75, 0.20, 0.80), 1.0)
	draw_line(Vector2(-3, -2), Vector2(-3, 6), Color(0.90, 0.75, 0.20, 0.60), 0.8)
	# Head
	draw_circle(Vector2(0, -5.5), 3.2, Color(0.88, 0.72, 0.55))
	# Plumed hat
	draw_rect(Rect2(-4, -11, 8, 4), Color(0.52, 0.14, 0.38))
	draw_rect(Rect2(-4, -11, 8, 4), Color(0.70, 0.22, 0.50), false, 0.8)
	# Feather plume
	draw_line(Vector2(2, -11), Vector2(6, -17), Color(0.88, 0.80, 0.65), 1.5)
	draw_circle(Vector2(6, -17), 2.0, Color(0.90, 0.84, 0.70, 0.80))
	# Jewel brooch (pocket item indicator)
	if not _pickpocketed:
		draw_circle(Vector2(0, -1), 1.5, Color(0.30, 0.65, 0.90, 0.90 + pulse * 0.10))
	# Monocle
	draw_arc(Vector2(1.5, -5.5), 1.5, 0, TAU, 12, Color(0.75, 0.72, 0.55, 0.60), 0.8)

func _draw_merchant(pulse: float) -> void:
	draw_circle(Vector2(0.5, 1.5), 4.5, Color(0, 0, 0, 0.22))
	# Apron — muted tan/orange
	var apron_col := Color(0.72, 0.55, 0.30) if not _spooked else Color(0.85, 0.65, 0.30)
	draw_circle(Vector2.ZERO, 4.8, apron_col)
	# Apron front (lighter rectangle)
	draw_rect(Rect2(-2.5, -3, 5, 7), Color(0.82, 0.72, 0.48))
	# Apron ties
	draw_line(Vector2(-2.5, -3), Vector2(-5, -1), Color(0.65, 0.50, 0.28), 1.0)
	draw_line(Vector2(2.5, -3), Vector2(5, -1), Color(0.65, 0.50, 0.28), 1.0)
	# Head
	draw_circle(Vector2(0, -5.5), 3.0, Color(0.80, 0.65, 0.48))
	# Belt pouch
	draw_circle(Vector2(-4, 2), 2.5, Color(0.55, 0.40, 0.20))
	draw_circle(Vector2(-4, 2), 2.5, Color(0.70, 0.52, 0.28), false, 0.8)
	draw_line(Vector2(-4, -0.5), Vector2(-4, -3), Color(0.60, 0.45, 0.22), 1.0)  # strap
	if not _merchant_items.is_empty():
		draw_arc(Vector2(-4, 2), 2.8, 0, TAU, 10, Color(0.90, 0.78, 0.18, 0.50 + pulse * 0.30), 1.0)

func _draw_prisoner(pulse: float) -> void:
	draw_circle(Vector2(0.5, 1.5), 4.0, Color(0, 0, 0, 0.20))
	# Ragged clothes — desaturated, torn
	var rag_col := Color(0.48, 0.42, 0.32) if not _freed else Color(0.52, 0.65, 0.42)
	# Hunched posture — offset body down
	draw_circle(Vector2(0, 2), 4.0, rag_col)
	# Torn tunic lines
	draw_line(Vector2(-3, 0), Vector2(-2, 4), Color(rag_col.r * 0.6, rag_col.g * 0.6, rag_col.b * 0.6), 0.8)
	draw_line(Vector2(2, -1), Vector2(3, 3), Color(rag_col.r * 0.6, rag_col.g * 0.6, rag_col.b * 0.6), 0.8)
	# Head (hunched = lower position)
	draw_circle(Vector2(-1, -3), 2.8, Color(0.75, 0.62, 0.48))
	# Chain links on wrists
	if not _freed:
		var chain_col := Color(0.60, 0.58, 0.45)
		var clink_t := _prisoner_chain_t
		for i in range(3):
			var cx := float(i - 1) * 3.0
			var cy := 5.0 + sin(clink_t * 2.0 + float(i)) * 0.5
			draw_arc(Vector2(cx - 3, cy), 1.5, 0, TAU, 8, chain_col, 1.0)
		for i in range(3):
			var cx := float(i - 1) * 3.0
			var cy := 5.0 + sin(clink_t * 2.0 + float(i)) * 0.5
			draw_arc(Vector2(cx + 3, cy), 1.5, 0, TAU, 8, chain_col, 1.0)
		# Ground chain line
		draw_line(Vector2(-6, 5.5), Vector2(6, 5.5), chain_col, 0.8)
	# Freed: small freedom aura
	if _freed:
		draw_arc(Vector2(0, 0), 7.0, 0, TAU, 16, Color(0.55, 0.90, 0.50, 0.30 + pulse * 0.20), 1.2)

func _draw_drunk_guard(pulse: float) -> void:
	var sway := sin(_drunk_sway) * 3.0
	draw_set_transform(Vector2(sway * 0.3, 0), sway * 0.04, Vector2.ONE)

	draw_circle(Vector2(0.5, 1.5), 5.0, Color(0, 0, 0, 0.22))
	# Guard armor but slumped — darker, dirtier
	var armor_col := Color(0.40, 0.40, 0.48)
	# Body armor (slightly lopsided)
	draw_rect(Rect2(-5, -4, 10, 9), armor_col)
	draw_rect(Rect2(-5, -4, 10, 9), Color(0.55, 0.55, 0.62), false, 0.8)
	# Pauldron (one drooping)
	draw_rect(Rect2(-6, -6, 4, 3), Color(0.45, 0.45, 0.52))
	draw_rect(Rect2(3, -5, 3, 2), Color(0.45, 0.45, 0.52))  # lopsided
	# Head (slumped, slightly tilted)
	draw_circle(Vector2(1, -5), 3.2, Color(0.80, 0.65, 0.50))
	# Helmet (half off)
	draw_rect(Rect2(-2, -9, 6, 4), Color(0.42, 0.42, 0.50))
	draw_rect(Rect2(-2, -9, 6, 4), Color(0.55, 0.55, 0.62), false, 0.8)
	# Ale mug in hand
	draw_rect(Rect2(4, -1, 4, 5), Color(0.55, 0.40, 0.18))
	draw_rect(Rect2(4, -1, 4, 5), Color(0.68, 0.52, 0.25), false, 0.8)
	draw_rect(Rect2(4, -1, 4, 1.5), Color(0.85, 0.78, 0.45, 0.70))  # foam
	# Hiccup bubble
	if fmod(_drunk_sway, 3.0) < 0.3:
		draw_circle(Vector2(2, -9), 2.5, Color(0.75, 0.80, 0.90, 0.35 + pulse * 0.25))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_informant(pulse: float) -> void:
	draw_circle(Vector2(0.5, 1.5), 4.5, Color(0, 0, 0, 0.22))
	var body_col := Color(0.55, 0.42, 0.20) if not _spooked else Color(0.80, 0.55, 0.20)
	if _bribed: body_col = Color(0.45, 0.38, 0.18)
	# Cloaked figure — darker, hood pulled low
	draw_circle(Vector2.ZERO, 4.5, body_col)
	# Hood (covers part of head)
	draw_arc(Vector2(0, -6), 4.0, PI, TAU, 14, Color(body_col.r * 0.72, body_col.g * 0.72, body_col.b * 0.72), 2.5)
	# Head peeking out
	draw_circle(Vector2(0, -5.5), 2.8, Color(0.72, 0.58, 0.42))
	# Subtle eye glint
	if not _spooked:
		draw_circle(Vector2(-1, -5.5), 0.8, Color(0.40, 0.35, 0.28))
		draw_circle(Vector2(1, -5.5), 0.8, Color(0.40, 0.35, 0.28))
	# Cautious aura (faint)
	draw_arc(Vector2.ZERO, 8.5, 0, TAU, 20, Color(0.65, 0.50, 0.18, 0.15 + pulse * 0.10), 1.0)
