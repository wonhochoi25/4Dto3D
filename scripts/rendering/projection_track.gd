extends RefCounted
## Presentation expressions. Not read during 4D simulation or hierarchy evaluation.
const Expression4D = preload("res://scripts/core/animation/math_expression.gd")
const Projection4D = preload("res://scripts/core/math/projection_4d.gd")
var sources: Dictionary = {}
var compiled: Dictionary = {}
var error := ""
var error_field := ""
func _init() -> void:
	for i in range(12): sources["projection.%d" % i] = "1" if i in [0,5,10] else "0"
	apply_sources(sources, 0)
func apply_sources(candidate: Dictionary, time: float) -> bool:
	var next := {}
	for key in sources:
		var parser := Expression4D.new()
		if not parser.compile(str(candidate.get(key, sources[key]))):
			error = parser.error
			error_field = key
			return false
		next[key] = parser
	if sample(time, next) == null: return false
	for key in sources: sources[key] = str(candidate.get(key, sources[key]))
	compiled = next
	return true
func sample(time: float, programs: Dictionary = {}) -> Variant:
	error = ""
	error_field = ""
	if programs.is_empty(): programs = compiled
	var projection := Projection4D.new()
	for i in range(12):
		var key := "projection.%d" % i
		var value = programs[key].evaluate(time)
		if value == null:
			error = programs[key].error
			error_field = key
			return null
		projection.rows[i / 4][i % 4] = value
	return projection
