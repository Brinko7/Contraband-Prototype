extends Node
# ── Contraband V12 Loot System ────────────────────────────────────────────────
# Full overhaul: consumables, contraband, intel, junk, cursed items,
# unidentified pool, weight system, fence values, room-typed loot.

enum Category { CONSUMABLE, VALUABLE, DOCUMENT, EQUIPMENT, RELIC,
				WEAPON, CONTRABAND, INTEL, JUNK }
enum Rarity { JUNK, COMMON, UNCOMMON, RARE, LEGENDARY }

# Room types for roll_room_loot
enum RoomType { GENERIC, VAULT, ARMORY, LIBRARY, KITCHEN, BARRACKS }

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

# item weight (carry units). Player limit = 6 + STR_bonus.
# Weight 3-4 items apply -10% move speed.
# "iw" = item weight (1-4), "cursed" = true for cursed items.

const ITEMS: Dictionary = {
	# ── Consumables ────────────────────────────────────────────────────────────
	"GOLD_PIECE":         { "name": "Gold Piece",            "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 1,    "iw": 1, "desc": "Clinking gold. The universal language.",                         "color": Color(0.95, 0.80, 0.10) },
	"SMOKE_BOMB":         { "name": "Smoke Bomb",             "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 20,   "iw": 1, "desc": "Releases a blinding cloud on impact.",                          "color": Color(0.55, 0.90, 0.45) },
	"ROPE":               { "name": "Hemp Rope",              "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 18,   "iw": 2, "desc": "Coil a guard tight, or climb. Situationally essential.",         "color": Color(0.72, 0.60, 0.38) },
	"COIN_POUCH":         { "name": "Coin Pouch",             "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 35,   "iw": 1, "desc": "A bulging cloth pouch. Someone will miss this.",                 "color": Color(0.85, 0.72, 0.25) },
	"SOPORIFIC_DART":     { "name": "Soporific Dart",         "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 40,   "iw": 1, "desc": "One prick and it's lights out. Silently.",                      "color": Color(0.30, 0.70, 0.95) },
	"SILK_ROPE":          { "name": "Silk Rope",              "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 25,   "iw": 2, "desc": "A length of strong, near-silent rope.",                         "color": Color(0.75, 0.55, 0.95) },
	"FLASH_POWDER":       { "name": "Flash Powder",           "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 35,   "iw": 1, "desc": "Blinds and disorients nearby guards.",                          "color": Color(1.00, 0.95, 0.70) },
	"HOLD_SCROLL":        { "name": "Hold Person Scroll",     "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 55,   "iw": 1, "desc": "Freezes a target in place for 4 seconds.",                      "color": Color(0.55, 0.35, 0.90) },
	"SILENCE_SCROLL":     { "name": "Silence Scroll",         "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 50,   "iw": 1, "desc": "Creates a zone of magical silence.",                            "color": Color(0.30, 0.20, 0.55) },
	"THIEVES_TOOLS":      { "name": "Thieves' Tools",         "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 30,   "iw": 1, "desc": "+5 to next lockpick attempt. Also identifies magic items.",      "color": Color(0.70, 0.55, 0.30) },
	"SHADOW_OIL":         { "name": "Shadow Cloak Oil",       "cat": Category.CONSUMABLE, "rar": Rarity.RARE,      "value": 90,   "iw": 1, "desc": "Anointing yourself reduces guard vision by 20 for 60s.",         "color": Color(0.20, 0.15, 0.35) },
	"HEALING_SALVE":      { "name": "Healing Salve",          "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 65,   "iw": 1, "desc": "Restores 1 HP. Smells faintly of pine resin.",                  "color": Color(0.28, 0.72, 0.38) },
	"ANTITOXIN":          { "name": "Antitoxin Vial",         "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 50,   "iw": 1, "desc": "Clears bleeding and limping status.",                           "color": Color(0.45, 0.88, 0.65) },
	"STIM_POWDER":        { "name": "Stim Powder",            "cat": Category.CONSUMABLE, "rar": Rarity.RARE,      "value": 80,   "iw": 1, "desc": "A single sniff gives 8 seconds of doubled movement speed.",      "color": Color(0.88, 0.55, 0.92) },
	"MARKED_COIN":        { "name": "Marked Coin",            "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 10,   "iw": 1, "desc": "A weighted coin — makes noise on landing. Useful distraction.",  "color": Color(0.75, 0.65, 0.25) },
	"POISON_VIAL":        { "name": "Poison Vial",            "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 55,   "iw": 1, "desc": "Coat a blade or drop in food. Causes BLEEDING on any hit for 30s.", "color": Color(0.35, 0.72, 0.25) },
	"FLASH_POWDER_LARGE": { "name": "Flash Powder (Large)",   "cat": Category.CONSUMABLE, "rar": Rarity.RARE,      "value": 75,   "iw": 2, "desc": "Wide-radius flash. Blinds all guards in the room.",             "color": Color(1.00, 0.98, 0.55) },
	"GRAPPLE_HOOK":       { "name": "Grapple Hook",           "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 70,   "iw": 2, "desc": "Reach high ledges or yank a guard off-balance.",               "color": Color(0.55, 0.55, 0.65) },
	"SLEEPING_DRAUGHT":   { "name": "Sleeping Draught",       "cat": Category.CONSUMABLE, "rar": Rarity.UNCOMMON,  "value": 60,   "iw": 1, "desc": "Slipped into a drink: guard sleeps at their post for 60s.",      "color": Color(0.55, 0.80, 0.65) },
	"PARCHMENT_FORGERY":  { "name": "Parchment Forgery",      "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 45,   "iw": 1, "desc": "Convincing forgery. Counts as FORGED_PAPERS at exit.",          "color": Color(0.85, 0.80, 0.60) },
	"ACID_FLASK":         { "name": "Acid Flask",             "cat": Category.CONSUMABLE, "rar": Rarity.RARE,      "value": 85,   "iw": 2, "desc": "Dissolves locks, chains, or armored guards' protection.",       "color": Color(0.70, 0.90, 0.22) },
	"CALTROPS":           { "name": "Caltrops",               "cat": Category.CONSUMABLE, "rar": Rarity.COMMON,    "value": 25,   "iw": 2, "desc": "Scatter behind you. SLOWS pursuing guards for 6s.",             "color": Color(0.55, 0.55, 0.50) },
	"SILENCE_STONE":      { "name": "Silence Stone",          "cat": Category.CONSUMABLE, "rar": Rarity.RARE,      "value": 110,  "iw": 1, "desc": "Place on floor: any kills within 2 tiles are utterly silent.",  "color": Color(0.35, 0.28, 0.55) },
	# ── Valuables ──────────────────────────────────────────────────────────────
	"RUBY":               { "name": "Rough Ruby",             "cat": Category.VALUABLE,   "rar": Rarity.RARE,      "value": 320,  "iw": 1, "desc": "A blood-red gemstone from the southern mines.",                "color": Color(0.92, 0.15, 0.18) },
	"SAPPHIRE":           { "name": "Polished Sapphire",      "cat": Category.VALUABLE,   "rar": Rarity.RARE,      "value": 280,  "iw": 1, "desc": "Deep blue, clear as winter sky.",                              "color": Color(0.18, 0.35, 0.98) },
	"EMERALD":            { "name": "Emerald Fragment",       "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 180,  "iw": 1, "desc": "A cracked but valuable green stone.",                          "color": Color(0.12, 0.82, 0.35) },
	"PEARL":              { "name": "Sea Pearl",              "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 150,  "iw": 1, "desc": "Lustrous and perfectly round. Merchant-grade.",                "color": Color(0.92, 0.90, 0.88) },
	"GOLD_RING":          { "name": "Gold Signet Ring",       "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 220,  "iw": 1, "desc": "A family crest ring. The fence won't ask questions.",          "color": Color(0.92, 0.78, 0.18) },
	"SILVER_NECKLACE":    { "name": "Silver Necklace",        "cat": Category.VALUABLE,   "rar": Rarity.COMMON,    "value": 95,   "iw": 1, "desc": "Fine silverwork. Probably shouldn't be here.",                 "color": Color(0.80, 0.80, 0.88) },
	"ANCIENT_COIN":       { "name": "Ancient Gold Coin",      "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 130,  "iw": 1, "desc": "Minted before the Compact. Collectors pay well.",             "color": Color(0.88, 0.70, 0.22) },
	"SILVER_CHALICE":     { "name": "Silver Chalice",         "cat": Category.VALUABLE,   "rar": Rarity.COMMON,    "value": 110,  "iw": 3, "desc": "Heavy and tarnished. Still worth good coin.",                  "color": Color(0.72, 0.72, 0.80) },
	"NOBLE_BROOCH":       { "name": "Noble's Brooch",         "cat": Category.VALUABLE,   "rar": Rarity.RARE,      "value": 380,  "iw": 1, "desc": "Encrusted with small gems. Clearly expensive.",                "color": Color(0.82, 0.62, 0.88) },
	"IVORY_FIGURINE":     { "name": "Ivory Figurine",         "cat": Category.VALUABLE,   "rar": Rarity.UNCOMMON,  "value": 200,  "iw": 2, "desc": "A carved deity statuette. Sacred? Profitable.",               "color": Color(0.92, 0.88, 0.80) },
	"VOID_CRYSTAL":       { "name": "Void Crystal Shard",     "cat": Category.VALUABLE,   "rar": Rarity.LEGENDARY, "value": 850,  "iw": 1, "desc": "Hums with barely-contained shadow energy.",                   "color": Color(0.30, 0.12, 0.55) },
	"GOLD_BAR":           { "name": "Gold Bar",               "cat": Category.VALUABLE,   "rar": Rarity.RARE,      "value": 450,  "iw": 4, "desc": "Heavy as sin and twice as valuable. You'll feel it.",          "color": Color(0.95, 0.80, 0.12) },
	"CROWN_JEWEL":        { "name": "Crown Jewel",            "cat": Category.VALUABLE,   "rar": Rarity.LEGENDARY, "value": 900,  "iw": 2, "desc": "One of the vault's centerpieces. Don't drop it.",             "color": Color(0.95, 0.70, 0.92) },
	"ARMOR_FRAGMENT":     { "name": "Armor Fragment",         "cat": Category.VALUABLE,   "rar": Rarity.COMMON,    "value": 55,   "iw": 3, "desc": "A chunk of quality plate. Scrap price is still good.",        "color": Color(0.62, 0.65, 0.68) },
	# ── Documents ──────────────────────────────────────────────────────────────
	"PATROL_SCHEDULE":    { "name": "Patrol Schedule",        "cat": Category.DOCUMENT,   "rar": Rarity.UNCOMMON,  "value": 80,   "iw": 1, "desc": "READ: Reveals all patrol routes on this floor.",              "color": Color(0.82, 0.72, 0.42) },
	"VAULT_MANIFEST":     { "name": "Vault Manifest",         "cat": Category.DOCUMENT,   "rar": Rarity.RARE,      "value": 120,  "iw": 1, "desc": "READ: Marks the exact location of the primary objective.",    "color": Color(0.78, 0.68, 0.38) },
	"ARREST_WARRANT":     { "name": "Arrest Warrant",         "cat": Category.DOCUMENT,   "rar": Rarity.RARE,      "value": 200,  "iw": 1, "desc": "A warrant for your arrest, signed in triplicate. Ironic to fence.", "color": Color(0.88, 0.35, 0.25) },
	"BRIBE_LEDGER":       { "name": "Bribe Ledger",           "cat": Category.DOCUMENT,   "rar": Rarity.LEGENDARY, "value": 600,  "iw": 1, "desc": "Names, amounts, dates. The guild pays a fortune for this.",   "color": Color(0.62, 0.78, 0.35) },
	"FORGED_PAPERS":      { "name": "Forged Papers",          "cat": Category.DOCUMENT,   "rar": Rarity.COMMON,    "value": 60,   "iw": 1, "desc": "Passable forgeries. Reduce wanted level by 1 if used at exit.", "color": Color(0.75, 0.72, 0.58) },
	# ── Equipment ──────────────────────────────────────────────────────────────
	"WEIGHTED_GLOVES":    { "name": "Weighted Gloves",        "cat": Category.EQUIPMENT,  "rar": Rarity.UNCOMMON,  "value": 140,  "iw": 1, "desc": "+1 melee damage. Knuckles dusted with iron shavings.",        "color": Color(0.55, 0.42, 0.28) },
	"LOCKPICK_SET_ADV":   { "name": "Expert Lockpick Set",    "cat": Category.EQUIPMENT,  "rar": Rarity.RARE,      "value": 220,  "iw": 1, "desc": "+8 to all lockpick rolls. Crafted by a guild master.",        "color": Color(0.65, 0.65, 0.72) },
	"DARK_LENS":          { "name": "Dark-Vision Lens",       "cat": Category.EQUIPMENT,  "rar": Rarity.RARE,      "value": 300,  "iw": 1, "desc": "A single monocle that pierces magical darkness.",             "color": Color(0.28, 0.38, 0.55) },
	# ── Relics ─────────────────────────────────────────────────────────────────
	"RING_BLINKING":      { "name": "Ring of Blinking",       "cat": Category.RELIC,      "rar": Rarity.LEGENDARY, "value": 1200, "iw": 1, "desc": "Short-range teleport to a random adjacent tile (10s cooldown).", "color": Color(0.55, 0.88, 0.95) },
	"CLOAK_MISTS":        { "name": "Cloak of Mists",         "cat": Category.RELIC,      "rar": Rarity.LEGENDARY, "value": 900,  "iw": 2, "desc": "On taking damage, unleash a blinding mist cloud.",            "color": Color(0.62, 0.72, 0.88) },
	"BOOTS_SILENCE":      { "name": "Boots of Silence",       "cat": Category.RELIC,      "rar": Rarity.RARE,      "value": 550,  "iw": 2, "desc": "Movement is always completely silent.",                       "color": Color(0.28, 0.22, 0.45) },
	"THIEVES_LANTERN":    { "name": "Thief's Lantern",        "cat": Category.RELIC,      "rar": Rarity.UNCOMMON,  "value": 180,  "iw": 2, "desc": "A shielded lantern. Reveals nearby hidden traps.",            "color": Color(0.92, 0.78, 0.25) },
	# ── Cursed relics ──────────────────────────────────────────────────────────
	"CURSED_BOOTS":       { "name": "Boots of Swift Ruin",    "cat": Category.RELIC,      "rar": Rarity.RARE,      "value": 420,  "iw": 2, "cursed": true,
							"desc": "Fast movement — but they creak loudly on every step. Guards hear you from double range.", "color": Color(0.75, 0.30, 0.22) },
	"CURSED_BLADE":       { "name": "Wrathblade",             "cat": Category.RELIC,      "rar": Rarity.RARE,      "value": 480,  "iw": 2, "cursed": true,
							"desc": "+2 melee damage. On Nat 1, deals 1 damage to the wielder instead.", "color": Color(0.55, 0.10, 0.10) },
	"VOID_CONTRACT":      { "name": "Void Contract",          "cat": Category.RELIC,      "rar": Rarity.LEGENDARY, "value": 200,  "iw": 1, "cursed": true,
							"desc": "+200gp at run end — but all guards are SUSPICIOUS from floor 2 onward. The ink smells wrong.", "color": Color(0.25, 0.10, 0.35) },
	# ── Contraband (hot items; +wanted_level on exit if carried) ───────────────
	"STOLEN_CROWN":       { "name": "The Stolen Crown",       "cat": Category.CONTRABAND, "rar": Rarity.LEGENDARY, "value": 1400, "iw": 2, "hot": true,
							"desc": "You shouldn't have this. Neither should they. +1 wanted on exit.", "color": Color(0.95, 0.82, 0.15) },
	"NOBLE_SIGNET":       { "name": "Noble's Signet Ring",    "cat": Category.CONTRABAND, "rar": Rarity.RARE,      "value": 520,  "iw": 1, "hot": true,
							"desc": "Proof of identity — or forgery. +1 wanted on exit.",             "color": Color(0.88, 0.72, 0.28) },
	"GUILD_LEDGER":       { "name": "Guild Ledger",           "cat": Category.CONTRABAND, "rar": Rarity.LEGENDARY, "value": 780,  "iw": 2, "hot": true,
							"desc": "Every contract, every name. Multiple factions want this dead. +1 wanted on exit.", "color": Color(0.45, 0.65, 0.30) },
	"ANCIENT_RELIC":      { "name": "Ancient Relic",          "cat": Category.CONTRABAND, "rar": Rarity.LEGENDARY, "value": 950,  "iw": 3, "hot": true,
							"desc": "Pre-empire. Priceless. Illegal to own. +1 wanted on exit.",       "color": Color(0.80, 0.65, 0.30) },
	"BLOOD_DIAMOND":      { "name": "Blood Diamond",          "cat": Category.CONTRABAND, "rar": Rarity.LEGENDARY, "value": 1100, "iw": 1, "hot": true,
							"desc": "Its origin is worse than its name implies. +1 wanted on exit.",   "color": Color(0.95, 0.12, 0.12) },
	"FORGED_DEED":        { "name": "Forged Property Deed",   "cat": Category.CONTRABAND, "rar": Rarity.RARE,      "value": 380,  "iw": 1, "hot": true,
							"desc": "Makes you the legal owner of something you aren't. +1 wanted on exit.", "color": Color(0.75, 0.70, 0.50) },
	# ── Intel items (consumed on pickup for instant benefits) ──────────────────
	"PATROL_MAP":         { "name": "Patrol Map",             "cat": Category.INTEL,      "rar": Rarity.UNCOMMON,  "value": 0,    "iw": 1, "intel": "reveal_patrols",
							"desc": "INTEL: Immediately reveals all guard patrol routes this floor.", "color": Color(0.82, 0.78, 0.40) },
	"VAULT_KEY_RUBBING":  { "name": "Vault Key Rubbing",      "cat": Category.INTEL,      "rar": Rarity.RARE,      "value": 0,    "iw": 1, "intel": "unlock_vault",
							"desc": "INTEL: Unlocks one locked door on this floor.",                   "color": Color(0.75, 0.65, 0.28) },
	"GUARD_MANIFEST":     { "name": "Guard Manifest",         "cat": Category.INTEL,      "rar": Rarity.UNCOMMON,  "value": 0,    "iw": 1, "intel": "reveal_stats",
							"desc": "INTEL: Reveals HP bars and detection radii for all guards.",      "color": Color(0.70, 0.70, 0.55) },
	"POISON_RECIPE":      { "name": "Poison Recipe",          "cat": Category.INTEL,      "rar": Rarity.RARE,      "value": 0,    "iw": 1, "intel": "grant_poison",
							"desc": "INTEL: Grants one free POISON_VIAL — you already know the ingredients.", "color": Color(0.40, 0.75, 0.28) },
	# ── Junk (low value; throwable as distractions) ────────────────────────────
	"BROKEN_BOTTLE":      { "name": "Broken Bottle",          "cat": Category.JUNK,       "rar": Rarity.JUNK,      "value": 5,    "iw": 1, "throwable": true,
							"desc": "Mostly shards. Thrown: makes noise and leaves hazardous floor.",  "color": Color(0.70, 0.88, 0.80) },
	"DUSTY_TOME":         { "name": "Dusty Tome",             "cat": Category.JUNK,       "rar": Rarity.JUNK,      "value": 8,    "iw": 3, "throwable": true,
							"desc": "An ancient text. Heavy and worthless. Thrown: solid thunk.",       "color": Color(0.65, 0.55, 0.38) },
	"CHEAP_TRINKET":      { "name": "Cheap Trinket",          "cat": Category.JUNK,       "rar": Rarity.JUNK,      "value": 12,   "iw": 1, "throwable": true,
							"desc": "A pewter charm. Fence might give you enough for a meal.",          "color": Color(0.60, 0.60, 0.60) },
	"PLAYING_CARDS":      { "name": "Playing Cards",          "cat": Category.JUNK,       "rar": Rarity.JUNK,      "value": 4,    "iw": 1, "throwable": true,
							"desc": "Dogeared deck from the barracks. Scatter them: guards investigate.", "color": Color(0.90, 0.88, 0.82) },
	"IRON_RATION":        { "name": "Iron Ration",            "cat": Category.JUNK,       "rar": Rarity.COMMON,    "value": 6,    "iw": 1, "throwable": true,
							"desc": "Hard tack and jerky. Edible. Throwable.",                         "color": Color(0.72, 0.60, 0.42) },
}

# ── Unidentified item pool ────────────────────────────────────────────────────
const UNIDENTIFIED_NAMES: Array = [
	"Vial of Unknown Liquid",
	"Sealed Scroll",
	"Strange Amulet",
	"Wrapped Package",
	"Odd-Smelling Flask",
	"Mysterious Pouch",
	"Unlabeled Bottle",
	"Tarnished Medallion",
]

# Which items can appear unidentified (typically relics and rare gear)
const UNIDENTIFIED_POOL: Array = [
	"CURSED_BOOTS", "CURSED_BLADE", "VOID_CONTRACT",
	"RING_BLINKING", "CLOAK_MISTS", "BOOTS_SILENCE",
	"SHADOW_OIL", "SILENCE_STONE",
]

# ── Loot tables per zone/floor ────────────────────────────────────────────────
const LOOT_TABLES: Dictionary = {
	"floor1_common":  [
		["GOLD_PIECE", 30], ["SMOKE_BOMB", 15], ["SOPORIFIC_DART", 10],
		["MARKED_COIN", 20], ["SILVER_NECKLACE", 12], ["ANCIENT_COIN", 8],
		["FORGED_PAPERS", 10], ["PATROL_SCHEDULE", 5],
		["COIN_POUCH", 12], ["BROKEN_BOTTLE", 10], ["PLAYING_CARDS", 8],
	],
	"floor1_rare":    [
		["GOLD_RING", 20], ["IVORY_FIGURINE", 15], ["RUBY", 8],
		["HEALING_SALVE", 18], ["ANTITOXIN", 12], ["LOCKPICK_SET_ADV", 10],
		["THIEVES_LANTERN", 8], ["PATROL_SCHEDULE", 15], ["VAULT_MANIFEST", 5],
		["POISON_VIAL", 10], ["SILENCE_STONE", 5], ["PATROL_MAP", 8],
	],
	"floor2_common":  [
		["GOLD_PIECE", 20], ["SMOKE_BOMB", 12], ["SOPORIFIC_DART", 12],
		["SILK_ROPE", 10], ["FLASH_POWDER", 10], ["SILVER_CHALICE", 14],
		["ANCIENT_COIN", 10], ["FORGED_PAPERS", 8], ["PATROL_SCHEDULE", 8],
		["CALTROPS", 10], ["COIN_POUCH", 10], ["SLEEPING_DRAUGHT", 8],
	],
	"floor2_rare":    [
		["EMERALD", 18], ["SAPPHIRE", 12], ["GOLD_RING", 15],
		["HEALING_SALVE", 12], ["STIM_POWDER", 10], ["WEIGHTED_GLOVES", 8],
		["DARK_LENS", 6], ["VAULT_MANIFEST", 10], ["ARREST_WARRANT", 6],
		["ACID_FLASK", 8], ["GRAPPLE_HOOK", 8], ["GUARD_MANIFEST", 6],
	],
	"floor3_common":  [
		["GOLD_PIECE", 15], ["SOPORIFIC_DART", 15], ["HOLD_SCROLL", 12],
		["SHADOW_OIL", 10], ["SILENCE_SCROLL", 10], ["SILVER_CHALICE", 10],
		["EMERALD", 8], ["ARREST_WARRANT", 8], ["BRIBE_LEDGER", 4],
		["ACID_FLASK", 8], ["SILENCE_STONE", 6], ["PARCHMENT_FORGERY", 8],
	],
	"floor3_rare":    [
		["RUBY", 18], ["SAPPHIRE", 14], ["NOBLE_BROOCH", 12],
		["VOID_CRYSTAL", 8], ["RING_BLINKING", 5], ["CLOAK_MISTS", 4],
		["BOOTS_SILENCE", 8], ["BRIBE_LEDGER", 10], ["VAULT_MANIFEST", 8],
		["CURSED_BLADE", 5], ["CURSED_BOOTS", 5], ["VOID_CONTRACT", 3],
		["BLOOD_DIAMOND", 4], ["GUILD_LEDGER", 6],
	],
	"guard_body":     [
		["GOLD_PIECE", 40], ["MARKED_COIN", 20], ["SOPORIFIC_DART", 12],
		["ANCIENT_COIN", 12], ["FORGED_PAPERS", 8], ["THIEVES_TOOLS", 8],
		["COIN_POUCH", 12], ["PLAYING_CARDS", 6],
	],
	"captain_body":   [
		["ANCIENT_COIN", 25], ["GOLD_RING", 20], ["PATROL_SCHEDULE", 18],
		["HEALING_SALVE", 15], ["VAULT_MANIFEST", 10], ["RUBY", 8],
		["GUARD_MANIFEST", 10], ["PATROL_MAP", 8],
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

# ── Room-typed loot tables ────────────────────────────────────────────────────
const ROOM_LOOT_TABLES: Dictionary = {
	RoomType.VAULT: [
		["GOLD_BAR", 20], ["CROWN_JEWEL", 12], ["GUILD_LEDGER", 10],
		["RUBY", 18], ["SAPPHIRE", 15], ["BLOOD_DIAMOND", 8],
		["STOLEN_CROWN", 5], ["NOBLE_SIGNET", 12], ["VOID_CRYSTAL", 6],
	],
	RoomType.ARMORY: [
		["ARMOR_FRAGMENT", 25], ["WEIGHTED_GLOVES", 20], ["CALTROPS", 15],
		["ACID_FLASK", 12], ["ROPE", 15], ["GRAPPLE_HOOK", 10],
		["ANCIENT_RELIC", 5], ["FORGED_DEED", 8],
	],
	RoomType.LIBRARY: [
		["PATROL_MAP", 25], ["VAULT_KEY_RUBBING", 15], ["GUARD_MANIFEST", 20],
		["POISON_RECIPE", 12], ["DUSTY_TOME", 20], ["BRIBE_LEDGER", 6],
		["PATROL_SCHEDULE", 18], ["VAULT_MANIFEST", 10], ["PARCHMENT_FORGERY", 15],
	],
	RoomType.KITCHEN: [
		["POISON_VIAL", 30], ["SLEEPING_DRAUGHT", 25], ["HEALING_SALVE", 20],
		["IRON_RATION", 25], ["ACID_FLASK", 10], ["BROKEN_BOTTLE", 15],
		["ANTITOXIN", 12],
	],
	RoomType.BARRACKS: [
		["COIN_POUCH", 28], ["PLAYING_CARDS", 25], ["MARKED_COIN", 20],
		["IRON_RATION", 18], ["GOLD_PIECE", 15], ["FORGED_PAPERS", 12],
		["WEIGHTED_GLOVES", 8], ["CALTROPS", 10],
	],
	RoomType.GENERIC: [
		["GOLD_PIECE", 25], ["SMOKE_BOMB", 15], ["MARKED_COIN", 15],
		["COIN_POUCH", 12], ["SOPORIFIC_DART", 10], ["SILVER_NECKLACE", 8],
		["BROKEN_BOTTLE", 8], ["CHEAP_TRINKET", 7],
	],
}

# ── Static helpers (all original functions preserved) ────────────────────────
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
	return ITEMS.get(item_id, {"name": item_id, "value": 50, "iw": 1,
		"cat": Category.VALUABLE, "rar": Rarity.COMMON,
		"desc": "Unknown item.", "color": Color(0.75, 0.72, 0.65)})

static func get_rarity_color(item_id: String) -> Color:
	var data: Dictionary = ITEMS.get(item_id, {})
	return RARITY_COLORS.get(data.get("rar", Rarity.COMMON), Color(0.88, 0.85, 0.80))

static func get_item_value(item_id: String, floor_n: int) -> int:
	var data: Dictionary = ITEMS.get(item_id, {})
	var base: int = data.get("value", 50)
	var rar: int = data.get("rar", Rarity.COMMON)
	var mults: Dictionary = {Rarity.JUNK: 0.6, Rarity.COMMON: 1.0, Rarity.UNCOMMON: 1.5,
		Rarity.RARE: 2.2, Rarity.LEGENDARY: 4.0}
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

# ── New V12 helpers ───────────────────────────────────────────────────────────

static func get_item_weight(item_id: String) -> int:
	return ITEMS.get(item_id, {}).get("iw", 1)

static func is_heavy(item_id: String) -> bool:
	return get_item_weight(item_id) >= 3

static func is_cursed(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).get("cursed", false)

static func is_contraband(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).get("cat", -1) == Category.CONTRABAND

static func is_intel(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).get("cat", -1) == Category.INTEL

static func is_junk(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).get("cat", -1) == Category.JUNK

static func is_throwable(item_id: String) -> bool:
	return ITEMS.get(item_id, {}).get("throwable", false)

static func get_intel_effect(item_id: String) -> String:
	return ITEMS.get(item_id, {}).get("intel", "")

# Returns gold after fence cut, reduced by heat (wanted_level).
# Fence always takes 30% cut; each wanted level adds 5% extra cut (max 60% total).
static func get_fence_value(item_id: String, wanted_level: int) -> int:
	var data: Dictionary = ITEMS.get(item_id, {})
	var base: int = data.get("value", 0)
	if base == 0:
		return 0
	# Intel and junk worth nothing to the fence
	if data.get("cat", -1) in [Category.INTEL]:
		return 0
	var cut_pct: float = 0.30 + clampf(wanted_level * 0.05, 0.0, 0.30)
	return int(base * (1.0 - cut_pct))

# Unidentified name — returns a generic disguise name for a mystery item.
static func get_unidentified_name(item_id: String) -> String:
	# Use item_id as a stable seed for consistent names per item
	var idx: int = abs(item_id.hash()) % UNIDENTIFIED_NAMES.size()
	return UNIDENTIFIED_NAMES[idx]

# Identify an item. Rolls Investigation DC 12 using player's relevant stat.
# Returns true on success. On failure, item is still revealed but cursed items
# trigger an immediate curse activation signal.
static func identify_item(item_id: String, player: Node) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var roll: int = rng.randi_range(1, 20)
	# Player INT bonus (assume player has "int_bonus" property, default 0)
	var bonus: int = 0
	if player and player.get("int_bonus") != null:
		bonus = player.get("int_bonus")
	var total: int = roll + bonus
	if total >= 12:
		return true
	# On failure: if cursed, the item activates its negative effect
	if is_cursed(item_id) and player and player.has_method("on_curse_activated"):
		player.on_curse_activated(item_id)
	return false

# Check carry weight against player capacity.
static func get_carry_capacity(player: Node) -> int:
	var str_bonus: int = 0
	if player and player.get("str_bonus") != null:
		str_bonus = player.get("str_bonus")
	return 6 + str_bonus

# Roll thematic loot for a specific room type and floor.
# Returns an array of {id, count} dicts.
static func roll_room_loot(room_type: int, floor_num: int,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var table: Array = ROOM_LOOT_TABLES.get(room_type, ROOM_LOOT_TABLES[RoomType.GENERIC])

	# Item count scales with floor: 1-2 on floor 1, 2-3 on floor 2, 2-4 on floor 3
	var min_items: int = 1 + (1 if floor_num >= 2 else 0)
	var max_items: int = 2 + (1 if floor_num >= 2 else 0) + (1 if floor_num >= 3 else 0)
	var count: int = rng.randi_range(min_items, max_items)

	# Build weighted roll from room table
	var total_weight := 0
	for entry in table:
		total_weight += entry[1]

	var seen_ids: Dictionary = {}
	for _i in range(count):
		var roll := rng.randi_range(0, total_weight - 1)
		var cumulative := 0
		var chosen_id: String = table[0][0]
		for entry in table:
			cumulative += entry[1]
			if roll < cumulative:
				chosen_id = entry[0]
				break
		# Avoid duplicate unique items (relics, contraband)
		var data: Dictionary = ITEMS.get(chosen_id, {})
		var is_unique_type: bool = data.get("cat", -1) in [Category.RELIC, Category.CONTRABAND, Category.INTEL]
		if is_unique_type and seen_ids.has(chosen_id):
			# Re-roll once with a generic fallback
			chosen_id = "GOLD_PIECE"
		seen_ids[chosen_id] = true

		# Gold stacks
		var item_count := 1
		if chosen_id == "GOLD_PIECE":
			item_count = rng.randi_range(8, 30) + (floor_num - 1) * 10
		elif chosen_id == "COIN_POUCH":
			item_count = 1

		# Floor scaling: bump value items on deeper floors
		if floor_num >= 3 and data.get("rar", Rarity.COMMON) == Rarity.COMMON:
			# 25% chance to upgrade common to uncommon equivalent
			if rng.randf() < 0.25:
				chosen_id = _upgrade_common_item(chosen_id, rng)

		results.append({"id": chosen_id, "count": item_count})

	return results

# Internal: upgrade a common item to a slightly better equivalent
static func _upgrade_common_item(item_id: String, rng: RandomNumberGenerator) -> String:
	const UPGRADES: Dictionary = {
		"GOLD_PIECE":      "ANCIENT_COIN",
		"SMOKE_BOMB":      "FLASH_POWDER",
		"MARKED_COIN":     "COIN_POUCH",
		"BROKEN_BOTTLE":   "POISON_VIAL",
		"PLAYING_CARDS":   "CALTROPS",
		"IRON_RATION":     "HEALING_SALVE",
	}
	return UPGRADES.get(item_id, item_id)

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
