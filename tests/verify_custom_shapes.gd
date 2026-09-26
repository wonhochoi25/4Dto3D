extends SceneTree
const Registry = preload("res://scripts/shapes/shape_registry.gd")
const Model = preload("res://scripts/procedural/procedural_object.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	# Temporary catalog proves multiple discovery entries and duplicate-name independence.
	var directory := "res://tests/custom_fixtures_temp"
	DirAccess.make_dir_recursive_absolute(directory)
	var data := {"name":"Same label", "vertices":[[0,0,0,0],[1,0,0,0]], "edges":[[0,1]], "procedural_defaults":{
		"geometry":{"position":{"X":"t+2"},"anchor":{"X":"1"},"scale":{"X":2},"rotation":{"XW":"30*t"},"projection":[[1,0,0,0],[0,1,0,0],[0,0,0,1]]},
		"group":{"position":{"Y":"3"},"anchor":{"Y":"1"},"scale":"2", "rotation":{"ZW":"15*t"}}}}
	for filename in ["b.json", "a.json"]:
		var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
	var saved := Registry.ENTRIES
	Registry.ENTRIES = Registry.discover(directory)
	check(Registry.ENTRIES.size() == 9, "Seven built-ins plus two files")
	check(Registry.ENTRIES[7].path.ends_with("a.json"), "Sorted discovery")
	check(Registry.ENTRIES[7].id != Registry.ENTRIES[8].id, "Stable independent path IDs")
	var scene = load("res://scripts/procedural/procedural_scene.gd").new()
	root.add_child(scene)
	var a = scene.add_shape(7)
	var b = scene.add_shape(8)
	check(a != null and b != null, "Add both custom entries")
	check(a.object.sources["position.0"] == "t+2", "Literal position, no anchor compensation")
	check(a.object.sources["anchor.0"] == "1" and float(a.object.sources["scale.0"]) == 2, "Geometry anchor and numeric scale")
	check(a.fields["angles.2"].text == "30*t" and float(a.fields["projection.11"].text) == 1, "Rotation and projection in editor")
	var group = scene.pairs[a.get_meta("group_id")].group_card
	check(group.fields["position.1"].text == "3" and group.fields["anchor.1"].text == "1", "Literal group defaults")
	check(group.object.sources["scale.3"] == "2", "Uniform group scale")
	check(scene.evaluate_time(2) and scene.evaluate_time(0), "Time-dependent sampling")
	a.object.shape.vertices[0].x = 99
	check(b.object.shape.vertices[0].x == 0, "Independent geometry instances")
	var model := Model.new(-1)
	check(not model.initialize_defaults({"rotation":{"XY":"invalid("}},0), "Invalid expression rejected")
	check(model.sources["angles.0"] == "0", "Invalid defaults leave compiled state intact")
	Registry.ENTRIES = saved
	for filename in ["a.json", "b.json"]: DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	print("Custom shape failures: ", failures)
	quit(1 if failures else 0)
