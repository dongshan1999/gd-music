extends Node

## 滚动交互回归测试：触摸手势 1:1 跟手、松手惯性、滚动不触发行点击、
## 以及触摸设备同时派发的模拟鼠标事件不能造成双倍滚动。

const SCROLL_SCRIPT := preload("res://assets/scripts/ui/music_app/music_app_scroll.gd")
const ROW_HEIGHT := 72.0
const VIEW_HEIGHT := 600.0

var _failures := PackedStringArray()
var _root: Control
var _scroll: ScrollContainer
var _interaction: Node
var _container: VBoxContainer
var _row_pressed := 0
var _row: Button

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_touch_drag_tracks_finger()
	await _test_emulated_mouse_events_do_not_double_scroll()
	await _test_touch_fling_continues_then_stops()
	await _test_drag_does_not_click_row()
	await _test_tap_still_clicks_row()
	await _test_fling_brake_tap_does_not_click()
	for failure in _failures:
		push_error(failure)
	print("Music app scroll tests: %s failures" % _failures.size())
	get_tree().quit(OK if _failures.is_empty() else FAILED)

func _build_list() -> void:
	if _root != null:
		_root.queue_free()
		await get_tree().process_frame

	_row_pressed = 0
	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = Vector2(430, VIEW_HEIGHT)
	add_child(_root)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2.ZERO
	_scroll.size = Vector2(430, VIEW_HEIGHT)
	_root.add_child(_scroll)

	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", 0)
	_scroll.add_child(_container)

	for i in 30:
		var button := Button.new()
		button.custom_minimum_size = Vector2(430, ROW_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _row_pressed += 1)
		_container.add_child(button)
		if i == 0:
			_row = button

	_interaction = Node.new()
	_interaction.set_script(SCROLL_SCRIPT)
	_interaction.scroll_container_path = NodePath("..")
	_scroll.add_child(_interaction)

	# 等容器完成一次排序，滚动条的 max_value 才是真实值。
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = 0

func _test_touch_drag_tracks_finger() -> void:
	await _build_list()
	_check(_max_scroll() > 0.0, "List content is taller than the viewport")

	var before := _scroll.scroll_vertical
	_touch_press(Vector2(200, 300))
	# 每一步都小于阈值，只有累加后才会开始滚动。
	_touch_drag(Vector2(200, 290), Vector2(0, -10), Vector2(0, -800))
	_touch_drag(Vector2(200, 280), Vector2(0, -10), Vector2(0, -800))
	var moved := _scroll.scroll_vertical - before
	_check(moved == 20, "Touch drag scrolls exactly with the finger (%d px for 20 px)" % moved)
	_touch_release(Vector2(200, 280))

## 触摸设备会把同一手势再派发一份模拟鼠标事件（device == -1），不能重复滚动。
func _test_emulated_mouse_events_do_not_double_scroll() -> void:
	await _build_list()

	_touch_press(Vector2(200, 300))
	_emulated_mouse_press(Vector2(200, 300))
	_touch_drag(Vector2(200, 288), Vector2(0, -12), Vector2(0, -800))
	_emulated_mouse_motion(Vector2(200, 288), Vector2(0, -12))
	_touch_drag(Vector2(200, 276), Vector2(0, -12), Vector2(0, -800))
	_emulated_mouse_motion(Vector2(200, 276), Vector2(0, -12))
	var moved := _scroll.scroll_vertical
	_check(moved == 24, "Emulated mouse events do not scroll twice (%d px for 24 px)" % moved)
	_touch_release(Vector2(200, 276))

func _test_touch_fling_continues_then_stops() -> void:
	await _build_list()
	_touch_press(Vector2(200, 300))
	_touch_drag(Vector2(200, 290), Vector2(0, -10), Vector2(0, -1200))
	_touch_drag(Vector2(200, 280), Vector2(0, -10), Vector2(0, -2000))
	_touch_drag(Vector2(200, 270), Vector2(0, -10), Vector2(0, -2400))
	var release_position := _scroll.scroll_vertical
	_touch_release(Vector2(200, 270))
	_check(_interaction._fling_active, "Releasing a fast drag starts fling scrolling")
	await get_tree().create_timer(0.25).timeout
	var after := _scroll.scroll_vertical
	_check(
		after > release_position + 20,
		"Fling keeps scrolling after release (%d -> %d)" % [release_position, after]
	)
	await get_tree().create_timer(2.0).timeout
	var settled := _scroll.scroll_vertical
	_check(not _interaction._fling_active, "Fling stops by itself")
	_check(settled <= int(_max_scroll()) + 1, "Fling never scrolls past the end")
	await get_tree().process_frame
	_check(absf(_scroll.scroll_vertical - settled) < 2, "Scroll stays put after fling settles")

func _test_drag_does_not_click_row() -> void:
	await _build_list()
	# 按下落在第一行上：这是「手指放下就被当成选中」的复现路径。
	_emulated_mouse_press(Vector2(200, ROW_HEIGHT * 0.5))
	_touch_press(Vector2(200, ROW_HEIGHT * 0.5))
	_check(_row.get_draw_mode() == Button.DRAW_PRESSED, "Pressing a row shows the pressed state")
	_touch_drag(Vector2(200, ROW_HEIGHT * 0.5 - 12), Vector2(0, -12), Vector2(0, -600))
	_touch_drag(Vector2(200, ROW_HEIGHT * 0.5 - 30), Vector2(0, -18), Vector2(0, -900))
	_check(_row.get_draw_mode() != Button.DRAW_PRESSED, "Dragging clears the pressed highlight")
	_emulated_mouse_release(Vector2(200, ROW_HEIGHT * 0.5 - 30))
	_touch_release(Vector2(200, ROW_HEIGHT * 0.5 - 30))
	_check(_row_pressed == 0, "Scrolling over a row does not press it")
	_check(_scroll.scroll_vertical > 0, "The drag actually scrolled the list")

func _test_tap_still_clicks_row() -> void:
	await _build_list()
	_emulated_mouse_press(Vector2(200, ROW_HEIGHT * 0.5))
	_touch_press(Vector2(200, ROW_HEIGHT * 0.5))
	_touch_release(Vector2(200, ROW_HEIGHT * 0.5))
	_emulated_mouse_release(Vector2(200, ROW_HEIGHT * 0.5))
	_check(_row_pressed == 1, "A tap without movement still presses the row")

func _test_fling_brake_tap_does_not_click() -> void:
	await _build_list()
	_touch_press(Vector2(200, 500))
	_touch_drag(Vector2(200, 480), Vector2(0, -20), Vector2(0, -2400))
	_touch_drag(Vector2(200, 460), Vector2(0, -20), Vector2(0, -2400))
	_touch_release(Vector2(200, 460))
	_check(_interaction._fling_active, "Fast release starts fling before the brake tap")
	# 惯性还在跑时，第一次按下只负责刹车，不能选中手指下面的行。
	_emulated_mouse_press(Vector2(200, 60))
	_touch_press(Vector2(200, 60))
	_check(not _interaction._fling_active, "Tapping during fling stops the fling")
	_check(_row_pressed == 0, "The brake tap does not press the row under the finger")
	_touch_release(Vector2(200, 60))
	_emulated_mouse_release(Vector2(200, 60))
	_check(_row_pressed == 0, "Releasing the brake tap does not press the row either")

func _touch_press(position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = true
	_push(event)

func _touch_release(position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = false
	_push(event)

func _touch_drag(position: Vector2, relative: Vector2, velocity: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	event.relative = relative
	event.velocity = velocity
	_push(event)

func _emulated_mouse_press(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	_push(event)

func _emulated_mouse_release(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = position
	_push(event)

func _emulated_mouse_motion(position: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	_push(event)

## 用 local_coords = true 投递，避免 headless 窗口把坐标再缩放一次。
func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)

func _max_scroll() -> float:
	var bar := _scroll.get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures.append(message)
	print("FAIL: %s" % message)
