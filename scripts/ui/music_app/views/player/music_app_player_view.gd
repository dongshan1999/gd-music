class_name MusicAppPlayerView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const PlaybackStartedEventScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_STARTED_EVENT)
const PlaybackFinishedEventScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_FINISHED_EVENT)
const PlaybackProgressChangedEventScript := preload(
	MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_PROGRESS_CHANGED_EVENT
)

var _controller: MusicAppShowcaseController
var _player_controller: MusicAppPlayerController
var _is_bound := false
var _is_progress_dragging := false
var _active_progress_touch_index := -1

@onready var close_player_button: Button = %ClosePlayerButton
@onready var player_share_button: Button = %PlayerShareButton
@onready var now_title_label: Label = %NowTitleLabel
@onready var now_artist_label: Label = %NowArtistLabel
@onready var player_source_label: Label = %PlayerSourceLabel
@onready var cover_mark_label: Label = %CoverMarkLabel
@onready var like_button: Button = %LikeButton
@onready var player_fx_label: Label = %PlayerFxLabel
@onready var tone_button: Button = %ToneButton
@onready var speed_label: Label = %SpeedLabel
@onready var comment_button: Button = %CommentButton
@onready var player_queue_button: Button = %PlayerQueueButton
@onready var elapsed_label: Label = %ElapsedLabel
@onready var remaining_label: Label = %RemainingLabel
@onready var player_progress_bar: ProgressBar = %PlayerProgressBar
@onready var shuffle_button: Button = %ShuffleButton
@onready var player_prev_button: Button = %PlayerPrevButton
@onready var player_play_button: Button = %PlayerPlayButton
@onready var player_next_button: Button = %PlayerNextButton
@onready var player_list_button: Button = %PlayerListButton

## 注入播放器控制器并完成首次绑定与渲染。
func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_player_controller = MusicAppPlayerController.new(controller)
	bind()
	refresh()

## 绑定播放器固定按钮和进度条输入事件。
func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	close_player_button.pressed.connect(navigate_back)
	player_prev_button.pressed.connect(_play_previous)
	player_play_button.pressed.connect(toggle_playback)
	player_next_button.pressed.connect(_play_next)
	shuffle_button.pressed.connect(_cycle_playback_mode)
	like_button.pressed.connect(_toggle_like_current_track)
	player_queue_button.pressed.connect(_show_playback_queue)
	player_list_button.pressed.connect(_show_playback_queue)
	_bind_player_progress_bar_input()
	DX.signals.subscribe(PlaybackStartedEventScript, _on_playback_started)
	DX.signals.subscribe(PlaybackFinishedEventScript, _on_playback_finished)
	DX.signals.subscribe(PlaybackProgressChangedEventScript, _on_playback_progress_changed)

## 根据当前播放状态刷新播放器文案、图标和进度条。
func refresh() -> void:
	if _controller == null:
		return

	MusicAppIconsType.apply_icon_button(
		shuffle_button,
		_player_controller.get_playback_mode_icon()
	)
	shuffle_button.tooltip_text = tr(_player_controller.get_playback_mode_label_key())

	if not _player_controller.has_tracks():
		now_title_label.text = tr("music_app.player.empty_title")
		now_artist_label.text = tr("music_app.player.empty_artist")
		player_source_label.text = ""
		cover_mark_label.text = ""
		MusicAppIconsType.apply_icon_button(like_button, MusicAppIconsType.HEART_OUTLINE)
		MusicAppIconsType.apply_icon_button(player_play_button, MusicAppIconsType.PLAY)
		MusicAppIconsType.apply_icon_button(
			shuffle_button,
			_player_controller.get_playback_mode_icon()
		)
		player_progress_bar.value = 0.0
		elapsed_label.text = "00:00"
		remaining_label.text = "00:00"
		return

	var track: TrackData = _player_controller.get_current_track()
	var duration: int = _player_controller.get_current_duration()
	var progress := 0.0
	if duration > 0:
		progress = clampf(
			float(_player_controller.get_current_elapsed_seconds()) / float(duration),
			0.0,
			1.0
		)

	now_title_label.text = track.title
	now_artist_label.text = _player_controller.get_track_display_artist(track)
	player_source_label.text = track.source
	cover_mark_label.text = track.title
	MusicAppIconsType.apply_icon_button(
		like_button,
		MusicAppIconsType.HEART_FILLED
		if _player_controller.is_current_track_liked()
		else MusicAppIconsType.HEART_OUTLINE
	)
	MusicAppIconsType.apply_icon_button(
		player_play_button,
		MusicAppIconsType.PAUSE
		if _player_controller.is_playing()
		else MusicAppIconsType.PLAY
	)
	player_progress_bar.value = progress * 100.0
	elapsed_label.text = _format_seconds(_player_controller.get_current_elapsed_seconds())
	remaining_label.text = _format_seconds(duration)

func open_from_current() -> void:
	_player_controller.show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)

func on_popup_shown() -> void:
	refresh()

func _exit_tree() -> void:
	DX.signals.unsubscribe(PlaybackStartedEventScript, _on_playback_started)
	DX.signals.unsubscribe(PlaybackFinishedEventScript, _on_playback_finished)
	DX.signals.unsubscribe(PlaybackProgressChangedEventScript, _on_playback_progress_changed)

func navigate_back() -> void:
	close_popup()

func toggle_playback() -> void:
	_player_controller.toggle_playback()
	refresh()

func _toggle_like_current_track() -> void:
	_player_controller.toggle_like_current_track()
	refresh()

func _play_previous() -> void:
	_player_controller.play_previous_track()
	refresh()

func _play_next() -> void:
	_player_controller.play_next_track()
	refresh()

func _show_playback_queue() -> void:
	_player_controller.show_playback_queue()

func _cycle_playback_mode() -> void:
	_player_controller.cycle_playback_mode()
	refresh()

## 处理拖拽进度条期间的鼠标与触摸输入，实时更新 seek 位置。
func _input(event: InputEvent) -> void:
	if not _is_progress_dragging:
		return

	if event is InputEventMouseMotion:
		_seek_player_from_global_x(get_global_mouse_position().x, false)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_seek_player_from_global_x(get_global_mouse_position().x, true)
			_finish_progress_drag()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _active_progress_touch_index:
			_seek_player_from_global_x(drag_event.position.x, false)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.index == _active_progress_touch_index and not touch_event.pressed:
			_seek_player_from_global_x(touch_event.position.x, true)
			_finish_progress_drag()
			get_viewport().set_input_as_handled()

## 将秒数格式化为 mm:ss 文案。
func _format_seconds(total_seconds: int) -> String:
	var minutes: int = int(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]

## 为进度条绑定统一的输入处理入口。
func _bind_player_progress_bar_input() -> void:
	if not player_progress_bar.gui_input.is_connected(_on_player_progress_bar_gui_input):
		player_progress_bar.gui_input.connect(_on_player_progress_bar_gui_input)
	player_progress_bar.mouse_filter = Control.MOUSE_FILTER_STOP

## 响应进度条点击和触摸，开始或结束拖拽 seek。
func _on_player_progress_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_begin_progress_drag()
			_seek_player_from_global_x(get_global_mouse_position().x, false)
		else:
			_seek_player_from_global_x(get_global_mouse_position().x, true)
			_finish_progress_drag()
			refresh()
		accept_event()
		return

	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_active_progress_touch_index = touch_event.index
			_begin_progress_drag()
			_seek_player_from_global_x(touch_event.position.x, false)
		elif touch_event.index == _active_progress_touch_index:
			_seek_player_from_global_x(touch_event.position.x, true)
			_finish_progress_drag()
			refresh()
		accept_event()

## 标记当前进入播放器进度拖拽状态。
func _begin_progress_drag() -> void:
	_is_progress_dragging = true

## 结束拖拽并清理触摸跟踪状态。
func _finish_progress_drag() -> void:
	_is_progress_dragging = false
	_active_progress_touch_index = -1

## 根据全局横坐标计算进度比例，并同步到播放器控制器。
func _seek_player_from_global_x(global_x: float, persist_state: bool) -> void:
	if _player_controller == null or not _player_controller.has_tracks():
		return
	var progress_ratio := _get_progress_ratio_from_global_x(global_x)
	_player_controller.seek_to_progress_ratio(progress_ratio, persist_state)

## 将全局横坐标换算为进度条的 0 到 1 比例。
func _get_progress_ratio_from_global_x(global_x: float) -> float:
	var progress_rect := player_progress_bar.get_global_rect()
	if progress_rect.size.x <= 0.0:
		return 0.0
	return clampf((global_x - progress_rect.position.x) / progress_rect.size.x, 0.0, 1.0)

func _on_playback_started(_event: MusicAppPlaybackStartedEvent) -> void:
	refresh()

func _on_playback_finished(_event: MusicAppPlaybackFinishedEvent) -> void:
	refresh()

func _on_playback_progress_changed(_event: MusicAppPlaybackProgressChangedEvent) -> void:
	refresh()
