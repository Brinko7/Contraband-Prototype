extends Node
# Single source of truth for all weapon data.
# Referenced by CombatSystem, PlayerCombat, HUD, Shop, ClassSelect.

const WEAPONS: Dictionary = {
	# ── Cutpurse line ────────────────────────────────────────────────────────
	"SHIV": {
		"name": "Shiv", "class": "CUTPURSE", "tier": 1,
		"tags": ["piercing","throwable"],
		"desc": "+2 to rear takedowns. Throw once per floor for a silent 80px kill.",
		"color": Color(0.65, 0.65, 0.70),
	},
	"STILETTO": {
		"name": "Stiletto", "class": "CUTPURSE", "tier": 2,
		"tags": ["piercing","silent","throwable"],
		"desc": "Rear takedowns always silent. Throw up to 2×/floor. +3 vs unaware.",
		"color": Color(0.80, 0.78, 0.85),
	},
	"ASSASSIN_FANG": {
		"name": "Assassin's Fang", "class": "CUTPURSE", "tier": 3,
		"tags": ["piercing","silent","throwable","shadow"],
		"desc": "All takedowns count as rear. Throw ignores detection bar. Nat-1 becomes 5.",
		"color": Color(0.55, 0.30, 0.95),
	},
	# ── Shadowdancer line ────────────────────────────────────────────────────
	"SHADOW_BLADE": {
		"name": "Shadow Blade", "class": "SHADOWDANCER", "tier": 1,
		"tags": ["shadow","silent"],
		"desc": "Sneak takedowns always silent. Backstab from full darkness skips d20.",
		"color": Color(0.50, 0.25, 0.85),
	},
	"GHOST_BLADE": {
		"name": "Ghost Blade", "class": "SHADOWDANCER", "tier": 2,
		"tags": ["shadow","silent","piercing"],
		"desc": "No noise on any takedown. 3 phantom strikes/floor skip d20 regardless of light.",
		"color": Color(0.65, 0.40, 1.00),
	},
	"VOID_REAPER": {
		"name": "Void Reaper", "class": "SHADOWDANCER", "tier": 3,
		"tags": ["shadow","silent","piercing","cursed"],
		"desc": "Takedowns erase the body. 5 phantom strikes/floor. Souls fuel detection drain.",
		"color": Color(0.35, 0.10, 0.70),
	},
	# ── Assassin line ────────────────────────────────────────────────────────
	"CROSSBOW": {
		"name": "Hand Crossbow", "class": "ASSASSIN", "tier": 1,
		"tags": ["ranged","piercing"],
		"desc": "200px ranged kill. Loud unless silenced. 3 bolts per floor.",
		"color": Color(0.55, 0.38, 0.22),
	},
	"REPEATING_CROSSBOW": {
		"name": "Repeating Crossbow", "class": "ASSASSIN", "tier": 2,
		"tags": ["ranged","piercing"],
		"desc": "5 bolts/floor. 250px range. Reload silent. NAT20 pierces two guards.",
		"color": Color(0.70, 0.50, 0.28),
	},
	"SILENT_BOLT": {
		"name": "Silenced Arbalest", "class": "ASSASSIN", "tier": 3,
		"tags": ["ranged","piercing","silent"],
		"desc": "Unlimited silent bolts. 300px range. Every kill resets detection on nearby guards.",
		"color": Color(0.85, 0.65, 0.35),
	},
	# ── Sellsword line ───────────────────────────────────────────────────────
	"LONGSWORD": {
		"name": "Longsword", "class": "SELLSWORD", "tier": 1,
		"tags": ["heavy"],
		"desc": "Wide slash attack. Makes noise but hits multiple enemies in arc.",
		"color": Color(0.80, 0.75, 0.55),
	},
	"BROADSWORD": {
		"name": "Broadsword", "class": "SELLSWORD", "tier": 2,
		"tags": ["heavy","piercing"],
		"desc": "Heavier slash. NAT20 staggers nearby enemies. +1 damage vs armored guards.",
		"color": Color(0.90, 0.82, 0.60),
	},
	"BLADESONG": {
		"name": "Bladesong", "class": "SELLSWORD", "tier": 3,
		"tags": ["heavy","shadow"],
		"desc": "Enchanted blade. Slash silenced in shadow. NAT20 splits into two arcs.",
		"color": Color(0.65, 0.85, 1.00),
	},
	# ── Universal found weapons ───────────────────────────────────────────────
	"GARROTE": {
		"name": "Garrote Wire", "class": "", "tier": 2,
		"tags": ["silent","heavy"],
		"desc": "From behind: always silent kill, no dice. Frontal: -4 penalty. Requires 2s hold.",
		"color": Color(0.72, 0.68, 0.60),
	},
	"VENOM_NEEDLE": {
		"name": "Venom Needle", "class": "", "tier": 2,
		"tags": ["piercing","silent","throwable"],
		"desc": "120px throw: target stumbles (confused 6s) then falls silently. 2 uses.",
		"color": Color(0.30, 0.75, 0.35),
	},
	"RUNED_BLADE": {
		"name": "Runed Blade", "class": "", "tier": 3,
		"tags": ["shadow","piercing","cursed"],
		"desc": "Kills charge the rune. 3 charges = free shadow step. Cursed: -1 HP/floor.",
		"color": Color(0.50, 0.20, 0.80),
	},
	"SMOKE_BLADE": {
		"name": "Smoke Blade", "class": "", "tier": 2,
		"tags": ["silent","shadow"],
		"desc": "Silent kills release a 3s smoke cloud at target position.",
		"color": Color(0.55, 0.75, 0.65),
	},
	"WAR_PICK": {
		"name": "War Pick", "class": "", "tier": 1,
		"tags": ["heavy","piercing"],
		"desc": "High damage, loud. Breaks armor: target -4 detect for 8s after kill.",
		"color": Color(0.70, 0.55, 0.30),
	},
	"SPEAR": {
		"name": "Boar Spear", "class": "", "tier": 2,
		"tags": ["heavy","piercing"],
		"desc": "Long thrust: hits 2 tiles ahead. Guards in a line take full damage.",
		"color": Color(0.72, 0.60, 0.35),
	},
	"WAND": {
		"name": "Wand of Force", "class": "", "tier": 2,
		"tags": ["ranged","cursed"],
		"desc": "Fires a slow magical orb. Silent but unpredictable. 5 charges per floor.",
		"color": Color(0.55, 0.30, 0.95),
	},
	"NONE": {
		"name": "Unarmed", "class": "", "tier": 0,
		"tags": [],
		"desc": "No weapon equipped. Fists are slower and louder.",
		"color": Color(0.45, 0.45, 0.45),
	},
}

# Combat stats: shape, damage, cooldown, noise radius
# shapes: jab | slash | thrust | bolt | orb
const COMBAT: Dictionary = {
	"NONE":               {"shape": "jab",    "damage": 1, "cooldown": 0.55, "noise_r":  60.0},
	"SHIV":               {"shape": "jab",    "damage": 1, "cooldown": 0.28, "noise_r":   0.0},
	"STILETTO":           {"shape": "jab",    "damage": 1, "cooldown": 0.25, "noise_r":   0.0},
	"ASSASSIN_FANG":      {"shape": "jab",    "damage": 2, "cooldown": 0.22, "noise_r":   0.0},
	"SHADOW_BLADE":       {"shape": "slash",  "damage": 2, "cooldown": 0.40, "noise_r":   0.0},
	"GHOST_BLADE":        {"shape": "slash",  "damage": 2, "cooldown": 0.38, "noise_r":   0.0},
	"VOID_REAPER":        {"shape": "slash",  "damage": 2, "cooldown": 0.36, "noise_r":   0.0},
	"CROSSBOW":           {"shape": "bolt",   "damage": 2, "cooldown": 1.20, "noise_r": 140.0},
	"REPEATING_CROSSBOW": {"shape": "bolt",   "damage": 1, "cooldown": 0.65, "noise_r": 120.0},
	"SILENT_BOLT":        {"shape": "bolt",   "damage": 1, "cooldown": 0.80, "noise_r":   0.0},
	"GARROTE":            {"shape": "jab",    "damage": 2, "cooldown": 0.60, "noise_r":   0.0},
	"VENOM_NEEDLE":       {"shape": "bolt",   "damage": 2, "cooldown": 0.50, "noise_r":   0.0},
	"RUNED_BLADE":        {"shape": "slash",  "damage": 2, "cooldown": 0.42, "noise_r":  60.0},
	"SMOKE_BLADE":        {"shape": "slash",  "damage": 1, "cooldown": 0.40, "noise_r":   0.0},
	"WAR_PICK":           {"shape": "slash",  "damage": 2, "cooldown": 0.55, "noise_r": 140.0},
	"LONGSWORD":          {"shape": "slash",  "damage": 2, "cooldown": 0.45, "noise_r":  80.0},
	"BROADSWORD":         {"shape": "slash",  "damage": 3, "cooldown": 0.52, "noise_r": 100.0},
	"BLADESONG":          {"shape": "slash",  "damage": 3, "cooldown": 0.48, "noise_r":  40.0},
	"SPEAR":              {"shape": "thrust", "damage": 2, "cooldown": 0.60, "noise_r":  80.0},
	"WAND":               {"shape": "orb",    "damage": 2, "cooldown": 0.80, "noise_r":   0.0},
}

const CLASS_STARTING: Dictionary = {
	"CUTPURSE":     "SHIV",
	"SHADOWDANCER": "SHADOW_BLADE",
	"ASSASSIN":     "CROSSBOW",
	"SELLSWORD":    "LONGSWORD",
}

const UPGRADES: Dictionary = {
	"SHIV":               "STILETTO",
	"STILETTO":           "ASSASSIN_FANG",
	"SHADOW_BLADE":       "GHOST_BLADE",
	"GHOST_BLADE":        "VOID_REAPER",
	"CROSSBOW":           "REPEATING_CROSSBOW",
	"REPEATING_CROSSBOW": "SILENT_BOLT",
	"WAR_PICK":           "RUNED_BLADE",
	"LONGSWORD":          "BROADSWORD",
	"BROADSWORD":         "BLADESONG",
}

const FLOOR_DROP_POOL: Dictionary = {
	1: ["GARROTE", "WAR_PICK", "SPEAR"],
	2: ["GARROTE", "VENOM_NEEDLE", "SMOKE_BLADE", "WAR_PICK", "SPEAR"],
	3: ["VENOM_NEEDLE", "SMOKE_BLADE", "RUNED_BLADE", "WAND"],
	4: ["RUNED_BLADE", "SMOKE_BLADE", "WAND"],
	5: ["RUNED_BLADE", "WAND"],
}

static func fetch(weapon_id: String) -> Dictionary:
	return WEAPONS.get(weapon_id, WEAPONS["NONE"])

static func get_combat(weapon_id: String) -> Dictionary:
	return COMBAT.get(weapon_id, COMBAT["NONE"])

static func get_upgrade(weapon_id: String) -> String:
	return UPGRADES.get(weapon_id, "")

static func has_tag(weapon_id: String, tag: String) -> bool:
	return tag in WEAPONS.get(weapon_id, {}).get("tags", [])

static func get_floor_drops(floor_num: int, count: int = 1) -> Array:
	var pool: Array = FLOOR_DROP_POOL.get(floor_num, ["GARROTE"])
	var shuffled: Array = pool.duplicate()
	shuffled.shuffle()
	var result: Array = []
	for i in range(mini(count, shuffled.size())):
		result.append(shuffled[i])
	return result
