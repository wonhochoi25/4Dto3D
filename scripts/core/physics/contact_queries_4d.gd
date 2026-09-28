extends RefCounted
## Exhaustive, deterministic pair selection. No scene, renderer or algorithm dependency.
## Results are reports, not response constraints; indeterminate never means separated.
static func query(body_types: Dictionary, colliders: Dictionary, backend, options: Dictionary) -> Array[Dictionary]:
	var reports: Array[Dictionary]=[]
	var ids := body_types.keys()
	ids.sort()
	for i in range(ids.size()):
		for j in range(i+1,ids.size()):
			var a: int=ids[i]
			var b: int=ids[j]
			if body_types[a]!="dynamic" and body_types[b]!="dynamic": continue
			var result: Dictionary
			if not colliders.has(a) or not colliders.has(b):
				result={"status":"indeterminate","reason":"Missing world-space collider input"}
			else:
				result=backend.query(colliders[a],colliders[b],options)
			reports.append({"body_a":a,"body_b":b,"result":result})
	return reports
