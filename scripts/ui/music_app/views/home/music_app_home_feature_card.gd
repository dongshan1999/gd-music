class_name MusicAppHomeFeatureCard
extends Panel

signal pressed(index: int)

var _is_bound := false
var _feature_index := -1

var _icon_label: Label
var _text_label: Label
var _button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_icon_label = $Margin/VBox/IconLabel
	_text_label = $Margin/VBox/TextLabel
	_button = $OpenButton

	_button.pressed.connect(_on_pressed)

func configure(index: int, icon_text: String, display_text: String) -> void:
	setup()
	_feature_index = index
	_icon_label.text = icon_text
	_text_label.text = display_text

func _on_pressed() -> void:
	if _feature_index < 0:
		return
	pressed.emit(_feature_index)
