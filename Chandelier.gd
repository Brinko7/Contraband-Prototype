extends Node2D

# A hanging chandelier. Player can cut the chain (E interact) to drop it.
# Dropping: creates loud noise burst, stuns guards in 48px radius for 2s,
# extinguishes all torches in 80px radius, creates a SmokeCloud,
# drops loot (1 coin, random chance of gold chain item).
# Guards will investigate the crash site.

const TILE_SIZE := 16
const STUN_RADIUS := 48.0
const TORCH_EXTINGUISH_RADIUS := 80.0
const CRASH_NOISE_RADIUS := 140.0  # very loud
const INTERACT_RANGE := 40.0       # larger range — it's overhead

var _lit: bool = true
var _fallen: bool = false
var _sway_t: float = 0.0
var _cut_t: float = 0.0   # animation timer when cut (0 = idle, counts to 1)
var _fall_progress: float = 0.0
var _chain_cut: bool = false
var _fall_done: bool = false

# Visual state
var _flame_flicker: Array[float] = []

const _CHAND_TEX_PATH := "res://sprites/prop_chandelier.png"
static var _chand_tex: Texture2D = null

var _gm = null

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("light_sources")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _chand_tex == null and ResourceLoader.exists(_CHAND_TEX_PATH):
		_chand_tex = load(_CHAND_TEX_PATH)
	_gm = get_node_or_null("/root/GameManager")
	# Randomise per-candle flicker phases
	for i in range(6):
		_flame_flicker.append(randf() * TAU)

func is_in_range(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= INTERACT_RANGE

func interact(player: Node) -> void:
	if _fallen or _chain_cut:
		return
	_chain_cut = true
	_cut_t = 0.0
	# Start fall animation; actual effects fire when fall completes
	if player.has_method("_popup"):
		player._popup("Cut the chain!", Color(0.90, 0.80, 0.30))

func _process(delta: float) -> void:
	_sway_t += delta

	if _chain_cut and not _fall_done:
		_cut_t += delta
		_fall_progress = minf(_cut_t / 0.6, 1.0)  # 0.6s fall
		if _fall_progress >= 1.0 and not _fallen:
			_fallen = true
			_fall_done = true
			_drop()

	queue_redraw()

func _drop() -> void:
	_lit = false

	# 1. Stun nearby guards
	var guards := get_tree().get_nodes_in_group("guards")
	for guard in guards:
		if guard.global_position.distance_to(global_position) <= STUN_RADIUS:
			if guard.has_method("apply_stun"):
				guard.apply_stun(2.0)
			elif guard.has_method("_on_noise_emitted"):
				# Fallback — make them investigate
				guard._on_noise_emitted(2, global_position)

	# 2. Extinguish nearby torches
	var torches := get_tree().get_nodes_in_group("torches")
	for torch in torches:
		if torch.global_position.distance_to(global_position) <= TORCH_EXTINGUISH_RADIUS:
			if torch.has_method("interact"):
				torch.interact(null)  # snuff it

	# 3. Alert other guards by noise
	for guard in guards:
		if global_position.distance_to(guard.global_position) <= CRASH_NOISE_RADIUS:
			if guard.has_method("_on_noise_emitted"):
				guard._on_noise_emitted(2, global_position)

	# 4. Spawn smoke cloud
	var smoke_script = load("res://SmokeCloud.gd")
	if smoke_script:
		var smoke := Node2D.new()
		smoke.set_script(smoke_script)
		get_tree().root.add_child(smoke)
		smoke.global_position = global_position
		if smoke.has_method("setup"):
			smoke.setup(3.5)  # duration

	# 5. Drop loot — 1 coin always, chance of gold chain
	_spawn_coin_at(global_position + Vector2(randf_range(-6, 6), randf_range(-6, 6)))
	if randf() < 0.35:
		_spawn_gold_chain()

	# 6. Camera shake
	if _gm and _gm.has_method("shake"):
		_gm.shake(6.0, 0.45)

	# 7. Notify levelmap to recalculate light
	for lm in get_tree().get_nodes_in_group("levelmap"):
		lm.queue_redraw()

	# 8. Popup
	var dice_scene = load("res://DicePopup.tscn")
	if dice_scene:
		var p = dice_scene.instantiate()
		p.setup("CHANDELIER FALLS! — CRASH!", Color(1.0, 0.75, 0.10))
		p.global_position = global_position + Vector2(0, -20)
		get_tree().root.add_child(p)

func _spawn_coin_at(pos: Vector2) -> void:
	# Use existing coin pickup pattern from GameManager if present
	if _gm and _gm.has_method("add_gold"):
		_gm.add_gold(15)
	# Visual: small gold dot flung out
	var dice_scene = load("res://DicePopup.tscn")
	if dice_scene:
		var p = dice_scene.instantiate()
		p.setup("+15gp (chain loot)", Color(0.95, 0.80, 0.10))
		p.global_position = pos + Vector2(0, -10)
		get_tree().root.add_child(p)

func _spawn_gold_chain() -> void:
	if _gm and _gm.has_method("add_gold"):
		_gm.add_gold(40)
	var dice_scene = load("res://DicePopup.tscn")
	if dice_scene:
		var p = dice_scene.instantiate()
		p.setup("+40gp (gold chain!)", Color(1.0, 0.90, 0.20))
		p.global_position = global_position + Vector2(0, -28)
		get_tree().root.add_child(p)

func _draw() -> void:
	var t := _sway_t
	var pulse: float = sin(t * 3.0) * 0.5 + 0.5

	if _fallen:
		_draw_wreckage()
		return

	# Sway angle: gentle unless chain cut (increasing lurch)
	var sway_amp := 0.08
	if _chain_cut and not _fallen:
		sway_amp = 0.08 + _fall_progress * 0.5
	var sway := sin(t * 1.2) * sway_amp

	# Fall offset: chandelier moves down as it falls
	var fall_y := _fall_progress * 48.0

	# Apply sway transform
	draw_set_transform(Vector2(0, fall_y), sway, Vector2.ONE)

	# Chain from ceiling to body
	var chain_top := Vector2(0, -32)
	var chain_bot := Vector2(0, -8)
	var chain_col := Color(0.70, 0.65, 0.40)
	if _chain_cut:
		chain_col = Color(0.50, 0.45, 0.25)
	# Draw chain links (segmented line)
	var num_links := 5
	for i in range(num_links):
		var t0 := float(i) / num_links
		var t1 := float(i + 1) / num_links
		var p0 := chain_top.lerp(chain_bot, t0)
		var p1 := chain_top.lerp(chain_bot, t1)
		draw_line(p0, p1, chain_col, 1.5)
		# Link cross-piece
		var mid: Vector2 = (p0 + p1) * 0.5
		draw_line(mid + Vector2(-1.5, 0), mid + Vector2(1.5, 0), chain_col, 1.0)

	# Broken chain end when cut
	if _chain_cut and _fall_progress < 1.0:
		draw_line(chain_bot, chain_bot + Vector2(randf_range(-3, 3), randf_range(0, 4)),
			Color(0.80, 0.70, 0.20, 0.7), 1.0)

	# Chandelier body — 32x24 sprite, 3-frame candle flicker, centred on the hub.
	if _chand_tex != null:
		var frame: int = (int(t * 8.0) % 3) if _lit else 0
		var cmod := Color(1, 1, 1, 1) if _lit else Color(0.55, 0.55, 0.6, 1)
		draw_texture_rect_region(_chand_tex, Rect2(Vector2(-16, -16), Vector2(32, 24)),
			Rect2(frame * 32, 0, 32, 24), cmod)
	else:
		# Central hub / ring
		draw_circle(Vector2(0, -4), 5.0, Color(0.55, 0.50, 0.30))
		draw_arc(Vector2(0, -4), 5.0, 0, TAU, 16, Color(0.80, 0.72, 0.40), 1.2)
		# Candle ring — 6 candles arranged in circle radius 8
		for i in range(6):
			var angle := TAU * float(i) / 6.0
			var cp := Vector2(cos(angle), sin(angle)) * 8.0 + Vector2(0, -4)
			draw_rect(Rect2(cp + Vector2(-1.5, -3), Vector2(3, 6)), Color(0.92, 0.90, 0.82))
			if _lit:
				var flick := sin(t * 8.0 + _flame_flicker[i]) * 0.4 + 0.6
				var fh := 3.5 * flick
				draw_circle(cp + Vector2(0, -3 - fh * 0.5), fh * 0.5, Color(1.0, 0.55, 0.10, 0.70))
				draw_circle(cp + Vector2(0, -3 - fh * 0.35), fh * 0.3, Color(1.0, 0.95, 0.50, 0.95))
			else:
				draw_line(cp + Vector2(0, -3), cp + Vector2(0.5, 0), Color(0.85, 0.82, 0.75, 0.6), 1.0)

	# Glow aura when lit
	if _lit:
		draw_arc(Vector2(0, -4), 14.0, 0, TAU, 24, Color(1.0, 0.85, 0.40, 0.12 + pulse * 0.08), 3.0)

	# Interaction prompt when player is near
	var player := get_tree().get_first_node_in_group("player")
	if player and is_in_range(player.global_position) and not _chain_cut:
		draw_arc(Vector2(0, -4), 16.0, 0, TAU, 20, Color(0.95, 0.88, 0.50, 0.65), 1.5)

	# Reset transform
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_wreckage() -> void:
	var t := _sway_t
	# Fallen ring — tilted, broken
	draw_arc(Vector2(2, 4), 9.0, 0.3, TAU - 0.3, 20, Color(0.55, 0.48, 0.28), 2.0)
	# Scattered chain bits
	var offsets := [Vector2(-10, 2), Vector2(6, -3), Vector2(-4, 8), Vector2(12, 1)]
	for off in offsets:
		draw_line(off, off + Vector2(randf_range(-3,3) + 4, randf_range(-2, 2)), Color(0.65, 0.58, 0.30), 1.2)
	# Wax pools — static blobs
	var wax_positions := [Vector2(-6, 5), Vector2(5, 6), Vector2(-2, 3), Vector2(8, -2),
		Vector2(-8, -1), Vector2(3, -5)]
	for wp in wax_positions:
		draw_circle(wp, 2.2 + sin(t * 0.3 + wp.x) * 0.2, Color(0.88, 0.85, 0.78, 0.70))
	# Broken candles lying flat
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var cp := Vector2(cos(angle), sin(angle)) * 9.0
		var end := cp + Vector2(cos(angle + 1.2), sin(angle + 1.2)) * 5.0
		draw_line(cp, end, Color(0.88, 0.85, 0.78), 1.5)
	# Debris smoke wisp (fades)
	var wisp_alpha := maxf(0.0, 1.0 - _sway_t * 0.3)
	if wisp_alpha > 0.0:
		draw_circle(Vector2(0, -6), 5.0, Color(0.55, 0.55, 0.55, wisp_alpha * 0.30))
