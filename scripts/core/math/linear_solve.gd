extends RefCounted
## Small dense pivoted solve; empty means singular or invalid. Row-major matrix.
static func solve(matrix: PackedFloat64Array, rhs: PackedFloat64Array) -> PackedFloat64Array:
	var n:=rhs.size()
	var a:=matrix.duplicate()
	var b:=rhs.duplicate()
	var scale:=0.0
	for v in a: scale=maxf(scale,absf(v))
	if a.size()!=n*n or scale==0: return PackedFloat64Array()
	for col in range(n):
		var pivot:=col
		for row in range(col+1,n):
			if absf(a[row*n+col])>absf(a[pivot*n+col]): pivot=row
		if absf(a[pivot*n+col])<scale*1e-10: return PackedFloat64Array()
		for j in range(n):
			var temp: float=a[col*n+j];a[col*n+j]=a[pivot*n+j];a[pivot*n+j]=temp
		var temp: float=b[col];b[col]=b[pivot];b[pivot]=temp
		var divisor: float=a[col*n+col]
		for j in range(col,n): a[col*n+j]/=divisor
		b[col]/=divisor
		for row in range(n):
			if row==col: continue
			var factor: float=a[row*n+col]
			for j in range(col,n): a[row*n+j]-=factor*a[col*n+j]
			b[row]-=factor*b[col]
	for v in b:
		if not is_finite(v): return PackedFloat64Array()
	return b
