class_name MusicAppLocalScanView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const SCAN_FOLDER_ROW_SCENE := preload(MusicAppScriptPathsType.LOCAL_SCAN_FOLDER_ROW)

var _controller: MusicAppShowcaseController
var _local_scan_controller: MusicAppLocalScanController
var _is_bound := false
var _root_path := ""
var _current_path := ""
var _selected_paths := {}
var _current_entries: Array[Dictionary] = []
var _folder_rows: Array[MusicAppLocalMusicScanFolderRow] = []

@onready var scan_back_button: Button = %ScanBackButton
@onready var scan_path_label: Label = %ScanPathLabel
@onready var scan_select_all_button: Button = %ScanSelectAllButton
@onready var scan_folder_list: VBoxContainer = %ScanFolderList
@onready var scan_hint_label: Label = %ScanHintLabel
@onready var scan_folder_bottom_space: Control = %ScanFolderBottomSpace
@onready var start_scan_button: Button = %StartScanButton

## 注入本地扫描控制器并完成首次界面绑定。
func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_local_scan_controller = MusicAppLocalScanController.new(controller)
	bind()
	refresh()

## 绑定扫描页固定按钮事件。
func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	scan_back_button.pressed.connect(navigate_back)
	scan_select_all_button.pressed.connect(_toggle_select_all)
	start_scan_button.pressed.connect(_start_scan)

## 根据当前路径刷新目录列表、路径文案和选中态。
func refresh() -> void:
	if _controller == null:
		return
	if _root_path.is_empty():
		_root_path = _local_scan_controller.get_scan_root_path()
	if _current_path.is_empty():
		_current_path = _root_path

	_current_entries = _local_scan_controller.list_scan_directories(_current_path)
	scan_path_label.text = _local_scan_controller.get_scan_display_path(_current_path)
	scan_hint_label.visible = _current_entries.is_empty()
	_update_select_all_button_text()

	_sync_rows(_current_entries.size())
	for index in _folder_rows.size():
		var entry: Dictionary = _current_entries[index]
		var entry_path := str(entry.get("path", ""))
		var entry_name := str(entry.get("name", ""))
		_folder_rows[index].configure(entry_path, entry_name, _selected_paths.has(entry_path))

func open_page() -> void:
	if _root_path.is_empty():
		_root_path = _local_scan_controller.get_scan_root_path()
	_selected_paths.clear()
	_current_path = _root_path
	refresh()

func close_page() -> void:
	close_popup()

func navigate_back() -> void:
	if _current_path == _root_path:
		close_page()
		return

	_current_path = _local_scan_controller.get_scan_parent_path(_current_path, _root_path)
	refresh()

## 按目录项数量增删文件夹行节点，并维持底部占位顺序。
func _sync_rows(target_size: int) -> void:
	while _folder_rows.size() < target_size:
		var row := SCAN_FOLDER_ROW_SCENE.instantiate() as MusicAppLocalMusicScanFolderRow
		scan_folder_list.add_child(row)
		scan_folder_list.move_child(row, scan_folder_bottom_space.get_index())
		row.open_requested.connect(_open_folder)
		row.selection_toggled.connect(_toggle_path_selection)
		_folder_rows.append(row)

	while _folder_rows.size() > target_size:
		var row: MusicAppLocalMusicScanFolderRow = _folder_rows.pop_back()
		row.queue_free()

func _open_folder(path: String) -> void:
	if path.is_empty():
		return
	_current_path = path
	refresh()

func _toggle_path_selection(path: String, selected: bool) -> void:
	if selected:
		_selected_paths[path] = true
	else:
		_selected_paths.erase(path)
	_update_select_all_button_text()

func _toggle_select_all() -> void:
	var select_all := not _are_all_current_selected()
	for entry in _current_entries:
		var path := str(entry.get("path", ""))
		if select_all:
			_selected_paths[path] = true
		else:
			_selected_paths.erase(path)
	refresh()

## 判断当前列表中的目录是否已经全部被勾选。
func _are_all_current_selected() -> bool:
	if _current_entries.is_empty():
		return false
	for entry in _current_entries:
		if not _selected_paths.has(str(entry.get("path", ""))):
			return false
	return true

## 根据当前勾选状态更新“全选/取消全选”按钮文案。
func _update_select_all_button_text() -> void:
	scan_select_all_button.text = tr("music_app.scan.unselect_all") if _are_all_current_selected() and not _current_entries.is_empty() else tr("music_app.scan.select_all")

## 扫描所选目录并将新发现的音频文件导入全局曲库。
func _start_scan() -> void:
	var target_paths: Array[String] = []
	for path in _selected_paths.keys():
		target_paths.append(str(path))
	if target_paths.is_empty():
		if _local_scan_controller.is_scan_virtual_root(_current_path):
			_local_scan_controller.show_common_alert(
				tr("music_app.scan.select_folder_title"),
				tr("music_app.scan.select_folder_message")
			)
			return
		target_paths.append(_current_path)

	var imported_count := _local_scan_controller.scan_local_music_directories(target_paths)
	_selected_paths.clear()

	if imported_count <= 0:
		_local_scan_controller.show_common_alert(
			tr("music_app.scan.not_found_title"),
			tr("music_app.scan.not_found_message")
		)
		refresh()
		return

	_local_scan_controller.show_common_alert(
		tr("music_app.scan.complete_title"),
		tr("music_app.scan.complete_message").format({"count": imported_count})
	)
	close_page()
