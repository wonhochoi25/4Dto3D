extends RefCounted
## 4D hierarchy independent of Godot's 3D scene graph. Geometry is always a leaf.
## World = parent_world * fixed_parenting_offset * expression_PRSA(t).
const Math4D = preload("res://scripts/core/math/transform_4d.gd")
var entries: Dictionary = {}
var next_id := 1
var error := ""
var error_id := 0

func add(model) -> int:
	var id := next_id
	next_id += 1
	entries[id] = {"model": model, "parent": 0, "offset": Math4D.identity()}
	return id

func can_parent(id: int, parent: int) -> bool:
	if not entries.has(id): return false
	if parent != 0 and (not entries.has(parent) or not entries[parent].model.is_group): return false
	var ancestor := parent
	while ancestor != 0:
		if ancestor == id: return false
		ancestor = entries[ancestor].parent
	return true

func sample(time: float) -> Variant:
	error = ""
	error_id = 0
	var result := {0: {"world": Math4D.identity()}}
	for id in entries:
		if resolve(id, time, result) == null: return null
	return result

func resolve(id: int, time: float, result: Dictionary) -> Variant:
	if result.has(id): return result[id]
	var entry: Dictionary = entries[id]
	var parent = resolve(entry.parent, time, result)
	if parent == null: return null
	var local = local_sample(id, time)
	if local == null:
		error_id = id
		error = entry.model.error
		return null
	var world := Math4D.multiply(Math4D.multiply(parent.world, entry.offset), local.matrix)
	for value in world:
		if not is_finite(value):
			error_id = id
			error = "World transform overflow."
			return null
	result[id] = {"world": world}
	return result[id]

## Gauss-Jordan inversion with pivoting. Empty result denotes a singular parent.
static func inverse(matrix: PackedFloat64Array) -> PackedFloat64Array:
	var a := matrix.duplicate()
	var result := Math4D.identity()
	for col in range(5):
		var pivot := col
		for row in range(col + 1, 5):
			if absf(a[row * 5 + col]) > absf(a[pivot * 5 + col]): pivot = row
		if absf(a[pivot * 5 + col]) < 1e-12: return PackedFloat64Array()
		for j in range(5):
			var temporary := a[col * 5 + j]
			a[col * 5 + j] = a[pivot * 5 + j]
			a[pivot * 5 + j] = temporary
			temporary = result[col * 5 + j]
			result[col * 5 + j] = result[pivot * 5 + j]
			result[pivot * 5 + j] = temporary
		var divisor := a[col * 5 + col]
		for j in range(5):
			a[col * 5 + j] /= divisor
			result[col * 5 + j] /= divisor
		for row in range(5):
			if row == col: continue
			var factor := a[row * 5 + col]
			for j in range(5):
				a[row * 5 + j] -= factor * a[col * 5 + j]
				result[row * 5 + j] -= factor * result[col * 5 + j]
	return result

## No inverse of the child's PRSA is needed, so even collapsed children can be moved.
func reparent(id: int, parent: int, time: float) -> bool:
	if not can_parent(id, parent):
		error = "Choose World or a group outside this node's subtree."
		return false
	var state = sample(time)
	if state == null: return false
	var parent_inverse := inverse(state[parent].world)
	if parent_inverse.is_empty():
		error = "Cannot preserve world pose: destination group has zero or singular scale at this time."
		return false
	var entry: Dictionary = entries[id]
	entry.offset = Math4D.multiply(Math4D.multiply(parent_inverse, state[entry.parent].world), entry.offset)
	entry.parent = parent
	return true

## Removing a group promotes its children atomically, preserving their world matrices.
func remove(id: int, time: float) -> bool:
	var children := []
	for child in entries:
		if entries[child].parent == id: children.append(child)
	if not children.is_empty():
		var state = sample(time)
		if state == null: return false
		var parent: int = entries[id].parent
		var inv := inverse(state[parent].world)
		if inv.is_empty():
			error = "Cannot remove this group while its parent transform is singular."
			return false
		var correction := Math4D.multiply(inv, state[id].world)
		for child in children:
			entries[child].offset = Math4D.multiply(correction, entries[child].offset)
			entries[child].parent = parent
	entries.erase(id)
	return true

func local_sample(id: int, time: float) -> Variant:
	return entries[id].model.sample(time)
