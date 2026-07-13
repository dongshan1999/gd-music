class_name DX_DebugLogView
extends RefCounted

const LOG_LEVEL_INFO := "INFO"
const LOG_LEVEL_WARN := "WARN"
const LOG_LEVEL_ERROR := "ERROR"

var search_text := ""
var show_info := true
var show_warn := true
var show_error := true

func rebuild(logs_list: VBoxContainer, entries: Array) -> void:
	if logs_list == null:
		return

	for child in logs_list.get_children():
		child.queue_free()

	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		if _is_entry_visible(entry):
			logs_list.add_child(_create_log_item(entry))

func apply_filter_button_styles(info_button: Button, warn_button: Button, error_button: Button) -> void:
	_apply_filter_button_state(info_button, show_info, Color(0.58, 0.6, 0.64, 1))
	_apply_filter_button_state(warn_button, show_warn, Color(0.82, 0.68, 0.22, 1))
	_apply_filter_button_state(error_button, show_error, Color(0.82, 0.32, 0.32, 1))

func set_search_text(value: String) -> void:
	search_text = value.strip_edges().to_lower()

func toggle_info() -> void:
	show_info = not show_info

func toggle_warn() -> void:
	show_warn = not show_warn

func toggle_error() -> void:
	show_error = not show_error

func _is_entry_visible(entry: Dictionary) -> bool:
	var level := str(entry.get("level", LOG_LEVEL_INFO)).to_upper()
	if level == LOG_LEVEL_INFO and not show_info:
		return false
	if level == LOG_LEVEL_WARN and not show_warn:
		return false
	if level == LOG_LEVEL_ERROR and not show_error:
		return false

	if search_text.is_empty():
		return true

	return str(entry.get("text", "")).to_lower().contains(search_text)

func _create_log_item(entry: Dictionary) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	wrapper.mouse_force_pass_scroll_events = true
	wrapper.tooltip_text = str(entry.get("text", ""))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _build_log_panel_style(str(entry.get("level", LOG_LEVEL_INFO))))
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.mouse_force_pass_scroll_events = true

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.mouse_force_pass_scroll_events = true
	panel.add_child(margin)

	var text_button := Button.new()
	text_button.flat = true
	text_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_button.text = str(entry.get("text", ""))
	text_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_button.modulate = Color(0.86, 0.86, 0.88, 1)
	text_button.mouse_filter = Control.MOUSE_FILTER_PASS
	text_button.mouse_force_pass_scroll_events = true
	text_button.focus_mode = Control.FOCUS_NONE
	text_button.pressed.connect(_copy_log_text.bind(str(entry.get("text", ""))))
	margin.add_child(text_button)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	spacer.mouse_force_pass_scroll_events = true

	wrapper.add_child(panel)
	wrapper.add_child(spacer)
	return wrapper

func _build_log_panel_style(level: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.03)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.border_width_bottom = 2

	match level.to_upper():
		LOG_LEVEL_WARN:
			style.border_color = Color(0.82, 0.68, 0.22, 0.95)
		LOG_LEVEL_ERROR:
			style.border_color = Color(0.82, 0.32, 0.32, 0.95)
		_:
			style.border_color = Color(0.56, 0.58, 0.62, 0.9)

	return style

func _apply_filter_button_state(button: Button, enabled: bool, accent_color: Color) -> void:
	if button == null:
		return

	var normal := StyleBoxFlat.new()
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_right = 8
	normal.corner_radius_bottom_left = 8

	var hover := normal.duplicate()
	var pressed := normal.duplicate()

	if enabled:
		normal.bg_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.18)
		normal.border_width_bottom = 2
		normal.border_color = accent_color
		hover.bg_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.24)
		hover.border_width_bottom = 2
		hover.border_color = accent_color
		pressed.bg_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.24)
		pressed.border_width_bottom = 2
		pressed.border_color = accent_color
	else:
		normal.bg_color = Color(1, 1, 1, 0.03)
		hover.bg_color = Color(1, 1, 1, 0.08)
		pressed.bg_color = Color(1, 1, 1, 0.08)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)

func _copy_log_text(text: String) -> void:
	if not text.is_empty():
		DisplayServer.clipboard_set(text)
