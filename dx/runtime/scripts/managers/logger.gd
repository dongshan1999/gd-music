class_name DX_Logger
extends RefCounted

const MAX_ENTRIES := 200
const LEVEL_INFO := "INFO"
const LEVEL_WARN := "WARN"
const LEVEL_ERROR := "ERROR"

class DXEngineLogger extends Logger:
	var owner

	func _init(owner_ref) -> void:
		owner = owner_ref

	func _log_message(message: String, is_error: bool) -> void:
		if owner != null:
			owner._capture_native_message(message, is_error)

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		editor_notify: bool,
		error_type: int,
		script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if owner != null:
			owner._capture_native_error(
				function,
				file,
				line,
				code,
				rationale,
				editor_notify,
				error_type,
				script_backtraces
			)

var dx: Node
var _enabled := true
var _info_enabled := true
var _warning_enabled := true
var _error_enabled := true
var _tag_states: Dictionary = {}
var _entries: Array[Dictionary] = []
var _revision := 0
var _mutex := Mutex.new()
var _engine_logger: Logger
var _suppressed_native_messages: Array[String] = []

func _init() -> void:
	_register_engine_logger()

func in_ready() -> void:
	_register_engine_logger()

func in_exit_tree() -> void:
	_unregister_engine_logger()

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

func log(tag_or_message: Variant, message: Variant = null) -> void:
	if message == null:
		_emit_local_log(&"", tag_or_message, LEVEL_INFO)
		return
	_emit_local_log(StringName(str(tag_or_message)), message, LEVEL_INFO)

func warning(tag_or_message: Variant, message: Variant = null) -> void:
	if message == null:
		_emit_local_log(&"", tag_or_message, LEVEL_WARN)
		return
	_emit_local_log(StringName(str(tag_or_message)), message, LEVEL_WARN)

func error(tag_or_message: Variant, message: Variant = null) -> void:
	if message == null:
		_emit_local_log(&"", tag_or_message, LEVEL_ERROR)
		return
	_emit_local_log(StringName(str(tag_or_message)), message, LEVEL_ERROR)

func exception(tag: Variant, err: Variant) -> void:
	_emit_local_log(StringName(str(tag)), err, LEVEL_ERROR)

func get_entries() -> Array[Dictionary]:
	_mutex.lock()
	var result: Array[Dictionary] = []
	for entry in _entries:
		result.append(entry.duplicate(true))
	_mutex.unlock()
	return result

func get_revision() -> int:
	_mutex.lock()
	var revision := _revision
	_mutex.unlock()
	return revision

func clear_entries() -> void:
	_mutex.lock()
	_entries.clear()
	_revision += 1
	_mutex.unlock()

func _emit_local_log(tag: StringName, message: Variant, level: String) -> void:
	if not _enabled:
		return
	if not tag.is_empty() and not is_tag_enabled(tag):
		return
	if not _is_level_enabled(level):
		return

	var timestamp := _timestamp()
	var tag_text := String(tag)
	var message_text := str(message)
	var text := _compose_text(timestamp, tag_text, message_text)
	_append_entry(timestamp, tag_text, level, message_text, text)
	_suppress_native_once(message_text)

	match level:
		LEVEL_WARN:
			push_warning(message_text)
		LEVEL_ERROR:
			push_error(message_text)
		_:
			print(text)

func _capture_native_message(message: String, is_error: bool) -> void:
	if not _enabled:
		return
	var normalized_message := message.strip_edges()
	if normalized_message.is_empty():
		return
	if _consume_suppressed_native_message(normalized_message):
		return

	var level := LEVEL_ERROR if is_error else LEVEL_INFO
	if not _is_level_enabled(level):
		return

	var timestamp := _timestamp()
	var text := "[%s] %s" % [timestamp, normalized_message]
	_append_entry(timestamp, "", level, normalized_message, text)

func _capture_native_error(
	_function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	if not _enabled:
		return

	var message_text := rationale.strip_edges()
	if message_text.is_empty():
		message_text = code.strip_edges()
	if message_text.is_empty():
		return
	if _consume_suppressed_native_message(message_text):
		return

	var level := LEVEL_WARN
	if int(error_type) != Logger.ERROR_TYPE_WARNING:
		level = LEVEL_ERROR
	if not _is_level_enabled(level):
		return

	var location := ""
	if not file.is_empty():
		location = "%s:%d" % [file, line]
	var timestamp := _timestamp()
	var text := "[%s][%s] %s" % [timestamp, level, message_text]
	if not location.is_empty():
		text += " (%s)" % location
	_append_entry(timestamp, "", level, message_text, text)

func _append_entry(time_text: String, tag_text: String, level: String, message_text: String, text: String) -> void:
	_mutex.lock()
	_entries.append(
		{
			"time": time_text,
			"tag": tag_text,
			"level": level,
			"message": message_text,
			"text": text,
		}
	)
	while _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)
	_revision += 1
	_mutex.unlock()

func _is_level_enabled(level: String) -> bool:
	match level:
		LEVEL_WARN:
			return _warning_enabled
		LEVEL_ERROR:
			return _error_enabled
		_:
			return _info_enabled

func _compose_text(time_text: String, tag_text: String, message_text: String) -> String:
	var prefix := "[%s]" % time_text
	if not tag_text.is_empty():
		prefix += "[%s]" % tag_text
	return "%s %s" % [prefix, message_text]

func _suppress_native_once(message_text: String) -> void:
	_mutex.lock()
	_suppressed_native_messages.append(message_text)
	_mutex.unlock()

func _consume_suppressed_native_message(message_text: String) -> bool:
	_mutex.lock()
	var suppressed_index := _suppressed_native_messages.find(message_text)
	if suppressed_index >= 0:
		_suppressed_native_messages.remove_at(suppressed_index)
		_mutex.unlock()
		return true
	_mutex.unlock()
	return false

func _register_engine_logger() -> void:
	if _engine_logger != null:
		return
	_engine_logger = DXEngineLogger.new(self)
	OS.add_logger(_engine_logger)

func _unregister_engine_logger() -> void:
	if _engine_logger == null:
		return
	OS.remove_logger(_engine_logger)
	_engine_logger = null

func _timestamp() -> String:
	if dx != null and dx.time != null:
		return dx.time.now().format("yyyy-MM-dd HH:mm:ss")
	return Time.get_datetime_string_from_system(true, true)
