## StatusEffectManager.gd — Player status effect manager (V12)
## Add to AutoLoad as "StatusEffectManager"
extends Node

signal effect_applied(id: String)
signal effect_expired(id: String)

# ── Effect definitions ─────────────────────────────────────────────────────────
# duration: -1 = use default below; positive = override seconds
const EFFECT_DEFS: Dictionary = {
	# id                default_dur  damage  dmg_interval  notes
	"BLEEDING":   {"dur": 15.0, "dmg": 2,  "tick": 5.0,  "tags": ["harmful", "floor_spread"]},
	"BURNING":    {"dur": 8.0,  "dmg": 1,  "tick": 2.0,  "tags": ["harmful", "fire_spread"]},
	"POISONED":   {"dur": 20.0, "dmg": 1,  "tick": 8.0,  "tags": ["harmful", "detection_penalty"]},
	"FEARED":     {"dur": 4.0,  "dmg": 0,  "tick": 0.0,  "tags": ["harmful", "no_attack", "haste_move"]},
	"SILENCED":   {"dur": 8.0,  "dmg": 0,  "tick": 0.0,  "tags": ["beneficial", "no_noise"]},
	"HASTED":     {"dur": 6.0,  "dmg": 0,  "tick": 0.0,  "tags": ["beneficial", "fast_move"]},
	"MARKED":     {"dur": 10.0, "dmg": 0,  "tick": 0.0,  "tags": ["harmful", "no_shadow_hide"]},
	"SLOWED":     {"dur": 6.0,  "dmg": 0,  "tick": 0.0,  "tags": ["harmful", "slow_move"]},
	"INVISIBLE":  {"dur": 5.0,  "dmg": 0,  "tick": 0.0,  "tags": ["beneficial", "no_detection"]},
}

# ── Active effects: id → { time_left, dmg_tick_accum } ────────────────────────
var _active: Dictionary = {}

# ── Cached autoload refs ───────────────────────────────────────────────────────
var _gm: Node = null      # GameManager
var _player: Node = null

func _ready() -> void:
	_gm = get_node_or_null("/root/GameManager")
	# Defer player lookup to first frame so scene is ready
	call_deferred("_cache_player")

func _cache_player() -> void:
	if get_tree():
		_player = get_tree().get_first_node_in_group("player")

# ── Public API ─────────────────────────────────────────────────────────────────

func apply(effect_id: String, duration: float = -1.0) -> void:
	if not EFFECT_DEFS.has(effect_id):
		push_warning("StatusEffectManager: unknown effect '%s'" % effect_id)
		return
	var def: Dictionary = EFFECT_DEFS[effect_id]
	var dur: float = duration if duration > 0.0 else def["dur"]

	# Refresh or apply
	if _active.has(effect_id):
		_active[effect_id]["time_left"] = maxf(_active[effect_id]["time_left"], dur)
	else:
		_active[effect_id] = {"time_left": dur, "dmg_tick_accum": 0.0}
		_on_effect_start(effect_id)
		effect_applied.emit(effect_id)

func has_effect(effect_id: String) -> bool:
	return _active.has(effect_id)

func clear(effect_id: String) -> void:
	if _active.has(effect_id):
		_active.erase(effect_id)
		_on_effect_end(effect_id)
		effect_expired.emit(effect_id)

func clear_all() -> void:
	for id in _active.keys():
		_on_effect_end(id)
		effect_expired.emit(id)
	_active.clear()

# Returns a list of active effect ids
func get_active() -> Array:
	return _active.keys()

# Returns true if effect has a given tag
func effect_has_tag(effect_id: String, tag: String) -> bool:
	if not EFFECT_DEFS.has(effect_id):
		return false
	return tag in EFFECT_DEFS[effect_id].get("tags", [])

# ── Process tick ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _gm != null and _gm.get("state") != null:
		# Only tick during active play
		var play_state = _gm.get("state")
		if play_state != _gm.get("State").PLAYING if _gm.get("State") != null else false:
			pass  # fall through — we still tick (graceful)

	if _player == null:
		_cache_player()

	var to_remove: Array[String] = []

	for id in _active.keys():
		var entry: Dictionary = _active[id]
		entry["time_left"] -= delta

		# Damage tick
		var def: Dictionary = EFFECT_DEFS.get(id, {})
		var tick_interval: float = def.get("tick", 0.0)
		var dmg_per_tick: int = def.get("dmg", 0)
		if tick_interval > 0.0 and dmg_per_tick > 0:
			entry["dmg_tick_accum"] += delta
			if entry["dmg_tick_accum"] >= tick_interval:
				entry["dmg_tick_accum"] -= tick_interval
				_apply_dot_damage(id, dmg_per_tick)

		if entry["time_left"] <= 0.0:
			to_remove.append(id)

	for id in to_remove:
		_active.erase(id)
		_on_effect_end(id)
		effect_expired.emit(id)

# ── Helpers ────────────────────────────────────────────────────────────────────

func _apply_dot_damage(effect_id: String, amount: int) -> void:
	if _gm == null:
		return
	if _gm.has_method("take_damage"):
		_gm.take_damage(amount)

	# BLEEDING: leave blood splatter on floor
	if effect_id == "BLEEDING" and _player != null:
		_spread_floor_effect(_player.global_position, "blood")

	# BURNING: spread fire tiles around player
	if effect_id == "BURNING" and _player != null:
		_spread_floor_effect(_player.global_position, "fire")

func _spread_floor_effect(world_pos: Vector2, fx_type: String) -> void:
	# Notify any floor-effect system listening for this (optional integration)
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("floor_fx_receiver"):
		if node.has_method("receive_floor_fx"):
			node.receive_floor_fx(fx_type, world_pos)

func _on_effect_start(effect_id: String) -> void:
	if _player == null:
		return
	match effect_id:
		"HASTED":
			if _player.has_method("set_move_interval"):
				_player.call("set_move_interval", 0.15)
			elif "move_interval" in _player:
				_player.move_interval = 0.15
		"SLOWED":
			if _player.has_method("set_move_interval"):
				_player.call("set_move_interval", 0.6)
			elif "move_interval" in _player:
				_player.move_interval = 0.6
		"FEARED":
			if "move_interval" in _player:
				_player.move_interval = _player.move_interval * 0.67  # 1.5x speed = 0.67x interval
		"SILENCED":
			if "silenced" in _player:
				_player.silenced = true
		"INVISIBLE":
			if "is_hidden" in _player:
				_player.is_hidden = true

func _on_effect_end(effect_id: String) -> void:
	if _player == null:
		return
	match effect_id:
		"HASTED", "SLOWED", "FEARED":
			# Restore default interval — player script stores its own default
			if _player.has_method("reset_move_interval"):
				_player.call("reset_move_interval")
			elif _player.get("_default_move_interval") != null:
				_player.move_interval = _player.get("_default_move_interval")
		"SILENCED":
			if "silenced" in _player:
				_player.silenced = false
		"INVISIBLE":
			if "is_hidden" in _player:
				_player.is_hidden = false

# ── Detection penalty query (called by Guard detection logic) ──────────────────
## Returns a multiplier to apply to guard detection fill rate.
## > 1.0 means player is detected faster; < 1.0 means slower.
func get_detection_multiplier() -> float:
	var mult := 1.0
	if has_effect("POISONED"):
		mult *= 1.5   # POISONED: detection +50%
	if has_effect("MARKED"):
		mult *= 9999.0  # MARKED: guards see through shadows (effectively always detected in range)
	if has_effect("INVISIBLE"):
		mult = 0.0    # INVISIBLE: no detection
	return mult

## Returns true if player noise emission should be suppressed.
func is_silenced() -> bool:
	return has_effect("SILENCED")
