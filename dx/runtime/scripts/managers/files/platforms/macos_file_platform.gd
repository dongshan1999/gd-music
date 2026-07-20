class_name DX_MacOSFilePlatform
extends "res://dx/runtime/scripts/managers/files/platforms/file_platform.gd"

func pick_file(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_macos_system_file_picker(title, current_directory, filters, callback, PICK_KIND_FILE, false)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("macOS file picker falling back to native dialog", result)
		return super.pick_file(title, filters, callback, current_directory)
	return result

func pick_files(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_macos_system_file_picker(title, current_directory, filters, callback, PICK_KIND_FILES, true)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("macOS multi-file picker falling back to native dialog", result)
		return super.pick_files(title, filters, callback, current_directory)
	return result

func pick_directory(title: String, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_macos_system_directory_picker(title, current_directory, callback, PICK_KIND_DIRECTORY)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("macOS folder picker falling back to native dialog", result)
		return super.pick_directory(title, callback, current_directory)
	return result

func pick_save_file(
	title: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable,
	current_directory: String = ""
) -> Dictionary:
	var result := _show_macos_system_save_file_picker(title, current_directory, default_filename, filters, callback)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("macOS save picker falling back to native dialog", result)
		return super.pick_save_file(title, default_filename, filters, callback, current_directory)
	return result

func open_path(path: String) -> Dictionary:
	var target: String = manager.globalize(path).strip_edges()
	if target.is_empty():
		return _fail("Path is empty.", path)
	var output: Array = []
	var exit_code := OS.execute("/usr/bin/open", [target], output, false, false)
	return _ok(path, {"native_path": target}) if exit_code == OK else _fail("Failed to open path. Error: %s" % exit_code, target)

func reveal_path(path: String) -> Dictionary:
	var target: String = manager.globalize(path).strip_edges()
	if target.is_empty():
		return _fail("Path is empty.", path)
	var output: Array = []
	var args := ["-R", target] if FileAccess.file_exists(target) else [target]
	var exit_code := OS.execute("/usr/bin/open", args, output, false, false)
	return _ok(path, {"native_path": target}) if exit_code == OK else _fail("Failed to reveal path. Error: %s" % exit_code, target)

func _show_macos_system_file_picker(
	title: String,
	current_directory: String,
	filters: PackedStringArray,
	callback: Callable,
	kind: String,
	multiple: bool
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("macOS system file picker callback invalid", {"kind": kind})
		return _fail("File picker callback is invalid.")

	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var script_lines := PackedStringArray()
	var script_arguments := PackedStringArray([title])
	var next_argument_index := 2
	var default_location_suffix := ""
	var file_type_suffix := ""
	script_lines.append("on run argv")
	script_lines.append("set dialogTitle to item 1 of argv")
	if DirAccess.dir_exists_absolute(dialog_directory):
		script_arguments.append(dialog_directory)
		script_lines.append("set dialogDefaultLocation to POSIX file (item %s of argv)" % next_argument_index)
		default_location_suffix = " default location dialogDefaultLocation"
		next_argument_index += 1
	var extensions := _apple_script_extensions(filters)
	if not extensions.is_empty():
		for extension in extensions:
			script_arguments.append(extension)
		script_lines.append("set allowedExtensions to items %s thru -1 of argv" % next_argument_index)
		file_type_suffix = " of type allowedExtensions"
	if multiple:
		script_lines.append(
			"set pickedItems to choose file with prompt dialogTitle%s%s with multiple selections allowed" % [
				default_location_suffix,
				file_type_suffix
			]
		)
		script_lines.append("set outputPaths to {}")
		script_lines.append("repeat with pickedItem in pickedItems")
		script_lines.append("set end of outputPaths to POSIX path of pickedItem")
		script_lines.append("end repeat")
		script_lines.append("set AppleScript's text item delimiters to linefeed")
		script_lines.append("return outputPaths as text")
	else:
		script_lines.append(
			"set pickedItem to choose file with prompt dialogTitle%s%s" % [
				default_location_suffix,
				file_type_suffix
			]
		)
		script_lines.append("return POSIX path of pickedItem")
	script_lines.append("end run")

	return _run_macos_system_picker("\n".join(script_lines), script_arguments, kind, callback, "macOS system file picker", title, current_directory, dialog_directory)

func _show_macos_system_directory_picker(
	title: String,
	current_directory: String,
	callback: Callable,
	kind: String
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("macOS system folder picker callback invalid", {"kind": kind})
		return _fail("File picker callback is invalid.")

	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var script_lines := PackedStringArray()
	var script_arguments := PackedStringArray([title])
	var default_location_suffix := ""
	script_lines.append("on run argv")
	script_lines.append("set dialogTitle to item 1 of argv")
	if DirAccess.dir_exists_absolute(dialog_directory):
		script_arguments.append(dialog_directory)
		script_lines.append("set dialogDefaultLocation to POSIX file (item 2 of argv)")
		default_location_suffix = " default location dialogDefaultLocation"
	script_lines.append("set pickedItem to choose folder with prompt dialogTitle%s" % default_location_suffix)
	script_lines.append("return POSIX path of pickedItem")
	script_lines.append("end run")
	return _run_macos_system_picker("\n".join(script_lines), script_arguments, kind, callback, "macOS system folder picker", title, current_directory, dialog_directory)

func _show_macos_system_save_file_picker(
	title: String,
	current_directory: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("macOS system save picker callback invalid", {"kind": PICK_KIND_SAVE_FILE})
		return _fail("File picker callback is invalid.")

	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var script_lines := PackedStringArray()
	var script_arguments := PackedStringArray([title])
	var next_argument_index := 2
	var default_name_suffix := ""
	var default_location_suffix := ""
	script_lines.append("on run argv")
	script_lines.append("set dialogTitle to item 1 of argv")
	if DirAccess.dir_exists_absolute(dialog_directory):
		script_arguments.append(dialog_directory)
		script_lines.append("set dialogDefaultLocation to POSIX file (item %s of argv)" % next_argument_index)
		default_location_suffix = " default location dialogDefaultLocation"
		next_argument_index += 1
	var clean_default_filename := default_filename.strip_edges()
	var extensions := _apple_script_extensions(filters)
	if not clean_default_filename.is_empty() and clean_default_filename.get_extension().is_empty() and not extensions.is_empty():
		clean_default_filename = "%s.%s" % [clean_default_filename, extensions[0]]
	if not clean_default_filename.is_empty():
		script_arguments.append(clean_default_filename)
		script_lines.append("set dialogDefaultName to item %s of argv" % next_argument_index)
		default_name_suffix = " default name dialogDefaultName"
	script_lines.append(
		"set pickedItem to choose file name with prompt dialogTitle%s%s" % [
			default_name_suffix,
			default_location_suffix
		]
	)
	script_lines.append("return POSIX path of pickedItem")
	script_lines.append("end run")
	return _run_macos_system_picker("\n".join(script_lines), script_arguments, PICK_KIND_SAVE_FILE, callback, "macOS system save picker", title, current_directory, dialog_directory)

func _run_macos_system_picker(
	script: String,
	script_arguments: PackedStringArray,
	kind: String,
	callback: Callable,
	log_label: String,
	title: String = "",
	current_directory: String = "",
	dialog_directory: String = ""
) -> Dictionary:
	_debug_file_picker("%s show" % log_label, {
		"kind": kind,
		"title": title,
		"current_directory": current_directory,
		"dialog_directory": dialog_directory
	})
	var output: Array = []
	var exit_code := OS.execute("/usr/bin/osascript", _apple_script_execute_args(script, script_arguments), output, true, false)
	var output_text := _process_output_to_text(output)

	if exit_code != OK:
		if output_text.contains("User canceled") or output_text.contains("-128"):
			_debug_file_picker("%s cancelled" % log_label, {"output": output_text})
			if callback.is_valid():
				callback.call_deferred(_build_file_dialog_result(false, PackedStringArray(), kind))
			return _ok("", {"pending": false, "cancelled": true})
		_debug_file_picker("%s failed" % log_label, {
			"exit_code": exit_code,
			"output": output_text,
			"script": script
		})
		return _fail("%s failed: %s" % [log_label, output_text])

	return _finish_blocking_system_picker(output_text, kind, callback, log_label)

func _apple_script_execute_args(script: String, script_arguments: PackedStringArray) -> PackedStringArray:
	var args := PackedStringArray()
	for line in script.split("\n", false):
		args.append("-e")
		args.append(str(line))
	args.append("--")
	args.append_array(script_arguments)
	return args

func _apple_script_extensions(filters: PackedStringArray) -> PackedStringArray:
	var extensions := PackedStringArray()
	for filter in filters:
		var pattern_part := str(filter).split(";", true, 1)[0]
		for pattern_value in pattern_part.split(",", false):
			var pattern := str(pattern_value).strip_edges()
			if pattern.is_empty() or pattern == "*":
				continue
			var extension := ""
			if pattern.begins_with("*."):
				extension = pattern.substr(2)
			elif pattern.begins_with("."):
				extension = pattern.substr(1)
			else:
				extension = pattern.get_extension()
			extension = extension.strip_edges().trim_prefix(".").to_lower()
			if extension.is_empty() or extensions.has(extension):
				continue
			extensions.append(extension)
	return extensions
