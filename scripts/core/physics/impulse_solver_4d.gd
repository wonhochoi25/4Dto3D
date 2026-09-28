extends RefCounted
## Frictionless, linear/angular sequential impulses. Accumulation is local to one step.
## No contact cache, friction or dependency on a particular collision algorithm.
const Friction=preload("res://scripts/core/physics/friction_4d.gd")
const Weights=preload("res://scripts/core/physics/overlap_solver_4d.gd")

static func solve(world, reports: Array, velocity: Callable, apply_pair: Callable, options: Dictionary = {}, point_velocity: Callable = Callable(), apply_at_points: Callable = Callable()) -> Dictionary:
	if not apply_at_points.is_valid(): apply_at_points=world.apply_point_impulses
	var iterations: int=options.get("iterations",32)
	var dt: float=options.get("dt",1.0/60.0)
	var margin: float=options.get("contact_margin",0.005)
	var bounce_threshold: float=options.get("bounce_threshold",1.0)
	var tolerance: float=options.get("velocity_tolerance",0.000001)
	if iterations<1 or iterations>256 or not is_finite(dt) or dt<=0 or not is_finite(margin) or margin<0 or not is_finite(bounce_threshold) or bounce_threshold<0 or not is_finite(tolerance) or tolerance<0:
		return {"status":"invalid_options","impulses":0,"skipped":0,"iterations":0}
	var constraints: Array[Dictionary]=[]
	var skipped:=0
	for report in reports:
		var a: int=report.body_a
		var b: int=report.body_b
		var wa:=Weights.inverse_mass(world,a)
		var wb:=Weights.inverse_mass(world,b)
		if wa+wb<=0: continue
		var result: Dictionary=report.result
		var direction=PackedFloat64Array()
		var gap:=0.0
		if result.get("status")=="intersecting":
			var pen: Dictionary=result.get("penetration",{})
			if not pen.get("converged",false) or pen.get("status") not in ["penetrating","touching"]:
				skipped+=1
				continue
			direction=pen.get("direction",PackedFloat64Array())
		elif result.get("status")=="separated":
			# Use the certified interval gap along this normal, not an unrelated distance.
			gap=result.get("gap",INF)
			if not is_finite(gap) or gap<0 or gap>margin: continue
			direction=result.get("direction",PackedFloat64Array())
		else:
			skipped+=1
			continue
		if direction.size()!=4:
			skipped+=1
			continue
		var n:=Vector4(direction[0],direction[1],direction[2],direction[3])
		if not n.is_finite() or absf(n.length()-1)>0.001:
			skipped+=1
			continue
		n=n.normalized()
		var measurements: Dictionary=result.get("penetration",{}) if result.get("status")=="intersecting" else result
		var pa=point_from(measurements.get("point_a"))
		var pb=point_from(measurements.get("point_b"))
		var point: Variant=(pa+pb)*0.5 if pa!=null and pb!=null else null
		var points: Array=result.get("contacts",[point])
		for contact in points:
			point=point_from(contact)
			var weight: float=wa+wb
			if point!=null:
				weight+=world.angular_inverse_mass(a,point,n)+world.angular_inverse_mass(b,point,n)
			if not is_finite(weight) or weight<=0:
				skipped+=1
				continue
			var va:=contact_velocity(world,velocity,point_velocity,a,point)
			var vb:=contact_velocity(world,velocity,point_velocity,b,point)
			var closing: float=(vb-va).dot(n)
			if not is_finite(closing):
				skipped+=1
				continue
			# Freeze the restitution target before iteration; never re-bounce in each sweep.
			var restitution: float=maxf(world.motion_settings.get(a,{}).get("restitution",0.0),world.motion_settings.get(b,{}).get("restitution",0.0))
			var target: float=-gap/dt
			if result.get("status")=="intersecting" and closing<0 and -closing>=bounce_threshold:
				target=-restitution*closing
			constraints.append({"a":a,"b":b,"n":n,"weight":weight,"point":point,"target":target,"lambda":0.0,"changed":false,"friction":Friction.setup(world,a,b,point,n,wa+wb)})
	var sweeps:=0
	var residual:=0.0
	var friction_change:=0.0
	for sweep in range(iterations):
		sweeps=sweep+1
		friction_change=0.0
		for c in constraints:
			var va:=contact_velocity(world,velocity,point_velocity,c.a,c.point)
			var vb:=contact_velocity(world,velocity,point_velocity,c.b,c.point)
			var speed: float=(vb-va).dot(c.n)
			var next: float=maxf(0.0,c.lambda+(c.target-speed)/c.weight)
			var delta: float=next-c.lambda
			# Friction still needs a pass when the normal impulse no longer changes.
			var impulse: Vector4=c.n*delta
			var accepted:=false
			if impulse.is_finite():
				if c.point==null: accepted=apply_pair.call({c.a:-impulse,c.b:impulse})
				else: accepted=apply_at_points.call({c.a:{"impulse":-impulse,"point":c.point},c.b:{"impulse":impulse,"point":c.point}})
			if not accepted:
				skipped+=1
				continue
			c.lambda=next
			c.changed=c.changed or delta!=0
			if c.friction.mu>0:
				var relative: Vector4=contact_velocity(world,velocity,point_velocity,c.b,c.point)-contact_velocity(world,velocity,point_velocity,c.a,c.point)
				var friction=Friction.update(c.friction,relative,c.lambda)
				var tangential: Vector4=friction.impulse
				var ok: bool=apply_pair.call({c.a:-tangential,c.b:tangential}) if c.point==null else apply_at_points.call({c.a:{"impulse":-tangential,"point":c.point},c.b:{"impulse":tangential,"point":c.point}})
				if ok:
					c.friction.total=friction.total
					friction_change=maxf(friction_change,tangential.length())
					c.changed=c.changed or tangential.length_squared()>0

		# Check after the whole sweep: a later pair may disturb an earlier pair.
		residual=0.0
		for c in constraints:
			var va:=contact_velocity(world,velocity,point_velocity,c.a,c.point)
			var vb:=contact_velocity(world,velocity,point_velocity,c.b,c.point)
			var difference: float=c.target-(vb-va).dot(c.n)
			residual=maxf(residual,absf(difference) if c.lambda>0 else maxf(0.0,difference))
		if residual<=tolerance and friction_change<=tolerance: break
	var applied:=0
	for c in constraints:
		if c.changed: applied+=1
	return {"status":"finished" if residual<=tolerance and friction_change<=tolerance else "iteration_limit","impulses":applied,"skipped":skipped,"iterations":sweeps,"constraints":constraints.size(),"velocity_error":residual,"friction_impulse_change":friction_change}

static func point_from(value) -> Variant:
	if value is Vector4: return value if value.is_finite() else null
	if not (value is Array or value is PackedFloat64Array or value is PackedFloat32Array) or value.size()!=4: return null
	for v in value:
		if not (v is int or v is float) or not is_finite(v): return null
	return Vector4(value[0],value[1],value[2],value[3])

static func contact_velocity(world, linear: Callable, custom: Callable, id: int, point: Variant) -> Vector4:
	if point==null: return linear.call(id)
	if custom.is_valid(): return custom.call(id,point)
	return linear.call(id)+world.angular_point_velocity(id,point)
