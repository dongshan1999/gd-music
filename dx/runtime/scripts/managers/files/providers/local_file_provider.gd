class_name DX_LocalFileProvider
extends "res://dx/runtime/scripts/managers/files/providers/file_provider.gd"

const SCHEME_LOCAL := "local"

func supports(path_info: Dictionary) -> bool:
	return str(path_info.get("scheme", "")) == SCHEME_LOCAL

func read_bytes(path_info: Dictionary) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	return _read_file_bytes(globalize(path_info))

func write_bytes(path_info: Dictionary, data: PackedByteArray) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	return _write_file_bytes(globalize(path_info), data)

func exists(path_info: Dictionary) -> bool:
	if not _is_supported_platform():
		return false
	var path := globalize(path_info)
	return _is_native_link(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

func is_dir(path_info: Dictionary) -> bool:
	if not _is_supported_platform():
		return false
	var path := globalize(path_info)
	return DirAccess.dir_exists_absolute(path) and not _is_native_link(path)

func is_link(path_info: Dictionary) -> bool:
	return _is_supported_platform() and _is_native_link(globalize(path_info))

func get_info(path_info: Dictionary) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	var path := globalize(path_info)
	return _get_native_file_info(path, "local://%s" % path)

func make_dir_recursive(path_info: Dictionary) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	var path := globalize(path_info)
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return _fail("Failed to create directory. Error: %s" % err, path)
	return _ok(path)

func list_dir(path_info: Dictionary) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	var native_dir := globalize(path_info)
	if not DirAccess.dir_exists_absolute(native_dir):
		return _fail("Directory does not exist.", native_dir)

	var directory := DirAccess.open(native_dir)
	if directory == null:
		return _fail("Failed to open directory. Error: %s" % DirAccess.get_open_error(), native_dir)

	var entries: Array[Dictionary] = []
	directory.list_dir_begin()
	while true:
		var item_name := directory.get_next()
		if item_name.is_empty():
			break
		var native_path := native_dir.path_join(item_name)
		var is_link := directory.is_link(item_name)
		entries.append({
			"name": item_name,
			"path": "local://%s" % native_path,
			"native_path": native_path,
			"is_dir": directory.current_is_dir() and not is_link,
			"is_link": is_link
		})
	directory.list_dir_end()
	return _ok("local://%s" % native_dir, {"entries": entries})

func delete_file(path_info: Dictionary) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	return _delete_native_file(globalize(path_info))

func delete_dir(path_info: Dictionary) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	return _delete_native_dir(globalize(path_info))

func copy_from_access_path(path_info: Dictionary, source_access_path: String, chunk_size: int = 1024 * 1024) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	return _copy_file_streaming(source_access_path, globalize(path_info), chunk_size, true)

func move_path(source_info: Dictionary, target_info: Dictionary, overwrite: bool = true) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(source_info))
	return _move_native_path(globalize(source_info), globalize(target_info), overwrite)

func globalize(path_info: Dictionary) -> String:
	return str(path_info.get("body", "")).strip_edges()

func _is_supported_platform() -> bool:
	return OS.get_name() != "Android"
