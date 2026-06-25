extends Control
# Full-screen heist briefing — shown between floors like a dossier/mission brief.
# Draws a dark overlay with animated text showing:
#   - TARGET: name + location
#   - OBJECTIVE: macguffin description
#   - INTEL: 2–3 floor rumors
#   - COMPLICATIONS: current floor complication
#   - [ENTER to begin]
#
# Add as child of a CanvasLayer. Call show_briefing() to activate.

signal briefing_dismissed

var _active          := false
var _full_text       := ""
var _revealed_chars  := 0
var _reveal_timer    := 0.0
const CHAR_DELAY     := 0.025  # seconds per character

# Vignette animation
var _fade_in_t       := 0.0
const FADE_IN_DUR    := 0.35

# Stamp animation
var _stamp_t         := 0.0
const STAMP_DELAY    := 0.4  # wait before stamp appears
var _stamp_visible   := false

var _font: Font       = null
var _dismiss_hint_t  := 0.0  # blink timer for hint

# Sections to render (built when showing)
var _sections: Array[Dictionary] = []
# Each section: { label: String, text: String, color: Color, size: int }

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_font = ThemeDB.fallback_font

func show_briefing() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if not gm:
		briefing_dismissed.emit()
		return

	# Gather narrative data
	var narrative: Node = null
	for child in get_tree().get_nodes_in_group("run_narrative"):
		narrative = child
		break

	_sections.clear()

	# Header section (no label)
	_sections.append({
		"label": "",
		"text":  "CLASSIFIED INTELLIGENCE FILE",
		"color": Color(0.80, 0.72, 0.50),
		"size":  11,
		"gap":   18,
	})

	if narrative:
		_sections.append({
			"label": "TARGET",
			"text":  "%s" % narrative.target_name,
			"color": Color(0.95, 0.85, 0.55),
			"size":  15,
			"gap":   6,
		})
		_sections.append({
			"label": "LOCATION",
			"text":  narrative.target_location,
			"color": Color(0.80, 0.75, 0.55),
			"size":  13,
			"gap":   6,
		})
		_sections.append({
			"label": "OBJECTIVE",
			"text":  "Retrieve %s" % narrative.macguffin,
			"color": Color(0.70, 0.90, 0.70),
			"size":  13,
			"gap":   16,
		})
		_sections.append({
			"label": "BRIEFING",
			"text":  narrative.story_hook,
			"color": Color(0.85, 0.82, 0.70),
			"size":  12,
			"gap":   16,
		})

		# Floor rumors
		var rumors: Array = narrative.get_floor_rumors(gm.current_floor)
		for i in range(rumors.size()):
			_sections.append({
				"label": "INTEL %d" % (i + 1),
				"text":  rumors[i],
				"color": Color(0.65, 0.80, 0.65),
				"size":  11,
				"gap":   5,
			})
		if not rumors.is_empty():
			# spacing after intel block
			_sections[-1]["gap"] = 16
	else:
		# Fallback using GameManager data
		_sections.append({
			"label": "FLOOR",
			"text":  gm.get_floor_name(),
			"color": Color(0.95, 0.85, 0.55),
			"size":  15,
			"gap":   6,
		})
		var pool: Array = GameManager.MISSION_BRIEFS.get(gm.current_floor, [])
		if not pool.is_empty():
			var rng := RandomNumberGenerator.new()
			rng.seed = gm.run_seed + gm.current_floor * 3571
			_sections.append({
				"label": "BRIEFING",
				"text":  pool[rng.randi() % pool.size()],
				"color": Color(0.85, 0.82, 0.70),
				"size":  12,
				"gap":   16,
			})

	# Complication
	if gm.floor_complication != "CLEAR":
		_sections.append({
			"label": "COMPLICATION",
			"text":  "%s — %s" % [gm.complication_name, gm.complication_desc],
			"color": Color(1.00, 0.65, 0.30),
			"size":  12,
			"gap":   6,
		})

	# Objective
	if gm.floor_objective != "NONE":
		_sections.append({
			"label": "OPTIONAL",
			"text":  "%s — %s  (+%d gp)" % [gm.floor_objective_name, gm.floor_objective_desc, gm.floor_objective_bonus],
			"color": Color(0.55, 0.90, 0.65),
			"size":  11,
			"gap":   6,
		})

	# Compute full text for char-by-char reveal
	_full_text = ""
	for sec in _sections:
		if not sec.label.is_empty():
			_full_text += sec.label + ":  "
		_full_text += sec.text + "\n"

	_revealed_chars = 0
	_reveal_timer   = 0.0
	_fade_in_t      = 0.0
	_stamp_t        = 0.0
	_stamp_visible  = false
	_dismiss_hint_t = 0.0
	_active         = true
	visible         = true
	queue_redraw()

func _process(delta: float) -> void:
	if not _active:
		return

	_fade_in_t = minf(_fade_in_t + delta / FADE_IN_DUR, 1.0)
	_dismiss_hint_t += delta

	# Stamp appears after delay
	if not _stamp_visible:
		_stamp_t += delta
		if _stamp_t >= STAMP_DELAY:
			_stamp_visible = true

	# Reveal text characters
	if _revealed_chars < _full_text.length():
		_reveal_timer += delta
		var chars_to_reveal := int(_reveal_timer / CHAR_DELAY)
		if chars_to_reveal > 0:
			_revealed_chars = mini(_revealed_chars + chars_to_reveal, _full_text.length())
			_reveal_timer = fmod(_reveal_timer, CHAR_DELAY)

	queue_redraw()

func _input(event: InputEvent) -> void:
	if not _active:
		return
	var dismiss := false
	if event is InputEventKey and event.pressed and not event.echo:
		dismiss = true
	elif event is InputEventJoypadButton and event.pressed:
		dismiss = true
	if dismiss:
		# Skip reveal or dismiss
		if _revealed_chars < _full_text.length():
			_revealed_chars = _full_text.length()
		else:
			_active  = false
			visible  = false
			briefing_dismissed.emit()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not _active:
		return
	var vp := get_viewport_rect().size
	var alpha: float = _fade_in_t

	# Dark vignette background
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.03, 0.06, 0.96 * alpha))

	# Warm parchment inner panel
	var pw := minf(640.0, vp.x - 80.0)
	var ph := minf(520.0, vp.y - 80.0)
	var px := (vp.x - pw) * 0.5
	var py := (vp.y - ph) * 0.5
	var panel_rect := Rect2(px, py, pw, ph)

	# Panel shadow
	draw_rect(Rect2(px + 6, py + 6, pw, ph), Color(0.0, 0.0, 0.0, 0.55 * alpha))
	# Panel background — warm parchment tone
	draw_rect(panel_rect, Color(0.14, 0.11, 0.08, 0.97 * alpha))
	# Border
	_draw_border(panel_rect, Color(0.45, 0.35, 0.18, 0.70 * alpha), 2.0)
	# Inner border inset
	var inset := 5.0
	_draw_border(
		Rect2(px + inset, py + inset, pw - inset * 2.0, ph - inset * 2.0),
		Color(0.35, 0.27, 0.14, 0.40 * alpha), 1.0
	)

	if _font == null:
		return

	# "DOSSIER" header
	var header_y := py + 28.0
	var header_x := px + pw * 0.5
	var header_str := "— DOSSIER —"
	var header_w := _font.get_string_size(header_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(_font, Vector2(header_x - header_w * 0.5, header_y),
		header_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.65, 0.55, 0.30, 0.85 * alpha))

	# Horizontal rule below header
	draw_line(
		Vector2(px + 20.0, header_y + 10.0),
		Vector2(px + pw - 20.0, header_y + 10.0),
		Color(0.40, 0.30, 0.15, 0.50 * alpha), 1.0
	)

	# Floor badge (top right of panel)
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		var floor_str := "FLOOR %d / %d" % [gm.current_floor, gm.MAX_FLOORS]
		var fs_w := _font.get_string_size(floor_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(_font, Vector2(px + pw - fs_w - 14.0, py + 14.0),
			floor_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.50, 0.42, 0.25, 0.65 * alpha))

	# Content area — render revealed text by section
	var content_x := px + 32.0
	var content_y := header_y + 26.0
	var content_w := pw - 64.0
	var chars_remaining := _revealed_chars

	for sec in _sections:
		var label: String = sec.get("label", "")
		var text: String  = sec.get("text", "")
		var sec_color: Color = sec.get("color", Color(0.85, 0.82, 0.70))
		var fsize: int    = sec.get("size", 12)
		var gap: float    = sec.get("gap", 10.0)
		sec_color.a      *= alpha

		# Build full section string
		var full_line := ""
		if not label.is_empty():
			full_line = label + ":  " + text
		else:
			full_line = text

		if chars_remaining <= 0:
			break

		var reveal_count := mini(chars_remaining, full_line.length())
		var shown := full_line.substr(0, reveal_count)
		chars_remaining -= reveal_count

		# Draw label part in slightly dimmer color
		if not label.is_empty():
			var label_part := label + ":  "
			var label_w := _font.get_string_size(label_part, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			var label_col := Color(sec_color.r * 0.75, sec_color.g * 0.75, sec_color.b * 0.75, sec_color.a)
			draw_string(_font, Vector2(content_x, content_y),
				label_part.substr(0, mini(label_part.length(), shown.length())),
				HORIZONTAL_ALIGNMENT_LEFT, int(content_w), fsize, label_col)
			if shown.length() > label_part.length():
				var val_str := shown.substr(label_part.length())
				draw_string(_font, Vector2(content_x + label_w, content_y),
					val_str, HORIZONTAL_ALIGNMENT_LEFT, int(content_w - label_w), fsize, sec_color)
		else:
			draw_string(_font, Vector2(content_x, content_y),
				shown, HORIZONTAL_ALIGNMENT_LEFT, int(content_w), fsize, sec_color)

		content_y += fsize + gap

		if content_y > py + ph - 50.0:
			break  # don't overflow panel

	# Red CLASSIFIED stamp — appears after delay, slight rotation
	if _stamp_visible:
		var stamp_str := "CLASSIFIED"
		var stamp_size := 28
		var sw := _font.get_string_size(stamp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, stamp_size).x
		var stamp_pos := Vector2(px + pw - sw - 40.0, py + 80.0)
		var stamp_alpha := minf((_stamp_t - STAMP_DELAY) * 3.0, 1.0) * alpha
		# Draw slightly tilted by offsetting two draws
		draw_string(_font, stamp_pos + Vector2(1.5, -1.5),
			stamp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, stamp_size,
			Color(0.70, 0.05, 0.05, stamp_alpha * 0.5))
		draw_string(_font, stamp_pos,
			stamp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, stamp_size,
			Color(0.90, 0.08, 0.08, stamp_alpha * 0.85))
		# Stamp border rect
		_draw_border(
			Rect2(stamp_pos.x - 8.0, stamp_pos.y - stamp_size, sw + 16.0, stamp_size + 10.0),
			Color(0.85, 0.08, 0.08, stamp_alpha * 0.60), 2.0
		)

	# Dismiss hint (blink)
	var hint_alpha := (0.5 + 0.5 * sin(_dismiss_hint_t * 3.0)) * alpha
	if _revealed_chars < _full_text.length():
		var skip_str := "[ any key — skip ]"
		var sk_w := _font.get_string_size(skip_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(_font, Vector2(vp.x * 0.5 - sk_w * 0.5, py + ph - 18.0),
			skip_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.50, 0.45, 0.30, hint_alpha * 0.7))
	else:
		var begin_str := "[ any key — BEGIN THE JOB ]"
		var bw := _font.get_string_size(begin_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(_font, Vector2(vp.x * 0.5 - bw * 0.5, py + ph - 20.0),
			begin_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.75, 0.70, 0.45, hint_alpha))

func _draw_border(rect: Rect2, color: Color, width: float) -> void:
	var tl := rect.position
	var br := rect.position + rect.size
	draw_line(tl, Vector2(br.x, tl.y), color, width)
	draw_line(Vector2(br.x, tl.y), br, color, width)
	draw_line(br, Vector2(tl.x, br.y), color, width)
	draw_line(Vector2(tl.x, br.y), tl, color, width)
