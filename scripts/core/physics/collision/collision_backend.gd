extends RefCounted
## Replaceable narrow-phase entry point. Contract: docs/COLLISION_BACKEND.md.
## Inputs contain geometry (local Geometry4D) and world (row-major 5x5 matrix).
## Inputs are borrowed read-only. No projection, rendering, IO or state mutation.
const GJK = preload("res://scripts/core/physics/collision/gjk_4d.gd")
const EPA = preload("res://scripts/core/physics/collision/epa_4d.gd")
const Collider = preload("res://scripts/core/physics/collision/convex_vertices_4d.gd")

static func query(a: Dictionary, b: Dictionary, options: Dictionary = {}) -> Dictionary:
	var boxes=preload("res://scripts/core/physics/collision/box_sat_4d.gd").query(a,b,options)
	if not boxes.is_empty(): return boxes
	var ca = Collider.new(a.geometry.vertices,a.world)
	var cb = Collider.new(b.geometry.vertices,b.world)
	var raw := GJK.query(ca,cb)
	var result := {"status":raw.status,"reason":raw.reason,
		"diagnostics":{"backend":"GJK + EPA (convex hulls)","detection_iterations":raw.iterations}}
	# Expose algorithm-neutral measurements only. Simplex internals stay private.
	for key in ["distance","distance_lower","direction","intervals","gap","point_a","point_b","tolerance"]:
		if raw.has(key) and raw[key] != null: result[key] = raw[key]
	if raw.status == "separated": result.interval_origin = ca.center.duplicate()
	if options.get("include_penetration",false) and raw.status == "intersecting":
		var penetration := EPA.query(ca,cb,raw)
		result.diagnostics.penetration_iterations = penetration.iterations
		result.penetration = {}
		for key in ["status","reason","converged","depth","depth_lower","depth_upper","direction","translation_b","point_a","point_b","tolerance"]:
			if penetration.has(key): result.penetration[key] = penetration[key]
	return result
