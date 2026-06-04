extends Node
# ── Contraband V7 Loot System ─────────────────────────────────────────────────
# Mature, categorized loot with rarity, named items, body-looting, and stashes.

enum Category { CONSUMABLE, VALUABLE, DOCUMENT, EQUIPMENT, RELIC }
enum Rarity { JUNK, COMMON, UNCOMMON, RARE, LEGENDARY }

const RARITY_NAMES: Dictionary = {
	Rarity.JUNK:      "Junk",
	Rarity.COMMON:    "Common",
	Rarity.UNCOMMON:  "Uncommon",
	Rarity.RARE:      "Rare",
	Rarity.LEGENDARY: "Legendary",
}

const RARITY_COLORS: Dictionary = {
	Rarity.JUNK:      Color(0.55, 0.52, 0.50),
	Rarity.COMMON:    Color(0.88, 0.85, 0.80),
	Rarity.UNCOMMON:  Color(0.28, 0.82, 0.45),
	Rarity.RARE:      Color(0.28, 0.55, 1.00),
	Rarity.LEGENDARY: Color(0.95, 0.68, 0.10),
}

# Every item in the game — id → data
const ITEMS: Dictionary = {
	# ── Consumables ────────────────────────────────────────────────────────────
	"GOLD_PIECE":       { "name": "Gold Piece",         "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 1,   "weight": 0.1, "desc": "Clinking gold. The universal language.", "color": Color(0.95, 0.80, 0.10) },
	"SMOKE_BOMB":       { "name": "Smoke Bomb",          "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 20,  "weight": 0.3, "desc": "Releases a blinding cloud on impact.", "color": Color(0.55, 0.90, 0.45) },
	"SOPORIFIC_DART":   { "name": "Soporific Dart",      "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 40,  "weight": 0.1, "desc": "One prick and it's lights out. Silently.", "color": Color(0.30, 0.70, 0.95) },
	"SILK_ROPE":        { "name": "Silk Rope",            "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 25,  "weight": 0.5, "desc": "A length of strong, near-silent rope.", "color": Color(0.75, 0.55, 0.95) },
	"FLASH_POWDER":     { "name": "Flash Powder",         "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 35,  "weight": 0.2, "desc": "Blinds and disorients nearby guards.", "color": Color(1.00, 0.95, 0.70) },
	"HOLD_SCROLL":      { "name": "Hold Person Scroll",   "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 55,  "weight": 0.2, "desc": "Freezes a target in place for 4 seconds.", "color": Color(0.55, 0.35, 0.90) },
	"SILENCE_SCROLL":   { "name": "Silence Scroll",       "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 50,  "weight": 0.2, "desc": "Creates a zone of magical silence.", "color": Color(0.30, 0.20, 0.55) },
	"THIEVES_TOOLS":    { "name": "Thieves' Tools",       "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 30,  "weight": 0.4, "desc": "+5 to next lockpick attempt. Also identifies magic items.", "color": Color(0.70, 0.55, 0.30) },
	"SHADOW_OIL":       { "name": "Shadow Cloak Oil",     "cat": Category.CONSUMABLE, "rar": Rarity.RARE,      "value": 90,  "weight": 0.3, "desc": "Anointing yourself reduces guard vision by 20 for 60s.", "color": Color(0.20, 0.15, 0.35) },
	"HEALING_SALVE":    { "name": "Healing Salve",        "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 65,  "weight": 0.3, "desc": "Restores 1 HP. Smells faintly of pine resin.", "color": Color(0.28, 0.72, 0.38) },
	"ANTITOXIN":        { "name": "Antitoxin Vial",       "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 50,  "weight": 0.2, "desc": "Clears bleeding and limping status.", "color": Color(0.45, 0.88, 0.65) },
	"STIM_POWDER":      { "name": "Stim Powder",          "cat": Category.CONSUMABLE, "rar": Rarity.RARE,      "value": 80,  "weight": 0.1, "desc": "A single sniff gives 8 seconds of doubled movement speed.", "color": Color(0.88, 0.55, 0.92) },
	"MARKED_COIN":      { "name": "Marked Coin",          "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 10,  "weight": 0.1, "desc": "A weighted coin — makes noise on landing. Useful distraction.", "color": Color(0.75, 0.65, 0.25) },
	# ── Valuables ──────────────────────────────────────────────────────────────
	"RUBY":             { "name": "Rough Ruby",           "cat": Category.VALUABLE,   "rar": Rarity.RARE,      "value": 320, "weight": 0.1, "desc": "A blood-red gemstone from the southern mines.", "color": Color(0.92, 0.15, 0.18) },
	"SAPPHIRE":         { "name": "Polished Sapphire",    "cat": Category.VALUABLE,   "rar": Rarity.RARE,      "value": 280, "weight": 0.1, "desc": "Deep blue, clear as winter sky.", "color": Color(0.18, 0.35, 0.98) },
	"EMERALD":          { "name": "Emerald Fragment",     "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 180, "weight": 0.1, "desc": "A cracked but valuable green stone.", "color": Color(0.12, 0.82, 0.35) },
	"PEARL":            { "name": "Sea Pearl",            "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 150, "weight": 0.1, "desc": "Lustrous and perfectly round. Merchant-grade.", "color": Color(0.92, 0.90, 0.88) },
	"GOLD_RING":        { "name": "Gold Signet Ring",     "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 220, "weight": 0.2, "desc": "A family crest ring. The fence won't ask questions.", "color": Color(0.92, 0.78, 0.18) },
	"SILVER_NECKLACE":  { "name": "Silver Necklace",      "cat": Category.VALUABLE,   "rar": Rarity.COMMON,    "value": 95,  "weight": 0.2, "desc": "Fine silverwork. Probably shouldn't be here.", "color": Color(0.80, 0.80, 0.88) },
	"ANCIENT_COIN":     { "name": "Ancient Gold Coin",    "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 130, "weight": 0.1, "desc": "Minted before the Compact. Collectors pay well.", "color": Color(0.88, 0.70, 0.22) },
	"SILVER_CHALICE":   { "name": "Silver Chalice",       "cat": Category.VALUABLE,   "rar": Rarity.COMMON,    "value": 110, "weight": 0.8, "desc": "Heavy and tarnished. Still worth good coin.", "color": Color(0.72, 0.72, 0.80) },
	"NOBLE_BROOCH":     { "name": "Noble's Brooch",       "cat": Category.VALUABLE,   "rar": Rarity.RARE,      "value": 380, "weight": 0.2, "desc": "Encrusted with small gems. Clearly expensive.", "color": Color(0.82, 0.62, 0.88) },
	"IVORY_FIGURINE":   { "name": "Ivory Figurine",       "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 200, "weight": 0.4, "desc": "A carved deity statuette. Sacred? Profitable.", "color": Color(0.92, 0.88, 0.80) },
	"VOID_CRYSTAL":     { "name": "Void Crystal Shard",   "cat": Category.VALUABLE,   "rar": Rarity.LEGENDARY, "value": 850, "weight": 0.2, "desc": "Hums with barely-contained shadow energy.", "color": Color(0.30, 0.12, 0.55) },
	# ── Documents ──────────────────────────────────────────────────────────────
	"PATROL_SCHEDULE":  { "name": "Patrol Schedule",      "cat": Category.DOCUMENT,   "rar": Rarity.UNCOMMON,  "value": 80,  "weight": 0.1, "desc": "READ: Reveals all patrol routes on this floor.", "color": Color(0.82, 0.72, 0.42) },
	"VAULT_MANIFEST":   { "name": "Vault Manifest",       "cat": Category.DOCUMENT,   "rar": Rarity.RARE,      "value": 120, "weight": 0.1, "desc": "READ: Marks the exact location of the primary objective.", "color": Color(0.78, 0.68, 0.38) },
	"ARREST_WARRANT":   { "name": "Arrest Warrant",       "cat": Category.DOCUMENT,   "rar": Rarity.RARE,      "value": 200, "weight": 0.1, "desc": "A warrant for your arrest, signed in triplicate. Ironic to fence.", "color": Color(0.88, 0.35, 0.25) },
	"BRIBE_LEDGER":     { "name": "Bribe Ledger",         "cat": Category.DOCUMENT,   "rar": Rarity.LEGENDARY, "value": 600, "weight": 0.2, "desc": "Names, amounts, dates. The guild pays a fortune for this.", "color": Color(0.62, 0.78, 0.35) },
	"FORGED_PAPERS":    { "name": "Forged Papers",        "cat": Category.DOCUMENT,   "rar": Rarity.COMMON,    "value": 60,  "weight": 0.1, "desc": "Passable forgeries. Reduce wanted level by 1 if used at the exit.", "color": Color(0.75, 0.72, 0.58) },
	# ── Equipment (worn gear upgrades) ─────────────────────────────────────────
	"WEIGHTED_GLOVES":  { "name": "Weighted Gloves",      "cat": Category.EQUIPMENT,  "rar": Rarity.UNCOMMON,  "value": 140, "weight": 0.5, "desc": "+1 melee damage. Knuckles dusted with iron shavings.", "color": Color(0.55, 0.42, 0.28) },
	"LOCKPICK_SET_ADV": { "name": "Expert Lockpick Set",  "cat": Category.EQUIPMENT,  "rar": Rarity.RARE,      "value": 220, "weight": 0.4, "desc": "+8 to all lockpick rolls. Crafted by a guild master.", "color": Color(0.65, 0.65, 0.72) },
	"DARK_LENS":        { "name": "Dark-Vision Lens",     "cat": Category.EQUIPMENT,  "rar": Rarity.RARE,      "value": 300, "weight": 0.3, "desc": "A single monocle that pierces magical darkness.", "color": Color(0.28, 0.38, 0.55) },
	# ── Relics (unique magical items) ──────────────────────────────────────────
	"RING_BLINKING":    { "name": "Ring of Blinking",     "cat": Category.RELIC,      "rar": Rarity.LEGENDARY, "value": 1200,"weight": 0.1, "desc": "Short-range teleport to a random adjacent tile (10s cooldown).", "color": Color(0.55, 0.88, 0.95) },
	"CLOAK_MISTS":      { "name": "Cloak of Mists",       "cat": Category.RELIC,      "rar": Rarity.LEGENDARY, "value": 900, "weight": 0.8, "desc": "On taking damage, unleash a blinding mist cloud.", "color": Color(0.62, 0.72, 0.88) },
	"BOOTS_SILENCE":    { "name": "Boots of Silence",     "cat": Category.RELIC,      "rar": Rarity.RARE,      "value": 550, "weight": 0.6, "desc": "Movement is always completely silent.", "color": Color(0.28, 0.22, 0.45) },
	"THIEVES_LANTERN":  { "name": "Thief's Lantern",      "cat": Category.RELIC,      "rar": Rarity.UNCOMMON,  "value": 180, "weight": 0.6, "desc": "A shielded lantern. Reveals nearby hidden traps.", "color": Color(0.92, 0.78, 0.25) },
}

# ── Loot tables per zone/floor ────────────────────────────────────────────────
# Each entry: [ item_id, weight ]  (higher weight = more likely)
const LOOT_TABLES: Dictionary = {
	"floor1_common":  [
		["GOLD_PIECE", 30], ["SMOKE_BOMB", 15], ["SOPORIFIC_DART", 10],
		["MARKED_COIN", 20], ["SILVER_NECKLACE", 12], ["ANCIENT_COIN", 8],
		["FORGED_PAPERS", 10], ["PATROL_SCHEDULE", 5],
	],
	"floor1_rare":    [
		["GOLD_RING", 20], ["IVORY_FIGURINE", 15], ["RUBY", 8],
		["HEALING_SALVE", 18], ["ANTITOXIN", 12], ["LOCKPICK_SET_ADV", 10],
		["THIEVES_LANTERN", 8], ["PATROL_SCHEDULE", 15], ["VAULT_MANIFEST", 5],
	],
	"floor2_common":  [
		["GOLD_PIECE", 20], ["SMOKE_BOMB", 12], ["SOPORIFIC_DART", 12],
		["SILK_ROPE", 10], ["FLASH_POWDER", 10], ["SILVER_CHALICE", 14],
		["ANCIENT_COIN", 10], ["FORGED_PAPERS", 8], ["PATROL_SCHEDULE", 8],
	],
	"floor2_rare":    [
		["EMERALD", 18], ["SAPPHIRE", 12], ["GOLD_RING", 15],
		["HEALING_SALVE", 12], ["STIM_POWDER", 10], ["WEIGHTED_GLOVES", 8],
		["DARK_LENS", 6], ["VAULT_MANIFEST", 10], ["ARREST_WARRANT", 6],
	],
	"floor3_common":  [
		["GOLD_PIECE", 15], ["SOPORIFIC_DART", 15], ["HOLD_SCROLL", 12],
		["SHADOW_OIL", 10], ["SILENCE_SCROLL", 10], ["SILVER_CHALICE", 10],
		["EMERALD", 8], ["ARREST_WARRANT", 8], ["BRIBE_LEDGER", 4],
	],
	"floor3_rare":    [
		["RUBY", 18], ["SAPPHIRE", 14], ["NOBLE_BROOCH", 12],
		["VOID_CRYSTAL", 8], ["RING_BLINKING", 5], ["CLOAK_MISTS", 4],
		["BOOTS_SILENCE", 8], ["BRIBE_LEDGER", 10], ["VAULT_MANIFEST", 8],
	],
	"guard_body":     [
		["GOLD_PIECE", 40], ["MARKED_COIN", 20], ["SOPORIFIC_DART", 12],
		["ANCIENT_COIN", 12], ["FORGED_PAPERS", 8], ["THIEVES_TOOLS", 8],
	],
	"captain_body":   [
		["ANCIENT_COIN", 25], ["GOLD_RING", 20], ["PATROL_SCHEDULE", 18],
		["HEALING_SALVE", 15], ["VAULT_MANIFEST", 10], ["RUBY", 8],
	],
}

# ── Named loot per floor (for the primary vault objective) ────────────────────
const FLOOR_NAMED_LOOT: Dictionary = {
	1: [
		{"name": "The Merchant's Coffer",     "desc": "A locked iron box. Heavy."},
		{"name": "The Alderman's Seal",        "desc": "A golden seal-ring of office."},
		{"name": "Lady Vex's Jewel Box",       "desc": "Sapphires, emeralds, scandal."},
		{"name": "The Tax Assessor's Ledger",  "desc": "Every bribe in the district."},
	],
	2: [
		{"name": "The Commander's War Chest",  "desc": "Military gold. Unguarded no more."},
		{"name": "The Captain's Key Ring",     "desc": "Unlocks every door in the barracks."},
		{"name": "The Armory Master's Vault",  "desc": "Rare weapons, cached for war."},
		{"name": "The Informant's Dossier",    "desc": "Names, dates, dead drops."},
	],
	3: [
		{"name": "The Arcane Reliquary",       "desc": "A sealed container of void shards."},
		{"name": "The Guildmaster's Ransom",   "desc": "Your mark's life savings. Take them."},
		{"name": "The Crown Jewels",           "desc": "Stolen once before. Steal them again."},
		{"name": "The Heretic's Testament",    "desc": "A treaty that would topple a dynasty."},
	],
}

# ── Static helpers ────────────────────────────────────────────────────────────
static func roll_from_table(table_id: String, rng: RandomNumberGenerator) -> String:
	var table: Array = LOOT_TABLES.get(table_id, [])
	if table.is_empty():
		return "GOLD_PIECE"
	var total_weight := 0
	for entry in table:
		total_weight += entry[1]
	var roll := rng.randi_range(0, total_weight - 1)
	var cumulative := 0
	for entry in table:
		cumulative += entry[1]
		if roll < cumulative:
			return entry[0]
	return table[0][0]

static func get_table_for_floor(floor_n: int, is_rare: bool) -> String:
	var f := clampi(floor_n, 1, 3)
	return "floor%d_%s" % [f, "rare" if is_rare else "common"]

static func get_item(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {"name": item_id, "value": 50, "weight": 0.5,
		"cat": Category.VALUABLE, "rar": Rarity.COMMON,
		"desc": "Unknown item.", "color": Color(0.75, 0.72, 0.65)})

static func get_rarity_color(item_id: String) -> Color:
	var data: Dictionary = ITEMS.get(item_id, {})
	return RARITY_COLORS.get(data.get("rar", Rarity.COMMON), Color(0.88, 0.85, 0.80))

static func get_item_value(item_id: String, floor_n: int) -> int:
	var data: Dictionary = ITEMS.get(item_id, {})
	var base: int = data.get("value", 50)
	# Rarity multiplier
	var rar: int = data.get("rar", Rarity.COMMON)
	var mults: Dictionary = {Rarity.JUNK: 0.6, Rarity.COMMON: 1.0, Rarity.UNCOMMON: 1.5,
		Rarity.RARE: 2.2, Rarity.LEGENDARY: 4.0}
	# Floor depth bonus
	return int(base * mults.get(rar, 1.0) * (1.0 + (floor_n - 1) * 0.25))

static func get_random_named_loot(floor_n: int, rng: RandomNumberGenerator) -> Dictionary:
	var options: Array = FLOOR_NAMED_LOOT.get(clampi(floor_n, 1, 3), FLOOR_NAMED_LOOT[1])
	return options[rng.randi() % options.size()]

static func is_valuable(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).get("cat", Category.CONSUMABLE) == Category.VALUABLE

static func is_document(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).get("cat", Category.CONSUMABLE) == Category.DOCUMENT

static func is_relic(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).get("cat", Category.CONSUMABLE) == Category.RELIC

# ── Body-loot roll (called by guard on death) ─────────────────────────────────
static func roll_body_loot(is_captain: bool, is_boss: bool, floor_n: int,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var table_id := "guard_body"
	if is_captain or is_boss:
		table_id = "captain_body"
	# Base coin drop
	var coins := rng.randi_range(4, 18) if not is_captain else rng.randi_range(20, 55)
	if is_boss: coins = rng.randi_range(80, 180)
	results.append({"id": "GOLD_PIECE", "count": coins})
	# Extra item (50% chance for regular guard, 85% for captain/boss)
	var chance := 0.85 if (is_captain or is_boss) else 0.50
	if rng.randf() < chance:
		var extra_id := roll_from_table(table_id, rng)
		var extra_count := 1
		if extra_id == "GOLD_PIECE":
			extra_count = rng.randi_range(5, 20)
		results.append({"id": extra_id, "count": extra_count})
	# Rare bonus item for boss
	if is_boss and rng.randf() < 0.70:
		var bonus_table := get_table_for_floor(floor_n, true)
		var bonus_id := roll_from_table(bonus_table, rng)
		results.append({"id": bonus_id, "count": 1})
	return results
