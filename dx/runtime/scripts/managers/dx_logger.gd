class_name DXLogger
extends "res://dx/runtime/scripts/managers/dx_manager.gd"

var _enabled := true
var _info_enabled := true
var _warning_enabled := true
var _error_enabled := true
var _tag_states: Dictionary = {}

func in_ready() -> void:
	pass

func set_enable(enabled: bool) -> void:
	_enabled = enabled

func set_info_enable(enabled: bool) -> void:
	_info_enabled = enabled

func set_warning_enable(enabled: bool) -> void:
	_warning_enabled = enabled

func set_error_enable(enabled: bool) -> void:
	_error_enabled = enabled

func set_tag_enable(tag: StringName, enabled: bool) -> void:
	var string_tag := String(tag)
	_tag_states[string_tag] = enabled

func is_tag_enabled(tag: StringName) -> bool:
	var string_tag := String(tag)
	if _tag_states.has(string_tag):
		return bool(_tag_states[string_tag])
	return true

func load_settings() -> void:
	pass

func save_settings() -> void:
	pass

func log(tag_or_message: Variant, message: Variant = null) -> void:
	if message == null:
		_log_internal(&"", tag_or_message, "info")
		return
	_log_internal(StringName(str(tag_or_message)), message, "info")

func warning(tag_or_message: Variant, message: Variant = null) -> void:
	if message == null:
		_log_internal(&"", tag_or_message, "warning")
		return
	_log_internal(StringName(str(tag_or_message)), message, "warning")

func error(tag_or_message: Variant, message: Variant = null) -> void:
	if message == null:
		_log_internal(&"", tag_or_message, "error")
		return
	_log_internal(StringName(str(tag_or_message)), message, "error")

func exception(tag: Variant, err: Variant) -> void:
	_log_internal(StringName(str(tag)), err, "error")

func _log_internal(tag: StringName, message: Variant, level: String) -> void:
	if not _enabled:
		return
	if not tag.is_empty() and not is_tag_enabled(tag):
		return

	match level:
		"info":
			if not _info_enabled:
				return
		"warning":
			if not _warning_enabled:
				return
		"error":
			if not _error_enabled:
				return

	var prefix := "[%s]" % _timestamp()
	if not tag.is_empty():
		prefix += "[%s]" % String(tag)
	var text := "%s %s" % [prefix, str(message)]

	match level:
		"warning":
			push_warning(text)
		"error":
			push_error(text)
		_:
			print(text)

func _timestamp() -> String:
	if framework != null and framework.time != null:
		return framework.time.now().format("yyyy-MM-dd HH:mm:ss")
	return Time.get_datetime_string_from_system(true, true)
