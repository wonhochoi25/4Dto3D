extends SceneTree
const Exporter = preload("res://scripts/io/shape_json_exporter.gd")
const Loader = preload("res://scripts/io/shape_json_loader.gd")
const Model = preload("res://scripts/sandbox/procedural/object_view_model.gd")
var failures := 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func _initialize():
	var model := Model.new(0)
	var group := Model.new(-1)
	var sources: Dictionary = model.sources.duplicate()
	for key in sources:
		sources[key] = "1+t*0.1" if key.begins_with("scale") else "sin(t)+0.25"
	model.track.keep_anchor_in_place = false
	check(model.apply_sources(sources,0),"Geometry compile")
	var gs: Dictionary = group.sources.duplicate()
	for key in gs: gs[key] = "2+t*0.2"
	group.track.keep_anchor_in_place = false
	check(group.apply_sources(gs,0),"Group compile")
	model.shape.vertices[0] = Vector4(0.5,2,-3,4)
	var data := Exporter.serialize_shape(model.shape,"Exported test",model.track.sources,group.track.sources,model.projection_track.sources)
	var path := OS.get_environment("TMPDIR").path_join("godot-shape-export-%d.json" % OS.get_process_id())
	check(Exporter.save(path,data)==OK,"Write JSON")
	var loaded := Loader.new(path)
	check(loaded.vertices==model.shape.vertices and loaded.edges==model.shape.edges,"Local edited geometry roundtrip")
	check(JSON.stringify(loaded.faces)==JSON.stringify(model.shape.faces),"Faces roundtrip")
	var restored := Model.new(0)
	var restored_group := Model.new(-1)
	check(restored.initialize_defaults(loaded.procedural_defaults.geometry,0),"Reload geometry defaults")
	check(restored_group.initialize_defaults(loaded.procedural_defaults.group,0),"Reload group defaults")
	check(restored.sources==model.sources,"All geometry/projection expressions preserved")
	check(restored_group.track.sources==group.track.sources,"All group expressions preserved")
	check(not data.has("parent") and data.keys().size()==5,"Existing schema only")
	DirAccess.remove_absolute(path)
	print("Shape export failures: ",failures)
	quit(1 if failures else 0)
