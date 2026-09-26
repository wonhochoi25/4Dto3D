extends VBoxContainer
## Playback requests times; the scene accepts only a fully valid evaluated frame.
signal time_requested(value: float)
signal range_changed(previous_start: float)
const STEP := 1.0 / 60.0
var remainder := 0.0
var busy := false
var time := 0.0
var direction := 0
var start := 0.0
var end := 10.0
var speed := 1.0
var looping := false
var slider: HSlider
var time_field: SpinBox
var start_field: SpinBox
var end_field: SpinBox
var message: Label

func _ready() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	button(row, "◀ Reverse", func(): direction = -1)
	button(row, "Pause", pause)
	button(row, "Forward ▶", func(): direction = 1)
	button(row, "Restart", func(): pause(); time_requested.emit(start))
	text(row, "Speed")
	var speed_field := number(row, 1)
	speed_field.min_value = 0.01
	speed_field.max_value = 100
	speed_field.allow_lesser = false
	speed_field.allow_greater = false
	speed_field.value_changed.connect(func(value: float): speed = value)
	var loop := CheckBox.new()
	loop.text = "Loop"
	loop.toggled.connect(func(value: bool): looping = value)
	row.add_child(loop)
	var time_row := HBoxContainer.new()
	add_child(time_row)
	text(time_row, "t (seconds)")
	time_field = number(time_row, 0)
	time_field.value_changed.connect(func(value: float): scrub(value))
	slider = HSlider.new()
	slider.min_value = start
	slider.max_value = end
	slider.step = STEP
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(scrub)
	time_row.add_child(slider)
	text(time_row, "Start")
	start_field = number(time_row, start)
	text(time_row, "End")
	end_field = number(time_row, end)
	button(time_row, "Set range", set_range)
	message = Label.new()
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.text = "Paused · t in seconds · rotation outputs in degrees"
	add_child(message)

func pause() -> void:
	direction = 0
	remainder = 0.0

func scrub(value: float) -> void:
	pause()
	if is_finite(value): time_requested.emit(clampf(value, start, end))

func set_range() -> void:
	start_field.apply()
	end_field.apply()
	if not is_finite(start_field.value) or not is_finite(end_field.value) or start_field.value >= end_field.value:
		message.text = "Start must be finite and less than End."
		return
	pause()
	var previous_start := start
	start = start_field.value
	end = end_field.value
	slider.set_block_signals(true)
	slider.max_value = maxf(end, slider.max_value)
	slider.min_value = start
	slider.max_value = end
	slider.set_block_signals(false)
	range_changed.emit(previous_start)

func accept(value: float) -> void:
	time = value
	slider.set_value_no_signal(time)
	time_field.set_value_no_signal(time)
	time_field.get_line_edit().text = "%.3f" % time
	message.text = "t = %.3f s" % time

func _process(delta: float) -> void:
	if direction == 0 or busy: return
	remainder += delta * speed
	var steps := int(floor(remainder / STEP))
	if steps == 0: return
	remainder -= steps * STEP
	var last := maxi(0, int(floor((end - start) / STEP + 0.000001)))
	var index := int(round((time - start) / STEP)) + steps * direction
	if index > last or index < 0:
		if looping: index = posmod(index, maxi(1, last))
		else:
			index = clampi(index, 0, last)
			pause()
	var next_time := start + index * STEP
	time_requested.emit(next_time)

func button(parent: Node, title: String, action: Callable) -> void:
	var result := Button.new()
	result.text = title
	result.pressed.connect(action)
	parent.add_child(result)
func text(parent: Node, title: String) -> void:
	var result := Label.new()
	result.text = title
	parent.add_child(result)
func number(parent: Node, value: float) -> SpinBox:
	var result := SpinBox.new()
	result.allow_greater = true
	result.allow_lesser = true
	result.step = 0.001
	result.value = value
	result.custom_minimum_size.x = 90
	parent.add_child(result)
	return result
