class_name MusicProgressRing
extends Control

@export var track_color: Color = Color(0.905882, 0.917647, 0.968627, 1.0)
@export var progress_color: Color = Color(0.980392, 0.45098, 0.545098, 1.0)
@export var knob_color: Color = Color(0.980392, 0.45098, 0.545098, 1.0)
@export var line_width: float = 10.0
@export var start_angle_degrees: float = 198.0
@export var arc_length_degrees: float = 228.0

var _progress: float = 0.28

@export_range(0.0, 1.0, 0.001) var progress: float:
	set(value):
		_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
	get:
		return _progress

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - line_width - 4.0
	var start_radians: float = deg_to_rad(start_angle_degrees)
	var end_radians: float = deg_to_rad(start_angle_degrees + arc_length_degrees)
	var progress_radians: float = lerpf(start_radians, end_radians, _progress)

	draw_arc(center, radius, start_radians, end_radians, 64, track_color, line_width, true)
	draw_arc(center, radius, start_radians, progress_radians, maxi(2, int(64.0 * _progress)), progress_color, line_width, true)

	var knob_position := center + Vector2(cos(progress_radians), sin(progress_radians)) * radius
	draw_circle(knob_position, line_width * 0.62, knob_color)
