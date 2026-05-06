class_name MusicAppLocalMusicScanFolderRow
extends Panel

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
	_folder_button.text = "📁 %s" % display_name
	_toggle_button.text = "[x]" if _selected else "[ ]"

func _on_open_pressed() -> void:
	if _folder_path.is_empty():
		return
	open_requested.emit(_folder_path)

func _on_toggle_pressed() -> void:
	if _folder_path.is_empty():
		return
	_selected = not _selected
	_toggle_button.text = "[x]" if _selected else "[ ]"
	selection_toggled.emit(_folder_path, _selected)
