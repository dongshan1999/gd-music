extends RefCounted

const SAVE_ROOT := "user://save_data"
const DEFAULT_DATA_PATH := "app/data.json"
const APP_SAVE_DATA_SCRIPT := preload("res://dx/runtime/scripts/managers/save/save_data.gd")
const JSON_SERIALIZER_SCRIPT := preload("res://dx/runtime/scripts/serializer/json_serializer.gd")

var dx: Node
var data = APP_SAVE_DATA_SCRIPT.new()
var _data_path: String = DEFAULT_DATA_PATH

func in_ready() -> void:
	_ensure_dir("")
	load_data()

func save(relative_path: String, value: Variant) -> bool:
	var encoded = _encode_save_value(value)
	if not bool(encoded.get("ok", false)):
		return false
	return _save_json(relative_path, encoded.get("value"))

func load(relative_path: String, default_value: Variant = null):
	if _is_json_object(default_value):
		return _load_object(relative_path, default_value)
	return _load_json(relative_path, default_value)

func load_data(relative_path: String = DEFAULT_DATA_PATH):
	_data_path = relative_path
	var has_existing_file := _file_exists(_data_path)
	var fallback_data = APP_SAVE_DATA_SCRIPT.new()
	data = self.load(_data_path, fallback_data)
	if data == null:
		data = _clone_object(fallback_data)
	_normalize_object(data)
	if not has_existing_file:
		save_data()
	return data

func save_data(relative_path: String = "") -> bool:
	var target_path := _data_path if relative_path.is_empty() else relative_path
	_data_path = target_path
	return save(_data_path, data)

func _get_user_path(relative_path: String = "") -> String:
	var cleaned := _normalize_relative_path(relative_path)
	if cleaned.is_empty():
		return SAVE_ROOT
	return "%s/%s" % [SAVE_ROOT, cleaned]

func _get_native_path(relative_path: String = "") -> String:
	return ProjectSettings.globalize_path(_get_user_path(relative_path))

func _ensure_dir(relative_dir: String = "") -> bool:
	var native_path := _get_native_path(relative_dir)
	var err := DirAccess.make_dir_recursive_absolute(native_path)
	return err == OK or err == ERR_ALREADY_EXISTS

func _file_exists(relative_path: String) -> bool:
	return FileAccess.file_exists(_get_user_path(relative_path))

func _save_json(relative_path: String, payload: Variant, pretty: bool = true) -> bool:
	if not _ensure_parent_dir(relative_path):
		return false

	var file := FileAccess.open(_get_user_path(relative_path), FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(payload, "\t" if pretty else ""))
	return true

func _load_json(relative_path: String, default_value: Variant = null) -> Variant:
	var user_path := _get_user_path(relative_path)
	if not FileAccess.file_exists(user_path):
		return _duplicate_value(default_value)

	var file := FileAccess.open(user_path, FileAccess.READ)
	if file == null:
		return _duplicate_value(default_value)

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _duplicate_value(default_value)
	return json.data

func _load_object(relative_path: String, default_object):
	if default_object == null:
		return null

	var loaded_object = _clone_object(default_object)
	if loaded_object == null:
		return null
	var parsed: Variant = _load_json(relative_path, null)
	if typeof(parsed) == TYPE_DICTIONARY:
		_populate_object(loaded_object, parsed)

	_normalize_object(loaded_object)
	return loaded_object

func _serialize_object(object, include_ignored: bool = false) -> Dictionary:
	if object == null:
		return {}
	return JSON_SERIALIZER_SCRIPT.serialize(object, include_ignored)

func _populate_object(object, source_data: Dictionary) -> void:
	if object == null:
		return
	JSON_SERIALIZER_SCRIPT.deserialize(source_data, object)

func _clone_object(object):
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

func _encode_save_value(value: Variant) -> Dictionary:
	if _is_json_object(value):
		var normalized_object = _clone_object(value)
		if normalized_object == null:
			return {"ok": false}
		_normalize_object(normalized_object)
		return {
			"ok": true,
			"value": _serialize_object(normalized_object)
		}

	if value == null or value is Dictionary or value is Array:
		return {
			"ok": true,
			"value": _duplicate_value(value)
		}

	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return {"ok": true, "value": value}

	push_error(
		"SaveManager.save only supports JSON-compatible values or JsonObject instances."
	)
	return {"ok": false}

func _is_json_object(value: Variant) -> bool:
	return value != null and value is Object and value.has_method("_get_serialize_config")

func _ensure_parent_dir(relative_path: String) -> bool:
	var cleaned := _normalize_relative_path(relative_path)
	var parent_dir := cleaned.get_base_dir()
	if parent_dir == "." or parent_dir.is_empty():
		return _ensure_dir("")
	return _ensure_dir(parent_dir)

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
