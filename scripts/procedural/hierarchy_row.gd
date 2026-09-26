extends Button
## A row is both a selector and drag source/drop target; World cannot be dragged.
var controller
var node_id := 0
func _get_drag_data(_position: Vector2) -> Variant:
	if node_id == 0: return null
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return {"hierarchy": controller, "id": node_id}
func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("hierarchy") == controller and controller.graph.can_parent(data.get("id", 0), node_id)
func _drop_data(_position: Vector2, data: Variant) -> void:
	controller.reparent_node(data.id, node_id)
