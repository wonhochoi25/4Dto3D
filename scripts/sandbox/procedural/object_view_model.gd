extends RefCounted
## Sandbox presentation adapter. Core owns track and geometry; this owns appearance/projection.
const Registry = preload("res://scripts/io/shape_catalog.gd")
const Track = preload("res://scripts/core/animation/transform_track_4d.gd")
const ProjectionTrack = preload("res://scripts/rendering/projection_track.gd")
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
var track
var projection_track := ProjectionTrack.new()
var shape
var defaults: Dictionary = {}
var is_group := false
var node_name := ""
var faces: Array:
	get: return shape.faces
var sources: Dictionary:
	get:
		var result: Dictionary = track.sources.duplicate()
		result.merge(projection_track.sources)
		return result
var color := Color(0.25, 0.72, 1.0, 0.25)
var visible := true
var show_edges := false
var keep_anchor_in_place: bool:
	get: return track.keep_anchor_in_place
	set(value): track.keep_anchor_in_place = value
var last_points := PackedVector3Array()
var error := ""
var error_field := ""

func _init(index: int = 0) -> void:
	is_group = index == -1
	track = Track.new(is_group)
	if is_group:
		shape = preload("res://scripts/core/geometry/geometry_4d.gd").new()
		shape.display_name = "Group"
	else:
		var asset := Registry.asset(index)
		shape = asset.geometry
		defaults = asset.defaults
		show_edges = shape.faces.is_empty()
	node_name = shape.display_name

func initialize_defaults(settings: Dictionary, time: float) -> bool:
	if not track.initialize_defaults(settings, time):
		error = track.error
		error_field = track.error_field
		return false
	var candidate := projection_track.sources.duplicate()
	if not is_group and settings.has("projection"):
		for row in range(3):
			for col in range(4): candidate["projection.%d" % (row * 4 + col)] = str(settings.projection[row][col])
	if not projection_track.apply_sources(candidate, time):
		error = projection_track.error
		error_field = projection_track.error_field
		return false
	return true

## Validate both parts before committing. UI controller uses Session for core mutation.
func apply_sources(candidate: Dictionary, time: float) -> bool:
	var trial := ProjectionTrack.new()
	if not trial.apply_sources(candidate, time):
		error = trial.error
		error_field = trial.error_field
		return false
	if not track.apply_sources(candidate, time):
		error = track.error
		error_field = track.error_field
		return false
	projection_track = trial
	error = ""
	return true

func sample(time: float) -> Variant:
	var result = track.sample(time)
	if result == null:
		error = track.error
		error_field = track.error_field
		return null
	var projection = projection_track.sample(time)
	if projection == null:
		error = projection_track.error
		error_field = projection_track.error_field
		return null
	result.projection = projection
	return result

func project_world(world: PackedFloat64Array, time: float) -> Variant:
	var projection = projection_track.sample(time)
	if projection == null:
		error = projection_track.error
		error_field = projection_track.error_field
		return null
	var vertices: Array[Vector4] = []
	for vertex in shape.vertices: vertices.append(Math4D.apply(world, vertex))
	var points = projection.project(vertices)
	for point in points:
		if not point.is_finite():
			error = "Projected position overflow"
			return null
	return points

func evaluate(time: float) -> Variant:
	var local = track.sample(time)
	if local == null: return null
	return project_world(local.matrix, time)
