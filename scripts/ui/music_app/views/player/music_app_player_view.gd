class_name MusicAppPlayerView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppUiSymbolsType := preload("res://scripts/constants/music_app_ui_symbols.gd")

var _controller: MusicAppShowcaseController
var _player_controller: MusicAppPlayerController
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

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_player_controller = MusicAppPlayerController.new(controller)
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	close_player_button.pressed.connect(navigate_back)
	player_prev_button.pressed.connect(_play_previous)
	player_play_button.pressed.connect(toggle_playback)
	player_next_button.pressed.connect(_play_next)
	like_button.pressed.connect(_toggle_like_current_track)
	player_queue_button.pressed.connect(_show_playback_queue)
	player_list_button.pressed.connect(_show_playback_queue)
	if not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func refresh() -> void:
	if _controller == null:
		return


	if not _player_controller.has_tracks():
		now_title_label.text = tr("music_app.player.empty_title")
		now_artist_label.text = tr("music_app.player.empty_artist")
		player_source_label.text = ""
		cover_mark_label.text = ""
		like_button.text = MusicAppUiSymbolsType.HEART_OUTLINE
		player_play_button.text = MusicAppUiSymbolsType.PLAY
		player_progress_bar.value = 0.0
		elapsed_label.text = "00:00"
		remaining_label.text = "00:00"
		return

	var track: TrackData = _player_controller.get_current_track()
	var duration: int = _player_controller.get_current_duration()
	var progress: float = clampf(float(_player_controller.get_current_elapsed_seconds()) / float(duration), 0.0, 1.0)

	now_title_label.text = track.title
	now_artist_label.text = _player_controller.get_track_display_artist(track)
	player_source_label.text = track.source
	cover_mark_label.text = track.title
	like_button.text = (
		MusicAppUiSymbolsType.HEART_FILLED
		if _player_controller.is_current_track_liked()
		else MusicAppUiSymbolsType.HEART_OUTLINE
	)
	player_play_button.text = (
		MusicAppUiSymbolsType.PAUSE
		if _player_controller.is_playing()
		else MusicAppUiSymbolsType.PLAY
	)
	player_progress_bar.value = progress * 100.0
	elapsed_label.text = _format_seconds(_player_controller.get_current_elapsed_seconds())
	remaining_label.text = _format_seconds(duration)

func open_from_current() -> void:
	_player_controller.show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYER)

func navigate_back() -> void:
	close_popup()

func toggle_playback() -> void:
	_player_controller.toggle_playback()

func _toggle_like_current_track() -> void:
	_player_controller.toggle_like_current_track()

func _play_previous() -> void:
	_player_controller.play_previous_track()

func _play_next() -> void:
	_player_controller.play_next_track()

func _show_playback_queue() -> void:
	_player_controller.show_playback_queue()

func _format_seconds(total_seconds: int) -> String:
	var minutes: int = int(float(total_seconds) / 60.0)
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
