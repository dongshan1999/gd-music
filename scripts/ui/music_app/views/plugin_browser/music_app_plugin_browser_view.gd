class_name MusicAppPluginBrowserView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppPluginControllerType := preload("res://scripts/ui/music_app/controllers/music_app_plugin_controller.gd")
const MusicPluginManagerType := preload("res://dx/runtime/scripts/managers/music_plugin_manager.gd")

var _controller: MusicAppShowcaseControllerType
var _plugin_controller: MusicAppPluginControllerType = MusicAppPluginControllerType.new()
var _is_bound := false
var _plugins: Array[Dictionary] = []
var _search_results: Array[Dictionary] = []
var _reload_requested := false

var _back_button: Button
var _title_label: Label
var _host_status_label: Label
var _start_host_button: Button
var _refresh_plugins_button: Button
var _install_file_input: LineEdit
var _install_file_button: Button
var _install_url_input: LineEdit
var _install_url_button: Button
var _plugin_selector: OptionButton
var _load_vars_button: Button
var _save_vars_button: Button
var _plugin_info_label: Label
var _vars_editor: TextEdit
var _query_input: LineEdit
var _search_button: Button
var _result_summary_label: Label
var _results_box: VBoxContainer

func _ready() -> void:
	_build_ui()

func setup(controller: MusicAppShowcaseControllerType) -> void:
	_controller = controller
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
	_install_file_button.pressed.connect(_on_install_file_pressed)
	_install_url_button.pressed.connect(_on_install_url_pressed)
	_plugin_selector.item_selected.connect(_on_plugin_selected)
	_load_vars_button.pressed.connect(_on_load_vars_pressed)
	_save_vars_button.pressed.connect(_on_save_vars_pressed)
	_search_button.pressed.connect(_on_search_pressed)
	_query_input.text_submitted.connect(_on_query_submitted)
	if not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func on_popup_shown() -> void:
	refresh()

func refresh() -> void:
	if _title_label != null:
		_title_label.text = "Plugin Browser"
	if _result_summary_label != null and _search_results.is_empty():
		_result_summary_label.text = "No search results."

func _build_ui() -> void:
	if get_child_count() > 0:
		return

	var background := ColorRect.new()
	background.name = "Background"
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.color = Color(0.06, 0.07, 0.09, 0.98)
	add_child(background)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 14
	margin.offset_top = 14
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
	_back_button.custom_minimum_size = Vector2(52, 42)
	_back_button.text = "Back"
	top_row.add_child(_back_button)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.text = "Plugin Browser"
	top_row.add_child(_title_label)

	_host_status_label = Label.new()
	_host_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_status_label.text = "Host status: unknown"
	layout.add_child(_host_status_label)

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	layout.add_child(host_row)

	_start_host_button = Button.new()
	_start_host_button.text = "Start Host"
	host_row.add_child(_start_host_button)

	_refresh_plugins_button = Button.new()
	_refresh_plugins_button.text = "Refresh Plugins"
	host_row.add_child(_refresh_plugins_button)

	layout.add_child(_make_section_label("Install from file"))
	var install_file_row := HBoxContainer.new()
	install_file_row.add_theme_constant_override("separation", 8)
	layout.add_child(install_file_row)

	_install_file_input = LineEdit.new()
	_install_file_input.placeholder_text = "Path to plugin .js"
	_install_file_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	install_file_row.add_child(_install_file_input)

	_install_file_button = Button.new()
	_install_file_button.text = "Install"
	install_file_row.add_child(_install_file_button)

	layout.add_child(_make_section_label("Install from URL"))
	var install_url_row := HBoxContainer.new()
	install_url_row.add_theme_constant_override("separation", 8)
	layout.add_child(install_url_row)

	_install_url_input = LineEdit.new()
	_install_url_input.placeholder_text = "https://..."
	_install_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	install_url_row.add_child(_install_url_input)

	_install_url_button = Button.new()
	_install_url_button.text = "Install"
	install_url_row.add_child(_install_url_button)

	layout.add_child(_make_section_label("Plugin"))
	var plugin_row := HBoxContainer.new()
	plugin_row.add_theme_constant_override("separation", 8)
	layout.add_child(plugin_row)

	_plugin_selector = OptionButton.new()
	_plugin_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plugin_row.add_child(_plugin_selector)

	_load_vars_button = Button.new()
	_load_vars_button.text = "Load Vars"
	plugin_row.add_child(_load_vars_button)

	_save_vars_button = Button.new()
	_save_vars_button.text = "Save Vars"
	plugin_row.add_child(_save_vars_button)

	_plugin_info_label = Label.new()
	_plugin_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plugin_info_label.text = "No plugin selected."
	layout.add_child(_plugin_info_label)

	layout.add_child(_make_section_label("Plugin vars JSON"))
	_vars_editor = TextEdit.new()
	_vars_editor.custom_minimum_size = Vector2(0, 110)
	_vars_editor.text = "{}"
	layout.add_child(_vars_editor)

	layout.add_child(_make_section_label("Search"))
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	layout.add_child(search_row)

	_query_input = LineEdit.new()
	_query_input.placeholder_text = "Search keyword"
	_query_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(_query_input)

	_search_button = Button.new()
	_search_button.text = "Search"
	search_row.add_child(_search_button)

	_result_summary_label = Label.new()
	_result_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_summary_label.text = "No search results."
	layout.add_child(_result_summary_label)

	var results_scroll := ScrollContainer.new()
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(results_scroll)

	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 6)
	_results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.add_child(_results_box)

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _normalize_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item in value:
		if item is Dictionary:
			result.append(item)
	return result

func _get_plugin_manager() -> MusicPluginManagerType:
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

func _set_status(text: String) -> void:
	if _host_status_label != null:
		_host_status_label.text = text

func _set_plugin_info() -> void:
	var plugin := _get_selected_plugin()
	if plugin.is_empty():
		_plugin_info_label.text = "No plugin selected."
		return
	var search_types: Array = plugin.get("supportedSearchType", [])
	var vars_count := 0
	if plugin.get("userVariables", null) is Array:
		vars_count = plugin.get("userVariables", []).size()
	_plugin_info_label.text = "Plugin: %s\nVersion: %s\nSearch Types: %s\nUser Vars: %d" % [
		str(plugin.get("name", "")),
		str(plugin.get("version", "")),
		", ".join(PackedStringArray(search_types)),
		vars_count
	]

func _sync_plugin_selector() -> void:
	_plugin_selector.clear()
	for plugin in _plugins:
		_plugin_selector.add_item(str(plugin.get("name", "")))
		_plugin_selector.set_item_metadata(_plugin_selector.item_count - 1, plugin)
	if _plugin_selector.item_count > 0:
		_plugin_selector.select(0)
	_set_plugin_info()

func _render_results() -> void:
	for child in _results_box.get_children():
		child.queue_free()

	if _search_results.is_empty():
		_result_summary_label.text = "No search results."
		return

	_result_summary_label.text = "Results: %d" % _search_results.size()
	for index in _search_results.size():
		var item := _search_results[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%d. %s - %s" % [
			index + 1,
			str(item.get("title", "")),
			str(item.get("artist", ""))
		]
		row.add_child(label)

		var import_button := Button.new()
		import_button.text = "Add"
		import_button.pressed.connect(_on_import_result_pressed.bind(index))
		row.add_child(import_button)

		_results_box.add_child(row)

func _show_error(message: String) -> void:
	if _plugin_controller != null:
		_plugin_controller.show_common_alert("Plugin Browser", message)

func _toast(message: String) -> void:
	if _plugin_controller != null:
		_plugin_controller.show_toast(message)

func _ensure_controller() -> bool:
	if _controller != null:
		return true
	_set_status("Plugin browser controller is not ready.")
	return false

func _request_reload_plugins() -> void:
	if _reload_requested:
		return
	_reload_requested = true
	call_deferred("_reload_plugins_deferred")

func _reload_plugins_deferred() -> void:
	_reload_requested = false
	if not _ensure_controller():
		return
	await _reload_plugins()

func _on_start_host_pressed() -> void:
	if not _ensure_controller():
		return
	_set_status("Starting host...")
	var result := await _plugin_controller.start_music_plugin_host()
	if not bool(result.get("ok", false)):
		_set_status("Host start failed.")
		_show_error(str(result.get("error", "Failed to start host.")))
		return
	_set_status("Host ready.")
	_toast("Plugin host is running.")
	await _reload_plugins()

func _on_refresh_plugins_pressed() -> void:
	if not _ensure_controller():
		return
	await _reload_plugins()

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
	await _reload_plugins()

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
	await _reload_plugins()

func _on_plugin_selected(_index: int) -> void:
	_set_plugin_info()

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
	_on_search_pressed()

func _on_search_pressed() -> void:
	if not _ensure_controller():
		return
	var plugin_id := _get_selected_plugin_id()
	if plugin_id.is_empty():
		_show_error("Please select a plugin first.")
		return

	var query := _query_input.text.strip_edges()
	if query.is_empty():
		_show_error("Please enter a search keyword.")
		return

	_result_summary_label.text = "Searching..."
	var result := await _plugin_controller.search_music_plugin(plugin_id, query, 1, "music")
	if not bool(result.get("ok", false)):
		_result_summary_label.text = "Search failed."
		_show_error(str(result.get("error", "Search failed.")))
		return

	var payload = result.get("data", {})
	if payload is Dictionary and payload.get("data", null) is Array:
		_search_results = _normalize_dictionary_array(payload.get("data", []))
	else:
		_search_results = _normalize_dictionary_array(null)
	_render_results()

func _on_import_result_pressed(index: int) -> void:
	if not _ensure_controller():
		return
	if index < 0 or index >= _search_results.size():
		return
	var plugin_id := _get_selected_plugin_id()
	if plugin_id.is_empty():
		_show_error("Please select a plugin first.")
		return
	var imported_indices := _plugin_controller.import_music_plugin_search_results(plugin_id, [_search_results[index]])
	if imported_indices.is_empty():
		_show_error("Failed to import search result.")
		return
	_toast("Track imported to playlist.")

func _reload_plugins() -> void:
	var manager := _get_plugin_manager()
	if manager == null:
		_set_status("Plugin manager unavailable.")
		return

	var health_result := await manager.ping()
	if bool(health_result.get("ok", false)):
		_set_status("Host ready at %s" % manager.get_base_url())
	else:
		_set_status("Host unavailable at %s" % manager.get_base_url())

	var list_result := await manager.list_plugins()
	if not bool(list_result.get("ok", false)):
		_plugins = _normalize_dictionary_array(null)
		_sync_plugin_selector()
		return

	var payload = list_result.get("data", {})
	if payload is Dictionary and payload.get("plugins", null) is Array:
		_plugins = _normalize_dictionary_array(payload.get("plugins", []))
	else:
		_plugins = _normalize_dictionary_array(null)

	_sync_plugin_selector()
