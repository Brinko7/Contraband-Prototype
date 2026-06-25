extends Node
# Evidence system: guards find clues and escalate response proportionally.
#
# Evidence types:
#   BODY              — large alert escalation (body found)
#   OPEN_LOCK         — moderate — guards go SUSPICIOUS, check vault
#   EXTINGUISHED_TORCH — mild — brief investigation
#   BLOOD_POOL        — moderate — guards go SUSPICIOUS at that location
#   MISSING_ITEM      — mild — "Something's off here"
#   DISTURBED_SHELF   — mild — brief inspection pause

signal evidence_discovered(evidence: Dictionary)
signal heat_changed(new_bonus: float)

enum EvidenceType {
	BODY,
	OPEN_LOCK,
	EXTINGUISHED_TORCH,
	BLOOD_POOL,
	MISSING_ITEM,
	DISTURBED_SHELF,
}

const TYPE_NAMES := {
	EvidenceType.BODY:               "BODY",
	EvidenceType.OPEN_LOCK:          "OPEN_LOCK",
	EvidenceType.EXTINGUISHED_TORCH: "EXTINGUISHED_TORCH",
	EvidenceType.BLOOD_POOL:         "BLOOD_POOL",
	EvidenceType.MISSING_ITEM:       "MISSING_ITEM",
	EvidenceType.DISTURBED_SHELF:    "DISTURBED_SHELF",
}

# Discovery radius — guards within this distance of evidence may find it
const DISCOVERY_RADIUS := 72.0

# How often guards scan for nearby evidence (seconds)
const SCAN_INTERVAL    := 4.0

var evidence_items: Array[Dictionary] = []
var _scan_timer: float = 0.0

func _ready() -> void:
	add_to_group("evidence_system")
	evidence_items.clear()
	_scan_timer = 0.0
	# Wire to GameManager signal so HUD can react
	evidence_discovered.connect(_relay_to_game_manager)

func _relay_to_game_manager(evidence: Dictionary) -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("evidence_found"):
		gm.evidence_found.emit(str(evidence.get("type", "UNKNOWN")))

func _process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL:
		_scan_timer = 0.0
		_guards_scan_for_evidence()

# ── Public API ────────────────────────────────────────────────────────────────

func add_evidence(type: String, world_pos: Vector2) -> void:
	evidence_items.append({
		"type":           type,
		"position":       world_pos,
		"discovered":     false,
		"discovery_time": 0.0,
	})

func discover_evidence(evidence: Dictionary) -> void:
	if evidence.discovered:
		return
	evidence.discovered     = true
	evidence.discovery_time = Time.get_ticks_msec() / 1000.0
	evidence_discovered.emit(evidence)
	_apply_discovery_effect(evidence)
	heat_changed.emit(calculate_heat_bonus())

func get_evidence_count() -> int:
	return evidence_items.size()

func get_discovered_count() -> int:
	var count := 0
	for e in evidence_items:
		if e.discovered:
			count += 1
	return count

func calculate_heat_bonus() -> float:
	# Returns extra alertness multiplier (0.0 = none, 1.0 = significant)
	var bonus := 0.0
	for e in evidence_items:
		if not e.discovered:
			continue
		match e.type:
			"BODY":               bonus += 0.35
			"BLOOD_POOL":         bonus += 0.20
			"OPEN_LOCK":          bonus += 0.15
			"EXTINGUISHED_TORCH": bonus += 0.08
			"MISSING_ITEM":       bonus += 0.07
			"DISTURBED_SHELF":    bonus += 0.05
	return minf(bonus, 1.0)

func get_end_of_floor_rating() -> Dictionary:
	var total     := evidence_items.size()
	var found     := get_discovered_count()
	var bodies    := 0
	var blood     := 0

	for e in evidence_items:
		if e.type == "BODY":
			bodies += 1
		if e.type == "BLOOD_POOL":
			blood += 1

	var rating := ""
	var rating_color := Color.WHITE
	var bonus_gp  := 0
	var rep_bonus := 0

	if total == 0 or found == 0:
		rating       = "GHOST"
		rating_color = Color(0.55, 0.90, 1.00)
		bonus_gp     = 150
		rep_bonus    = 2
	elif bodies == 0 and found == 0:
		rating       = "GHOST"
		rating_color = Color(0.55, 0.90, 1.00)
		bonus_gp     = 150
		rep_bonus    = 2
	elif bodies == 0 and found <= 1:
		rating       = "CLEAN"
		rating_color = Color(0.40, 0.90, 0.55)
		bonus_gp     = 75
		rep_bonus    = 1
	elif bodies <= 1 and found <= 3:
		rating       = "MESSY"
		rating_color = Color(0.95, 0.78, 0.20)
		bonus_gp     = 0
		rep_bonus    = 0
	else:
		rating       = "BLOODY"
		rating_color = Color(0.90, 0.20, 0.20)
		bonus_gp     = 0
		rep_bonus    = -1

	return {
		"rating":       rating,
		"color":        rating_color,
		"total":        total,
		"discovered":   found,
		"bodies":       bodies,
		"bonus_gp":     bonus_gp,
		"rep_bonus":    rep_bonus,
		"heat_bonus":   calculate_heat_bonus(),
	}

func reset() -> void:
	evidence_items.clear()
	_scan_timer = 0.0

# ── Internal ──────────────────────────────────────────────────────────────────

func _apply_discovery_effect(evidence: Dictionary) -> void:
	var gm = get_node_or_null("/root/GameManager")
	match evidence.type:
		"BODY":
			# Already handled by BodyMarker/guard logic — but we can add escalation
			if gm:
				gm.floor_bodies_found += 1
				gm.alert_escalation = mini(gm.alert_escalation + 1, 10)

		"BLOOD_POOL":
			# Guards at that location go suspicious
			_set_nearby_guards_suspicious(evidence.position, 1.5)

		"OPEN_LOCK":
			# Guards go suspicious, start heading toward vault
			_set_nearby_guards_suspicious(evidence.position, 2.0)
			# Optionally trigger GameManager alert escalation
			if gm:
				gm.floor_alerts = mini(gm.floor_alerts + 1, 99)

		"EXTINGUISHED_TORCH":
			# Brief investigation pause — nudge nearby guards to suspicious
			_set_nearby_guards_suspicious(evidence.position, 0.8)

		"MISSING_ITEM":
			# Mild: guards become suspicious in vicinity
			_set_nearby_guards_suspicious(evidence.position, 0.6)

		"DISTURBED_SHELF":
			# Very mild
			_set_nearby_guards_suspicious(evidence.position, 0.5)

func _set_nearby_guards_suspicious(pos: Vector2, intensity: float) -> void:
	# intensity: multiplier for suspicion bar fill
	if not get_tree():
		return
	for guard in get_tree().get_nodes_in_group("guards"):
		var gpos: Vector2 = guard.global_position if guard.has_method("get_global_position") else Vector2.ZERO
		if gpos.distance_to(pos) < DISCOVERY_RADIUS * 3.0:
			# Set suspicious
			if guard.get("alert_state") != null and guard.get("alert_state") < 1:
				guard.set("alert_state", 1)
			# Fill suspicion bar proportionally
			if guard.get("detection") != null:
				var current: float = float(guard.get("detection"))
				guard.set("detection", minf(current + 30.0 * intensity, 100.0))

func _guards_scan_for_evidence() -> void:
	if not get_tree():
		return
	var guards := get_tree().get_nodes_in_group("guards")
	for e in evidence_items:
		if e.discovered:
			continue
		for guard in guards:
			var gpos: Vector2 = guard.global_position if "global_position" in guard else Vector2.ZERO
			if gpos.distance_to(e.position) < DISCOVERY_RADIUS:
				# Guard found evidence
				discover_evidence(e)
				break  # one discovery per evidence per scan
