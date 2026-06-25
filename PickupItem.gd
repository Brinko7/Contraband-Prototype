extends Node2D

const PICKUP_RANGE = 10.0

@export var item_type := 0  # 0=COIN 1=SMOKE 2=DART

const COLORS := {
	0: Color(0.95, 0.80, 0.10),
	1: Color(0.55, 0.90, 0.45),
	2: Color(0.30, 0.70, 0.95),
	4: Color(1.00, 0.95, 0.70),
	5: Color(0.55, 0.35, 0.90),
	6: Color(0.30, 0.20, 0.55),
}

const _PICKUP_TEX := {
	0: "res://sprites/pickup_coin.png",
	1: "res://sprites/pickup_potion.png",
	2: "res://sprites/pickup_potion.png",
	4: "res://sprites/pickup_potion.png",
	5: "res://sprites/pickup_potion.png",
	6: "res://sprites/pickup_potion.png",
}
static var _pickup_tex_cache := {}

var _bob_t     := 0.0
var _collected := false

func _pickup_tex() -> Texture2D:
	var path: String = _PICKUP_TEX.get(item_type, "")
	if path == "":
		return null
	if _pickup_tex_cache.has(path):
		return _pickup_tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_pickup_tex_cache[path] = tex
	return tex

func _ready():
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta):
	if _collected:
		return
	_bob_t += delta
	var player = get_tree().get_first_node_in_group("player")
	if player and global_position.distance_to(player.global_position) <= PICKUP_RANGE:
		_collect(player)
	queue_redraw()

func _collect(player: Node2D):
	_collected = true
	var count: int = 2 if GameManager.has_passive("SCAVENGER") else 1
	if player.has_method("add_item"):
		player.add_item(item_type, count)
	AudioManager.loot_collect()
	queue_free()

func _draw():
	var col: Color = COLORS.get(item_type, Color.WHITE)
	var bob := sin(_bob_t * 3.5) * 1.5
	# Colored glow ring — kept as FX so item types stay distinguishable by aura.
	draw_arc(Vector2(0, bob), 6.5, 0, TAU, 16, Color(col.r, col.g, col.b, 0.35), 1.0)
	var tex: Texture2D = _pickup_tex()
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2(-8, bob - 10), Vector2(16, 16)), false)
		return
	# Fallback dot
	draw_circle(Vector2(0, bob), 3.5, col)
