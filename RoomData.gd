## RoomData.gd
## Data container for a named room instance on the current floor.
## Tracks identity, state, and thematic flavor for each area of the map.
## Created by _register_rooms() in World.gd each floor, consumed by RoomManager.

extends RefCounted
class_name RoomData

# ── Room identity ─────────────────────────────────────────────────────────────
enum RoomType {
	VAULT,
	CAPTAINS_OFFICE,
	ANTECHAMBER,
	ARMORY,
	BARRACKS,
	STOREROOM,
	ENTRY_FOYER,
	SECRET_CHAMBER,
	DUNGEON_CELL,
	TROPHY_HALL,
	SERVANTS_QUARTERS,
	LIBRARY,
	KITCHEN,
}

# How well-guarded this room is — affects danger_level and AI density
enum SecurityLevel { OPEN, GUARDED, RESTRICTED, MAXIMUM }

# Tracks player interaction: have they been here? done something suspicious?
enum RoomState { UNDISTURBED, DISTURBED, COMPROMISED, CLEARED }

# ── Core fields ───────────────────────────────────────────────────────────────
var room_type:      RoomType
var security_level: SecurityLevel
var room_state:     RoomState      = RoomState.UNDISTURBED
var tile_rect:      Rect2i         ## Bounds in tile coordinates (16 px per tile)
var world_rect:     Rect2          ## Bounds in world-pixel coordinates
var room_name:      String
var flavor_text:    String         ## Shown when the player first enters this room

var has_secret:     bool  = false  ## True if a secret passage/chamber is adjacent
var secret_found:   bool  = false  ## Player revealed the secret this floor
var loot_multiplier: float = 1.0   ## Scales loot value spawned here
var guard_count:    int   = 0      ## Number of guards assigned at spawn time
var is_visited:     bool  = false  ## Has the player stepped inside yet?

# ── State transitions ─────────────────────────────────────────────────────────

## Record first entry; called by RoomManager when player moves into this room.
func mark_visited() -> void:
	is_visited = true

## Called when the player does something that might alert guards (combat,
## noise, looting under a guard's vision, etc.).
func mark_disturbed() -> void:
	match room_state:
		RoomState.UNDISTURBED:
			room_state = RoomState.DISTURBED
		RoomState.DISTURBED:
			room_state = RoomState.COMPROMISED
		_:
			pass  # Already compromised / cleared — no further escalation here

## Returns a 0.0–1.0 danger rating combining security tier and current state.
func get_danger_level() -> float:
	# Base from security tier
	var base: float
	match security_level:
		SecurityLevel.OPEN:       base = 0.10
		SecurityLevel.GUARDED:    base = 0.35
		SecurityLevel.RESTRICTED: base = 0.65
		SecurityLevel.MAXIMUM:    base = 0.90
		_:                        base = 0.10

	# Additive penalty for disturbed / compromised state
	var state_penalty: float
	match room_state:
		RoomState.UNDISTURBED: state_penalty = 0.0
		RoomState.DISTURBED:   state_penalty = 0.10
		RoomState.COMPROMISED: state_penalty = 0.25
		RoomState.CLEARED:     state_penalty = -0.10  # guards gone — safer now
		_:                     state_penalty = 0.0

	return clampf(base + state_penalty, 0.0, 1.0)

# ── Factory ───────────────────────────────────────────────────────────────────

## Create a RoomData with sensible defaults for the given type.
## tile_rect is in tile coordinates; world_rect is computed automatically.
## Call this from World._register_rooms().
static func make(type: RoomType, tr: Rect2i) -> RoomData:
	var r := RoomData.new()
	r.room_type = type
	r.tile_rect = tr
	# Convert tile-space rect to world-space (16 px per tile)
	r.world_rect = Rect2(
		Vector2(tr.position.x * 16.0, tr.position.y * 16.0),
		Vector2(tr.size.x    * 16.0, tr.size.y    * 16.0)
	)

	# Fill name, flavor, security, and loot multiplier by room type
	match type:
		RoomType.VAULT:
			r.room_name      = "The Iron Vault"
			r.flavor_text    = "Rows of gilded chests under ward-light. Every footstep echoes."
			r.security_level = SecurityLevel.MAXIMUM
			r.loot_multiplier = 2.0

		RoomType.CAPTAINS_OFFICE:
			r.room_name      = "Commander's Quarters"
			r.flavor_text    = "Maps, correspondence, a half-empty decanter. Someone was here recently."
			r.security_level = SecurityLevel.RESTRICTED
			r.loot_multiplier = 1.4

		RoomType.ANTECHAMBER:
			r.room_name      = "The Antechamber"
			r.flavor_text    = "A waiting room for those who never had to wait."
			r.security_level = SecurityLevel.GUARDED
			r.loot_multiplier = 1.1

		RoomType.ARMORY:
			r.room_name      = "The Armory"
			r.flavor_text    = "Racks of weapons gleam in torchlight. Help yourself."
			r.security_level = SecurityLevel.RESTRICTED
			r.loot_multiplier = 1.2

		RoomType.BARRACKS:
			r.room_name      = "Guard Barracks"
			r.flavor_text    = "Bunk beds, card games, the smell of boot leather."
			r.security_level = SecurityLevel.GUARDED
			r.loot_multiplier = 0.9

		RoomType.STOREROOM:
			r.room_name      = "The Storeroom"
			r.flavor_text    = "Crates, barrels, sacks. Easy to get lost in. Easy to hide."
			r.security_level = SecurityLevel.GUARDED
			r.loot_multiplier = 1.0

		RoomType.ENTRY_FOYER:
			r.room_name      = "Entry Foyer"
			r.flavor_text    = "Two guards at the door and a long walk ahead. You've made worse starts."
			r.security_level = SecurityLevel.GUARDED
			r.loot_multiplier = 0.7

		RoomType.SECRET_CHAMBER:
			r.room_name      = "The Hidden Room"
			r.flavor_text    = "Someone went to great lengths to conceal this."
			r.security_level = SecurityLevel.OPEN   # unguarded but trapped
			r.loot_multiplier = 3.0
			r.has_secret     = true

		RoomType.DUNGEON_CELL:
			r.room_name      = "The Cells"
			r.flavor_text    = "Iron bars. Straw pallets. Someone scratched the days into the wall."
			r.security_level = SecurityLevel.GUARDED
			r.loot_multiplier = 0.5

		RoomType.TROPHY_HALL:
			r.room_name      = "The Trophy Hall"
			r.flavor_text    = "Heads, antlers, stolen crowns. The wealth of conquest on display."
			r.security_level = SecurityLevel.RESTRICTED
			r.loot_multiplier = 1.6

		RoomType.SERVANTS_QUARTERS:
			r.room_name      = "Servants' Hall"
			r.flavor_text    = "Modest quarters. The staff see everything and say nothing — usually."
			r.security_level = SecurityLevel.OPEN
			r.loot_multiplier = 0.6

		RoomType.LIBRARY:
			r.room_name      = "The Scriptorium"
			r.flavor_text    = "Shelves of ledgers, maps, secrets written in ink."
			r.security_level = SecurityLevel.RESTRICTED
			r.loot_multiplier = 1.3

		RoomType.KITCHEN:
			r.room_name      = "The Kitchen"
			r.flavor_text    = "Hot coals, sharp knives, and something very flammable."
			r.security_level = SecurityLevel.OPEN
			r.loot_multiplier = 0.8

		_:
			r.room_name      = "Unknown Room"
			r.flavor_text    = "You're not sure what this place is."
			r.security_level = SecurityLevel.OPEN

	return r
