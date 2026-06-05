extends Node
# Persistent cross-run progression: guild reputation, lifetime stats,
# unlocks, and save/load. Completely separate from per-run GameManager state.

const SAVE_PATH := "user://contraband_meta.cfg"

# ── Guild tier milestones ──────────────────────────────────────────────────────
const GUILD_TIERS: Array = [
	{"rep": 0,   "title": "Street Rat",      "color": Color(0.55, 0.55, 0.55)},
	{"rep": 10,  "title": "Guild Initiate",  "color": Color(0.60, 0.85, 0.55)},
	{"rep": 30,  "title": "Shadow Hand",     "color": Color(0.45, 0.65, 0.90)},
	{"rep": 60,  "title": "Nightblade",      "color": Color(0.75, 0.40, 0.90)},
	{"rep": 100, "title": "Master Thief",    "color": Color(0.95, 0.80, 0.20)},
	{"rep": 150, "title": "Phantom",         "color": Color(0.95, 0.95, 1.00)},
]

const GUILD_UNLOCKS: Array = [
	{"rep": 10,  "id": "GUILD_MARK",    "name": "Guild Mark",     "desc": "Start each floor with a 50 gp bonus."},
	{"rep": 20,  "id": "SELLSWORD",     "name": "Sellsword Class","desc": "Unlocks the Sellsword class for selection."},
	{"rep": 30,  "id": "FENCE_NETWORK", "name": "Fence Network",  "desc": "All shop items cost 15% less."},
	{"rep": 40,  "id": "TRINKETS",      "name": "Trinket Slots",  "desc": "Trinket gear slot unlocked in shop."},
	{"rep": 60,  "id": "SAFECRACKER",   "name": "Safecracker",    "desc": "Bonus loot yields +50% gold."},
	{"rep": 80,  "id": "INTEL_SYSTEM",  "name": "Intel Network",  "desc": "Pre-heist intel briefs now available."},
	{"rep": 100, "id": "SHADOW_GUILD",  "name": "Shadow Guild",   "desc": "Detection fills 20% slower always."},
	{"rep": 150, "id": "MASTERTHIEF",   "name": "Master Thief",   "desc": "Natural 1 on d20 treated as 5. Run modifier rerolls."},
]

# ── Per-run rating thresholds ──────────────────────────────────────────────────
const RATINGS: Array = [
	{"id": "LEGEND",        "name": "Legend",         "min_score": 1400, "color": Color(1.00, 0.90, 0.20)},
	{"id": "PHANTOM_THIEF", "name": "Phantom Thief",  "min_score":  900, "color": Color(0.95, 0.95, 1.00)},
	{"id": "SHADOWBLADE",   "name": "Shadowblade",    "min_score":  650, "color": Color(0.65, 0.40, 1.00)},
	{"id": "GHOST",         "name": "Ghost",          "min_score":  400, "color": Color(0.45, 0.80, 0.95)},
	{"id": "SELLSWORD",     "name": "Sellsword",      "min_score":  200, "color": Color(0.80, 0.55, 0.20)},
	{"id": "ROGUE",         "name": "Rogue",          "min_score":    0, "color": Color(0.55, 0.55, 0.55)},
]

# ── Heat (city awareness) ──────────────────────────────────────────────────────
# Heat persists across runs; decays 1 per day (not yet time-gated but structure is here)
const HEAT_LEVELS: Array = [
	{"level": 0, "name": "Unknown",      "color": Color(0.55, 0.55, 0.55), "guard_bonus": 0,    "patrol_mult": 1.00},
	{"level": 1, "name": "Rumored",      "color": Color(0.65, 0.80, 0.35), "guard_bonus": 0,    "patrol_mult": 1.00},
	{"level": 2, "name": "Known",        "color": Color(0.95, 0.78, 0.15), "guard_bonus": 1,    "patrol_mult": 1.10},
	{"level": 3, "name": "Sought",       "color": Color(0.95, 0.55, 0.15), "guard_bonus": 2,    "patrol_mult": 1.20},
	{"level": 4, "name": "Notorious",    "color": Color(0.90, 0.25, 0.15), "guard_bonus": 3,    "patrol_mult": 1.35},
	{"level": 5, "name": "City Watch",   "color": Color(0.85, 0.15, 0.15), "guard_bonus": 4,    "patrol_mult": 1.50},
]

# ── State ──────────────────────────────────────────────────────────────────────
var guild_rep:          int   = 0
var lifetime_gold:      int   = 0
var runs_completed:     int   = 0
var runs_attempted:     int   = 0
var best_rating:        String= ""
var lifetime_takedowns: int   = 0
var lifetime_alerts:    int   = 0
var ghost_runs:         int   = 0
var citadel_clears:     int   = 0   # full 6-floor completions
var city_heat:          int   = 0   # 0-5, persists and affects future runs
var unlocked_classes:   Array = ["CUTPURSE","SHADOWDANCER","ASSASSIN"]

# Which heist targets have been completed (for narrative continuity)
var completed_targets:  Array = []

# Active challenge contract chosen at run start
var active_contract:    String = "NONE"

# ── Signals ───────────────────────────────────────────────────────────────────
signal guild_rep_changed(new_rep: int, gained: int)
signal tier_reached(tier_data: Dictionary)
signal unlock_gained(unlock_data: Dictionary)
signal heat_changed(new_level: int)

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	load_progress()

# ── Guild tier ────────────────────────────────────────────────────────────────
func get_guild_tier() -> Dictionary:
	var best: Dictionary = GUILD_TIERS[0]
	for t in GUILD_TIERS:
		if guild_rep >= t["rep"]:
			best = t
	return best

func get_next_tier() -> Dictionary:
	for t in GUILD_TIERS:
		if guild_rep < t["rep"]:
			return t
	return GUILD_TIERS[-1]

func get_tier_progress() -> float:
	var current: Dictionary = get_guild_tier()
	var next: Dictionary    = get_next_tier()
	if current["rep"] == next["rep"]:
		return 1.0
	return float(guild_rep - current["rep"]) / float(next["rep"] - current["rep"])

# ── Rep gain ──────────────────────────────────────────────────────────────────
func add_rep(amount: int) -> void:
	var old_tier: Dictionary = get_guild_tier()
	guild_rep = max(0, guild_rep + amount)
	var new_tier: Dictionary = get_guild_tier()
	guild_rep_changed.emit(guild_rep, amount)
	if new_tier["rep"] > old_tier["rep"]:
		tier_reached.emit(new_tier)
		_check_unlocks()
	save_progress()

func _check_unlocks() -> void:
	for unlock in GUILD_UNLOCKS:
		if guild_rep >= unlock["rep"] and not has_unlock(unlock["id"]):
			if unlock["id"] == "SELLSWORD" and not "SELLSWORD" in unlocked_classes:
				unlocked_classes.append("SELLSWORD")
			unlock_gained.emit(unlock)

func has_unlock(unlock_id: String) -> bool:
	for unlock in GUILD_UNLOCKS:
		if unlock["id"] == unlock_id and guild_rep >= unlock["rep"]:
			return true
	return false

# ── Run completion ─────────────────────────────────────────────────────────────
func record_run_complete(score: int, gold: int, takedowns: int, alerts: int,
		was_ghost: bool, floors_completed: int) -> Dictionary:
	runs_completed += 1
	lifetime_gold += gold
	lifetime_takedowns += takedowns
	lifetime_alerts += alerts
	if was_ghost:
		ghost_runs += 1
	var rating: Dictionary = calculate_rating(score)
	if best_rating.is_empty() or score > _rating_score(best_rating):
		best_rating = rating["id"]
	# Rep gain: base + floors + ghost bonus
	var rep_gain: int = 5 + floors_completed * 3
	if was_ghost:
		rep_gain += 5
	if rating["id"] in ["PHANTOM_THIEF","SHADOWBLADE","LEGEND"]:
		rep_gain += 4
	if floors_completed >= 6:
		citadel_clears += 1
		rep_gain += 10   # Citadel clear is a prestige event
	add_rep(rep_gain)
	# Heat increase based on alerts
	var heat_gain: int = 0
	if alerts >= 3:   heat_gain = 2
	elif alerts >= 1: heat_gain = 1
	if was_ghost:     heat_gain = 0  # ghost run never raises heat
	# Exceptional runs cool the city's attention: ghost or Phantom Thief rating decays heat by 1
	if was_ghost or rating["id"] == "PHANTOM_THIEF":
		heat_gain -= 1
	set_heat(clamp(city_heat + heat_gain, 0, 5))
	save_progress()
	return {"rating": rating, "rep_gained": rep_gain, "heat_gained": heat_gain}

func record_run_failed() -> void:
	runs_attempted += 1
	set_heat(clamp(city_heat + 1, 0, 5))
	save_progress()

# ── Heat ──────────────────────────────────────────────────────────────────────
func set_heat(new_level: int) -> void:
	city_heat = clamp(new_level, 0, 5)
	heat_changed.emit(city_heat)

func get_heat_data() -> Dictionary:
	return HEAT_LEVELS[city_heat]

func get_heat_guard_bonus() -> int:
	return HEAT_LEVELS[city_heat]["guard_bonus"]

func get_heat_patrol_mult() -> float:
	return HEAT_LEVELS[city_heat]["patrol_mult"]

func decay_heat() -> void:
	if city_heat > 0:
		city_heat -= 1
		heat_changed.emit(city_heat)
		save_progress()

# ── Rating ────────────────────────────────────────────────────────────────────
func calculate_rating(score: int) -> Dictionary:
	for r in RATINGS:
		if score >= r["min_score"]:
			return r
	return RATINGS[-1]

func _rating_score(rating_id: String) -> int:
	for r in RATINGS:
		if r["id"] == rating_id:
			return r["min_score"]
	return 0

# ── Score calculation ──────────────────────────────────────────────────────────
func calculate_score(gold: int, run_time: float, alerts: int, takedowns: int,
		floors: int, was_ghost: bool, contract_bonus: int) -> int:
	var score: int = gold
	# Speed bonus: under 3 minutes
	if run_time < 180.0:
		score += int((180.0 - run_time) * 1.5)
	# Ghost bonus
	if was_ghost:
		score += 500
	# Alert penalty
	score -= alerts * 80
	# Takedown bonus (small — killing is not optimal)
	score += takedowns * 15
	# Floor depth bonus
	score += floors * 100
	# Contract bonus
	score += contract_bonus
	return max(0, score)

# ── Save / load ────────────────────────────────────────────────────────────────
func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "guild_rep",          guild_rep)
	cfg.set_value("meta", "lifetime_gold",      lifetime_gold)
	cfg.set_value("meta", "runs_completed",     runs_completed)
	cfg.set_value("meta", "runs_attempted",     runs_attempted)
	cfg.set_value("meta", "best_rating",        best_rating)
	cfg.set_value("meta", "lifetime_takedowns", lifetime_takedowns)
	cfg.set_value("meta", "lifetime_alerts",    lifetime_alerts)
	cfg.set_value("meta", "ghost_runs",         ghost_runs)
	cfg.set_value("meta", "citadel_clears",     citadel_clears)
	cfg.set_value("meta", "city_heat",          city_heat)
	cfg.set_value("meta", "unlocked_classes",   unlocked_classes)
	cfg.set_value("meta", "completed_targets",  completed_targets)
	cfg.save(SAVE_PATH)

func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	guild_rep          = cfg.get_value("meta", "guild_rep",          0)
	lifetime_gold      = cfg.get_value("meta", "lifetime_gold",      0)
	runs_completed     = cfg.get_value("meta", "runs_completed",     0)
	runs_attempted     = cfg.get_value("meta", "runs_attempted",     0)
	best_rating        = cfg.get_value("meta", "best_rating",        "")
	lifetime_takedowns = cfg.get_value("meta", "lifetime_takedowns", 0)
	lifetime_alerts    = cfg.get_value("meta", "lifetime_alerts",    0)
	ghost_runs         = cfg.get_value("meta", "ghost_runs",         0)
	citadel_clears     = cfg.get_value("meta", "citadel_clears",     0)
	city_heat          = cfg.get_value("meta", "city_heat",          0)
	unlocked_classes   = cfg.get_value("meta", "unlocked_classes",   ["CUTPURSE","SHADOWDANCER","ASSASSIN"])
	completed_targets  = cfg.get_value("meta", "completed_targets",  [])

func reset_all() -> void:
	guild_rep = 0; lifetime_gold = 0; runs_completed = 0; runs_attempted = 0
	best_rating = ""; lifetime_takedowns = 0; lifetime_alerts = 0
	ghost_runs = 0; city_heat = 0
	unlocked_classes = ["CUTPURSE","SHADOWDANCER","ASSASSIN"]
	completed_targets = []
	save_progress()
