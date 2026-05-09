class_name DX_DateTime
extends RefCounted

const SCRIPT_PATH := "res://dx/runtime/scripts/utility/datetime.gd"
const DEFAULT_FORMAT := "yyyy-MM-dd HH:mm:ss"

const WEEKDAY_NAMES := [
	"Sunday",
	"Monday",
	"Tuesday",
	"Wednesday",
	"Thursday",
	"Friday",
	"Saturday"
]

const WEEKDAY_NAMES_SHORT := [
	"Sun",
	"Mon",
	"Tue",
	"Wed",
	"Thu",
	"Fri",
	"Sat"
]

const MONTH_NAMES := [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December"
]

const MONTH_NAMES_SHORT := [
	"Jan",
	"Feb",
	"Mar",
	"Apr",
	"May",
	"Jun",
	"Jul",
	"Aug",
	"Sep",
	"Oct",
	"Nov",
	"Dec"
]

const FORMAT_TOKENS := [
	"yyyy",
	"yy",
	"MMMM",
	"MMM",
	"MM",
	"M",
	"dddd",
	"ddd",
	"dd",
	"d",
	"HH",
	"H",
	"hh",
	"h",
	"mm",
	"m",
	"ss",
	"s",
	"tt"
]

var _year: int
var _month: int
var _day: int
var _hour: int
var _minute: int
var _second: int
var _weekday: int

var year: int:
	get:
		return _year

var month: int:
	get:
		return _month

var day: int:
	get:
		return _day

var hour: int:
	get:
		return _hour

var minute: int:
	get:
		return _minute

var second: int:
	get:
		return _second

var weekday: int:
	get:
		return _weekday

var day_of_week: int:
	get:
		return _weekday

var day_of_year: int:
	get:
		return _get_day_of_year()

var date:
	get:
		return _get_date_only()

var unix_timestamp: int:
	get:
		return to_unix_timestamp()

func _init(
	year_value: int = 0,
	month_value: int = 0,
	day_value: int = 0,
	hour_value: int = 0,
	minute_value: int = 0,
	second_value: int = 0
):
	if (
		year_value == 0 and
		month_value == 0 and
		day_value == 0 and
		hour_value == 0 and
		minute_value == 0 and
		second_value == 0
	):
		_assign_from_dict(Time.get_datetime_dict_from_system())
		return

	_set_components(year_value, month_value, day_value, hour_value, minute_value, second_value)

static func now():
	return _create()

static func today():
	var current = now()
	return _create(current.year, current.month, current.day)

static func from_unix_timestamp(timestamp: int):
	return from_dictionary(Time.get_datetime_dict_from_unix_time(timestamp))

static func from_dictionary(value: Dictionary):
	return _create(
		int(value.get("year", 1)),
		int(value.get("month", 1)),
		int(value.get("day", 1)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
		int(value.get("second", 0))
	)

static func parse(value: String):
	var iso_value := value.strip_edges()
	if iso_value.ends_with("Z"):
		iso_value = iso_value.left(iso_value.length() - 1)
	return from_unix_timestamp(Time.get_unix_time_from_datetime_string(iso_value))

static func is_leap_year(year_value: int) -> bool:
	assert(year_value >= 1, "datetime year must be >= 1.")
	return (year_value % 4 == 0 and year_value % 100 != 0) or year_value % 400 == 0

static func days_in_month(year_value: int, month_value: int) -> int:
	assert(month_value >= 1 and month_value <= 12, "datetime month must be between 1 and 12.")
	if month_value == 2 and is_leap_year(year_value):
		return 29

	match month_value:
		4, 6, 9, 11:
			return 30
		_:
			return 31

func clone():
	return _create(_year, _month, _day, _hour, _minute, _second)

func get_weekday_text(short_name: bool = false) -> String:
	if _weekday < 0 or _weekday >= WEEKDAY_NAMES.size():
		return "Unknown"
	return WEEKDAY_NAMES_SHORT[_weekday] if short_name else WEEKDAY_NAMES[_weekday]

func get_total_seconds_today() -> int:
	return _hour * 3600 + _minute * 60 + _second

func get_total_minutes_today() -> int:
	return _hour * 60 + _minute

func to_unix_timestamp() -> int:
	return Time.get_unix_time_from_datetime_dict(to_dictionary())

func to_dictionary() -> Dictionary:
	return {
		"year": _year,
		"month": _month,
		"day": _day,
		"hour": _hour,
		"minute": _minute,
		"second": _second,
		"weekday": _weekday
	}

func to_iso_string(use_space: bool = false) -> String:
	return Time.get_datetime_string_from_datetime_dict(to_dictionary(), use_space)

func add_years(years: int):
	var target_year := _year + years
	assert(target_year >= 1, "datetime year must be >= 1 after add_years.")
	var target_day := mini(_day, days_in_month(target_year, _month))
	return _create(target_year, _month, target_day, _hour, _minute, _second)

func add_months(months: int):
	var absolute_month := (_year - 1) * 12 + (_month - 1) + months
	assert(absolute_month >= 0, "datetime result year must be >= 1 after add_months.")

	var target_year := int(floor(float(absolute_month) / 12.0)) + 1
	var target_month := posmod(absolute_month, 12) + 1
	var target_day := mini(_day, days_in_month(target_year, target_month))
	return _create(target_year, target_month, target_day, _hour, _minute, _second)

func add_days(days: int):
	return from_unix_timestamp(to_unix_timestamp() + days * 24 * 3600)

func add_hours(hours: int):
	return from_unix_timestamp(to_unix_timestamp() + hours * 3600)

func add_minutes(minutes: int):
	return from_unix_timestamp(to_unix_timestamp() + minutes * 60)

func add_seconds(seconds: int):
	return from_unix_timestamp(to_unix_timestamp() + seconds)

func equals(other) -> bool:
	if other == null:
		return false
	return (
		_year == other.year and
		_month == other.month and
		_day == other.day and
		_hour == other.hour and
		_minute == other.minute and
		_second == other.second
	)

func compare_to(other) -> int:
	var diff := subtract(other)
	if diff == 0:
		return 0
	return 1 if diff > 0 else -1

func is_after(other) -> bool:
	return compare_to(other) > 0

func is_before(other) -> bool:
	return compare_to(other) < 0

func subtract(other) -> int:
	return to_unix_timestamp() - other.to_unix_timestamp()

func format(pattern: String = DEFAULT_FORMAT) -> String:
	var result := ""
	var index := 0

	while index < pattern.length():
		var matched := false
		for token in FORMAT_TOKENS:
			if pattern.substr(index, token.length()) == token:
				result += _format_token(token)
				index += token.length()
				matched = true
				break
		if matched:
			continue

		result += pattern.substr(index, 1)
		index += 1

	return result

func to_short_date_string() -> String:
	return format("yyyy-MM-dd")

func to_long_date_string() -> String:
	return format("yyyy-MM-dd dddd")

func to_long_time_string() -> String:
	return format("HH:mm:ss")

func to_short_time_string() -> String:
	return format("HH:mm")

func _to_string() -> String:
	return format()

func _get_day_of_year() -> int:
	var total := _day
	for month_index in range(1, _month):
		total += days_in_month(_year, month_index)
	return total

func _get_date_only():
	return _create(_year, _month, _day)

static func _create(
	year_value: int = 0,
	month_value: int = 0,
	day_value: int = 0,
	hour_value: int = 0,
	minute_value: int = 0,
	second_value: int = 0
):
	var script = load(SCRIPT_PATH)
	return script.new(year_value, month_value, day_value, hour_value, minute_value, second_value)

func _set_components(
	year_value: int,
	month_value: int,
	day_value: int,
	hour_value: int,
	minute_value: int,
	second_value: int
) -> void:
	assert(year_value >= 1, "datetime year must be >= 1.")
	assert(month_value >= 1 and month_value <= 12, "datetime month must be between 1 and 12.")
	assert(hour_value >= 0 and hour_value <= 23, "datetime hour must be between 0 and 23.")
	assert(minute_value >= 0 and minute_value <= 59, "datetime minute must be between 0 and 59.")
	assert(second_value >= 0 and second_value <= 59, "datetime second must be between 0 and 59.")
	assert(
		day_value >= 1 and day_value <= days_in_month(year_value, month_value),
		"datetime day is out of range for the current month."
	)

	_year = year_value
	_month = month_value
	_day = day_value
	_hour = hour_value
	_minute = minute_value
	_second = second_value
	_weekday = _calculate_weekday(year_value, month_value, day_value)

func _assign_from_dict(value: Dictionary) -> void:
	_year = int(value.get("year", 1))
	_month = int(value.get("month", 1))
	_day = int(value.get("day", 1))
	_hour = int(value.get("hour", 0))
	_minute = int(value.get("minute", 0))
	_second = int(value.get("second", 0))
	_weekday = _calculate_weekday(_year, _month, _day)

func _calculate_weekday(year_value: int, month_value: int, day_value: int) -> int:
	var date_string := "%04d-%02d-%02dT00:00:00" % [year_value, month_value, day_value]
	var value := Time.get_datetime_dict_from_datetime_string(date_string, true)
	return int(value.get("weekday", 0))

func _format_token(token: String) -> String:
	match token:
		"yyyy":
			return "%04d" % _year
		"yy":
			return "%02d" % (_year % 100)
		"MMMM":
			return MONTH_NAMES[_month - 1]
		"MMM":
			return MONTH_NAMES_SHORT[_month - 1]
		"MM":
			return "%02d" % _month
		"M":
			return str(_month)
		"dddd":
			return get_weekday_text()
		"ddd":
			return get_weekday_text(true)
		"dd":
			return "%02d" % _day
		"d":
			return str(_day)
		"HH":
			return "%02d" % _hour
		"H":
			return str(_hour)
		"hh":
			return "%02d" % _get_12_hour()
		"h":
			return str(_get_12_hour())
		"mm":
			return "%02d" % _minute
		"m":
			return str(_minute)
		"ss":
			return "%02d" % _second
		"s":
			return str(_second)
		"tt":
			return "AM" if _hour < 12 else "PM"
		_:
			return token

func _get_12_hour() -> int:
	var hour_12 := _hour % 12
	return 12 if hour_12 == 0 else hour_12
