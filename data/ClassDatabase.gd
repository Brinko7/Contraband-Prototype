extends Node
# Canonical definitions for all playable classes, races, passives, and gear sets.

const CLASSES: Dictionary = {
	"CUTPURSE": {
		"title":   "Cutpurse",
		"items":   [{"type": 0, "count": 4}, {"type": 1, "count": 1}],
		"passive": "Walking is quiet. Coin range +50%. First item per floor is free (Sleight of Hand).",
		"flavor":  "Gold has a way of finding my pockets.",
		"color":   Color(0.95, 0.78, 0.15),
		"stat_bonuses": {"dex": 2, "str": 0, "int": 1},
		"hp_base": 6,
	},
	"SHADOWDANCER": {
		"title":   "Shadowdancer",
		"items":   [{"type": 1, "count": 2}, {"type": 3, "count": 1}],
		"passive": "Sneak takedowns are silent — 2 per floor. Third attempt wakes a nearby guard.",
		"flavor":  "Strike from where the light cannot follow.",
		"color":   Color(0.55, 0.30, 0.95),
		"stat_bonuses": {"dex": 3, "str": 0, "int": 0},
		"hp_base": 5,
	},
	"ASSASSIN": {
		"title":   "Assassin",
		"items":   [{"type": 2, "count": 2}, {"type": 0, "count": 2}],
		"passive": "d20 ≥ 6 succeeds. Misses on 4+. Frontal kills earn +120 gp. Mark: auto-execute.",
		"flavor":  "Every guard a contract. Every contract fulfilled.",
		"color":   Color(0.85, 0.15, 0.15),
		"stat_bonuses": {"dex": 1, "str": 1, "int": 1},
		"hp_base": 6,
	},
	"SELLSWORD": {
		"title":   "Sellsword",
		"items":   [{"type": 0, "count": 2}],
		"passive": "Loud kills earn +80 gp. Battle Shout: next hit deals double. Takes 1 less damage.",
		"flavor":  "Subtlety is for people who haven't tried hitting harder.",
		"color":   Color(0.80, 0.55, 0.20),
		"stat_bonuses": {"dex": 0, "str": 3, "int": 0},
		"hp_base": 8,
	},
}

const RACES: Dictionary = {
	"HALFLING": {
		"title":        "Halfling",
		"passive_id":   "HALFLING_LUCKY",
		"passive":      "Lucky — reroll any Nat 1. Guards detect you 20% slower.",
		"ability_name": "Lucky Break",
		"ability_desc": "Once per floor, negate one alert for free.",
		"flavor":       "The safest hands in the guild belong to the smallest thief.",
		"color":        Color(0.85, 0.68, 0.30),
		"skin":         Color(0.88, 0.72, 0.55),
		"stat_bonuses": {"dex": 1, "detect_mult": 0.80},
	},
	"TIEFLING": {
		"title":        "Tiefling",
		"passive_id":   "TIEFLING_DARKVISION",
		"passive":      "Darkvision — torches don't affect your vision range. Hellish aura intimidates.",
		"ability_name": "Hellish Rebuke",
		"ability_desc": "When caught in vision, vanish from all detection bars instantly.",
		"flavor":       "They fear what hides in the dark. I am what hides in the dark.",
		"color":        Color(0.70, 0.20, 0.85),
		"skin":         Color(0.40, 0.18, 0.55),
		"stat_bonuses": {"int": 1, "darkvision": true},
	},
	"WOOD_ELF": {
		"title":        "Wood Elf",
		"passive_id":   "ELF_TREAD",
		"passive":      "Elven Tread — movement is always silent. Immune to Gnoll scent.",
		"ability_name": "Vanish",
		"ability_desc": "Become invisible to all guards for 3 seconds.",
		"flavor":       "A ghost in the underbrush. A whisper in the vault.",
		"color":        Color(0.25, 0.75, 0.35),
		"skin":         Color(0.75, 0.85, 0.65),
		"stat_bonuses": {"dex": 2, "silent_move": true},
	},
	"DWARF": {
		"title":        "Dwarf",
		"passive_id":   "DWARF_IRON_WILL",
		"passive":      "Iron Will — one failed takedown per run becomes a graze. Stonecunning: see traps.",
		"ability_name": "Battle Cry",
		"ability_desc": "Stun all adjacent guards for 2 seconds.",
		"flavor":       "Aye, subtle as a cave-in. And twice as effective.",
		"color":        Color(0.75, 0.55, 0.25),
		"skin":         Color(0.70, 0.52, 0.38),
		"stat_bonuses": {"str": 1, "con": 2, "trap_sight": true},
	},
}

const RACE_ORDER: Array = ["HALFLING", "TIEFLING", "WOOD_ELF", "DWARF"]

const PASSIVES: Array = [
	{"id": "SOFT_BOOTS",    "name": "Soft Boots",      "desc": "Walking always counts as quiet movement.",       "color": Color(0.60, 0.85, 0.95), "tier": 1},
	{"id": "GHOST_STEP",    "name": "Ghost Step",      "desc": "Sneaking produces absolutely no noise.",         "color": Color(0.70, 0.90, 1.00), "tier": 2},
	{"id": "IRON_NERVES",   "name": "Iron Nerves",     "desc": "+2 bonus to all d20 rolls.",                     "color": Color(0.95, 0.75, 0.20), "tier": 1},
	{"id": "PICKPOCKET",    "name": "Pickpocket",      "desc": "Each takedown yields +35 gp.",                   "color": Color(0.95, 0.80, 0.10), "tier": 1},
	{"id": "QUICK_HANDS",   "name": "Quick Hands",     "desc": "Movement cooldown reduced by 20%.",              "color": Color(0.95, 0.55, 0.20), "tier": 1},
	{"id": "DARK_SHROUD",   "name": "Dark Shroud",     "desc": "Guards detect you 30% slower while sneaking.",   "color": Color(0.45, 0.30, 0.75), "tier": 2},
	{"id": "ASSASSINS_EYE", "name": "Assassin's Eye",  "desc": "Frontal d20 takedowns succeed on 10+.",          "color": Color(0.85, 0.15, 0.15), "tier": 2},
	{"id": "FENCE_CONTACT", "name": "Fence Contact",   "desc": "Shop items cost 20% less.",                      "color": Color(0.95, 0.80, 0.40), "tier": 1},
	{"id": "SECOND_WIND",   "name": "Second Wind",     "desc": "First failed takedown per floor becomes a graze.", "color": Color(0.30, 0.80, 0.55), "tier": 2},
	{"id": "SHADOW_CLOAK",  "name": "Shadow Cloak",    "desc": "Hiding in a barrel also silences all noise.",    "color": Color(0.35, 0.25, 0.60), "tier": 1},
	{"id": "DEAD_WEIGHT",   "name": "Dead Weight",     "desc": "Carrying bodies doesn't slow your movement.",    "color": Color(0.55, 0.55, 0.55), "tier": 1},
	{"id": "COLD_BLOOD",    "name": "Cold Blood",      "desc": "Class ability cooldowns reduced by 30%.",        "color": Color(0.30, 0.75, 0.90), "tier": 2},
	{"id": "LOCKSMITH",     "name": "Locksmith",       "desc": "Smoke grenades last 50% longer.",                "color": Color(0.45, 0.85, 0.55), "tier": 1},
	{"id": "INSURANCE",     "name": "Insurance",       "desc": "One alert per floor costs no escalation.",       "color": Color(0.85, 0.70, 0.30), "tier": 2},
	{"id": "SCAVENGER",     "name": "Scavenger",       "desc": "Floor item pickups give 1 extra item.",          "color": Color(0.70, 0.55, 0.35), "tier": 1},
	{"id": "SHADOW_VEIL",   "name": "Shadow Veil",     "desc": "Entering any shadow tile resets your detection bar.", "color": Color(0.40, 0.20, 0.70), "tier": 3},
	{"id": "OPPORTUNIST",   "name": "Opportunist",     "desc": "Flanking enemies (from the side) grants +3 to d20.", "color": Color(0.75, 0.85, 0.35), "tier": 2},
	{"id": "NERVE_STEEL",   "name": "Nerve of Steel",  "desc": "Your first hit each floor always crits (max damage).", "color": Color(0.90, 0.30, 0.20), "tier": 3},
]

const GEAR: Dictionary = {
	# ── Boots ─────────────────────────────────────────────────────────────────
	"LEATHER_BOOTS":    { "slot": "boots",   "name": "Soft Leather Boots",  "cost": 55,
		"desc": "Movement noise -25%.",     "set": "thief",
		"tags": ["stealth"], "effect": "QUIET_BOOTS", "color": Color(0.65, 0.48, 0.28), "rarity": 0 },
	"SHADOWSTEP_BOOTS": { "slot": "boots",   "name": "Shadowstep Boots",    "cost": 120,
		"desc": "Sneaking is always perfectly silent.", "set": "shadow",
		"tags": ["stealth","shadow"], "effect": "GHOST_BOOTS", "color": Color(0.35, 0.25, 0.60), "rarity": 1 },
	"IRONSHOD_BOOTS":   { "slot": "boots",   "name": "Ironshod Boots",      "cost": 70,
		"desc": "Glass tiles don't shatter. -1 on all stealth rolls.", "set": "iron",
		"tags": ["heavy"], "effect": "GLASS_IMMUNE", "color": Color(0.55, 0.55, 0.60), "rarity": 0 },
	"SWIFT_SLIPPERS":   { "slot": "boots",   "name": "Swift Slippers",      "cost": 85,
		"desc": "Movement cooldown -15%. Sneak speed equals walk speed.", "set": "thief",
		"tags": ["stealth"], "effect": "FAST_SNEAK", "color": Color(0.65, 0.78, 0.55), "rarity": 1 },
	# ── Cloaks ────────────────────────────────────────────────────────────────
	"SHADOW_CLOAK":     { "slot": "cloak",   "name": "Shadow Cloak",        "cost": 90,
		"desc": "Detection rate -30% while sneaking.",   "set": "shadow",
		"tags": ["stealth","shadow"], "effect": "SLOW_DETECT_SNEAK", "color": Color(0.30, 0.20, 0.55), "rarity": 1 },
	"SILK_MANTLE":      { "slot": "cloak",   "name": "Silk Mantle",         "cost": 65,
		"desc": "Walking noise counts as quiet.",        "set": "thief",
		"tags": ["stealth"], "effect": "SOFT_WALK", "color": Color(0.55, 0.45, 0.75), "rarity": 0 },
	"DUSTCLOAK":        { "slot": "cloak",   "name": "Dustcloak",           "cost": 80,
		"desc": "After hiding, detection resets 2× faster when you move.", "set": "shadow",
		"tags": ["stealth","shadow"], "effect": "FAST_RESET", "color": Color(0.40, 0.32, 0.22), "rarity": 1 },
	"WARDED_MANTLE":    { "slot": "cloak",   "name": "Warded Mantle",       "cost": 105,
		"desc": "First magic trap/ward each floor deals no penalty.", "set": "iron",
		"tags": ["heavy","magic"], "effect": "WARD_RESIST", "color": Color(0.35, 0.50, 0.70), "rarity": 2 },
	"ASSASSIN_SHROUD":  { "slot": "cloak",   "name": "Assassin's Shroud",   "cost": 110,
		"desc": "After a kill, you are invisible for 2 seconds.", "set": "shadow",
		"tags": ["shadow","stealth"], "effect": "KILL_VANISH", "color": Color(0.20, 0.15, 0.40), "rarity": 2 },
	# ── Off-hand ──────────────────────────────────────────────────────────────
	"PARRYING_DAGGER":  { "slot": "offhand", "name": "Parrying Dagger",     "cost": 85,
		"desc": "Failed takedowns become grazes. Shadowdancer: +1 silent strike/floor.", "set": "thief",
		"tags": ["piercing","silent"], "effect": "PARRY", "color": Color(0.70, 0.70, 0.78), "rarity": 1 },
	"SMOKE_CANISTER":   { "slot": "offhand", "name": "Smoke Canister",      "cost": 95,
		"desc": "Smoke bombs last 60% longer. Active: instant mini-smoke (1 use).", "set": "shadow",
		"tags": ["stealth","utility"], "effect": "EXTENDED_SMOKE", "color": Color(0.42, 0.58, 0.42), "rarity": 1 },
	"LOCKPICK_KIT":     { "slot": "offhand", "name": "Lockpick Kit",        "cost": 75,
		"desc": "No item needed for doors/chests. +4 to all lock/trap d20 checks.", "set": "thief",
		"tags": ["utility"], "effect": "LOCKPICK", "color": Color(0.70, 0.55, 0.28), "rarity": 1 },
	"THROWING_KNIVES":  { "slot": "offhand", "name": "Throwing Knives",     "cost": 80,
		"desc": "3 silent throws per floor. 100px range. Doesn't kill — stuns for 3s.", "set": "thief",
		"tags": ["throwable","silent"], "effect": "THROW_STUN", "color": Color(0.72, 0.72, 0.80), "rarity": 1 },
	# ── Trinkets ──────────────────────────────────────────────────────────────
	"THIEVES_TOOLS":    { "slot": "trinket", "name": "Thieves' Tools",      "cost": 100,
		"desc": "Disarm traps and wards silently without using an item.",  "set": "thief",
		"tags": ["utility","stealth"], "effect": "DISARM_TOOL", "color": Color(0.70, 0.55, 0.28), "rarity": 1 },
	"DEADWEIGHT_HARNESS":{ "slot": "trinket","name": "Deadweight Harness",  "cost": 80,
		"desc": "Carrying bodies doesn't slow movement.",  "set": "iron",
		"tags": ["heavy"], "effect": "BODY_CARRY", "color": Color(0.50, 0.50, 0.50), "rarity": 0 },
	"QUICKSILVER_FLASK":{ "slot": "trinket", "name": "Quicksilver Flask",   "cost": 110,
		"desc": "8s movement speed boost, once per floor.",  "set": "shadow",
		"tags": ["stealth","utility"], "effect": "SPEED_BURST", "color": Color(0.55, 0.85, 0.95), "rarity": 1 },
	"BLOOD_VIAL":       { "slot": "trinket", "name": "Blood Vial",          "cost": 90,
		"desc": "Heals bleeding on use. Passively: bleeding deals half noise.", "set": "iron",
		"tags": ["utility","heavy"], "effect": "BLEED_RESIST", "color": Color(0.80, 0.25, 0.25), "rarity": 1 },
	"SHADOWGLASS":      { "slot": "trinket", "name": "Shadowglass Lens",    "cost": 130,
		"desc": "See guard patrol paths as faint trails. +1 to all stealth rolls.", "set": "shadow",
		"tags": ["stealth","shadow"], "effect": "PATROL_SIGHT", "color": Color(0.25, 0.55, 0.85), "rarity": 2 },
	"THIEVES_MARK":     { "slot": "trinket", "name": "Thief's Mark",        "cost": 95,
		"desc": "Tag a guard — their patrol schedule is revealed on the minimap.", "set": "thief",
		"tags": ["utility","stealth"], "effect": "MARK_GUARD", "color": Color(0.95, 0.70, 0.20), "rarity": 1 },
}

const SET_BONUSES: Dictionary = {
	"shadow": {
		"name": "Shadow Sovereign",
		"desc": "Breaking line-of-sight resets detection bar instantly.",
		"effect": "SET_SHADOW",
		"color": Color(0.55, 0.25, 0.90),
	},
	"thief": {
		"name": "Master Thief",
		"desc": "All d20 rolls gain +3. Walking noise eliminated while sneaking.",
		"effect": "SET_THIEF",
		"color": Color(0.90, 0.75, 0.20),
	},
	"iron": {
		"name": "Iron Resolve",
		"desc": "Body discovery window +6s. Failed takedowns never trigger alert (once/floor).",
		"effect": "SET_IRON",
		"color": Color(0.65, 0.65, 0.70),
	},
}

static func get_class_data(class_id: String) -> Dictionary:
	return CLASSES.get(class_id, CLASSES["CUTPURSE"])

static func get_race(race_id: String) -> Dictionary:
	return RACES.get(race_id, RACES["HALFLING"])

static func get_passive(passive_id: String) -> Dictionary:
	for p in PASSIVES:
		if p.id == passive_id:
			return p
	return {}

static func get_gear(gear_id: String) -> Dictionary:
	return GEAR.get(gear_id, {})

static func get_set_bonus(gear_dict: Dictionary, weapon_id: String) -> String:
	var counts: Dictionary = {"shadow": 0, "thief": 0, "iron": 0}
	for slot in gear_dict:
		var gid: String = gear_dict[slot]
		if not gid.is_empty():
			var s: String = GEAR.get(gid, {}).get("set", "")
			if s in counts:
				counts[s] += 1
	var wtags: Array = WeaponDatabase.WEAPONS.get(weapon_id, {}).get("tags", [])
	if "shadow" in wtags: counts["shadow"] += 1
	if "piercing" in wtags or "silent" in wtags: counts["thief"] += 1
	for s in counts:
		if counts[s] >= 3:
			return SET_BONUSES[s].get("effect", "")
	return ""

static func get_gear_for_slot(slot: String) -> Array:
	var result: Array = []
	for gid in GEAR:
		if GEAR[gid].get("slot", "") == slot:
			result.append(gid)
	return result
