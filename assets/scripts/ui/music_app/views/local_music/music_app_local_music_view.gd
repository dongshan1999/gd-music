class_name MusicAppLocalMusicView
extends "res://assets/scripts/ui/music_app/music_app_page.gd"

const MusicAppScriptPathsType := preload("res://assets/scripts/constants/music_app_script_paths.gd")
const LOCAL_MUSIC_ROW_SCENE := preload(MusicAppScriptPathsType.LOCAL_MUSIC_ROW)
const DEBUG_TAG := "MusicLocalImport"
## 行高与行距必须和 local_music_row.tscn / 旧 VBoxContainer 设置保持一致。
const ROW_HEIGHT := 72.0
const ROW_GAP := 8.0
const ROW_STRIDE := ROW_HEIGHT + ROW_GAP
## 视口上下各多渲染几行，滚动时避免白边。
const OVERSCAN_ROWS := 4

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
@onready var local_music_scroll: ScrollContainer = %LocalMusicScroll
@onready var local_music_list: Control = %LocalMusicList
@onready var local_music_empty_label: Label = %LocalMusicEmptyLabel
@onready var local_music_menu_scrim: Button = %LocalMusicMenuScrim
@onready var local_music_menu_panel: Panel = %LocalMusicMenuPanel
@onready var scan_music_button: Button = %ScanMusicButton

var _rows: Array[MusicAppLocalMusicRow] = []
var _first_slot := -1
var _row_pool_size := -1

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
	%ImportMusicButton.pressed.connect(_open_native_import)
	%ImportMusicButton.text = tr("music_app.ui.import")
	local_music_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	local_music_scroll.resized.connect(_on_scroll_resized)

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
	_first_slot = -1
	_row_pool_size = -1
	_refresh_visible_rows()

func open_page() -> void:
	_hide_menu()
	refresh()

func close_page() -> void:
	_hide_menu()
	close_popup()

## 只维护视口内（含少量缓冲）的行节点，滚动时复用，避免上千行全量实例化。
func _refresh_visible_rows() -> void:
	var total := _visible_track_ids.size()
	local_music_empty_label.visible = total == 0
	if total == 0:
		local_music_list.custom_minimum_size = Vector2(0, 180.0)
		local_music_empty_label.position = Vector2.ZERO
		local_music_empty_label.size = Vector2(local_music_scroll.size.x, 180.0)
		for row in _rows:
			row.visible = false
		_first_slot = -1
		_row_pool_size = -1
		return

	var viewport_height := maxf(local_music_scroll.size.y, ROW_STRIDE * 8.0)
	var visible_count := int(ceilf(viewport_height / ROW_STRIDE)) + OVERSCAN_ROWS * 2
	visible_count = mini(visible_count, total)
	var first_slot := int(floorf(local_music_scroll.scroll_vertical / ROW_STRIDE)) - OVERSCAN_ROWS
	first_slot = clampi(first_slot, 0, maxi(0, total - visible_count))
	if first_slot == _first_slot and visible_count == _row_pool_size:
		return
	_first_slot = first_slot
	_row_pool_size = visible_count

	local_music_list.custom_minimum_size = Vector2(0, total * ROW_STRIDE - ROW_GAP)
	var list_width := maxf(local_music_scroll.size.x, 0.0)
	_sync_row_pool(visible_count)
	for index in _rows.size():
		var row := _rows[index]
		var slot := first_slot + index
		if slot >= total:
			row.visible = false
			continue
		row.visible = true
		row.position = Vector2(0, slot * ROW_STRIDE)
		row.size = Vector2(list_width, ROW_HEIGHT)
		var track_id := _visible_track_ids[slot]
		row.configure(slot, _local_music_controller.get_track(track_id))

## 维持行节点池大小，池内行随滚动复用。
func _sync_row_pool(target_size: int) -> void:
	while _rows.size() < target_size:
		var row := LOCAL_MUSIC_ROW_SCENE.instantiate() as MusicAppLocalMusicRow
		local_music_list.add_child(row)
		row.play_requested.connect(_play_track)
		_rows.append(row)

	while _rows.size() > target_size:
		var row: MusicAppLocalMusicRow = _rows.pop_back()
		row.queue_free()

func _on_scroll_value_changed(_value: float) -> void:
	_refresh_visible_rows()

func _on_scroll_resized() -> void:
	_first_slot = -1
	_row_pool_size = -1
	_refresh_visible_rows()

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
	await _local_music_controller.remove_local_folder(folder_path)
	if not is_inside_tree():
		return
	refresh()

func _debug_import(message: String, payload: Variant = null) -> void:
	var text := message if payload == null else "%s | %s" % [message, str(payload)]
	if DX != null and DX.logger != null:
		DX.logger.log(DEBUG_TAG, text)
	else:
		print("[%s] %s" % [DEBUG_TAG, text])
