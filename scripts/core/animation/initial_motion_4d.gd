extends RefCounted
## Initial-condition expressions only. Sample once at run start, never each step.
## Uses the shared safe scalar evaluator; no physics, scene, or UI dependencies.
const Scalar = preload("res://scripts/core/animation/math_expression.gd")
const COUNTS = {"velocity":4,"acceleration":4,"angular_velocity":6,"angular_acceleration":6}
var sources: Dictionary = {}
var programs: Dictionary = {}
var error := ""

func configure(candidate: Dictionary, time: float) -> bool:
	var next := {}
	var text := {}
	for component in COUNTS:
		for axis in range(COUNTS[component]):
			var key := "%s.%d" % [component,axis]
			var parser := Scalar.new()
			text[key]=str(candidate.get(key,"0"))
			if not parser.compile(text[key]) or parser.evaluate(time)==null:
				error=key+": "+parser.error
				return false
			next[key]=parser
	sources=text
	programs=next
	error=""
	return true

func sample(time: float) -> Variant:
	var result := {}
	for component in COUNTS:
		var values := PackedFloat64Array()
		for axis in range(COUNTS[component]):
			var key := "%s.%d" % [component,axis]
			var value = programs[key].evaluate(time)
			if value==null:
				error=key+": "+programs[key].error
				return null
			values.append(value)
		result[component]=Vector4(values[0],values[1],values[2],values[3]) if COUNTS[component]==4 else values
	error=""
	return result
