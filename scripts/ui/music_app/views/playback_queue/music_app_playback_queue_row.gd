class_name MusicAppPlaybackQueueRow
extends Control

const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")

signal play_requested(queue_index: int)
signal remove_requested(queue_index: int)

const ACTIVE_TEXT := Color(0.411765, 0.756863, 1.0, 1.0)
const PRIMARY_TEXT := Color(0.968627, 0.968627, 0.972549, 1.0)
const MUTED_TEXT := Color(0.643137, 0.65098, 0.690196, 1.0)

var _is_bound := false
var _queue_index := -1

@onready var current_icon_rect: TextureRect = %CurrentIconRect
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var remove_button: Button = %RemoveButton
@onready var open_button: Button = %OpenButton

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true
	current_icon_rect.self_modulate = ACTIVE_TEXT

	remove_button.pressed.connect(_on_remove_pressed)
	open_button.pressed.connect(_on_open_pressed)

func configure(
	queue_index: int,
	title: String,
	subtitle: String,
	source: String,
	is_current: bool
) -> void:
	setup()
	_queue_index = queue_index
	current_icon_rect.visible = is_current
	title_label.text = title
	subtitle_label.text = _format_subtitle(subtitle, source)
	title_label.add_theme_color_override(
		"font_color",
		ACTIVE_TEXT if is_current else PRIMARY_TEXT
	)
	subtitle_label.add_theme_color_override("font_color", MUTED_TEXT)

func _on_open_pressed() -> void:
	if _queue_index < 0:
		return
	play_requested.emit(_queue_index)

func _on_remove_pressed() -> void:
	if _queue_index < 0:
		return
	remove_requested.emit(_queue_index)

func _format_subtitle(subtitle: String, source: String) -> String:
	var normalized_subtitle := subtitle.strip_edges()
	var normalized_source := source.strip_edges()
	if normalized_source.is_empty() or normalized_source == normalized_subtitle:
		return normalized_subtitle
	if normalized_subtitle.is_empty():
		return normalized_source
	return "%s · %s" % [normalized_subtitle, normalized_source]
