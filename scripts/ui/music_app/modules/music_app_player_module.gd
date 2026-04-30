class_name MusicAppPlayerModule
extends Control
const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")

var _controller: MusicAppShowcaseControllerType
var _is_bound := false

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

func setup(controller: MusicAppShowcaseControllerType) -> void:
	_controller = controller
	bind()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	close_player_button.pressed.connect(navigate_back)
	player_prev_button.pressed.connect(_play_previous)
	player_play_button.pressed.connect(toggle_playback)
	player_next_button.pressed.connect(_play_next)
	player_list_button.pressed.connect(_open_selected_playlist)
	player_queue_button.pressed.connect(_open_selected_playlist)
	like_button.pressed.connect(_toggle_like_current_track)

func refresh() -> void:
	if _controller == null:
		return

	if not _controller._has_tracks():
		now_title_label.text = "暂无歌曲"
		now_artist_label.text = "请先导入音乐"
		player_source_label.text = ""
		cover_mark_label.text = ""
		like_button.text = "♡"
		player_play_button.text = "▶"
		player_progress_bar.value = 0.0
		elapsed_label.text = "00:00"
		remaining_label.text = "00:00"
		return

	var track: TrackDataType = _controller._get_current_track()
	var duration: int = _controller._get_current_duration()
	var progress: float = clampf(float(_controller._elapsed_seconds) / float(duration), 0.0, 1.0)

	now_title_label.text = track.title
	now_artist_label.text = track.artist
	player_source_label.text = track.source
	cover_mark_label.text = track.title
	like_button.text = "♥" if _controller._is_current_track_liked() else "♡"
	player_play_button.text = "Ⅱ" if _controller._is_playing else "▶"
	player_progress_bar.value = progress * 100.0
	elapsed_label.text = _format_seconds(_controller._elapsed_seconds)
	remaining_label.text = _format_seconds(duration)

func open_from_current() -> void:
	if _controller._current_page != _controller._page_player():
		_controller._set_return_page(_controller._current_page)
	_controller._refresh_player_page()
	_controller._show_page(_controller._page_player())

func navigate_back() -> void:
	_controller._show_page(_controller._get_return_page())

func toggle_playback() -> void:
	if not _controller._has_tracks():
		_controller._is_playing = false
		_controller._refresh_player_page()
		_controller._refresh_mini_player()
		return

	_controller._is_playing = not _controller._is_playing
	_controller._refresh_player_page()
	_controller._refresh_mini_player()
	_controller._refresh_playlist_page()
	_controller._save_app_state()

func on_tick() -> void:
	if not _controller._has_tracks():
		_controller._is_playing = false
		return

	if not _controller._is_playing:
		return

	_controller._elapsed_seconds += 1
	if _controller._elapsed_seconds >= _controller._get_current_duration():
		_controller._select_track(_controller._selected_track_index + 1, true)
		return

	_controller._refresh_player_page()
	_controller._refresh_mini_player()
	_controller._refresh_playlist_page()

func _toggle_like_current_track() -> void:
	if not _controller._has_tracks():
		return

	var key: String = _controller._track_key(_controller._get_current_track())
	var next_state: bool = not bool(_controller._liked_tracks.get(key, false))
	_controller._liked_tracks[key] = next_state
	_controller._refresh_player_page()
	_controller._save_app_state()

func _play_previous() -> void:
	_controller._select_track(_controller._selected_track_index - 1, true)

func _play_next() -> void:
	_controller._select_track(_controller._selected_track_index + 1, true)

func _open_selected_playlist() -> void:
	_controller.playlist_page.open_selected_playlist()

func _format_seconds(total_seconds: int) -> String:
	var minutes: int = int(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
