@tool
extends EditorPlugin

const BUILD_INFO_PATH := "res://build_info.cfg"

class DXBuildNumberExportHook:
	extends EditorExportPlugin

	func _get_name() -> String:
		return "DXBuildNumberExport"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return not _get_platform_key(platform).is_empty()

	func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
		var platform_key := _get_platform_key(platform)
		if platform_key.is_empty():
			return {}

		var next_build_number := _read_project_build_number() + 1
		return {
			"build_number": next_build_number,
		}

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		var platform_key := _get_platform_key(get_export_platform())
		if platform_key.is_empty():
			return

		var build_number := _read_project_build_number() + 1
		var build_info := _make_build_info(platform_key, build_number, _is_debug)
		_write_project_build_info(build_info)
		add_file("res://build_info.cfg", build_info.to_utf8_buffer(), false)
		print("[DXBuildNumberExport] %s build_number -> %d" % [platform_key, build_number])

	func _get_platform_key(platform: EditorExportPlatform) -> String:
		if platform == null:
			return ""
		var normalized_name := platform.get_os_name().strip_edges().to_lower()
		if normalized_name.contains("windows"):
			return "windows"
		if normalized_name.contains("android"):
			return "android"
		return ""

	func _make_build_info(platform_key: String, build_number: int, is_debug: bool) -> String:
		var config := ConfigFile.new()
		config.set_value("app", "version", str(ProjectSettings.get_setting("application/config/version", "0.0.0")))
		config.set_value("build", "platform", platform_key)
		config.set_value("build", "number", maxi(0, build_number))
		config.set_value("build", "debug", is_debug)
		config.set_value("build", "unix_time", int(Time.get_unix_time_from_system()))
		return config.encode_to_text()

	func _read_project_build_number() -> int:
		var config := ConfigFile.new()
		if config.load(BUILD_INFO_PATH) != OK:
			return 0
		return maxi(0, int(config.get_value("build", "number", 0)))

	func _write_project_build_info(build_info: String) -> void:
		var file := FileAccess.open(BUILD_INFO_PATH, FileAccess.WRITE)
		if file == null:
			push_warning("Failed to write build info: %s" % BUILD_INFO_PATH)
			return
		file.store_string(build_info)

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	_export_plugin = DXBuildNumberExportHook.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	if _export_plugin == null:
		return
	remove_export_plugin(_export_plugin)
	_export_plugin = null
