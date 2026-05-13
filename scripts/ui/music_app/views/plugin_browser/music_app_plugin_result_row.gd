class_name MusicAppPluginResultRow
extends Control

const ACTIVE_TEXT := Color(0.968627, 0.968627, 0.972549, 1)
const MUTED_TEXT := Color(0.643137, 0.65098, 0.690196, 1)

signal play_requested(index: int)

var _index := -1

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var source_label: Label = %SourceLabel
@onready var more_label: Label = %MoreLabel
@onready var hit_button: Button = %HitButton

func _ready() -> void:
	title_label.add_theme_color_override("font_color", ACTIVE_TEXT)
	subtitle_label.add_theme_color_override("font_color", MUTED_TEXT)
	source_label.add_theme_color_override("font_color", Color(0.92549, 0.929412, 0.94902, 1))
	more_label.add_theme_color_override("font_color", MUTED_TEXT)
	if not hit_button.pressed.is_connected(_on_pressed):
		hit_button.pressed.connect(_on_pressed)

func configure(index: int, title: String, subtitle: String, source: String) -> void:
	_index = index
	title_label.text = title
	subtitle_label.text = subtitle
	source_label.text = source

func _on_pressed() -> void:
	if _index < 0:
		return
	play_requested.emit(_index)
