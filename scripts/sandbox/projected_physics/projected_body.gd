extends RigidBody3D
## Godot adapter: 4D authored geometry plus a separate simulated 3D pose.
## Core math remains independent of Godot physics nodes and presentation.
const Renderer = preload("res://scripts/rendering/solid_hull_renderer.gd")
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
const BoundaryCells = preload("res://scripts/rendering/projected_boundary_cells.gd")
var view_rotation := Math4D.identity()
var camera_4d := preload("res://scripts/core/math/camera_projection_4d.gd").new()
## Source parts share one native body; graph composition stays in core Scene4D.
var graph
var node_id := 0
var members: Array = []
var parts: Array = []
var absorbed := false
var held := false
## Mass at uniform grab size 1. Camera deformation does not redefine density.
var base_mass := 1.0:
	set(value):
		base_mass = maxf(value, 0.01)
		update_mass()
var size_multiplier := 1.0
var rendered_size := -1.0
var local_points := PackedVector3Array()
var model
var renderer := Renderer.new()
var boundary_cells := BoundaryCells.new()
var show_boundary_cells := false
var collider := CollisionShape3D.new()
var authored_center := Vector3.ZERO
var initialized := false
var fixed := false
var suspended := false
var valid_volume := false
var last_projected := PackedVector3Array()
var error := ""

func _ready() -> void:
	add_child(renderer)
	add_child(boundary_cells)
	add_child(collider)
	continuous_cd = true
	var material := PhysicsMaterial.new()
	material.friction = 0.7
	material.bounce = 0.15
	physics_material_override = material

## Called at physics ticks. Rebuild only when authored projected points change.
## Center the hull locally so native body rotation is around the projected solid.
func update_geometry(time: float, reset_pose: bool = false) -> bool:
	if absorbed: return true
	var state = graph.sample(time) if graph != null else null
	if graph != null and state == null:
		error = graph.error
		return false
	var sources: Array = members if not members.is_empty() else [self]
	var clouds: Array = []
	var cell_clouds: Array = []
	var projected := PackedVector3Array()
	for source in sources:
		var sample = source.model.track.sample(time)
		var projection = source.model.projection_track.sample(time)
		if sample == null or projection == null:
			error = source.model.track.error if sample == null else source.model.projection_track.error
			return false
		var matrix = state[graph.objects[source.node_id].leaf_id].world if graph != null else sample.matrix
		var vertices: Array[Vector4] = []
		for vertex in source.model.shape.vertices: vertices.append(Math4D.apply(matrix, vertex))
		var cloud := camera_4d.project(vertices, projection.rows, view_rotation)
		clouds.append(cloud)
		if source.model.shape.display_name.begins_with("Tesseract") and source.model.shape.vertices.size() == 16:
			# Each 3-cell is defined by fixing one of four signed coordinates.
			for axis in range(4):
				for side in [-1.0, 1.0]:
					var cell := PackedVector3Array()
					for vertex_index in range(16):
						if is_equal_approx(source.model.shape.vertices[vertex_index][axis], side):
							cell.append(cloud[vertex_index])
					cell_clouds.append(cell)
		projected.append_array(cloud)
	var unchanged := parts.size() == clouds.size()
	if unchanged:
		for i in range(parts.size()):
			if parts[i].source != sources[i] or parts[i].projected != clouds[i]: unchanged = false
	if unchanged and not reset_pose:
		for part in parts: part.renderer.update_style(part.source.model)
		boundary_cells.set_enabled(show_boundary_cells)
		update_mass()
		if not is_equal_approx(rendered_size, size_multiplier): rebuild_solid()
		return true
	var center := Vector3.ZERO
	for point in projected: center += point
	if not projected.is_empty(): center /= projected.size()
	# Keep each convex part distinct, including during clipping and resizing.
	while parts.size() > clouds.size():
		var old: Dictionary = parts.pop_back()
		old.collider.shape = null
		old.renderer.queue_free()
		old.collider.queue_free()
	for i in range(clouds.size()):
		if i >= parts.size():
			var visual = renderer if i == 0 else Renderer.new()
			var collision = collider if i == 0 else CollisionShape3D.new()
			if i != 0:
				add_child(visual)
				add_child(collision)
			parts.append({"renderer": visual, "collider": collision})
		var points := PackedVector3Array()
		for point in clouds[i]: points.append(point - center)
		parts[i].merge({"source": sources[i], "projected": clouds[i], "points": points}, true)
	local_points.clear()
	for point in projected: local_points.append(point - center)
	boundary_cells.set_cells(cell_clouds, center)
	boundary_cells.set_enabled(show_boundary_cells)
	rebuild_solid()
	if not initialized or reset_pose:
		transform = Transform3D(Basis.IDENTITY, center)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		# Authored displacement is world-space; retain accumulated native motion.
		position += center - authored_center
	authored_center = center
	last_projected = projected.duplicate()
	initialized = true
	sleeping = false
	refresh_freeze()
	error = "" if valid_volume else "Projection has no 3D volume: collision and gravity suspended."
	return true

func refresh_freeze() -> void:
	freeze = absorbed or fixed or suspended or not valid_volume

## Native body scale stays identity. Bake uniform resizing into mesh and collider.
func rebuild_solid() -> void:
	valid_volume = false
	for part in parts:
		var scaled := PackedVector3Array()
		for point in part.points: scaled.append(point * size_multiplier)
		part.renderer.visible = not absorbed and not scaled.is_empty()
		part.collider.shape = null
		if scaled.is_empty(): continue
		part.renderer.render(part.source.model, scaled)
		if part.renderer.hull.dimension == 3 and not absorbed:
			var shape := ConvexPolygonShape3D.new()
			shape.points = scaled
			part.collider.shape = shape
			valid_volume = true
	update_mass()
	rendered_size = size_multiplier
	refresh_freeze()

func scaled_points(factor: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for p in local_points: points.append(p * factor)
	return points

func set_size_multiplier(value: float) -> void:
	size_multiplier = clampf(value, 0.05, 20.0)
	if not is_equal_approx(rendered_size, size_multiplier): rebuild_solid()

func update_mass() -> void:
	var total := base_mass
	if not members.is_empty():
		total = 0.0
		for source in members: total += source.base_mass
	var desired := maxf(total * pow(size_multiplier, 3.0), 0.000001)
	if not is_equal_approx(mass, desired):
		mass = desired
		if is_inside_tree(): sleeping = false

## Child adapters retain authoring settings but own no active native colliders.
func set_absorbed(value: bool) -> void:
	if absorbed == value: return
	absorbed = value
	if value: members.clear()
	for part in parts:
		part.collider.shape = null
		part.renderer.hide()
	parts.clear()
	# First renderer/collider are retained for editor references.
	for child in get_children():
		if (child is CollisionShape3D or child is Renderer) and child != renderer and child != collider:
			child.queue_free()
	initialized = false
	valid_volume = false
	refresh_freeze()

## Resizing queries the compound pieces, never a hull spanning the gaps.
func scaled_collision_parts(factor: float) -> Array:
	var result: Array = []
	for part in parts:
		if part.collider.shape == null: continue
		var points := PackedVector3Array()
		for point in part.points: points.append(point * factor)
		result.append(points)
	return result

func select_part(source) -> void:
	for part in parts: part.renderer.set_selected(part.source == source)
