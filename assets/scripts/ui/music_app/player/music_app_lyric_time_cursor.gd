class_name MusicAppLyricTimeCursor
extends Control

@export var dash_length := 6.0
@export var dash_gap := 6.0
@export var line_width := 1.0
@export var line_color := Color(1, 1, 1, 0.42)

@onready var time_label: Label = %CursorTimeLabel

func set_timestamp(seconds: int) -> void:
	if time_label == null:
		return
	if seconds < 0:
		time_label.text = ""
		return
	var minutes := int(float(seconds) / 60.0)
	time_label.text = "%02d:%02d" % [minutes, seconds % 60]

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var y := size.y * 0.5
	var next_x := 0.0
	while next_x < size.x:
		var end_x := minf(next_x + dash_length, size.x)
		draw_line(Vector2(next_x, y), Vector2(end_x, y), line_color, line_width, true)
		next_x = end_x + dash_gap
