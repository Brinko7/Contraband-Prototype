extends Node
# Generates a narrative context for each heist run.
# Provides: target name/description, story hook, mid-floor twist events,
# rumors, and post-floor narrative reactions.
#
# Usage: add as child node, call generate() at run start, then _process
# runs twist timers automatically.

signal twist_triggered(twist: Dictionary)

# ── Run narrative state ───────────────────────────────────────────────────────
var target_name: String     = ""
var target_location: String = ""
var macguffin: String       = ""
var story_hook: String      = ""
var run_twists: Array       = []  # this run's twist events

var _twist_timer: float  = 0.0
var _twist_min_time: float = 25.0  # earliest a twist fires
var _twist_max_time: float = 75.0  # latest

# ── Data pools ────────────────────────────────────────────────────────────────
const _TARGETS := [
	"Lord Aldric Vane",
	"The Merchant Prince Torval",
	"Inquisitor Harwick",
	"Countess Elara Dusk",
	"The Iron Brotherhood",
	"Spymaster Renn",
	"Archbishop Caldwell",
	"The Doge of Vareth",
]

const _LOCATIONS := [
	"Summer Estate",
	"City Tower",
	"Guild Hall",
	"Cathedral Vault",
	"War Room",
	"Private Dock Warehouse",
]

const _MACGUFFINS := [
	"the Blood Ledger",
	"the Stolen Crown",
	"a blackmail dossier",
	"the cipher key",
	"a prisoner's confession",
	"the heir's seal",
]

const _STORY_HOOKS := [
	"They framed your contact. Steal the ledger that proves it.",
	"The client wants it quiet — no bodies, no witnesses.",
	"The mark knows someone's coming. They've tripled the guard.",
	"You've been here before. They've changed everything since.",
	"The item was already stolen once. You're stealing it back.",
]

# Each twist: id, text, min_floor, max_floor (for flavor gating)
const _TWIST_POOL := [
	{
		"id":       "PATROL_CHANGE",
		"text":     "Shift rotation — guards are moving.",
		"flavor":   "The distant clatter of boots echoes through the corridor. Someone changed the schedule.",
	},
	{
		"id":       "LOCKDOWN_PARTIAL",
		"text":     "Someone found a footprint. Partial lockdown.",
		"flavor":   "An angry shout from below. Then the grinding of iron bolts. The vault re-locks.",
	},
	{
		"id":       "CIVILIAN_SCREAM",
		"text":     "A scream from the upper floor.",
		"flavor":   "A sharp cry, cut short. Guards snap to attention across the building.",
	},
	{
		"id":       "RIVAL_THIEF",
		"text":     "A shadow just passed the window — you're not alone.",
		"flavor":   "Smaller hands, quieter feet. Someone else is working this job tonight.",
	},
	{
		"id":       "GUARD_OFF_DUTY",
		"text":     "The south wing guard just clocked off.",
		"flavor":   "Footsteps fade toward the guardhouse. One fewer pair of eyes on the south corridor.",
	},
	{
		"id":       "REINFORCEMENTS",
		"text":     "Cavalry approaching — you have 90 seconds.",
		"flavor":   "Hoofbeats on cobblestone. The shift captain called it in. Clock's running.",
	},
]

# Per-floor rumor pools (indexed by floor number)
const _FLOOR_RUMORS := {
	1: [
		"Word is the cellar guard's been skimming the wine. He's distracted.",
		"They moved the vault key last week. Twice. Nobody tells the night shift anything.",
		"The hound master leaves early on Wednesdays. Tonight's Wednesday.",
		"South door's been sticking for a month. Guards use the side passage.",
		"The foreman drinks with the watch captain. He's not here tonight.",
		"New torches in the east hall. The old ones kept going out.",
	],
	2: [
		"The barracks sergeant runs drills at midnight. Everyone else hates it.",
		"Three guards swapped shifts tonight. Nobody knows the new rotation.",
		"The officer's been acting paranoid. Checked the vault twice in one hour.",
		"Heard there's a loose stone behind the duty board. Someone hides things there.",
		"Night watch has been doubled since the cellar incident. Word travels fast.",
		"The armory door squeaks. Guards leave it open to avoid the noise.",
	],
	3: [
		"The inner vault hasn't been opened in weeks. Whoever's been going in uses the back passage.",
		"A courier arrived at dusk. Something changed — the patrols are irregular now.",
		"The vault chamber has three locks, but only two guards know all three combinations.",
		"One of the Wardens is new. First week. He checks things other guards walk past.",
		"Someone reported a draft in the east corridor. They're looking for a hidden door.",
		"The treasury clerk left in a hurry this afternoon. Left his lamp burning.",
	],
	4: [
		"The Archduke's personal guard doesn't rotate with the rest. They answer to him alone.",
		"Three floors below, there was a break-in. Everyone upstairs heard about it.",
		"The sanctum door is on a delay-lock. Opens from inside only after the midnight bell.",
		"A Warden was dismissed last week. He knew too much — and now someone else does too.",
		"The hounds are kept off-leash in the sanctum corridor after dark.",
		"There's a second entrance through the chapel. It's been sealed, but not well.",
	],
	5: [
		"The throne room guard rotation is three minutes. They time it precisely.",
		"City Watch patrols the outer wall. They've been told to listen for noise inside.",
		"Something's been moved out of the throne vault. The guards who moved it aren't talking.",
		"The throne room floor was re-laid last year. Some tiles ring hollow.",
		"The Archduke's personal chamberlain sleeps in the adjacent room. Light sleeper.",
		"Two of the senior guards are under orders to shoot first if the alarm sounds.",
	],
	6: [
		"The Citadel vault hasn't been opened since before the current Archduke's reign.",
		"There are no guards inside the Citadel inner sanctum. Whatever protects it isn't guards.",
		"The last thief who reached the Citadel didn't make it out. Nobody found the body.",
		"The Broker sent three other crews here before you. You were told you were the first.",
		"Every corridor in the Citadel has a bell wire. Step carefully.",
		"The vault opens with sound, not a key. Whoever designed it thought no one would know that.",
	],
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func generate(floor_num: int, rng: RandomNumberGenerator) -> void:
	target_name     = _TARGETS[rng.randi() % _TARGETS.size()]
	target_location = _LOCATIONS[rng.randi() % _LOCATIONS.size()]
	macguffin       = _MACGUFFINS[rng.randi() % _MACGUFFINS.size()]
	story_hook      = _STORY_HOOKS[rng.randi() % _STORY_HOOKS.size()]

	# Pick 1–2 twists for this run, seeded by floor
	run_twists.clear()
	var pool := _TWIST_POOL.duplicate()
	# Shuffle using rng
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	var twist_count := 1 + (1 if floor_num >= 3 else 0)
	var base_time := _twist_min_time + rng.randf() * (_twist_max_time - _twist_min_time)
	for k in range(mini(twist_count, pool.size())):
		run_twists.append({
			"id":           pool[k].id,
			"text":         pool[k].text,
			"flavor":       pool[k].flavor,
			"trigger_time": base_time + k * 20.0,
			"triggered":    false,
		})

	_twist_timer = 0.0

func _process(delta: float) -> void:
	if run_twists.is_empty():
		return
	_twist_timer += delta
	for twist in run_twists:
		if not twist.triggered and _twist_timer >= twist.trigger_time:
			twist.triggered = true
			_apply_twist(twist)
			twist_triggered.emit(twist)

func _apply_twist(twist: Dictionary) -> void:
	var gm = get_node_or_null("/root/GameManager")
	match twist.id:
		"PATROL_CHANGE":
			# Randomize guard patrol paths — nudge guards to re-evaluate
			var guards := get_tree().get_nodes_in_group("guards") if get_tree() else []
			var changed := 0
			for g in guards:
				if changed >= 2:
					break
				if g.has_method("randomize_patrol"):
					g.call("randomize_patrol")
					changed += 1
				elif g.get("patrol_reversed") != null:
					g.set("patrol_reversed", not g.get("patrol_reversed"))
					changed += 1

		"LOCKDOWN_PARTIAL":
			# Re-lock vault doors on the floor
			for door in get_tree().get_nodes_in_group("vault_doors") if get_tree() else []:
				if door.has_method("relock"):
					door.call("relock")
				elif door.get("locked") != null:
					door.set("locked", true)

		"CIVILIAN_SCREAM":
			# All guards briefly go suspicious
			for guard in get_tree().get_nodes_in_group("guards") if get_tree() else []:
				if guard.get("alert_state") != null and guard.get("alert_state") < 1:
					guard.set("alert_state", 1)
					if guard.get("_suspicion_timer") != null:
						guard.set("_suspicion_timer", 4.0)

		"RIVAL_THIEF":
			# Spawn rival thief — a fast-moving civilian that targets loot
			_spawn_rival_thief()

		"GUARD_OFF_DUTY":
			# Remove one guard from patrol (deactivate)
			var guards := get_tree().get_nodes_in_group("guards") if get_tree() else []
			if not guards.is_empty():
				var target_g = guards[randi() % guards.size()]
				if target_g.has_method("set_off_duty"):
					target_g.call("set_off_duty")
				elif target_g.get("patrol_active") != null:
					target_g.set("patrol_active", false)

		"REINFORCEMENTS":
			# Escalate heat
			if gm:
				gm.floor_heat_level = mini(gm.floor_heat_level + 2, 5)
				gm.reinforcement_incoming.emit()

func _spawn_rival_thief() -> void:
	# Spawn a simple rival thief Node2D that moves toward loot
	var player := get_tree().get_first_node_in_group("player") if get_tree() else null
	if not player:
		return
	var world := get_tree().get_root().get_child(0) if get_tree() else null
	if not world:
		return

	var rival := Node2D.new()
	rival.name = "RivalThief"
	rival.add_to_group("rival_thief")

	# Position: offset from player
	rival.global_position = player.global_position + Vector2(randf_range(-200, 200), randf_range(-200, 200))

	var script := GDScript.new()
	script.source_code = """
extends Node2D
var _speed := 80.0
var _target_loot = null
var _lifetime := 30.0
func _process(delta):
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	if _target_loot == null or not is_instance_valid(_target_loot):
		var loot_nodes = get_tree().get_nodes_in_group("loot")
		if loot_nodes.is_empty():
			return
		_target_loot = loot_nodes[randi() % loot_nodes.size()]
	if _target_loot and is_instance_valid(_target_loot):
		var dir := (_target_loot.global_position - global_position).normalized()
		global_position += dir * _speed * delta
		if global_position.distance_to(_target_loot.global_position) < 12.0:
			_target_loot.queue_free()
			_target_loot = null
func _draw():
	draw_circle(Vector2.ZERO, 6.0, Color(0.15, 0.85, 0.55, 0.75))
	draw_arc(Vector2.ZERO, 8.0, 0, TAU, 16, Color(0.10, 0.60, 0.40, 0.55), 1.5)
"""
	rival.set_script(script)
	world.add_child(rival)

# ── Queries ───────────────────────────────────────────────────────────────────
func get_briefing_text() -> String:
	return "TARGET: %s\nLOCATION: %s\nOBJECTIVE: Retrieve %s\n\n\"%s\"" % [
		target_name, target_location, macguffin, story_hook
	]

func get_floor_rumors(floor_num: int) -> Array[String]:
	var pool: Array = _FLOOR_RUMORS.get(floor_num, _FLOOR_RUMORS.get(1, []))
	if pool.is_empty():
		return ["The guards seem jumpy tonight.", "Something changed on this floor."]
	var rng := RandomNumberGenerator.new()
	var gm = get_node_or_null("/root/GameManager")
	rng.seed = (gm.run_seed if gm else 12345) + floor_num * 7919
	# Shuffle and pick 2
	var shuffled := pool.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var result: Array[String] = []
	result.append(shuffled[0])
	if shuffled.size() > 1:
		result.append(shuffled[1])
	return result
