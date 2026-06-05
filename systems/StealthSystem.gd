extends Node
# Centralized stealth and detection math.
# Guards query this system rather than implementing their own detection logic.

# ── Detection fill rates (seconds to fill 0→1) ───────────────────────────────
const BASE_FILL_RATES: Dictionary = {
	"UNAWARE":    0.9,   # guard hasn't noticed anything
	"SUSPICIOUS": 0.5,   # guard is on alert, saw something
}

# ── Noise levels ──────────────────────────────────────────────────────────────
enum NoiseLevel { SILENT, QUIET, LOUD }

const NOISE_RADII: Dictionary = {
	NoiseLevel.SILENT:  0.0,
	NoiseLevel.QUIET:  48.0,
	NoiseLevel.LOUD:  140.0,
}

# ── Signals ───────────────────────────────────────────────────────────────────
signal noise_event(origin: Vector2, level: NoiseLevel, radius: float, source: Node)
signal player_spotted(guard: Node, player: Node)
signal player_detected(guard: Node)

# ── Player-facing detection modifier ──────────────────────────────────────────
# Returns a multiplier applied to the guard's detection fill rate.
# Values < 1.0 = harder to detect. Values > 1.0 = easier to detect.
func get_player_detect_mult(player: Node, is_sneaking: bool, guard_alert_state: int) -> float:
	var mult: float = 1.0

	# Sneaking
	if is_sneaking:
		mult *= 0.7
		# Dark Shroud passive
		if GameManager.has_passive("DARK_SHROUD"):
			mult *= 0.7
		# SHADOWDANCER: sneak much harder to detect
		if GameManager.selected_class == "SHADOWDANCER":
			mult *= 0.6
	# Walking
	else:
		if GameManager.has_passive("SOFT_BOOTS"):
			mult *= 0.85
		if GameManager.has_gear_effect("SOFT_WALK"):
			mult *= 0.85

	# HALFLING racial bonus
	if GameManager.selected_race == "HALFLING":
		mult *= 0.8

	# WOOD_ELF: silent movement
	if GameManager.selected_race == "WOOD_ELF" and is_sneaking:
		mult *= 0.5

	# Shadow Cloak Oil item active
	if player.get("_shadow_oil_timer") != null and player.get("_shadow_oil_timer") > 0.0:
		mult *= 0.6

	# SHADOW_GUILD guild unlock
	if MetaProgress.has_unlock("SHADOW_GUILD"):
		mult *= 0.8

	# Dodge i-frames: completely invisible to detection
	if player.get("_dodge_iframes") != null and player.get("_dodge_iframes") > 0.0:
		return 0.0

	# Hidden in hiding spot
	if player.get("is_hidden") != null and player.get("is_hidden"):
		return 0.0

	return mult

# ── Line of sight check (2D raycast) ─────────────────────────────────────────
# Returns true if there is an unobstructed line from origin to target.
func has_line_of_sight(space_state: PhysicsDirectSpaceState2D,
		origin: Vector2, target: Vector2, exclude_rids: Array = []) -> bool:
	var params := PhysicsRayQueryParameters2D.create(origin, target)
	params.exclude = exclude_rids
	params.collision_mask = 1   # walls layer
	var result := space_state.intersect_ray(params)
	return result.is_empty()

# ── Cone visibility check ─────────────────────────────────────────────────────
# Returns true if target_pos is within the guard's vision cone AND in range.
func is_in_vision_cone(guard_pos: Vector2, guard_facing: Vector2,
		target_pos: Vector2, vision_range: float, vision_angle_deg: float) -> bool:
	var to_target: Vector2 = target_pos - guard_pos
	if to_target.length_squared() > vision_range * vision_range:
		return false
	var angle_to: float = rad_to_deg(guard_facing.angle_to(to_target.normalized()))
	return absf(angle_to) <= vision_angle_deg * 0.5

# ── Noise propagation ─────────────────────────────────────────────────────────
func emit_noise(origin: Vector2, level: NoiseLevel, source: Node) -> void:
	var radius: float = NOISE_RADII.get(level, 0.0)
	if radius <= 0.0:
		return
	# Run modifier: THIN_WALLS increases noise range
	if GameManager.run_modifier == "THIN_WALLS":
		radius += 40.0
	noise_event.emit(origin, level, radius, source)

# ── Guard detection fill rate for current conditions ──────────────────────────
func get_guard_fill_rate(base_state_key: String, complication: String,
		modifier: String, alert_escalation: int) -> float:
	var rate: float = BASE_FILL_RATES.get(base_state_key, BASE_FILL_RATES["UNAWARE"])

	# Floor complication
	match complication:
		"PARANOID":
			rate *= 0.60
		"DIM":
			rate *= 1.20   # dim = guard is jumpy
		"LOCKDOWN":
			rate *= 0.55

	# Run modifier
	match modifier:
		"HIGH_ALERT":
			rate *= 0.60
		"CRACKDOWN":
			rate *= 0.45   # never drains
		"UNDER_THE_MOON":
			rate *= 0.80

	# Alert escalation pressure (worse guards over time)
	if alert_escalation >= 4:
		rate *= 0.85
	if alert_escalation >= 6:
		rate *= 0.75

	return rate

# ── Noise radius with item modifications ──────────────────────────────────────
func get_movement_noise_radius(player: Node, is_sneaking: bool) -> float:
	if GameManager.selected_race == "WOOD_ELF":
		return 0.0
	if player.get("is_hidden") == true:
		return 0.0
	if is_sneaking:
		if GameManager.has_passive("GHOST_STEP"):
			return 0.0
		if GameManager.has_gear_effect("GHOST_BOOTS"):
			return 0.0
		if GameManager.has_set_bonus("SET_THIEF"):
			return 0.0
		return NOISE_RADII[NoiseLevel.QUIET] * 0.5
	# Walking
	if GameManager.has_passive("SOFT_BOOTS") or GameManager.has_gear_effect("SOFT_WALK"):
		return NOISE_RADII[NoiseLevel.QUIET]
	if GameManager.selected_class == "CUTPURSE":
		return NOISE_RADII[NoiseLevel.QUIET]
	return NOISE_RADII[NoiseLevel.LOUD]
