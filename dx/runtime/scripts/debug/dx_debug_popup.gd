class_name DX_DebugPopup
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const GROUP_DEFAULT := "Default"
const TAB_DATA := 0
const TAB_LOG := 1
const LOG_LEVEL_INFO := "INFO"
const LOG_LEVEL_WARN := "WARN"
const LOG_LEVEL_ERROR := "ERROR"

@onready var menu_button: Button = %MenuButton
@onready var close_button: Button = %CloseButton
@onready var menu_layer: Control = %MenuLayer
@onready var data_menu_button: Button = %DataMenuButton
@onready var log_menu_button: Button = %LogMenuButton
@onready var data_page: Control = %DataPage
@onready var log_page: Control = %LogPage
@onready var scroll: ScrollContainer = %Scroll
@onready var content_vbox: VBoxContainer = %ContentVBox
@onready var log_search_input: LineEdit = %LogSearchInput
@onready var info_filter_button: Button = %InfoFilterButton
@onready var warn_filter_button: Button = %WarnFilterButton
@onready var error_filter_button: Button = %ErrorFilterButton
@onready var clear_logs_button: Button = %ClearLogsButton
@onready var logs_scroll: ScrollContainer = %LogsScroll
@onready var logs_list: VBoxContainer = %LogsList
@onready var refresh_timer: Timer = %RefreshTimer

var _last_log_revision := -1
var _is_bound := false
var _current_tab := TAB_DATA
var _trigger_control: Control
var _log_search_text := ""
var _show_info_logs := true
var _show_warn_logs := true
var _show_error_logs := true

func setup(_controller = null) -> void:
	_bind()
	_rebuild()

func on_popup_shown() -> void:
	_resolve_and_hide_trigger()
	_switch_tab(TAB_DATA)
	_set_menu_open(false)
	_rebuild()
	refresh_timer.start()

func on_popup_hidden() -> void:
	refresh_timer.stop()
	_restore_trigger()

func _bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	logs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	menu_button.pressed.connect(_on_menu_button_pressed)
	close_button.pressed.connect(close_popup)
	data_menu_button.pressed.connect(_on_data_menu_pressed)
	log_menu_button.pressed.connect(_on_log_menu_pressed)
	log_search_input.text_changed.connect(_on_log_search_changed)
	info_filter_button.pressed.connect(_on_info_filter_pressed)
	warn_filter_button.pressed.connect(_on_warn_filter_pressed)
	error_filter_button.pressed.connect(_on_error_filter_pressed)
	clear_logs_button.pressed.connect(_on_clear_logs_pressed)
	refresh_timer.timeout.connect(_on_refresh_timer_timeout)

func _rebuild() -> void:
	_rebuild_dynamic_sections()
	_refresh_logs(true)
	_apply_tab_state()
	_apply_log_filter_button_styles()

func _rebuild_dynamic_sections() -> void:
	for child in content_vbox.get_children():
		child.queue_free()

	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return

	var descriptors: Array[Dictionary] = debug_manager.get_target_descriptors()
	for descriptor in descriptors:
		_add_target_section(descriptor)

func _add_target_section(descriptor: Dictionary) -> void:
	var items: Array = descriptor.get("items", [])
	if items.is_empty():
		return

	var grouped: Dictionary = {}
	for item_variant in items:
		var item: Dictionary = item_variant
		var group_name := str(item.get("group", GROUP_DEFAULT))
		if not grouped.has(group_name):
			grouped[group_name] = []
		grouped[group_name].append(item)

	for group_name in grouped.keys():
		var section := _create_section_panel("%s / %s" % [str(descriptor.get("id", "")), str(group_name)])
		content_vbox.add_child(section.panel)
		for item_variant in grouped[group_name]:
			_add_item_row(section.body, item_variant)

func _add_item_row(parent: VBoxContainer, item: Dictionary) -> void:
	match str(item.get("type", "")):
		"action":
			var button := Button.new()
			button.text = str(item.get("name", ""))
			button.pressed.connect(_on_action_pressed.bind(item))
			parent.add_child(button)
		"string":
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var label := Label.new()
			label.custom_minimum_size = Vector2(160, 0)
			label.text = str(item.get("name", ""))

			var line_edit := LineEdit.new()
			line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line_edit.text = str(_read_item_value(item))
			line_edit.text_submitted.connect(_on_string_submitted.bind(item, line_edit))
			line_edit.focus_exited.connect(_on_string_focus_exited.bind(item, line_edit))

			row.add_child(label)
			row.add_child(line_edit)
			parent.add_child(row)
		"number":
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var label := Label.new()
			label.custom_minimum_size = Vector2(160, 0)
			label.text = str(item.get("name", ""))

			var spin := SpinBox.new()
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.min_value = -999999.0
			spin.max_value = 999999.0
			spin.step = 0.1
			spin.value = float(_read_item_value(item))
			spin.value_changed.connect(_on_number_changed.bind(item))

			row.add_child(label)
			row.add_child(spin)
			parent.add_child(row)

func _refresh_logs(force: bool = false) -> void:
	if DX == null or DX.logger == null:
		return

	var revision := int(DX.logger.get_revision())
	if not force and revision == _last_log_revision:
		return

	_last_log_revision = revision
	_rebuild_log_list(DX.logger.get_entries())

func _rebuild_log_list(entries: Array) -> void:
	for child in logs_list.get_children():
		child.queue_free()

	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if not _is_log_entry_visible(entry):
			continue
		logs_list.add_child(_create_log_item(entry))

	call_deferred("_scroll_logs_to_bottom")

func _is_log_entry_visible(entry: Dictionary) -> bool:
	var level := str(entry.get("level", LOG_LEVEL_INFO)).to_upper()
	if level == LOG_LEVEL_INFO and not _show_info_logs:
		return false
	if level == LOG_LEVEL_WARN and not _show_warn_logs:
		return false
	if level == LOG_LEVEL_ERROR and not _show_error_logs:
		return false

	if _log_search_text.is_empty():
		return true

	var message_text := str(entry.get("text", "")).to_lower()
	return message_text.contains(_log_search_text)

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
	text_button.pressed.connect(_on_log_item_pressed.bind(str(entry.get("text", ""))))
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

func _read_item_value(item: Dictionary) -> Variant:
	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return null
	return debug_manager.read_value(
		str(item.get("target_id", "")),
		str(item.get("member_name", ""))
	)

func _create_section_panel(title: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = title
	vbox.add_child(header)

	return {
		"panel": panel,
		"body": vbox,
	}

func _switch_tab(tab_index: int) -> void:
	_current_tab = tab_index
	_apply_tab_state()

func _apply_tab_state() -> void:
	if data_page == null or log_page == null:
		return

	var show_data := _current_tab == TAB_DATA
	data_page.visible = show_data
	log_page.visible = not show_data
	_apply_menu_button_state(data_menu_button, show_data)
	_apply_menu_button_state(log_menu_button, not show_data)

func _apply_menu_button_state(button: Button, selected: bool) -> void:
	if button == null:
		return

	button.disabled = false
	button.add_theme_stylebox_override("normal", _build_menu_button_style(selected, false))
	button.add_theme_stylebox_override("hover", _build_menu_button_style(selected, true))
	button.add_theme_stylebox_override("pressed", _build_menu_button_style(selected, true))

func _build_menu_button_style(selected: bool, hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8

	if selected:
		style.bg_color = Color(1, 1, 1, 0.18)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(1, 1, 1, 0.14)
	elif hover:
		style.bg_color = Color(1, 1, 1, 0.08)
	else:
		style.bg_color = Color(1, 1, 1, 0.03)

	return style

func _apply_log_filter_button_styles() -> void:
	_apply_log_filter_button_state(info_filter_button, _show_info_logs, Color(0.58, 0.6, 0.64, 1))
	_apply_log_filter_button_state(warn_filter_button, _show_warn_logs, Color(0.82, 0.68, 0.22, 1))
	_apply_log_filter_button_state(error_filter_button, _show_error_logs, Color(0.82, 0.32, 0.32, 1))

func _apply_log_filter_button_state(button: Button, enabled: bool, accent_color: Color) -> void:
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

func _set_menu_open(is_open: bool) -> void:
	if menu_layer == null:
		return
	menu_layer.visible = is_open

func _resolve_and_hide_trigger() -> void:
	if _trigger_control != null and is_instance_valid(_trigger_control):
		_trigger_control.visible = false
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	_trigger_control = current_scene.get_node_or_null("DebugTrigger")
	if _trigger_control != null:
		_trigger_control.visible = false

func _restore_trigger() -> void:
	if _trigger_control != null and is_instance_valid(_trigger_control):
		_trigger_control.visible = true

func _scroll_logs_to_bottom() -> void:
	if logs_scroll == null:
		return
	logs_scroll.scroll_vertical = int(logs_scroll.get_v_scroll_bar().max_value)

func _on_log_item_pressed(text: String) -> void:
	if text.is_empty():
		return
	DisplayServer.clipboard_set(text)

func _get_debug_manager():
	if DX == null:
		return null
	return DX.get_manager(&"debug")

func _on_menu_button_pressed() -> void:
	_set_menu_open(not menu_layer.visible)

func _on_data_menu_pressed() -> void:
	_switch_tab(TAB_DATA)
	_set_menu_open(false)

func _on_log_menu_pressed() -> void:
	_switch_tab(TAB_LOG)
	_set_menu_open(false)

func _on_log_search_changed(new_text: String) -> void:
	_log_search_text = new_text.strip_edges().to_lower()
	_refresh_logs(true)

func _on_info_filter_pressed() -> void:
	_show_info_logs = not _show_info_logs
	_apply_log_filter_button_styles()
	_refresh_logs(true)

func _on_warn_filter_pressed() -> void:
	_show_warn_logs = not _show_warn_logs
	_apply_log_filter_button_styles()
	_refresh_logs(true)

func _on_error_filter_pressed() -> void:
	_show_error_logs = not _show_error_logs
	_apply_log_filter_button_styles()
	_refresh_logs(true)

func _on_action_pressed(item: Dictionary) -> void:
	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return
	debug_manager.invoke_action(
		str(item.get("target_id", "")),
		str(item.get("member_name", ""))
	)
	call_deferred("_rebuild_dynamic_sections")

func _on_string_submitted(_text: String, item: Dictionary, line_edit: LineEdit) -> void:
	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return
	debug_manager.write_string(
		str(item.get("target_id", "")),
		str(item.get("member_name", "")),
		line_edit.text
	)

func _on_string_focus_exited(item: Dictionary, line_edit: LineEdit) -> void:
	_on_string_submitted(line_edit.text, item, line_edit)

func _on_number_changed(value: float, item: Dictionary) -> void:
	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return
	debug_manager.write_number(
		str(item.get("target_id", "")),
		str(item.get("member_name", "")),
		value
	)

func _on_clear_logs_pressed() -> void:
	if DX == null or DX.logger == null:
		return
	DX.logger.clear_entries()
	_refresh_logs(true)

func _on_refresh_timer_timeout() -> void:
	_refresh_logs()
