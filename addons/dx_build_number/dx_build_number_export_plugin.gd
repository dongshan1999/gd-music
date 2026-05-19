@tool
extends EditorPlugin

const BuildNumberStoreScript := preload("res://addons/dx_build_number/dx_build_number_store.gd")

class DXBuildNumberExportHook:
	extends EditorExportPlugin

	var _store := BuildNumberStoreScript.new()

	func _get_name() -> String:
		return "DXBuildNumberExport"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return not _get_platform_key(platform).is_empty()

	func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
		var platform_key := _get_platform_key(platform)
		if platform_key.is_empty():
			return {}

		var next_build_number := _store.get_next_build_number(platform_key)
		return {
			"build_number": next_build_number,
		}

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		var platform_key := _get_platform_key(get_export_platform())
		if platform_key.is_empty():
			return

		var build_number := _store.increment_build_number(platform_key)
		print("[DXBuildNumberExport] %s build_number -> %d" % [platform_key, build_number])

	func _get_platform_key(platform: EditorExportPlatform) -> String:
		if platform == null:
			return ""
		return BuildNumberStoreScript.normalize_platform_name(platform.get_os_name())

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	_export_plugin = DXBuildNumberExportHook.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	if _export_plugin == null:
		return
	remove_export_plugin(_export_plugin)
	_export_plugin = null
