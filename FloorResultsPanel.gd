## FloorResultsPanel.gd  (V13)
## Full-screen overlay shown when the player escapes a floor.
## Displays GHOST/CLEAN/MESSY/BLOODY rating, evidence count,
## bonus GP and rep. Auto-advances after _DISPLAY_DUR seconds (any key skips).
extends CanvasLayer

signal panel_dismissed

const _DISPLAY_DUR := 4.5
const _FADE_DUR    := 0.6

var _timer      := 0.0
var _fading     := false
var _fade_t     := 0.0
var _callback: Callable
var _data: Dictionary = {}

# ── Layout nodes ───────────────────────────────────────────────────────────────
var _root_ctrl: Control

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func setup(rating_data: Dictionary, on_done: Callable) -> void:
	_data     = rating_data
	_callback = on_done
	_populate_ui()
	_timer = 0.0

# ── Build the panel skeleton (called once in _ready) ──────────────────────────
func _build_ui() -> void:
	_root_ctrl = Control.new()
	_root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root_ctrl)

	# Semi-opaque backdrop
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.04, 0.06, 0.88)
	_root_ctrl.add_child(bg)

	# Centred card
	var card := PanelContainer.new()
	card.anchor_left   = 0.5; card.anchor_right  = 0.5
	card.anchor_top    = 0.5; card.anchor_bottom = 0.5
	card.offset_left   = -200.0; card.offset_right  = 200.0
	card.offset_top    = -150.0; card.offset_bottom = 150.0
	_root_ctrl.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Add labelled rows — populated later in _populate_ui
	for tag in ["header", "rating_label", "divider", "evidence_row",
				"gp_row", "rep_row", "heat_row", "divider2", "hint"]:
		var lbl := Label.new()
		lbl.name = tag
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13 if tag in ["header", "rating_label"] else 11)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lbl)

func _populate_ui() -> void:
	if _root_ctrl == null:
		return
	var rating: String  = _data.get("rating",     "???")
	var color:  Color   = _data.get("color",      Color.WHITE)
	var total:  int     = _data.get("total",      0)
	var found:  int     = _data.get("discovered", 0)
	var bodies: int     = _data.get("bodies",     0)
	var gp:     int     = _data.get("bonus_gp",   0)
	var rep:    int     = _data.get("rep_bonus",  0)
	var heat:   float   = _data.get("heat_bonus", 0.0)

	# Rating flavor
	var flavor := match_flavor(rating)

	_set_label("header",       "— FLOOR CLEARED —",          Color(0.85, 0.80, 0.60))
	_set_label("rating_label", rating + "  " + flavor,       color)
	_set_label("divider",      "─────────────────────",       Color(0.35, 0.35, 0.35))
	_set_label("evidence_row", "Evidence found:  %d / %d   Bodies: %d" % [found, total, bodies],
		Color(0.75, 0.75, 0.75))
	var gp_col := Color(0.30, 0.90, 0.50) if gp > 0 else (Color(0.6,0.6,0.6) if gp == 0 else Color(0.9,0.25,0.25))
	_set_label("gp_row",  "Bonus gold:  %+d gp" % gp,        gp_col)
	var rep_col := Color(0.40, 0.80, 1.0) if rep >= 0 else Color(1.0, 0.35, 0.20)
	_set_label("rep_row", "Reputation:  %+d" % rep,           rep_col)
	var heat_col := Color(1.0, 0.35, 0.15) if heat > 0.5 else Color(0.65, 0.90, 0.65)
	_set_label("heat_row","Guard heat:  +%.0f%%" % (heat * 100.0), heat_col)
	_set_label("divider2", "─────────────────────",           Color(0.35, 0.35, 0.35))
	_set_label("hint",    "Press any key to continue...",     Color(0.50, 0.50, 0.50))

func match_flavor(rating: String) -> String:
	match rating:
		"GHOST":  return "✦ Not a trace left behind."
		"CLEAN":  return "✔ Barely noticed."
		"MESSY":  return "⚠ They know someone was here."
		"BLOODY": return "☠ The fortress is on high alert."
		_:        return ""

func _set_label(node_name: String, text: String, color: Color) -> void:
	var lbl := _root_ctrl.find_child(node_name, true, false) as Label
	if lbl:
		lbl.text    = text
		lbl.modulate = color

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _fading:
		_fade_t += delta
		var alpha := 1.0 - clampf(_fade_t / _FADE_DUR, 0.0, 1.0)
		_root_ctrl.modulate = Color(1, 1, 1, alpha)
		if _fade_t >= _FADE_DUR:
			_dismiss()
		return

	_timer += delta
	# Progress bar / timer hint update
	var remaining := _DISPLAY_DUR - _timer
	var hint_lbl := _root_ctrl.find_child("hint", true, false) as Label
	if hint_lbl:
		hint_lbl.text = "Press any key to continue...  (%.0f)" % maxf(remaining, 0.0)
	if _timer >= _DISPLAY_DUR:
		_start_fade()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not _fading:
		_start_fade()

func _start_fade() -> void:
	if _fading:
		return
	_fading = true
	_fade_t = 0.0

func _dismiss() -> void:
	panel_dismissed.emit()
	if _callback.is_valid():
		_callback.call()
	queue_free()
