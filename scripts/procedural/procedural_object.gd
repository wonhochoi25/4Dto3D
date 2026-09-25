extends RefCounted
## Independent object: model, face topology, expressions, material, last valid geometry.
const Registry = preload("res://scripts/shapes/shape_registry.gd")
const MathExpression = preload("res://scripts/procedural/math_expression.gd")
const Transform4D = preload("res://scripts/geometry/transform_4d.gd")
const Projection4D = preload("res://scripts/geometry/projection_4d.gd")
var shape
var faces: Array = []
var sources: Dictionary = {}
var compiled: Dictionary = {}
var color := Color(0.25, 0.72, 1.0, 0.25)
var visible := true
var show_edges := false
var last_points := PackedVector3Array()
var error_field := ""
var error := ""

func _init(index: int = 0) -> void:
	shape = Registry.create(index)
	var path: String = "res://data/faces/%s.json" % Registry.ENTRIES[index]["id"]
	faces = JSON.parse_string(FileAccess.get_file_as_string(path))
	for component in ["position", "anchor", "scale"]:
		for axis in range(4): sources["%s.%d" % [component, axis]] = "1" if component == "scale" else "0"
	for axis in range(6): sources["angles.%d" % axis] = "0"
	for row in range(3):
		for col in range(4): sources["projection.%d" % (row * 4 + col)] = "1" if row == col else "0"
	apply_sources(sources, 0)

## Compile all fields and evaluate a trial frame before committing any expression.
func apply_sources(candidate: Dictionary, time: float) -> bool:
	var next := {}
	for key in sources:
		var parser := MathExpression.new()
		if not parser.compile(str(candidate.get(key, ""))):
			error_field = key
			error = parser.error
			return false
		next[key] = parser
	if evaluate(time, next) == null:
		return false
	sources = candidate.duplicate()
	compiled = next
	return true

## Pure sampling at t: no integration, anchor compensation, or previous-frame state.
func evaluate(time: float, programs: Dictionary = {}) -> Variant:
	error = ""
	error_field = ""
	if programs.is_empty(): programs = compiled
	var values := {}
	for key in programs:
		var value = programs[key].evaluate(time)
		if value == null:
			error_field = key
			error = programs[key].error
			return null
		values[key] = value
	var transform := Transform4D.new()
	transform.keep_in_place = false
	for component in ["position", "anchor", "scale"]:
		var vector := Vector4.ZERO
		for axis in range(4): vector[axis] = values["%s.%d" % [component, axis]]
		transform.set(component, vector)
	for axis in range(6): transform.angles[axis] = values["angles.%d" % axis]
	var projection := Projection4D.new()
	for row in range(3):
		for col in range(4): projection.rows[row][col] = values["projection.%d" % (row * 4 + col)]
	var points := projection.project(transform.transform_vertices(shape.vertices))
	for point in points:
		if not point.is_finite():
			error = "Transform or projection overflow at t = %.3f." % time
			return null
	return points
