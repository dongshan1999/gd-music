class_name MusicAppPluginFilePickerRow
extends Panel

const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")

signal open_requested(path: String)
signal pick_requested(path: String)

var _is_bound := false
var _entry_path := ""
var _is_directory := false

var _main_button: Button
var _action_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_main_button = $Margin/Row/MainButton
	_action_button = $Margin/Row/ActionButton

	_main_button.pressed.connect(_on_main_pressed)
	_action_button.pressed.connect(_on_action_pressed)

func configure(entry_path: String, display_name: String, is_directory: bool) -> void:
	setup()
	_entry_path = entry_path
	_is_directory = is_directory
	_main_button.text = display_name
	if _is_directory:
		MusicAppIconsType.apply_icon_button(_main_button, MusicAppIconsType.FOLDER, true, false)
		_action_button.text = "进入"
		_action_button.icon = preload("res://textures/arrow-right-end-on-rectangle.svg")
		_action_button.expand_icon = true
	else:
		MusicAppIconsType.apply_icon_button(_main_button, preload("res://textures/document-outline.svg"), true, false)
		_action_button.text = "选择"
		_action_button.icon = MusicAppIconsType.CHECKED
		_action_button.expand_icon = true

func _on_main_pressed() -> void:
	if _entry_path.is_empty():
		return
	if _is_directory:
		open_requested.emit(_entry_path)
	else:
		pick_requested.emit(_entry_path)

func _on_action_pressed() -> void:
	if _entry_path.is_empty():
		return
	if _is_directory:
		open_requested.emit(_entry_path)
	else:
		pick_requested.emit(_entry_path)
