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
	var native_path := globalize(path_info)
	return _is_native_link(native_path) or FileAccess.file_exists(_to_godot_path(path_info)) or DirAccess.dir_exists_absolute(native_path)

func is_dir(path_info: Dictionary) -> bool:
	var path := globalize(path_info)
	return DirAccess.dir_exists_absolute(path) and not _is_native_link(path)

func is_link(path_info: Dictionary) -> bool:
	return _is_native_link(globalize(path_info))

func get_info(path_info: Dictionary) -> Dictionary:
	return _get_native_file_info(globalize(path_info), "app://%s" % str(path_info.get("body", "")).strip_edges().replace("\\", "/").trim_prefix("/"))

func make_dir_recursive(path_info: Dictionary) -> Dictionary:
	var path := _to_godot_path(path_info)
	var native_path := ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(native_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return _fail("Failed to create directory. Error: %s" % err, path)
	return _ok(path)

func list_dir(path_info: Dictionary) -> Dictionary:
	var godot_dir := _to_godot_path(path_info)
	var native_dir := ProjectSettings.globalize_path(godot_dir)
	if not DirAccess.dir_exists_absolute(native_dir):
		return _fail("Directory does not exist.", godot_dir)

	var directory := DirAccess.open(godot_dir)
	if directory == null:
		return _fail("Failed to open directory. Error: %s" % DirAccess.get_open_error(), godot_dir)

	var base_body := str(path_info.get("body", "")).strip_edges().replace("\\", "/").trim_prefix("/")
	var entries: Array[Dictionary] = []
	directory.list_dir_begin()
	while true:
		var item_name := directory.get_next()
		if item_name.is_empty():
			break
		var child_body := base_body.path_join(item_name) if not base_body.is_empty() else item_name
		var godot_path := godot_dir.path_join(item_name)
		var is_link := directory.is_link(item_name)
		entries.append({
			"name": item_name,
			"path": "app://%s" % child_body,
			"native_path": ProjectSettings.globalize_path(godot_path),
			"is_dir": directory.current_is_dir() and not is_link,
			"is_link": is_link
		})
	directory.list_dir_end()
	return _ok("app://%s" % base_body, {"entries": entries})

func delete_file(path_info: Dictionary) -> Dictionary:
	return _delete_native_file(globalize(path_info))

func delete_dir(path_info: Dictionary) -> Dictionary:
	return _delete_native_dir(globalize(path_info))

func copy_from_access_path(path_info: Dictionary, source_access_path: String, chunk_size: int = 1024 * 1024) -> Dictionary:
	return _copy_file_streaming(source_access_path, globalize(path_info), chunk_size, true)

func move_path(source_info: Dictionary, target_info: Dictionary, overwrite: bool = true) -> Dictionary:
	return _move_native_path(globalize(source_info), globalize(target_info), overwrite)

func globalize(path_info: Dictionary) -> String:
	return ProjectSettings.globalize_path(_to_godot_path(path_info))

func _to_godot_path(path_info: Dictionary) -> String:
	var body := str(path_info.get("body", "")).strip_edges().replace("\\", "/").trim_prefix("/")
	return "user://%s" % body
