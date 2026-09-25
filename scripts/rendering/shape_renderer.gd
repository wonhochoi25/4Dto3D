extends Node3D
## Draws projected geometry only. Never reads UI or changes the 4D model.
var wire := MeshInstance3D.new()
var markers := MultiMeshInstance3D.new()
var highlight := MeshInstance3D.new()

func _ready() -> void:
	add_child(wire)
	add_child(markers)
	add_child(highlight)
	build_reference_axes()

func render(shape, positions: PackedVector3Array, selected: int) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	var indices := PackedInt32Array()
	for edge in shape.edges:
		indices.append(edge.x)
		indices.append(edge.y)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	wire.mesh = mesh
	wire.material_override = material(Color("74ddff"))
	var sphere := SphereMesh.new()
	sphere.radius = 0.025 if positions.size() > 100 else 0.035
	sphere.height = sphere.radius * 2
	sphere.radial_segments = 8
	sphere.rings = 4
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = sphere
	instances.instance_count = positions.size()
	for i in range(positions.size()):
		instances.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
	markers.multimesh = instances
	markers.material_override = material(Color("e6f8ff"))
	update_highlight(shape, positions, selected)

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.albedo_color = color
	return result

func build_reference_axes() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var colors := [Color("b85a65"), Color("64a877"), Color("678dc5")]
	for axis in range(3):
		var endpoint := Vector3.ZERO
		endpoint[axis] = 2.5
		mesh.surface_set_color(colors[axis])
		mesh.surface_add_vertex(-endpoint)
		mesh.surface_add_vertex(endpoint)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var axis_material := material(Color.WHITE)
	axis_material.vertex_color_use_as_albedo = true
	instance.material_override = axis_material
	add_child(instance)
	for axis in range(3):
		var label := Label3D.new()
		label.text = ["X", "Y", "Z"][axis]
		label.position[axis] = 2.7
		label.font_size = 40
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = colors[axis]
		add_child(label)

func update_highlight(shape, positions: PackedVector3Array, selected_vertex: int) -> void:
	if not is_instance_valid(highlight) or not highlight.is_inside_tree():
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for edge in shape.edges:
		if edge.x == selected_vertex or edge.y == selected_vertex:
			mesh.surface_add_vertex(positions[edge.x])
			mesh.surface_add_vertex(positions[edge.y])
	mesh.surface_end()
	highlight.mesh = mesh
	var gold := material(Color("ffd166"))
	gold.no_depth_test = true
	gold.render_priority = 1
	highlight.material_override = gold
	for child in highlight.get_children():
		highlight.remove_child(child)
		child.queue_free()
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	marker.mesh = sphere
	marker.material_override = gold
	marker.position = positions[selected_vertex]
	highlight.add_child(marker)
