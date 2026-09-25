extends SceneTree
## Headless layout check: tabs use physical pixels without scaling their UI or hit targets.
func _initialize() -> void: call_deferred("verify")
func verify() -> void:
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	app.new_procedural()
	for window_size in [Vector2i(1440, 900), Vector2i(2880, 1800), Vector2i(3024, 1964), Vector2i(1440, 900)]:
		root.size = window_size
		for i in range(5): await process_frame
		for page in app.pages:
			var expected: Vector2 = (app.content.size * root.get_final_transform().get_scale()).round()
			assert(page.viewport.size == Vector2i(expected))
			assert(page.viewport.get_visible_rect().size.is_equal_approx(app.content.size))
			assert((page.host.size * page.host.scale).is_equal_approx(app.content.size))
			# Physical-to-logical viewport scaling cancels container counter-scaling.
			var mapping: Vector2 = page.viewport.get_final_transform().get_scale() * page.host.scale
			assert(mapping.is_equal_approx(Vector2.ONE))
			assert(page.viewport.msaa_3d == Viewport.MSAA_4X)
	print("PASS: native resolution, logical UI/input mapping, resize, both tabs, 4x MSAA")
	quit()
