class_name DX_TimeUtility
extends RefCounted

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

static func now_unix(offset_seconds: int = 0) -> int:
	return int(Time.get_unix_time_from_system()) + offset_seconds

static func parse_unix(value: String) -> int:
	var iso_value := value.strip_edges()
	if iso_value.ends_with("Z"):
		iso_value = iso_value.left(iso_value.length() - 1)
	return int(Time.get_unix_time_from_datetime_string(iso_value))

static func datetime_dict_from_unix(timestamp: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(timestamp)

static func unix_from_dictionary(value: Dictionary) -> int:
	return unix_from_components(
		int(value.get("year", 1)),
		int(value.get("month", 1)),
		int(value.get("day", 1)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
		int(value.get("second", 0))
	)

static func unix_from_components(
	year_value: int,
	month_value: int,
	day_value: int,
	hour_value: int = 0,
	minute_value: int = 0,
	second_value: int = 0
) -> int:
	assert(year_value >= 1, "datetime year must be >= 1.")
	assert(month_value >= 1 and month_value <= 12, "datetime month must be between 1 and 12.")
	assert(hour_value >= 0 and hour_value <= 23, "datetime hour must be between 0 and 23.")
	assert(minute_value >= 0 and minute_value <= 59, "datetime minute must be between 0 and 59.")
	assert(second_value >= 0 and second_value <= 59, "datetime second must be between 0 and 59.")
	assert(
		day_value >= 1 and day_value <= days_in_month(year_value, month_value),
		"datetime day is out of range for the current month."
	)

	return int(
		Time.get_unix_time_from_datetime_dict(
			{
				"year": year_value,
				"month": month_value,
				"day": day_value,
				"hour": hour_value,
				"minute": minute_value,
				"second": second_value
			}
		)
	)

static func start_of_day_unix(timestamp: int) -> int:
	var value := datetime_dict_from_unix(timestamp)
	return unix_from_components(
		int(value.get("year", 1)),
		int(value.get("month", 1)),
		int(value.get("day", 1))
	)

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

static func calculate_weekday(year_value: int, month_value: int, day_value: int) -> int:
	var date_string := "%04d-%02d-%02dT00:00:00" % [year_value, month_value, day_value]
	var value := Time.get_datetime_dict_from_datetime_string(date_string, true)
	return int(value.get("weekday", 0))

static func format_datetime_dict(value: Dictionary, pattern: String = DEFAULT_FORMAT) -> String:
	var result := ""
	var index := 0

	while index < pattern.length():
		var matched := false
		for token in FORMAT_TOKENS:
			if pattern.substr(index, token.length()) == token:
				result += _format_token(token, value)
				index += token.length()
				matched = true
				break
		if matched:
			continue

		result += pattern.substr(index, 1)
		index += 1

	return result

static func _format_token(token: String, value: Dictionary) -> String:
	var year_value := int(value.get("year", 1))
	var month_value := int(value.get("month", 1))
	var day_value := int(value.get("day", 1))
	var hour_value := int(value.get("hour", 0))
	var minute_value := int(value.get("minute", 0))
	var second_value := int(value.get("second", 0))
	var weekday_value := int(value.get("weekday", -1))
	if weekday_value < 0:
		weekday_value = calculate_weekday(year_value, month_value, day_value)

	match token:
		"yyyy":
			return "%04d" % year_value
		"yy":
			return "%02d" % (year_value % 100)
		"MMMM":
			return MONTH_NAMES[month_value - 1]
		"MMM":
			return MONTH_NAMES_SHORT[month_value - 1]
		"MM":
			return "%02d" % month_value
		"M":
			return str(month_value)
		"dddd":
			return WEEKDAY_NAMES[weekday_value]
		"ddd":
			return WEEKDAY_NAMES_SHORT[weekday_value]
		"dd":
			return "%02d" % day_value
		"d":
			return str(day_value)
		"HH":
			return "%02d" % hour_value
		"H":
			return str(hour_value)
		"hh":
			return "%02d" % _to_12_hour(hour_value)
		"h":
			return str(_to_12_hour(hour_value))
		"mm":
			return "%02d" % minute_value
		"m":
			return str(minute_value)
		"ss":
			return "%02d" % second_value
		"s":
			return str(second_value)
		"tt":
			return "AM" if hour_value < 12 else "PM"
		_:
			return token

static func _to_12_hour(hour_value: int) -> int:
	var hour_12 := hour_value % 12
	return 12 if hour_12 == 0 else hour_12
