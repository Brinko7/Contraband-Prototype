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
			_duration = 0.35
		"VENOM_NEEDLE", "SHIV", "STILETTO":
			_duration = 0.30
		"SPEAR":
			_duration = 0.30
		"LONGSWORD", "BROADSWORD", "BLADESONG":
			_duration = 0.28
		"WAND":
			_duration = 0.40
		_:
			_duration = 0.25
	_timer = _duration

func _process(delta):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw():
	var t: float = clamp(_timer / _duration, 0.0, 1.0)   # 1 = start, 0 = end
	var fade: float = t

	# Pick color based on weapon type and silent
	var col: Color
	match _weapon_id:
		"SHADOW_BLADE", "GHOST_BLADE", "VOID_REAPER", "SMOKE_BLADE":
			col = Color(0.55, 0.20, 0.90, fade * 0.75)
		"BLADESONG":
			col = Color(0.40, 0.75, 1.00, fade * 0.85)
		"WAND":
			col = Color(0.65, 0.25, 1.00, fade * 0.90)
		"LONGSWORD", "BROADSWORD":
			col = Color(0.90, 0.85, 0.50, fade * 0.85)
		"SPEAR":
			col = Color(0.75, 0.60, 0.30, fade * 0.85)
		_:
			if _silent:
				col = Color(0.25, 0.80, 0.65, fade * 0.80)
			else:
				col = Color(1.00, 0.50, 0.15, fade * 0.80)

	match _weapon_id:
		"CROSSBOW", "REPEATING_CROSSBOW", "SILENT_BOLT":
			# Thin line projectile extending 200px in facing direction
			var length: float = 200.0 * (1.0 - (1.0 - t) * 0.4)
			draw_line(Vector2.ZERO, _direction * length, col, 1.5)
			# Small tip circle
			draw_circle(_direction * length, 2.0, col)

		"VENOM_NEEDLE", "SHIV":
			# Dashed arc trajectory (throw)
			var arc_len := 120.0
			var perp := _direction.rotated(PI * 0.5)
			var ctrl_pt: Vector2 = _direction * arc_len * 0.6 + perp * 20.0
			var steps := 8
			var prev := Vector2.ZERO
			for i in range(1, steps + 1):
				var bt: float = float(i) / float(steps)
				var pt: Vector2 = (1.0 - bt) * (1.0 - bt) * Vector2.ZERO \
					+ 2.0 * (1.0 - bt) * bt * ctrl_pt \
					+ bt * bt * (_direction * arc_len)
				if i % 2 == 0:
					draw_line(prev, pt, col, 1.2)
				prev = pt

		"STILETTO", "ASSASSIN_FANG":
			# Fast dashed throw arc
			var arc_len2 := 150.0
			var perp2 := _direction.rotated(PI * 0.5)
			var ctrl2: Vector2 = _direction * arc_len2 * 0.5 + perp2 * 15.0
			var steps2 := 10
			var prev2 := Vector2.ZERO
			for i in range(1, steps2 + 1):
				var bt2: float = float(i) / float(steps2)
				var pt2: Vector2 = (1.0 - bt2) * (1.0 - bt2) * Vector2.ZERO \
					+ 2.0 * (1.0 - bt2) * bt2 * ctrl2 \
					+ bt2 * bt2 * (_direction * arc_len2)
				if i % 2 == 0:
					draw_line(prev2, pt2, col, 1.2)
				prev2 = pt2

		"LONGSWORD", "BROADSWORD", "BLADESONG":
			# Wide 140° slash arc
			var radius := 22.0
			var fa := _direction.angle()
			var sweep := deg_to_rad(140.0)
			var arc_start := fa - sweep * 0.5
			var actual_sweep: float = sweep * (0.3 + t * 0.7)
			draw_arc(Vector2.ZERO, radius * (0.6 + t * 0.4), arc_start, arc_start + actual_sweep, 18, col, 3.0)
			draw_circle(_direction * radius, 3.0 * t, col)
			# BLADESONG: second arc slightly offset
			if _weapon_id == "BLADESONG":
				var col2 := Color(0.70, 0.90, 1.00, fade * 0.50)
				draw_arc(Vector2.ZERO, radius * 0.65, arc_start - deg_to_rad(10), arc_start + actual_sweep + deg_to_rad(10), 14, col2, 1.5)

		"SPEAR":
			# Straight thrust: extends 2 tiles then snaps back
			var thrust_len := 34.0 * (0.5 + t * 0.5)
			draw_line(Vector2.ZERO, _direction * thrust_len, col, 3.0)
			draw_circle(_direction * thrust_len, 3.5 * t, col)
			# Crossguard lines
			var perp := _direction.rotated(PI * 0.5)
			draw_line(_direction * 8.0 - perp * 5.0, _direction * 8.0 + perp * 5.0, Color(col.r, col.g, col.b, fade * 0.5), 1.5)

		"WAND":
			# Pulsing orb leaving a glow trail
			var orb_dist := 16.0 * (1.0 - t)
			draw_circle(_direction * orb_dist, 4.0 + (1.0 - t) * 2.0, col)
			draw_arc(_direction * orb_dist, 7.0, 0, TAU, 16, Color(col.r, col.g, col.b, fade * 0.35), 1.5)

		_:
			# Melee sweep arc: 120° in facing direction, radius ~20px
			var radius := 20.0
			var fa := _direction.angle()
			var sweep := deg_to_rad(120.0)
			var arc_start := fa - sweep * 0.5
			# Fade the arc: at t=1 (fresh) full, shrinks and fades
			var actual_sweep: float = sweep * (0.3 + t * 0.7)
			draw_arc(Vector2.ZERO, radius * (0.6 + t * 0.4), arc_start, arc_start + actual_sweep, 16, col, 2.5)
			# Small impact dot at tip
			var tip := _direction * radius
			draw_circle(tip, 2.5 * t, col)
