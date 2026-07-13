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
	var godot_path := _to_godot_path(path_info)
	if godot_path.is_empty() or godot_path == str(path_info.get("body", "")):
		return _fail("Android SAF write path must target a file URI or tree URI with a relative file path.", str(path_info.get("raw", "")))
	var file := FileAccess.open(godot_path, FileAccess.WRITE)
	if file == null:
		return _fail("Failed to open Android SAF file for write. Error: %s" % FileAccess.get_open_error(), godot_path)
	file.store_buffer(data)
	return _ok(godot_path, {"bytes": data.size()})

func exists(path_info: Dictionary) -> bool:
	if not is_supported():
		return false
	return FileAccess.file_exists(_to_godot_path(path_info))

func make_dir_recursive(path_info: Dictionary) -> Dictionary:
	return _fail("Android SAF directory creation is not implemented yet.", str(path_info.get("raw", "")))

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
