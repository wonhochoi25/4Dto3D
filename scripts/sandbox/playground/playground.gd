extends Node3D
## Composition root: connect model, editor, projection, renderer, and UI signals.
## To add a shape, implement its generator and register it; this file stays unchanged.
const Registry = preload("res://scripts/io/shape_catalog.gd")
const Projection4D = preload("res://scripts/core/math/projection_4d.gd")
const Editor = preload("res://scripts/sandbox/playground/geometry_editor.gd")
const Renderer = preload("res://scripts/rendering/shape_renderer.gd")
const ProjectionPanel = preload("res://scripts/sandbox/ui/projection_panel.gd")
const VertexPanel = preload("res://scripts/sandbox/ui/vertex_editor_panel.gd")
const Transform4D = preload("res://scripts/core/math/transform_4d.gd")
var model_transform := Transform4D.new()
var transform_cache: Dictionary = {}
var projection := Projection4D.new()
var editor := Editor.new()
var renderer := Renderer.new()
var projection_panel := ProjectionPanel.new()
var vertex_panel := VertexPanel.new()
var cache: Dictionary = {}
var selected := 0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("101722"))
	add_child(editor)
	add_child(renderer)
	add_child(projection_panel)
	add_child(vertex_panel)
	projection_panel.shape_selected.connect(select_shape)
	projection_panel.matrix_applied.connect(apply_projection)
	projection_panel.camera_reset_requested.connect($Camera.reset_view)
	vertex_panel.coordinate_changed.connect(editor.edit_coordinate)
	vertex_panel.vertex_selected.connect(select_vertex)
	vertex_panel.reset_requested.connect(func(all_vertices: bool): editor.reset_vertices(all_vertices, selected))
	vertex_panel.undo_requested.connect(editor.undo)
	vertex_panel.redo_requested.connect(editor.redo)
	editor.changed.connect(refresh_geometry)
	editor.history_changed.connect(refresh_history)
	projection_panel.transform_panel.parameter_changed.connect(change_transform)
	projection_panel.transform_panel.option_changed.connect(change_transform_option)
	projection_panel.transform_panel.reset_requested.connect(reset_transform)
	select_shape(0)

## Cache models so switching preserves edits. History remains scoped to the active model.
func select_shape(index: int) -> void:
	var id: String = Registry.ENTRIES[index]["id"]
	if not cache.has(id):
		cache[id] = Registry.create(index)
	if not transform_cache.has(id):
		transform_cache[id] = Transform4D.new()
	model_transform = transform_cache[id]
	projection_panel.transform_panel.show_transform(model_transform)
	editor.set_shape(cache[id])
	selected = 0
	projection_panel.show_shape(editor.shape, index)
	vertex_panel.show_shape(editor.shape)
	refresh_geometry()

func apply_projection(rows: Array[Vector4]) -> void:
	projection.rows = rows.duplicate()
	refresh_geometry()

func select_vertex(index: int) -> void:
	selected = index
	var transformed := model_transform.transform_vertices(editor.shape.vertices)
	var positions := projection.project(transformed)
	renderer.update_highlight(editor.shape, positions, selected)
	projection_panel.transform_panel.show_vertex(selected, editor.shape.vertices[selected], transformed[selected], positions[selected])

func refresh_geometry() -> void:
	vertex_panel.sync_fields()
	var transformed := model_transform.transform_vertices(editor.shape.vertices)
	var positions := projection.project(transformed)
	renderer.render(editor.shape, positions, selected)
	projection_panel.show_counts(editor.shape, positions)
	projection_panel.transform_panel.show_vertex(selected, editor.shape.vertices[selected], transformed[selected], positions[selected])

func refresh_history() -> void:
	vertex_panel.show_history(editor.history.has_undo(), editor.history.has_redo())

## Anchor compensation happens in the model, so all views see the same updated position.
func change_transform(component: String, axis: int, value: float) -> void:
	if not is_finite(value):
		projection_panel.transform_panel.show_transform(model_transform)
		return
	if component == "angles":
		model_transform.angles[axis] = value
	else:
		var vector: Vector4 = model_transform.get(component)
		vector[axis] = value
		if component == "anchor":
			model_transform.set_anchor(vector)
		elif component == "scale" and model_transform.uniform_scale:
			model_transform.scale = Vector4.ONE * value
		else:
			model_transform.set(component, vector)
	projection_panel.transform_panel.show_transform(model_transform)
	refresh_geometry()

func change_transform_option(option: String, enabled: bool) -> void:
	model_transform.set(option, enabled)

func reset_transform() -> void:
	model_transform.reset()
	projection_panel.transform_panel.show_transform(model_transform)
	refresh_geometry()
