class_name DX_ScrollInteractionComp
extends Node

## 通用滚动交互组件：滚轮 / 触控板 / 鼠标拖拽 / 触摸拖拽与惯性。
##
## 两个容易踩的点：
## 1. 触摸设备会同时上报 InputEventScreenTouch/Drag 和一份模拟鼠标事件
##    （device == DEVICE_ID_EMULATION），只处理其中一套，否则同一手势会滚动两倍距离。
## 2. 手指开始拖动时要向子节点广播 NOTIFICATION_SCROLL_BEGIN（与引擎 ScrollContainer
##    一致），Button 会因此清除按压态，松手不会被当成点击。

signal drag_scroll_started
signal drag_scroll_finished

@export_node_path("ScrollContainer") var scroll_container_path: NodePath
@export var wheel_scroll_step := 96
## 滚轮滚动到目标的平滑时长（秒），<= 0 时立即跳转。
@export var wheel_smooth_time := 0.18
## 手指/鼠标移动超过该距离才判定为滚动，避免把点击吞成拖拽。
@export var drag_scroll_threshold := 8.0
@export var enable_mouse_wheel := true
@export var enable_pan_gesture := true
@export var enable_drag_scroll := true
@export var enable_touch_drag_scroll := true
@export var enable_horizontal_scroll := true
@export var enable_vertical_scroll := true
@export var force_pass_scroll_events := true
@export var configure_scroll_modes := true
## 触摸拖动时内容位移与手指位移的比例，1.0 为完全跟手。
@export var touch_drag_scale := 1.0
## 松手后是否按松手速度继续滑动。
@export var touch_fling_enabled := true
## 惯性衰减系数：越大停得越快（松手 1 秒后速度降到 e^-该值 倍）。
@export var touch_fling_decay := 3.2
## 惯性速度低于该值（像素/秒）时停止。
@export var touch_fling_min_speed := 80.0
## 惯性起始速度上限（像素/秒），避免甩动过猛。
@export var touch_fling_max_speed := 5200.0
## 最后一次移动距今超过该时长（秒）时不再产生惯性，对应“手指停住再松手”。
@export var touch_fling_stale_time := 0.1

## 惯性刹车点击的吞并窗口，覆盖同一次触摸生成的全部鼠标事件。
const FLING_STOP_TAP_WINDOW_USEC := 500000
## 速度低通时间常数，越小越灵敏。
const TOUCH_VELOCITY_SMOOTH_TIME := 0.05

var _scroll: ScrollContainer
## 浮点滚动位置：ScrollContainer 只接受整数，慢速滚动时逐帧取整会卡顿。
var _scroll_position := Vector2.ZERO
var _scroll_position_valid := false
var _drag_scroll_active := false
var _drag_scroll_started := false
var _drag_scroll_press_position := Vector2.ZERO
var _drag_scroll_last_position := Vector2.ZERO
var _touch_drag_active := false
var _touch_drag_started := false
var _touch_drag_press_position := Vector2.ZERO
var _touch_velocity := Vector2.ZERO
var _touch_last_motion_usec := 0
var _fling_active := false
var _fling_velocity := Vector2.ZERO
var _fling_stop_tap_until_usec := 0
var _scroll_begin_notified := false
var _wheel_tween: Tween
var _wheel_target := 0.0

func _ready() -> void:
	_scroll = _resolve_scroll_container()
	if _scroll == null:
		push_warning(
			"DX_ScrollInteractionComp requires a valid ScrollContainer path: %s"
			% str(scroll_container_path)
		)
		return

	set_process_input(true)
	if configure_scroll_modes:
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if force_pass_scroll_events:
		_apply_scroll_event_passthrough(_scroll)

func _exit_tree() -> void:
	_kill_wheel_tween()

func _process(delta: float) -> void:
	if not _fling_active:
		return

	_scroll_position += _fling_velocity * delta
	var hit_bound := _apply_scroll_position()
	_fling_velocity *= exp(-touch_fling_decay * delta)
	if hit_bound or _fling_velocity.length() < touch_fling_min_speed:
		_stop_fling()

func _resolve_scroll_container() -> ScrollContainer:
	if scroll_container_path.is_empty():
		return null

	var local_node := get_node_or_null(scroll_container_path)
	if local_node is ScrollContainer:
		return local_node as ScrollContainer

	var parent_node := get_parent()
	if parent_node != null:
		var sibling_node := parent_node.get_node_or_null(scroll_container_path)
		if sibling_node is ScrollContainer:
			return sibling_node as ScrollContainer

	return null

func _input(event: InputEvent) -> void:
	if _scroll == null or not _scroll.is_visible_in_tree():
		return

	var owner_control := get_parent() as Control
	if owner_control != null and not owner_control.visible:
		return

	if event is InputEventScreenTouch:
		if enable_touch_drag_scroll:
			_handle_touch_drag_touch(event as InputEventScreenTouch)
		return

	if event is InputEventScreenDrag:
		if enable_touch_drag_scroll:
			_handle_touch_drag_motion(event as InputEventScreenDrag)
		return

	# 触摸设备会把同一手势再翻译成一份鼠标事件（device == -1）。只认触摸那一套，
	# 否则拖动会被处理两次，手机上表现为“滚得飞快、没有阻尼”。
	if enable_touch_drag_scroll and event.device == InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton and _consume_fling_stop_press(event.position):
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if enable_mouse_wheel:
			_handle_mouse_wheel(mouse_button)
		if enable_drag_scroll:
			_handle_drag_scroll_button(mouse_button)
	elif enable_drag_scroll and event is InputEventMouseMotion:
		_handle_drag_scroll_motion(event as InputEventMouseMotion)
	elif enable_pan_gesture and event is InputEventPanGesture:
		_handle_pan_gesture(event as InputEventPanGesture)

func _apply_scroll_event_passthrough(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			var control := child as Control
			control.mouse_force_pass_scroll_events = true
			if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				control.mouse_filter = Control.MOUSE_FILTER_PASS
		_apply_scroll_event_passthrough(child)

func _handle_mouse_wheel(event: InputEventMouseButton) -> void:
	if not event.pressed or not _is_pointer_inside_scroll_content(event.position):
		return

	var direction := 0.0
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			direction = -1.0
		MOUSE_BUTTON_WHEEL_DOWN:
			direction = 1.0
		_:
			return

	var vertical_bar := _scroll.get_v_scroll_bar()
	if vertical_bar == null:
		return

	if _wheel_tween == null or not _wheel_tween.is_running():
		_wheel_target = vertical_bar.value
	else:
		_wheel_tween.kill()
	var max_scroll := _max_vertical_scroll()
	_wheel_target = clampf(
		_wheel_target + direction * wheel_scroll_step * event.factor,
		0.0,
		max_scroll
	)
	if wheel_smooth_time <= 0.0:
		vertical_bar.value = _wheel_target
	else:
		_wheel_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_wheel_tween.tween_property(vertical_bar, "value", _wheel_target, wheel_smooth_time)
	get_viewport().set_input_as_handled()

func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	if not _is_pointer_inside_scroll_content(event.position):
		return
	_stop_wheel()
	_sync_scroll_position()
	_apply_scroll_delta(event.delta)
	get_viewport().set_input_as_handled()

func _handle_drag_scroll_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		if not _is_pointer_inside_scroll_content(event.position):
			return
		_stop_wheel()
		_stop_fling()
		_drag_scroll_active = true
		_drag_scroll_started = false
		_drag_scroll_press_position = event.position
		_drag_scroll_last_position = event.position
		_sync_scroll_position()
		return

	var did_drag_scroll := _drag_scroll_active and _drag_scroll_started
	_drag_scroll_active = false
	_drag_scroll_started = false
	if did_drag_scroll:
		_notify_scroll_end()
		drag_scroll_finished.emit()
		# The release ends a scroll gesture, so it must not reach a row button
		# and be interpreted as a click on the item under the pointer.
		get_viewport().set_input_as_handled()

func _handle_drag_scroll_motion(event: InputEventMouseMotion) -> void:
	if not _drag_scroll_active:
		return

	var drag_offset := event.position - _drag_scroll_press_position
	if not _drag_scroll_started:
		if _pointer_drag_distance(drag_offset) < drag_scroll_threshold:
			return
		_drag_scroll_started = true
		_notify_scroll_begin()
		drag_scroll_started.emit()
		_apply_scroll_delta(-drag_offset)
		_drag_scroll_last_position = event.position
	else:
		var delta := event.position - _drag_scroll_last_position
		_drag_scroll_last_position = event.position
		_apply_scroll_delta(-delta)
	get_viewport().set_input_as_handled()

func _handle_touch_drag_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# 惯性还在跑时按下的第一下只负责“刹车”，不能算作点击行。
		if _consume_fling_stop_press(event.position):
			_sync_scroll_position()
			get_viewport().set_input_as_handled()
			return
		if not _is_pointer_inside_scroll_content(event.position):
			return
		_stop_wheel()
		_touch_drag_active = true
		_touch_drag_started = false
		_touch_drag_press_position = event.position
		_touch_velocity = Vector2.ZERO
		_touch_last_motion_usec = 0
		_sync_scroll_position()
		return

	if _fling_stop_tap_until_usec > 0:
		# 这是“刹车点击”的抬起，吞掉并结束吞并窗口。
		_fling_stop_tap_until_usec = 0
		get_viewport().set_input_as_handled()
		return

	var did_drag_scroll := _touch_drag_active and _touch_drag_started
	_touch_drag_active = false
	_touch_drag_started = false
	if did_drag_scroll:
		drag_scroll_finished.emit()
		_notify_scroll_end()
		_start_touch_fling()
		# Prevent the touch-up from activating the control that was pressed
		# before the finger moved far enough to start scrolling.
		get_viewport().set_input_as_handled()

func _handle_touch_drag_motion(event: InputEventScreenDrag) -> void:
	if not _touch_drag_active:
		if _fling_stop_tap_until_usec == 0:
			return
		# 刹车点击后手指继续拖动：直接接着当一次新的拖拽。
		_touch_drag_active = true
		_touch_drag_started = false
		_touch_drag_press_position = event.position - event.relative
		_touch_velocity = Vector2.ZERO
		_touch_last_motion_usec = 0
		_sync_scroll_position()

	var drag_offset := event.position - _touch_drag_press_position
	if not _touch_drag_started:
		if _pointer_drag_distance(drag_offset) < drag_scroll_threshold:
			return
		_touch_drag_started = true
		_fling_stop_tap_until_usec = 0
		_notify_scroll_begin()
		drag_scroll_started.emit()
		_touch_velocity = Vector2.ZERO
		_touch_last_motion_usec = 0
		# 补上死区内的位移，避免内容永远落后手指一截。
		_apply_scroll_delta(-drag_offset * touch_drag_scale)
	else:
		_apply_scroll_delta(-event.relative * touch_drag_scale)

	_update_touch_velocity(event)
	get_viewport().set_input_as_handled()

## 记录并按时间常数平滑松手速度，供惯性使用。
func _update_touch_velocity(event: InputEventScreenDrag) -> void:
	var now := Time.get_ticks_usec()
	var previous := _touch_last_motion_usec
	_touch_last_motion_usec = now

	var instant := -event.velocity * touch_drag_scale
	var elapsed := 0.0
	if previous > 0:
		elapsed = maxf(0.0001, float(now - previous) / 1000000.0)
	if instant.length() < 1.0 and previous > 0:
		# 部分平台不给 velocity，用位移估算。
		instant = -event.relative * touch_drag_scale / elapsed

	if previous <= 0:
		_touch_velocity = instant
		return
	var blend := 1.0 - exp(-minf(elapsed, 0.05) / TOUCH_VELOCITY_SMOOTH_TIME)
	_touch_velocity = _touch_velocity.lerp(instant, blend)

func _start_touch_fling() -> void:
	if not touch_fling_enabled:
		return

	var velocity := _touch_velocity
	if _touch_last_motion_usec > 0:
		var idle := float(Time.get_ticks_usec() - _touch_last_motion_usec) / 1000000.0
		if idle > touch_fling_stale_time:
			return
		# 手指停住的那段时间按衰减补偿，避免“按住后松手还飞出去”。
		velocity *= exp(-touch_fling_decay * idle)

	if not enable_horizontal_scroll:
		velocity.x = 0.0
	if not enable_vertical_scroll:
		velocity.y = 0.0

	var speed := velocity.length()
	if speed < touch_fling_min_speed:
		return

	if speed > touch_fling_max_speed:
		velocity = velocity * (touch_fling_max_speed / speed)
	_fling_velocity = velocity
	_fling_active = true

## 停止惯性，返回停止前是否真的在滑动。
func _stop_fling() -> bool:
	if not _fling_active:
		return false
	_fling_active = false
	_fling_velocity = Vector2.ZERO
	return true

## 判断这次按下是不是“给惯性刹车”，是则吞掉事件返回 true。
func _consume_fling_stop_press(position: Vector2) -> bool:
	if _fling_stop_tap_until_usec > 0:
		return true
	if not _fling_active or not _is_pointer_inside_scroll_content(position):
		return false
	_stop_fling()
	_stop_wheel()
	_fling_stop_tap_until_usec = Time.get_ticks_usec() + FLING_STOP_TAP_WINDOW_USEC
	return true

func _stop_wheel() -> void:
	_kill_wheel_tween()

func _kill_wheel_tween() -> void:
	if _wheel_tween != null:
		_wheel_tween.kill()
		_wheel_tween = null

## 广播滚动开始：引擎的 Button 收到后会清掉按压态，滚动不会被当成点击。
func _notify_scroll_begin() -> void:
	if _scroll_begin_notified:
		return
	_scroll_begin_notified = true
	if is_instance_valid(_scroll):
		_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)

func _notify_scroll_end() -> void:
	if not _scroll_begin_notified:
		return
	_scroll_begin_notified = false
	if is_instance_valid(_scroll):
		_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)

func _pointer_drag_distance(offset: Vector2) -> float:
	if enable_horizontal_scroll and enable_vertical_scroll:
		return offset.length()
	if enable_horizontal_scroll:
		return absf(offset.x)
	if enable_vertical_scroll:
		return absf(offset.y)
	return offset.length()

func _sync_scroll_position() -> void:
	var horizontal_bar := _scroll.get_h_scroll_bar()
	var vertical_bar := _scroll.get_v_scroll_bar()
	_scroll_position = Vector2(
		horizontal_bar.value if horizontal_bar != null else 0.0,
		vertical_bar.value if vertical_bar != null else 0.0
	)
	_scroll_position_valid = true

func _apply_scroll_delta(delta: Vector2) -> void:
	if not _scroll_position_valid:
		_sync_scroll_position()
	_scroll_position += delta
	_apply_scroll_position()

## 把浮点位置写回 ScrollContainer，返回是否已经顶到边界。
func _apply_scroll_position() -> bool:
	if _scroll == null:
		return true

	var hit_bound := false
	var horizontal_bar := _scroll.get_h_scroll_bar()
	if horizontal_bar != null:
		if enable_horizontal_scroll:
			var target_x := clampf(_scroll_position.x, 0.0, _max_horizontal_scroll())
			if not is_equal_approx(target_x, _scroll_position.x):
				hit_bound = true
			_scroll_position.x = target_x
			var pixel_x := roundi(target_x)
			if pixel_x != _scroll.scroll_horizontal:
				_scroll.scroll_horizontal = pixel_x
		else:
			_scroll_position.x = float(_scroll.scroll_horizontal)

	var vertical_bar := _scroll.get_v_scroll_bar()
	if vertical_bar != null:
		if enable_vertical_scroll:
			var target_y := clampf(_scroll_position.y, 0.0, _max_vertical_scroll())
			if not is_equal_approx(target_y, _scroll_position.y):
				hit_bound = true
			_scroll_position.y = target_y
			var pixel_y := roundi(target_y)
			if pixel_y != _scroll.scroll_vertical:
				_scroll.scroll_vertical = pixel_y
		else:
			_scroll_position.y = float(_scroll.scroll_vertical)

	return hit_bound

func _max_horizontal_scroll() -> float:
	var horizontal_bar := _scroll.get_h_scroll_bar()
	if horizontal_bar == null:
		return 0.0
	return maxf(0.0, horizontal_bar.max_value - horizontal_bar.page)

func _max_vertical_scroll() -> float:
	var vertical_bar := _scroll.get_v_scroll_bar()
	if vertical_bar == null:
		return 0.0
	return maxf(0.0, vertical_bar.max_value - vertical_bar.page)

func _set_scroll_axis(value: Vector2) -> void:
	if _scroll == null:
		return
	_scroll_position = value
	_scroll_position_valid = true
	_apply_scroll_position()

func _set_scroll_horizontal(value: float) -> void:
	_sync_scroll_position()
	_scroll_position.x = value
	_apply_scroll_position()

func _set_scroll_vertical(value: float) -> void:
	_sync_scroll_position()
	_scroll_position.y = value
	_apply_scroll_position()

func _is_pointer_inside_scroll(position: Vector2) -> bool:
	return _scroll != null and _scroll.get_global_rect().has_point(position)

func _is_pointer_inside_scroll_content(position: Vector2) -> bool:
	if not _is_pointer_inside_scroll(position):
		return false
	var vertical_bar := _scroll.get_v_scroll_bar()
	if vertical_bar != null and vertical_bar.visible and vertical_bar.get_global_rect().has_point(position):
		return false
	var horizontal_bar := _scroll.get_h_scroll_bar()
	if horizontal_bar != null and horizontal_bar.visible and horizontal_bar.get_global_rect().has_point(position):
		return false
	return true
