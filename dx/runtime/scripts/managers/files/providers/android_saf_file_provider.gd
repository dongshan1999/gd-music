class_name DX_AndroidSafFileProvider
extends "res://dx/runtime/scripts/managers/files/providers/file_provider.gd"

const AndroidSafTreeScript := preload("res://dx/runtime/scripts/platform/android/dx_android_saf_tree.gd")
const SCHEME_SAF_FILE := "saf-file"
const SCHEME_SAF_TREE := "saf-tree"

func supports(path_info: Dictionary) -> bool:
	var scheme := str(path_info.get("scheme", ""))
	return scheme == SCHEME_SAF_FILE or scheme == SCHEME_SAF_TREE

func read_bytes(path_info: Dictionary) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(path_info.get("raw", "")))
	return _read_file_bytes(_to_godot_path(path_info))

func write_bytes(path_info: Dictionary, data: PackedByteArray) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(path_info.get("raw", "")))
	var scheme := str(path_info.get("scheme", ""))
	var godot_path := _to_godot_path(path_info)
	if godot_path.is_empty():
		return _fail("Android SAF write path is empty.", str(path_info.get("raw", "")))
	if scheme == SCHEME_SAF_FILE:
		var direct_result := _write_saf_access_path(godot_path, data)
		if bool(direct_result.get("ok", false)):
			direct_result["atomic"] = false
		return direct_result
	if scheme != SCHEME_SAF_TREE:
		return _fail("Unsupported Android SAF scheme.", str(path_info.get("raw", "")))

	var tree_uri := str(path_info.get("body", "")).strip_edges()
	var relative_path := str(path_info.get("relative_path", "")).strip_edges().trim_prefix("/")
	if relative_path.is_empty():
		return _fail("Android SAF tree writes require a relative file path.", str(path_info.get("raw", "")))
	var temporary_relative_path := _temporary_tree_relative_path(relative_path)
	var temporary_access_path := "%s#%s" % [tree_uri, temporary_relative_path]
	var write_result := _write_saf_access_path(temporary_access_path, data)
	if not bool(write_result.get("ok", false)):
		return _attach_saf_cleanup_error(write_result, _cleanup_saf_tree_path(tree_uri, temporary_relative_path))

	var replace_result := AndroidSafTreeScript.move_path(tree_uri, temporary_relative_path, relative_path, true)
	if not bool(replace_result.get("ok", false)):
		var replace_failure := _fail(str(replace_result.get("error", "Failed to replace Android SAF target.")), str(path_info.get("raw", "")))
		for key in ["rollback_succeeded", "rollback_error", "backup_path"]:
			if replace_result.has(key):
				replace_failure[key] = replace_result[key]
		return _attach_saf_cleanup_error(replace_failure, _cleanup_saf_tree_path(tree_uri, temporary_relative_path))
	return _ok(str(path_info.get("raw", "")), {
		"bytes": data.size(),
		"atomic": true,
		"cleanup_error": str(replace_result.get("cleanup_error", "")),
		"backup_path": str(replace_result.get("backup_path", ""))
	})

func exists(path_info: Dictionary) -> bool:
	if not is_supported():
		return false
	var scheme := str(path_info.get("scheme", ""))
	if scheme == SCHEME_SAF_TREE:
		return AndroidSafTreeScript.tree_path_exists(
			str(path_info.get("body", "")),
			str(path_info.get("relative_path", ""))
		)
	return FileAccess.file_exists(_to_godot_path(path_info))

func is_dir(path_info: Dictionary) -> bool:
	if not is_supported():
		return false
	if str(path_info.get("scheme", "")) != SCHEME_SAF_TREE:
		return false
	return AndroidSafTreeScript.path_is_directory(
		str(path_info.get("body", "")),
		str(path_info.get("relative_path", ""))
	)

func get_info(path_info: Dictionary) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(path_info.get("raw", "")))
	var scheme := str(path_info.get("scheme", ""))
	if scheme == SCHEME_SAF_FILE:
		return AndroidSafTreeScript.get_uri_info(str(path_info.get("body", "")))
	if scheme == SCHEME_SAF_TREE:
		return AndroidSafTreeScript.get_path_info(
			str(path_info.get("body", "")),
			str(path_info.get("relative_path", ""))
		)
	return _fail("Unsupported Android SAF scheme.", str(path_info.get("raw", "")))

func make_dir_recursive(path_info: Dictionary) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(path_info.get("raw", "")))
	if str(path_info.get("scheme", "")) != SCHEME_SAF_TREE:
		return _fail("Android SAF directory creation requires a tree URI.", str(path_info.get("raw", "")))
	return AndroidSafTreeScript.make_dir_recursive(
		str(path_info.get("body", "")),
		str(path_info.get("relative_path", ""))
	)

func list_dir(path_info: Dictionary) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(path_info.get("raw", "")))
	var scheme := str(path_info.get("scheme", ""))
	if scheme != SCHEME_SAF_TREE:
		return _fail("Android SAF directory listing requires a tree URI.", str(path_info.get("raw", "")))

	var tree_uri := str(path_info.get("body", "")).strip_edges()
	var relative_dir := str(path_info.get("relative_path", "")).strip_edges().trim_prefix("/")
	var list_result := AndroidSafTreeScript.list_entries_result(tree_uri, relative_dir)
	if not bool(list_result.get("ok", false)):
		return list_result
	var raw_entries: Array = list_result.get("entries", [])
	var entries: Array[Dictionary] = []
	for raw_entry in raw_entries:
		var relative_path := str(raw_entry.get("relative_path", ""))
		var is_dir := bool(raw_entry.get("is_dir", false))
		var document_uri := str(raw_entry.get("document_uri", ""))
		entries.append({
			"name": str(raw_entry.get("name", "")),
			"path": "saf-tree://%s#%s" % [tree_uri, relative_path],
			"native_path": document_uri,
			"relative_path": relative_path,
			"is_dir": is_dir,
			"is_link": false
		})
	return _ok(str(path_info.get("raw", "")), {"entries": entries})

func delete_file(path_info: Dictionary) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(path_info.get("raw", "")))
	var scheme := str(path_info.get("scheme", ""))
	if scheme == SCHEME_SAF_FILE:
		return AndroidSafTreeScript.delete_uri(str(path_info.get("body", "")))
	if scheme == SCHEME_SAF_TREE:
		if AndroidSafTreeScript.path_is_directory(str(path_info.get("body", "")), str(path_info.get("relative_path", ""))):
			return _fail("Android SAF path is a directory.", str(path_info.get("raw", "")))
		return AndroidSafTreeScript.delete_path(
			str(path_info.get("body", "")),
			str(path_info.get("relative_path", ""))
		)
	return _fail("Unsupported Android SAF scheme.", str(path_info.get("raw", "")))

func delete_dir(path_info: Dictionary) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(path_info.get("raw", "")))
	if str(path_info.get("scheme", "")) != SCHEME_SAF_TREE:
		return _fail("Android SAF directory deletion requires a tree URI.", str(path_info.get("raw", "")))
	if not AndroidSafTreeScript.path_is_directory(str(path_info.get("body", "")), str(path_info.get("relative_path", ""))):
		return _fail("Android SAF path is not a directory.", str(path_info.get("raw", "")))
	return AndroidSafTreeScript.delete_path(
		str(path_info.get("body", "")),
		str(path_info.get("relative_path", ""))
	)

func copy_from_access_path(path_info: Dictionary, source_access_path: String, chunk_size: int = 1024 * 1024) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(path_info.get("raw", "")))
	return _copy_file_streaming(source_access_path, _to_godot_path(path_info), chunk_size, false)

func move_path(source_info: Dictionary, target_info: Dictionary, overwrite: bool = true) -> Dictionary:
	if not is_supported():
		return _fail("Android SAF is not available on this platform.", str(source_info.get("raw", "")))
	if str(source_info.get("scheme", "")) != SCHEME_SAF_TREE or str(target_info.get("scheme", "")) != SCHEME_SAF_TREE:
		return {
			"ok": false,
			"path": str(target_info.get("raw", "")),
			"error": "Android SAF native move requires tree paths.",
			"unsupported": true
		}
	var source_tree := str(source_info.get("body", ""))
	var target_tree := str(target_info.get("body", ""))
	if source_tree != target_tree:
		return {
			"ok": false,
			"path": str(target_info.get("raw", "")),
			"error": "Android SAF native move requires the same tree URI.",
			"unsupported": true
		}
	return AndroidSafTreeScript.move_path(
		source_tree,
		str(source_info.get("relative_path", "")),
		str(target_info.get("relative_path", "")),
		overwrite
	)

func globalize(path_info: Dictionary) -> String:
	return _to_godot_path(path_info)

func is_supported() -> bool:
	return AndroidSafTreeScript.is_supported()

func persist_uri_permission(virtual_path_or_uri: String, persist: bool = true) -> bool:
	var uri := _extract_uri(virtual_path_or_uri)
	if uri.is_empty():
		return false
	return AndroidSafTreeScript.persist_uri_permission(uri, persist)

func _extract_uri(value: String) -> String:
	var normalized := value.strip_edges()
	if normalized.begins_with("saf-file://"):
		return normalized.trim_prefix("saf-file://")
	if normalized.begins_with("saf-tree://"):
		var body := normalized.trim_prefix("saf-tree://")
		var fragment_index := body.find("#")
		return body.substr(0, fragment_index) if fragment_index >= 0 else body
	return normalized

func _to_godot_path(path_info: Dictionary) -> String:
	var scheme := str(path_info.get("scheme", ""))
	var body := str(path_info.get("body", "")).strip_edges()
	if scheme == SCHEME_SAF_FILE:
		return body
	if scheme == SCHEME_SAF_TREE:
		var relative_path := str(path_info.get("relative_path", "")).strip_edges().trim_prefix("/")
		if relative_path.is_empty():
			return body
		return "%s#%s" % [body, relative_path]
	return str(path_info.get("raw", ""))

func _write_saf_access_path(path: String, data: PackedByteArray) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("Failed to open Android SAF file for write. Error: %s" % FileAccess.get_open_error(), path)
	if not file.store_buffer(data):
		file = null
		return _fail("Failed to write the complete Android SAF file.", path)
	file.flush()
	file = null
	return _ok(path, {"bytes": data.size()})

func _temporary_tree_relative_path(relative_path: String) -> String:
	var parent := relative_path.get_base_dir()
	if parent == ".":
		parent = ""
	var temporary_name := ".%s.dx-tmp-%s-%s" % [relative_path.get_file(), Time.get_ticks_usec(), randi()]
	return parent.path_join(temporary_name) if not parent.is_empty() else temporary_name

func _cleanup_saf_tree_path(tree_uri: String, relative_path: String) -> String:
	if not AndroidSafTreeScript.tree_path_exists(tree_uri, relative_path):
		return ""
	var cleanup_result := AndroidSafTreeScript.delete_path(tree_uri, relative_path)
	return "" if bool(cleanup_result.get("ok", false)) else str(cleanup_result.get("error", "Failed to clean Android SAF temporary path."))

func _attach_saf_cleanup_error(result: Dictionary, cleanup_error: String) -> Dictionary:
	if not cleanup_error.is_empty():
		var existing_cleanup_error := str(result.get("cleanup_error", ""))
		result["cleanup_error"] = cleanup_error if existing_cleanup_error.is_empty() else "%s; %s" % [existing_cleanup_error, cleanup_error]
	return result
