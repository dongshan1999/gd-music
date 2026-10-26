class_name CommonToastPopup
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const FADE_DURATION := 0.18
const VISIBLE_DURATION := 0.95
const LIFT_DISTANCE := 10.0

var _toast_tween: Tween

@onready var toast_panel: PanelContainer = %ToastPanel
@onready var toast_label: Label = %ToastLabel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	toast_panel.visible = false

	var toast_style := StyleBoxFlat.new()
	toast_style.bg_color = Color(0.0705882, 0.0784314, 0.0980392, 0.94)
	toast_style.corner_radius_top_left = 18
	toast_style.corner_radius_top_right = 18
	toast_style.corner_radius_bottom_right = 18
	toast_style.corner_radius_bottom_left = 18
	toast_panel.add_theme_stylebox_override("panel", toast_style)
	toast_label.add_theme_color_override("font_color", Color(0.968627, 0.968627, 0.972549, 1))
	toast_label.add_theme_font_size_override("font_size", 14)

func show_message(message: String, bottom_offset: float = 104.0) -> void:
	toast_label.text = message
	toast_panel.reset_size()
	var toast_size := toast_panel.get_combined_minimum_size()
	toast_panel.size = toast_size
	var base_position := _get_toast_position(toast_size, bottom_offset)

	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null

	visible = true
	toast_panel.visible = true
	toast_panel.modulate = Color(1, 1, 1, 0)
	toast_panel.position = base_position + Vector2(0, LIFT_DISTANCE)

	_toast_tween = create_tween()
	_toast_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.parallel().tween_property(
		toast_panel,
		"position",
		base_position,
		FADE_DURATION
	)
	_toast_tween.parallel().tween_property(
		toast_panel,
		"modulate",
		Color.WHITE,
		FADE_DURATION
	)
	_toast_tween.tween_interval(VISIBLE_DURATION)
	_toast_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_toast_tween.parallel().tween_property(
		toast_panel,
		"position",
		base_position + Vector2(0, -LIFT_DISTANCE),
		FADE_DURATION
	)
	_toast_tween.parallel().tween_property(
		toast_panel,
		"modulate",
		Color(1, 1, 1, 0),
		FADE_DURATION
	)
	_toast_tween.finished.connect(_on_tween_finished)

func on_popup_hidden() -> void:
	if _toast_tween != null:
		_toast_tween.kill()
		_toast_tween = null
	toast_panel.visible = false
	visible = false

func _on_tween_finished() -> void:
	_toast_tween = null
	close_popup()

func _get_toast_position(toast_size: Vector2, bottom_offset: float) -> Vector2:
	var layout_size := size
	if layout_size.is_zero_approx():
		var parent = get_parent()
		if parent is Control:
			layout_size = (parent as Control).size
	if layout_size.is_zero_approx():
		layout_size = get_viewport_rect().size

	return Vector2(
		floor((layout_size.x - toast_size.x) * 0.5),
		floor(layout_size.y - bottom_offset - toast_size.y)
	)
