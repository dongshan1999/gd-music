class_name DX_FileManager
extends RefCounted

const VirtualPathScript := preload("res://dx/runtime/scripts/managers/files/virtual_path.gd")
const FileProviderScript := preload("res://dx/runtime/scripts/managers/files/providers/file_provider.gd")
const AppDataProviderScript := preload("res://dx/runtime/scripts/managers/files/providers/app_data_file_provider.gd")
const LocalProviderScript := preload("res://dx/runtime/scripts/managers/files/providers/local_file_provider.gd")
const AndroidSafProviderScript := preload("res://dx/runtime/scripts/managers/files/providers/android_saf_file_provider.gd")

const PICK_KIND_FILE := "file"
const PICK_KIND_DIRECTORY := "directory"

var dx: Node:
	set(value):
		_dx = value
		for provider in _providers:
			provider.setup(_dx)
	get:
		return _dx

var _providers: Array = []
var _dx: Node

func _init() -> void:
	_register_provider(AppDataProviderScript.new())
	_register_provider(LocalProviderScript.new())
	_register_provider(AndroidSafProviderScript.new())

func app_path(relative_path: String) -> String:
	return VirtualPathScript.normalize_app_path(relative_path)

func local_path(native_path: String) -> String:
	return VirtualPathScript.normalize_local_path(native_path)

func saf_file_path(uri: String) -> String:
	return VirtualPathScript.normalize_saf_file_path(uri)

func saf_tree_path(uri: String, relative_path: String = "") -> String:
	return VirtualPathScript.normalize_saf_tree_path(uri, relative_path)

func is_virtual_path(path: String) -> bool:
	return VirtualPathScript.is_virtual_path(path)

func to_virtual_path(path: String, default_scheme: String = "") -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return ""
	if normalized.begins_with("content://"):
		var fragment_index := normalized.find("#")
		if fragment_index >= 0:
			return saf_tree_path(normalized.substr(0, fragment_index), normalized.substr(fragment_index + 1))
		return saf_file_path(normalized)
	if is_virtual_path(normalized):
		return normalize_virtual_path(normalized)
	if normalized.begins_with("user://"):
		return app_path(normalized.trim_prefix("user://"))
	if OS.get_name() != "Android":
		if normalized.begins_with("res://"):
			return local_path(ProjectSettings.globalize_path(normalized))
		if normalized.is_absolute_path() or _looks_like_windows_absolute_path(normalized):
			return local_path(normalized)
	if default_scheme == VirtualPathScript.SCHEME_APP:
		return app_path(normalized)
	return normalized

func path_join(base_path: String, relative_path: String) -> String:
	var normalized_base := base_path.strip_edges().replace("\\", "/")
	var base_virtual_path := saf_tree_path(normalized_base) if normalized_base.begins_with("content://") and not normalized_base.contains("#") else to_virtual_path(base_path)
	var clean_relative := relative_path.strip_edges().replace("\\", "/").trim_prefix("/")
	if clean_relative.is_empty():
		return base_virtual_path

	var info := _parse(base_virtual_path)
	if not bool(info.get("ok", false)):
		return base_path.path_join(clean_relative)

	match str(info.get("scheme", "")):
		VirtualPathScript.SCHEME_APP:
			return app_path(str(info.get("body", "")).path_join(clean_relative))
		VirtualPathScript.SCHEME_LOCAL:
			return local_path(str(info.get("body", "")).path_join(clean_relative))
		VirtualPathScript.SCHEME_SAF_TREE:
			var existing_relative := str(info.get("relative_path", "")).strip_edges().trim_prefix("/")
			var next_relative := clean_relative if existing_relative.is_empty() else existing_relative.path_join(clean_relative)
			return saf_tree_path(str(info.get("body", "")), next_relative)
	return base_virtual_path.path_join(clean_relative)

func normalize_virtual_path(path: String) -> String:
	var info := _parse(path)
	if not bool(info.get("ok", false)):
		return path.strip_edges()
	match str(info.get("scheme", "")):
		VirtualPathScript.SCHEME_APP:
			return app_path(str(info.get("body", "")))
		VirtualPathScript.SCHEME_LOCAL:
			return local_path(str(info.get("body", "")))
		VirtualPathScript.SCHEME_SAF_FILE:
			return saf_file_path(str(info.get("body", "")))
		VirtualPathScript.SCHEME_SAF_TREE:
			return saf_tree_path(str(info.get("body", "")), str(info.get("relative_path", "")))
	return str(info.get("raw", path)).strip_edges()

func read_bytes(path: String) -> Dictionary:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return resolved["provider"].read_bytes(resolved["path_info"])

func read_text(path: String) -> Dictionary:
	var result := read_bytes(path)
	if not bool(result.get("ok", false)):
		return result
	var data: PackedByteArray = result.get("data", PackedByteArray())
	result["text"] = data.get_string_from_utf8()
	return result

func write_bytes(path: String, data: PackedByteArray) -> Dictionary:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return resolved["provider"].write_bytes(resolved["path_info"], data)

func write_text(path: String, text: String) -> Dictionary:
	return write_bytes(path, text.to_utf8_buffer())

func exists(path: String) -> bool:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return false
	return resolved["provider"].exists(resolved["path_info"])

func make_dir_recursive(path: String) -> Dictionary:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return resolved["provider"].make_dir_recursive(resolved["path_info"])

func globalize(path: String) -> String:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return path.strip_edges()
	return resolved["provider"].globalize(resolved["path_info"])

func persist_saf_uri_permission(path_or_uri: String, persist: bool = true) -> bool:
	for provider in _providers:
		if provider.has_method("persist_uri_permission"):
			return bool(provider.call("persist_uri_permission", path_or_uri, persist))
	return false

func pick_file(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	return _show_native_file_dialog(
		title,
		current_directory,
		"",
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		filters,
		callback,
		PICK_KIND_FILE
	)

func pick_directory(title: String, callback: Callable, current_directory: String = "") -> Dictionary:
	return _show_native_file_dialog(
		title,
		current_directory,
		"",
		DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
		PackedStringArray(),
		callback,
		PICK_KIND_DIRECTORY
	)

func _register_provider(provider) -> void:
	if provider == null:
		return
	if dx != null:
		provider.setup(dx)
	_providers.append(provider)

func _show_native_file_dialog(
	title: String,
	current_directory: String,
	filename: String,
	mode: int,
	filters: PackedStringArray,
	callback: Callable,
	kind: String
) -> Dictionary:
	if not callback.is_valid():
		return _fail("File picker callback is invalid.")
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		return _fail("Native file picker is not available on this platform.")

	var dialog_directory := _dialog_native_directory(current_directory)
	var error := DisplayServer.file_dialog_show(
		title,
		dialog_directory,
		filename,
		false,
		mode,
		filters,
		Callable(self, "_on_native_file_dialog_result").bind(kind, callback),
		0
	)
	if error != OK:
		return _fail("Failed to open native file picker. Error: %s" % error)
	return _ok("", {"pending": true})

func _on_native_file_dialog_result(arg1 = null, arg2 = null, arg3 = null, arg4 = null, arg5 = null) -> void:
	var status := false
	var selected_paths := PackedStringArray()
	var kind := ""
	var callback := Callable()
	if arg1 is bool:
		status = bool(arg1)
	if arg2 is PackedStringArray:
		selected_paths = arg2
	elif arg2 is Array:
		for item in arg2:
			selected_paths.append(str(item))
	if arg4 is String:
		kind = str(arg4)
	if arg5 is Callable:
		callback = arg5
	elif arg4 is Callable:
		callback = arg4
	if kind.is_empty() and arg3 is String:
		kind = str(arg3)

	var result := {
		"ok": false,
		"cancelled": true,
		"path": "",
		"paths": PackedStringArray(),
		"error": ""
	}
	if status and not selected_paths.is_empty():
		var selected_path := str(selected_paths[0]).strip_edges().replace("\\", "/")
		var virtual_path := _selected_path_to_virtual_path(selected_path, kind)
		if virtual_path.begins_with("saf-file://") or virtual_path.begins_with("saf-tree://"):
			persist_saf_uri_permission(virtual_path, true)
		result["ok"] = true
		result["cancelled"] = false
		result["path"] = virtual_path
		result["paths"] = _selected_paths_to_virtual_paths(selected_paths, kind)
	if callback.is_valid():
		callback.call(result)

func _selected_paths_to_virtual_paths(selected_paths: PackedStringArray, kind: String) -> PackedStringArray:
	var result := PackedStringArray()
	for selected_path in selected_paths:
		result.append(_selected_path_to_virtual_path(str(selected_path), kind))
	return result

func _selected_path_to_virtual_path(path: String, kind: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if kind == PICK_KIND_DIRECTORY and normalized.begins_with("content://"):
		return saf_tree_path(normalized)
	return to_virtual_path(normalized)

func _dialog_native_directory(path: String) -> String:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return ProjectSettings.globalize_path("user://")
	var virtual_path := to_virtual_path(normalized)
	if virtual_path.begins_with("local://") or virtual_path.begins_with("app://"):
		return globalize(virtual_path)
	return normalized

func _resolve(path: String) -> Dictionary:
	var path_info := _parse(to_virtual_path(path))
	if not bool(path_info.get("ok", false)):
		return path_info
	for provider in _providers:
		if provider.supports(path_info):
			return {
				"ok": true,
				"path_info": path_info,
				"provider": provider
			}
	return _fail("Unsupported virtual path scheme: %s" % str(path_info.get("scheme", "")), path)

func _parse(path: String) -> Dictionary:
	return VirtualPathScript.parse(path)

func _looks_like_windows_absolute_path(path: String) -> bool:
	return path.length() >= 3 and path.substr(1, 2) == ":/"

func _fail(message: String, path: String = "") -> Dictionary:
	return {
		"ok": false,
		"path": path,
		"error": message
	}

func _ok(path: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"path": path,
		"error": ""
	}
	for key in extra.keys():
		result[key] = extra[key]
	return result
