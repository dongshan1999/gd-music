class_name MusicAppPluginController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const PLUGIN_ROOT_DIR := "user://gdmusic_plugins"
const PLUGIN_ENTRY_FILE := "plugin.gd"
const PLUGIN_VARS_FILE := "user://gdmusic_plugins/plugin_vars.json"

var _plugins: Dictionary = {}
var last_error := ""

## 控制器进入运行期时预热插件设置对象并刷新本地插件列表。
func in_ready() -> void:
	get_settings()
	await refresh_plugins()

## 读取音乐插件设置数据，不存在时返回默认值。
func get_settings() -> MusicPluginSettingsData:
	var save_manager = get_save_manager()
	if save_manager == null or save_manager.data == null:
		return MusicPluginSettingsData.new()
	if save_manager.data.music_plugins == null:
		save_manager.data.music_plugins = MusicPluginSettingsData.new()
	return save_manager.data.music_plugins

func refresh_plugins() -> bool:
	_ensure_plugin_root()
	_plugins.clear()

	var root_absolute = ProjectSettings.globalize_path(PLUGIN_ROOT_DIR)
	var root_dir = DirAccess.open(root_absolute)
	if root_dir == null:
		return _fail("Failed to open plugin root directory.")

	root_dir.list_dir_begin()
	while true:
		var entry_name = root_dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue
		if not root_dir.current_is_dir():
			continue

		var plugin_dir = root_absolute.path_join(entry_name)
		var load_result = _load_plugin_from_directory(plugin_dir)
		if load_result.is_empty():
			push_warning("Failed to load plugin from %s: %s" % [plugin_dir, last_error])
			continue

		var plugin_payload: Dictionary = load_result.get("plugin_data", {})
		var plugin_id = str(plugin_payload.get("id", "")).strip_edges()
		if plugin_id.is_empty():
			continue

		_plugins[plugin_id] = {
			"plugin": load_result.get("plugin"),
			"dir": plugin_dir,
			"script_path": load_result.get("script_path", ""),
			"plugin_data": plugin_payload
		}

	last_error = ""
	return true

func list_plugins() -> Array[Dictionary]:
	var plugins: Array[Dictionary] = []
	for plugin_id in _plugins.keys():
		plugins.append(_serialize_plugin(_plugins[plugin_id]))
	plugins.sort_custom(_sort_plugin_payloads)
	return plugins

func uninstall_plugin(plugin_id: String) -> bool:
	var normalized_plugin_id = plugin_id.strip_edges()
	if normalized_plugin_id.is_empty():
		return _fail("Plugin id is required.")

	await refresh_plugins()
	var plugin_entry = _get_plugin_entry(normalized_plugin_id)
	if plugin_entry.is_empty():
		return _fail("Plugin not found: %s" % normalized_plugin_id)

	var plugin_dir = str(plugin_entry.get("dir", ""))
	var remove_error = _remove_directory_recursive_absolute(plugin_dir)
	if remove_error != OK:
		return _fail(
			"Failed to remove plugin directory.",
			{"plugin_id": normalized_plugin_id, "code": remove_error}
		)

	_plugins.erase(normalized_plugin_id)
	get_settings().disabled_plugin_ids.erase(normalized_plugin_id)
	last_error = ""
	return true

func get_plugin_user_variables(plugin_id: String) -> Dictionary:
	var normalized_plugin_id = plugin_id.strip_edges()
	if normalized_plugin_id.is_empty():
		_fail("Plugin id is required.")
		return {}

	var plugin_entry = await _require_plugin_entry(normalized_plugin_id)
	if plugin_entry.is_empty():
		return {}

	var plugin_instance = plugin_entry.get("plugin")
	if plugin_instance != null and plugin_instance.has_method("set_runtime_user_variables"):
		plugin_instance.set_runtime_user_variables(_get_plugin_user_vars(normalized_plugin_id))

	return _get_plugin_user_vars(normalized_plugin_id)

func set_plugin_user_variables(plugin_id: String, values: Dictionary) -> bool:
	var normalized_plugin_id = plugin_id.strip_edges()
	if normalized_plugin_id.is_empty():
		return _fail("Plugin id is required.")

	var plugin_entry = await _require_plugin_entry(normalized_plugin_id)
	if plugin_entry.is_empty():
		return false

	var plugin_values = values.duplicate(true)
	_set_plugin_user_vars(normalized_plugin_id, plugin_values)

	var plugin_instance = plugin_entry.get("plugin")
	if plugin_instance != null and plugin_instance.has_method("set_runtime_user_variables"):
		plugin_instance.set_runtime_user_variables(plugin_values)

	last_error = ""
	return true

func install_plugin_from_url(_plugin_url: String) -> bool:
	return _fail("Installing GDScript plugins from URL is not supported.")

## 安装外部 GDScript 插件。支持直接传入 plugin.gd，或包含 plugin.gd 的目录。
func install_plugin_from_file(plugin_path: String) -> Dictionary:
	var normalized_plugin_path = plugin_path.strip_edges()
	if normalized_plugin_path.is_empty():
		_fail("Plugin path is required.")
		return {}

	_ensure_plugin_root()

	var resolved_path = _resolve_command_path(normalized_plugin_path)
	var source_plugin_dir = _resolve_gd_plugin_directory(resolved_path)
	if source_plugin_dir.is_empty():
		_fail("Selected path does not contain a valid plugin.gd entry.")
		return {}

	var load_result = _load_plugin_from_directory(source_plugin_dir)
	if load_result.is_empty():
		return {}

	var plugin_payload: Dictionary = load_result.get("plugin_data", {})
	var plugin_id = str(plugin_payload.get("id", "")).strip_edges()
	if plugin_id.is_empty():
		_fail("Plugin id is empty.")
		return {}

	var target_dir = ProjectSettings.globalize_path(PLUGIN_ROOT_DIR.path_join(plugin_id))
	var remove_error = _remove_directory_recursive_absolute(target_dir)
	if remove_error != OK and DirAccess.dir_exists_absolute(target_dir):
		_fail("Failed to overwrite existing plugin directory.", {"code": remove_error})
		return {}

	var copy_error = _copy_directory_recursive_absolute(source_plugin_dir, target_dir)
	if copy_error != OK:
		_fail("Failed to copy plugin directory.", {"code": copy_error})
		return {}

	if not await refresh_plugins():
		return {}

	return _serialize_plugin(_get_plugin_entry(plugin_id))

func is_plugin_enabled(plugin_id: String) -> bool:
	var normalized_plugin_id := plugin_id.strip_edges()
	if normalized_plugin_id.is_empty():
		return false
	return not get_settings().disabled_plugin_ids.has(normalized_plugin_id)

func set_plugin_enabled(plugin_id: String, enabled: bool) -> void:
	var settings := get_settings()
	var normalized_plugin_id := plugin_id.strip_edges()
	if normalized_plugin_id.is_empty():
		return
	settings.disabled_plugin_ids.erase(normalized_plugin_id)
	if not enabled and not settings.disabled_plugin_ids.has(normalized_plugin_id):
		settings.disabled_plugin_ids.append(normalized_plugin_id)

func search(plugin_id: String, query: String, page: int = 1, media_type: String = "music") -> Dictionary:
	var plugin_result = await _require_plugin_entry(plugin_id)
	if plugin_result.is_empty():
		return {}

	var plugin = plugin_result.get("plugin")
	if plugin == null or not plugin.has_method("search"):
		_fail("Selected plugin does not support search.")
		return {}

	var result = await plugin.search(query, maxi(1, page), media_type)
	last_error = ""
	return result if result is Dictionary else {"isEnd": true, "data": []}

func get_media_source(track, quality: String = "standard") -> Dictionary:
	if track == null or not track.has_method("to_plugin_media_item"):
		_fail("Track does not provide plugin media payload.")
		return {}

	var plugin_result = await _require_plugin_entry(str(track.platform))
	if plugin_result.is_empty():
		return {}

	var plugin = plugin_result.get("plugin")
	if plugin == null or not plugin.has_method("get_media_source"):
		_fail("Selected plugin does not support media source resolving.")
		return {}

	var result = await plugin.get_media_source(track.to_plugin_media_item(), quality)
	last_error = ""
	return result if result is Dictionary else {}

func get_lyric(track) -> Dictionary:
	if track == null or not track.has_method("to_plugin_media_item"):
		_fail("Track does not provide plugin media payload.")
		return {}

	var plugin_result = await _require_plugin_entry(str(track.platform))
	if plugin_result.is_empty():
		return {}

	var plugin = plugin_result.get("plugin")
	if plugin == null or not plugin.has_method("get_lyric"):
		_fail("Selected plugin does not support lyric resolving.")
		return {}

	var result = await plugin.get_lyric(track.to_plugin_media_item())
	last_error = ""
	return result if result is Dictionary else {}

func get_toplists(plugin_id: String) -> Array:
	var plugin_result = await _require_plugin_entry(plugin_id)
	if plugin_result.is_empty():
		return []

	var plugin = plugin_result.get("plugin")
	if plugin == null or not plugin.has_method("get_toplists"):
		_fail("Selected plugin does not support toplists.")
		return []

	var result = await plugin.get_toplists()
	last_error = ""
	return result if result is Array else []

func _ensure_plugin_root() -> void:
	var plugin_root = ProjectSettings.globalize_path(PLUGIN_ROOT_DIR)
	DirAccess.make_dir_recursive_absolute(plugin_root)

func _resolve_gd_plugin_directory(source_path: String) -> String:
	if FileAccess.file_exists(source_path):
		if source_path.get_file().to_lower() != PLUGIN_ENTRY_FILE:
			return ""
		return source_path.get_base_dir()

	if DirAccess.dir_exists_absolute(source_path):
		var direct_entry = source_path.path_join(PLUGIN_ENTRY_FILE)
		if FileAccess.file_exists(direct_entry):
			return source_path

		var found_entry = _find_plugin_entry_recursive(source_path)
		if not found_entry.is_empty():
			return found_entry.get_base_dir()

	return ""

func _find_plugin_entry_recursive(directory_path: String) -> String:
	var dir = DirAccess.open(directory_path)
	if dir == null:
		return ""

	dir.list_dir_begin()
	while true:
		var entry_name = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue

		var entry_path = directory_path.path_join(entry_name)
		if dir.current_is_dir():
			var nested_entry = _find_plugin_entry_recursive(entry_path)
			if not nested_entry.is_empty():
				dir.list_dir_end()
				return nested_entry
		elif entry_name.to_lower() == PLUGIN_ENTRY_FILE:
			dir.list_dir_end()
			return entry_path

	dir.list_dir_end()
	return ""

func _load_plugin_from_directory(plugin_dir: String) -> Dictionary:
	var entry_script_path = plugin_dir.path_join(PLUGIN_ENTRY_FILE)
	if not FileAccess.file_exists(entry_script_path):
		_fail("Plugin entry file is missing.", {"dir": plugin_dir})
		return {}

	var script_resource = load(ProjectSettings.localize_path(entry_script_path))
	if script_resource == null:
		_fail("Failed to load plugin script.", {"path": entry_script_path})
		return {}
	if not (script_resource is GDScript):
		_fail("Plugin entry is not a GDScript resource.", {"path": entry_script_path})
		return {}

	var plugin_instance = (script_resource as GDScript).new()
	if plugin_instance == null:
		_fail("Failed to instantiate plugin script.", {"path": entry_script_path})
		return {}

	var validate_result = _validate_plugin_instance(plugin_instance, plugin_dir)
	if not validate_result:
		return {}

	last_error = ""
	return {
		"plugin": plugin_instance,
		"plugin_data": _build_plugin_payload(plugin_instance, plugin_dir, entry_script_path),
		"script_path": entry_script_path
	}

func _validate_plugin_instance(plugin_instance, plugin_dir: String) -> bool:
	if not plugin_instance.has_method("get_platform"):
		return _fail("Plugin missing get_platform().", {"dir": plugin_dir})
	if not plugin_instance.has_method("get_supported_search_types"):
		return _fail("Plugin missing get_supported_search_types().", {"dir": plugin_dir})

	var platform_name = str(plugin_instance.get_platform()).strip_edges()
	if platform_name.is_empty():
		return _fail("Plugin platform name is empty.", {"dir": plugin_dir})

	last_error = ""
	return true

func _build_plugin_payload(plugin_instance, plugin_dir: String, entry_script_path: String) -> Dictionary:
	var plugin_id = str(plugin_instance.get_platform()).strip_edges()
	var supported_search_types: Array = []
	if plugin_instance.has_method("get_supported_search_types"):
		for item in plugin_instance.get_supported_search_types():
			supported_search_types.append(str(item))

	var user_variables: Array = []
	if plugin_instance.has_method("get_user_variables"):
		user_variables = plugin_instance.get_user_variables()

	var supported_methods: PackedStringArray = PackedStringArray()
	if plugin_instance.has_method("get_supported_methods"):
		supported_methods = plugin_instance.get_supported_methods()

	return {
		"id": plugin_id,
		"name": plugin_id,
		"version": _call_plugin_string(plugin_instance, "get_version"),
		"path": entry_script_path,
		"dir": plugin_dir,
		"srcUrl": _call_plugin_string(plugin_instance, "get_src_url"),
		"supportedSearchType": supported_search_types,
		"defaultSearchType": _call_plugin_string(plugin_instance, "get_default_search_type", "music"),
		"userVariables": user_variables,
		"author": _call_plugin_string(plugin_instance, "get_author"),
		"description": _call_plugin_string(plugin_instance, "get_description"),
		"hasSearch": _supports_plugin_method(plugin_instance, supported_methods, "search", "search"),
		"hasGetMediaSource": _supports_plugin_method(plugin_instance, supported_methods, "get_media_source", "getMediaSource"),
		"hasGetLyric": _supports_plugin_method(plugin_instance, supported_methods, "get_lyric", "getLyric"),
		"hasGetTopLists": _supports_plugin_method(plugin_instance, supported_methods, "get_toplists", "getTopLists"),
		"type": "gd"
	}

func _serialize_plugin(plugin_entry: Variant) -> Dictionary:
	if not (plugin_entry is Dictionary):
		return {}
	var payload = (plugin_entry as Dictionary).get("plugin_data", {})
	return payload.duplicate(true) if payload is Dictionary else {}

func _get_plugin_entry(plugin_id: String) -> Dictionary:
	var normalized_plugin_id = plugin_id.strip_edges()
	if normalized_plugin_id.is_empty():
		return {}
	if _plugins.has(normalized_plugin_id):
		return _plugins[normalized_plugin_id]
	for loaded_plugin_id in _plugins.keys():
		var entry: Dictionary = _plugins[loaded_plugin_id]
		var plugin_data: Dictionary = entry.get("plugin_data", {})
		if str(plugin_data.get("name", "")) == normalized_plugin_id:
			return entry
	return {}

func _require_plugin_entry(plugin_id: String) -> Dictionary:
	await refresh_plugins()
	var plugin_entry = _get_plugin_entry(plugin_id)
	if plugin_entry.is_empty():
		_fail("Plugin not found: %s" % plugin_id)
		return {}

	var plugin_instance = plugin_entry.get("plugin")
	if plugin_instance != null and plugin_instance.has_method("set_runtime_user_variables"):
		plugin_instance.set_runtime_user_variables(_get_plugin_user_vars(str((plugin_entry.get("plugin_data", {}) as Dictionary).get("id", plugin_id))))

	last_error = ""
	return plugin_entry

func _call_plugin_string(plugin_instance, method_name: String, default_value: String = "") -> String:
	if plugin_instance == null or not plugin_instance.has_method(method_name):
		return default_value
	return str(plugin_instance.call(method_name))

func _get_plugin_user_vars(plugin_id: String) -> Dictionary:
	var vars_map = _read_plugin_vars_map()
	var plugin_vars = vars_map.get(plugin_id, {})
	return plugin_vars.duplicate(true) if plugin_vars is Dictionary else {}

func _set_plugin_user_vars(plugin_id: String, values: Dictionary) -> void:
	var vars_map = _read_plugin_vars_map()
	vars_map[plugin_id] = values.duplicate(true)
	_write_plugin_vars_map(vars_map)

func _read_plugin_vars_map() -> Dictionary:
	var vars_path = ProjectSettings.globalize_path(PLUGIN_VARS_FILE)
	if not FileAccess.file_exists(vars_path):
		return {}

	var file = FileAccess.open(vars_path, FileAccess.READ)
	if file == null:
		return {}

	var raw_text = file.get_as_text()
	var json = JSON.new()
	if json.parse(raw_text) != OK or not (json.data is Dictionary):
		return {}
	return json.data

func _write_plugin_vars_map(vars_map: Dictionary) -> void:
	var vars_path = ProjectSettings.globalize_path(PLUGIN_VARS_FILE)
	var vars_dir = vars_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(vars_dir)

	var file = FileAccess.open(vars_path, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to write plugin vars file: %s" % vars_path)
		return
	file.store_string(JSON.stringify(vars_map, "\t"))

func _supports_plugin_method(plugin_instance, supported_methods: PackedStringArray, gd_method_name: String, method_flag_name: String) -> bool:
	if plugin_instance == null or not plugin_instance.has_method(gd_method_name):
		return false
	if supported_methods.is_empty():
		return true
	return method_flag_name in supported_methods

func _sort_plugin_payloads(left: Variant, right: Variant) -> bool:
	var left_dict: Dictionary = left if left is Dictionary else {}
	var right_dict: Dictionary = right if right is Dictionary else {}
	return str(left_dict.get("name", "")).naturalnocasecmp_to(str(right_dict.get("name", ""))) < 0

func _copy_directory_recursive_absolute(source_dir: String, target_dir: String) -> int:
	var make_dir_error = DirAccess.make_dir_recursive_absolute(target_dir)
	if make_dir_error != OK:
		return make_dir_error

	var dir = DirAccess.open(source_dir)
	if dir == null:
		return ERR_CANT_OPEN

	dir.list_dir_begin()
	while true:
		var entry_name = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue

		var source_path = source_dir.path_join(entry_name)
		var target_path = target_dir.path_join(entry_name)
		if dir.current_is_dir():
			var nested_error = _copy_directory_recursive_absolute(source_path, target_path)
			if nested_error != OK:
				dir.list_dir_end()
				return nested_error
		else:
			var copy_error = DirAccess.copy_absolute(source_path, target_path)
			if copy_error != OK:
				dir.list_dir_end()
				return copy_error

	dir.list_dir_end()
	return OK

func _remove_directory_recursive_absolute(target_dir: String) -> int:
	if not DirAccess.dir_exists_absolute(target_dir):
		return OK

	var dir = DirAccess.open(target_dir)
	if dir == null:
		return ERR_CANT_OPEN

	dir.list_dir_begin()
	while true:
		var entry_name = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue

		var entry_path = target_dir.path_join(entry_name)
		if dir.current_is_dir():
			var nested_error = _remove_directory_recursive_absolute(entry_path)
			if nested_error != OK:
				dir.list_dir_end()
				return nested_error
		else:
			var remove_file_error = DirAccess.remove_absolute(entry_path)
			if remove_file_error != OK:
				dir.list_dir_end()
				return remove_file_error

	dir.list_dir_end()
	return DirAccess.remove_absolute(target_dir)

## 将 Godot 资源路径解析为实际系统路径。
func _resolve_command_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path

func _fail(message: String, extra: Dictionary = {}) -> bool:
	last_error = message if extra.is_empty() else "%s %s" % [message, str(extra)]
	if not extra.is_empty():
		push_warning("%s %s" % [message, str(extra)])
	else:
		push_warning(message)
	return false
