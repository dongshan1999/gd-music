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
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

func make_dir_recursive(path_info: Dictionary) -> Dictionary:
	if not _is_supported_platform():
		return _fail("local:// paths are only available on desktop/editor platforms.", globalize(path_info))
	var path := globalize(path_info)
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return _fail("Failed to create directory. Error: %s" % err, path)
	return _ok(path)

func globalize(path_info: Dictionary) -> String:
	return str(path_info.get("body", "")).strip_edges()

func _is_supported_platform() -> bool:
	return OS.get_name() != "Android"
