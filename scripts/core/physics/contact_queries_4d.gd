extends RefCounted
## Exhaustive, deterministic pair selection. No scene, renderer or algorithm dependency.
## Results are reports, not response constraints; indeterminate never means separated.
static func query(body_types: Dictionary, colliders: Dictionary, backend, options: Dictionary) -> Array[Dictionary]:
	var reports: Array[Dictionary]=[]
	var broad: bool=options.get("broad_phase",false)
	var candidates: Dictionary=preload("res://scripts/core/physics/broad_phase_4d.gd").candidates(colliders,options.get("contact_margin",0.005)) if broad else {}
	var ids := body_types.keys()
	ids.sort()
	for i in range(ids.size()):
		for j in range(i+1,ids.size()):
			var a: int=ids[i]
			var b: int=ids[j]
			if body_types[a]!="dynamic" and body_types[b]!="dynamic": continue
			if broad and colliders.has(a) and colliders.has(b) and not candidates.has(Vector2i(a,b)): continue
			var result: Dictionary
			if not colliders.has(a) or not colliders.has(b):
				result={"status":"indeterminate","reason":"Missing world-space collider input"}
			else:
				result=backend.query(colliders[a],colliders[b],options)
			reports.append({"body_a":a,"body_b":b,"result":result})
	return reports
