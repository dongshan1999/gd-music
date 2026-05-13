class_name MusicAppMiniPlayerView
extends Panel

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")

var _controller: MusicAppShowcaseController
var _mini_player_controller: MusicAppMiniPlayerController
var _is_bound := false

@onready var mini_cover_mark_label: Label = %MiniCoverMarkLabel
@onready var mini_track_label: Label = %MiniTrackLabel
@onready var mini_play_button: Button = %MiniPlayButton
@onready var mini_list_button: Button = %MiniListButton
@onready var mini_open_button: Button = %MiniOpenButton

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_mini_player_controller = MusicAppMiniPlayerController.new(controller)
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	mini_play_button.pressed.connect(_toggle_playback)
	mini_list_button.pressed.connect(_show_playback_queue)
	mini_open_button.pressed.connect(_open_player_from_current)
	if not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func refresh() -> void:
	if _controller == null:
		return

	if not _mini_player_controller.has_tracks():
		mini_cover_mark_label.text = ""
		mini_track_label.text = tr("music_app.mini_player.empty")
		MusicAppIconsType.apply_icon_button(mini_play_button, MusicAppIconsType.PLAY)
		MusicAppIconsType.apply_icon_button(mini_list_button, MusicAppIconsType.PLAYLIST)
		return

	var track: TrackData = _mini_player_controller.get_current_track()
	mini_cover_mark_label.text = track.mark
	mini_track_label.text = "%s - %s" % [track.title, _mini_player_controller.get_track_display_artist(track)]
	MusicAppIconsType.apply_icon_button(
		mini_play_button,
		MusicAppIconsType.PAUSE
		if _mini_player_controller.is_playing()
		else MusicAppIconsType.PLAY
	)
	MusicAppIconsType.apply_icon_button(mini_list_button, MusicAppIconsType.PLAYLIST)

func _toggle_playback() -> void:
	if not _mini_player_controller.has_tracks():
		return
	_mini_player_controller.toggle_playback()

func _show_playback_queue() -> void:
	if not _mini_player_controller.has_tracks():
		return
	_mini_player_controller.show_playback_queue()

func _open_player_from_current() -> void:
	_mini_player_controller.open_player_page()
