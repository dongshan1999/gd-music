class_name DX_SaveManager
extends RefCounted

const SAVE_ROOT := "user://save_data"
const DEFAULT_DATA_PATH := "app/data.json"
const AUTO_SAVE_INTERVAL_MSEC := 60 * 1000
const AUTO_SAVE_DELAY_EXTENSION_MSEC := 3 * 1000

var dx: Node
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
	var save_file_path := SAVE_ROOT.path_join(DEFAULT_DATA_PATH)
	var has_existing_file := FileAccess.file_exists(save_file_path)
	var fallback_data = DX_SaveData.new()
	data = _load_main_object(fallback_data)
	if data == null:
		data = _clone_object(fallback_data)
	_normalize_object(data)
	_reset_pending_state()
	if not has_existing_file:
		save(true)
	return data

func _ensure_save_dir() -> bool:
	var native_path := ProjectSettings.globalize_path(SAVE_ROOT)
	var err := DirAccess.make_dir_recursive_absolute(native_path)
	return err == OK or err == ERR_ALREADY_EXISTS

func _save_main_json(payload: Variant, pretty: bool = true) -> bool:
	if not _ensure_save_dir():
		return false

	var file := FileAccess.open(SAVE_ROOT.path_join(DEFAULT_DATA_PATH), FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(payload, "\t" if pretty else ""))
	return true

func _load_main_json() -> Variant:
	var save_path := SAVE_ROOT.path_join(DEFAULT_DATA_PATH)
	if not FileAccess.file_exists(save_path):
		return null

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return null

	var raw_text := file.get_as_text()
	var json := JSON.new()
	if json.parse(raw_text) != OK:
		return null
	return json.data

func _load_main_object(default_object):
	if default_object == null:
		return null

	var loaded_object = _clone_object(default_object)
	if loaded_object == null:
		return null
	var parsed: Variant = _load_main_json()
	if typeof(parsed) == TYPE_DICTIONARY:
		_populate_object(loaded_object, parsed)

	_normalize_object(loaded_object)
	return loaded_object

func _serialize_object(object, include_ignored: bool = false) -> Dictionary:
	if object == null:
		return {}
	return DX_JsonSerializer.serialize(object, include_ignored)

func _populate_object(object, source_data: Dictionary) -> void:
	if object == null:
		return
	DX_JsonSerializer.deserialize(source_data, object)

func _clone_object(object):
	if object == null:
		return null

	var script = object.get_script()
	if script == null:
		return null

	var cloned = script.new()
	if cloned == null:
		return null

	var serialized_data = _serialize_object(object, true)
	if DX_JsonSerializer.has_error():
		return null

	DX_JsonSerializer.deserialize(serialized_data, cloned, true)
	if DX_JsonSerializer.has_error():
		return null
	return cloned

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
	var normalized_data = _clone_object(data)
	if normalized_data == null:
		push_error("DX_SaveManager failed to clone main save data.")
		return {}
	_normalize_object(normalized_data)

	var encoded = _serialize_object(normalized_data)
	if DX_JsonSerializer.has_error():
		push_error("DX_SaveManager failed to serialize main save data.")
		return {}
	return encoded

func _reset_pending_state() -> void:
	_is_dirty = false
	_next_save_at_msec = -1
