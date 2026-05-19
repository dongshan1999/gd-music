class_name MusicAppPluginController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const PLUGIN_ROOT_DIR := "user://gdmusic_plugins"
const PLUGIN_ENTRY_FILE := "plugin.gd"

var _plugins: Dictionary = {}
var last_error := ""

## 控制器进入运行期时预热插件设置对象并刷新本地插件列表。
func in_ready() -> void:
	get_settings()
	await refresh_plugins()

func in_quit() -> void:
	pass

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
		var load_result = _load_plugin_from_script(plugin_dir.path_join(PLUGIN_ENTRY_FILE))
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

func install_plugin_from_url(_plugin_url: String) -> bool:
	return _fail("Installing GDScript plugins from URL is not supported.")

## 按指定路径导入插件脚本。支持单个脚本文件，或递归扫描目录中的插件脚本。
func install_plugin_from_file(plugin_path: String) -> Dictionary:
	var normalized_plugin_path = plugin_path.strip_edges()
	if normalized_plugin_path.is_empty():
		_fail("Plugin path is required.")
		return {}

	_ensure_plugin_root()

	var resolved_path = _resolve_command_path(normalized_plugin_path)
	var source_script_paths = _collect_plugin_script_paths(resolved_path)
	if source_script_paths.is_empty():
		_fail("Selected path does not contain a valid plugin script.")
		return {}

	var installed_plugin_ids := PackedStringArray()
	for source_script_path in source_script_paths:
		var load_result = _load_plugin_from_script(source_script_path)
		if load_result.is_empty():
			continue

		var plugin_payload: Dictionary = load_result.get("plugin_data", {})
		var plugin_id = str(plugin_payload.get("id", "")).strip_edges()
		if plugin_id.is_empty():
			push_warning("Skipped plugin script with empty plugin id: %s" % source_script_path)
			continue

		var target_dir = ProjectSettings.globalize_path(PLUGIN_ROOT_DIR.path_join(plugin_id))
		var remove_error = _remove_directory_recursive_absolute(target_dir)
		if remove_error != OK and DirAccess.dir_exists_absolute(target_dir):
			push_warning(
				"Failed to overwrite existing plugin directory. %s" %
				str({"plugin_id": plugin_id, "code": remove_error})
			)
			continue

		var copy_error = _copy_plugin_script_absolute(source_script_path, target_dir)
		if copy_error != OK:
			push_warning(
				"Failed to copy plugin script. %s" %
				str({"plugin_id": plugin_id, "code": copy_error, "path": source_script_path})
			)
			continue

		if not installed_plugin_ids.has(plugin_id):
			installed_plugin_ids.append(plugin_id)

	if installed_plugin_ids.is_empty():
		_fail("Selected path does not contain a valid plugin script.")
		return {}

	if not await refresh_plugins():
		return {}

	var installed_plugins: Array[Dictionary] = []
	for plugin_id in installed_plugin_ids:
		var plugin_entry = _get_plugin_entry(plugin_id)
		if not plugin_entry.is_empty():
			installed_plugins.append(_serialize_plugin(plugin_entry))

	if installed_plugins.size() == 1:
		return installed_plugins[0]
	return {"plugins": installed_plugins}

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
	print("[MusicPluginController] search request:",
		{
			"plugin_id": plugin_id,
			"query": query,
			"page": page,
			"media_type": media_type
		}
	)
	var plugin_result = await _require_plugin_entry(plugin_id)
	if plugin_result.is_empty():
		print("[MusicPluginController] search aborted: plugin entry missing, last_error=", last_error)
		return {}

	var plugin = plugin_result.get("plugin")
	if plugin == null or not plugin.has_method("search"):
		_fail("Selected plugin does not support search.")
		print("[MusicPluginController] search aborted: plugin missing search(), last_error=", last_error)
		return {}

	var result = await plugin.search(query, maxi(1, page), media_type)
	print("[MusicPluginController] search result:",
		{
			"is_dictionary": result is Dictionary,
			"keys": result.keys() if result is Dictionary else [],
			"data_size": (result.get("data", []) as Array).size() if result is Dictionary and result.get("data", []) is Array else -1,
			"is_end": result.get("isEnd", null) if result is Dictionary else null
		}
	)
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

func _load_plugin_from_script(entry_script_path: String) -> Dictionary:
	if not FileAccess.file_exists(entry_script_path):
		_fail("Plugin script is missing.", {"path": entry_script_path})
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

	var plugin_dir = entry_script_path.get_base_dir()
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

	last_error = ""
	return plugin_entry

func _call_plugin_string(plugin_instance, method_name: String, default_value: String = "") -> String:
	if plugin_instance == null or not plugin_instance.has_method(method_name):
		return default_value
	return str(plugin_instance.call(method_name))

func _collect_plugin_script_paths(source_path: String) -> Array[String]:
	var script_paths: Array[String] = []
	if FileAccess.file_exists(source_path):
		if _looks_like_plugin_script(source_path):
			script_paths.append(source_path)
		return script_paths
	if not DirAccess.dir_exists_absolute(source_path):
		return script_paths

	_collect_plugin_script_paths_recursive(source_path, script_paths)
	return script_paths

func _collect_plugin_script_paths_recursive(directory_path: String, script_paths: Array[String]) -> void:
	var dir = DirAccess.open(directory_path)
	if dir == null:
		return

	dir.list_dir_begin()
	while true:
		var entry_name = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue

		var entry_path = directory_path.path_join(entry_name)
		if dir.current_is_dir():
			_collect_plugin_script_paths_recursive(entry_path, script_paths)
			continue
		if entry_path.get_extension().to_lower() != "gd":
			continue
		if _looks_like_plugin_script(entry_path):
			script_paths.append(entry_path)

	dir.list_dir_end()

func _looks_like_plugin_script(script_path: String) -> bool:
	if script_path.get_extension().to_lower() != "gd":
		return false

	var file = FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return false

	var source_text = file.get_as_text()
	if source_text.contains("func get_platform") and source_text.contains("func get_supported_search_types"):
		return true
	if source_text.contains("extends GDMusicPluginBase") or source_text.contains("extends GDMusicPluginMethods"):
		return true
	if source_text.contains('extends "res://gdmusic_plugin_codegen/godot/base/gdmusic_plugin_methods.gd"'):
		return true
	return false

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

func _copy_plugin_script_absolute(source_script_path: String, target_dir: String) -> int:
	var make_dir_error = DirAccess.make_dir_recursive_absolute(target_dir)
	if make_dir_error != OK:
		return make_dir_error
	return DirAccess.copy_absolute(source_script_path, target_dir.path_join(PLUGIN_ENTRY_FILE))

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
