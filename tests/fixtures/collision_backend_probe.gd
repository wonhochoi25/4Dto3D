extends RefCounted
## Contract test double, NOT a physical collision algorithm.
static var response := {"status":"intersecting","reason":"Detection-only contract probe"}
static var calls := 0
static var requested_penetration := false
static func query(a: Dictionary, b: Dictionary, options: Dictionary = {}) -> Dictionary:
	assert(a.geometry.vertices.size()>0 and b.geometry.vertices.size()>0)
	assert(a.world.size()==25 and b.world.size()==25)
	calls += 1
	requested_penetration = options.get("include_penetration",false)
	return response.duplicate(true)
