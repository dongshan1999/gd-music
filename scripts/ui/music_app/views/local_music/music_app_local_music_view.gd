class_name MusicAppLocalMusicView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const LOCAL_MUSIC_ROW_SCENE := preload(MusicAppScriptPathsType.LOCAL_MUSIC_ROW)
const DEBUG_TAG := "MusicLocalImport"

var _controller: MusicAppShowcaseController
var _local_music_controller: MusicAppLocalMusicController
var _is_bound := false
var _visible_track_ids: Array[String] = []
var _folder_chip_buttons: Array[Button] = []

@onready var local_music_back_button: Button = %LocalMusicBackButton
@onready var local_music_title_label: Label = %LocalMusicTitleLabel
@onready var local_music_search_button: Button = %LocalMusicSearchButton
@onready var local_music_more_button: Button = %LocalMusicMoreButton
@onready var local_folder_panel: PanelContainer = %LocalFolderPanel
@onready var local_folder_chips: FlowContainer = %LocalFolderChips
@onready var local_music_list: VBoxContainer = %LocalMusicList
@onready var local_music_empty_label: Label = %LocalMusicEmptyLabel
@onready var local_music_bottom_space: Control = %LocalMusicBottomSpace
@onready var local_music_menu_scrim: Button = %LocalMusicMenuScrim
@onready var local_music_menu_panel: Panel = %LocalMusicMenuPanel
@onready var scan_music_button: Button = %ScanMusicButton

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

## 刷新本地音乐列表、空态文案与当前可见曲目索引。
func refresh() -> void:
	if _controller == null:
		return
	local_music_empty_label.text = "%s\n%s" % [
		tr("music_app.local.empty_line1"),
		tr("music_app.local.empty_line2")
	]
	_refresh_folder_chips()

	_visible_track_ids = _local_music_controller.get_local_track_ids()
	var track_count := _visible_track_ids.size()
	_sync_rows(track_count)
	local_music_empty_label.visible = track_count == 0

	for index in _rows.size():
		var track_id := _visible_track_ids[index]
		_rows[index].configure(index, _local_music_controller.get_track(track_id))

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
		_rows.append(row)

	while _rows.size() > target_size:
		var row: MusicAppLocalMusicRow = _rows.pop_back()
		row.queue_free()

func _play_track(slot_index: int) -> void:
	_hide_menu()
	if slot_index < 0 or slot_index >= _visible_track_ids.size():
		return
	_local_music_controller.play_local_track_list(_visible_track_ids, slot_index)

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
	_debug_import("local music scan button pressed")
	_local_music_controller.open_native_import(Callable(self, "_on_native_import_finished"))

func _on_native_import_finished() -> void:
	_debug_import("local music import callback received")
	refresh()

func _open_plugin_search() -> void:
	_local_music_controller.open_plugin_browser()


func _refresh_folder_chips() -> void:
	for button in _folder_chip_buttons:
		if button != null and button.get_parent() == local_folder_chips:
			local_folder_chips.remove_child(button)
			button.queue_free()
	_folder_chip_buttons.clear()

	var folder_paths := _local_music_controller.get_local_folder_paths()
	local_folder_panel.visible = not folder_paths.is_empty()
	_debug_import("refresh local folder chips", {
		"folders": folder_paths,
		"visible": local_folder_panel.visible
	})
	for folder_path in folder_paths:
		var chip := _create_folder_chip(folder_path)
		local_folder_chips.add_child(chip)
		_folder_chip_buttons.append(chip)

func _create_folder_chip(folder_path: String) -> Button:
	var button := Button.new()
	button.text = "%s  ×" % _local_music_controller.get_folder_display_name(folder_path)
	button.tooltip_text = folder_path
	button.custom_minimum_size = Vector2(0, 30)
	button.flat = false
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color(0.968627, 0.968627, 0.972549, 1.0))
	button.add_theme_font_size_override("font_size", 12)
	var normal_style := _make_folder_chip_style(Color(0.235294, 0.235294, 0.243137, 1.0))
	var hover_style := _make_folder_chip_style(Color(0.29, 0.30, 0.33, 1.0))
	var pressed_style := _make_folder_chip_style(Color(0.20, 0.21, 0.24, 1.0))
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", normal_style)
	button.pressed.connect(_remove_local_folder.bind(folder_path))
	return button

func _make_folder_chip_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func _remove_local_folder(folder_path: String) -> void:
	_local_music_controller.remove_local_folder(folder_path)
	refresh()

func _debug_import(message: String, payload: Variant = null) -> void:
	var text := message if payload == null else "%s | %s" % [message, str(payload)]
	if DX != null and DX.logger != null:
		DX.logger.log(DEBUG_TAG, text)
	else:
		print("[%s] %s" % [DEBUG_TAG, text])
