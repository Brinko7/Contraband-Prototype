extends Node
# Centralized combat resolution for all entities.
# Both player and guards call into here — no combat math lives elsewhere.
#
# DnD 5e-inspired: d20 roll + modifiers vs difficulty class (DC).
# Result: CRIT | SUCCESS | GRAZE | MISS

enum Result { CRIT, SUCCESS, GRAZE, MISS }

# ── Status effects ─────────────────────────────────────────────────────────────
enum Status {
	NONE,
	POISONED,    # -2 to all rolls, emits quiet noise every 4s
	BLEEDING,    # emits quiet noise every 3s until healed
	STUNNED,     # cannot act or move
	HELD,        # cannot move, can still be targeted
	CONFUSED,    # moves in random directions
	BLINDED,     # cannot see player or guards
	MARKED,      # next attack against this target is auto-crit
	SILENCED,    # area: all noise suppressed within radius
	SLOWED,      # movement speed halved
	FRENZIED,    # attacks random nearby target (guards only)
	EXPOSED,     # armor bypassed — takes +1 damage per hit
}

const STATUS_DURATIONS: Dictionary = {
	Status.POISONED:  10.0,
	Status.BLEEDING:   0.0,  # healed by item, not timed
	Status.STUNNED:    2.0,
	Status.HELD:       4.0,
	Status.CONFUSED:   6.0,
	Status.BLINDED:    5.0,
	Status.MARKED:     0.0,  # cleared on next hit
	Status.SILENCED:   8.0,
	Status.SLOWED:     6.0,
	Status.FRENZIED:   4.0,
	Status.EXPOSED:    8.0,
}

const STATUS_NAMES: Dictionary = {
	Status.NONE:      "",
	Status.POISONED:  "Poisoned",
	Status.BLEEDING:  "Bleeding",
	Status.STUNNED:   "Stunned",
	Status.HELD:      "Held",
	Status.CONFUSED:  "Confused",
	Status.BLINDED:   "Blinded",
	Status.MARKED:    "Marked",
	Status.SILENCED:  "Silenced",
	Status.SLOWED:    "Slowed",
	Status.FRENZIED:  "Frenzied",
	Status.EXPOSED:   "Exposed",
}

const STATUS_COLORS: Dictionary = {
	Status.POISONED:  Color(0.30, 0.80, 0.35),
	Status.BLEEDING:  Color(0.90, 0.20, 0.20),
	Status.STUNNED:   Color(0.95, 0.85, 0.20),
	Status.HELD:      Color(0.55, 0.40, 0.90),
	Status.CONFUSED:  Color(0.80, 0.50, 0.90),
	Status.BLINDED:   Color(0.70, 0.70, 0.75),
	Status.MARKED:    Color(0.95, 0.30, 0.20),
	Status.SILENCED:  Color(0.30, 0.25, 0.55),
	Status.SLOWED:    Color(0.45, 0.65, 0.90),
	Status.FRENZIED:  Color(0.95, 0.45, 0.15),
	Status.EXPOSED:   Color(0.85, 0.65, 0.20),
}

# ── Takedown configuration ─────────────────────────────────────────────────────
# Thresholds for d20 roll after modifiers. Unmodified range: 1-20.
const TAKEDOWN_DC: Dictionary = {
	"frontal":  14,   # facing enemy head-on — hardest
	"side":     10,   # approaching from the side
	"rear":      6,   # attacking from behind — easiest
	"unaware":   3,   # target is fully unaware (not in any alert state)
}

# Modifiers applied to d20 roll
const MODIFIER_IRON_NERVES:   int = 2
const MODIFIER_ASSASSINS_EYE: int = 4   # lowers DC for frontal
const MODIFIER_IRON_WILL:     int = 0   # not a roll modifier — changes miss to graze
const MODIFIER_RUN:           int = 2   # run modifier LUCKY_BREAK
const MODIFIER_CURSED_DICE:   int = -3

# ── Signals ────────────────────────────────────────────────────────────────────
signal takedown_resolved(attacker: Node, target: Node, result: Result, damage: int)
signal status_applied(target: Node, status: Status, duration: float)
signal status_cleared(target: Node, status: Status)
signal damage_dealt(target: Node, amount: int, is_silent: bool)

# ── Roll a d20 with modifiers ──────────────────────────────────────────────────
func roll_d20(bonus: int = 0) -> int:
	var raw: int = randi_range(1, 20)
	# HALFLING: reroll nat 1
	if raw == 1 and GameManager.selected_race == "HALFLING":
		raw = randi_range(1, 20)
	var result: int = clamp(raw + bonus, 1, 20)
	return result

# ── Takedown approach detection ────────────────────────────────────────────────
func get_approach(attacker: Node, target: Node) -> String:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return "frontal"
	var to_target: Vector2 = (target.global_position - attacker.global_position).normalized()
	var target_facing: Vector2 = target.get("facing") if target.get("facing") != null else Vector2.RIGHT
	# Rear: attacker is behind target (target is looking away)
	var dot: float = target_facing.dot(to_target)
	if dot > 0.6:
		return "rear"
	elif dot < -0.3:
		return "frontal"
	return "side"

# ── Core takedown resolution ───────────────────────────────────────────────────
# Returns a Result enum value.
# is_unaware: target doesn't know attacker is near
# bonuses: array of int modifiers (each passive/gear effect adds one)
func resolve_takedown(attacker: Node, target: Node, weapon_id: String,
		is_unaware: bool = false, bonuses: Array = []) -> Result:

	# Determine approach angle
	var approach: String = "frontal"
	if is_unaware:
		approach = "unaware"
	else:
		approach = get_approach(attacker, target)

	# Weapons that bypass the roll entirely
	var weapon_tags: Array = WeaponDatabase.WEAPONS.get(weapon_id, {}).get("tags", [])
	if "shadow" in weapon_tags and is_unaware:
		return Result.SUCCESS
	if weapon_id == "GARROTE" and approach in ["rear","unaware"]:
		return Result.SUCCESS

	# Build total bonus
	var total_bonus: int = 0
	for b in bonuses:
		total_bonus += b
	# Run modifier
	if GameManager.run_modifier == "LUCKY_BREAK":
		total_bonus += MODIFIER_RUN
	elif GameManager.run_modifier == "CURSED_DICE":
		total_bonus += MODIFIER_CURSED_DICE

	var roll: int = roll_d20(total_bonus)
	var dc: int   = TAKEDOWN_DC.get(approach, TAKEDOWN_DC["frontal"])

	# ASSASSIN class bonus: frontal DC effectively lowered
	if GameManager.selected_class == "ASSASSIN" and approach == "frontal":
		dc -= 4

	if roll == 20:
		return Result.CRIT
	elif roll >= dc:
		return Result.SUCCESS
	elif roll >= dc - 4:
		return Result.GRAZE
	else:
		return Result.MISS

# ── Melee attack (combat, not stealth takedown) ────────────────────────────────
func resolve_attack(attacker: Node, target: Node, weapon_id: String,
		is_charged: bool = false, bonuses: Array = []) -> Dictionary:
	var cdata: Dictionary = WeaponDatabase.COMBAT.get(weapon_id, WeaponDatabase.COMBAT["NONE"])
	var base_dmg: int = cdata.get("damage", 1)
	if is_charged:
		base_dmg = ceili(base_dmg * 1.75)

	# Combo tier bonus (SHARP = +20%)
	if GameManager.combo_tier >= 1:
		base_dmg = ceili(base_dmg * 1.2)

	# Status: EXPOSED gives +1
	if target.has_method("has_status") and target.call("has_status", Status.EXPOSED):
		base_dmg += 1

	# MARKED = auto-crit
	var is_crit: bool = false
	if target.has_method("has_status") and target.call("has_status", Status.MARKED):
		is_crit = true
		if target.has_method("clear_status"):
			target.call("clear_status", Status.MARKED)

	var roll: int = roll_d20()
	if roll == 20:
		is_crit = true
	if is_crit:
		base_dmg *= 2

	var noise_r: float = cdata.get("noise_r", 60.0)
	var is_silent: bool = noise_r == 0.0 or ("silent" in weapon_tags_for(weapon_id))

	return {
		"damage":    base_dmg,
		"is_crit":   is_crit,
		"roll":      roll,
		"is_silent": is_silent,
		"noise_r":   noise_r,
	}

# ── Apply damage to any entity with hp ────────────────────────────────────────
func apply_damage(target: Node, amount: int, source_weapon: String = "NONE") -> void:
	if not is_instance_valid(target):
		return
	if target.has_method("hurt"):
		var dir: Vector2 = Vector2.ZERO
		target.call("hurt", amount, dir)
	damage_dealt.emit(target, amount, WeaponDatabase.get_combat(source_weapon).get("noise_r", 60.0) == 0.0)

# ── Status effect application ──────────────────────────────────────────────────
func apply_status(target: Node, status: Status, duration_override: float = -1.0) -> void:
	if not is_instance_valid(target):
		return
	var dur: float = duration_override if duration_override >= 0.0 else STATUS_DURATIONS.get(status, 4.0)
	if target.has_method("apply_status"):
		target.call("apply_status", status, dur)
	status_applied.emit(target, status, dur)

# ── Weapon tag helper ──────────────────────────────────────────────────────────
func weapon_tags_for(weapon_id: String) -> Array:
	return WeaponDatabase.WEAPONS.get(weapon_id, {}).get("tags", [])

# ── Wall slam check ────────────────────────────────────────────────────────────
func is_against_wall(entity: Node, direction: Vector2) -> bool:
	if not entity.has_method("is_position_blocked"):
		return false
	var tile_size: int = 16
	var check_pos: Vector2 = entity.global_position + direction * tile_size
	return entity.call("is_position_blocked", check_pos)

# ── Check if a takedown would be silent ───────────────────────────────────────
func would_be_silent(attacker: Node, weapon_id: String, approach: String) -> bool:
	var tags: Array = weapon_tags_for(weapon_id)
	if "silent" in tags:
		return true
	if weapon_id == "GARROTE" and approach in ["rear","unaware"]:
		return true
	# SHADOWDANCER: first 2 sneak takedowns per floor are silent
	if GameManager.selected_class == "SHADOWDANCER":
		var kills: int = attacker.get("_shadowdancer_silent_kills") if attacker.get("_shadowdancer_silent_kills") != null else 3
		if kills < 2:
			return true
	return false
