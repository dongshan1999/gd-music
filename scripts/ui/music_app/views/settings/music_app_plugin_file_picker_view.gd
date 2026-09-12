class_name MusicAppPluginFilePickerView
extends "res://scripts/ui/music_app/music_app_page.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const PickerControllerScript := preload("res://scripts/ui/music_app/controllers/music_app_plugin_file_picker_controller.gd")
const PICKER_ROW_SCENE := preload("res://scenes/ui/music_app/settings/music_app_plugin_file_picker_row.tscn")

signal plugin_selected(path: String)

var _controller: MusicAppShowcaseController
var _picker_controller
var _is_bound := false
var _root_path := ""
var _current_path := ""
var _current_entries: Array[Dictionary] = []
var _entry_rows: Array = []

@onready var back_button: Button = %PluginPickerBackButton
@onready var path_label: Label = %PluginPickerPathLabel
@onready var entry_list: VBoxContainer = %PluginPickerEntryList
@onready var hint_label: Label = %PluginPickerHintLabel
@onready var bottom_space: Control = %PluginPickerBottomSpace

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_picker_controller = PickerControllerScript.new(controller)
	_bind()
	_open_root()

func on_popup_shown() -> void:
	_open_root()

func _bind() -> void:
	if _is_bound:
		return
	_is_bound = true
	back_button.pressed.connect(_on_back_pressed)

func _open_root() -> void:
	if _picker_controller == null:
		return
	_root_path = _picker_controller.get_scan_root_path()
	_current_path = _root_path
	_refresh()

func _refresh() -> void:
	if _picker_controller == null:
		return
	_current_entries = _picker_controller.list_directory_entries(_current_path)
	path_label.text = _picker_controller.get_scan_display_path(_current_path)
	hint_label.visible = _current_entries.is_empty()
	_sync_rows(_current_entries.size())

	for index in _entry_rows.size():
		var entry: Dictionary = _current_entries[index]
		_entry_rows[index].configure(
			str(entry.get("path", "")),
			str(entry.get("name", "")),
			bool(entry.get("is_dir", false))
		)

func _sync_rows(target_size: int) -> void:
	while _entry_rows.size() < target_size:
		var row = PICKER_ROW_SCENE.instantiate()
		entry_list.add_child(row)
		entry_list.move_child(row, bottom_space.get_index())
		row.open_requested.connect(_open_directory)
		row.pick_requested.connect(_pick_file)
		_entry_rows.append(row)

	while _entry_rows.size() > target_size:
		var row = _entry_rows.pop_back()
		row.queue_free()

func _open_directory(path: String) -> void:
	if path.is_empty():
		return
	_current_path = path
	_refresh()

func _pick_file(path: String) -> void:
	if path.is_empty():
		return
	plugin_selected.emit(path)
	close_popup()

func _on_back_pressed() -> void:
	if _picker_controller == null:
		close_popup()
		return
	if _current_path == _root_path:
		close_popup()
		return
	_current_path = _picker_controller.get_scan_parent_path(_current_path, _root_path)
	_refresh()
