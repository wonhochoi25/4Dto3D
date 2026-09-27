extends "res://scripts/rendering/face_renderer.gd"
## Opaque exterior of the projected convex solid. Cache unchanged point clouds.
const Hull = preload("res://scripts/rendering/projected_hull_3d.gd")
var last_points := PackedVector3Array()
var hull: Dictionary = {}
var description := ""
func update_style(object) -> void:
	super.update_style(object)
	face_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	face_material.albedo_color = Color(object.color.r,object.color.g,object.color.b,1)
	if hull.get("dimension",3)<2: edges.visible=true

func render(object, points: PackedVector3Array) -> void:
	if points == last_points and not hull.is_empty():
		update_style(object)
		return
	last_points=points.duplicate()
	hull=Hull.build(points)
	description=["Projected point (no 3D volume)","Projected line (no 3D volume)","Projected plane (no 3D volume)","Projected 3D convex solid"][hull.dimension]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for tri in hull.triangles:
		var a: Vector3=hull.vertices[tri[0]]
		var b: Vector3=hull.vertices[tri[1]]
		var c: Vector3=hull.vertices[tri[2]]
		var n := (b-a).cross(c-a).normalized()
		vertices.append_array(PackedVector3Array([a,c,b]))
		normals.append_array(PackedVector3Array([n,n,n]))
	surface.mesh=null
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		surface.mesh=mesh
	var lines := PackedVector3Array()
	for edge in hull.edges: lines.append_array(PackedVector3Array([hull.vertices[edge[0]],hull.vertices[edge[1]]]))
	if hull.dimension==0 and not hull.vertices.is_empty():
		var p: Vector3=hull.vertices[0]
		for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]: lines.append_array(PackedVector3Array([p-axis*0.025,p+axis*0.025]))
	edges.mesh=null
	if not lines.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=lines
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
		edges.mesh=mesh
	update_style(object)

func set_selected(value: bool) -> void:
	super.set_selected(value)
	if hull.get("dimension",3)<2: edges.visible=true
