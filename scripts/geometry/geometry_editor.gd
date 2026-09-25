extends Node
## Owns active geometry and its undo history. UI listens to changed/history_changed.
signal changed
signal history_changed
var shape
var history := UndoRedo.new()

func set_shape(model) -> void:
	history.clear_history()
	shape = model
	history_changed.emit()

func edit_coordinate(value: float, vertex: int, axis: int) -> void:
	if not is_finite(value) or shape.vertices[vertex][axis] == value:
		return
	var after: Array[Vector4] = shape.vertices.duplicate()
	after[vertex][axis] = value
	commit("Edit V%d" % vertex, after)

func reset_vertices(all_vertices: bool, selected: int) -> void:
	var after: Array[Vector4] = shape.vertices.duplicate()
	if all_vertices:
		after = shape.original_vertices.duplicate()
	else:
		after[selected] = shape.original_vertices[selected]
	if after != shape.vertices:
		commit("Reset vertices", after)

## Snapshot arrays are copied both on capture and restore to prevent aliasing.
func commit(title: String, after: Array[Vector4]) -> void:
	history.create_action(title)
	history.add_do_method(restore.bind(after))
	history.add_undo_method(restore.bind(shape.vertices.duplicate()))
	history.commit_action()
	history_changed.emit()

func restore(points: Array[Vector4]) -> void:
	shape.vertices = points.duplicate()
	changed.emit()

func undo() -> void:
	if history.has_undo():
		history.undo()
	history_changed.emit()

func redo() -> void:
	if history.has_redo():
		history.redo()
	history_changed.emit()

func _exit_tree() -> void:
	history.free()
