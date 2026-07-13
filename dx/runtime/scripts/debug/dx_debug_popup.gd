class_name DX_DebugPopup
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const DebugLogViewScript := preload("res://dx/runtime/scripts/debug/debug_log_view.gd")

const GROUP_DEFAULT := "Default"
const TAB_OPTIONS := 0
const TAB_LOG := 1
const TAB_SYSTEM := 2
const TAB_PROFILER := 3
const DEBUG_TRIGGER_GROUP := "dx_debug_trigger"
const ARROW_RIGHT := ">"
const ARROW_UP := "^"
const ARROW_DOWN := "v"

enum GroupDisplayMode {
	INLINE,
	COLLAPSE,
	PAGE,
}

@onready var menu_button: Button = %MenuButton
@onready var close_button: Button = %CloseButton
@onready var menu_layer: Control = %MenuLayer
@onready var options_menu_button: Button = %OptionsMenuButton
@onready var log_menu_button: Button = %LogMenuButton
@onready var system_menu_button: Button = %SystemMenuButton
@onready var profiler_menu_button: Button = %ProfilerMenuButton
@onready var options_page: Control = %OptionsPage
@onready var log_page: Control = %LogPage
@onready var system_page: Control = %SystemPage
@onready var profiler_page: Control = %ProfilerPage
@onready var options_content_vbox: VBoxContainer = %OptionsContentVBox
@onready var system_content_vbox: VBoxContainer = %SystemContentVBox
@onready var profiler_content_vbox: VBoxContainer = %ProfilerContentVBox
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
var _current_tab := TAB_OPTIONS
var _trigger_control: Control
var _options_page_stack: Array[Dictionary] = []
var _log_view = DebugLogViewScript.new()

func close_popup() -> void:
	if popup_manager != null:
		super.close_popup()
		return
	_popup_close()
	queue_free()

func setup(_controller = null) -> void:
	_bind()
	_rebuild()

func on_popup_shown() -> void:
	_resolve_and_hide_trigger()
	_switch_tab(TAB_OPTIONS)
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
	options_menu_button.pressed.connect(_on_options_menu_pressed)
	log_menu_button.pressed.connect(_on_log_menu_pressed)
	system_menu_button.pressed.connect(_on_system_menu_pressed)
	profiler_menu_button.pressed.connect(_on_profiler_menu_pressed)
	log_search_input.text_changed.connect(_on_log_search_changed)
	info_filter_button.pressed.connect(_on_info_filter_pressed)
	warn_filter_button.pressed.connect(_on_warn_filter_pressed)
	error_filter_button.pressed.connect(_on_error_filter_pressed)
	clear_logs_button.pressed.connect(_on_clear_logs_pressed)
	refresh_timer.timeout.connect(_on_refresh_timer_timeout)

func _rebuild() -> void:
	_rebuild_dynamic_sections()
	_rebuild_system_sections()
	_rebuild_profiler_sections()
	_refresh_logs(true)
	_apply_tab_state()
	_apply_log_filter_button_styles()

func _rebuild_dynamic_sections() -> void:
	for child in options_content_vbox.get_children():
		child.queue_free()

	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return

	var descriptors: Array[Dictionary] = debug_manager.get_target_descriptors()
	if not _options_page_stack.is_empty():
		_add_options_page_content(options_content_vbox, descriptors)
		return

	for descriptor in descriptors:
		_add_target_section(options_content_vbox, descriptor)

func _rebuild_system_sections() -> void:
	for child in system_content_vbox.get_children():
		child.queue_free()

	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return

	var descriptors: Array[Dictionary] = debug_manager.get_system_descriptors()
	for descriptor in descriptors:
		_add_target_section(system_content_vbox, descriptor)

func _rebuild_profiler_sections() -> void:
	for child in profiler_content_vbox.get_children():
		child.queue_free()

	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return

	var descriptors: Array[Dictionary] = debug_manager.get_profiler_descriptors()
	for descriptor in descriptors:
		_add_target_section(profiler_content_vbox, descriptor)

func _add_target_section(content_parent: VBoxContainer, descriptor: Dictionary) -> void:
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
		var display_mode := _get_group_display_mode(descriptor, str(group_name))
		_add_group_section(
			content_parent,
			str(descriptor.get("id", "")),
			str(group_name),
			grouped[group_name],
			display_mode
		)

func _add_group_section(
	content_parent: VBoxContainer,
	target_id: String,
	group_name: String,
	items: Array,
	display_mode: int
) -> void:
	match display_mode:
		GroupDisplayMode.COLLAPSE:
			_add_collapsible_group_section(content_parent, target_id, group_name, items)
		GroupDisplayMode.PAGE:
			_add_page_group_entry(content_parent, target_id, group_name, items)
		_:
			var section := _create_section_panel("%s / %s" % [target_id, group_name], "")
			content_parent.add_child(section.panel)
			for item_variant in items:
				_add_item_row(section.body, item_variant)

func _add_collapsible_group_section(
	content_parent: VBoxContainer,
	target_id: String,
	group_name: String,
	items: Array
) -> void:
	var section := _create_section_panel("%s / %s" % [target_id, group_name], ARROW_DOWN)
	content_parent.add_child(section.panel)

	var body := VBoxContainer.new()
	body.visible = false
	body.add_theme_constant_override("separation", 8)
	section.body.add_child(body)
	for item_variant in items:
		_add_item_row(body, item_variant)
	section.header_button.pressed.connect(_on_collapse_group_pressed.bind(section.arrow_label, body))

func _add_page_group_entry(
	content_parent: VBoxContainer,
	target_id: String,
	group_name: String,
	items: Array
) -> void:
	var section := _create_section_panel("%s / %s" % [target_id, group_name], ARROW_RIGHT)
	content_parent.add_child(section.panel)
	section.header_button.pressed.connect(_on_page_group_pressed.bind(target_id, group_name, items))

func _add_options_page_content(content_parent: VBoxContainer, descriptors: Array[Dictionary]) -> void:
	var page: Dictionary = _options_page_stack.back()
	var target_id := str(page.get("target_id", ""))
	var group_name := str(page.get("group", GROUP_DEFAULT))

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 8)
	content_parent.add_child(header)

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.pressed.connect(_on_options_page_back_pressed)
	header.add_child(back_button)

	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = "%s / %s" % [target_id, group_name]
	header.add_child(title)

	for descriptor in descriptors:
		if str(descriptor.get("id", "")) != target_id:
			continue
		var items := _get_group_items(descriptor, group_name)
		for item_variant in items:
			_add_item_row(content_parent, item_variant)
		return

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
			if _number_has_range(item):
				_add_number_slider_row(parent, item)
			else:
				_add_number_spin_row(parent, item)
		"boolean":
			var checkbox := CheckBox.new()
			checkbox.text = str(item.get("name", ""))
			checkbox.button_pressed = bool(_read_item_value(item))
			checkbox.toggled.connect(_on_boolean_toggled.bind(item))
			parent.add_child(checkbox)
		"select":
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var label := Label.new()
			label.custom_minimum_size = Vector2(160, 0)
			label.text = str(item.get("name", ""))

			var option_button := OptionButton.new()
			option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var selected_index := _populate_select_options(option_button, item)
			if selected_index >= 0:
				option_button.select(selected_index)
			option_button.item_selected.connect(_on_select_item_selected.bind(item, option_button))

			row.add_child(label)
			row.add_child(option_button)
			parent.add_child(row)
		"readonly":
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var label := Label.new()
			label.custom_minimum_size = Vector2(160, 0)
			label.text = str(item.get("name", ""))

			var value_label := Label.new()
			value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value_label.text = str(_read_item_value(item))

			row.add_child(label)
			row.add_child(value_label)
			parent.add_child(row)

func _refresh_logs(force: bool = false) -> void:
	if DX == null or DX.logger == null:
		return

	var revision := int(DX.logger.get_revision())
	if not force and revision == _last_log_revision:
		return

	_last_log_revision = revision
	_log_view.rebuild(logs_list, DX.logger.get_entries())
	call_deferred("_scroll_logs_to_bottom")

func _read_item_value(item: Dictionary) -> Variant:
	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return null
	return debug_manager.read_item_value(item)

func _add_number_spin_row(parent: VBoxContainer, item: Dictionary) -> void:
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

func _add_number_slider_row(parent: VBoxContainer, item: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.custom_minimum_size = Vector2(160, 0)
	label.text = str(item.get("name", ""))

	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = _get_number_range_value(item, "min", 0.0)
	slider.max_value = _get_number_range_value(item, "max", 100.0)
	slider.step = _get_number_range_value(item, "step", 1.0)
	slider.value = clampf(float(_read_item_value(item)), slider.min_value, slider.max_value)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(72, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = _format_number_slider_value(slider.value, slider.step)
	slider.value_changed.connect(_on_number_slider_changed.bind(item, value_label, slider.step))

	row.add_child(label)
	row.add_child(slider)
	row.add_child(value_label)
	parent.add_child(row)

func _number_has_range(item: Dictionary) -> bool:
	var value_range: Dictionary = item.get("range", {})
	return value_range.has("min") and value_range.has("max")

func _get_number_range_value(item: Dictionary, key: String, default_value: float) -> float:
	var value_range: Dictionary = item.get("range", {})
	return float(value_range.get(key, default_value))

func _format_number_slider_value(value: float, step: float) -> String:
	if is_equal_approx(step, round(step)):
		return str(int(round(value)))
	return "%.2f" % value

func _populate_select_options(option_button: OptionButton, item: Dictionary) -> int:
	var selected_index := -1
	var current_value: Variant = _read_item_value(item)
	var options: Array = item.get("options", [])
	for index in options.size():
		var option: Variant = options[index]
		if not option is Dictionary:
			continue
		var label := str(option.get("label", option.get("value", "")))
		var value: Variant = option.get("value", null)
		option_button.add_item(label, index)
		option_button.set_item_metadata(index, value)
		if selected_index < 0 and _are_select_values_equal(current_value, value):
			selected_index = index
	return selected_index

func _are_select_values_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) == TYPE_STRING_NAME or typeof(right) == TYPE_STRING_NAME:
		return StringName(left) == StringName(right)
	return left == right

func _get_group_display_mode(descriptor: Dictionary, group_name: String) -> int:
	var modes: Dictionary = descriptor.get("group_display_modes", {})
	return int(modes.get(group_name, GroupDisplayMode.INLINE))

func _get_group_items(descriptor: Dictionary, group_name: String) -> Array:
	var result: Array = []
	var items: Array = descriptor.get("items", [])
	for item_variant in items:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant
		if str(item.get("group", GROUP_DEFAULT)) == group_name:
			result.append(item)
	return result

func _create_section_panel(title: String, arrow_text: String = "") -> Dictionary:
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

	var header_button := Button.new()
	header_button.flat = true
	header_button.focus_mode = Control.FOCUS_NONE
	header_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_button.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(header_button)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_row.offset_left = 0.0
	header_row.offset_top = 0.0
	header_row.offset_right = 0.0
	header_row.offset_bottom = 0.0
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_button.add_child(header_row)

	var header := Label.new()
	header.text = title
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(header)

	var arrow := Label.new()
	arrow.text = arrow_text
	arrow.custom_minimum_size = Vector2(24, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(arrow)

	return {
		"panel": panel,
		"body": vbox,
		"header_button": header_button,
		"arrow_label": arrow,
	}

func _switch_tab(tab_index: int) -> void:
	if tab_index != TAB_OPTIONS:
		_options_page_stack.clear()
	_current_tab = tab_index
	_apply_tab_state()

func _apply_tab_state() -> void:
	if options_page == null or log_page == null or system_page == null or profiler_page == null:
		return

	var show_options := _current_tab == TAB_OPTIONS
	var show_log := _current_tab == TAB_LOG
	var show_system := _current_tab == TAB_SYSTEM
	var show_profiler := _current_tab == TAB_PROFILER
	options_page.visible = show_options
	log_page.visible = show_log
	system_page.visible = show_system
	profiler_page.visible = show_profiler
	_apply_menu_button_state(options_menu_button, show_options)
	_apply_menu_button_state(log_menu_button, show_log)
	_apply_menu_button_state(system_menu_button, show_system)
	_apply_menu_button_state(profiler_menu_button, show_profiler)

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
	_log_view.apply_filter_button_styles(info_filter_button, warn_filter_button, error_filter_button)

func _set_menu_open(is_open: bool) -> void:
	if menu_layer == null:
		return
	menu_layer.visible = is_open

func _resolve_and_hide_trigger() -> void:
	if _trigger_control != null and is_instance_valid(_trigger_control):
		_trigger_control.visible = false
		return

	_trigger_control = _find_debug_trigger()
	if _trigger_control != null:
		_trigger_control.visible = false

func _find_debug_trigger() -> Control:
	var tree := get_tree()
	if tree == null:
		return null

	for node in tree.get_nodes_in_group(DEBUG_TRIGGER_GROUP):
		if node is Control and is_instance_valid(node):
			return node as Control

	if DX != null:
		var global_trigger := DX.get_node_or_null("DebugLayer/DebugTrigger") as Control
		if global_trigger != null:
			return global_trigger

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null

	var trigger := current_scene.get_node_or_null("DebugTrigger") as Control
	if trigger == null:
		trigger = current_scene.get_node_or_null("HUD/DebugTrigger") as Control
	if trigger == null:
		trigger = current_scene.get_node_or_null("HUD/DXDebugTrigger") as Control
	if trigger == null:
		trigger = current_scene.find_child("DXDebugTrigger", true, false) as Control
	return trigger

func _restore_trigger() -> void:
	if _trigger_control != null and is_instance_valid(_trigger_control):
		if _trigger_control.has_method("refresh_visibility"):
			_trigger_control.call("refresh_visibility")
		else:
			_trigger_control.visible = true

func _scroll_logs_to_bottom() -> void:
	if logs_scroll == null:
		return
	logs_scroll.scroll_vertical = int(logs_scroll.get_v_scroll_bar().max_value)

func _get_debug_manager():
	if DX == null:
		return null
	return DX.get_manager(&"debug")

func _on_menu_button_pressed() -> void:
	_set_menu_open(not menu_layer.visible)

func _on_options_menu_pressed() -> void:
	_switch_tab(TAB_OPTIONS)
	_set_menu_open(false)

func _on_log_menu_pressed() -> void:
	_switch_tab(TAB_LOG)
	_set_menu_open(false)

func _on_system_menu_pressed() -> void:
	_switch_tab(TAB_SYSTEM)
	_set_menu_open(false)

func _on_profiler_menu_pressed() -> void:
	_switch_tab(TAB_PROFILER)
	_set_menu_open(false)

func _on_log_search_changed(new_text: String) -> void:
	_log_view.set_search_text(new_text)
	_refresh_logs(true)

func _on_info_filter_pressed() -> void:
	_log_view.toggle_info()
	_apply_log_filter_button_styles()
	_refresh_logs(true)

func _on_warn_filter_pressed() -> void:
	_log_view.toggle_warn()
	_apply_log_filter_button_styles()
	_refresh_logs(true)

func _on_error_filter_pressed() -> void:
	_log_view.toggle_error()
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

func _on_number_slider_changed(value: float, item: Dictionary, value_label: Label, step: float) -> void:
	value_label.text = _format_number_slider_value(value, step)
	_on_number_changed(value, item)

func _on_boolean_toggled(value: bool, item: Dictionary) -> void:
	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return
	debug_manager.write_boolean(
		str(item.get("target_id", "")),
		str(item.get("member_name", "")),
		value
	)

func _on_select_item_selected(index: int, item: Dictionary, option_button: OptionButton) -> void:
	var debug_manager = _get_debug_manager()
	if debug_manager == null:
		return
	debug_manager.write_select(
		str(item.get("target_id", "")),
		str(item.get("member_name", "")),
		option_button.get_item_metadata(index)
	)

func _on_collapse_group_pressed(arrow_label: Label, body: Control) -> void:
	body.visible = not body.visible
	arrow_label.text = ARROW_UP if body.visible else ARROW_DOWN

func _on_page_group_pressed(target_id: String, group_name: String, _items: Array) -> void:
	_options_page_stack.append({
		"target_id": target_id,
		"group": group_name,
	})
	_rebuild_dynamic_sections()

func _on_options_page_back_pressed() -> void:
	if not _options_page_stack.is_empty():
		_options_page_stack.pop_back()
	_rebuild_dynamic_sections()

func _on_clear_logs_pressed() -> void:
	if DX == null or DX.logger == null:
		return
	DX.logger.clear_entries()
	_refresh_logs(true)

func _on_refresh_timer_timeout() -> void:
	if _current_tab == TAB_SYSTEM:
		_rebuild_system_sections()
	elif _current_tab == TAB_PROFILER:
		_rebuild_profiler_sections()
	_refresh_logs()
