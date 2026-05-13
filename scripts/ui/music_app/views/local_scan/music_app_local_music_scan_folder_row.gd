class_name MusicAppLocalMusicScanFolderRow
extends Panel

const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")

signal open_requested(path: String)
signal selection_toggled(path: String, selected: bool)

var _is_bound := false
var _folder_path := ""
var _selected := false

var _folder_button: Button
var _toggle_button: Button

func setup() -> void:
	if _is_bound:
		return
	_is_bound = true

	_folder_button = $Margin/Row/FolderButton
	_toggle_button = $Margin/Row/ToggleButton

	_folder_button.pressed.connect(_on_open_pressed)
	_toggle_button.pressed.connect(_on_toggle_pressed)

func configure(folder_path: String, display_name: String, selected: bool) -> void:
	setup()
	_folder_path = folder_path
	_selected = selected
	_folder_button.text = display_name
	MusicAppIconsType.apply_icon_button(_folder_button, MusicAppIconsType.FOLDER, true, false)
	MusicAppIconsType.apply_icon_button(
		_toggle_button,
		MusicAppIconsType.CHECKED if _selected else MusicAppIconsType.UNCHECKED
	)

func _on_open_pressed() -> void:
	if _folder_path.is_empty():
		return
	open_requested.emit(_folder_path)

func _on_toggle_pressed() -> void:
	if _folder_path.is_empty():
		return
	_selected = not _selected
	MusicAppIconsType.apply_icon_button(
		_toggle_button,
		MusicAppIconsType.CHECKED if _selected else MusicAppIconsType.UNCHECKED
	)
	selection_toggled.emit(_folder_path, _selected)
