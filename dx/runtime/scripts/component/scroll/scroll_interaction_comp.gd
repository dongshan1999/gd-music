class_name DX_ScrollInteractionComp
extends Node

@export_node_path("ScrollContainer") var scroll_container_path: NodePath
@export var wheel_scroll_step := 96
@export var drag_scroll_threshold := 8.0
@export var enable_mouse_wheel := true
@export var enable_pan_gesture := true
@export var enable_drag_scroll := true
@export var enable_touch_drag_scroll := true
@export var force_pass_scroll_events := true

var _scroll: ScrollContainer
var _drag_scroll_active := false
var _drag_scroll_started := false
var _drag_scroll_last_position := Vector2.ZERO
var _drag_scroll_press_position := Vector2.ZERO
var _touch_drag_active := false
var _touch_drag_started := false
var _touch_drag_last_position := Vector2.ZERO
var _touch_drag_press_position := Vector2.ZERO

func _ready() -> void:
	_scroll = _resolve_scroll_container()
	if _scroll == null:
		push_warning(
			"DX_ScrollInteractionComp requires a valid ScrollContainer path: %s"
			% str(scroll_container_path)
		)
		return

	set_process_input(true)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if force_pass_scroll_events:
		_apply_scroll_event_passthrough(_scroll)

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
	if _scroll == null:
		return

	var owner_control := get_parent() as Control
	if owner_control != null and not owner_control.visible:
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if enable_mouse_wheel:
			_handle_mouse_wheel(mouse_button)
		if enable_drag_scroll:
			_handle_drag_scroll_button(mouse_button)
	elif enable_drag_scroll and event is InputEventMouseMotion:
		_handle_drag_scroll_motion(event as InputEventMouseMotion)
	elif enable_touch_drag_scroll and event is InputEventScreenTouch:
		_handle_touch_drag_touch(event as InputEventScreenTouch)
	elif enable_touch_drag_scroll and event is InputEventScreenDrag:
		_handle_touch_drag_motion(event as InputEventScreenDrag)
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
	if not event.pressed or not _is_pointer_inside_scroll(event.position):
		return

	var next_value := _scroll.scroll_vertical
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		next_value -= wheel_scroll_step
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		next_value += wheel_scroll_step
	else:
		return

	_set_scroll_vertical(next_value)
	get_viewport().set_input_as_handled()

func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	if not _is_pointer_inside_scroll(event.position):
		return
	_set_scroll_vertical(_scroll.scroll_vertical + int(event.delta.y))
	get_viewport().set_input_as_handled()

func _handle_drag_scroll_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		if not _is_pointer_inside_scroll(event.position):
			return
		_drag_scroll_active = true
		_drag_scroll_started = false
		_drag_scroll_press_position = event.position
		_drag_scroll_last_position = event.position
		return

	_drag_scroll_active = false
	_drag_scroll_started = false

func _handle_drag_scroll_motion(event: InputEventMouseMotion) -> void:
	if not _drag_scroll_active:
		return

	var drag_offset := event.position - _drag_scroll_press_position
	if not _drag_scroll_started:
		if absf(drag_offset.y) < drag_scroll_threshold:
			return
		_drag_scroll_started = true

	var delta_y := event.position.y - _drag_scroll_last_position.y
	_drag_scroll_last_position = event.position
	_set_scroll_vertical(_scroll.scroll_vertical - delta_y)
	get_viewport().set_input_as_handled()

func _handle_touch_drag_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if not _is_pointer_inside_scroll(event.position):
			return
		_touch_drag_active = true
		_touch_drag_started = false
		_touch_drag_press_position = event.position
		_touch_drag_last_position = event.position
		return

	_touch_drag_active = false
	_touch_drag_started = false

func _handle_touch_drag_motion(event: InputEventScreenDrag) -> void:
	if not _touch_drag_active:
		return

	var drag_offset := event.position - _touch_drag_press_position
	if not _touch_drag_started:
		if absf(drag_offset.y) < drag_scroll_threshold:
			return
		_touch_drag_started = true

	_touch_drag_last_position = event.position
	_set_scroll_vertical(_scroll.scroll_vertical - event.relative.y)
	get_viewport().set_input_as_handled()

func _is_pointer_inside_scroll(position: Vector2) -> bool:
	return _scroll != null and _scroll.get_global_rect().has_point(position)

func _set_scroll_vertical(value: float) -> void:
	var vertical_bar := _scroll.get_v_scroll_bar()
	if vertical_bar == null:
		return

	var max_scroll := maxf(0.0, vertical_bar.max_value - vertical_bar.page)
	_scroll.scroll_vertical = int(clampf(value, 0.0, max_scroll))
