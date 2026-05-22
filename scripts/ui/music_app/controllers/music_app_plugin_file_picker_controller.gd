class_name MusicAppPluginFilePickerController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const WINDOWS_SCAN_ROOT := "windows://drives"
const PLUGIN_EXTENSION := "gd"

func get_scan_root_path() -> String:
	var os_name := OS.get_name()
	if os_name == "Android":
		for candidate in ["/storage/emulated/0", "/sdcard", "/storage/self/primary"]:
			if DirAccess.dir_exists_absolute(candidate):
				return candidate
		return "/"
	if os_name == "Windows":
		return WINDOWS_SCAN_ROOT

	var base_path := OS.get_environment("USERPROFILE")
	if base_path.is_empty():
		base_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if base_path.is_empty():
		base_path = ProjectSettings.globalize_path("res://")
	return path_root(base_path)

func get_scan_display_path(path: String) -> String:
	var normalized_path := normalize_path(path)
	if is_scan_virtual_root(normalized_path):
		return "此电脑"
	return normalized_path

func get_scan_parent_path(current_path: String, root_path: String) -> String:
	var normalized_current := normalize_path(current_path)
	var normalized_root := normalize_path(root_path)
	if normalized_current == normalized_root:
		return normalized_root
	if is_scan_virtual_root(normalized_root) and is_windows_drive_root(normalized_current):
		return normalized_root

	var parent := normalize_path(normalized_current.get_base_dir())
	if parent.is_empty():
		return normalized_root
	if parent.ends_with(":"):
		parent += "/"
	if parent.length() < normalized_root.length():
		return normalized_root
	return parent

func list_directory_entries(path: String) -> Array[Dictionary]:
	var normalized_path := normalize_path(path)
	if is_scan_virtual_root(normalized_path):
		return list_windows_drive_entries()
	if not DirAccess.dir_exists_absolute(normalized_path):
		return []

	var entries: Array[Dictionary] = []
	var directory_names := DirAccess.get_directories_at(normalized_path)
	directory_names.sort()
	for directory_name in directory_names:
		if directory_name in [".", ".."]:
			continue
		entries.append(
			{
				"name": directory_name,
				"path": normalize_path(normalized_path.path_join(directory_name)),
				"is_dir": true
			}
		)

	var file_names := DirAccess.get_files_at(normalized_path)
	file_names.sort()
	for file_name in file_names:
		if file_name.get_extension().to_lower() != PLUGIN_EXTENSION:
			continue
		entries.append(
			{
				"name": file_name,
				"path": normalize_path(normalized_path.path_join(file_name)),
				"is_dir": false
			}
		)

	return entries

func list_windows_drive_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for index in letters.length():
		var drive_letter := letters.substr(index, 1)
		var drive_path := "%s:/" % drive_letter
		if not DirAccess.dir_exists_absolute(drive_path):
			continue
		result.append(
			{
				"name": "%s:" % drive_letter,
				"path": drive_path,
				"is_dir": true
			}
		)
	return result

func is_scan_virtual_root(path: String) -> bool:
	return normalize_path(path) == WINDOWS_SCAN_ROOT

func is_windows_drive_root(path: String) -> bool:
	var normalized_path := normalize_path(path)
	return normalized_path.length() == 3 and normalized_path[1] == ":" and normalized_path[2] == "/"

func normalize_path(path: String) -> String:
	var trimmed := str(path).strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed == WINDOWS_SCAN_ROOT:
		return WINDOWS_SCAN_ROOT
	var normalized := trimmed.replace("\\", "/")
	if normalized.length() == 2 and normalized[1] == ":":
		normalized += "/"
	return normalized

func path_root(path: String) -> String:
	var normalized := normalize_path(path)
	if normalized.is_empty():
		return ""
	if normalized.contains(":/"):
		return normalized.substr(0, normalized.find(":/") + 2)
	if normalized.begins_with("/"):
		return "/"
	return normalized
