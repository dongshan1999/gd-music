class_name DX_SaveManager
extends RefCounted

const DEFAULT_SAVE_PATH := "user://save/data.json"
const DEFAULT_SAVE_SPLIT_CHAR_LIMIT := 512 * 1024
const SPLIT_SAVE_MARKER := "__dx_split_save"
const SPLIT_SAVE_VERSION := 1
const SAVE_BACKUP_SUFFIX := ".bak"
const SAVE_TEMP_SUFFIX := ".tmp"
const AUTO_SAVE_INTERVAL_MSEC := 60 * 1000
const AUTO_SAVE_DELAY_EXTENSION_MSEC := 3 * 1000

var dx: Node
var save_path := DEFAULT_SAVE_PATH
var save_split_char_limit := DEFAULT_SAVE_SPLIT_CHAR_LIMIT
var data = DX_SaveData.new()
var _is_dirty: bool = false
var _next_save_at_msec: int = -1

func in_ready() -> void:
	_ensure_save_dir()
	self.load()

func in_process(_delta: float) -> void:
	if not _is_dirty or _next_save_at_msec < 0:
		return
	if Time.get_ticks_msec() < _next_save_at_msec:
		return
	_flush_pending_save()

func in_quit() -> void:
	_flush_pending_save(true)

func in_pause(paused: bool) -> void:
	if paused:
		_flush_pending_save(true)

func in_focus(has_focus: bool) -> void:
	if not has_focus:
		_flush_pending_save(true)

func save(force: bool = true) -> bool:
	if not force:
		_mark_dirty()
		return true

	return _flush_pending_save(true)

func load():
	var has_existing_file := FileAccess.file_exists(save_path)
	data = DX_SaveData.new()
	var payload: Variant = _load_main_payload()
	if payload is Dictionary:
		if data.has_method("sanitize_payload"):
			payload = data.call("sanitize_payload", payload)
		DX_JsonSerializer.deserialize(payload, data)
	_normalize_object(data)
	_reset_pending_state()
	if not has_existing_file:
		save(true)
	return data

func _ensure_save_dir() -> bool:
	var native_path := ProjectSettings.globalize_path(save_path.get_base_dir())
	var err := DirAccess.make_dir_recursive_absolute(native_path)
	return err == OK or err == ERR_ALREADY_EXISTS

func _save_main_json(payload: Variant, pretty: bool = true) -> bool:
	if not _ensure_save_dir():
		return false

	var json_string := JSON.stringify(payload, "\t" if pretty else "")
	if save_split_char_limit > 0 and json_string.length() > save_split_char_limit:
		return _save_split_json_chunks(json_string, pretty)

	var ok := _write_json_file_safe(save_path, payload, pretty, true)
	if ok:
		_cleanup_split_files(_collect_backup_split_part_paths())
	return ok

func _load_main_payload() -> Variant:
	var primary := _try_load_save_payload(save_path)
	if bool(primary.get("ok", false)):
		return primary.get("payload", null)

	var backup_path := _get_backup_path(save_path)
	var backup := _try_load_save_payload(backup_path)
	if bool(backup.get("ok", false)):
		push_warning("Main save is damaged. Loaded backup: %s" % backup_path)
		return backup.get("payload", null)
	return null

func _save_split_json_chunks(json_string: String, pretty: bool = true) -> bool:
	var generation := _create_split_generation()
	var part_paths: Array[String] = []
	var part_entries: Array[Dictionary] = []
	var offset := 0
	var part_index := 0
	while offset < json_string.length():
		var chunk := json_string.substr(offset, save_split_char_limit)
		var part_path := _get_split_part_path(part_index, generation)
		var part_payload := {
			"version": SPLIT_SAVE_VERSION,
			"generation": generation,
			"index": part_index,
			"length": chunk.length(),
			"sha256": chunk.sha256_text(),
			"data": chunk,
		}
		if not _write_json_file_safe(part_path, part_payload, pretty, false):
			_cleanup_paths(part_paths)
			return false
		part_paths.append(part_path)
		part_entries.append({
			"path": part_path,
			"index": part_index,
			"length": chunk.length(),
			"sha256": chunk.sha256_text(),
		})
		offset += save_split_char_limit
		part_index += 1

	var manifest := {
		SPLIT_SAVE_MARKER: true,
		"version": SPLIT_SAVE_VERSION,
		"generation": generation,
		"part_count": part_entries.size(),
		"length": json_string.length(),
		"sha256": json_string.sha256_text(),
		"parts": part_entries,
	}
	if not _write_json_file_safe(save_path, manifest, pretty, true):
		_cleanup_paths(part_paths)
		return false

	var keep_paths := part_paths.duplicate()
	keep_paths.append_array(_collect_backup_split_part_paths())
	_cleanup_split_files(keep_paths)
	return true

func _try_load_save_payload(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "payload": null}

	var payload: Variant = _read_json_file(path)
	if payload == null:
		return {"ok": false, "payload": null}

	var resolved_payload: Variant = _resolve_split_payload(payload)
	if not resolved_payload is Dictionary:
		push_warning("Save file is not a valid JSON object: %s" % path)
		return {"ok": false, "payload": null}

	return {"ok": true, "payload": resolved_payload}

func _resolve_split_payload(payload: Variant) -> Variant:
	if not payload is Dictionary or not bool((payload as Dictionary).get(SPLIT_SAVE_MARKER, false)):
		return payload

	var manifest: Dictionary = payload
	var parts: Array = manifest.get("parts", [])
	if parts.is_empty():
		push_warning("Split save manifest has no parts.")
		return null
	if int(manifest.get("part_count", parts.size())) != parts.size():
		push_warning("Split save manifest part count mismatch.")
		return null

	var result := ""
	for index in parts.size():
		var part_entry: Variant = parts[index]
		var part_path := _get_manifest_part_path(part_entry)
		var part_payload: Variant = _read_json_file(part_path)
		if not part_payload is Dictionary:
			push_warning("Split save part failed to load: %s" % part_path)
			return null

		var part_index := int((part_payload as Dictionary).get("index", -1))
		if part_index != index:
			push_warning("Split save part index mismatch: %s" % part_path)
			return null

		var chunk := str((part_payload as Dictionary).get("data", ""))
		if not _validate_split_chunk(chunk, part_payload):
			push_warning("Split save part checksum mismatch: %s" % part_path)
			return null
		if part_entry is Dictionary and not _validate_split_chunk(chunk, part_entry):
			push_warning("Split save manifest checksum mismatch: %s" % part_path)
			return null
		result += chunk

	if not _validate_split_chunk(result, manifest):
		push_warning("Split save full checksum mismatch.")
		return null
	return _parse_json_string(result)

func _write_json_file_safe(path: String, payload: Variant, pretty: bool = true, backup_existing: bool = true) -> bool:
	var temp_path := _get_temp_path(path)
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))

	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(payload, "\t" if pretty else ""))
	file = null

	if backup_existing and FileAccess.file_exists(path):
		var current := _try_load_save_payload(path)
		if bool(current.get("ok", false)) and not _copy_file(path, _get_backup_path(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
			return false

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(path)
	)
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	return true

func _copy_file(from_path: String, to_path: String) -> bool:
	var source := FileAccess.open(from_path, FileAccess.READ)
	if source == null:
		return false

	var target := FileAccess.open(to_path, FileAccess.WRITE)
	if target == null:
		return false

	target.store_buffer(source.get_buffer(source.get_length()))
	return true

func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return _parse_json_string(file.get_as_text())

func _parse_json_string(source: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return null
	return parser.data

func _cleanup_split_files(keep_paths: Array = []) -> void:
	var keep_map := {}
	for path in keep_paths:
		keep_map[str(path)] = true

	var directory := DirAccess.open(save_path.get_base_dir())
	if directory == null:
		return

	var file_prefix := "%s.part." % save_path.get_file().get_basename()
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.begins_with(file_prefix):
			var path := "%s/%s" % [save_path.get_base_dir(), file_name]
			if not keep_map.has(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		file_name = directory.get_next()
	directory.list_dir_end()

func _cleanup_paths(paths: Array) -> void:
	for path in paths:
		if FileAccess.file_exists(str(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(str(path)))

func _collect_backup_split_part_paths() -> Array[String]:
	return _collect_manifest_part_paths_from_file(_get_backup_path(save_path))

func _collect_manifest_part_paths_from_file(path: String) -> Array[String]:
	var result: Array[String] = []
	var parsed: Variant = _read_json_file(path)
	if not parsed is Dictionary or not bool((parsed as Dictionary).get(SPLIT_SAVE_MARKER, false)):
		return result

	var parts: Array = (parsed as Dictionary).get("parts", [])
	for part_entry in parts:
		var part_path := _get_manifest_part_path(part_entry)
		if not part_path.is_empty():
			result.append(part_path)
	return result

func _get_manifest_part_path(part_entry: Variant) -> String:
	if part_entry is Dictionary:
		return str((part_entry as Dictionary).get("path", ""))
	return str(part_entry)

func _validate_split_chunk(source: String, metadata: Dictionary) -> bool:
	if metadata.has("length") and int(metadata.get("length", -1)) != source.length():
		return false
	if metadata.has("sha256") and str(metadata.get("sha256", "")) != source.sha256_text():
		return false
	return true

func _get_split_part_path(index: int, generation: String = "") -> String:
	var extension := save_path.get_extension()
	var suffix := ".%03d" % index
	if not generation.is_empty():
		suffix = ".%s.%03d" % [generation, index]
	if extension.is_empty():
		return "%s.part%s" % [save_path, suffix]
	return "%s.part%s.%s" % [save_path.get_basename(), suffix, extension]

func _create_split_generation() -> String:
	return "%d_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi()]

func _get_backup_path(path: String) -> String:
	return "%s%s" % [path, SAVE_BACKUP_SUFFIX]

func _get_temp_path(path: String) -> String:
	return "%s%s" % [path, SAVE_TEMP_SUFFIX]

func _normalize_object(object: Variant) -> void:
	if object != null and object.has_method("normalize"):
		object.call("normalize")

func _mark_dirty() -> void:
	var now_msec := Time.get_ticks_msec()
	if not _is_dirty:
		_is_dirty = true
		_next_save_at_msec = now_msec + AUTO_SAVE_INTERVAL_MSEC
		return
	_next_save_at_msec = maxi(_next_save_at_msec, now_msec) + AUTO_SAVE_DELAY_EXTENSION_MSEC

func _flush_pending_save(force: bool = false) -> bool:
	var ok := true

	if force or _is_dirty:
		ok = _save_main_json(_encode_data_for_save()) and ok

	if ok:
		_reset_pending_state()
	else:
		_is_dirty = true
	return ok

func _encode_data_for_save() -> Variant:
	_normalize_object(data)
	return DX_JsonSerializer.serialize(data)

func _reset_pending_state() -> void:
	_is_dirty = false
	_next_save_at_msec = -1
