extends RefCounted
## Independent object: model, face topology, expressions, material, last valid geometry.
const Registry = preload("res://scripts/shapes/shape_registry.gd")
const MathExpression = preload("res://scripts/procedural/math_expression.gd")
const Transform4D = preload("res://scripts/geometry/transform_4d.gd")
const Projection4D = preload("res://scripts/geometry/projection_4d.gd")
var shape
var is_group := false
var node_name := ""
var faces: Array = []
var sources: Dictionary = {}
var compiled: Dictionary = {}
var color := Color(0.25, 0.72, 1.0, 0.25)
var visible := true
var show_edges := false
var keep_anchor_in_place := true
var last_points := PackedVector3Array()
var error_field := ""
var error := ""

func _init(index: int = 0) -> void:
	is_group = index == -1
	if is_group:
		shape = preload("res://scripts/shapes/shape_4d.gd").new()
		shape.display_name = "Group"
	else:
		shape = Registry.create(index)
		if Registry.ENTRIES[index]["id"] == "custom":
			faces = shape.faces
			show_edges = faces.is_empty()
		else:
			var path: String = "res://data/faces/%s.json" % Registry.ENTRIES[index]["id"]
			faces = JSON.parse_string(FileAccess.get_file_as_string(path))
	node_name = shape.display_name
	for component in ["position", "anchor", "scale"]:
		for axis in range(4): sources["%s.%d" % [component, axis]] = "1" if component == "scale" else "0"
	for axis in range(6): sources["angles.%d" % axis] = "0"
	for row in range(3):
		for col in range(4): sources["projection.%d" % (row * 4 + col)] = "1" if row == col else "0"
	apply_sources(sources, 0)

## Compile all fields and evaluate a trial frame before committing any expression.
func apply_sources(candidate: Dictionary, time: float) -> bool:
	candidate = candidate.duplicate()
	if is_group:
		for axis in range(1, 4): candidate["scale.%d" % axis] = candidate.get("scale.0", "1")
		for row in range(3):
			for column in range(4): candidate["projection.%d" % (row * 4 + column)] = "1" if row == column else "0"
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
	var adjusted := candidate.duplicate()
	var anchor_changed := false
	for axis in range(4):
		var key := "anchor.%d" % axis
		anchor_changed = anchor_changed or candidate[key] != sources[key]
	if keep_anchor_in_place and anchor_changed and not compiled.is_empty():
		# Bake an edit-time correction into Position expressions, not a frame accumulator.
		var delta := Vector4.ZERO
		var transform := Transform4D.new()
		for axis in range(4):
			var key := "anchor.%d" % axis
			var old_value = compiled[key].evaluate(time)
			if old_value == null:
				error_field = key
				error = "Cannot compensate the previous anchor at this time. Disable Keep shape in place or scrub to a valid time."
				return false
			delta[axis] = next[key].evaluate(time) - old_value
			transform.scale[axis] = next["scale.%d" % axis].evaluate(time)
		for axis in range(6): transform.angles[axis] = next["angles.%d" % axis].evaluate(time)
		var correction := Transform4D.apply(Transform4D.multiply(transform.rotation_matrix(), transform.scaling_matrix()), delta, 0)
		for axis in range(4):
			if is_zero_approx(correction[axis]): continue
			var key := "position.%d" % axis
			adjusted[key] = "(%s)+(%.9f)" % [candidate[key], correction[axis]]
			var parser := MathExpression.new()
			if not parser.compile(adjusted[key]):
				error_field = key
				error = parser.error
				return false
			next[key] = parser
		if evaluate(time, next) == null: return false
	sources = adjusted
	compiled = next
	return true

## Pure sampling at t: no integration, anchor compensation, or previous-frame state.
func sample(time: float, programs: Dictionary = {}) -> Variant:
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
	var matrix := transform.matrix()
	for value in matrix:
		if not is_finite(value):
			error = "Transform overflow at t = %.3f." % time
			return null
	return {"matrix": matrix, "projection": projection}

## Standalone sampling retained for expression validation and non-hierarchical callers.
func evaluate(time: float, programs: Dictionary = {}) -> Variant:
	var sampled = sample(time, programs)
	if sampled == null: return null
	var vertices: Array[Vector4] = []
	for point in shape.vertices: vertices.append(Transform4D.apply(sampled.matrix, point))
	var points: PackedVector3Array = sampled.projection.project(vertices)
	for point in points:
		if not point.is_finite():
			error = "Transform or projection overflow at t = %.3f." % time
			return null
	return points
