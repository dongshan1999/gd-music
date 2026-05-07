extends RefCounted
const DateTimeType := preload("res://dx/runtime/scripts/utility/datetime.gd")

var dx: Node
var _base_time_scale := 1.0
var _debug_time_scale_enabled := false
var _debug_time_scale := 1.0
var _debug_time_offset_seconds := 0

func in_ready() -> void:
	_base_time_scale = Engine.time_scale
	_apply_time_scale()

func now() -> DateTimeType:
	return DateTimeType.from_unix_timestamp(now_unix())

func today() -> DateTimeType:
	var current := now()
	return DateTimeType.new(current.year, current.month, current.day)

func utc_now() -> DateTimeType:
	return DateTimeType.from_unix_timestamp(utc_now_unix())

func from_unix_timestamp(timestamp: int) -> DateTimeType:
	return DateTimeType.from_unix_timestamp(timestamp)

func from_dictionary(value: Dictionary) -> DateTimeType:
	return DateTimeType.from_dictionary(value)

func parse(value: String) -> DateTimeType:
	return DateTimeType.parse(value)

func now_unix() -> int:
	return int(Time.get_unix_time_from_system()) + _debug_time_offset_seconds

func utc_now_unix() -> int:
	return int(Time.get_unix_time_from_system()) + _debug_time_offset_seconds

func get_time_scale() -> float:
	return Engine.time_scale

func set_time_scale(value: float) -> void:
	_base_time_scale = maxf(0.0, value)
	_apply_time_scale()

func set_debug_time_scale(value: float, enabled: bool = true, _persist: bool = true) -> void:
	_debug_time_scale = maxf(0.0, value)
	_debug_time_scale_enabled = enabled
	_apply_time_scale()

func clear_debug_time_scale(_persist: bool = true) -> void:
	_debug_time_scale_enabled = false
	_apply_time_scale()

func set_debug_time_offset_seconds(value: int, _persist: bool = true) -> void:
	_debug_time_offset_seconds = value

func get_debug_time_offset_seconds() -> int:
	return _debug_time_offset_seconds

func _apply_time_scale() -> void:
	Engine.time_scale = _debug_time_scale if _debug_time_scale_enabled else _base_time_scale
