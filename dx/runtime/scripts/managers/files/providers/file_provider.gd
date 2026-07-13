class_name DX_FileProvider
extends RefCounted

var dx: Node

func setup(dx_root: Node) -> void:
	dx = dx_root

func supports(_path_info: Dictionary) -> bool:
	return false

func read_bytes(path_info: Dictionary) -> Dictionary:
	return _fail("Read is not supported for this path.", str(path_info.get("raw", "")))

func write_bytes(path_info: Dictionary, _data: PackedByteArray) -> Dictionary:
	return _fail("Write is not supported for this path.", str(path_info.get("raw", "")))

func exists(_path_info: Dictionary) -> bool:
	return false

func make_dir_recursive(path_info: Dictionary) -> Dictionary:
	return _fail("Directory creation is not supported for this path.", str(path_info.get("raw", "")))

func globalize(path_info: Dictionary) -> String:
	return str(path_info.get("raw", ""))

func _ok(path: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"path": path,
		"error": ""
	}
	for key in extra.keys():
		result[key] = extra[key]
	return result

func _fail(message: String, path: String = "") -> Dictionary:
	return {
		"ok": false,
		"path": path,
		"error": message
	}

func _read_file_bytes(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("File does not exist.", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Failed to open file for read. Error: %s" % FileAccess.get_open_error(), path)
	var bytes := file.get_buffer(file.get_length())
	return _ok(path, {"data": bytes, "bytes": bytes.size()})

func _write_file_bytes(path: String, data: PackedByteArray) -> Dictionary:
	var dir_result := _ensure_parent_dir(path)
	if not bool(dir_result.get("ok", false)):
		return dir_result
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("Failed to open file for write. Error: %s" % FileAccess.get_open_error(), path)
	file.store_buffer(data)
	return _ok(path, {"bytes": data.size()})

func _ensure_parent_dir(path: String) -> Dictionary:
	var base_dir := path.get_base_dir()
	if base_dir.is_empty():
		return _ok(path)
	var native_dir := base_dir
	if base_dir.begins_with("res://") or base_dir.begins_with("user://"):
		native_dir = ProjectSettings.globalize_path(base_dir)
	var err := DirAccess.make_dir_recursive_absolute(native_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return _fail("Failed to create directory. Error: %s" % err, path)
	return _ok(path)
