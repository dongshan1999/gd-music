extends Control



@export var current_time_label: Label
@export var work_end_label: Label
@export var lunch_label: Label
@export var meal_allowance_label: Label
@export var special_time_label: Label
@export var f: Label

var work_end_time = datetime.today().add_hours(18)
var lunch_start_time = datetime.today().add_hours(12)
var lunch_end_time = datetime.today().add_hours(13)
var meal_allowance_time = datetime.today().add_hours(17).add_minutes(30)
var special_time = datetime.today().add_hours(22).add_minutes(30)

var timer := Timer.new()

func _ready() -> void:
	var value := 1.0 + (1 - 1) * 0.05
	f.text = str(value)

	add_child(timer)
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(update_all_timers)
	timer.start()

	update_all_timers()

func update_all_timers() -> void:
	var now := datetime.now()

	current_time_label.text = "Current Time: " + now.to_long_time_string()
	update_work_end_timer(now)
	update_lunch_timer(now)
	update_meal_allowance_timer(now)
	update_special_time_timer(now)

func update_work_end_timer(now) -> void:
	if now.is_before(work_end_time):
		work_end_label.text = "Time To Off Work: " + _format_duration(work_end_time.subtract(now))
	else:
		work_end_label.text = "Off work already!"

func update_lunch_timer(now) -> void:
	if now.is_before(lunch_start_time):
		lunch_label.text = "Time To Lunch: " + _format_duration(lunch_start_time.subtract(now))
	elif now.is_before(lunch_end_time):
		lunch_label.text = "Lunch Remaining: " + _format_duration(lunch_end_time.subtract(now))
	else:
		lunch_label.text = "Lunch is over"

func update_meal_allowance_timer(now) -> void:
	if now.is_before(meal_allowance_time):
		meal_allowance_label.text = "Time To Meal Allowance: " + _format_duration(meal_allowance_time.subtract(now))
	else:
		meal_allowance_label.text = "Meal allowance time!"

func update_special_time_timer(now) -> void:
	if now.is_before(special_time):
		special_time_label.text = "Time To 22:30: " + _format_duration(special_time.subtract(now))
	else:
		special_time_label.text = "22:30 passed"

func _format_duration(total_seconds: int) -> String:
	var hours := int(float(total_seconds) / 3600.0)
	var minutes := int(float(total_seconds % 3600) / 60.0)
	var seconds := total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]
