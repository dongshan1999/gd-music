class_name MusicAppLocalMusicView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const LOCAL_MUSIC_ROW_SCENE := preload(MusicAppScriptPathsType.LOCAL_MUSIC_ROW)

var _controller: MusicAppShowcaseController
var _local_music_controller: MusicAppLocalMusicController
var _is_bound := false
var _visible_track_indices: Array[int] = []

@onready var local_music_back_button: Button = %LocalMusicBackButton
@onready var local_music_title_label: Label = %LocalMusicTitleLabel
@onready var local_music_search_button: Button = %LocalMusicSearchButton
@onready var local_music_more_button: Button = %LocalMusicMoreButton
@onready var local_music_list: VBoxContainer = %LocalMusicList
@onready var local_music_empty_label: Label = %LocalMusicEmptyLabel
@onready var local_music_bottom_space: Control = %LocalMusicBottomSpace
@onready var local_music_menu_scrim: Button = %LocalMusicMenuScrim
@onready var local_music_menu_panel: Panel = %LocalMusicMenuPanel
@onready var scan_music_button: Button = %ScanMusicButton
@onready var edit_music_button: Button = %EditMusicButton
@onready var download_list_button: Button = %DownloadListButton

var _rows: Array[MusicAppLocalMusicRow] = []

## 注入本地音乐页控制器并完成首次绑定与渲染。
func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_local_music_controller = MusicAppLocalMusicController.new(controller)
	bind()
	refresh()

## 绑定本地音乐页固定按钮事件，避免重复连接。
func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	local_music_back_button.pressed.connect(close_page)
	local_music_search_button.pressed.connect(_open_plugin_search)
	local_music_more_button.pressed.connect(_toggle_menu)
	local_music_menu_scrim.pressed.connect(_hide_menu)
	scan_music_button.pressed.connect(_open_native_import)
	edit_music_button.pressed.connect(_show_stub_edit)
	download_list_button.pressed.connect(_show_stub_download)

## 刷新本地音乐列表、空态文案与当前可见曲目索引。
func refresh() -> void:
	if _controller == null:
		return
	local_music_empty_label.text = "%s\n%s" % [
		tr("music_app.local.empty_line1"),
		tr("music_app.local.empty_line2")
	]

	_visible_track_indices = _local_music_controller.get_local_track_indices()
	var track_count := _visible_track_indices.size()
	_sync_rows(track_count)
	local_music_empty_label.visible = track_count == 0

	for index in _rows.size():
		var track_index := _visible_track_indices[index]
		_rows[index].configure(index, _local_music_controller.get_track(track_index))

func open_page() -> void:
	_hide_menu()
	refresh()

func close_page() -> void:
	_hide_menu()
	close_popup()

## 根据目标数量增删本地音乐行节点，并维持底部占位结构。
func _sync_rows(target_size: int) -> void:
	while _rows.size() < target_size:
		var row := LOCAL_MUSIC_ROW_SCENE.instantiate() as MusicAppLocalMusicRow
		local_music_list.add_child(row)
		local_music_list.move_child(row, local_music_bottom_space.get_index())
		row.play_requested.connect(_play_track)
		row.more_requested.connect(_show_row_menu)
		_rows.append(row)

	while _rows.size() > target_size:
		var row: MusicAppLocalMusicRow = _rows.pop_back()
		row.queue_free()

func _play_track(track_index: int) -> void:
	_hide_menu()
	if track_index < 0 or track_index >= _visible_track_indices.size():
		return
	_local_music_controller.play_local_track_list(_visible_track_indices, track_index)

func _toggle_menu() -> void:
	var next_visible := not local_music_menu_panel.visible
	local_music_menu_panel.visible = next_visible
	local_music_menu_scrim.visible = next_visible

## 隐藏本地音乐页右上角操作菜单。
func _hide_menu() -> void:
	local_music_menu_panel.visible = false
	local_music_menu_scrim.visible = false

func _open_native_import() -> void:
	_hide_menu()
	_local_music_controller.open_native_import(Callable(self, "_on_native_import_finished"))

func _on_native_import_finished() -> void:
	refresh()

func _open_plugin_search() -> void:
	_local_music_controller.open_plugin_browser()

func _show_stub_edit() -> void:
	_hide_menu()
	_local_music_controller.show_edit_placeholder()

func _show_stub_download() -> void:
	_hide_menu()
	_local_music_controller.show_download_placeholder()

func _show_row_menu(_track_index: int) -> void:
	_toggle_menu()
