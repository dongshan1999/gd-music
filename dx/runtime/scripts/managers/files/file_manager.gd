class_name DX_FileManager
extends RefCounted

const VirtualPathScript := preload("res://dx/runtime/scripts/managers/files/virtual_path.gd")
const AppDataProviderScript := preload("res://dx/runtime/scripts/managers/files/providers/app_data_file_provider.gd")
const LocalProviderScript := preload("res://dx/runtime/scripts/managers/files/providers/local_file_provider.gd")
const AndroidSafProviderScript := preload("res://dx/runtime/scripts/managers/files/providers/android_saf_file_provider.gd")
const BasePlatformScript := preload("res://dx/runtime/scripts/managers/files/platforms/file_platform.gd")
const MacOSPlatformScript := preload("res://dx/runtime/scripts/managers/files/platforms/macos_file_platform.gd")
const WindowsPlatformScript := preload("res://dx/runtime/scripts/managers/files/platforms/windows_file_platform.gd")
const LinuxPlatformScript := preload("res://dx/runtime/scripts/managers/files/platforms/linux_file_platform.gd")
const AndroidPlatformScript := preload("res://dx/runtime/scripts/managers/files/platforms/android_file_platform.gd")
const IOSPlatformScript := preload("res://dx/runtime/scripts/managers/files/platforms/ios_file_platform.gd")

var dx: Node:
	set(value):
		_dx = value
		for provider in _providers:
			provider.setup(_dx)
		if _platform != null:
			_platform.setup(self, _dx)
	get:
		return _dx

var _providers: Array = []
var _platform
var _dx: Node

func _init() -> void:
	_register_provider(AppDataProviderScript.new())
	_register_provider(LocalProviderScript.new())
	_register_provider(AndroidSafProviderScript.new())
	_platform = _create_platform()
	_platform.setup(self, _dx)

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
	if normalized.begins_with("file://"):
		return local_path(_file_uri_to_native_path(normalized))
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

func path_join(base_path: String, relative_path: String) -> String:
	var normalized_base := base_path.strip_edges().replace("\\", "/")
	var base_virtual_path := saf_tree_path(normalized_base) if normalized_base.begins_with("content://") and not normalized_base.contains("#") else to_virtual_path(base_path)
	var relative_result := VirtualPathScript.normalize_relative_path(relative_path)
	if not bool(relative_result.get("ok", false)):
		return ""
	var clean_relative := str(relative_result.get("path", ""))
	if clean_relative.is_empty():
		return base_virtual_path

	var info := _parse(base_virtual_path)
	if not bool(info.get("ok", false)):
		return ""

	match str(info.get("scheme", "")):
		VirtualPathScript.SCHEME_APP:
			return app_path(str(info.get("body", "")).path_join(clean_relative))
		VirtualPathScript.SCHEME_LOCAL:
			return local_path(str(info.get("body", "")).path_join(clean_relative))
		VirtualPathScript.SCHEME_SAF_TREE:
			var existing_relative := str(info.get("relative_path", "")).strip_edges().trim_prefix("/")
			var next_relative := clean_relative if existing_relative.is_empty() else existing_relative.path_join(clean_relative)
			return saf_tree_path(str(info.get("body", "")), next_relative)
	return ""

func path_parent(path: String) -> String:
	var info := _parse(to_virtual_path(path))
	if not bool(info.get("ok", false)):
		return ""
	match str(info.get("scheme", "")):
		VirtualPathScript.SCHEME_APP:
			if str(info.get("body", "")).is_empty():
				return ""
			var app_base := _parent_body(str(info.get("body", "")))
			return app_path(app_base)
		VirtualPathScript.SCHEME_LOCAL:
			var local_base := _parent_body(str(info.get("body", "")))
			return local_path(local_base) if not local_base.is_empty() else ""
		VirtualPathScript.SCHEME_SAF_TREE:
			var relative_base := _parent_body(str(info.get("relative_path", "")))
			return saf_tree_path(str(info.get("body", "")), relative_base) if not relative_base.is_empty() else saf_tree_path(str(info.get("body", "")))
	return ""

func path_name(path: String) -> String:
	var info := _parse(to_virtual_path(path))
	if not bool(info.get("ok", false)):
		return path.strip_edges().replace("\\", "/").get_file()
	match str(info.get("scheme", "")):
		VirtualPathScript.SCHEME_APP, VirtualPathScript.SCHEME_LOCAL:
			return str(info.get("body", "")).get_file()
		VirtualPathScript.SCHEME_SAF_TREE:
			var relative_path := str(info.get("relative_path", ""))
			if not relative_path.is_empty():
				return relative_path.get_file()
			return str(info.get("body", "")).uri_decode().get_file()
		VirtualPathScript.SCHEME_SAF_FILE:
			return str(info.get("body", "")).uri_decode().get_file()
	return str(info.get("raw", path)).get_file()

func read_bytes(path: String) -> Dictionary:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return _normalize_provider_result(path, resolved["provider"].read_bytes(resolved["path_info"]), resolved)

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
	return _normalize_provider_result(path, resolved["provider"].write_bytes(resolved["path_info"], data), resolved)

func write_text(path: String, text: String) -> Dictionary:
	return write_bytes(path, text.to_utf8_buffer())

func exists(path: String) -> bool:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return false
	return resolved["provider"].exists(resolved["path_info"])

func is_dir(path: String) -> bool:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return false
	return bool(resolved["provider"].is_dir(resolved["path_info"]))

func is_link(path: String) -> bool:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return false
	return bool(resolved["provider"].is_link(resolved["path_info"]))

func is_file(path: String) -> bool:
	var info := get_info(path)
	return bool(info.get("ok", false)) and bool(info.get("is_file", false))

func get_info(path: String) -> Dictionary:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return _normalize_provider_result(path, resolved["provider"].get_info(resolved["path_info"]), resolved)

func make_dir_recursive(path: String) -> Dictionary:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return _normalize_provider_result(path, resolved["provider"].make_dir_recursive(resolved["path_info"]), resolved)

func list_dir(path: String) -> Dictionary:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return _normalize_provider_result(path, resolved["provider"].list_dir(resolved["path_info"]), resolved)

func delete_file(path: String) -> Dictionary:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return _normalize_provider_result(path, resolved["provider"].delete_file(resolved["path_info"]), resolved)

func delete_dir(path: String) -> Dictionary:
	if _is_protected_root(path):
		return _fail("Deleting a protected filesystem root is not allowed.", path)
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return _fail(str(resolved.get("error", "")), path)
	return _normalize_provider_result(path, resolved["provider"].delete_dir(resolved["path_info"]), resolved)

func delete_dir_recursive(path: String) -> Dictionary:
	if _is_protected_root(path):
		return _fail("Deleting a protected filesystem root is not allowed.", path)
	return _delete_dir_recursive(path, {})

func _delete_dir_recursive(path: String, visited: Dictionary) -> Dictionary:
	var info := get_info(path)
	if not bool(info.get("ok", false)):
		return info
	if bool(info.get("is_link", false)):
		return delete_file(path)
	if not bool(info.get("is_dir", false)):
		return _fail("Directory does not exist.", path)
	var canonical_path := _canonical_path_key(path)
	if canonical_path.is_empty():
		return _fail("Cannot resolve canonical directory path.", path)
	if visited.has(canonical_path):
		return _fail("Directory recursion cycle detected.", path)
	visited[canonical_path] = true

	var list_result := list_dir(path)
	if not bool(list_result.get("ok", false)):
		return list_result
	for entry_value in list_result.get("entries", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var entry_path := str(entry.get("path", ""))
		if entry_path.is_empty():
			entry_path = str(entry.get("native_path", ""))
		if entry_path.is_empty():
			continue
		var delete_result := _delete_dir_recursive(entry_path, visited) if bool(entry.get("is_dir", false)) and not bool(entry.get("is_link", false)) else delete_file(entry_path)
		if not bool(delete_result.get("ok", false)):
			return delete_result
	return delete_dir(path)

func delete(path: String) -> Dictionary:
	var info := get_info(path)
	if not bool(info.get("ok", false)):
		return info
	return delete_dir_recursive(path) if bool(info.get("is_dir", false)) and not bool(info.get("is_link", false)) else delete_file(path)

func copy_file(source_path: String, target_path: String, overwrite: bool = true) -> Dictionary:
	if _same_path(source_path, target_path):
		return _ok(target_path, {"source_path": source_path, "target_path": target_path, "bytes": 0})
	var source_info := get_info(source_path)
	if not bool(source_info.get("ok", false)):
		return source_info
	if bool(source_info.get("is_link", false)):
		return _fail("Copying symbolic links is not supported.", source_path)
	if bool(source_info.get("is_dir", false)):
		return _fail("Source is a directory. Use copy_dir().", source_path)
	if not bool(source_info.get("is_file", false)):
		return _fail("Source file does not exist.", source_path)
	if exists(target_path):
		var target_info := get_info(target_path)
		if bool(target_info.get("is_dir", false)) or bool(target_info.get("is_link", false)):
			return _fail("Target is an existing directory.", target_path)
		if not overwrite:
			return _fail("Target file already exists.", target_path)

	var source_resolved := _resolve(source_path)
	var target_resolved := _resolve(target_path)
	if not bool(source_resolved.get("ok", false)):
		return source_resolved
	if not bool(target_resolved.get("ok", false)):
		return target_resolved
	var source_access_path := str(source_resolved["provider"].globalize(source_resolved["path_info"]))
	var staged_path := _temporary_sibling_virtual_path(target_path)
	if staged_path.is_empty():
		var direct_result: Dictionary = target_resolved["provider"].copy_from_access_path(target_resolved["path_info"], source_access_path)
		if not bool(direct_result.get("ok", false)):
			return _normalize_provider_result(target_path, direct_result, target_resolved)
		return _ok(target_path, {
			"source_path": source_path,
			"target_path": target_path,
			"bytes": int(direct_result.get("bytes", 0)),
			"atomic": false
		})

	var staged_resolved := _resolve(staged_path)
	if not bool(staged_resolved.get("ok", false)):
		return staged_resolved
	var stage_result: Dictionary = staged_resolved["provider"].copy_from_access_path(staged_resolved["path_info"], source_access_path)
	if not bool(stage_result.get("ok", false)):
		var stage_failure := _normalize_provider_result(staged_path, stage_result, staged_resolved)
		return _cleanup_virtual_temporary_path(staged_path, stage_failure)
	var replace_result: Dictionary = staged_resolved["provider"].move_path(staged_resolved["path_info"], target_resolved["path_info"], overwrite)
	if not bool(replace_result.get("ok", false)):
		var replace_failure := _normalize_provider_result(target_path, replace_result, target_resolved)
		return _cleanup_virtual_temporary_path(staged_path, replace_failure)
	return _ok(target_path, {
		"source_path": source_path,
		"target_path": target_path,
		"bytes": int(stage_result.get("bytes", 0)),
		"atomic": true,
		"cleanup_error": str(replace_result.get("cleanup_error", "")),
		"backup_path": str(replace_result.get("backup_path", ""))
	})

func copy_dir(source_dir: String, target_dir: String, recursive: bool = true, overwrite: bool = true) -> Dictionary:
	var target_existed := exists(target_dir)
	var result := _copy_dir(source_dir, target_dir, recursive, overwrite, {})
	if not bool(result.get("ok", false)) and not target_existed and exists(target_dir):
		var cleanup_result := delete(target_dir)
		if not bool(cleanup_result.get("ok", false)):
			result["cleanup_error"] = str(cleanup_result.get("error", ""))
	return result

func _copy_dir(source_dir: String, target_dir: String, recursive: bool, overwrite: bool, visited: Dictionary) -> Dictionary:
	if _same_path(source_dir, target_dir):
		return _ok(target_dir, {"source_path": source_dir, "target_path": target_dir, "files": 0, "directories": 0})
	if _is_path_inside(source_dir, target_dir):
		return _fail("Cannot copy a directory into itself.", target_dir)
	var source_info := get_info(source_dir)
	if not bool(source_info.get("ok", false)):
		return source_info
	if bool(source_info.get("is_link", false)):
		return _fail("Copying symbolic link directories is not supported.", source_dir)
	if not bool(source_info.get("is_dir", false)):
		return _fail("Source directory does not exist.", source_dir)

	if exists(target_dir):
		var target_info := get_info(target_dir)
		if not bool(target_info.get("is_dir", false)) or bool(target_info.get("is_link", false)):
			return _fail("Target exists and is not a replaceable directory.", target_dir)
		if not overwrite:
			return _fail("Target directory already exists.", target_dir)
		var staged_target := _temporary_sibling_virtual_path(target_dir)
		if staged_target.is_empty():
			return _fail("Cannot create a staging directory next to the target.", target_dir)
		var staged_result := _copy_dir(source_dir, staged_target, recursive, false, visited)
		if not bool(staged_result.get("ok", false)):
			return _cleanup_virtual_temporary_path(staged_target, staged_result)
		var replace_result := _replace_staged_path(staged_target, target_dir, true)
		if not bool(replace_result.get("ok", false)):
			return _cleanup_virtual_temporary_path(staged_target, replace_result)
		return _ok(target_dir, {
			"source_path": source_dir,
			"target_path": target_dir,
			"files": int(staged_result.get("files", 0)),
			"directories": int(staged_result.get("directories", 0)),
			"atomic": true,
			"cleanup_error": str(replace_result.get("cleanup_error", "")),
			"backup_path": str(replace_result.get("backup_path", ""))
		})

	var canonical_source := _canonical_path_key(source_dir)
	if canonical_source.is_empty():
		return _fail("Cannot resolve canonical source directory.", source_dir)
	if visited.has(canonical_source):
		return _fail("Directory recursion cycle detected.", source_dir)
	visited[canonical_source] = true

	var make_result := make_dir_recursive(target_dir)
	if not bool(make_result.get("ok", false)):
		return make_result

	var list_result := list_dir(source_dir)
	if not bool(list_result.get("ok", false)):
		return list_result

	var copied_files := 0
	var copied_dirs := 0
	for entry_value in list_result.get("entries", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var entry_name := str(entry.get("name", ""))
		var entry_path := str(entry.get("path", ""))
		if entry_name.is_empty() or entry_path.is_empty():
			continue
		var child_target := path_join(target_dir, entry_name)
		if child_target.is_empty():
			return _fail("Cannot construct target child path.", target_dir)
		if bool(entry.get("is_link", false)):
			return _fail("Copying symbolic links is not supported.", entry_path)
		if bool(entry.get("is_dir", false)):
			if not recursive:
				continue
			var child_dir_result := _copy_dir(entry_path, child_target, recursive, false, visited)
			if not bool(child_dir_result.get("ok", false)):
				return child_dir_result
			copied_files += int(child_dir_result.get("files", 0))
			copied_dirs += int(child_dir_result.get("directories", 0)) + 1
			continue
		var child_file_result := copy_file(entry_path, child_target, false)
		if not bool(child_file_result.get("ok", false)):
			return child_file_result
		copied_files += 1

	return _ok(target_dir, {
		"source_path": source_dir,
		"target_path": target_dir,
		"files": copied_files,
		"directories": copied_dirs
	})

func copy(source_path: String, target_path: String, overwrite: bool = true) -> Dictionary:
	return copy_dir(source_path, target_path, true, overwrite) if is_dir(source_path) else copy_file(source_path, target_path, overwrite)

func paste(source_path: String, target_dir: String, new_name: String = "", overwrite: bool = true) -> Dictionary:
	var target_name := new_name.strip_edges()
	if target_name.is_empty():
		target_name = path_name(source_path)
	if not _is_valid_entry_name(target_name):
		return _fail("Cannot resolve source file name.", source_path)
	var target_path := path_join(target_dir, target_name)
	if target_path.is_empty():
		return _fail("Cannot construct paste target path.", target_dir)
	return copy(source_path, target_path, overwrite)

func move(source_path: String, target_path: String, overwrite: bool = true) -> Dictionary:
	if _is_protected_root(source_path):
		return _fail("Moving a protected filesystem root is not allowed.", source_path)
	if _is_protected_root(target_path):
		return _fail("Replacing a protected filesystem root is not allowed.", target_path)
	if _same_path(source_path, target_path):
		return _ok(target_path, {"source_path": source_path, "target_path": target_path})
	var source_info := get_info(source_path)
	if not bool(source_info.get("ok", false)):
		return source_info
	if exists(target_path):
		var target_info := get_info(target_path)
		if bool(target_info.get("is_link", false)):
			return _fail("Replacing a symbolic link target is not allowed.", target_path)
		if bool(source_info.get("is_dir", false)) != bool(target_info.get("is_dir", false)):
			return _fail("Source and target path types do not match.", target_path)
	if bool(source_info.get("is_dir", false)) and _is_path_inside(source_path, target_path):
		return _fail("Cannot move a directory into itself.", target_path)
	var source_resolved := _resolve(source_path)
	var target_resolved := _resolve(target_path)
	if not bool(source_resolved.get("ok", false)):
		return source_resolved
	if not bool(target_resolved.get("ok", false)):
		return target_resolved
	if source_resolved["provider"] == target_resolved["provider"]:
		var native_result: Dictionary = source_resolved["provider"].move_path(source_resolved["path_info"], target_resolved["path_info"], overwrite)
		if bool(native_result.get("ok", false)):
			return _ok(target_path, {
				"source_path": source_path,
				"target_path": target_path,
				"native": true,
				"cleanup_error": str(native_result.get("cleanup_error", "")),
				"backup_path": str(native_result.get("backup_path", ""))
			})
		if not bool(native_result.get("unsupported", false)):
			return _normalize_provider_result(target_path, native_result, target_resolved)

	var copy_result := copy(source_path, target_path, overwrite)
	if not bool(copy_result.get("ok", false)):
		return copy_result

	var delete_result := delete_dir_recursive(source_path) if bool(source_info.get("is_dir", false)) and not bool(source_info.get("is_link", false)) else delete_file(source_path)
	if not bool(delete_result.get("ok", false)):
		delete_result["source_path"] = source_path
		delete_result["target_path"] = target_path
		delete_result["copied"] = true
		delete_result["partial"] = true
		delete_result["error"] = "Move copied the target but failed to delete the source: %s" % str(delete_result.get("error", "Unknown delete error."))
		return delete_result
	return _ok(target_path, {"source_path": source_path, "target_path": target_path, "native": false})

func rename(path: String, new_name: String, overwrite: bool = true) -> Dictionary:
	var clean_name := new_name.strip_edges()
	if not _is_valid_entry_name(clean_name):
		return _fail("New name is empty.", path)
	var parent := path_parent(path)
	if parent.is_empty():
		return _fail("Cannot resolve parent directory.", path)
	return move(path, path_join(parent, clean_name), overwrite)

func globalize(path: String) -> String:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return ""
	return resolved["provider"].globalize(resolved["path_info"])

func native_path(path: String) -> String:
	return globalize(path)

func file_uri(path: String) -> String:
	var native := globalize(path).strip_edges().replace("\\", "/")
	if native.is_empty():
		return ""
	if native.begins_with("content://"):
		return native
	return _native_path_to_file_uri(native)

func pick_file(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	return _platform.pick_file(title, filters, callback, current_directory)

func pick_files(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	return _platform.pick_files(title, filters, callback, current_directory)

func pick_directory(title: String, callback: Callable, current_directory: String = "") -> Dictionary:
	return _platform.pick_directory(title, callback, current_directory)

func pick_save_file(
	title: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable,
	current_directory: String = ""
) -> Dictionary:
	return _platform.pick_save_file(title, default_filename, filters, callback, current_directory)

func save_bytes_with_picker(
	title: String,
	default_filename: String,
	data: PackedByteArray,
	callback: Callable,
	current_directory: String = "",
	filters: PackedStringArray = PackedStringArray()
) -> Dictionary:
	return pick_save_file(
		title,
		default_filename,
		filters,
		Callable(self, "_on_save_bytes_path_picked").bind(data, callback),
		current_directory
	)

func save_text_with_picker(
	title: String,
	default_filename: String,
	text: String,
	callback: Callable,
	current_directory: String = "",
	filters: PackedStringArray = PackedStringArray()
) -> Dictionary:
	return save_bytes_with_picker(
		title,
		default_filename,
		text.to_utf8_buffer(),
		callback,
		current_directory,
		filters
	)

func open_path(path: String) -> Dictionary:
	return _platform.open_path(path)

func reveal_path(path: String) -> Dictionary:
	return _platform.reveal_path(path)

func dialog_native_directory(path: String) -> String:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return ProjectSettings.globalize_path("user://")
	var virtual_path := to_virtual_path(normalized)
	if virtual_path.begins_with("local://") or virtual_path.begins_with("app://"):
		return globalize(virtual_path)
	return normalized

func persist_saf_uri_permission(path_or_uri: String, persist: bool = true) -> bool:
	for provider in _providers:
		if provider.has_method("persist_uri_permission"):
			return bool(provider.call("persist_uri_permission", path_or_uri, persist))
	return false

func platform_capabilities() -> Dictionary:
	return _platform.get_capabilities() if _platform != null else {}

func _create_platform():
	match OS.get_name():
		"macOS":
			return MacOSPlatformScript.new()
		"Windows":
			return WindowsPlatformScript.new()
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return LinuxPlatformScript.new()
		"Android":
			return AndroidPlatformScript.new()
		"iOS":
			return IOSPlatformScript.new()
	return BasePlatformScript.new()

func _register_provider(provider) -> void:
	if provider == null:
		return
	if dx != null:
		provider.setup(dx)
	_providers.append(provider)

func _on_save_bytes_path_picked(result: Dictionary, data: PackedByteArray, callback: Callable) -> void:
	var save_result := result.duplicate(true)
	if bool(result.get("ok", false)):
		save_result = write_bytes(str(result.get("path", "")), data)
		save_result["cancelled"] = false
	if callback.is_valid():
		callback.call(save_result)

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

func _file_uri_to_native_path(uri: String) -> String:
	var path := uri.strip_edges().replace("\\", "/").trim_prefix("file://").uri_decode()
	if path.begins_with("localhost/"):
		path = path.substr("localhost".length())
	if path.length() >= 3 and path.begins_with("/") and path.substr(2, 1) == ":":
		path = path.substr(1)
	return path

func _native_path_to_file_uri(native_path: String) -> String:
	var normalized := native_path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return ""
	if _looks_like_windows_absolute_path(normalized):
		var drive_prefix := normalized.substr(0, 2)
		var rest := normalized.substr(2)
		return "file:///%s%s" % [drive_prefix, _encode_file_uri_path(rest)]
	if normalized.begins_with("/"):
		return "file://%s" % _encode_file_uri_path(normalized)
	return normalized

func _encode_file_uri_path(path: String) -> String:
	var encoded_parts := PackedStringArray()
	for part in path.split("/", true):
		encoded_parts.append(str(part).uri_encode())
	return "/".join(encoded_parts)

func _parent_body(body: String) -> String:
	var normalized := body.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return ""
	var base := normalized.get_base_dir()
	if base == "." or base == normalized:
		return ""
	return base

func _is_path_inside(parent_path: String, child_path: String) -> bool:
	var parent := _canonical_path_key(parent_path)
	var child := _canonical_path_key(child_path)
	if parent.is_empty() or child.is_empty() or parent == child:
		return false
	if parent.begins_with("saf-tree:") and parent.ends_with("#"):
		return child.begins_with(parent)
	return child.begins_with("%s/" % parent)

func _same_path(left_path: String, right_path: String) -> bool:
	var left := _canonical_path_key(left_path)
	var right := _canonical_path_key(right_path)
	return not left.is_empty() and left == right

func _canonical_path_key(path: String) -> String:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return ""
	var path_info: Dictionary = resolved["path_info"]
	var scheme := str(path_info.get("scheme", ""))
	if scheme == VirtualPathScript.SCHEME_APP or scheme == VirtualPathScript.SCHEME_LOCAL:
		var native_path := str(resolved["provider"].globalize(path_info)).replace("\\", "/").simplify_path().trim_suffix("/")
		if native_path.is_empty():
			native_path = "/"
		if OS.get_name() == "Windows" or OS.get_name() == "macOS":
			native_path = native_path.to_lower()
		return "native:%s" % native_path
	if scheme == VirtualPathScript.SCHEME_SAF_TREE:
		var tree_uri := str(path_info.get("body", "")).strip_edges()
		var relative_path := str(path_info.get("relative_path", "")).strip_edges().trim_suffix("/")
		return "saf-tree:%s#%s" % [tree_uri, relative_path]
	if scheme == VirtualPathScript.SCHEME_SAF_FILE:
		return "saf-file:%s" % str(path_info.get("body", "")).strip_edges()
	return normalize_virtual_path(str(path_info.get("raw", path)))

func _is_protected_root(path: String) -> bool:
	var resolved := _resolve(path)
	if not bool(resolved.get("ok", false)):
		return false
	var path_info: Dictionary = resolved["path_info"]
	var scheme := str(path_info.get("scheme", ""))
	if scheme == VirtualPathScript.SCHEME_APP:
		return str(path_info.get("body", "")).is_empty()
	if scheme == VirtualPathScript.SCHEME_SAF_TREE:
		return str(path_info.get("relative_path", "")).is_empty()
	if scheme == VirtualPathScript.SCHEME_LOCAL:
		return _is_native_filesystem_root(str(path_info.get("body", "")))
	return false

func _is_native_filesystem_root(path: String) -> bool:
	var normalized := path.strip_edges().replace("\\", "/").simplify_path()
	if normalized == "/":
		return true
	if normalized.length() == 2 and normalized.substr(1, 1) == ":":
		return true
	if normalized.length() == 3 and normalized.substr(1, 2) == ":/":
		return true
	if normalized.begins_with("//"):
		return normalized.split("/", false).size() <= 2
	return normalized.get_base_dir() == normalized

func _temporary_sibling_virtual_path(path: String) -> String:
	var parent := path_parent(path)
	var file_name := path_name(path)
	if parent.is_empty() or file_name.is_empty():
		return ""
	return path_join(parent, ".%s.dx-tmp-%s-%s" % [file_name, Time.get_ticks_usec(), randi()])

func _replace_staged_path(staged_path: String, target_path: String, overwrite: bool) -> Dictionary:
	var staged_resolved := _resolve(staged_path)
	var target_resolved := _resolve(target_path)
	if not bool(staged_resolved.get("ok", false)):
		return staged_resolved
	if not bool(target_resolved.get("ok", false)):
		return target_resolved
	if staged_resolved["provider"] != target_resolved["provider"]:
		return _fail("Staged replacement requires the same target provider.", target_path)
	var result: Dictionary = staged_resolved["provider"].move_path(staged_resolved["path_info"], target_resolved["path_info"], overwrite)
	return _normalize_provider_result(target_path, result, target_resolved)

func _cleanup_virtual_temporary_path(path: String, result: Dictionary) -> Dictionary:
	if path.is_empty() or not exists(path):
		return result
	var cleanup_result := delete(path)
	if not bool(cleanup_result.get("ok", false)):
		var cleanup_error := str(cleanup_result.get("error", "Failed to clean temporary path."))
		var existing_cleanup_error := str(result.get("cleanup_error", ""))
		result["cleanup_error"] = cleanup_error if existing_cleanup_error.is_empty() else "%s; %s" % [existing_cleanup_error, cleanup_error]
		result["temporary_path"] = path
	return result

func _is_valid_entry_name(value: String) -> bool:
	var name := value.strip_edges()
	return not name.is_empty() and name != "." and name != ".." and not name.contains("/") and not name.contains("\\")

func _normalize_provider_result(requested_path: String, result: Dictionary, resolved: Dictionary) -> Dictionary:
	var normalized_path := to_virtual_path(requested_path)
	if not normalized_path.is_empty():
		result["path"] = normalized_path
	if not result.has("native_path") and bool(resolved.get("ok", false)):
		result["native_path"] = str(resolved["provider"].globalize(resolved["path_info"]))
	return result

func _looks_like_windows_absolute_path(path: String) -> bool:
	return path.length() >= 3 and path.substr(1, 2) == ":/"

func _fail(message: String, path: String = "") -> Dictionary:
	return {
		"ok": false,
		"path": path,
		"error": message
	}

func _ok(path: String, extra: Dictionary = {}) -> Dictionary:
	var result_path := to_virtual_path(path) if not path.is_empty() else ""
	var result := {
		"ok": true,
		"path": result_path,
		"error": ""
	}
	for key in extra.keys():
		result[key] = extra[key]
	return result
