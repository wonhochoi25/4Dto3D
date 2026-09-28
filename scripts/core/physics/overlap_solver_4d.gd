extends RefCounted
## Position-only sequential correction. Backend direction moves B away from A.
## The host supplies fresh world colliders after each correction, including hierarchy changes.
static func solve(world, colliders: Callable, translate: Callable, options: Dictionary = {}) -> Dictionary:
	var slop: float = options.get("slop",0.0001)
	var limit: int = options.get("iterations",8)
	if not is_finite(slop) or slop < 0 or limit < 1 or limit > 64:
		return {"status":"invalid_options","iterations":0}
	var ids: Array = world.body_types.keys()
	ids.sort()
	var applied := 0
	for sweep in range(limit):
		var changed := false
		for i in range(ids.size()):
			for j in range(i+1,ids.size()):
				var a: int = ids[i]
				var b: int = ids[j]
				var wa := inverse_mass(world,a)
				var wb := inverse_mass(world,b)
				if wa+wb <= 0: continue
				var inputs: Dictionary = colliders.call()
				if not inputs.has(a) or not inputs.has(b): continue
				var result: Dictionary = world.query_collision(inputs[a],inputs[b],{"include_penetration":true})
				var pen: Dictionary = result.get("penetration",{})
				if result.get("status") != "intersecting" or pen.get("status") != "penetrating" or not pen.get("converged",false): continue
				var depth: float = pen.get("depth",0.0)
				var direction = pen.get("direction",PackedFloat64Array())
				if direction.size()!=4 or not is_finite(depth) or depth<=slop: continue
				var n := Vector4(direction[0],direction[1],direction[2],direction[3])
				if not n.is_finite() or absf(n.length()-1.0)>0.001: continue
				var delta := n.normalized()*(depth-slop)
				# Host applies both displacements atomically, or rejects the pair.
				if translate.call({a:-delta*(wa/(wa+wb)),b:delta*(wb/(wa+wb))}):
					changed=true
					applied+=1
		if not changed: return {"status":"finished","iterations":sweep+1,"corrections":applied}
	return {"status":"iteration_limit","iterations":limit,"corrections":applied}

static func inverse_mass(world, id: int) -> float:
	if world.body_types.get(id)!="dynamic" or not world.bodies.has(id): return 0.0
	var mass: float = world.bodies[id][41]
	return 1.0/mass if is_finite(mass) and mass>0 else 0.0
