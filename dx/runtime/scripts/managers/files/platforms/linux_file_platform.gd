class_name DX_LinuxFilePlatform
extends "res://dx/runtime/scripts/managers/files/platforms/file_platform.gd"

func pick_file(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_linux_system_file_picker(title, current_directory, filters, callback, PICK_KIND_FILE, false)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("Linux file picker falling back to native dialog", result)
		return super.pick_file(title, filters, callback, current_directory)
	return result

func pick_files(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_linux_system_file_picker(title, current_directory, filters, callback, PICK_KIND_FILES, true)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("Linux multi-file picker falling back to native dialog", result)
		return super.pick_files(title, filters, callback, current_directory)
	return result

func pick_directory(title: String, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_linux_system_directory_picker(title, current_directory, callback, PICK_KIND_DIRECTORY)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("Linux folder picker falling back to native dialog", result)
		return super.pick_directory(title, callback, current_directory)
	return result

func pick_save_file(
	title: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable,
	current_directory: String = ""
) -> Dictionary:
	var result := _show_linux_system_save_file_picker(title, current_directory, default_filename, filters, callback)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("Linux save picker falling back to native dialog", result)
		return super.pick_save_file(title, default_filename, filters, callback, current_directory)
	return result

func _show_linux_system_file_picker(
	title: String,
	current_directory: String,
	filters: PackedStringArray,
	callback: Callable,
	kind: String,
	multiple: bool
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("Linux system file picker callback invalid", {"kind": kind})
		return _fail("File picker callback is invalid.")

	var command := _find_linux_file_picker_command()
	if command.is_empty():
		return _fail("No Linux native file picker command found. Install zenity or kdialog.")
	if command.get_file() == "kdialog":
		return _show_linux_kdialog_file_picker(command, title, current_directory, filters, callback, kind, multiple)
	return _show_linux_zenity_file_picker(command, title, current_directory, filters, callback, kind, multiple)

func _show_linux_system_directory_picker(
	title: String,
	current_directory: String,
	callback: Callable,
	kind: String
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("Linux system folder picker callback invalid", {"kind": kind})
		return _fail("File picker callback is invalid.")

	var command := _find_linux_file_picker_command()
	if command.is_empty():
		return _fail("No Linux native file picker command found. Install zenity or kdialog.")
	if command.get_file() == "kdialog":
		return _show_linux_kdialog_directory_picker(command, title, current_directory, callback, kind)
	return _show_linux_zenity_directory_picker(command, title, current_directory, callback, kind)

func _show_linux_system_save_file_picker(
	title: String,
	current_directory: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("Linux system save picker callback invalid", {"kind": PICK_KIND_SAVE_FILE})
		return _fail("File picker callback is invalid.")

	var command := _find_linux_file_picker_command()
	if command.is_empty():
		return _fail("No Linux native file picker command found. Install zenity or kdialog.")
	if command.get_file() == "kdialog":
		return _show_linux_kdialog_save_file_picker(command, title, current_directory, default_filename, filters, callback)
	return _show_linux_zenity_save_file_picker(command, title, current_directory, default_filename, filters, callback)

func _show_linux_zenity_file_picker(
	command: String,
	title: String,
	current_directory: String,
	filters: PackedStringArray,
	callback: Callable,
	kind: String,
	multiple: bool
) -> Dictionary:
	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var args := PackedStringArray(["--file-selection", "--title=%s" % title])
	if multiple:
		args.append("--multiple")
		args.append("--separator=\n")
	var filename := _linux_dialog_filename(dialog_directory)
	if not filename.is_empty():
		args.append("--filename=%s" % filename)
	for filter_arg in _zenity_filter_args(filters):
		args.append(filter_arg)
	return _run_linux_system_picker(command, args, kind, callback, "Linux zenity file picker", title, current_directory, dialog_directory)

func _show_linux_zenity_directory_picker(
	command: String,
	title: String,
	current_directory: String,
	callback: Callable,
	kind: String
) -> Dictionary:
	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var args := PackedStringArray(["--file-selection", "--directory", "--title=%s" % title])
	var filename := _linux_dialog_filename(dialog_directory)
	if not filename.is_empty():
		args.append("--filename=%s" % filename)
	return _run_linux_system_picker(command, args, kind, callback, "Linux zenity folder picker", title, current_directory, dialog_directory)

func _show_linux_zenity_save_file_picker(
	command: String,
	title: String,
	current_directory: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable
) -> Dictionary:
	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var args := PackedStringArray(["--file-selection", "--save", "--confirm-overwrite", "--title=%s" % title])
	var filename := _linux_dialog_filename(dialog_directory, default_filename)
	if not filename.is_empty():
		args.append("--filename=%s" % filename)
	for filter_arg in _zenity_filter_args(filters):
		args.append(filter_arg)
	return _run_linux_system_picker(command, args, PICK_KIND_SAVE_FILE, callback, "Linux zenity save picker", title, current_directory, dialog_directory)

func _show_linux_kdialog_file_picker(
	command: String,
	title: String,
	current_directory: String,
	filters: PackedStringArray,
	callback: Callable,
	kind: String,
	multiple: bool
) -> Dictionary:
	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var args := PackedStringArray(["--title", title])
	if multiple:
		args.append("--multiple")
		args.append("--separate-output")
	args.append("--getopenfilename")
	args.append(dialog_directory if not dialog_directory.is_empty() else ".")
	args.append(_kdialog_filter_string(filters))
	return _run_linux_system_picker(command, args, kind, callback, "Linux kdialog file picker", title, current_directory, dialog_directory)

func _show_linux_kdialog_directory_picker(
	command: String,
	title: String,
	current_directory: String,
	callback: Callable,
	kind: String
) -> Dictionary:
	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var args := PackedStringArray([
		"--title",
		title,
		"--getexistingdirectory",
		dialog_directory if not dialog_directory.is_empty() else "."
	])
	return _run_linux_system_picker(command, args, kind, callback, "Linux kdialog folder picker", title, current_directory, dialog_directory)

func _show_linux_kdialog_save_file_picker(
	command: String,
	title: String,
	current_directory: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable
) -> Dictionary:
	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var filename := _linux_dialog_filename(dialog_directory, default_filename)
	var args := PackedStringArray([
		"--title",
		title,
		"--getsavefilename",
		filename if not filename.is_empty() else default_filename,
		_kdialog_filter_string(filters)
	])
	return _run_linux_system_picker(command, args, PICK_KIND_SAVE_FILE, callback, "Linux kdialog save picker", title, current_directory, dialog_directory)

func _run_linux_system_picker(
	command: String,
	args: PackedStringArray,
	kind: String,
	callback: Callable,
	log_label: String,
	title: String,
	current_directory: String,
	dialog_directory: String
) -> Dictionary:
	_debug_file_picker("%s show" % log_label, {
		"kind": kind,
		"title": title,
		"current_directory": current_directory,
		"dialog_directory": dialog_directory,
		"command": command
	})
	var output: Array = []
	var exit_code := OS.execute(command, args, output, true, false)
	var output_text := _process_output_to_text(output)
	if exit_code == 1:
		_debug_file_picker("%s cancelled" % log_label, {"output": output_text})
		if callback.is_valid():
			callback.call_deferred(_build_file_dialog_result(false, PackedStringArray(), kind))
		return _ok("", {"pending": false, "cancelled": true})
	if exit_code != OK:
		_debug_file_picker("%s failed" % log_label, {
			"exit_code": exit_code,
			"output": output_text
		})
		return _fail("%s failed: %s" % [log_label, output_text])
	return _finish_blocking_system_picker(output_text, kind, callback, log_label)

func _find_linux_file_picker_command() -> String:
	for command_name in ["zenity", "kdialog"]:
		var output: Array = []
		var exit_code := OS.execute("/bin/sh", ["-lc", "command -v %s" % command_name], output, true, false)
		if exit_code != OK:
			continue
		var output_text := _process_output_to_text(output)
		if output_text.is_empty():
			continue
		return str(output_text.split("\n", false)[0]).strip_edges()
	return ""

func _linux_dialog_filename(dialog_directory: String, default_filename: String = "") -> String:
	var directory := dialog_directory.strip_edges().replace("\\", "/")
	if directory.is_empty():
		return default_filename.strip_edges()
	if not default_filename.strip_edges().is_empty():
		return directory.path_join(default_filename.strip_edges())
	if directory.ends_with("/"):
		return directory
	return "%s/" % directory

func _zenity_filter_args(filters: PackedStringArray) -> PackedStringArray:
	var args := PackedStringArray()
	for filter in filters:
		var parsed := _parse_picker_filter(str(filter))
		var patterns: PackedStringArray = parsed.get("patterns", PackedStringArray())
		if patterns.is_empty():
			continue
		var description := str(parsed.get("description", "Files")).strip_edges()
		args.append("--file-filter=%s | %s" % [description, " ".join(patterns)])
	if not args.is_empty():
		args.append("--file-filter=All files | *")
	return args

func _kdialog_filter_string(filters: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for filter in filters:
		var parsed := _parse_picker_filter(str(filter))
		var patterns: PackedStringArray = parsed.get("patterns", PackedStringArray())
		if patterns.is_empty():
			continue
		var description := str(parsed.get("description", "Files")).strip_edges()
		parts.append("%s|%s" % [" ".join(patterns), description])
	if parts.is_empty():
		return "*|All files"
	parts.append("*|All files")
	return "\n".join(parts)
