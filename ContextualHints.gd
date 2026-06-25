## ContextualHints.gd  (V13)
## Autoload-style singleton spawned by World.gd.
## Tracks first-time player actions and shows floating hint bubbles.
## Hints fire ONCE per run — a persistent "shown" set prevents repeats.
extends Node

# ── Hint definitions ──────────────────────────────────────────────────────────
const HINTS: Dictionary = {
	"first_guard_nearby": {
		"text":  "SHIFT to sneak — sneaking lowers detection speed",
		"color": Color(0.70, 0.85, 0.95),
		"dist":  80.0,
	},
	"first_loot_seen": {
		"text":  "Walk over loot to collect it.  F to take down nearby guards.",
		"color": Color(0.95, 0.80, 0.30),
		"dist":  50.0,
	},
	"first_shadow": {
		"text":  "Dark areas reduce guard detection radius",
		"color": Color(0.45, 0.35, 0.75),
		"dist":  24.0,
	},
	"first_hiding_spot": {
		"text":  "E to hide inside — guards will walk right past you",
		"color": Color(0.60, 0.80, 0.55),
		"dist":  28.0,
	},
	"first_locked_door": {
		"text":  "E to pick the lock — or find the Captain's key",
		"color": Color(0.85, 0.65, 0.35),
		"dist":  24.0,
	},
	"first_alert": {
		"text":  "Guard alerted! Stay out of sight and wait for suspicion to drop",
		"color": Color(1.0, 0.35, 0.15),
		"dist":  0.0,
	},
	"first_evidence": {
		"text":  "Bodies and blood raise guard alertness on the next floor",
		"color": Color(0.90, 0.20, 0.20),
		"dist":  0.0,
	},
	"low_hp": {
		"text":  "HP critical! Reach the exit to escape — or buy a Healer's Salve",
		"color": Color(1.0, 0.45, 0.20),
		"dist":  0.0,
	},
}

var _shown: Dictionary = {}   # id → true
var _scan_t: float     = 0.0
const _SCAN_INTERVAL := 1.0

func _ready() -> void:
	add_to_group("contextual_hints")
	_shown.clear()

func _process(delta: float) -> void:
	_scan_t += delta
	if _scan_t < _SCAN_INTERVAL:
		return
	_scan_t = 0.0
	_scan()

func _scan() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var ppos: Vector2 = player.global_position

	# First guard nearby
	if not _shown.has("first_guard_nearby"):
		for guard in get_tree().get_nodes_in_group("guards"):
			if ppos.distance_to(guard.global_position) < HINTS["first_guard_nearby"].dist:
				_show("first_guard_nearby", ppos)
				break

	# First loot seen
	if not _shown.has("first_loot_seen"):
		for loot in get_tree().get_nodes_in_group("loot_targets"):
			if ppos.distance_to(loot.global_position) < HINTS["first_loot_seen"].dist:
				_show("first_loot_seen", ppos)
				break

	# First hiding spot
	if not _shown.has("first_hiding_spot"):
		for hs in get_tree().get_nodes_in_group("hiding_spots"):
			if ppos.distance_to(hs.global_position) < HINTS["first_hiding_spot"].dist:
				_show("first_hiding_spot", ppos)
				break

	# First locked door
	if not _shown.has("first_locked_door"):
		for door in get_tree().get_nodes_in_group("locked_doors"):
			if ppos.distance_to(door.global_position) < HINTS["first_locked_door"].dist:
				_show("first_locked_door", ppos)
				break

	# Player HP critical
	if not _shown.has("low_hp"):
		var hp: int     = int(GameManager.player_hp if GameManager.get("player_hp") != null else 2)
		var max_hp: int = int(GameManager.player_max_hp if GameManager.get("player_max_hp") != null else 3)
		if hp == 1 and max_hp >= 2:
			_show("low_hp", ppos)

	# Alert fired
	if not _shown.has("first_alert"):
		for guard in get_tree().get_nodes_in_group("guards"):
			if guard.get("alert_state") == 2:  # ALERT
				_show("first_alert", ppos)
				break

# ── Called externally when evidence is discovered ────────────────────────────
func notify_evidence() -> void:
	if not _shown.has("first_evidence"):
		var player = get_tree().get_first_node_in_group("player")
		var pos: Vector2 = player.global_position if player else Vector2(384, 300)
		_show("first_evidence", pos)

# ── Show a floating hint via DicePopup-style node ────────────────────────────
func _show(id: String, pos: Vector2) -> void:
	if _shown.has(id):
		return
	_shown[id] = true

	var hint_data: Dictionary = HINTS.get(id, {})
	var text:  String = hint_data.get("text", id)
	var color: Color  = hint_data.get("color", Color.WHITE)

	# Spawn a persistent hint popup (stays longer than DicePopup)
	var popup := Node2D.new()
	popup.global_position = pos + Vector2(0, -32)
	var hint_script := GDScript.new()
	hint_script.source_code = """extends Node2D
var _t := 0.0
const DUR := 4.5
var msg := \"\"
var col := Color.WHITE
func _process(d):
	_t += d
	if _t > DUR:
		queue_free()
	position.y -= d * 6.0
	queue_redraw()
func _draw():
	var a := clampf(1.0 - (_t / DUR) * (_t / DUR), 0.0, 1.0) * clampf(_t * 4.0, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var sw := 8.0 * msg.length()
	draw_rect(Rect2(-sw * 0.5 - 5, -13, sw + 10, 16), Color(0.0, 0.0, 0.0, a * 0.65))
	draw_string(font, Vector2(-sw * 0.5 + 1, 0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0, 0, 0, a * 0.8))
	draw_string(font, Vector2(-sw * 0.5, -1), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(col.r, col.g, col.b, a))
"""
	popup.set_script(hint_script)
	popup.set("msg", text)
	popup.set("col", color)
	if get_tree():
		get_tree().root.add_child(popup)
