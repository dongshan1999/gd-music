class_name DX_AppDataFileProvider
extends "res://dx/runtime/scripts/managers/files/providers/file_provider.gd"

const SCHEME_APP := "app"

func supports(path_info: Dictionary) -> bool:
	return str(path_info.get("scheme", "")) == SCHEME_APP

func read_bytes(path_info: Dictionary) -> Dictionary:
	return _read_file_bytes(_to_godot_path(path_info))

func write_bytes(path_info: Dictionary, data: PackedByteArray) -> Dictionary:
	return _write_file_bytes(_to_godot_path(path_info), data)

func exists(path_info: Dictionary) -> bool:
	return FileAccess.file_exists(_to_godot_path(path_info)) or DirAccess.dir_exists_absolute(globalize(path_info))

func make_dir_recursive(path_info: Dictionary) -> Dictionary:
	var path := _to_godot_path(path_info)
	var native_path := ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(native_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return _fail("Failed to create directory. Error: %s" % err, path)
	return _ok(path)

func globalize(path_info: Dictionary) -> String:
	return ProjectSettings.globalize_path(_to_godot_path(path_info))

func _to_godot_path(path_info: Dictionary) -> String:
	var body := str(path_info.get("body", "")).strip_edges().replace("\\", "/").trim_prefix("/")
	return "user://%s" % body
