extends Control

func _draw() -> void:
	var inv: Node = get_meta("inv_screen")
	if inv and is_instance_valid(inv):
		inv.do_draw(self)
