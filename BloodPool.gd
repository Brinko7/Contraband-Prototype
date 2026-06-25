extends Node2D

# Persistent blood pool — fades very slowly over 12s
const _DUR:   float = 12.0
const _DROPS: int   = 7

var _timer:  float = _DUR
var _drops:  Array = []   # {offset: Vector2, r: float}

func _ready():
	for i in range(_DROPS):
		_drops.append({
			"offset": Vector2(randf_range(-7.0, 7.0), randf_range(-4.0, 4.0)),
			"r":      randf_range(2.5, 5.5),
		})
	# Register as evidence for EvidenceSystem
	var es = get_tree().get_first_node_in_group("evidence_system") if get_tree() else null
	if es == null:
		es = get_tree().root.find_child("EvidenceSystem", true, false) if get_tree() else null
	if es and es.has_method("add_evidence"):
		es.add_evidence("BLOOD_POOL", global_position)

func _process(delta: float):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	queue_redraw()

func _draw():
	var t: float    = _timer / _DUR
	# Slow fade — bright red → dark maroon → gone
	var fade: float = t * t * 0.70
	var r_val: float = 0.55 + t * 0.35
	var pool_col := Color(r_val, 0.04, 0.04, fade)
	for d in _drops:
		draw_circle(d["offset"], d["r"], pool_col)
	# Central pool slightly larger
	draw_circle(Vector2.ZERO, 6.0, pool_col)
