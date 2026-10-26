class_name MusicAppRingProgress
extends Control

@export_range(0.0, 1.0, 0.001) var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

@export var track_color := Color(1, 1, 1, 0.2):
	set(value):
		track_color = value
		queue_redraw()

@export var progress_color := Color(1, 1, 1, 1):
	set(value):
		progress_color = value
		queue_redraw()

@export_range(1.0, 16.0, 0.5) var ring_width := 2.5:
	set(value):
		ring_width = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var radius: float = min(size.x, size.y) * 0.5 - ring_width
	if radius <= 0.0:
		return

	var center: Vector2 = size * 0.5
	draw_arc(center, radius, 0.0, TAU, 64, track_color, ring_width, true)

	if progress <= 0.0:
		return

	var start_angle := -PI * 0.5
	var end_angle := start_angle + TAU * progress
	draw_arc(center, radius, start_angle, end_angle, 64, progress_color, ring_width, true)
