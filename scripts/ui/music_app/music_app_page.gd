extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"
## App navigation animations keep the popup stack alive until dismissal finishes.

enum Presentation { NONE, PUSH, SHEET, DIALOG }
@export var presentation: Presentation = Presentation.PUSH
@export_node_path("Control") var transition_target: NodePath = NodePath(".")

var _navigation_tween: Tween
var _closing := false
var _motion_target: Control
var _rest_position := Vector2.ZERO
var _input_guard: Control
var _previous_focus: Control

func _popup_open(manager) -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	super._popup_open(manager)
	if presentation == Presentation.NONE:
		return
	modulate.a = 0.0
	_set_input_guard(true)
	# Containers must finish laying out sheets and dialogs before animating.
	await get_tree().process_frame
	if _closing or not is_inside_tree():
		return
	_motion_target = get_node(transition_target) as Control
	_rest_position = _motion_target.position
	_motion_target.position = _rest_position + _travel()
	modulate.a = 0.0
	_navigation_tween = create_tween().set_parallel(true)
	_navigation_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_navigation_tween.tween_property(_motion_target, "position", _rest_position, 0.28)
	_navigation_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_navigation_tween.finished.connect(_set_input_guard.bind(false))

func close_popup() -> void:
	if _closing:
		return
	_closing = true
	if presentation == Presentation.NONE or not is_instance_valid(_motion_target):
		super.close_popup()
		return
	if _navigation_tween != null:
		_navigation_tween.kill()
	_set_input_guard(true)
	_navigation_tween = create_tween().set_parallel(true)
	_navigation_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_navigation_tween.tween_property(_motion_target, "position", _rest_position + _travel(), 0.2)
	_navigation_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_navigation_tween.finished.connect(_finish_dismissal)

func _travel() -> Vector2:
	match presentation:
		Presentation.SHEET:
			return Vector2(0, minf(size.y * 0.4, 300.0))
		Presentation.DIALOG:
			return Vector2(0, 12)
	return Vector2(48, 0)

func _set_input_guard(enabled: bool) -> void:
	if _input_guard == null:
		_input_guard = Control.new()
		_input_guard.name = "NavigationInputGuard"
		_input_guard.mouse_filter = Control.MOUSE_FILTER_STOP
		_input_guard.focus_mode = Control.FOCUS_ALL
		add_child(_input_guard)
		_input_guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_input_guard.visible = enabled
	if enabled:
		_input_guard.grab_focus()
	else:
		_input_guard.release_focus()

func _finish_dismissal() -> void:
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	super.close_popup()
