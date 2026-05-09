class_name MusicAppLocalMusicView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppUiSymbolsType := preload("res://scripts/constants/music_app_ui_symbols.gd")
const LOCAL_MUSIC_ROW_SCENE := preload(MusicAppScriptPathsType.LOCAL_MUSIC_ROW)

var _controller: MusicAppShowcaseController
var _local_music_controller: MusicAppLocalMusicController = MusicAppLocalMusicController.new()
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

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	local_music_back_button.pressed.connect(close_page)
	local_music_search_button.pressed.connect(_show_stub_search)
	local_music_more_button.pressed.connect(_toggle_menu)
	local_music_menu_scrim.pressed.connect(_hide_menu)
	scan_music_button.pressed.connect(_open_scan_page)
	edit_music_button.pressed.connect(_show_stub_edit)
	download_list_button.pressed.connect(_show_stub_download)
	if not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func refresh() -> void:
	if _controller == null:
		return

	local_music_back_button.text = MusicAppUiSymbolsType.BACK
	local_music_search_button.text = MusicAppUiSymbolsType.SEARCH
	local_music_more_button.text = MusicAppUiSymbolsType.MORE
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

func _hide_menu() -> void:
	local_music_menu_panel.visible = false
	local_music_menu_scrim.visible = false

func _open_scan_page() -> void:
	_hide_menu()
	_local_music_controller.open_scan_page()

func _show_stub_search() -> void:
	_local_music_controller.open_plugin_browser()

func _show_stub_edit() -> void:
	_hide_menu()
	_local_music_controller.show_edit_placeholder()

func _show_stub_download() -> void:
	_hide_menu()
	_local_music_controller.show_download_placeholder()

func _show_row_menu(_track_index: int) -> void:
	_toggle_menu()
