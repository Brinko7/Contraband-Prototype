# Floorplans.gd — building layouts the heist can take place in.
#
# Each plan is a self-contained description of a floor's GEOMETRY (which tiles
# are carved out of solid rock) plus the SEMANTIC ANCHORS the spawners need
# (which room is the entry, which is the vault, where torches/cover go). The
# map grid is 48 cols x 36 rows of 16px tiles.
#
# Index 0 is CLASSIC — the original hand-authored building. LevelMap and World
# keep their bespoke code paths for it (furniture, hand-tuned encounters), so
# its room/torch arrays here only need to mirror those constants for the
# minimap + fog sizing. Indices 1+ are new buildings driven generically.
#
# Selection rule: floors 1-5 always roll a NEW plan (so the variety is always
# visible); floor 6 is always CLASSIC, preserving the authored Citadel finale.

const TILE := 16

# Each room: { "rect": Rect2i(col,row,w,h), "name": String, "kind": String }
#   kind ∈ "entry" | "vault" | "guard" | "hall" | "store"
# Room array ORDER is the fog/minimap index order; _tile_to_room returns it.

const PLANS := [
	# ── 0: CLASSIC — mirrors LevelMap._build_map / ROOM_TILE_RECTS / TORCHES ──
	{
		"id": "CLASSIC",
		"entry_idx": 0,
		"vault_idx": 5,
		"rooms": [
			{ "rect": Rect2i(11, 30, 26,  5), "name": "Entry Foyer",      "kind": "entry" },
			{ "rect": Rect2i( 1, 19, 19, 10), "name": "Barracks",         "kind": "guard" },
			{ "rect": Rect2i(27, 19, 19, 10), "name": "Storeroom",        "kind": "store" },
			{ "rect": Rect2i( 1,  8, 16, 10), "name": "Captain's Office", "kind": "guard" },
			{ "rect": Rect2i(19,  8, 13, 10), "name": "Antechamber",      "kind": "hall"  },
			{ "rect": Rect2i( 6,  1, 36,  6), "name": "The Vault",        "kind": "vault" },
			{ "rect": Rect2i(35,  8, 11, 10), "name": "Armory",           "kind": "store" },
		],
		"carves": [
			Rect2i( 6,  1, 36,  6), Rect2i( 8,  6,  3,  3), Rect2i(25,  6,  3,  3),
			Rect2i( 1,  8, 16, 10), Rect2i(19,  8, 13, 10), Rect2i(35,  8, 11, 10),
			Rect2i(16, 10,  4,  6), Rect2i(31, 10,  5,  6),
			Rect2i( 7, 17,  3,  3), Rect2i(36, 17,  3,  3),
			Rect2i( 1, 19, 19, 10), Rect2i(27, 19, 19, 10),
			Rect2i(14, 28,  3,  3), Rect2i(31, 28,  3,  3),
			Rect2i(11, 30, 26,  5),
		],
		"torches": [
			Vector2(240, 24), Vector2(384, 24), Vector2(528, 24),
			Vector2(80, 140), Vector2(216, 270), Vector2(408, 140),
			Vector2(636, 140), Vector2(700, 252), Vector2(72, 316),
			Vector2(216, 442), Vector2(660, 316), Vector2(300, 494), Vector2(468, 494),
		],
		"cover": [],
	},

	# ── 1: CROSS — central hub with four wings; vault due north of entry ──────
	{
		"id": "CROSS",
		"entry_idx": 0,
		"vault_idx": 4,
		"rooms": [
			{ "rect": Rect2i(16, 27, 16,  7), "name": "Grand Foyer",    "kind": "entry" },
			{ "rect": Rect2i( 2, 14, 12,  8), "name": "West Gallery",   "kind": "guard" },
			{ "rect": Rect2i(20, 14,  8,  8), "name": "Central Rotunda","kind": "hall"  },
			{ "rect": Rect2i(34, 14, 12,  8), "name": "East Armory",    "kind": "store" },
			{ "rect": Rect2i(16,  2, 16,  7), "name": "The High Vault", "kind": "vault" },
		],
		"carves": [
			Rect2i(16, 27, 16,  7), Rect2i( 2, 14, 12,  8), Rect2i(20, 14,  8,  8),
			Rect2i(34, 14, 12,  8), Rect2i(16,  2, 16,  7),
			Rect2i(22,  8,  4,  6), Rect2i(22, 21,  4,  6),
			Rect2i(13, 16,  8,  4), Rect2i(27, 16,  8,  4),
		],
		"torches": [
			Vector2(384, 480), Vector2(128, 248), Vector2(384, 248),
			Vector2(640, 248), Vector2(384, 80),
		],
		"cover": [ Vector2i(23, 17), Vector2i(24, 18), Vector2i(5, 17), Vector2i(42, 18) ],
	},

	# ── 2: GAUNTLET — a winding S-chain entry→hall→gallery→ante→vault ─────────
	{
		"id": "GAUNTLET",
		"entry_idx": 0,
		"vault_idx": 4,
		"rooms": [
			{ "rect": Rect2i( 2, 28, 14,  6), "name": "Cellar Door",   "kind": "entry" },
			{ "rect": Rect2i( 2, 16, 16,  8), "name": "Guard Hall",    "kind": "guard" },
			{ "rect": Rect2i(13,  4, 20,  8), "name": "Long Gallery",  "kind": "hall"  },
			{ "rect": Rect2i(29, 15, 16,  8), "name": "Antechamber",   "kind": "guard" },
			{ "rect": Rect2i(30,  1, 16,  7), "name": "Sealed Vault",  "kind": "vault" },
		],
		"carves": [
			Rect2i( 2, 28, 14,  6), Rect2i( 2, 16, 16,  8), Rect2i(13,  4, 20,  8),
			Rect2i(29, 15, 16,  8), Rect2i(30,  1, 16,  7),
			Rect2i( 8, 24,  4,  5), Rect2i(13, 12,  4,  5),
			Rect2i(29, 11,  4,  5), Rect2i(36,  8,  4,  8),
		],
		"torches": [
			Vector2(144, 496), Vector2(160, 320), Vector2(368, 128),
			Vector2(592, 304), Vector2(608, 72),
		],
		"cover": [ Vector2i(20, 7), Vector2i(26, 7), Vector2i(8, 19), Vector2i(36, 18) ],
	},

	# ── 3: TWIN VAULTS — two vaults flank a central hall; pick your prize ─────
	{
		"id": "TWIN",
		"entry_idx": 0,
		"vault_idx": 2,
		"rooms": [
			{ "rect": Rect2i(18, 29, 12,  5), "name": "Servants' Door", "kind": "entry" },
			{ "rect": Rect2i(14, 20, 20,  8), "name": "Pillared Hall",  "kind": "hall"  },
			{ "rect": Rect2i( 2,  3, 14, 10), "name": "West Vault",     "kind": "vault" },
			{ "rect": Rect2i(32,  3, 14, 10), "name": "East Vault",     "kind": "vault" },
		],
		"carves": [
			Rect2i(18, 29, 12,  5), Rect2i(14, 20, 20,  8),
			Rect2i( 2,  3, 14, 10), Rect2i(32,  3, 14, 10),
			Rect2i(22, 27,  4,  3), Rect2i(11, 12,  4,  8), Rect2i(31, 12,  4,  8),
		],
		"torches": [
			Vector2(384, 496), Vector2(384, 384), Vector2(144, 128), Vector2(624, 128),
		],
		"cover": [ Vector2i(20, 23), Vector2i(28, 23), Vector2i(6, 7), Vector2i(40, 7) ],
	},
]

# Deterministic plan choice. Floor 6 = CLASSIC finale; 1-5 = a new building.
static func pick(seed: int, floor_num: int) -> int:
	if floor_num >= 6:
		return 0
	var new_count := PLANS.size() - 1            # exclude CLASSIC (index 0)
	if new_count <= 0:
		return 0
	return 1 + posmod(int(seed / 100.0) + floor_num * 3, new_count)

static func count() -> int:
	return PLANS.size()

static func get_plan(idx: int) -> Dictionary:
	if idx < 0 or idx >= PLANS.size():
		return PLANS[0]
	return PLANS[idx]

# Pixel-space center of a tile rect.
static func room_center(rect: Rect2i) -> Vector2:
	return Vector2(
		(float(rect.position.x) + float(rect.size.x) * 0.5) * TILE,
		(float(rect.position.y) + float(rect.size.y) * 0.5) * TILE)

# Pixel-space rect for a tile rect.
static func room_world_rect(rect: Rect2i) -> Rect2:
	return Rect2(
		float(rect.position.x) * TILE, float(rect.position.y) * TILE,
		float(rect.size.x) * TILE, float(rect.size.y) * TILE)

# A 4-corner perimeter patrol loop inset from the room edge (pixel space).
static func perimeter_patrol(rect: Rect2i, inset_px: float = 24.0) -> Array:
	var wr := room_world_rect(rect)
	var x0 := wr.position.x + inset_px
	var y0 := wr.position.y + inset_px
	var x1 := wr.position.x + wr.size.x - inset_px
	var y1 := wr.position.y + wr.size.y - inset_px
	# Guard against tiny rooms collapsing the loop.
	if x1 <= x0:
		var cx := wr.position.x + wr.size.x * 0.5
		x0 = cx; x1 = cx
	if y1 <= y0:
		var cy := wr.position.y + wr.size.y * 0.5
		y0 = cy; y1 = cy
	return [
		Vector2(x0, y0), Vector2(x1, y0),
		Vector2(x1, y1), Vector2(x0, y1),
	]
