class_name DX_FilePlatform
extends RefCounted

const PICK_KIND_FILE := "file"
const PICK_KIND_FILES := "files"
const PICK_KIND_DIRECTORY := "directory"
const PICK_KIND_SAVE_FILE := "save_file"
const DEBUG_FILE_PICKER_TAG := "DXFiles"

var manager
var dx: Node
var _pending_file_dialog_kind := ""
var _pending_file_dialog_callback := Callable()

func setup(file_manager, dx_root: Node = null) -> void:
	manager = file_manager
	dx = dx_root

func get_capabilities() -> Dictionary:
	return {
		"os": OS.get_name(),
		"native_file_picker": DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE),
		"picker_callback_deferred": true,
		"open_path": true,
		"reveal_path": true,
		"requires_native_bridge": false
	}

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

func pick_files(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	return _show_native_file_dialog(
		title,
		current_directory,
		"",
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILES,
		filters,
		callback,
		PICK_KIND_FILES
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

func pick_save_file(
	title: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable,
	current_directory: String = ""
) -> Dictionary:
	return _show_native_file_dialog(
		title,
		current_directory,
		default_filename,
		DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		filters,
		callback,
		PICK_KIND_SAVE_FILE
	)

func open_path(path: String) -> Dictionary:
	var target: String = manager.globalize(path).strip_edges()
	if target.is_empty():
		return _fail("Path is empty.", path)
	var err := OS.shell_open(manager.file_uri(path))
	return _ok(path, {"native_path": target}) if err == OK else _fail("Failed to open path. Error: %s" % err, target)

func reveal_path(path: String) -> Dictionary:
	var target: String = manager.globalize(path).strip_edges()
	if target.is_empty():
		return _fail("Path is empty.", path)
	if target.begins_with("content://"):
		var content_err := OS.shell_open(target)
		return _ok(path, {"native_path": target}) if content_err == OK else _fail("Failed to reveal path. Error: %s" % content_err, target)

	var open_target: String = target if DirAccess.dir_exists_absolute(target) else target.get_base_dir()
	if open_target.is_empty():
		open_target = target
	var err := OS.shell_open(manager.file_uri(open_target))
	return _ok(path, {"native_path": target}) if err == OK else _fail("Failed to reveal path. Error: %s" % err, target)

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
		_debug_file_picker("native file dialog callback invalid", {"kind": kind})
		return _fail("File picker callback is invalid.")
	if _pending_file_dialog_callback.is_valid():
		_debug_file_picker("native file dialog already pending", {"kind": _pending_file_dialog_kind})
		return _fail("A native file picker is already open.")
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_debug_file_picker("native file dialog feature unavailable", {
			"kind": kind,
			"os": OS.get_name()
		})
		return _fail("Native file picker is not available on this platform.")

	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	_pending_file_dialog_kind = kind
	_pending_file_dialog_callback = callback
	_debug_file_picker("native file dialog show", {
		"kind": kind,
		"title": title,
		"current_directory": current_directory,
		"dialog_directory": dialog_directory,
		"mode": mode
	})
	var error := DisplayServer.file_dialog_show(
		title,
		dialog_directory,
		filename,
		false,
		mode,
		filters,
		Callable(self, "_on_native_file_dialog_result"),
		0
	)
	if error != OK:
		_pending_file_dialog_kind = ""
		_pending_file_dialog_callback = Callable()
		_debug_file_picker("native file dialog show failed", {
			"kind": kind,
			"error": error
		})
		return _fail("Failed to open native file picker. Error: %s" % error)
	return _ok("", {"pending": true})

func _on_native_file_dialog_result(
	status: bool,
	selected_paths: PackedStringArray,
	selected_filter_index: int
) -> void:
	var kind := _pending_file_dialog_kind
	var callback := _pending_file_dialog_callback
	_pending_file_dialog_kind = ""
	_pending_file_dialog_callback = Callable()
	_debug_file_picker("native file dialog raw callback", {
		"status": status,
		"selected_paths": selected_paths,
		"selected_filter_index": selected_filter_index,
		"kind": kind,
		"has_callback": callback.is_valid()
	})

	var result := _build_file_dialog_result(status, selected_paths, kind)
	_debug_file_picker("native file dialog normalized result", result)
	if callback.is_valid():
		callback.call(result)

func _build_file_dialog_result(status: bool, selected_paths: PackedStringArray, kind: String) -> Dictionary:
	var result := {
		"ok": false,
		"cancelled": true,
		"path": "",
		"paths": PackedStringArray(),
		"native_path": "",
		"native_paths": PackedStringArray(),
		"uri": "",
		"uris": PackedStringArray(),
		"error": ""
	}
	if status and not selected_paths.is_empty():
		var virtual_paths := _selected_paths_to_virtual_paths(selected_paths, kind)
		for virtual_path_value in virtual_paths:
			if str(virtual_path_value).is_empty():
				result["cancelled"] = false
				result["error"] = "The selected system path could not be converted to a supported virtual path."
				return result
		var virtual_path := str(virtual_paths[0])
		for selected_virtual_path in virtual_paths:
			if selected_virtual_path.begins_with("saf-file://") or selected_virtual_path.begins_with("saf-tree://"):
				manager.persist_saf_uri_permission(selected_virtual_path, true)
		result["ok"] = true
		result["cancelled"] = false
		result["path"] = virtual_path
		result["paths"] = virtual_paths
		result["native_path"] = manager.globalize(virtual_path)
		result["native_paths"] = _selected_paths_to_native_paths(selected_paths, kind)
		result["uri"] = manager.file_uri(virtual_path)
		result["uris"] = _selected_paths_to_file_uris(selected_paths, kind)
	return result

func _finish_blocking_system_picker(
	output_text: String,
	kind: String,
	callback: Callable,
	log_label: String
) -> Dictionary:
	var selected_paths := PackedStringArray()
	for line in output_text.split("\n", false):
		var selected_path := str(line).strip_edges()
		if selected_path.is_empty():
			continue
		selected_paths.append(selected_path)
	_debug_file_picker("%s selected" % log_label, {
		"kind": kind,
		"selected_paths": selected_paths
	})
	var result := _build_file_dialog_result(not selected_paths.is_empty(), selected_paths, kind)
	_debug_file_picker("%s normalized result" % log_label, result)
	if callback.is_valid():
		callback.call_deferred(result)
	return _ok("", {"pending": false, "system_dialog": true})

func _selected_paths_to_virtual_paths(selected_paths: PackedStringArray, kind: String) -> PackedStringArray:
	var result := PackedStringArray()
	for selected_path in selected_paths:
		result.append(_selected_path_to_virtual_path(str(selected_path), kind))
	return result

func _selected_paths_to_native_paths(selected_paths: PackedStringArray, kind: String) -> PackedStringArray:
	var result := PackedStringArray()
	for selected_path in selected_paths:
		result.append(manager.globalize(_selected_path_to_virtual_path(str(selected_path), kind)))
	return result

func _selected_paths_to_file_uris(selected_paths: PackedStringArray, kind: String) -> PackedStringArray:
	var result := PackedStringArray()
	for selected_path in selected_paths:
		result.append(manager.file_uri(_selected_path_to_virtual_path(str(selected_path), kind)))
	return result

func _selected_path_to_virtual_path(path: String, kind: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if kind == PICK_KIND_DIRECTORY and normalized.begins_with("content://"):
		return manager.saf_tree_path(normalized)
	return manager.to_virtual_path(normalized)

func _process_output_to_text(output: Array) -> String:
	var output_text := ""
	for item in output:
		output_text += str(item)
	return output_text.strip_edges()

func _should_fallback_to_native_dialog(result: Dictionary) -> bool:
	return not bool(result.get("ok", false)) and not bool(result.get("cancelled", false))

func _parse_picker_filter(filter: String) -> Dictionary:
	var segments := filter.split(";", true)
	var pattern_text := str(segments[0]).strip_edges()
	var description := pattern_text
	if segments.size() > 1:
		description = str(segments[1]).strip_edges()
	var patterns := PackedStringArray()
	for pattern_value in pattern_text.split(",", false):
		var pattern := str(pattern_value).strip_edges()
		if pattern.is_empty():
			continue
		patterns.append(pattern)
	if description.is_empty():
		description = pattern_text if not pattern_text.is_empty() else "Files"
	return {
		"description": description,
		"patterns": patterns
	}

func _debug_file_picker(message: String, payload: Variant = null) -> void:
	var text := message if payload == null else "%s | %s" % [message, str(payload)]
	if dx != null and dx.logger != null:
		dx.logger.log(DEBUG_FILE_PICKER_TAG, text)
	else:
		print("[%s] %s" % [DEBUG_FILE_PICKER_TAG, text])

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
