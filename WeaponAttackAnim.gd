extends Node2D

var _weapon_id: String = "NONE"
var _direction: Vector2 = Vector2.RIGHT
var _silent: bool = false
var _timer: float = 0.0
var _duration: float = 0.25

func setup(weapon_id: String, dir: Vector2, silent: bool):
	_weapon_id = weapon_id
	_direction  = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	_silent     = silent
	match weapon_id:
		"CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT":
			_duration = 0.40
		"VENOM_NEEDLE", "SHIV", "STILETTO", "ASSASSIN_FANG":
			_duration = 0.28
		"SPEAR":
			_duration = 0.36
		"LONGSWORD", "BROADSWORD", "BLADESONG":
			_duration = 0.34
		"WAND":
			_duration = 0.45
		_:
			_duration = 0.30
	_timer = _duration

func _process(delta: float):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw():
	var t: float    = clamp(_timer / _duration, 0.0, 1.0)   # 1=start → 0=end
	var fade: float = t

	# Base color — silent attacks are teal, loud are orange-white
	var col: Color = Color(0.25, 0.90, 0.75, fade * 0.90) if _silent else Color(1.00, 0.65, 0.20, fade * 0.90)
	match _weapon_id:
		"SHADOW_BLADE", "GHOST_BLADE", "VOID_REAPER", "SMOKE_BLADE":
			col = Color(0.60, 0.15, 0.95, fade * 0.88)
		"BLADESONG":
			col = Color(0.45, 0.85, 1.00, fade * 0.92)
		"WAND":
			col = Color(0.70, 0.20, 1.00, fade * 0.95)
		"LONGSWORD", "BROADSWORD":
			col = Color(0.95, 0.90, 0.55, fade * 0.90)
		"SPEAR":
			col = Color(0.80, 0.65, 0.30, fade * 0.90)

	match _weapon_id:
		# ── Ranged: crossbows ────────────────────────────────────────────────
		"CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT":
			var bolt_len: float = 260.0 * (1.0 - (1.0 - t) * 0.3)
			# Thick bolt body
			draw_line(Vector2.ZERO, _direction * bolt_len,
				Color(col.r, col.g, col.b, fade * 0.90), 3.0)
			# Bright inner core
			draw_line(Vector2.ZERO, _direction * bolt_len,
				Color(1.0, 1.0, 0.90, fade * 0.60), 1.2)
			# Glowing tip
			draw_circle(_direction * bolt_len, 4.0 * t,
				Color(1.0, 0.95, 0.70, fade))

		# ── Jab / dagger: sharp forward stab ────────────────────────────────
		"SHIV", "STILETTO", "ASSASSIN_FANG", "VENOM_NEEDLE":
			# Blade at full reach at start of animation, retracts as it fades
			var stab_len: float = 32.0 * (0.50 + t * 0.50)
			var perp: Vector2 = _direction.rotated(PI * 0.5)
			# Glow trail behind the blade
			draw_line(Vector2.ZERO, _direction * stab_len * 0.70,
				Color(col.r, col.g, col.b, fade * 0.28), 6.0)
			# Main blade line
			draw_line(Vector2.ZERO, _direction * stab_len, col, 2.8)
			# Bright edge (sharpness highlight)
			draw_line(_direction * stab_len * 0.30, _direction * stab_len,
				Color(1.0, 0.98, 0.88, fade * 0.70), 1.2)
			# Small crossguard
			draw_line(_direction * stab_len * 0.30 - perp * 5.0,
				_direction * stab_len * 0.30 + perp * 5.0,
				Color(col.r, col.g, col.b, fade * 0.55), 2.0)
			# Glinting tip
			draw_circle(_direction * stab_len, 3.5 * t,
				Color(1.0, 0.95, 0.80, fade))

		# ── Broad swords: wide slash ─────────────────────────────────────────
		"LONGSWORD", "BROADSWORD", "BLADESONG":
			var radius := 36.0
			var fa := _direction.angle()
			var sweep := deg_to_rad(150.0)
			var arc_start := fa - sweep * 0.5
			var actual_sweep: float = sweep * (0.25 + t * 0.75)

			# Outer glow ring
			draw_arc(Vector2.ZERO, radius * (0.65 + t * 0.35) + 4.0,
				arc_start, arc_start + actual_sweep, 22,
				Color(col.r, col.g, col.b, fade * 0.30), 6.0)
			# Main arc
			draw_arc(Vector2.ZERO, radius * (0.65 + t * 0.35),
				arc_start, arc_start + actual_sweep, 22, col, 4.5)
			# Inner bright edge
			draw_arc(Vector2.ZERO, radius * (0.65 + t * 0.35) - 2.0,
				arc_start, arc_start + actual_sweep, 18,
				Color(1.0, 1.0, 0.95, fade * 0.50), 1.5)
			# Impact dot at tip
			draw_circle(_direction * radius, 4.5 * t, col)

			if _weapon_id == "BLADESONG":
				var col2 := Color(0.55, 0.92, 1.00, fade * 0.55)
				draw_arc(Vector2.ZERO, radius * 0.55,
					arc_start - deg_to_rad(12), arc_start + actual_sweep + deg_to_rad(12),
					16, col2, 2.5)

		# ── Spear: powerful thrust ────────────────────────────────────────────
		"SPEAR":
			var thrust_len := 52.0 * (0.45 + t * 0.55)
			var perp := _direction.rotated(PI * 0.5)
			# Shaft
			draw_line(Vector2.ZERO, _direction * thrust_len,
				Color(col.r * 0.65, col.g * 0.55, col.b * 0.30, fade * 0.80), 4.0)
			# Blade glow
			draw_line(_direction * (thrust_len * 0.55), _direction * thrust_len, col, 3.5)
			draw_line(_direction * (thrust_len * 0.55), _direction * thrust_len,
				Color(1.0, 0.95, 0.80, fade * 0.55), 1.5)
			# Tip
			draw_circle(_direction * thrust_len, 4.5 * t, col)
			# Crossguard
			draw_line(_direction * (thrust_len * 0.45) - perp * 7.0,
				_direction * (thrust_len * 0.45) + perp * 7.0,
				Color(col.r, col.g, col.b, fade * 0.60), 2.5)

		# ── Wand: pulsing magical orb ─────────────────────────────────────────
		"WAND":
			var orb_dist := 20.0 * (1.0 - t)
			var orb_r    := 6.0 + (1.0 - t) * 3.0
			# Outer glow
			draw_circle(_direction * orb_dist, orb_r + 4.0,
				Color(col.r, col.g, col.b, fade * 0.22))
			# Core
			draw_circle(_direction * orb_dist, orb_r, col)
			# Bright center
			draw_circle(_direction * orb_dist, orb_r * 0.45,
				Color(1.0, 0.95, 1.00, fade * 0.70))
			# Trailing ring
			draw_arc(_direction * orb_dist, orb_r + 2.0, 0, TAU, 20,
				Color(col.r, col.g, col.b, fade * 0.40), 1.8)

		# ── Default: all other melee ──────────────────────────────────────────
		_:
			var radius := 28.0
			var fa := _direction.angle()
			var sweep := deg_to_rad(130.0)
			var arc_start := fa - sweep * 0.5
			var actual_sweep: float = sweep * (0.25 + t * 0.75)

			# Glow halo
			draw_arc(Vector2.ZERO, radius * (0.60 + t * 0.40) + 3.0,
				arc_start, arc_start + actual_sweep, 18,
				Color(col.r, col.g, col.b, fade * 0.25), 5.0)
			# Main arc
			draw_arc(Vector2.ZERO, radius * (0.60 + t * 0.40),
				arc_start, arc_start + actual_sweep, 18, col, 3.5)
			# Inner bright line
			draw_arc(Vector2.ZERO, radius * (0.60 + t * 0.40) - 2.0,
				arc_start, arc_start + actual_sweep, 14,
				Color(1.0, 1.0, 0.95, fade * 0.45), 1.2)
			# Tip
			var tip := _direction * radius
			draw_circle(tip, 3.5 * t, col)
