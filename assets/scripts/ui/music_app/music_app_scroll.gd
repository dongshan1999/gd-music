extends "res://dx/runtime/scripts/component/scroll/scroll_interaction_comp.gd"
## Smooth wheel movement and quiet, automatically fading scroll indicators.

var _wheel_tween: Tween
var _indicator_tween: Tween
var _wheel_target := 0.0
var _touch_event := false
var _touch_velocity := 0.0

func _input(event: InputEvent) -> void:
	_touch_event = event is InputEventScreenTouch or event is InputEventScreenDrag
	super._input(event)
	_touch_event = false

func _ready() -> void:
	configure_scroll_modes = false
	enable_horizontal_scroll = false
	wheel_scroll_step = 72
	super._ready()
	if _scroll == null:
		return
	_scroll.follow_focus = true
	_scroll.get_v_scroll_bar().modulate.a = 0.0
	_scroll.get_v_scroll_bar().value_changed.connect(_show_indicator)
	_scroll.get_v_scroll_bar().mouse_entered.connect(_show_indicator.bind(0.0))
	drag_scroll_started.connect(_stop_wheel)

func _is_pointer_inside_scroll(pointer: Vector2) -> bool:
	if not super._is_pointer_inside_scroll(pointer) or not _scroll.is_visible_in_tree():
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered == _scroll or (hovered != null and _scroll.is_ancestor_of(hovered))

func _handle_mouse_wheel(event: InputEventMouseButton) -> void:
	if not event.pressed or not _is_pointer_inside_scroll(event.position):
		return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	var bar := _scroll.get_v_scroll_bar()
	if _wheel_tween == null or not _wheel_tween.is_running():
		_wheel_target = bar.value
	else:
		_wheel_tween.kill()
	var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	_wheel_target = clampf(_wheel_target + direction * wheel_scroll_step * event.factor, 0, maxf(0, bar.max_value - bar.page))
	_wheel_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_wheel_tween.tween_property(bar, "value", _wheel_target, 0.2)
	get_viewport().set_input_as_handled()

func _stop_wheel() -> void:
	if _wheel_tween != null:
		_wheel_tween.kill()

func _handle_touch_drag_touch(event: InputEventScreenTouch) -> void:
	var was_dragging := _touch_drag_started
	if event.pressed:
		_stop_wheel()
		_touch_velocity = 0.0
	super._handle_touch_drag_touch(event)
	if not event.pressed and was_dragging:
		var bar := _scroll.get_v_scroll_bar()
		var target := clampf(bar.value + _touch_velocity * 0.16, 0, maxf(0, bar.max_value - bar.page))
		_wheel_target = target
		_wheel_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_wheel_tween.tween_property(bar, "value", target, 0.4)
		get_viewport().set_input_as_handled()

func _handle_touch_drag_motion(event: InputEventScreenDrag) -> void:
	super._handle_touch_drag_motion(event)
	if _touch_drag_started:
		_touch_velocity = -event.velocity.y

func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	_stop_wheel()
	super._handle_pan_gesture(event)

func _show_indicator(_value: float) -> void:
	if _indicator_tween != null:
		_indicator_tween.kill()
	var bar := _scroll.get_v_scroll_bar()
	bar.modulate.a = 0.8
	_indicator_tween = create_tween()
	_indicator_tween.tween_interval(0.9)
	_indicator_tween.tween_property(bar, "modulate:a", 0.0, 0.25)
