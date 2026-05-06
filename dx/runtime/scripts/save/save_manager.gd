class_name AppSaveManager
extends Node
const SAVE_ROOT := "user://save_data"
const DEFAULT_DATA_PATH := "app/data.json"
const APP_SAVE_DATA_SCRIPT := preload("res://dx/runtime/scripts/save/save_data.gd")
const JSON_SERIALIZER_SCRIPT := preload("res://dx/runtime/scripts/serializer/json_serializer.gd")

var data = APP_SAVE_DATA_SCRIPT.new()
var _data_path: String = DEFAULT_DATA_PATH

func _enter_tree() -> void:
	ensure_dir("")
	load_data()

func get_save_root() -> String:
	return SAVE_ROOT

func get_user_path(relative_path: String = "") -> String:
	var cleaned := _normalize_relative_path(relative_path)
	if cleaned.is_empty():
		return SAVE_ROOT
	return "%s/%s" % [SAVE_ROOT, cleaned]

func get_native_path(relative_path: String = "") -> String:
	return ProjectSettings.globalize_path(get_user_path(relative_path))

func ensure_dir(relative_dir: String = "") -> bool:
	var native_path := get_native_path(relative_dir)
	var err := DirAccess.make_dir_recursive_absolute(native_path)
	return err == OK or err == ERR_ALREADY_EXISTS

func save_json(relative_path: String, payload: Variant, pretty: bool = true) -> bool:
	if not _ensure_parent_dir(relative_path):
		return false

	var file := FileAccess.open(get_user_path(relative_path), FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(payload, "\t" if pretty else ""))
	return true

func load_json(relative_path: String, default_value: Variant = null) -> Variant:
	var user_path := get_user_path(relative_path)
	if not FileAccess.file_exists(user_path):
		return _duplicate_value(default_value)

	var file := FileAccess.open(user_path, FileAccess.READ)
	if file == null:
		return _duplicate_value(default_value)

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		return _duplicate_value(default_value)
	return parsed

func save_var(relative_path: String, payload: Variant, full_objects: bool = false) -> bool:
	if not _ensure_parent_dir(relative_path):
		return false

	var file := FileAccess.open(get_user_path(relative_path), FileAccess.WRITE)
	if file == null:
		return false

	file.store_var(payload, full_objects)
	return true

func load_var(relative_path: String, default_value: Variant = null, allow_objects: bool = false) -> Variant:
	var user_path := get_user_path(relative_path)
	if not FileAccess.file_exists(user_path):
		return _duplicate_value(default_value)

	var file := FileAccess.open(user_path, FileAccess.READ)
	if file == null:
		return _duplicate_value(default_value)

	return file.get_var(allow_objects)

func save_text(relative_path: String, text: String) -> bool:
	if not _ensure_parent_dir(relative_path):
		return false

	var file := FileAccess.open(get_user_path(relative_path), FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(text)
	return true

func load_text(relative_path: String, default_value: String = "") -> String:
	var user_path := get_user_path(relative_path)
	if not FileAccess.file_exists(user_path):
		return default_value

	var file := FileAccess.open(user_path, FileAccess.READ)
	if file == null:
		return default_value

	return file.get_as_text()

func save_object(relative_path: String, object, pretty: bool = true) -> bool:
	if object == null:
		return false

	var serialized_object = clone_object(object)
	if serialized_object == null:
		return false
	_normalize_object(serialized_object)

	var serialized_data = serialize_object(serialized_object)
	if JSON_SERIALIZER_SCRIPT.has_error():
		return false
	return save_json(relative_path, serialized_data, pretty)

func load_object(relative_path: String, default_object):
	if default_object == null:
		return null

	var loaded_object = clone_object(default_object)
	if loaded_object == null:
		return null
	var parsed: Variant = load_json(relative_path, null)
	if typeof(parsed) == TYPE_DICTIONARY:
		populate_object(loaded_object, parsed)

	_normalize_object(loaded_object)
	return loaded_object

func serialize_object(object, include_ignored: bool = false) -> Dictionary:
	if object == null:
		return {}
	return JSON_SERIALIZER_SCRIPT.serialize(object, include_ignored)

func populate_object(object, source_data: Dictionary) -> void:
	if object == null:
		return
	JSON_SERIALIZER_SCRIPT.deserialize(source_data, object)

func clone_object(object):
	if object == null:
		return null

	var script = object.get_script()
	if script == null:
		return null

	var cloned = script.new()
	if cloned == null:
		return null

	var serialized_data = JSON_SERIALIZER_SCRIPT.serialize(object, true)
	if JSON_SERIALIZER_SCRIPT.has_error():
		return null

	JSON_SERIALIZER_SCRIPT.deserialize(serialized_data, cloned, true)
	if JSON_SERIALIZER_SCRIPT.has_error():
		return null
	return cloned

func load_data(default_data = null, relative_path: String = DEFAULT_DATA_PATH):
	_data_path = relative_path
	var has_existing_file := file_exists(_data_path)
	var fallback_data = default_data if default_data != null else APP_SAVE_DATA_SCRIPT.new()
	data = load_object(_data_path, fallback_data)
	if data == null:
		data = clone_object(fallback_data)
	_normalize_object(data)
	if not has_existing_file:
		save_data()
	return data

func save_data(relative_path: String = "") -> bool:
	var target_path := _data_path if relative_path.is_empty() else relative_path
	_data_path = target_path
	return save_object(_data_path, data, true)

func file_exists(relative_path: String) -> bool:
	return FileAccess.file_exists(get_user_path(relative_path))

func delete_file(relative_path: String) -> bool:
	var user_path := get_user_path(relative_path)
	if not FileAccess.file_exists(user_path):
		return false

	return DirAccess.remove_absolute(ProjectSettings.globalize_path(user_path)) == OK

func list_files(relative_dir: String = "") -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(get_user_path(relative_dir))
	if dir == null:
		return result

	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		result.append(entry)
	dir.list_dir_end()
	return result

func get_storage_info(relative_path: String = "") -> Dictionary:
	var platform := OS.get_name()
	var user_path := get_user_path(relative_path)
	var native_path := get_native_path(relative_path)
	return {
		"platform": platform,
		"user_path": user_path,
		"native_path": native_path,
		"save_root_user_path": SAVE_ROOT,
		"save_root_native_path": get_native_path(""),
		"can_browse_directly": platform in ["Windows", "macOS", "LinuxBSD"],
		"note": _platform_note(platform)
	}

func open_storage_location(relative_path: String = "") -> Dictionary:
	ensure_dir("")

	var platform := OS.get_name()
	var user_path := get_user_path(relative_path)
	var native_path := get_native_path(relative_path)
	var target_native_path := native_path
	var is_directory := DirAccess.dir_exists_absolute(native_path)

	if not is_directory and not FileAccess.file_exists(user_path):
		target_native_path = get_native_path("")
		is_directory = true

	var err := FAILED
	if platform == "Windows" or platform == "macOS":
		err = OS.shell_show_in_file_manager(target_native_path, is_directory)
	else:
		err = OS.shell_open(target_native_path)
		if err != OK:
			err = OS.shell_open("file://" + target_native_path)

	return {
		"ok": err == OK,
		"error": err,
		"platform": platform,
		"user_path": user_path,
		"native_path": target_native_path,
		"note": _platform_note(platform)
	}

func _ensure_parent_dir(relative_path: String) -> bool:
	var cleaned := _normalize_relative_path(relative_path)
	var parent_dir := cleaned.get_base_dir()
	if parent_dir == "." or parent_dir.is_empty():
		return ensure_dir("")
	return ensure_dir(parent_dir)

func _normalize_relative_path(relative_path: String) -> String:
	return relative_path.replace("\\", "/").trim_prefix("/").trim_suffix("/")

func _duplicate_value(value: Variant) -> Variant:
	if value is Array:
		return (value as Array).duplicate(true)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return value

func _normalize_object(object: Variant) -> void:
	if object != null and object.has_method("normalize"):
		object.call("normalize")

func _platform_note(platform: String) -> String:
	match platform:
		"Windows":
			return "Windows 下 user:// 会映射到用户数据目录，通常可直接用资源管理器打开。"
		"macOS":
			return "macOS 下 user:// 位于应用支持目录，Finder 可直接打开。"
		"Android":
			return "Android 下 user:// 位于应用沙盒，持久化没问题，但外部文件管理器不一定能直接访问。"
		"iOS":
			return "iOS 下 user:// 位于应用沙盒，通常只能通过应用内导出、Xcode 或设备管理工具查看。"
		_:
			return "当前平台使用 Godot 的 user:// 持久化目录。"
