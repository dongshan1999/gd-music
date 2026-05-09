class_name MusicAppMiniPlayerView
extends Panel

const MusicAppLibraryControllerType := preload("res://scripts/ui/music_app/controllers/music_app_library_controller.gd")
const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")

var _controller: MusicAppShowcaseControllerType
var _library_controller: MusicAppLibraryControllerType = MusicAppLibraryControllerType.new()
var _is_bound := false

@onready var mini_cover_mark_label: Label = %MiniCoverMarkLabel
@onready var mini_track_label: Label = %MiniTrackLabel
@onready var mini_play_button: Button = %MiniPlayButton
@onready var mini_list_button: Button = %MiniListButton
@onready var mini_open_button: Button = %MiniOpenButton

func setup(controller: MusicAppShowcaseControllerType) -> void:
	_controller = controller
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	mini_play_button.pressed.connect(_toggle_playback)
	mini_list_button.pressed.connect(_open_selected_playlist)
	mini_open_button.pressed.connect(_open_player_from_current)
	if not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func refresh() -> void:
	if _controller == null:
		return

	if not _library_controller.has_tracks():
		mini_cover_mark_label.text = ""
		mini_track_label.text = tr("music_app.mini_player.empty")
		mini_play_button.text = "▶"
		return

	var track: TrackDataType = _library_controller.get_current_track()
	mini_cover_mark_label.text = track.mark
	mini_track_label.text = "%s - %s" % [track.title, _library_controller.get_track_display_artist(track)]
	mini_play_button.text = "⏸" if _library_controller.is_playing() else "▶"

func _toggle_playback() -> void:
	if not _library_controller.has_tracks():
		return
	_library_controller.toggle_playback()

func _open_selected_playlist() -> void:
	if not _library_controller.has_tracks():
		return
	_library_controller.show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYLIST)

func _open_player_from_current() -> void:
	_library_controller.show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)
