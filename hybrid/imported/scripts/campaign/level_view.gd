extends "res://hybrid/imported/scripts/game/slice_view.gd"
## Presentation only. X-ray mode makes the enclosing tunnel shell readable;
## colliders are never hidden or removed when transparency changes.
var xray := false
var show_route := false

func rebuild(world: RefCounted, point: Vector4, new_mode: int) -> void:
	mode = new_mode
	for child in geometry.get_children():
		geometry.remove_child(child)
		child.queue_free()
	var coordinate: float = point[World.MODES[mode].hidden]
	var low := World.to_view(world.definition.low, mode)
	var high := World.to_view(world.definition.high, mode)
	view_center = (low + high) * 0.5
	visible_solids = 0
	for id in world.solid_ids:
		var points: PackedVector3Array = world.slice_points(id, mode, coordinate)
		if points.is_empty(): continue
		visible_solids += 1
		var renderer := SolidRenderer.new()
		geometry.add_child(renderer)
		renderer.set_meta("role", world.scene.objects[id].name)
		var color := Color("527b9c") if world.scene.objects[id].name == "gate" else Color("3f657f")
		if world.scene.objects[id].name == "exit_gate": color = Color("dc726d")
		renderer.render({"visible": true, "color": color, "show_edges": true}, points)
		if xray:
			renderer.face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			renderer.face_material.albedo_color.a = 0.12
			renderer.edge_material.albedo_color = Color(0.42, 0.65, 0.78, 0.24)
	add_wire_box(view_center, high - low, Color("344e68"))
	add_grid(low, high)
	add_axes(low, high)
	for i in range(world.marker_ids.size()):
		var points: PackedVector3Array = world.slice_points(world.marker_ids[i], mode, coordinate)
		var color := CYAN if i == world.stage else Color("496e82")
		if i == world.marker_ids.size() - 1: color = GOLD
		if not points.is_empty():
			add_region(points, color, "%02d%s" % [i + 1, "  /  EXIT" if i == world.marker_ids.size() - 1 else ""])
		elif i == world.stage:
			var marker := make_label("%02d  /  OTHER SLICE" % (i + 1), World.to_view(world.definition.route[i], mode) + Vector3(0, 1.15, 0), Color("c3a0ff"), 20)
			marker.no_depth_test = true
			geometry.add_child(marker)
	if show_route:
		var previous: Vector4 = world.definition.start
		for next in world.definition.route:
			var hidden: int = World.MODES[mode].hidden
			if absf(previous[hidden] - coordinate) < 0.6 and absf(next[hidden] - coordinate) < 0.6:
				add_lines([World.to_view(previous, mode), World.to_view(next, mode)], CYAN)
			previous = next
	set_player(point)
	update_camera()

func orbit(relative: Vector2) -> void:
	# Full horizontal orbit and almost pole-to-pole elevation, avoiding look_at's
	# singularity when the view direction is exactly parallel to Vector3.UP.
	yaw = wrapf(yaw - relative.x * 0.007, -PI, PI)
	pitch = clampf(pitch + relative.y * 0.007, -PI / 2.0 + 0.01, PI / 2.0 - 0.01)
	update_camera()
