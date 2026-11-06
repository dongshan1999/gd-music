class_name MusicAppHistoryView
extends "res://assets/scripts/ui/music_app/music_app_page.gd"

## 播放历史页：顶部两个排序标签（最近播放 / 播放最多），下面是复用的虚拟滚动列表。
## 列表行只负责渲染，排序与文案格式化都在 MusicAppHistoryController 里。

const MusicAppScriptPathsType := preload("res://assets/scripts/constants/music_app_script_paths.gd")
const HISTORY_ROW_SCENE := preload(MusicAppScriptPathsType.HISTORY_ROW)
## 行高/行距与 history_row.tscn 保持一致。
const ROW_HEIGHT := 72.0
const ROW_GAP := 8.0
const ROW_STRIDE := ROW_HEIGHT + ROW_GAP
const OVERSCAN_ROWS := 4

const TAB_ACCENT_COLOR := Color(0.968627, 0.968627, 0.972549, 1.0)
const TAB_IDLE_COLOR := Color(0.643137, 0.65098, 0.690196, 1.0)

var _controller: MusicAppShowcaseController
var _history_controller: MusicAppHistoryController
var _is_bound := false
var _visible_track_ids: Array[String] = []
var _rows: Array[MusicAppHistoryRow] = []
var _first_slot := -1
var _row_pool_size := -1

@onready var history_back_button: Button = %HistoryBackButton
@onready var history_title_label: Label = %HistoryTitleLabel
@onready var history_clear_button: Button = %HistoryClearButton
@onready var history_summary_label: Label = %HistorySummaryLabel
@onready var history_recent_tab_button: Button = %HistoryRecentTabButton
@onready var history_most_played_tab_button: Button = %HistoryMostPlayedTabButton
@onready var history_scroll: ScrollContainer = %HistoryScroll
@onready var history_list: Control = %HistoryList
@onready var history_empty_panel: Control = %HistoryEmptyPanel
@onready var history_empty_title_label: Label = %HistoryEmptyTitleLabel
@onready var history_empty_hint_label: Label = %HistoryEmptyHintLabel

## 注入展示层控制器并完成首次绑定与渲染。
func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_history_controller = MusicAppHistoryController.new(controller)
	bind()
	refresh()

## 绑定固定控件；重复调用直接返回，避免信号重复连接。
func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	history_back_button.pressed.connect(close_page)
	history_clear_button.pressed.connect(_on_clear_pressed)
	history_recent_tab_button.pressed.connect(_on_tab_pressed.bind(MusicAppHistoryController.Tab.RECENT))
	history_most_played_tab_button.pressed.connect(_on_tab_pressed.bind(MusicAppHistoryController.Tab.MOST_PLAYED))
	history_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	history_scroll.resized.connect(_on_scroll_resized)

	history_title_label.text = tr("music_app.history.title")
	history_recent_tab_button.text = _history_controller.get_tab_title(MusicAppHistoryController.Tab.RECENT)
	history_most_played_tab_button.text = _history_controller.get_tab_title(MusicAppHistoryController.Tab.MOST_PLAYED)
	history_clear_button.tooltip_text = tr("music_app.history.clear_title")

## 重新取数并刷新统计、空态、标签样式与列表。
func refresh() -> void:
	if _controller == null or _history_controller == null:
		return

	history_summary_label.text = _history_controller.get_summary_text()
	history_summary_label.visible = not history_summary_label.text.is_empty()
	history_empty_title_label.text = _history_controller.get_empty_title()
	history_empty_hint_label.text = _history_controller.get_empty_hint()
	_sync_tab_styles()

	_visible_track_ids = _history_controller.get_track_ids()
	_first_slot = -1
	_row_pool_size = -1
	_refresh_visible_rows()

func open_page() -> void:
	refresh()

func close_page() -> void:
	close_popup()

func _on_tab_pressed(tab: int) -> void:
	if _history_controller == null:
		return
	if _history_controller.set_tab(tab):
		history_scroll.scroll_vertical = 0
		refresh()

func _on_clear_pressed() -> void:
	if _history_controller == null:
		return
	_history_controller.request_clear_history(Callable(self, "refresh"))

## 按当前标签页给两个标签按钮上色，选中态用实底 + 白字。
func _sync_tab_styles() -> void:
	if _history_controller == null:
		return
	var current_tab := _history_controller.get_tab()
	_apply_tab_style(history_recent_tab_button, current_tab == MusicAppHistoryController.Tab.RECENT)
	_apply_tab_style(history_most_played_tab_button, current_tab == MusicAppHistoryController.Tab.MOST_PLAYED)

func _apply_tab_style(button: Button, is_active: bool) -> void:
	var normal_style := _make_tab_style(Color(0.235294, 0.235294, 0.243137, 1.0) if is_active else Color(1, 1, 1, 0))
	var hover_style := _make_tab_style(Color(0.29, 0.30, 0.33, 1.0) if is_active else Color(1, 1, 1, 0.06))
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("focus", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", _make_tab_style(Color(0.20, 0.21, 0.24, 1.0)))
	button.add_theme_color_override("font_color", TAB_ACCENT_COLOR if is_active else TAB_IDLE_COLOR)
	button.add_theme_color_override("font_hover_color", TAB_ACCENT_COLOR)
	button.add_theme_color_override("font_pressed_color", TAB_ACCENT_COLOR)

func _make_tab_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

## 只维护视口内（含缓冲）的行节点，滚动时复用，历史几百条也不会卡。
func _refresh_visible_rows() -> void:
	var total := _visible_track_ids.size()
	history_empty_panel.visible = total == 0
	if total == 0:
		history_list.custom_minimum_size = Vector2(0, 180.0)
		history_empty_panel.position = Vector2.ZERO
		history_empty_panel.size = Vector2(history_scroll.size.x, 180.0)
		for row in _rows:
			row.visible = false
		_first_slot = -1
		_row_pool_size = -1
		return

	var viewport_height := maxf(history_scroll.size.y, ROW_STRIDE * 8.0)
	var visible_count := int(ceilf(viewport_height / ROW_STRIDE)) + OVERSCAN_ROWS * 2
	visible_count = mini(visible_count, total)
	var first_slot := int(floorf(history_scroll.scroll_vertical / ROW_STRIDE)) - OVERSCAN_ROWS
	first_slot = clampi(first_slot, 0, maxi(0, total - visible_count))
	if first_slot == _first_slot and visible_count == _row_pool_size:
		return
	_first_slot = first_slot
	_row_pool_size = visible_count

	history_list.custom_minimum_size = Vector2(0, total * ROW_STRIDE - ROW_GAP)
	var list_width := maxf(history_scroll.size.x, 0.0)
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
		row.configure(
			slot,
			_history_controller.get_row_title(track_id),
			_history_controller.get_row_subtitle(track_id),
			_history_controller.get_row_side_text(track_id)
		)

func _sync_row_pool(target_size: int) -> void:
	while _rows.size() < target_size:
		var row := HISTORY_ROW_SCENE.instantiate() as MusicAppHistoryRow
		history_list.add_child(row)
		row.play_requested.connect(_play_track)
		_rows.append(row)

	while _rows.size() > target_size:
		var row: MusicAppHistoryRow = _rows.pop_back()
		row.queue_free()

func _on_scroll_value_changed(_value: float) -> void:
	_refresh_visible_rows()

func _on_scroll_resized() -> void:
	_first_slot = -1
	_row_pool_size = -1
	_refresh_visible_rows()

func _play_track(slot_index: int) -> void:
	if _history_controller == null:
		return
	if slot_index < 0 or slot_index >= _visible_track_ids.size():
		return
	_history_controller.play_track_list(_visible_track_ids, slot_index)

## 页面重新显示时，如果期间播过歌，列表顺序会变，这里重新取一次。
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		if _is_bound:
			refresh()
