class_name DX_DateTime
extends RefCounted

const SELF_SCRIPT := preload("res://dx/runtime/scripts/managers/time/datetime.gd")
const DX_TimeUtilityClass := preload("res://dx/runtime/scripts/utility/time_utility.gd")
const DEFAULT_FORMAT := DX_TimeUtilityClass.DEFAULT_FORMAT

var _unix_timestamp: int = 0
var _year: int = 0
var _month: int = 0
var _day: int = 0
var _hour: int = 0
var _minute: int = 0
var _second: int = 0
var _weekday: int = -1
var _is_expanded := false
var _dictionary_cache: Dictionary = {}

var year: int:
	get:
		_ensure_expanded()
		return _year

var month: int:
	get:
		_ensure_expanded()
		return _month

var day: int:
	get:
		_ensure_expanded()
		return _day

var hour: int:
	get:
		_ensure_expanded()
		return _hour

var minute: int:
	get:
		_ensure_expanded()
		return _minute

var second: int:
	get:
		_ensure_expanded()
		return _second

var weekday: int:
	get:
		_ensure_expanded()
		return _weekday

var day_of_week: int:
	get:
		return weekday

var day_of_year: int:
	get:
		_ensure_expanded()
		var total := _day
		for month_index in range(1, _month):
			total += DX_TimeUtilityClass.days_in_month(_year, month_index)
		return total

var date:
	get:
		return SELF_SCRIPT.new(DX_TimeUtilityClass.start_of_day_unix(_unix_timestamp))

var unix_timestamp: int:
	get:
		return _unix_timestamp

func _init(
	unix_timestamp_value: int = 0,
	year_value: int = 0,
	month_value: int = 0,
	day_value: int = 0,
	hour_value: int = 0,
	minute_value: int = 0,
	second_value: int = 0,
	weekday_value: int = -1,
	is_expanded_value: bool = false
):
	_unix_timestamp = unix_timestamp_value
	if is_expanded_value:
		_assign_expanded(
			year_value,
			month_value,
			day_value,
			hour_value,
			minute_value,
			second_value,
			weekday_value
		)
	elif unix_timestamp_value == 0:
		_unix_timestamp = _read_manager_unix_now()

static func now():
	return from_unix_timestamp(_read_manager_unix_now())

static func today():
	return now().date

static func from_unix_timestamp(timestamp: int):
	return SELF_SCRIPT.new(timestamp)

static func from_dictionary(value: Dictionary):
	var year_value := int(value.get("year", 1))
	var month_value := int(value.get("month", 1))
	var day_value := int(value.get("day", 1))
	var hour_value := int(value.get("hour", 0))
	var minute_value := int(value.get("minute", 0))
	var second_value := int(value.get("second", 0))
	var weekday_value := int(value.get("weekday", -1))
	var unix_timestamp_value := DX_TimeUtilityClass.unix_from_dictionary(value)
	return SELF_SCRIPT.new(
		unix_timestamp_value,
		year_value,
		month_value,
		day_value,
		hour_value,
		minute_value,
		second_value,
		weekday_value,
		true
	)

static func parse(value: String):
	return from_unix_timestamp(DX_TimeUtilityClass.parse_unix(value))

func clone():
	_ensure_expanded()
	return SELF_SCRIPT.new(
		_unix_timestamp,
		_year,
		_month,
		_day,
		_hour,
		_minute,
		_second,
		_weekday,
		true
	)

func to_unix_timestamp() -> int:
	return _unix_timestamp

func to_dictionary() -> Dictionary:
	return _get_datetime_dict().duplicate()

func to_iso_string(use_space: bool = false) -> String:
	return Time.get_datetime_string_from_datetime_dict(_get_datetime_dict(), use_space)

func format(pattern: String = DEFAULT_FORMAT) -> String:
	return DX_TimeUtilityClass.format_datetime_dict(_get_datetime_dict(), pattern)

func _to_string() -> String:
	return format()

func _assign_expanded(
	year_value: int,
	month_value: int,
	day_value: int,
	hour_value: int,
	minute_value: int,
	second_value: int,
	weekday_value: int
) -> void:
	_year = year_value
	_month = month_value
	_day = day_value
	_hour = hour_value
	_minute = minute_value
	_second = second_value
	_weekday = (
		weekday_value
		if weekday_value >= 0
		else DX_TimeUtilityClass.calculate_weekday(year_value, month_value, day_value)
	)
	_is_expanded = true
	_dictionary_cache = {}

func _ensure_expanded() -> void:
	if _is_expanded:
		return
	var value := DX_TimeUtilityClass.datetime_dict_from_unix(_unix_timestamp)
	_assign_expanded(
		int(value.get("year", 1)),
		int(value.get("month", 1)),
		int(value.get("day", 1)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
		int(value.get("second", 0)),
		int(value.get("weekday", -1))
	)

func _get_datetime_dict() -> Dictionary:
	_ensure_expanded()
	if _dictionary_cache.is_empty():
		_dictionary_cache = {
			"year": _year,
			"month": _month,
			"day": _day,
			"hour": _hour,
			"minute": _minute,
			"second": _second,
			"weekday": _weekday
		}
	return _dictionary_cache

static func _read_manager_unix_now() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return DX_TimeUtilityClass.now_unix()
	var dx_root := tree.root.get_node_or_null(^"DX")
	if dx_root == null:
		return DX_TimeUtilityClass.now_unix()
	if not dx_root.has_method("get_manager"):
		return DX_TimeUtilityClass.now_unix()
	var time_manager = dx_root.call("get_manager", &"time")
	if time_manager == null or not time_manager.has_method("now_unix"):
		return DX_TimeUtilityClass.now_unix()
	return int(time_manager.call("now_unix"))
