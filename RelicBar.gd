extends Control
# Bottom-right relic row — shows small colored orbs for each collected relic.

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var relics: Array = GameManager.collected_relics
	if relics.is_empty():
		return
	var orb_r := 5.0
	var gap   := 3.0
	var x := size.x - orb_r
	var y := size.y * 0.5
	for i in range(relics.size() - 1, -1, -1):
		var rdata: Dictionary = GameManager.get_relic_data_by_id(relics[i])
		var col: Color = rdata.get("color", Color(0.85, 0.70, 0.20))
		draw_circle(Vector2(x, y), orb_r + 1.2, Color(col.r, col.g, col.b, 0.20))
		draw_circle(Vector2(x, y), orb_r,       Color(col.r, col.g, col.b, 0.80))
		draw_circle(Vector2(x, y), orb_r * 0.40, Color(1, 1, 1, 0.55))
		x -= (orb_r * 2.0 + gap)
		if x < 0:
			break
