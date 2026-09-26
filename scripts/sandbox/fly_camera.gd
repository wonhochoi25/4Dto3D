extends Camera3D
## Controls only the 3D viewing camera; never modifies the 4D model or projection.
## Movement speed in world units per second.
var speed := 4.0
## Mouse sensitivity in radians per screen pixel.
var sensitivity := 0.003

## Restore a useful starting position looking at the world origin.
func reset_view() -> void:
	position = Vector3(4, 3, 6)
	look_at(Vector3.ZERO)

## Initialize the viewing pose when the scene starts.
func _ready() -> void:
	reset_view()

## Begin mouse capture only when a right-click was not consumed by the UI.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		get_viewport().gui_release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

## Handle captured look motion before GUI dispatch and release capture on RMB-up/Esc.
func _input(event: InputEvent) -> void:
	# Captured motion must be processed before GUI controls can consume it.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.screen_relative.x * sensitivity
		rotation.x = clampf(rotation.x - event.screen_relative.y * sensitivity, -1.55, 1.55)
		rotation.z = 0.0
		get_viewport().set_input_as_handled()
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed) or (event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Release the cursor when the application loses focus.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Move in camera-relative directions; Q/E add world-vertical movement.
## Movement is independent of mouse capture but pauses while a UI control has focus.
func _process(delta: float) -> void:
	# Free movement is allowed, except while interacting with the panel.
	if not DisplayServer.window_is_focused() or get_viewport().gui_get_focus_owner() != null:
		return
	var direction := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		0,
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var movement := basis * direction
	movement.y += float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	var boost := 3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	# Normalize to avoid faster diagonal movement; delta makes speed frame-independent.
	position += movement.normalized() * speed * boost * delta
