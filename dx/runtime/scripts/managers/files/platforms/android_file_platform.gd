class_name DX_AndroidFilePlatform
extends "res://dx/runtime/scripts/managers/files/platforms/file_platform.gd"

func pick_file(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	_debug_file_picker("Android system file picker requested", {"kind": PICK_KIND_FILE})
	return super.pick_file(title, filters, callback, current_directory)

func pick_files(title: String, filters: PackedStringArray, callback: Callable, current_directory: String = "") -> Dictionary:
	_debug_file_picker("Android system file picker requested", {"kind": PICK_KIND_FILES})
	return super.pick_files(title, filters, callback, current_directory)

func pick_directory(title: String, callback: Callable, current_directory: String = "") -> Dictionary:
	_debug_file_picker("Android system folder picker requested", {"kind": PICK_KIND_DIRECTORY})
	return super.pick_directory(title, callback, current_directory)

func pick_save_file(
	title: String,
	default_filename: String,
	filters: PackedStringArray,
	callback: Callable,
	current_directory: String = ""
) -> Dictionary:
	_debug_file_picker("Android system save picker requested", {"kind": PICK_KIND_SAVE_FILE})
	return super.pick_save_file(title, default_filename, filters, callback, current_directory)
