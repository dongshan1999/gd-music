class_name MusicAppPluginBrowserView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")

const DEFAULT_SEARCH_TYPE := "music"
const PANEL_BG := Color(0.12, 0.13, 0.15, 1.0)
const PANEL_BG_SOFT := Color(0.09, 0.10, 0.12, 1.0)
const PANEL_BORDER := Color(0.22, 0.24, 0.28, 1.0)
const MUTED_TEXT := Color(0.70, 0.73, 0.78, 1.0)
const STRONG_TEXT := Color(0.95, 0.96, 0.98, 1.0)

var _controller: MusicAppShowcaseController
var _plugin_controller: MusicAppPluginController
var _is_bound := false
var _plugins: Array[Dictionary] = []
var _search_results: Array[Dictionary] = []
var _reload_requested := false
var _current_page := 1
var _last_query := ""
var _last_is_end := true
var _is_searching := false

var _back_button: Button
var _title_label: Label
var _host_status_label: Label
var _start_host_button: Button
var _refresh_plugins_button: Button
var _manage_toggle_button: Button
var _install_file_input: LineEdit
var _install_file_button: Button
var _install_url_input: LineEdit
var _install_url_button: Button
var _plugin_selector: OptionButton
var _search_type_selector: OptionButton
var _load_vars_button: Button
var _save_vars_button: Button
var _plugin_info_label: Label
var _vars_editor: TextEdit
var _query_input: LineEdit
var _search_button: Button
var _import_all_button: Button
var _prev_page_button: Button
var _next_page_button: Button
var _result_summary_label: Label
var _results_box: VBoxContainer
var _management_panel: Control

func _ready() -> void:
	_build_ui()
	_render_results()

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_plugin_controller = MusicAppPluginController.new(controller)
	bind()
	refresh()
	_request_reload_plugins()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	_back_button.pressed.connect(close_popup)
	_start_host_button.pressed.connect(_on_start_host_pressed)
	_refresh_plugins_button.pressed.connect(_on_refresh_plugins_pressed)
	_manage_toggle_button.pressed.connect(_on_manage_toggle_pressed)
	_install_file_button.pressed.connect(_on_install_file_pressed)
	_install_url_button.pressed.connect(_on_install_url_pressed)
	_plugin_selector.item_selected.connect(_on_plugin_selected)
	_load_vars_button.pressed.connect(_on_load_vars_pressed)
	_save_vars_button.pressed.connect(_on_save_vars_pressed)
	_search_button.pressed.connect(_on_search_pressed)
	_import_all_button.pressed.connect(_on_import_all_pressed)
	_prev_page_button.pressed.connect(_on_prev_page_pressed)
	_next_page_button.pressed.connect(_on_next_page_pressed)
	_query_input.text_submitted.connect(_on_query_submitted)
	if _controller != null and not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func on_popup_shown() -> void:
	refresh()
	_request_reload_plugins()

func refresh() -> void:
	if _title_label != null:
		_title_label.text = "Plugin Search"
	if _back_button != null:
		MusicAppIconsType.apply_icon_button(_back_button, MusicAppIconsType.ARROW_LEFT)
	if _search_button != null:
		MusicAppIconsType.apply_icon_button(_search_button, MusicAppIconsType.SEARCH, true, false)
	_sync_action_state()

func _build_ui() -> void:
	if get_child_count() > 0:
		return

	var background := ColorRect.new()
	background.name = "Background"
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.color = Color(0.06, 0.07, 0.08, 1.0)
	add_child(background)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 14
	margin.offset_top = 10
	margin.offset_right = -14
	margin.offset_bottom = -14
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	layout.add_child(top_row)

	_back_button = Button.new()
	_back_button.custom_minimum_size = Vector2(44, 42)
	_back_button.tooltip_text = "Back"
	top_row.add_child(_back_button)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.text = "Plugin Search"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", STRONG_TEXT)
	top_row.add_child(_title_label)

	_manage_toggle_button = Button.new()
	_manage_toggle_button.custom_minimum_size = Vector2(86, 42)
	_manage_toggle_button.text = "Manage"
	top_row.add_child(_manage_toggle_button)

	_host_status_label = Label.new()
	_host_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_status_label.text = "Checking plugin host..."
	_host_status_label.add_theme_color_override("font_color", MUTED_TEXT)
	layout.add_child(_host_status_label)

	layout.add_child(_build_search_panel())
	layout.add_child(_build_results_toolbar())

	var results_scroll := ScrollContainer.new()
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(results_scroll)

	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 8)
	_results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.add_child(_results_box)

	_management_panel = _build_management_panel()
	_management_panel.visible = false
	layout.add_child(_management_panel)

func _build_search_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(PANEL_BG))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var plugin_row := HBoxContainer.new()
	plugin_row.add_theme_constant_override("separation", 8)
	layout.add_child(plugin_row)

	var source_label := _make_field_label("Source")
	source_label.custom_minimum_size = Vector2(58, 0)
	plugin_row.add_child(source_label)

	_plugin_selector = OptionButton.new()
	_plugin_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plugin_row.add_child(_plugin_selector)

	_start_host_button = Button.new()
	_start_host_button.custom_minimum_size = Vector2(72, 36)
	_start_host_button.text = "Start"
	plugin_row.add_child(_start_host_button)

	_refresh_plugins_button = Button.new()
	_refresh_plugins_button.custom_minimum_size = Vector2(78, 36)
	_refresh_plugins_button.text = "Refresh"
	plugin_row.add_child(_refresh_plugins_button)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	layout.add_child(search_row)

	_search_type_selector = OptionButton.new()
	_search_type_selector.custom_minimum_size = Vector2(96, 38)
	search_row.add_child(_search_type_selector)

	_query_input = LineEdit.new()
	_query_input.placeholder_text = "Search songs, artists, albums"
	_query_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(_query_input)

	_search_button = Button.new()
	_search_button.custom_minimum_size = Vector2(86, 38)
	_search_button.text = "Search"
	search_row.add_child(_search_button)

	return panel

func _build_results_toolbar() -> Control:
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)

	_result_summary_label = Label.new()
	_result_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_summary_label.text = "Choose a plugin and search."
	_result_summary_label.add_theme_color_override("font_color", MUTED_TEXT)
	toolbar.add_child(_result_summary_label)

	_import_all_button = Button.new()
	_import_all_button.custom_minimum_size = Vector2(76, 36)
	_import_all_button.text = "Add All"
	toolbar.add_child(_import_all_button)

	_prev_page_button = Button.new()
	_prev_page_button.custom_minimum_size = Vector2(42, 36)
	_prev_page_button.text = "<"
	toolbar.add_child(_prev_page_button)

	_next_page_button = Button.new()
	_next_page_button.custom_minimum_size = Vector2(42, 36)
	_next_page_button.text = ">"
	toolbar.add_child(_next_page_button)

	return toolbar

func _build_management_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(PANEL_BG_SOFT))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	layout.add_child(_make_section_label("Install plugin"))

	var install_file_row := HBoxContainer.new()
	install_file_row.add_theme_constant_override("separation", 8)
	layout.add_child(install_file_row)

	_install_file_input = LineEdit.new()
	_install_file_input.placeholder_text = "Path to MusicFree .js plugin"
	_install_file_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	install_file_row.add_child(_install_file_input)

	_install_file_button = Button.new()
	_install_file_button.custom_minimum_size = Vector2(70, 36)
	_install_file_button.text = "Install"
	install_file_row.add_child(_install_file_button)

	var install_url_row := HBoxContainer.new()
	install_url_row.add_theme_constant_override("separation", 8)
	layout.add_child(install_url_row)

	_install_url_input = LineEdit.new()
	_install_url_input.placeholder_text = "https://..."
	_install_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	install_url_row.add_child(_install_url_input)

	_install_url_button = Button.new()
	_install_url_button.custom_minimum_size = Vector2(70, 36)
	_install_url_button.text = "Install"
	install_url_row.add_child(_install_url_button)

	layout.add_child(_make_section_label("Selected plugin"))

	_plugin_info_label = Label.new()
	_plugin_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plugin_info_label.text = "No plugin selected."
	_plugin_info_label.add_theme_color_override("font_color", MUTED_TEXT)
	layout.add_child(_plugin_info_label)

	var vars_row := HBoxContainer.new()
	vars_row.add_theme_constant_override("separation", 8)
	layout.add_child(vars_row)

	_load_vars_button = Button.new()
	_load_vars_button.custom_minimum_size = Vector2(96, 34)
	_load_vars_button.text = "Load Vars"
	vars_row.add_child(_load_vars_button)

	_save_vars_button = Button.new()
	_save_vars_button.custom_minimum_size = Vector2(96, 34)
	_save_vars_button.text = "Save Vars"
	vars_row.add_child(_save_vars_button)

	_vars_editor = TextEdit.new()
	_vars_editor.custom_minimum_size = Vector2(0, 96)
	_vars_editor.text = "{}"
	layout.add_child(_vars_editor)

	return panel

func _make_panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = PANEL_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", STRONG_TEXT)
	label.add_theme_font_size_override("font_size", 15)
	return label

func _make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", MUTED_TEXT)
	return label

func _make_muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED_TEXT)
	return label

func _normalize_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item in value:
		if item is Dictionary:
			result.append(item)
	return result

func _get_plugin_manager() -> DX_MusicPluginManager:
	if _plugin_controller == null:
		return null
	return _plugin_controller.get_music_plugin_manager()

func _get_selected_plugin() -> Dictionary:
	if _plugin_selector == null or _plugin_selector.item_count == 0:
		return {}
	var selected_index := _plugin_selector.selected
	if selected_index < 0 or selected_index >= _plugin_selector.item_count:
		return {}
	var metadata = _plugin_selector.get_item_metadata(selected_index)
	if metadata is Dictionary:
		return metadata
	return {}

func _get_selected_plugin_id() -> String:
	var plugin := _get_selected_plugin()
	if plugin.is_empty():
		return ""
	return str(plugin.get("name", plugin.get("id", "")))

func _get_selected_search_type() -> String:
	if _search_type_selector == null or _search_type_selector.item_count == 0:
		return DEFAULT_SEARCH_TYPE
	var selected_index := _search_type_selector.selected
	if selected_index < 0 or selected_index >= _search_type_selector.item_count:
		return DEFAULT_SEARCH_TYPE
	var metadata = _search_type_selector.get_item_metadata(selected_index)
	if metadata is String:
		return metadata
	return DEFAULT_SEARCH_TYPE

func _set_status(text: String) -> void:
	if _host_status_label != null:
		_host_status_label.text = text

func _set_plugin_info() -> void:
	if _plugin_info_label == null:
		return
	var plugin := _get_selected_plugin()
	if plugin.is_empty():
		_plugin_info_label.text = "No plugin selected. Install a MusicFree-compatible plugin before searching."
		return

	var search_types := _string_list_from_array(plugin.get("supportedSearchType", []))
	if search_types.is_empty():
		search_types.append(DEFAULT_SEARCH_TYPE)

	var details := PackedStringArray()
	details.append("Name: %s" % str(plugin.get("name", "")))
	details.append("Version: %s" % str(plugin.get("version", "")))
	details.append("Search types: %s" % ", ".join(search_types))
	if not str(plugin.get("author", "")).is_empty():
		details.append("Author: %s" % str(plugin.get("author", "")))
	if not str(plugin.get("description", "")).is_empty():
		details.append(str(plugin.get("description", "")))
	_plugin_info_label.text = "\n".join(details)

func _string_list_from_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if not (value is Array):
		return result
	for item in value:
		var text := str(item).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result

func _sync_plugin_selector() -> void:
	_plugin_selector.clear()
	for plugin in _plugins:
		var label := str(plugin.get("name", plugin.get("id", "")))
		if label.is_empty():
			label = "Unnamed Plugin"
		_plugin_selector.add_item(label)
		_plugin_selector.set_item_metadata(_plugin_selector.item_count - 1, plugin)

	if _plugin_selector.item_count == 0:
		_plugin_selector.add_item("No plugins installed")
		_plugin_selector.set_item_disabled(0, true)
		_plugin_selector.select(0)
	else:
		_plugin_selector.select(0)

	_sync_search_type_selector()
	_set_plugin_info()
	_render_results()
	_sync_action_state()

func _sync_search_type_selector() -> void:
	_search_type_selector.clear()
	var plugin := _get_selected_plugin()
	var search_types := _string_list_from_array(plugin.get("supportedSearchType", []))
	if search_types.is_empty():
		search_types.append(DEFAULT_SEARCH_TYPE)

	var default_type := str(plugin.get("defaultSearchType", DEFAULT_SEARCH_TYPE))
	var default_index := 0
	for index in search_types.size():
		var search_type := search_types[index]
		if search_type == default_type:
			default_index = index
		_search_type_selector.add_item(_get_search_type_label(search_type))
		_search_type_selector.set_item_metadata(index, search_type)
	_search_type_selector.select(default_index)
	_search_type_selector.disabled = search_types.size() <= 1

func _get_search_type_label(search_type: String) -> String:
	match search_type:
		"music":
			return "Song"
		"album":
			return "Album"
		"artist":
			return "Artist"
		"playlist":
			return "Playlist"
		_:
			return search_type.capitalize()

func _render_results() -> void:
	if _results_box == null:
		return
	for child in _results_box.get_children():
		child.queue_free()

	if _search_results.is_empty():
		var empty_text := "Choose a plugin, enter a keyword, and search."
		if _plugins.is_empty():
			empty_text = "No plugins are installed. Open Manage to install a MusicFree-compatible .js plugin."
		elif not _last_query.is_empty():
			empty_text = "No results for \"%s\"." % _last_query
		_results_box.add_child(_make_empty_state(empty_text))
		if _result_summary_label != null:
			if _plugins.is_empty():
				_result_summary_label.text = "No searchable plugin available."
			elif _last_query.is_empty():
				_result_summary_label.text = "Ready to search."
			else:
				_result_summary_label.text = "No results on page %d." % _current_page
		_sync_action_state()
		return

	if _result_summary_label != null:
		var end_text := "end" if _last_is_end else "more"
		_result_summary_label.text = "%d results - page %d - %s" % [
			_search_results.size(),
			_current_page,
			end_text
		]

	for index in _search_results.size():
		_results_box.add_child(_make_result_row(index, _search_results[index]))
	_sync_action_state()

func _make_empty_state(text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(PANEL_BG_SOFT))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var label := _make_muted_label(text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 120)
	margin.add_child(label)
	return panel

func _make_result_row(index: int, item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style(PANEL_BG_SOFT))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var ordinal := Label.new()
	ordinal.custom_minimum_size = Vector2(30, 0)
	ordinal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ordinal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ordinal.text = str(index + 1 + ((_current_page - 1) * _search_results.size()))
	ordinal.add_theme_color_override("font_color", MUTED_TEXT)
	row.add_child(ordinal)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)

	var title_label := Label.new()
	title_label.text = _result_title(item)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_color_override("font_color", STRONG_TEXT)
	text_box.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = _result_subtitle(item)
	subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle_label.add_theme_color_override("font_color", MUTED_TEXT)
	text_box.add_child(subtitle_label)

	var add_button := Button.new()
	add_button.custom_minimum_size = Vector2(58, 36)
	add_button.text = "Add"
	add_button.pressed.connect(_on_import_result_pressed.bind(index))
	row.add_child(add_button)

	var play_button := Button.new()
	play_button.custom_minimum_size = Vector2(58, 36)
	play_button.text = "Play"
	play_button.pressed.connect(_on_play_result_pressed.bind(index))
	row.add_child(play_button)

	return panel

func _result_title(item: Dictionary) -> String:
	var title := str(item.get("title", "")).strip_edges()
	if title.is_empty():
		title = str(item.get("name", "")).strip_edges()
	if title.is_empty():
		title = "Untitled"
	return title

func _result_subtitle(item: Dictionary) -> String:
	var parts := PackedStringArray()
	var artist := str(item.get("artist", "")).strip_edges()
	var album := str(item.get("album", "")).strip_edges()
	var platform := str(item.get("platform", _get_selected_plugin_id())).strip_edges()
	var duration := int(item.get("duration", 0))
	if not artist.is_empty():
		parts.append(artist)
	if not album.is_empty():
		parts.append(album)
	if duration > 0:
		parts.append(_format_duration(duration))
	if not platform.is_empty():
		parts.append(platform)
	return " - ".join(parts) if not parts.is_empty() else "Unknown artist"

func _format_duration(seconds: int) -> String:
	var clamped_seconds := maxi(0, seconds)
	var minutes := floori(float(clamped_seconds) / 60.0)
	return "%d:%02d" % [minutes, clamped_seconds % 60]

func _show_error(message: String) -> void:
	if _plugin_controller != null:
		_plugin_controller.show_common_alert("Plugin Search", message)

func _toast(message: String) -> void:
	if _plugin_controller != null:
		_plugin_controller.show_toast(message)

func _ensure_controller() -> bool:
	if _controller != null and _plugin_controller != null:
		return true
	_set_status("Plugin search controller is not ready.")
	return false

func _sync_action_state() -> void:
	if _plugin_selector == null:
		return
	var has_plugin := not _get_selected_plugin().is_empty()
	_plugin_selector.disabled = _plugins.is_empty()
	_search_type_selector.disabled = _search_type_selector.item_count <= 1 or not has_plugin or _is_searching
	_query_input.editable = has_plugin and not _is_searching
	_search_button.disabled = not has_plugin or _is_searching
	_import_all_button.disabled = not has_plugin or _search_results.is_empty() or _is_searching
	_prev_page_button.disabled = _is_searching or _current_page <= 1 or _last_query.is_empty()
	_next_page_button.disabled = _is_searching or _last_is_end or _last_query.is_empty()
	_load_vars_button.disabled = not has_plugin or _is_searching
	_save_vars_button.disabled = not has_plugin or _is_searching
	_refresh_plugins_button.disabled = _is_searching
	_start_host_button.disabled = _is_searching

func _set_searching(value: bool) -> void:
	_is_searching = value
	_search_button.text = "Searching" if value else "Search"
	if not value:
		MusicAppIconsType.apply_icon_button(_search_button, MusicAppIconsType.SEARCH, true, false)
	_sync_action_state()

func _request_reload_plugins() -> void:
	if _reload_requested:
		return
	_reload_requested = true
	call_deferred("_reload_plugins_deferred")

func _reload_plugins_deferred() -> void:
	_reload_requested = false
	if not _ensure_controller():
		return
	await _reload_plugins(true)

func _on_manage_toggle_pressed() -> void:
	if _management_panel == null:
		return
	_management_panel.visible = not _management_panel.visible
	_manage_toggle_button.text = "Hide" if _management_panel.visible else "Manage"

func _on_start_host_pressed() -> void:
	if not _ensure_controller():
		return
	_set_status("Starting plugin host...")
	var result := await _plugin_controller.start_music_plugin_host()
	if not bool(result.get("ok", false)):
		_set_status("Host start failed: %s" % str(result.get("error", "Unknown error.")))
		_show_error(str(result.get("error", "Failed to start host.")))
		return
	_set_status("Host ready.")
	_toast("Plugin host is running.")
	await _reload_plugins(false)

func _on_refresh_plugins_pressed() -> void:
	if not _ensure_controller():
		return
	await _reload_plugins(true)

func _on_install_file_pressed() -> void:
	if not _ensure_controller():
		return
	var plugin_path := _install_file_input.text.strip_edges()
	if plugin_path.is_empty():
		_show_error("Please enter a plugin file path.")
		return
	var result := await _plugin_controller.install_music_plugin_from_file(plugin_path)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Install failed.")))
		return
	_toast("Plugin installed from file.")
	await _reload_plugins(false)

func _on_install_url_pressed() -> void:
	if not _ensure_controller():
		return
	var plugin_url := _install_url_input.text.strip_edges()
	if plugin_url.is_empty():
		_show_error("Please enter a plugin URL.")
		return
	var result := await _plugin_controller.install_music_plugin_from_url(plugin_url)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Install failed.")))
		return
	_toast("Plugin installed from URL.")
	await _reload_plugins(false)

func _on_plugin_selected(_index: int) -> void:
	_current_page = 1
	_last_query = ""
	_last_is_end = true
	_search_results = []
	_sync_search_type_selector()
	_set_plugin_info()
	_render_results()
	_sync_action_state()

func _on_load_vars_pressed() -> void:
	var plugin_id := _get_selected_plugin_id()
	if plugin_id.is_empty():
		_show_error("Please select a plugin first.")
		return
	var manager := _get_plugin_manager()
	if manager == null:
		_show_error("Plugin manager is not available.")
		return
	var result := await manager.get_plugin_user_variables(plugin_id)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Failed to load plugin vars.")))
		return
	var payload = result.get("data", {})
	var values: Dictionary = {}
	if payload is Dictionary:
		values = payload.get("values", {})
	_vars_editor.text = JSON.stringify(values, "\t")

func _on_save_vars_pressed() -> void:
	var plugin_id := _get_selected_plugin_id()
	if plugin_id.is_empty():
		_show_error("Please select a plugin first.")
		return

	var json := JSON.new()
	if json.parse(_vars_editor.text) != OK or not (json.data is Dictionary):
		_show_error("Plugin vars must be a JSON object.")
		return

	var manager := _get_plugin_manager()
	if manager == null:
		_show_error("Plugin manager is not available.")
		return

	var result := await manager.set_plugin_user_variables(plugin_id, json.data)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Failed to save plugin vars.")))
		return

	_toast("Plugin vars saved.")

func _on_query_submitted(_text: String) -> void:
	await _search_page(1)

func _on_search_pressed() -> void:
	await _search_page(1)

func _on_prev_page_pressed() -> void:
	if _current_page <= 1:
		return
	await _search_page(_current_page - 1)

func _on_next_page_pressed() -> void:
	if _last_is_end:
		return
	await _search_page(_current_page + 1)

func _search_page(page: int) -> void:
	if not _ensure_controller() or _is_searching:
		return
	var plugin := _get_selected_plugin()
	var plugin_id := _get_selected_plugin_id()
	if plugin_id.is_empty():
		_show_error("Please select a plugin first.")
		return
	if plugin.has("hasSearch") and not bool(plugin.get("hasSearch", true)):
		_show_error("Selected plugin does not support search.")
		return

	var query := _query_input.text.strip_edges()
	if query.is_empty():
		_show_error("Please enter a search keyword.")
		return

	var media_type := _get_selected_search_type()
	_current_page = maxi(1, page)
	_last_query = query
	_result_summary_label.text = "Searching \"%s\"..." % query
	_set_searching(true)

	var result := await _plugin_controller.search_music_plugin(plugin_id, query, _current_page, media_type)
	_set_searching(false)
	if not bool(result.get("ok", false)):
		_search_results = []
		_last_is_end = true
		_result_summary_label.text = "Search failed."
		_render_results()
		_show_error(str(result.get("error", "Search failed.")))
		return

	var payload = result.get("data", {})
	if payload is Dictionary:
		_search_results = _normalize_dictionary_array(payload.get("data", []))
		_last_is_end = bool(payload.get("isEnd", true))
	else:
		_search_results = _normalize_dictionary_array(null)
		_last_is_end = true
	_render_results()

func _on_import_result_pressed(index: int) -> void:
	if index < 0 or index >= _search_results.size():
		return
	_import_results([_search_results[index]], false)

func _on_play_result_pressed(index: int) -> void:
	if index < 0 or index >= _search_results.size():
		return
	_import_results([_search_results[index]], true)

func _on_import_all_pressed() -> void:
	if _search_results.is_empty():
		return
	_import_results(_search_results.duplicate(), false)

func _import_results(results: Array, autoplay_first: bool) -> void:
	if not _ensure_controller():
		return
	var plugin_id := _get_selected_plugin_id()
	if plugin_id.is_empty():
		_show_error("Please select a plugin first.")
		return
	var imported_indices := _plugin_controller.import_music_plugin_search_results(
		plugin_id,
		results,
		-1,
		autoplay_first
	)
	if imported_indices.is_empty():
		_show_error("Failed to import search result.")
		return
	if autoplay_first and _controller != null:
		_controller.show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)
	_toast("Imported %d track(s)." % imported_indices.size())

func _reload_plugins(auto_start: bool) -> void:
	var manager := _get_plugin_manager()
	if manager == null:
		_set_status("Plugin manager unavailable.")
		return

	_set_status("Checking plugin host at %s..." % manager.get_base_url())
	var health_result := await manager.ping()
	if not bool(health_result.get("ok", false)) and auto_start:
		_set_status("Starting plugin host...")
		health_result = await _plugin_controller.start_music_plugin_host()

	if not bool(health_result.get("ok", false)):
		_plugins = []
		_sync_plugin_selector()
		_set_status("Host unavailable: %s" % str(health_result.get("error", "Unknown error.")))
		return

	_set_status("Host ready at %s" % manager.get_base_url())
	var list_result := await manager.list_plugins()
	if not bool(list_result.get("ok", false)):
		_plugins = []
		_sync_plugin_selector()
		_set_status("Host ready, but plugins could not be listed: %s" % str(list_result.get("error", "")))
		return

	var payload = list_result.get("data", {})
	if payload is Dictionary and payload.get("plugins", null) is Array:
		_plugins = _normalize_dictionary_array(payload.get("plugins", []))
	else:
		_plugins = []

	_sync_plugin_selector()
	if _plugins.is_empty():
		_set_status("Host ready. No plugins installed yet.")
	else:
		_set_status("Host ready. %d plugin(s) loaded." % _plugins.size())
