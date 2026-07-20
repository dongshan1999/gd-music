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

func is_dir(_path_info: Dictionary) -> bool:
	return false

func is_link(_path_info: Dictionary) -> bool:
	return false

func get_info(path_info: Dictionary) -> Dictionary:
	return _fail("File info is not supported for this path.", str(path_info.get("raw", "")))

func make_dir_recursive(path_info: Dictionary) -> Dictionary:
	return _fail("Directory creation is not supported for this path.", str(path_info.get("raw", "")))

func list_dir(path_info: Dictionary) -> Dictionary:
	return _fail("Directory listing is not supported for this path.", str(path_info.get("raw", "")))

func delete_file(path_info: Dictionary) -> Dictionary:
	return _fail("File deletion is not supported for this path.", str(path_info.get("raw", "")))

func delete_dir(path_info: Dictionary) -> Dictionary:
	return _fail("Directory deletion is not supported for this path.", str(path_info.get("raw", "")))

func copy_from_access_path(path_info: Dictionary, source_access_path: String, chunk_size: int = 1024 * 1024) -> Dictionary:
	return _copy_file_streaming(source_access_path, globalize(path_info), chunk_size, false)

func move_path(source_info: Dictionary, _target_info: Dictionary, _overwrite: bool = true) -> Dictionary:
	return {
		"ok": false,
		"path": str(source_info.get("raw", "")),
		"error": "Native move is not supported for this provider.",
		"unsupported": true
	}

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
	var expected_bytes := file.get_length()
	var bytes := file.get_buffer(expected_bytes)
	if bytes.size() != expected_bytes:
		return _fail("Failed to read the complete file. Expected %s bytes, got %s." % [expected_bytes, bytes.size()], path)
	return _ok(path, {"data": bytes, "bytes": bytes.size()})

func _write_file_bytes(path: String, data: PackedByteArray) -> Dictionary:
	var native_path := _native_access_path(path)
	var dir_result := _ensure_parent_dir(native_path)
	if not bool(dir_result.get("ok", false)):
		return dir_result
	var temporary_path := _temporary_native_sibling_path(native_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _fail("Failed to open temporary file for write. Error: %s" % FileAccess.get_open_error(), path)
	if not file.store_buffer(data):
		file = null
		var write_failure := _fail("Failed to write the complete file.", path)
		return _attach_cleanup_error(write_failure, _cleanup_native_temporary_path(temporary_path))
	file.flush()
	file = null
	var replace_result := _move_native_path(temporary_path, native_path, true)
	if not bool(replace_result.get("ok", false)):
		var replace_failure := _fail(str(replace_result.get("error", "Failed to replace target file.")), path)
		for key in ["rollback_succeeded", "rollback_error", "backup_path"]:
			if replace_result.has(key):
				replace_failure[key] = replace_result[key]
		return _attach_cleanup_error(replace_failure, _cleanup_native_temporary_path(temporary_path))
	return _ok(path, {
		"bytes": data.size(),
		"atomic": true,
		"cleanup_error": str(replace_result.get("cleanup_error", "")),
		"backup_path": str(replace_result.get("backup_path", ""))
	})

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

func _get_native_file_info(path: String, virtual_path: String = "") -> Dictionary:
	var native_path := path.strip_edges()
	var result_path := virtual_path if not virtual_path.is_empty() else native_path
	var link := _is_native_link(native_path)
	var target_directory := DirAccess.dir_exists_absolute(native_path)
	var target_file := FileAccess.file_exists(native_path)
	if not link and not target_directory and not target_file:
		return _fail("Path does not exist.", result_path)
	var info := {
		"ok": true,
		"path": result_path,
		"native_path": native_path,
		"name": native_path.get_file(),
		"is_dir": target_directory and not link,
		"is_file": target_file and not link,
		"is_link": link,
		"link_target_is_dir": link and target_directory,
		"link_target_is_file": link and target_file,
		"size": 0,
		"modified_time": 0,
		"extension": native_path.get_extension().to_lower(),
		"error": ""
	}
	if target_file and not link:
		info["size"] = FileAccess.get_size(native_path)
		info["modified_time"] = FileAccess.get_modified_time(native_path)
	return info

func _delete_native_file(path: String) -> Dictionary:
	if _is_native_link(path):
		var link_error := DirAccess.remove_absolute(path)
		return _ok(path) if link_error == OK else _fail("Failed to delete symbolic link. Error: %s" % link_error, path)
	if DirAccess.dir_exists_absolute(path):
		return _fail("Path is a directory.", path)
	if not FileAccess.file_exists(path):
		return _fail("File does not exist.", path)
	var err := DirAccess.remove_absolute(path)
	return _ok(path) if err == OK else _fail("Failed to delete file. Error: %s" % err, path)

func _delete_native_dir(path: String) -> Dictionary:
	if _is_native_link(path):
		return _fail("Path is a symbolic link, not a directory.", path)
	if not DirAccess.dir_exists_absolute(path):
		return _fail("Directory does not exist.", path)
	var err := DirAccess.remove_absolute(path)
	return _ok(path) if err == OK else _fail("Failed to delete directory. Error: %s" % err, path)

func _copy_file_streaming(
	source_access_path: String,
	target_access_path: String,
	chunk_size: int,
	atomic_target: bool
) -> Dictionary:
	var source := FileAccess.open(source_access_path, FileAccess.READ)
	if source == null:
		return _fail("Failed to open source file for read. Error: %s" % FileAccess.get_open_error(), source_access_path)
	var native_target := _native_access_path(target_access_path)
	var dir_result := _ensure_parent_dir(native_target)
	if not bool(dir_result.get("ok", false)):
		return dir_result
	var write_path := _temporary_native_sibling_path(native_target) if atomic_target else target_access_path
	var target := FileAccess.open(write_path, FileAccess.WRITE)
	if target == null:
		return _fail("Failed to open target file for write. Error: %s" % FileAccess.get_open_error(), target_access_path)

	var total_bytes := source.get_length()
	var copied_bytes := 0
	var safe_chunk_size := maxi(64 * 1024, chunk_size)
	while copied_bytes < total_bytes:
		var requested_bytes := mini(safe_chunk_size, total_bytes - copied_bytes)
		var chunk := source.get_buffer(requested_bytes)
		if chunk.size() != requested_bytes:
			target = null
			var read_failure := _fail("Failed to read the complete source file.", source_access_path)
			return _attach_cleanup_error(read_failure, _cleanup_native_temporary_path(write_path)) if atomic_target else read_failure
		if not target.store_buffer(chunk):
			target = null
			var write_failure := _fail("Failed while writing the target file.", target_access_path)
			return _attach_cleanup_error(write_failure, _cleanup_native_temporary_path(write_path)) if atomic_target else write_failure
		copied_bytes += chunk.size()
	target.flush()
	target = null
	source = null

	if atomic_target:
		var replace_result := _move_native_path(write_path, native_target, true)
		if not bool(replace_result.get("ok", false)):
			var replace_failure := _fail(str(replace_result.get("error", "Failed to replace target file.")), target_access_path)
			for key in ["rollback_succeeded", "rollback_error", "backup_path"]:
				if replace_result.has(key):
					replace_failure[key] = replace_result[key]
			return _attach_cleanup_error(replace_failure, _cleanup_native_temporary_path(write_path))
		return _ok(target_access_path, {
			"bytes": copied_bytes,
			"atomic": true,
			"cleanup_error": str(replace_result.get("cleanup_error", "")),
			"backup_path": str(replace_result.get("backup_path", ""))
		})
	return _ok(target_access_path, {"bytes": copied_bytes, "atomic": false})

func _move_native_path(source_path: String, target_path: String, overwrite: bool) -> Dictionary:
	var normalized_source := _native_access_path(source_path).simplify_path()
	var normalized_target := _native_access_path(target_path).simplify_path()
	if normalized_source == normalized_target:
		return _ok(target_path)
	if not _native_path_exists(normalized_source):
		return _fail("Source path does not exist.", source_path)
	var parent_result := _ensure_parent_dir(normalized_target)
	if not bool(parent_result.get("ok", false)):
		return parent_result
	var target_exists := _native_path_exists(normalized_target)
	if target_exists and not overwrite:
		return _fail("Target path already exists.", target_path)

	var backup_path := ""
	if target_exists:
		backup_path = _temporary_native_sibling_path(normalized_target, "backup")
		var backup_error := DirAccess.rename_absolute(normalized_target, backup_path)
		if backup_error != OK:
			return _fail("Failed to preserve existing target. Error: %s" % backup_error, target_path)

	var move_error := DirAccess.rename_absolute(normalized_source, normalized_target)
	if move_error != OK:
		var rollback_error := OK
		if not backup_path.is_empty():
			rollback_error = DirAccess.rename_absolute(backup_path, normalized_target)
		var rollback_succeeded := backup_path.is_empty() or rollback_error == OK
		var message := "Native move failed. Error: %s" % move_error
		if not rollback_succeeded:
			message += " Existing target rollback also failed. Error: %s" % rollback_error
		return {
			"ok": false,
			"path": target_path,
			"error": message,
			"unsupported": rollback_succeeded,
			"rollback_succeeded": rollback_succeeded,
			"rollback_error": rollback_error,
			"backup_path": backup_path if not rollback_succeeded else ""
		}

	var cleanup_error := ""
	if not backup_path.is_empty():
		var cleanup_result := _remove_native_path_recursive_safe(backup_path)
		if not bool(cleanup_result.get("ok", false)):
			cleanup_error = str(cleanup_result.get("error", ""))
	return _ok(target_path, {
		"cleanup_error": cleanup_error,
		"backup_path": backup_path if not cleanup_error.is_empty() else ""
	})

func _cleanup_native_temporary_path(path: String) -> String:
	if path.is_empty() or not _native_path_exists(path):
		return ""
	var cleanup_result := _remove_native_path_recursive_safe(path)
	return "" if bool(cleanup_result.get("ok", false)) else str(cleanup_result.get("error", "Failed to clean temporary path."))

func _attach_cleanup_error(result: Dictionary, cleanup_error: String) -> Dictionary:
	if not cleanup_error.is_empty():
		var existing_cleanup_error := str(result.get("cleanup_error", ""))
		result["cleanup_error"] = cleanup_error if existing_cleanup_error.is_empty() else "%s; %s" % [existing_cleanup_error, cleanup_error]
	return result

func _remove_native_path_recursive_safe(path: String) -> Dictionary:
	if _is_native_link(path) or FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		var file_error := DirAccess.remove_absolute(path)
		return _ok(path) if file_error == OK else _fail("Failed to remove path. Error: %s" % file_error, path)
	if not DirAccess.dir_exists_absolute(path):
		return _ok(path)
	var directory := DirAccess.open(path)
	if directory == null:
		return _fail("Failed to open directory for cleanup.", path)
	directory.list_dir_begin()
	while true:
		var child_name := directory.get_next()
		if child_name.is_empty():
			break
		var child_path := path.path_join(child_name)
		var child_is_link := directory.is_link(child_name)
		var child_is_dir := directory.current_is_dir() and not child_is_link
		var child_result := _remove_native_path_recursive_safe(child_path) if child_is_dir else _delete_native_file(child_path)
		if not bool(child_result.get("ok", false)):
			directory.list_dir_end()
			return child_result
	directory.list_dir_end()
	var dir_error := DirAccess.remove_absolute(path)
	return _ok(path) if dir_error == OK else _fail("Failed to remove directory. Error: %s" % dir_error, path)

func _is_native_link(path: String) -> bool:
	var normalized := _native_access_path(path).simplify_path()
	var parent_path := normalized.get_base_dir()
	var file_name := normalized.get_file()
	if parent_path.is_empty() or file_name.is_empty():
		return false
	var parent := DirAccess.open(parent_path)
	return parent != null and parent.is_link(file_name)

func _native_path_exists(path: String) -> bool:
	return _is_native_link(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

func _native_access_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path

func _temporary_native_sibling_path(path: String, label: String = "tmp") -> String:
	var normalized := _native_access_path(path)
	var parent := normalized.get_base_dir()
	var file_name := normalized.get_file()
	var suffix := "%s-%s-%s" % [label, Time.get_ticks_usec(), randi()]
	return parent.path_join(".%s.dx-%s" % [file_name, suffix])
