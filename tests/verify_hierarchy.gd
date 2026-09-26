extends SceneTree
const Model = preload("res://scripts/procedural/procedural_object.gd")
const Graph = preload("res://scripts/procedural/scene_graph_4d.gd")
const Math4D = preload("res://scripts/geometry/transform_4d.gd")
var failures := 0
func check(value: bool, text: String) -> void:
	if not value:
		failures += 1
		push_error(text)
func matrices_close(a, b) -> bool:
	for i in range(25):
		if absf(a[i] - b[i]) > 0.00001: return false
	return true
func configure(model, changes: Dictionary, time: float = 2) -> void:
	var expressions = model.sources.duplicate()
	for key in changes: expressions[key] = changes[key]
	check(model.apply_sources(expressions, time), "Expression setup: " + model.error)
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	var graph := Graph.new()
	var parent := Model.new(-1)
	var nested := Model.new(-1)
	var child := Model.new(0)
	var sibling := Model.new(3)
	configure(parent, {"position.0": "t", "angles.2": "30*t", "scale.0": "2"})
	configure(nested, {"position.1": "3", "angles.4": "15*t", "scale.0": "0.5"})
	configure(child, {"scale.0": "3", "scale.1": "0", "angles.1": "20"})
	var a := graph.add(parent)
	var b := graph.add(nested)
	var c := graph.add(child)
	var d := graph.add(sibling)
	var before = graph.sample(2)
	check(graph.reparent(b, a, 2), "Parent group")
	check(graph.reparent(c, b, 2), "Parent zero-scale geometry")
	var after = graph.sample(2)
	check(matrices_close(before[b].world, after[b].world), "Group world preserved")
	check(matrices_close(before[c].world, after[c].world), "Geometry world preserved")
	check(not graph.can_parent(a, b), "Cycles prevented")
	check(not graph.can_parent(a, a), "Self-parent prevented")
	check(not graph.can_parent(b, c), "Geometry cannot parent")
	var at_three = graph.sample(3)
	check(not matrices_close(at_three[c].world, after[c].world), "Child follows group over time")
	check(matrices_close(at_three[d].world, after[d].world), "Sibling outside group unaffected")
	check(matrices_close(graph.sample(2)[c].world, after[c].world), "Reverse deterministic")
	check(graph.reparent(b, 0, 3), "Unparent subtree")
	check(matrices_close(graph.sample(3)[c].world, at_three[c].world), "Subtree world preserved")
	var child_before = graph.sample(3)[c].world
	check(graph.remove(b, 3), "Remove group")
	check(graph.entries[c].parent == 0 and matrices_close(graph.sample(3)[c].world, child_before), "Promote children preserving pose")
	configure(parent, {"scale.0": "0"})
	check(not graph.reparent(c, a, 2), "Singular destination refused")
	check(graph.entries[c].parent == 0, "Failed reparent atomic")
	var scale_values = parent.sample(2).matrix
	check(scale_values[0] == 0 and scale_values[6] == 0, "Group scale is uniform")
	root.size = Vector2i(1440, 900)
	var scene = load("res://scripts/procedural/procedural_scene.gd").new()
	root.add_child(scene)
	var parent_card = scene.add_shape(3)
	var card = scene.add_shape(0)
	var group_id: int = parent_card.get_meta("group_id")
	var shape_id: int = card.get_meta("group_id")
	var geometry_id: int = card.get_meta("node_id")
	var parent_geometry_id: int = parent_card.get_meta("node_id")
	var group_card = scene.pairs[group_id].group_card
	check(scene.graph.entries.size() == 4 and scene.cards.size() == 2, "Automatic pairs")
	check(group_card.fields.has("scale.0") and not group_card.fields.has("scale.1") and not group_card.fields.has("projection.0"), "Group-specific editor")
	check(scene.pairs[shape_id].editor.get_tab_title(0) == "Geometry" and scene.pairs[shape_id].editor.get_tab_title(1) == "Group", "Two named tabs")
	card.fields["position.0"].text = "sin(t)"
	var group_draft = scene.pairs[shape_id].group_card
	group_draft.fields["position.1"].text = "cos(t)"
	var original_pose = scene.graph.sample(0)[geometry_id].world
	check(scene.reparent_node(shape_id, group_id), "UI parenting")
	check(matrices_close(original_pose, scene.graph.sample(0)[geometry_id].world), "Pair parenting preserves pose")
	for i in range(4): await process_frame
	check(card.fields["position.0"].text == "sin(t)" and group_draft.fields["position.1"].text == "cos(t)", "Both drafts preserved")
	check(card.is_visible_in_tree(), "Selected inline editor visible")
	scene.pairs[shape_id].editor.current_tab = 1
	scene.select_card(parent_card)
	scene.select_card(card)
	for i in range(3): await process_frame
	check(group_draft.is_visible_in_tree() and not card.is_visible_in_tree(), "Group tab selection survives tree rebuild")
	scene.pairs[shape_id].editor.current_tab = 0
	var rows = scene.list.find_children("*", "Button", true, false)
	var tree_rows := 0
	for row in rows:
		if row.get_script() == load("res://scripts/sandbox/procedural/hierarchy_row.gd"): tree_rows += 1
	check(tree_rows == 3, "Only World and two shape rows")
	configure(parent_card.object, {"position.0": "10"}, 0)
	var geometry_edit = scene.graph.sample(0)
	check(matrices_close(original_pose, geometry_edit[geometry_id].world), "Parent geometry does not move child")
	check(not matrices_close(original_pose, geometry_edit[parent_geometry_id].world), "Parent geometry moves itself")
	configure(group_card.object, {"position.1": "t+4"}, 0)
	var group_edit = scene.graph.sample(0)
	check(not matrices_close(original_pose, group_edit[geometry_id].world), "Parent group moves child")
	check(not matrices_close(geometry_edit[parent_geometry_id].world, group_edit[parent_geometry_id].world), "Parent group moves own geometry")
	var world = scene.list.get_child(0)
	var payload = {"hierarchy": scene, "id": shape_id}
	check(world._can_drop_data(Vector2.ZERO, payload), "World accepts unparent drop")
	world._drop_data(Vector2.ZERO, payload)
	check(scene.graph.entries[shape_id].parent == 0, "Drop unparents pair")
	check(matrices_close(group_edit[geometry_id].world, scene.graph.sample(0)[geometry_id].world), "Unparent preserves geometry pose")
	check(scene.reparent_node(shape_id, group_id), "Reparent before removal")
	var old_world = scene.graph.sample(0)[geometry_id].world
	scene.remove_card(parent_card)
	check(scene.graph.entries.size() == 2 and scene.pairs.size() == 1, "Deleting shape removes pair")
	check(scene.graph.entries[shape_id].parent == 0 and matrices_close(old_world, scene.graph.sample(0)[geometry_id].world), "Delete promotes child preserving pose")
	# Reset the pair offset for a deterministic center picking check.
	scene.graph.entries[shape_id].offset = Math4D.identity()
	scene.evaluate_time(0)
	# Ray selection uses actual projected triangles, with no 3D collision proxies.
	scene.select_card(null)
	var center: Vector2 = scene.camera.unproject_position(Vector3.ZERO)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = center
	scene._unhandled_input(event)
	check(scene.selected_card == card, "Viewport face picking")
	scene.select_card(null)
	for i in range(3): await process_frame
	check(not card.is_visible_in_tree(), "Default tree without editor")
	print("Hierarchy failures: ", failures)
	quit(1 if failures else 0)
