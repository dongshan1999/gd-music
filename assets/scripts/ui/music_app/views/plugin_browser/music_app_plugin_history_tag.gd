class_name MusicAppPluginHistoryTag
extends PanelContainer

signal pressed(text: String)
signal remove_requested(text: String)

var _text := ""

@onready var hit_button: Button = %HitButton
@onready var remove_button: Button = %RemoveButton

func _ready() -> void:
	if not hit_button.pressed.is_connected(_on_hit_pressed):
		hit_button.pressed.connect(_on_hit_pressed)
	if not remove_button.pressed.is_connected(_on_remove_pressed):
		remove_button.pressed.connect(_on_remove_pressed)

func configure(text: String) -> void:
	_text = text
	hit_button.text = text

func _on_hit_pressed() -> void:
	if _text.is_empty():
		return
	pressed.emit(_text)

func _on_remove_pressed() -> void:
	if _text.is_empty():
		return
	remove_requested.emit(_text)
