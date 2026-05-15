class_name DX_TimeManager
extends RefCounted

const DX_DateTimeClass := preload("res://dx/runtime/scripts/managers/time/datetime.gd")
const DX_TimeUtilityClass := preload("res://dx/runtime/scripts/utility/time_utility.gd")

var dx: Node
var _base_time_scale := 1.0
var _debug_time_scale_enabled := false
var _debug_time_scale := 1.0
var _debug_time_offset_seconds := 0
var _cached_unix := 0

func in_ready() -> void:
	_base_time_scale = Engine.time_scale
	_refresh_cached_unix()
	_apply_time_scale()

func in_process(_delta: float) -> void:
	_refresh_cached_unix()

func now() -> DX_DateTime:
	return DX_DateTimeClass.from_unix_timestamp(now_unix())

func now_unix() -> int:
	if _cached_unix <= 0:
		_refresh_cached_unix()
	return _cached_unix

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
	_refresh_cached_unix()

func get_debug_time_offset_seconds() -> int:
	return _debug_time_offset_seconds

func _refresh_cached_unix() -> void:
	_cached_unix = DX_TimeUtilityClass.now_unix(_debug_time_offset_seconds)

func _apply_time_scale() -> void:
	Engine.time_scale = _debug_time_scale if _debug_time_scale_enabled else _base_time_scale
