extends RefCounted
## Mass-weighted central second moment C = integral(r r^T dm), row-major 4x4.
## Derived inertia acts on radians/s in plane order XY,XZ,XW,YZ,YW,ZW.
## Positive-volume solids only for now: C must be symmetric positive definite.
const Math4D=preload("res://scripts/core/math/transform_4d.gd")

static func uniform_box(mass: float, lengths: Vector4, center: Vector4 = Vector4.ZERO) -> Dictionary:
	if not is_finite(mass) or mass<=0 or not lengths.is_finite() or not center.is_finite(): return {}
	var moment:=PackedFloat64Array()
	moment.resize(16)
	for i in range(4):
		if lengths[i]<=0: return {}
		moment[i*4+i]=mass*lengths[i]*lengths[i]/12.0
	return {"mass":mass,"center_of_mass":center,"second_moment":moment}

## Apply an affine shape transform at fixed total mass. Scale/shear change distribution,
## translation changes only center. This does not infer density or alter total mass.
static func transformed(properties: Dictionary, matrix: PackedFloat64Array) -> Dictionary:
	var checked:=validated(properties,properties.get("mass",0.0))
	if checked.is_empty() or matrix.size()!=25: return {}
	var source: PackedFloat64Array=checked.second_moment
	var moment:=PackedFloat64Array()
	moment.resize(16)
	for i in range(4):
		for j in range(4):
			for k in range(4):
				for l in range(4): moment[i*4+j]+=matrix[i*5+k]*source[k*4+l]*matrix[j*5+l]
	return validated({"mass":checked.mass,"center_of_mass":Math4D.apply(matrix,checked.center_of_mass),"second_moment":moment},checked.mass)

static func validated(properties: Dictionary, mass: float) -> Dictionary:
	var center=properties.get("center_of_mass",Vector4.ZERO)
	var moment=properties.get("second_moment",PackedFloat64Array())
	if not is_finite(mass) or mass<=0 or properties.get("mass",mass)!=mass or not center is Vector4 or not center.is_finite(): return {}
	if not (moment is Array or moment is PackedFloat64Array) or moment.size()!=16: return {}
	for v in moment:
		if not (v is int or v is float) or not is_finite(v): return {}
	moment=PackedFloat64Array(moment)
	if positive_inverse(moment,4).is_empty(): return {}
	var inertia:=PackedFloat64Array()
	inertia.resize(36)
	for a in range(6):
		var i: int=Math4D.PLANES[a].x
		var j: int=Math4D.PLANES[a].y
		for b in range(6):
			var k: int=Math4D.PLANES[b].x
			var l: int=Math4D.PLANES[b].y
			# integral((E_ij r) dot (E_kl r) dm), E_ij[i,j]=-1, E_ij[j,i]=1.
			inertia[a*6+b]=(moment[j*4+l] if i==k else 0.0)-(moment[j*4+k] if i==l else 0.0)-(moment[i*4+l] if j==k else 0.0)+(moment[i*4+k] if j==l else 0.0)
	var inverse:=positive_inverse(inertia,6)
	if inverse.is_empty(): return {}
	return {"mass":mass,"center_of_mass":center,"second_moment":moment,"inertia":inertia,"inverse_inertia":inverse}

## Cholesky validation/inverse. Reject singular and numerically ill-conditioned distributions.
static func positive_inverse(matrix: PackedFloat64Array, size: int) -> PackedFloat64Array:
	var scale:=0.0
	for v in matrix:
		if not is_finite(v): return PackedFloat64Array()
		scale=maxf(scale,absf(v))
	if scale<=0: return PackedFloat64Array()
	var lower:=PackedFloat64Array()
	lower.resize(size*size)
	for i in range(size):
		for j in range(i+1):
			if absf(matrix[i*size+j]-matrix[j*size+i])>scale*1e-10: return PackedFloat64Array()
			var value: float=matrix[i*size+j]
			for k in range(j): value-=lower[i*size+k]*lower[j*size+k]
			if i==j:
				if value<=scale*1e-12: return PackedFloat64Array()
				lower[i*size+j]=sqrt(value)
			else: lower[i*size+j]=value/lower[j*size+j]
	var inverse:=PackedFloat64Array()
	inverse.resize(size*size)
	for col in range(size):
		var y:=PackedFloat64Array()
		y.resize(size)
		for i in range(size):
			var value:=1.0 if i==col else 0.0
			for k in range(i): value-=lower[i*size+k]*y[k]
			y[i]=value/lower[i*size+i]
		for i in range(size-1,-1,-1):
			var value: float=y[i]
			for k in range(i+1,size): value-=lower[k*size+i]*inverse[k*size+col]
			inverse[i*size+col]=value/lower[i*size+i]
	for v in inverse:
		if not is_finite(v): return PackedFloat64Array()
	return inverse
