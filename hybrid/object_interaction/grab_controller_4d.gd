extends RefCounted
## One active grab per player. Owns the interaction; the room owns its boxes,
## input, scene transforms and puzzle rules. All collision bounds are in XYZW.
const Placement = preload("res://hybrid/object_interaction/box_placement_4d.gd")

enum Hold { RELEASED, RESIZE, CARRY }
enum Result { OK, ALREADY_HOLDING, DISABLED, MISS, RESIZING, DESTINATION_BLOCKED, PATH_BLOCKED }

class Box extends RefCounted:
	var position: Vector4
	var base_half: Vector4
	var scale: float
	var min_scale := 0.25
	var max_scale := 6.0
	var can_resize := true
	var can_carry := true

	func _init(center: Vector4, half: Vector4, initial_scale: float = 1.0) -> void:
		position = center
		base_half = half
		scale = initial_scale

	func half_extents() -> Vector4:
		return base_half * scale

	func in_slice(eye: Vector4, hidden: int) -> bool:
		return absf(eye[hidden] - position[hidden]) < half_extents()[hidden]

var player_half: Vector4
var resize_reach := 2.5
var carry_reach := 24.0
var carry_gap := 0.85
var carry_speed := 12.0
var hold := Hold.RELEASED
var held: Box
var carry_limited := false
var _anchor_offset := Vector4.ZERO
var _scale_per_depth := 1.0

func _init(player_half_extents: Vector4) -> void:
	player_half = player_half_extents

## A slice supplies three display-to-world axis indices and the remaining hidden axis.
## Obstacles are {low, high} world bounds and exclude the candidate or held box.
func pickup(box: Box, action: Hold, player: Vector4, slice: Dictionary,
		forward: Vector3, obstacles: Array[Dictionary]) -> Result:
	if held != null:
		return Result.ALREADY_HOLDING
	if not ((action == Hold.RESIZE and box.can_resize) or (action == Hold.CARRY and box.can_carry)):
		return Result.DISABLED
	var direction := _lift(forward.normalized(), slice.axes)
	var reach := resize_reach if action == Hold.RESIZE else carry_reach
	var depth := _hit_depth(box, player, slice.hidden, direction * reach, reach, obstacles)
	if depth <= 0.0:
		return Result.MISS
	if action == Hold.RESIZE:
		_anchor_offset = (player + direction * depth - box.position) / box.scale
		_scale_per_depth = box.scale / depth
	held = box
	hold = action
	return Result.OK

## The accepted position and scale remain on the box after release.
func release() -> Box:
	var box := held
	held = null
	hold = Hold.RELEASED
	carry_limited = false
	return box

## On success the host can activate this slice. Failed transfers leave the box unchanged.
func try_switch_slice(player: Vector4, slice: Dictionary, forward: Vector3,
		obstacles: Array[Dictionary]) -> Result:
	if hold == Hold.RESIZE:
		return Result.RESIZING
	if held == null:
		return Result.OK
	if forward.is_zero_approx():
		return Result.MISS
	var half := held.half_extents()
	var direction := _lift(forward.normalized(), slice.axes)
	var near := player + direction * _minimum_carry_distance(direction, half)
	var far := near + direction * _carry_gap(half)
	var constraints := _with_player(obstacles, player)
	if not _clear_path(near, near, half, constraints):
		return Result.DESTINATION_BLOCKED
	var destination := near.lerp(far, Placement.safe_fraction(near, far, half, half, constraints))
	if not _clear_path(held.position, destination, half, constraints):
		# Move along the newly visible axes before centering on the new slice.
		var hidden: int = slice.hidden
		var corner := destination
		corner[hidden] = held.position[hidden]
		if not _clear_path(held.position, corner, half, constraints) or not _clear_path(corner, destination, half, constraints):
			return Result.PATH_BLOCKED
	held.position = destination
	carry_limited = false
	return Result.OK

func update(player: Vector4, slice: Dictionary, forward: Vector3, delta: float,
		obstacles: Array[Dictionary]) -> void:
	if forward.is_zero_approx():
		return
	match hold:
		Hold.RESIZE: _resize_toward_aim(player, slice, forward.normalized(), obstacles)
		Hold.CARRY: _carry_toward_aim(player, slice.axes, forward.normalized(), delta, obstacles)

## Optional movement helper. The host still owns the returned player pose.
## Supply other solid boxes, including released objects. The held box is handled here.
func move_player(player: Vector4, requested: Vector4, axes: Array, obstacles: Array[Dictionary]) -> Vector4:
	if hold == Hold.CARRY:
		return _move_carry(player, requested, axes, obstacles)
	var constraints := obstacles
	if held != null:
		constraints = obstacles.duplicate()
		constraints.append(Placement.bounds(held.position, held.half_extents()))
	for axis in axes:
		var step := Vector4.ZERO
		step[axis] = requested[axis]
		player += step * Placement.safe_fraction(player, player + step, player_half, player_half, constraints)
	return player

static func _hit_depth(box: Box, origin: Vector4, hidden: int, ray: Vector4,
		reach: float, obstacles: Array[Dictionary]) -> float:
	if not box.in_slice(origin, hidden):
		return -1.0
	var end := origin + ray
	var half := box.half_extents()
	var hit := Placement.overlap_interval(origin, end, Vector4.ZERO, Vector4.ZERO,
		box.position - half, box.position + half)
	if hit.x < 0.0:
		return -1.0
	for solid in obstacles:
		var occlusion := Placement.overlap_interval(origin, end, Vector4.ZERO, Vector4.ZERO,
			solid.low, solid.high)
		if occlusion.x >= 0.0 and occlusion.x <= hit.x:
			return -1.0
	return hit.x * reach

func _carry_toward_aim(player: Vector4, axes: Array, aim: Vector3, delta: float,
		obstacles: Array[Dictionary]) -> void:
	var half := held.half_extents()
	var offset := held.position - player
	var heading := Vector3(offset[axes[0]], offset[axes[1]], offset[axes[2]]).normalized()
	if heading.dot(aim) < 0.5 and not heading.is_zero_approx():
		# Steer around the body on a sharp turn instead of pulling through it.
		var axis := heading.cross(aim)
		if axis.length_squared() < 0.000001:
			axis = Vector3.UP if absf(heading.y) < 0.9 else Vector3.RIGHT
		aim = heading.rotated(axis.normalized(), PI / 6.0)
	var direction := _lift(aim, axes)
	var target := player + direction * (_minimum_carry_distance(direction, half) + _carry_gap(half))
	var travel := target - held.position
	if travel.is_zero_approx():
		carry_limited = false
		return
	var step := minf(1.0, carry_speed * delta / travel.length())
	var next := held.position + travel * step
	var fraction := Placement.safe_fraction(held.position, next, half, half, _with_player(obstacles, player))
	carry_limited = fraction < 1.0
	if fraction > 0.0:
		held.position = held.position.lerp(next, fraction)

func _resize_toward_aim(player: Vector4, slice: Dictionary, aim: Vector3,
		obstacles: Array[Dictionary]) -> void:
	var eye := player
	var hidden: int = slice.hidden
	var hidden_gap := absf(eye[hidden] - held.position[hidden])
	var min_scale := maxf(held.min_scale, (hidden_gap + Placement.SKIN) / held.base_half[hidden])
	var max_scale := held.max_scale
	if min_scale > max_scale:
		return
	# Anchor stays under the crosshair. Keep the center's hidden coordinate fixed.
	var center_per_scale := _lift(aim / _scale_per_depth, slice.axes) - _anchor_offset
	center_per_scale[hidden] = 0.0
	eye[hidden] = held.position[hidden]
	var first := eye + center_per_scale * min_scale
	var last := eye + center_per_scale * max_scale
	var first_half := held.base_half * min_scale
	var last_half := held.base_half * max_scale
	# Start at the first depth that clears the player. For fixed aim all box faces
	# are affine in scale, and the player's overlap is a single interval.
	var player_clearance := player_half + Vector4.ONE * Placement.SKIN
	var overlap := Placement.overlap_interval(first, last, first_half, last_half,
		player - player_clearance, player + player_clearance)
	if overlap.x >= 0.0:
		if overlap.y >= 1.0:
			return
		min_scale = lerpf(min_scale, max_scale, overlap.y + 0.00001)
		first = eye + center_per_scale * min_scale
		first_half = held.base_half * min_scale
	if Placement.safe_fraction(first, first, first_half, first_half, obstacles) == 0.0:
		return
	var depth_fraction := Placement.safe_fraction(first, last, first_half, last_half, obstacles)
	var candidate_scale := lerpf(min_scale, max_scale, depth_fraction)
	var candidate := eye + center_per_scale * candidate_scale
	# New aim or eye position can move the box sideways. Validate that sweep too.
	var travel := Placement.safe_fraction(held.position, candidate, held.half_extents(),
		held.base_half * candidate_scale, _with_player(obstacles, player))
	if travel > 0.0:
		held.position = held.position.lerp(candidate, travel)
		held.scale = lerpf(held.scale, candidate_scale, travel)

func _move_carry(player: Vector4, requested: Vector4, axes: Array, obstacles: Array[Dictionary]) -> Vector4:
	var center := held.position
	var half := held.half_extents()
	for axis in axes:
		var step := Vector4.ZERO
		step[axis] = requested[axis]
		if step.is_zero_approx():
			continue
		var player_fraction := Placement.safe_fraction(player, player + step, player_half, player_half, obstacles)
		var object_fraction := Placement.safe_fraction(center, center + step, half, half, obstacles)
		var shared_step := step * minf(player_fraction, object_fraction)
		center += shared_step
		player += shared_step
		if object_fraction < player_fraction:
			# The held box can stop at a wall while the player steers around it.
			var extra := step * (player_fraction - object_fraction)
			var box_bounds: Array[Dictionary] = [Placement.bounds(center, half)]
			player += extra * Placement.safe_fraction(player, player + extra, player_half, player_half, box_bounds)
	held.position = center
	return player

func _minimum_carry_distance(direction: Vector4, half: Vector4) -> float:
	# The first face of the expanded player box crossed by the center ray.
	var clearance := half + player_half + Vector4.ONE * (Placement.SKIN * 2.0)
	var distance := INF
	for axis in range(4):
		if absf(direction[axis]) > 0.000001:
			distance = minf(distance, clearance[axis] / absf(direction[axis]))
	return distance

func _carry_gap(half: Vector4) -> float:
	# Give large boxes more room so the player can see around them.
	return maxf(carry_gap, half.length() * 0.8)

func _with_player(obstacles: Array[Dictionary], player: Vector4) -> Array[Dictionary]:
	var constraints := obstacles.duplicate()
	constraints.append(Placement.bounds(player, player_half))
	return constraints

static func _clear_path(from: Vector4, to: Vector4, half: Vector4, constraints: Array[Dictionary]) -> bool:
	return Placement.safe_fraction(from, to, half, half, constraints) == 1.0

static func _lift(direction: Vector3, axes: Array) -> Vector4:
	var result := Vector4.ZERO
	for axis in range(3):
		result[axes[axis]] = direction[axis]
	return result
