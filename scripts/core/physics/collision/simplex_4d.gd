extends RefCounted
## Closest point in the convex hull of <=5 normalized 4D points.
## Enumerate features; reorthogonalized QR skips rank-deficient affine spans.
static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var value := 0.0
	for i in range(4): value += a[i]*b[i]
	return value

static func closest(points: Array) -> Dictionary:
	var best := INF
	var result := {}
	for mask in range(1, 1 << points.size()):
		var ids: Array[int] = []
		for i in range(points.size()):
			if mask & (1 << i): ids.append(i)
		var base: PackedFloat64Array = points[ids[0]]
		var count := ids.size()-1
		var q: Array[PackedFloat64Array] = []
		var r := PackedFloat64Array()
		r.resize(count*count)
		var rank_ok := true
		for j in range(count):
			var column := PackedFloat64Array([0,0,0,0])
			for k in range(4): column[k] = points[ids[j+1]][k]-base[k]
			var original_length := sqrt(dot(column,column))
			for pass_index in range(2):
				for i in range(j):
					var coefficient := dot(q[i],column)
					r[i*count+j] += coefficient
					for k in range(4): column[k] -= coefficient*q[i][k]
			var length := sqrt(dot(column,column))
			if length <= maxf(1e-14, original_length*1e-12):
				rank_ok = false
				break
			r[j*count+j] = length
			for k in range(4): column[k] /= length
			q.append(column)
		if not rank_ok: continue
		var coefficients := PackedFloat64Array()
		coefficients.resize(count)
		for j in range(count-1,-1,-1):
			var rhs := -dot(q[j],base)
			for k in range(j+1,count): rhs -= r[j*count+k]*coefficients[k]
			coefficients[j] = rhs/r[j*count+j]
		var weights := PackedFloat64Array([1.0])
		for coefficient in coefficients:
			weights[0] -= coefficient
			weights.append(coefficient)
		var feasible := true
		var total := 0.0
		for i in range(weights.size()):
			if not is_finite(weights[i]) or weights[i] < -1e-10: feasible = false
			weights[i] = maxf(0.0,weights[i])
			total += weights[i]
		if not feasible or total <= 0: continue
		var point := PackedFloat64Array([0,0,0,0])
		for i in range(ids.size()):
			weights[i] /= total
			for k in range(4): point[k] += weights[i]*points[ids[i]][k]
		var squared := dot(point,point)
		if squared < best:
			best = squared
			result = {"point":point,"indices":ids,"weights":weights,"squared":squared}
	return result
