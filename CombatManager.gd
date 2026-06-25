extends Node
# ── Contraband V12 CombatManager ──────────────────────────────────────────────
# Spawned by World. Tracks positioning advantages for DnD-style combat bonuses.
# Flanking, high ground, backstab, cover — all contribute to d20 rolls.
# Add to group "combat_manager" on spawn.

var _game_manager: Node = null

func _ready() -> void:
	add_to_group("combat_manager")
	_game_manager = get_node_or_null("/root/GameManager")

# ── Attack bonus calculation ──────────────────────────────────────────────────
# Returns total attack bonus modifier to add to attacker's d20 roll.
func get_attack_bonus(attacker: Node2D, target: Node2D) -> int:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return 0
	var bonus: int = 0

	# +2: backstab — attacker is behind target
	# "behind" = the vector from target to attacker goes the same direction as target's facing
	var to_attacker: Vector2 = (attacker.global_position - target.global_position).normalized()
	var target_facing: Vector2 = Vector2.RIGHT
	if target.get("facing") != null:
		target_facing = target.get("facing").normalized()
	var backstab_dot: float = target_facing.dot(to_attacker)
	if backstab_dot > 0.7:
		bonus += 2

	# +1: attacker in shadow, target in light
	var attacker_in_shadow: bool = false
	var target_in_light: bool = false
	if attacker.has_method("_is_in_shadow"):
		attacker_in_shadow = attacker._is_in_shadow()
	elif attacker.get("_shadow_t") != null:
		attacker_in_shadow = attacker.get("_shadow_t") > 0.5
	if target.has_method("_is_in_light"):
		target_in_light = target._is_in_light()
	if attacker_in_shadow and target_in_light:
		bonus += 1

	# +2: flanking — an ally (or another guard if target is the player) is on the
	# opposite side of the target from the attacker.
	if check_flanking(attacker, target):
		bonus += 2

	# -1: target has cover — within 16px of a wall/obstacle
	if _target_has_cover(target):
		bonus -= 1

	# +3: target is sleeping or off-duty
	var target_sleeping: bool = false
	if target.get("_is_sleeping") != null:
		target_sleeping = target.get("_is_sleeping")
	if target.get("_is_off_duty") != null:
		target_sleeping = target_sleeping or target.get("_is_off_duty")
	if target_sleeping:
		bonus += 3

	# +1 per combo_tier (from GameManager)
	if _game_manager != null:
		bonus += _game_manager.combo_tier

	return bonus

# ── Defense bonus calculation ──────────────────────────────────────────────────
# Returns defense DC modifier for the defender.
func get_defense_bonus(defender: Node2D) -> int:
	if not is_instance_valid(defender):
		return 0
	var bonus: int = 0

	# Cover adds +1
	if _target_has_cover(defender):
		bonus += 1

	# Alert state: ALERT guards are braced — +1
	if defender.get("alert_state") != null:
		var AlertState = defender.get_script().get_script_constant_map().get("AlertState", null) if defender.get_script() else null
		var state_val: int = defender.get("alert_state")
		# AlertState.ALERT is typically index 2
		if state_val == 2:
			bonus += 1

	# PRONE is -2 defense (handled by caller checking is_prone)
	if defender.get("_is_prone") != null and defender.get("_is_prone"):
		bonus -= 2

	return bonus

# ── Flanking check ────────────────────────────────────────────────────────────
# Returns true if any ally of the attacker is on the roughly opposite side of target.
func check_flanking(attacker: Node2D, target: Node2D) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return false
	var atk_dir: Vector2 = (attacker.global_position - target.global_position).normalized()
	# Check guards (for player attacker) or player allies
	var candidates: Array = []
	if attacker.is_in_group("player"):
		# Player flanked by checking if any guard is on the other side — rare but valid
		# More typically: player has a summoned/distracted guard pulling attention
		candidates = attacker.get_tree().get_nodes_in_group("guards")
	else:
		# Guard attacker — check if another guard flanks
		candidates = attacker.get_tree().get_nodes_in_group("guards")

	for ally in candidates:
		if ally == attacker or not is_instance_valid(ally):
			continue
		if target.global_position.distance_to(ally.global_position) > 80.0:
			continue
		var ally_dir: Vector2 = (ally.global_position - target.global_position).normalized()
		# Flanking: the ally is on the opposite side (dot product < -0.5)
		if atk_dir.dot(ally_dir) < -0.5:
			return true
	return false

# ── Cover check ──────────────────────────────────────────────────────────────
func _target_has_cover(target: Node2D) -> bool:
	if not is_instance_valid(target):
		return false
	# Check if any wall tile is within 16px using the physics space
	var space_state := target.get_world_2d().direct_space_state
	var check_dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for dir in check_dirs:
		var query := PhysicsRayQueryParameters2D.create(
			target.global_position,
			target.global_position + dir * 16.0,
			0x1  # collision layer 1 (walls/tilemap)
		)
		query.exclude = [target.get_rid()]
		var result := space_state.intersect_ray(query)
		if not result.is_empty():
			return true
	return false

# ── Finishing move resolver ───────────────────────────────────────────────────
# Called on Nat20 takedown. Returns class-specific flavor + bonuses.
func resolve_finishing_move(attacker: Node2D, target: Node2D, roll: int) -> Dictionary:
	if roll < 20:
		return {}
	var selected_class: String = "CUTPURSE"
	if _game_manager != null:
		selected_class = _game_manager.selected_class

	var flavor: String = "Perfect strike!"
	var bonus_gold: int = 25
	var bonus_xp: int = 2

	# Guard's current HP for flavor variance
	var target_hp: int = 999
	if target.get("guard_hp") != null:
		target_hp = target.get("guard_hp")

	match selected_class:
		"CUTPURSE":
			var options: Array = [
				"Coin to the temple — lights out.",
				"You never heard a thing.",
				"A quick hand. Quicker elbow.",
				"Their coin pouch was already in your hand.",
			]
			flavor = options[randi() % options.size()]
			bonus_gold = 40  # Cutpurse pockets extra
		"ASSASSIN":
			var options: Array = [
				"Shadow step — blade through the gap in their armor.",
				"The mark never blinked.",
				"Clean. Quiet. Gone.",
				"One motion. One less problem.",
			]
			flavor = options[randi() % options.size()]
			bonus_gold = 20
			bonus_xp = 3  # Assassin gets more XP for style
		"SELLSWORD":
			var options: Array = [
				"Shoulder slam into the wall — they crumple.",
				"Not a fight. An ending.",
				"They brought a patrol. You brought experience.",
				"Knocked cold before they could cry out.",
			]
			flavor = options[randi() % options.size()]
			bonus_gold = 20
			bonus_xp = 2
		"SHADOWDANCER":
			var options: Array = [
				"From shadow into shadow — they never existed.",
				"A whisper of steel. No echo.",
				"The shadow took them.",
				"You were never in this room.",
			]
			flavor = options[randi() % options.size()]
			bonus_gold = 30
		_:
			flavor = "Perfect strike!"

	return {
		"flavor":     flavor,
		"bonus_gold": bonus_gold,
		"bonus_xp":   bonus_xp,
	}
