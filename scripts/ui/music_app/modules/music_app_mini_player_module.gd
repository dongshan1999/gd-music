class_name MusicAppMiniPlayerModule
extends Panel
const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")

var _controller: MusicAppShowcaseControllerType
var _is_bound := false

@onready var mini_cover_mark_label: Label = %MiniCoverMarkLabel
@onready var mini_track_label: Label = %MiniTrackLabel
@onready var mini_play_button: Button = %MiniPlayButton
@onready var mini_list_button: Button = %MiniListButton
@onready var mini_open_button: Button = %MiniOpenButton

func setup(controller: MusicAppShowcaseControllerType) -> void:
	_controller = controller
	bind()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	mini_play_button.pressed.connect(_toggle_playback)
	mini_list_button.pressed.connect(_open_selected_playlist)
	mini_open_button.pressed.connect(_open_player_from_current)

func refresh() -> void:
	if _controller == null:
		return

	if not _controller._has_tracks():
		mini_cover_mark_label.text = ""
		mini_track_label.text = "暂无歌曲，请先导入"
		mini_play_button.text = "▶"
		return

	var track: TrackDataType = _controller._get_current_track()
	mini_cover_mark_label.text = track.mark
	mini_track_label.text = "%s - %s" % [track.title, track.artist]
	mini_play_button.text = "Ⅱ" if _controller._is_playing else "▶"

func _toggle_playback() -> void:
	if not _controller._has_tracks():
		return
	_controller.player_page.toggle_playback()

func _open_selected_playlist() -> void:
	if not _controller._has_tracks():
		return
	_controller.playlist_page.open_selected_playlist()

func _open_player_from_current() -> void:
	_controller.player_page.open_from_current()
