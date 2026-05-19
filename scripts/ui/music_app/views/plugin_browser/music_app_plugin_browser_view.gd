class_name MusicAppPluginBrowserView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const HISTORY_TAG_SCENE := preload(MusicAppScriptPathsType.PLUGIN_BROWSER_HISTORY_TAG)
const SEARCH_TAB_SCENE := preload(MusicAppScriptPathsType.PLUGIN_BROWSER_SEARCH_TAB)
const RESULT_ROW_SCENE := preload(MusicAppScriptPathsType.PLUGIN_BROWSER_RESULT_ROW)

const DEFAULT_SEARCH_TYPE := "music"
const EMPTY_HISTORY_TEXT := "暂无搜索记录"
const EMPTY_READY_TEXT := "请选择插件并输入搜索关键字"
const EMPTY_RESULT_TEXT := "暂无搜索结果"

var _controller: MusicAppShowcaseController
var _plugin_controller: MusicAppPluginBrowserController
var _is_bound := false
var _plugins: Array[Dictionary] = []
var _search_results: Array[Dictionary] = []
var _search_history: Array[String] = []
var _reload_requested := false
var _current_page := 1
var _last_query := ""
var _last_is_end := true
var _is_searching := false
var _selected_plugin_id := ""
var _selected_search_type := DEFAULT_SEARCH_TYPE

@onready var back_button: Button = %BackButton
@onready var search_icon_rect: TextureRect = %SearchIconRect
@onready var query_input: LineEdit = %QueryInput
@onready var clear_query_button: Button = %ClearQueryButton
@onready var submit_search_button: Button = %SubmitSearchButton
@onready var search_content: VBoxContainer = %SearchContent
@onready var history_section: VBoxContainer = %HistorySection
@onready var clear_history_button: Button = %ClearHistoryButton
@onready var history_tags_container: FlowContainer = %HistoryTagsContainer
@onready var history_empty_label: Label = %HistoryEmptyLabel
@onready var results_section: VBoxContainer = %ResultsSection
@onready var search_type_tabs: HBoxContainer = %SearchTypeTabs
@onready var plugin_tabs: HBoxContainer = %PluginTabs
@onready var results_list: VBoxContainer = %ResultsList
@onready var empty_results_label: Label = %EmptyResultsLabel
@onready var management_panel: PanelContainer = %ManagementPanel
@onready var host_status_label: Label = %HostStatusLabel
@onready var manage_toggle_button: Button = %ManageToggleButton
@onready var start_host_button: Button = %StartHostButton
@onready var refresh_plugins_button: Button = %RefreshPluginsButton
@onready var install_file_input: LineEdit = %InstallFileInput
@onready var install_file_button: Button = %InstallFileButton
@onready var install_url_input: LineEdit = %InstallUrlInput
@onready var install_url_button: Button = %InstallUrlButton
@onready var plugin_info_label: Label = %PluginInfoLabel
@onready var load_vars_button: Button = %LoadVarsButton
@onready var save_vars_button: Button = %SaveVarsButton
@onready var vars_editor: TextEdit = %VarsEditor

var _history_tag_nodes: Array = []
var _search_type_tab_nodes: Array = []
var _plugin_tab_nodes: Array = []
var _result_row_nodes: Array = []

## 注入插件浏览页控制器，并触发首轮插件列表加载。
func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_plugin_controller = MusicAppPluginBrowserController.new(controller)
	bind()
	refresh()
	_request_reload_plugins()

## 绑定插件浏览页所有固定交互事件。
func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	back_button.pressed.connect(close_popup)
	clear_query_button.pressed.connect(_on_clear_query_pressed)
	submit_search_button.pressed.connect(_on_search_pressed)
	query_input.text_submitted.connect(_on_query_submitted)
	query_input.text_changed.connect(_on_query_text_changed)
	clear_history_button.pressed.connect(_on_clear_history_pressed)
	manage_toggle_button.pressed.connect(_on_manage_toggle_pressed)
	start_host_button.pressed.connect(_on_start_host_pressed)
	refresh_plugins_button.pressed.connect(_on_refresh_plugins_pressed)
	install_file_button.pressed.connect(_on_install_file_pressed)
	install_url_button.pressed.connect(_on_install_url_pressed)
	load_vars_button.pressed.connect(_on_load_vars_pressed)
	save_vars_button.pressed.connect(_on_save_vars_pressed)

## 弹窗显示时刷新界面并重新请求插件状态。
func on_popup_shown() -> void:
	refresh()
	_request_reload_plugins()

## 刷新搜索历史、分页结果、标签页和管理区状态。
func refresh() -> void:
	_search_history = _copy_string_array(
		_plugin_controller.get_plugin_search_history() if _plugin_controller != null else []
	)
	_sync_query_state()
	_render_history()
	_render_tabs()
	_render_results()
	_set_plugin_info()
	_sync_action_state()

## 根据当前查询内容切换历史区与结果区可见性。
func _sync_query_state() -> void:
	var query := query_input.text.strip_edges()
	clear_query_button.visible = not query.is_empty()
	var showing_results := not _last_query.is_empty()
	history_section.visible = not showing_results
	results_section.visible = showing_results
	if not showing_results:
		empty_results_label.text = EMPTY_READY_TEXT

## 重新生成搜索历史标签区域。
func _render_history() -> void:
	for node in _history_tag_nodes:
		node.queue_free()
	_history_tag_nodes.clear()

	history_empty_label.visible = _search_history.is_empty()
	history_empty_label.text = EMPTY_HISTORY_TEXT
	clear_history_button.visible = not _search_history.is_empty()
	for text in _search_history:
		var chip = HISTORY_TAG_SCENE.instantiate()
		history_tags_container.add_child(chip)
		chip.configure(text)
		chip.pressed.connect(_on_history_tag_pressed)
		chip.remove_requested.connect(_on_history_tag_remove_requested)
		_history_tag_nodes.append(chip)

## 重新生成搜索类型标签和插件标签。
func _render_tabs() -> void:
	_sync_tab_row(
		search_type_tabs,
		_search_type_tab_nodes,
		_get_search_type_tab_items(),
		_selected_search_type,
		_on_search_type_tab_selected
	)
	_sync_tab_row(
		plugin_tabs,
		_plugin_tab_nodes,
		_get_plugin_tab_items(),
		_selected_plugin_id,
		_on_plugin_tab_selected
	)

## 复用统一逻辑重建某一行 Tab 节点并设置选中态。
func _sync_tab_row(
	container: HBoxContainer,
	storage: Array,
	items: Array[Dictionary],
	selected_id: String,
	callback: Callable
) -> void:
	for node in storage:
		node.queue_free()
	storage.clear()

	for item in items:
		var tab = SEARCH_TAB_SCENE.instantiate()
		container.add_child(tab)
		tab.configure(
			str(item.get("id", "")),
			str(item.get("text", "")),
			str(item.get("id", "")) == selected_id
		)
		tab.selected.connect(callback)
		storage.append(tab)

## 根据当前插件支持的搜索类型生成顶部搜索分类标签数据。
func _get_search_type_tab_items() -> Array[Dictionary]:
	var plugin := _get_selected_plugin()
	var search_types := _string_list_from_array(plugin.get("supportedSearchType", []))
	if search_types.is_empty():
		search_types.append(DEFAULT_SEARCH_TYPE)

	var items: Array[Dictionary] = []
	for search_type in search_types:
		items.append({
			"id": search_type,
			"text": _get_search_type_label(search_type),
		})
	return items

## 根据当前已加载插件列表生成插件标签数据。
func _get_plugin_tab_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for plugin in _plugins:
		items.append({
			"id": _plugin_key(plugin),
			"text": str(plugin.get("name", _plugin_key(plugin))),
		})
	return items

## 根据当前搜索结果重新生成结果列表与空态。
func _render_results() -> void:
	for node in _result_row_nodes:
		node.queue_free()
	_result_row_nodes.clear()

	var showing_results := not _last_query.is_empty()
	if not showing_results:
		empty_results_label.visible = false
		return

	if _search_results.is_empty():
		empty_results_label.visible = true
		empty_results_label.text = EMPTY_RESULT_TEXT if not _last_query.is_empty() else EMPTY_READY_TEXT
		return

	empty_results_label.visible = false
	for index in _search_results.size():
		var item := _search_results[index]
		var row = RESULT_ROW_SCENE.instantiate()
		results_list.add_child(row)
		row.configure(
			index,
			_result_title(item),
			_result_subtitle(item),
			str(item.get("platform", _get_selected_plugin_id()))
		)
		row.play_requested.connect(_on_result_row_pressed)
		_result_row_nodes.append(row)

func _plugin_key(plugin: Dictionary) -> String:
	return str(plugin.get("name", plugin.get("id", "")))

func _get_selected_plugin() -> Dictionary:
	for plugin in _plugins:
		if _plugin_key(plugin) == _selected_plugin_id:
			return plugin
	return {}

func _get_selected_plugin_id() -> String:
	return _selected_plugin_id

func _get_selected_search_type() -> String:
	return _selected_search_type if not _selected_search_type.is_empty() else DEFAULT_SEARCH_TYPE

func _set_status(text: String) -> void:
	host_status_label.text = text

## 汇总当前选中插件的元数据并展示在管理面板。
func _set_plugin_info() -> void:
	var plugin := _get_selected_plugin()
	if plugin.is_empty():
		plugin_info_label.text = "No plugin selected. Install a MusicFree-compatible plugin before searching."
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
	plugin_info_label.text = "\n".join(details)

## 将任意数组值规范成去重后的字符串数组。
func _string_list_from_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if not (value is Array):
		return result
	for item in value:
		var text := str(item).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result

## 复制字符串数组，避免直接持有外部引用。
func _copy_string_array(value: Array) -> Array[String]:
	var result: Array[String] = []
	for item in value:
		result.append(str(item))
	return result

## 将搜索类型标识转换为界面显示文案。
func _get_search_type_label(search_type: String) -> String:
	match search_type:
		"music":
			return "单曲"
		"album":
			return "专辑"
		"artist":
			return "作者"
		"playlist":
			return "歌单"
		_:
			return search_type.capitalize()

## 解析搜索结果项的主标题。
func _result_title(item: Dictionary) -> String:
	var title := str(item.get("title", "")).strip_edges()
	if title.is_empty():
		title = str(item.get("name", "")).strip_edges()
	if title.is_empty():
		title = "Untitled"
	return title

## 解析搜索结果项的副标题，优先展示作者与专辑。
func _result_subtitle(item: Dictionary) -> String:
	var parts := PackedStringArray()
	var artist := str(item.get("artist", "")).strip_edges()
	var album := str(item.get("album", "")).strip_edges()
	if not artist.is_empty():
		parts.append(artist)
	if not album.is_empty() and album != artist:
		parts.append(album)
	if parts.is_empty():
		var raw_text := JSON.stringify(item)
		return raw_text.left(96) if raw_text.length() > 96 else raw_text
	return " - ".join(parts)

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

## 根据插件、查询和加载状态统一刷新所有操作按钮可用性。
func _sync_action_state() -> void:
	var has_plugin := not _get_selected_plugin().is_empty()
	var has_query := not query_input.text.strip_edges().is_empty()
	submit_search_button.disabled = not has_plugin or not has_query or _is_searching
	start_host_button.disabled = _is_searching
	refresh_plugins_button.disabled = _is_searching
	load_vars_button.disabled = not has_plugin or _is_searching
	save_vars_button.disabled = not has_plugin or _is_searching
	clear_history_button.disabled = _search_history.is_empty() or _is_searching
	manage_toggle_button.text = "Hide" if management_panel.visible else "Manage"

## 切换搜索中状态，并同步按钮禁用与文案。
func _set_searching(value: bool) -> void:
	_is_searching = value
	submit_search_button.text = "搜索中" if value else "搜索"
	_sync_action_state()

## 过滤并复制结果数组中的字典项。
func _normalize_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item in value:
		if item is Dictionary:
			result.append(item)
	return result

func _get_plugin_controller():
	if _plugin_controller == null:
		return null
	return _plugin_controller.get_plugin_controller()

func _request_reload_plugins() -> void:
	if _reload_requested:
		return
	_reload_requested = true
	call_deferred("_reload_plugins_deferred")

## 延迟执行插件刷新，合并同一帧内的重复请求。
func _reload_plugins_deferred() -> void:
	_reload_requested = false
	if not _ensure_controller():
		return
	await _reload_plugins(true)

func _on_query_text_changed(_text: String) -> void:
	_sync_query_state()
	_sync_action_state()

func _on_clear_query_pressed() -> void:
	query_input.text = ""
	_last_query = ""
	_search_results = []
	_current_page = 1
	_last_is_end = true
	_sync_query_state()
	_render_results()
	_sync_action_state()

func _on_clear_history_pressed() -> void:
	_plugin_controller.clear_plugin_search_history()
	_search_history = _copy_string_array(_plugin_controller.get_plugin_search_history())
	_render_history()
	_sync_action_state()

func _on_history_tag_pressed(text: String) -> void:
	query_input.text = text
	await _search_page(1)

func _on_history_tag_remove_requested(text: String) -> void:
	_plugin_controller.remove_plugin_search_history(text)
	_search_history = _copy_string_array(_plugin_controller.get_plugin_search_history())
	_render_history()
	_sync_action_state()

func _on_search_type_tab_selected(search_type: String) -> void:
	if search_type == _selected_search_type:
		return
	_selected_search_type = search_type
	_render_tabs()
	if not _last_query.is_empty():
		await _search_page(1)

func _on_plugin_tab_selected(plugin_id: String) -> void:
	if plugin_id == _selected_plugin_id:
		return
	_selected_plugin_id = plugin_id
	var plugin := _get_selected_plugin()
	var supported_types := _string_list_from_array(plugin.get("supportedSearchType", []))
	if supported_types.is_empty():
		supported_types.append(DEFAULT_SEARCH_TYPE)
	if not supported_types.has(_selected_search_type):
		_selected_search_type = supported_types[0]
	_set_plugin_info()
	_render_tabs()
	_sync_action_state()
	if not _last_query.is_empty():
		await _search_page(1)

func _on_result_row_pressed(index: int) -> void:
	if index < 0 or index >= _search_results.size():
		return
	_toast("当前搜索结果仅展示，不执行导入或播放。")

func _on_manage_toggle_pressed() -> void:
	management_panel.visible = not management_panel.visible
	_sync_action_state()

func _on_start_host_pressed() -> void:
	if not _ensure_controller():
		return
	_set_status("Refreshing plugins...")
	var result: Dictionary = await _plugin_controller.refresh_music_plugins()
	if not bool(result.get("ok", false)):
		_set_status("Plugin refresh failed: %s" % str(result.get("error", "Unknown error.")))
		_show_error(str(result.get("error", "Failed to refresh plugins.")))
		return
	_set_status("Plugins refreshed.")
	_toast("Plugins refreshed.")
	await _reload_plugins(false)

func _on_refresh_plugins_pressed() -> void:
	if not _ensure_controller():
		return
	await _reload_plugins(true)

func _on_install_file_pressed() -> void:
	if not _ensure_controller():
		return
	var plugin_path := install_file_input.text.strip_edges()
	if plugin_path.is_empty():
		_show_error("Please enter a plugin file path.")
		return
	var result: Dictionary = await _get_plugin_controller().install_plugin_from_file(plugin_path)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Install failed.")))
		return
	_toast("Plugin installed from file.")
	await _reload_plugins(false)

func _on_install_url_pressed() -> void:
	if not _ensure_controller():
		return
	var plugin_url := install_url_input.text.strip_edges()
	if plugin_url.is_empty():
		_show_error("Please enter a plugin URL.")
		return
	var result: Dictionary = await _get_plugin_controller().install_plugin_from_url(plugin_url)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Install failed.")))
		return
	_toast("Plugin installed from URL.")
	await _reload_plugins(false)

func _on_load_vars_pressed() -> void:
	var plugin_id := _get_selected_plugin_id()
	if plugin_id.is_empty():
		_show_error("Please select a plugin first.")
		return
	var plugin_controller = _get_plugin_controller()
	if plugin_controller == null:
		_show_error("Plugin controller is not available.")
		return
	var result: Dictionary = await plugin_controller.get_plugin_user_variables(plugin_id)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Failed to load plugin vars.")))
		return
	var payload = result.get("data", {})
	var values: Dictionary = {}
	if payload is Dictionary:
		values = payload.get("values", {})
	vars_editor.text = JSON.stringify(values, "\t")

func _on_save_vars_pressed() -> void:
	var plugin_id := _get_selected_plugin_id()
	if plugin_id.is_empty():
		_show_error("Please select a plugin first.")
		return

	var json := JSON.new()
	if json.parse(vars_editor.text) != OK or not (json.data is Dictionary):
		_show_error("Plugin vars must be a JSON object.")
		return

	var plugin_controller = _get_plugin_controller()
	if plugin_controller == null:
		_show_error("Plugin controller is not available.")
		return

	var result: Dictionary = await plugin_controller.set_plugin_user_variables(plugin_id, json.data)
	if not bool(result.get("ok", false)):
		_show_error(str(result.get("error", "Failed to save plugin vars.")))
		return
	_toast("Plugin vars saved.")

func _on_query_submitted(_text: String) -> void:
	await _search_page(1)

func _on_search_pressed() -> void:
	await _search_page(1)

## 执行指定页的插件搜索，并同步历史、结果与空态。
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

	var query := query_input.text.strip_edges()
	if query.is_empty():
		_show_error("Please enter a search keyword.")
		return

	_current_page = maxi(1, page)
	_last_query = query
	_sync_query_state()
	_set_searching(true)

	var result: Dictionary = await _get_plugin_controller().search(
		plugin_id,
		query,
		_current_page,
		_get_selected_search_type()
	)
	_set_searching(false)
	if not bool(result.get("ok", false)):
		_search_results = []
		_last_is_end = true
		_render_results()
		_show_error(str(result.get("error", "Search failed.")))
		return

	_plugin_controller.push_plugin_search_history(query)
	_search_history = _copy_string_array(_plugin_controller.get_plugin_search_history())
	_render_history()

	var payload = result.get("data", {})
	if payload is Dictionary:
		_search_results = _normalize_dictionary_array(payload.get("data", []))
		_last_is_end = bool(payload.get("isEnd", true))
	else:
		_search_results = []
		_last_is_end = true
	_render_results()
	_sync_action_state()

## 刷新插件状态并重新加载插件列表。
func _reload_plugins(auto_start: bool) -> void:
	var plugin_controller = _get_plugin_controller()
	if plugin_controller == null:
		_set_status("Plugin controller unavailable.")
		return

	_set_status("Checking plugins at %s..." % plugin_controller.get_plugin_root_path())
	var health_result: Dictionary = await plugin_controller.get_plugin_runtime_status()
	if not bool(health_result.get("ok", false)) and auto_start:
		_set_status("Refreshing plugins...")
		health_result = await _plugin_controller.refresh_music_plugins()

	if not bool(health_result.get("ok", false)):
		_plugins = []
		_selected_plugin_id = ""
		_search_results = []
		_last_is_end = true
		_render_tabs()
		_render_results()
		_set_status("Plugins unavailable: %s" % str(health_result.get("error", "Unknown error.")))
		return

	_set_status("Plugins ready at %s" % plugin_controller.get_plugin_root_path())
	var list_result: Dictionary = await plugin_controller.list_plugins()
	if not bool(list_result.get("ok", false)):
		_plugins = []
		_selected_plugin_id = ""
		_render_tabs()
		_render_results()
		_set_status("Plugins ready, but listing failed: %s" % str(list_result.get("error", "")))
		return

	var payload = list_result.get("data", {})
	if payload is Dictionary and payload.get("plugins", null) is Array:
		_plugins = _normalize_dictionary_array(payload.get("plugins", []))
	else:
		_plugins = []

	if _plugins.is_empty():
		_selected_plugin_id = ""
		_selected_search_type = DEFAULT_SEARCH_TYPE
	else:
		if _selected_plugin_id.is_empty() or _get_selected_plugin().is_empty():
			_selected_plugin_id = _plugin_key(_plugins[0])
		var plugin := _get_selected_plugin()
		var search_types := _string_list_from_array(plugin.get("supportedSearchType", []))
		if search_types.is_empty():
			search_types.append(DEFAULT_SEARCH_TYPE)
		if not search_types.has(_selected_search_type):
			_selected_search_type = search_types[0]

	_render_tabs()
	_set_plugin_info()
	_render_results()
	_sync_action_state()
	if _plugins.is_empty():
		_set_status("Plugins ready. No plugins installed yet.")
	else:
		_set_status("Plugins ready. %d plugin(s) loaded." % _plugins.size())
