extends Node
# Synthesised sound effects — no external assets required.
# Pre-generates all sounds in _ready() to avoid runtime hitching.

const MIX_RATE = 11025
const POOL_SIZE = 10

var _pool: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}

func _ready():
	for i in POOL_SIZE:
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	# Pre-bake all sounds
	_cache["step_quiet"]   = _tone(280.0, 0.05, 0.20, 0, 180.0, 0.35)
	_cache["step_loud"]    = _tone(110.0, 0.08, 0.50, 1,  60.0, 0.15)
	_cache["detect_tick"]  = _tone(880.0, 0.07, 0.55, 0, 1320.0)
	_cache["alert_blare"]  = _tone(330.0, 0.30, 0.85, 1,  220.0)
	_cache["takedown"]     = _tone( 70.0, 0.14, 0.75, 0,   35.0, 0.20)
	_cache["coin"]         = _tone(1100.0, 0.18, 0.55, 0,  700.0)
	_cache["smoke"]        = _tone( 160.0, 0.22, 0.50, 3,    0.0, 0.75)
	_cache["dart"]         = _tone( 900.0, 0.09, 0.55, 0, 1800.0)
	_cache["rope"]         = _tone( 220.0, 0.10, 0.50, 2,  330.0)
	_cache["loot"]         = _tone( 660.0, 0.22, 0.65, 0,  990.0)
	_cache["ability"]      = _tone(1200.0, 0.18, 0.65, 0,  600.0)
	_cache["ui_nav"]       = _tone(1400.0, 0.03, 0.28)
	_cache["ui_confirm"]   = _tone( 880.0, 0.10, 0.48, 0, 1100.0)
	_cache["body_pickup"]  = _tone( 180.0, 0.12, 0.42, 0,  140.0, 0.22)
	_cache["body_drop"]    = _tone( 120.0, 0.10, 0.42, 0,   90.0, 0.30)
	_cache["reinforce"]    = _tone( 220.0, 0.40, 0.90, 1,  180.0)
	_cache["flash_bang"]   = _tone(1200.0, 0.22, 0.85, 0,  200.0, 0.15)
	_cache["goblin_shriek"]= _tone(1800.0, 0.28, 0.90, 0, 2400.0, 0.08)
	_cache["hold_person"]  = _tone( 280.0, 0.35, 0.70, 1,  220.0, 0.05)
	_cache["ward_trigger"] = _tone( 660.0, 0.30, 0.80, 0,  880.0, 0.10)

func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[randi() % POOL_SIZE]

func _play(key: String, vol_db: float):
	if not _cache.has(key):
		return
	var p = _free_player()
	p.volume_db = vol_db
	p.stream = _cache[key]
	p.play()

# ── Tone generator ─────────────────────────────────────────────────────────────
func _tone(freq: float, dur: float, vol: float = 0.5,
		wave: int = 0, freq2: float = -1.0, noise_mix: float = 0.0) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = 1  # FORMAT_16_BIT
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 1000) + int(dur * 10000)
	for i in n:
		var frac := float(i) / float(n)
		var env: float
		if frac < 0.05:
			env = frac / 0.05
		elif frac > 0.65:
			env = pow((1.0 - frac) / 0.35, 1.4)
		else:
			env = 1.0
		var f: float = lerp(freq, freq2 if freq2 > 0.0 else freq, frac)
		phase += TAU * f / float(MIX_RATE)
		var s: float
		match wave:
			0: s = sin(phase)
			1: s = 1.0 if fmod(phase, TAU) < PI else -1.0
			2: s = fmod(phase, TAU) / PI - 1.0
			_: s = 0.0
		if noise_mix > 0.0:
			s = lerp(s, rng.randf_range(-1.0, 1.0), noise_mix)
		s = clamp(s * env * vol, -1.0, 1.0)
		var sv := int(s * 32767.0)
		data[i * 2 + 0] = sv & 0xFF
		data[i * 2 + 1] = (sv >> 8) & 0xFF
	stream.data = data
	return stream

# ── Public API ─────────────────────────────────────────────────────────────────
func step_quiet():   _play("step_quiet",  -13.0)
func step_loud():    _play("step_loud",    -5.0)
func detect_tick():  _play("detect_tick", -10.0)
func alert_blare():  _play("alert_blare",  -2.0)
func takedown():     _play("takedown",     -5.0)
func coin_throw():   _play("coin",         -9.0)
func smoke_pop():    _play("smoke",        -8.0)
func dart_fire():    _play("dart",         -7.0)
func rope_dash():    _play("rope",        -10.0)
func loot_collect(): _play("loot",         -5.0)
func ability_use():  _play("ability",      -6.0)
func ui_nav():       _play("ui_nav",      -18.0)
func ui_confirm():   _play("ui_confirm",  -12.0)
func body_pickup():  _play("body_pickup", -10.0)
func body_drop():    _play("body_drop",   -10.0)
func reinforcement_alarm(): _play("reinforce",   -1.0)
func flash_bang():          _play("flash_bang",    -4.0)
func goblin_shriek():       _play("goblin_shriek", -2.0)
func hold_person():         _play("hold_person",   -5.0)
func ward_trigger():        _play("ward_trigger",  -3.0)
