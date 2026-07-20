class_name DX_WindowsFilePlatform
extends "res://dx/runtime/scripts/managers/files/platforms/file_platform.gd"

func pick_file(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_windows_system_file_picker(title, current_directory, filters, callback, PICK_KIND_FILE, false)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("Windows file picker falling back to native dialog", result)
		return super.pick_file(title, filters, callback, current_directory)
	return result

func pick_files(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_windows_system_file_picker(title, current_directory, filters, callback, PICK_KIND_FILES, true)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("Windows multi-file picker falling back to native dialog", result)
		return super.pick_files(title, filters, callback, current_directory)
	return result

func pick_directory(title: String, callback: Callable, current_directory: String = "") -> Dictionary:
	var result := _show_windows_system_directory_picker(title, current_directory, callback, PICK_KIND_DIRECTORY)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("Windows folder picker falling back to native dialog", result)
		return super.pick_directory(title, callback, current_directory)
	return result

func pick_save_file(
	title: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable,
	current_directory: String = ""
) -> Dictionary:
	var result := _show_windows_system_save_file_picker(title, current_directory, default_filename, filters, callback)
	if _should_fallback_to_native_dialog(result):
		_debug_file_picker("Windows save picker falling back to native dialog", result)
		return super.pick_save_file(title, default_filename, filters, callback, current_directory)
	return result

func reveal_path(path: String) -> Dictionary:
	var target: String = manager.globalize(path).strip_edges()
	if target.is_empty():
		return _fail("Path is empty.", path)
	var output: Array = []
	var args := ["/select,%s" % target] if FileAccess.file_exists(target) else [target]
	var exit_code := OS.execute("explorer.exe", args, output, false, false)
	return _ok(path, {"native_path": target}) if exit_code == OK else _fail("Failed to reveal path. Error: %s" % exit_code, target)

func _show_windows_system_file_picker(
	title: String,
	current_directory: String,
	filters: PackedStringArray,
	callback: Callable,
	kind: String,
	multiple: bool
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("Windows system file picker callback invalid", {"kind": kind})
		return _fail("File picker callback is invalid.")

	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var script_lines := PackedStringArray()
	script_lines.append("[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)")
	script_lines.append("Add-Type -AssemblyName System.Windows.Forms")
	script_lines.append("[System.Windows.Forms.Application]::EnableVisualStyles()")
	script_lines.append("$dialog = New-Object System.Windows.Forms.OpenFileDialog")
	script_lines.append("$dialog.Title = %s" % _power_shell_quote(title))
	script_lines.append("$dialog.Multiselect = %s" % ("$true" if multiple else "$false"))
	script_lines.append("$dialog.CheckFileExists = $true")
	script_lines.append("$dialog.Filter = %s" % _power_shell_quote(_windows_filter_string(filters)))
	if not dialog_directory.is_empty():
		script_lines.append(
			"if (Test-Path -LiteralPath %s) { $dialog.InitialDirectory = %s }" % [
				_power_shell_quote(dialog_directory),
				_power_shell_quote(dialog_directory)
			]
		)
	script_lines.append("if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {")
	script_lines.append("if ($dialog.Multiselect) { Write-Output ($dialog.FileNames -join [Environment]::NewLine) } else { Write-Output $dialog.FileName }")
	script_lines.append("exit 0")
	script_lines.append("}")
	script_lines.append("exit 2")
	return _run_windows_system_picker("\n".join(script_lines), kind, callback, "Windows system file picker", title, current_directory, dialog_directory)

func _show_windows_system_directory_picker(
	title: String,
	current_directory: String,
	callback: Callable,
	kind: String
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("Windows system folder picker callback invalid", {"kind": kind})
		return _fail("File picker callback is invalid.")

	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var script_lines := PackedStringArray()
	script_lines.append("[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)")
	script_lines.append("Add-Type -AssemblyName System.Windows.Forms")
	script_lines.append("[System.Windows.Forms.Application]::EnableVisualStyles()")
	script_lines.append("$dialog = New-Object System.Windows.Forms.FolderBrowserDialog")
	script_lines.append("$dialog.Description = %s" % _power_shell_quote(title))
	script_lines.append("$dialog.ShowNewFolderButton = $true")
	if not dialog_directory.is_empty():
		script_lines.append(
			"if (Test-Path -LiteralPath %s) { $dialog.SelectedPath = %s }" % [
				_power_shell_quote(dialog_directory),
				_power_shell_quote(dialog_directory)
			]
		)
	script_lines.append("if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dialog.SelectedPath; exit 0 }")
	script_lines.append("exit 2")
	return _run_windows_system_picker("\n".join(script_lines), kind, callback, "Windows system folder picker", title, current_directory, dialog_directory)

func _show_windows_system_save_file_picker(
	title: String,
	current_directory: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable
) -> Dictionary:
	if not callback.is_valid():
		_debug_file_picker("Windows system save picker callback invalid", {"kind": PICK_KIND_SAVE_FILE})
		return _fail("File picker callback is invalid.")

	var dialog_directory: String = manager.dialog_native_directory(current_directory)
	var script_lines := PackedStringArray()
	script_lines.append("[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)")
	script_lines.append("Add-Type -AssemblyName System.Windows.Forms")
	script_lines.append("[System.Windows.Forms.Application]::EnableVisualStyles()")
	script_lines.append("$dialog = New-Object System.Windows.Forms.SaveFileDialog")
	script_lines.append("$dialog.Title = %s" % _power_shell_quote(title))
	script_lines.append("$dialog.OverwritePrompt = $true")
	script_lines.append("$dialog.CheckPathExists = $true")
	script_lines.append("$dialog.Filter = %s" % _power_shell_quote(_windows_filter_string(filters)))
	if not default_filename.strip_edges().is_empty():
		script_lines.append("$dialog.FileName = %s" % _power_shell_quote(default_filename.strip_edges()))
	if not dialog_directory.is_empty():
		script_lines.append(
			"if (Test-Path -LiteralPath %s) { $dialog.InitialDirectory = %s }" % [
				_power_shell_quote(dialog_directory),
				_power_shell_quote(dialog_directory)
			]
		)
	script_lines.append("if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dialog.FileName; exit 0 }")
	script_lines.append("exit 2")
	return _run_windows_system_picker("\n".join(script_lines), PICK_KIND_SAVE_FILE, callback, "Windows system save picker", title, current_directory, dialog_directory)

func _run_windows_system_picker(
	script: String,
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
		"dialog_directory": dialog_directory
	})
	var output: Array = []
	var exit_code := OS.execute(
		"powershell.exe",
		["-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-Command", script],
		output,
		true,
		false
	)
	var output_text := _process_output_to_text(output)
	if exit_code == 2:
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

func _power_shell_quote(value: String) -> String:
	return "'%s'" % value.replace("'", "''")

func _windows_filter_string(filters: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for filter in filters:
		var parsed := _parse_picker_filter(str(filter))
		var patterns: PackedStringArray = parsed.get("patterns", PackedStringArray())
		if patterns.is_empty():
			continue
		var description := str(parsed.get("description", "Files")).strip_edges()
		var pattern_text := ";".join(patterns)
		parts.append("%s (%s)" % [description, pattern_text])
		parts.append(pattern_text)
	if parts.is_empty():
		return "All files (*.*)|*.*"
	parts.append("All files (*.*)")
	parts.append("*.*")
	return "|".join(parts)
