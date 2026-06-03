extends Control

# Styled item slot box — drawn at bottom-left of HUD

const ITEM_NAMES := {
	0: "Gold Piece",    1: "Alch. Smoke",   2: "Sopor. Dart",
	3: "Silk Rope",     4: "Flash Powder",   5: "Hold Person",
	6: "Silence",       7: "Thieves' Tools", 8: "Shadow Cloak",
	9: "Iron Key",
}
const ITEM_COLORS := {
	0: Color(0.95, 0.80, 0.10), 1: Color(0.55, 0.90, 0.45),
	2: Color(0.30, 0.70, 0.95), 3: Color(0.75, 0.55, 0.95),
	4: Color(1.00, 0.95, 0.70), 5: Color(0.55, 0.35, 0.90),
	6: Color(0.45, 0.30, 0.75), 7: Color(0.70, 0.55, 0.30),
	8: Color(0.55, 0.40, 0.80), 9: Color(0.90, 0.75, 0.20),
}

func _draw():
	var itype:    int    = int(get_meta("item_type",  -1))
	var count:    int    = int(get_meta("item_count",  0))
	var slot_idx: int    = int(get_meta("slot_index",  0))
	var bind:     String = str(get_meta("bind_label", "?"))
	var t:        float  = float(get_meta("hud_t",   0.0))

	var W    := size.x
	var H    := size.y
	var font := ThemeDB.fallback_font

	var is_empty  := itype == -1 or count == 0
	var item_col: Color = ITEM_COLORS.get(itype, Color(0.60, 0.58, 0.55)) \
		if itype != -1 else Color(0.32, 0.30, 0.28)

	# ── Background ────────────────────────────────────────────────────────────
	var bg := Color(0.07, 0.06, 0.10, 0.90) if not is_empty else Color(0.05, 0.05, 0.08, 0.72)
	draw_rect(Rect2(0, 0, W, H), bg, true)

	# Pulse glow when stocked
	if not is_empty:
		var pulse := sin(t * 1.8 + slot_idx * 1.1) * 0.5 + 0.5
		draw_rect(Rect2(0, 0, W, H),
			Color(item_col.r, item_col.g, item_col.b, 0.05 + pulse * 0.04), true)

	# Left accent band (color-codes the item type at a glance)
	draw_rect(Rect2(0, 0, 4, H),
		Color(item_col.r, item_col.g, item_col.b, 0.75 if not is_empty else 0.18), true)

	# Border
	draw_rect(Rect2(0, 0, W, H),
		Color(item_col.r, item_col.g, item_col.b, 0.60 if not is_empty else 0.22), false, 1.0)

	# ── Keybind chip (top-right) ──────────────────────────────────────────────
	var chip_text := "[%s]" % bind
	var chip_w := font.get_string_size(chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 6.0
	draw_rect(Rect2(W - chip_w, 0, chip_w, 14),
		Color(item_col.r, item_col.g, item_col.b, 0.22), true)
	draw_string(font, Vector2(W - chip_w + 3, 11), chip_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 1.0, 1.0, 0.60))

	if is_empty:
		draw_string(font, Vector2(8, H * 0.62), "─  empty  ─",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.36, 0.34, 0.30, 0.45))
		return

	# ── Item name ─────────────────────────────────────────────────────────────
	var name_str: String = ITEM_NAMES.get(itype, "?")
	draw_string(font, Vector2(8, H * 0.60 + 2), name_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(item_col.r, item_col.g, item_col.b, 0.95))

	# ── Count badge (bottom-right) ────────────────────────────────────────────
	var count_str := "×%d" % count
	var cnt_w := font.get_string_size(count_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6.0
	var cnt_x  := W - cnt_w - 2.0
	var cnt_y  := H - 15.0
	draw_rect(Rect2(cnt_x - 2, cnt_y - 1, cnt_w + 2, 14),
		Color(item_col.r, item_col.g, item_col.b, 0.22), true)
	draw_string(font, Vector2(cnt_x, cnt_y + 11), count_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 1.0, 1.0, 0.90))
