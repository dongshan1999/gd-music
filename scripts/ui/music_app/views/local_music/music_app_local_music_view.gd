class_name MusicAppLocalMusicView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppLibraryControllerType := preload("res://scripts/ui/music_app/controllers/music_app_library_controller.gd")
const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppLocalMusicRowType := preload("res://scripts/ui/music_app/views/local_music/music_app_local_music_row.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const LOCAL_MUSIC_ROW_SCENE := preload("res://scenes/ui/music_app/local_music_row.tscn")

var _controller: MusicAppShowcaseControllerType
var _library_controller: MusicAppLibraryControllerType = MusicAppLibraryControllerType.new()
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

var _rows: Array[MusicAppLocalMusicRowType] = []

func setup(controller: MusicAppShowcaseControllerType) -> void:
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

	local_music_back_button.text = "←"
	local_music_search_button.text = "🔎"
	local_music_more_button.text = "⋯"
	local_music_empty_label.text = "%s\n%s" % [
		tr("music_app.local.empty_line1"),
		tr("music_app.local.empty_line2")
	]

	_visible_track_indices = _library_controller.get_local_track_indices()
	var track_count := _visible_track_indices.size()
	_sync_rows(track_count)
	local_music_empty_label.visible = track_count == 0

	for index in _rows.size():
		var track_index := _visible_track_indices[index]
		_rows[index].configure(index, _library_controller.get_track(track_index))

func open_page() -> void:
	_hide_menu()
	refresh()

func close_page() -> void:
	_hide_menu()
	close_popup()

func _sync_rows(target_size: int) -> void:
	while _rows.size() < target_size:
		var row := LOCAL_MUSIC_ROW_SCENE.instantiate() as MusicAppLocalMusicRowType
		local_music_list.add_child(row)
		local_music_list.move_child(row, local_music_bottom_space.get_index())
		row.play_requested.connect(_play_track)
		row.more_requested.connect(_show_row_menu)
		_rows.append(row)

	while _rows.size() > target_size:
		var row: MusicAppLocalMusicRowType = _rows.pop_back()
		row.queue_free()

func _play_track(track_index: int) -> void:
	_hide_menu()
	if track_index < 0 or track_index >= _visible_track_indices.size():
		return
	if _library_controller.play_track_list(_visible_track_indices, track_index, true):
		_library_controller.show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)

func _toggle_menu() -> void:
	var next_visible := not local_music_menu_panel.visible
	local_music_menu_panel.visible = next_visible
	local_music_menu_scrim.visible = next_visible

func _hide_menu() -> void:
	local_music_menu_panel.visible = false
	local_music_menu_scrim.visible = false

func _open_scan_page() -> void:
	_hide_menu()
	var popup = _library_controller.show_popup(PopupRegistryType.PopupId.MUSIC_APP_LOCAL_SCAN)
	if popup != null and popup.has_method("open_page"):
		popup.open_page()

func _show_stub_search() -> void:
	_library_controller.show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLUGIN_BROWSER)

func _show_stub_edit() -> void:
	_hide_menu()
	_library_controller.show_common_alert(
		tr("music_app.local.edit_title"),
		tr("music_app.local.edit_message")
	)

func _show_stub_download() -> void:
	_hide_menu()
	_library_controller.show_common_alert(
		tr("music_app.local.download_title"),
		tr("music_app.local.download_message")
	)

func _show_row_menu(_track_index: int) -> void:
	_toggle_menu()
