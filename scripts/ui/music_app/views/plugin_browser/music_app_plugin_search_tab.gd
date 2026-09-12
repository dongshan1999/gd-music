class_name MusicAppPluginSearchTab
extends Control

signal selected(id: String)

const ACTIVE_COLOR := Color(1, 1, 1, 1)
const INACTIVE_COLOR := Color(0.65, 0.65, 0.69, 1)

var _id := ""

@onready var title_label: Label = %TitleLabel
@onready var underline: ColorRect = %Underline
@onready var hit_button: Button = %HitButton

func _ready() -> void:
	if not hit_button.pressed.is_connected(_on_pressed):
		hit_button.pressed.connect(_on_pressed)

func configure(id: String, text: String, is_active: bool) -> void:
	_id = id
	title_label.text = text
	title_label.add_theme_color_override(
		"font_color",
		ACTIVE_COLOR if is_active else INACTIVE_COLOR
	)
	underline.visible = false
	hit_button.flat = false
	hit_button.add_theme_stylebox_override("normal", hit_button.get_theme_stylebox(
		"selected" if is_active else "hover", "SegmentButton"
	))

func _on_pressed() -> void:
	if _id.is_empty():
		return
	selected.emit(_id)
