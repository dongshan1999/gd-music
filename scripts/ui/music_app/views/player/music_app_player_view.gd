class_name MusicAppPlayerView
extends "res://scripts/ui/music_app/music_app_page.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const PlaybackStartedEventScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_STARTED_EVENT)
const PlaybackFinishedEventScript := preload(MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_FINISHED_EVENT)
const PlaybackProgressChangedEventScript := preload(
	MusicAppScriptPathsType.MUSIC_APP_PLAYBACK_PROGRESS_CHANGED_EVENT
)
const MusicAppLyricParserScript := preload(
	"res://scripts/ui/music_app/player/music_app_lyric_parser.gd"
)

var _controller: MusicAppShowcaseController
var _player_controller: MusicAppPlayerController
var _is_bound := false
var _is_progress_dragging := false
var _active_progress_touch_index := -1
var _is_lyrics_visible := false
var _lyrics_track_key := ""
var _lyrics: Array[Dictionary] = []
var _lyric_line_labels: Array[Label] = []
var _active_lyric_index := -2
var _lyrics_manual_scroll_until_msec := 0
var _lyric_pointer_start := Vector2.ZERO
var _lyric_touch_index := -1
var _is_lyrics_content_dragging := false
var _is_lyrics_scrollbar_dragging := false
var _cover_animation_tween: Tween
var _lyrics_top_padding: Control
var _lyrics_bottom_padding: Control
var _is_lyrics_edge_padding_update_queued := false

@onready var close_player_button: Button = %ClosePlayerButton
@onready var now_title_label: Label = %NowTitleLabel
@onready var now_artist_label: Label = %NowArtistLabel
@onready var player_source_label: Label = %PlayerSourceLabel
@onready var album_stage: CenterContainer = %AlbumStage
@onready var cover_panel: Panel = %CoverPanel
@onready var cover_circle: Panel = %CoverCircle
@onready var cover_icon_rect: TextureRect = %CoverIconRect
@onready var lyrics_stage: Control = %LyricsStage
@onready var lyrics_scroll: ScrollContainer = %LyricsScroll
@onready var lyrics_scroll_interaction = %LyricsScrollInteraction
@onready var lyrics_lines: VBoxContainer = %LyricsLines
@onready var lyrics_time_cursor = %LyricsTimeCursor
@onready var no_lyrics_center: CenterContainer = %NoLyricsCenter
@onready var no_lyrics_label: Label = %NoLyricsLabel
@onready var like_button: Button = %LikeButton
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
	if not is_node_ready():
		return
	_finish_setup()

func _ready() -> void:
	album_stage.resized.connect(_resize_artwork)
	_resize_artwork.call_deferred()
	_apply_content_view_visibility()
	if _controller != null:
		_finish_setup()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_request_lyrics_edge_padding_update()

func _finish_setup() -> void:
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
	player_list_button.pressed.connect(_show_playback_queue)
	cover_panel.gui_input.connect(_on_cover_panel_gui_input)
	lyrics_stage.gui_input.connect(_on_lyrics_stage_gui_input)
	lyrics_scroll.gui_input.connect(_on_lyrics_scroll_gui_input)
	lyrics_scroll_interaction.drag_scroll_started.connect(_on_lyrics_drag_scroll_started)
	lyrics_scroll_interaction.drag_scroll_finished.connect(_on_lyrics_drag_scroll_finished)
	var vertical_scroll_bar := lyrics_scroll.get_v_scroll_bar()
	if not vertical_scroll_bar.value_changed.is_connected(_on_lyrics_scroll_position_changed):
		vertical_scroll_bar.value_changed.connect(_on_lyrics_scroll_position_changed)
	if not lyrics_scroll.resized.is_connected(_request_lyrics_edge_padding_update):
		lyrics_scroll.resized.connect(_request_lyrics_edge_padding_update)
	cover_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	cover_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cover_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	no_lyrics_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		cover_icon_rect.visible = true
		MusicAppIconsType.apply_icon_button(like_button, MusicAppIconsType.HEART_OUTLINE)
		MusicAppIconsType.apply_icon_button(player_play_button, MusicAppIconsType.PLAY, false, false)
		MusicAppIconsType.apply_icon_button(
			shuffle_button,
			_player_controller.get_playback_mode_icon()
		)
		player_progress_bar.value = 0.0
		elapsed_label.text = "00:00"
		remaining_label.text = "00:00"
		_refresh_lyrics_for_track(null, 0)
		_sync_cover_animation(false)
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
	cover_icon_rect.visible = true
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
		else MusicAppIconsType.PLAY,
		false,
		false
	)
	player_progress_bar.value = progress * 100.0
	elapsed_label.text = _format_seconds(_player_controller.get_current_elapsed_seconds())
	remaining_label.text = _format_seconds(duration)
	_refresh_lyrics_for_track(track, _player_controller.get_current_elapsed_seconds())
	_sync_cover_animation(_player_controller.is_playing())

func open_from_current() -> void:
	_player_controller.show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)

func on_popup_shown() -> void:
	_show_album_view()
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

func _on_cover_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_show_lyrics_view()
			accept_event()
		return
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if not touch_event.pressed:
			_show_lyrics_view()
			accept_event()

func _on_lyrics_stage_gui_input(event: InputEvent) -> void:
	if not _is_lyrics_visible or not _lyrics.is_empty():
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_show_album_view()
			accept_event()
		return
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if not touch_event.pressed:
			_show_album_view()
			accept_event()

func _on_lyrics_scroll_gui_input(event: InputEvent) -> void:
	if not _is_lyrics_visible:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_mark_lyrics_manually_scrolled()
			_hide_lyrics_time_cursor()
			return
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_is_lyrics_scrollbar_dragging = _is_lyrics_scrollbar_at(get_global_mouse_position())
			if _is_lyrics_scrollbar_dragging:
				_hide_lyrics_time_cursor()
				return
			_lyric_pointer_start = get_global_mouse_position()
			return
		if _is_lyrics_scrollbar_dragging:
			_is_lyrics_scrollbar_dragging = false
			_mark_lyrics_manually_scrolled()
			_hide_lyrics_time_cursor()
			return
		if _is_lyrics_content_dragging:
			return
		_handle_lyric_tap_or_scroll(get_global_mouse_position())
		return
	if event is InputEventMouseMotion:
		if _lyric_pointer_start.distance_to(get_global_mouse_position()) >= 8.0:
			_mark_lyrics_manually_scrolled()
		return
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_is_lyrics_scrollbar_dragging = _is_lyrics_scrollbar_at(touch_event.position)
			if _is_lyrics_scrollbar_dragging:
				_hide_lyrics_time_cursor()
				return
			_lyric_touch_index = touch_event.index
			_lyric_pointer_start = touch_event.position
			return
		if _is_lyrics_scrollbar_dragging:
			_is_lyrics_scrollbar_dragging = false
			_mark_lyrics_manually_scrolled()
			_hide_lyrics_time_cursor()
			return
		if touch_event.index == _lyric_touch_index:
			if _is_lyrics_content_dragging:
				_lyric_touch_index = -1
				return
			_handle_lyric_tap_or_scroll(touch_event.position)
			_lyric_touch_index = -1
		return
	if event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if drag_event.index == _lyric_touch_index:
			_mark_lyrics_manually_scrolled()

func _handle_lyric_tap_or_scroll(global_position: Vector2) -> void:
	if _lyric_pointer_start.distance_to(global_position) >= 8.0:
		_mark_lyrics_manually_scrolled()
		return
	var lyric_index := _get_lyric_index_at_global_position(global_position)
	if lyric_index < 0:
		_show_album_view()
		return
	if not _seek_to_lyric(lyric_index):
		_show_album_view()

func _seek_to_centered_lyric() -> bool:
	return _seek_to_lyric(_get_centered_timed_lyric_index())

func _get_centered_timed_lyric_index() -> int:
	if _lyric_line_labels.is_empty():
		return -1
	var scroll_center_y := lyrics_scroll.get_global_rect().get_center().y
	var closest_index := -1
	var closest_distance := INF
	for index in _lyric_line_labels.size():
		var lyric_time := int(_lyrics[index].get("time", -1))
		if lyric_time < 0:
			continue
		var line_center_y := _lyric_line_labels[index].get_global_rect().get_center().y
		var distance := absf(line_center_y - scroll_center_y)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	return closest_index

func _seek_to_lyric(lyric_index: int) -> bool:
	if _player_controller == null or lyric_index < 0 or lyric_index >= _lyrics.size():
		return false
	var lyric_time := int(_lyrics[lyric_index].get("time", -1))
	if lyric_time < 0:
		return false
	_player_controller.seek_to_elapsed_seconds(lyric_time)
	_active_lyric_index = -2
	_lyrics_manual_scroll_until_msec = 0
	refresh()
	return true

func _show_lyrics_view() -> void:
	if _player_controller == null or not _player_controller.has_tracks():
		return
	_is_lyrics_visible = true
	_hide_lyrics_time_cursor()
	_apply_content_view_visibility()
	if not is_node_ready():
		return
	var track := _player_controller.get_current_track()
	_refresh_lyrics_for_track(track, _player_controller.get_current_elapsed_seconds())

func _show_album_view() -> void:
	_is_lyrics_visible = false
	_lyric_touch_index = -1
	_hide_lyrics_time_cursor()
	_apply_content_view_visibility()

func _apply_content_view_visibility() -> void:
	if not is_node_ready() or album_stage == null or lyrics_stage == null:
		return
	album_stage.visible = not _is_lyrics_visible
	lyrics_stage.visible = _is_lyrics_visible
	var content := lyrics_stage if _is_lyrics_visible else album_stage
	content.modulate.a = 0.0
	create_tween().tween_property(content, "modulate:a", 1.0, 0.18)

func _resize_artwork() -> void:
	var side := clampf(minf(album_stage.size.x - 24, album_stage.size.y - 24), 48, 340)
	cover_panel.custom_minimum_size = Vector2(side, side)
	cover_icon_rect.pivot_offset = Vector2(side * 0.5, side * 0.5)

## 播放时让占位封面做轻微呼吸缩放，暂停时回到静止状态。
func _sync_cover_animation(playing: bool) -> void:
	if playing:
		if _cover_animation_tween != null and _cover_animation_tween.is_valid():
			return
		_cover_animation_tween = create_tween().set_loops()
		_cover_animation_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_cover_animation_tween.tween_property(cover_icon_rect, "scale", Vector2(1.018, 1.018), 1.8)
		_cover_animation_tween.tween_property(cover_icon_rect, "scale", Vector2.ONE, 1.8)
		return
	if _cover_animation_tween != null:
		_cover_animation_tween.kill()
		_cover_animation_tween = null
	cover_icon_rect.scale = Vector2.ONE

func _refresh_lyrics_for_track(track: TrackData, elapsed_seconds: int) -> void:
	var track_key := _get_lyrics_track_key(track)
	if track_key != _lyrics_track_key:
		_lyrics_track_key = track_key
		_lyrics = _load_track_lyrics(track)
		_rebuild_lyric_lines()
		_active_lyric_index = -2
	if not _is_lyrics_visible:
		return
	if _lyrics.is_empty():
		return
	var next_active_index := _get_active_lyric_index(elapsed_seconds)
	if next_active_index == _active_lyric_index:
		return
	_active_lyric_index = next_active_index
	for index in _lyric_line_labels.size():
		var line_label := _lyric_line_labels[index]
		var is_active := index == next_active_index
		line_label.add_theme_color_override(
			"font_color",
			Color(1, 1, 1, 0.96) if is_active else Color(1, 1, 1, 0.48)
		)
		line_label.add_theme_font_size_override("font_size", 22 if is_active else 18)
	if next_active_index >= 0 and Time.get_ticks_msec() >= _lyrics_manual_scroll_until_msec:
		call_deferred("_scroll_lyrics_to_line", next_active_index)

func _get_lyrics_track_key(track: TrackData) -> String:
	if track == null:
		return ""
	return "%s|%s" % [track.id, track.lyric_path]

func _load_track_lyrics(track: TrackData) -> Array[Dictionary]:
	if track == null or track.lyric_path.is_empty():
		return []
	var read_result: Dictionary = DX.files.read_text(track.lyric_path)
	if not bool(read_result.get("ok", false)):
		return []
	return MusicAppLyricParserScript.parse(str(read_result.get("text", "")))

func _rebuild_lyric_lines() -> void:
	for child in lyrics_lines.get_children():
		child.queue_free()
	_lyric_line_labels.clear()
	_lyrics_top_padding = null
	_lyrics_bottom_padding = null
	no_lyrics_center.visible = _lyrics.is_empty()
	lyrics_scroll.visible = not _lyrics.is_empty()
	if _lyrics.is_empty():
		no_lyrics_label.text = tr("music_app.player.no_lyrics")
		_hide_lyrics_time_cursor()
		return
	_lyrics_top_padding = _create_lyrics_edge_padding()
	lyrics_lines.add_child(_lyrics_top_padding)
	for lyric_entry in _lyrics:
		var line_label := Label.new()
		line_label.custom_minimum_size = Vector2(0, 40)
		line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line_label.text = str(lyric_entry.get("text", ""))
		line_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.48))
		line_label.add_theme_font_size_override("font_size", 18)
		lyrics_lines.add_child(line_label)
		_lyric_line_labels.append(line_label)
	_lyrics_bottom_padding = _create_lyrics_edge_padding()
	lyrics_lines.add_child(_lyrics_bottom_padding)
	_request_lyrics_edge_padding_update()

func _get_active_lyric_index(elapsed_seconds: int) -> int:
	var active_index := -1
	for index in _lyrics.size():
		var lyric_time := int(_lyrics[index].get("time", -1))
		if lyric_time < 0:
			continue
		if lyric_time > elapsed_seconds:
			break
		active_index = index
	return active_index

func _scroll_lyrics_to_line(index: int) -> void:
	if not _is_lyrics_visible or index < 0 or index >= _lyric_line_labels.size():
		return
	var line_label := _lyric_line_labels[index]
	var target_scroll := roundi(
		line_label.position.y + line_label.size.y * 0.5 - lyrics_scroll.size.y * 0.5
	)
	var max_scroll := roundi(maxf(0.0, lyrics_lines.size.y - lyrics_scroll.size.y))
	lyrics_scroll.scroll_vertical = clampi(target_scroll, 0, max_scroll)

func _get_lyric_index_at_global_position(global_position: Vector2) -> int:
	for index in _lyric_line_labels.size():
		if _lyric_line_labels[index].get_global_rect().has_point(global_position):
			return index
	return -1

func _mark_lyrics_manually_scrolled() -> void:
	_lyrics_manual_scroll_until_msec = Time.get_ticks_msec() + 4000

func _on_lyrics_drag_scroll_started() -> void:
	_is_lyrics_content_dragging = true
	_mark_lyrics_manually_scrolled()
	_show_lyrics_time_cursor()

func _on_lyrics_drag_scroll_finished() -> void:
	_is_lyrics_content_dragging = false
	if not _seek_to_centered_lyric():
		_mark_lyrics_manually_scrolled()
	_hide_lyrics_time_cursor()

func _on_lyrics_scroll_position_changed(_value: float) -> void:
	if lyrics_time_cursor.visible:
		call_deferred("_refresh_lyrics_time_cursor")

func _refresh_lyrics_time_cursor() -> void:
	if lyrics_time_cursor == null or not lyrics_time_cursor.visible:
		return
	var lyric_index := _get_centered_timed_lyric_index()
	var lyric_time := int(_lyrics[lyric_index].get("time", -1)) if lyric_index >= 0 else -1
	lyrics_time_cursor.set_timestamp(lyric_time)

func _show_lyrics_time_cursor() -> void:
	if lyrics_time_cursor == null or _lyrics.is_empty():
		return
	lyrics_time_cursor.visible = true
	_refresh_lyrics_time_cursor()

func _hide_lyrics_time_cursor() -> void:
	if lyrics_time_cursor == null:
		return
	lyrics_time_cursor.visible = false
	lyrics_time_cursor.set_timestamp(-1)

func _create_lyrics_edge_padding() -> Control:
	var padding := Control.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return padding

func _update_lyrics_edge_padding() -> void:
	if _lyric_line_labels.is_empty() or _lyrics_top_padding == null or _lyrics_bottom_padding == null:
		return
	var line_height := maxf(40.0, _lyric_line_labels[0].size.y)
	var separation := float(lyrics_lines.get_theme_constant("separation"))
	var edge_height := maxf(0.0, lyrics_scroll.size.y * 0.5 - line_height * 0.5 - separation)
	var padding_size := Vector2(0.0, edge_height)
	_lyrics_top_padding.custom_minimum_size = padding_size
	_lyrics_bottom_padding.custom_minimum_size = padding_size
	lyrics_lines.queue_sort()

func _request_lyrics_edge_padding_update() -> void:
	if _is_lyrics_edge_padding_update_queued:
		return
	_is_lyrics_edge_padding_update_queued = true
	call_deferred("_update_lyrics_edge_padding_after_layout")

func _update_lyrics_edge_padding_after_layout() -> void:
	await get_tree().process_frame
	_is_lyrics_edge_padding_update_queued = false
	_update_lyrics_edge_padding()

func _is_lyrics_scrollbar_at(global_position: Vector2) -> bool:
	var vertical_bar := lyrics_scroll.get_v_scroll_bar()
	return vertical_bar != null and vertical_bar.visible and vertical_bar.get_global_rect().has_point(global_position)

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
