class_name MusicAppPlaybackQueueView
extends "res://scripts/ui/music_app/music_app_page.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const MusicAppPlaybackQueueControllerType := preload(
	MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_QUEUE_CONTROLLER
)
const MusicAppPlaybackQueueRowType := preload(
	MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_QUEUE_ROW_VIEW
)
const PLAYBACK_QUEUE_ROW_SCENE := preload(MusicAppScriptPathsType.PLAYBACK_QUEUE_ROW)

var _controller: MusicAppShowcaseController
var _queue_controller
var _is_bound := false

@onready var close_backdrop_button: Button = %CloseBackdropButton
@onready var queue_title_label: Label = %QueueTitleLabel
@onready var playback_mode_button: Button = %PlaybackModeButton
@onready var clear_queue_button: Button = %ClearQueueButton
@onready var queue_scroll: ScrollContainer = %QueueScroll
@onready var queue_list: VBoxContainer = %QueueList
@onready var empty_label: Label = %EmptyLabel

var _queue_rows: Array = []

## 注入播放队列控制器并完成首次渲染。
func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_queue_controller = MusicAppPlaybackQueueControllerType.new(controller)
	bind()
	refresh()

## 绑定播放队列弹窗上的固定按钮事件。
func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	close_backdrop_button.pressed.connect(close_popup)
	playback_mode_button.pressed.connect(_cycle_playback_mode)
	clear_queue_button.pressed.connect(_clear_queue)

## 弹窗显示后刷新列表，并滚动到当前播放项。
func on_popup_shown() -> void:
	refresh()
	call_deferred("_scroll_to_current_row")

## 根据当前播放队列刷新标题、模式按钮、空态和行列表。
func refresh() -> void:
	if _queue_controller == null:
		return

	var rows: Array[Dictionary] = _queue_controller.get_queue_rows()
	var has_tracks: bool = not rows.is_empty()

	queue_title_label.text = tr("music_app.queue.title_with_count").format(
		{"count": _queue_controller.get_queue_track_count()}
	)
	MusicAppIconsType.apply_icon_button(
		playback_mode_button,
		_queue_controller.get_playback_mode_icon(),
		true,
		false
	)
	playback_mode_button.text = tr(_queue_controller.get_playback_mode_label_key())
	playback_mode_button.disabled = not has_tracks
	clear_queue_button.text = "清空"
	MusicAppIconsType.apply_icon_button(clear_queue_button, MusicAppIconsType.PLAYLIST, true, false)
	clear_queue_button.disabled = not has_tracks

	_sync_queue_rows(rows.size())
	for row_index in rows.size():
		var row_data: Dictionary = rows[row_index]
		_queue_rows[row_index].configure(
			int(row_data.get("queue_index", row_index)),
			str(row_data.get("title", "")),
			str(row_data.get("subtitle", "")),
			str(row_data.get("source", "")),
			bool(row_data.get("is_current", false))
		)

	queue_scroll.visible = has_tracks
	empty_label.visible = not has_tracks
	empty_label.text = tr("music_app.queue.empty")

## 按目标数量增删播放队列行节点。
func _sync_queue_rows(target_size: int) -> void:
	while _queue_rows.size() < target_size:
		var row = PLAYBACK_QUEUE_ROW_SCENE.instantiate()
		queue_list.add_child(row)
		row.play_requested.connect(_play_queue_track)
		row.remove_requested.connect(_remove_queue_track)
		_queue_rows.append(row)

	while _queue_rows.size() > target_size:
		var row = _queue_rows.pop_back()
		row.queue_free()

func _cycle_playback_mode() -> void:
	if _queue_controller == null:
		return
	_queue_controller.cycle_playback_mode()
	refresh()

func _clear_queue() -> void:
	if _queue_controller == null:
		return
	_queue_controller.clear_queue()

func _play_queue_track(queue_index: int) -> void:
	if _queue_controller == null:
		return
	_queue_controller.play_queue_track(queue_index)

func _remove_queue_track(queue_index: int) -> void:
	if _queue_controller == null:
		return
	_queue_controller.remove_queue_track(queue_index)

## 将滚动位置定位到当前播放的队列项。
func _scroll_to_current_row() -> void:
	if _queue_controller == null:
		return
	var current_queue_index := int(_queue_controller.get_current_queue_index())
	if current_queue_index < 0 or current_queue_index >= _queue_rows.size():
		return
	queue_scroll.ensure_control_visible(_queue_rows[current_queue_index])
