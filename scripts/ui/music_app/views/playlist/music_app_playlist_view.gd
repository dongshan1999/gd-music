class_name MusicAppPlaylistView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const PLAYLIST_SONG_ROW_SCENE := preload(MusicAppScriptPathsType.PLAYLIST_SONG_ROW)

var _controller: MusicAppShowcaseController
var _playlist_controller: MusicAppPlaylistController
var _is_bound := false

@onready var playlist_top_title: Label = %PlaylistTopTitle
@onready var playlist_back_button: Button = %PlaylistBackButton
@onready var playlist_search_button: Button = %PlaylistSearchButton
@onready var playlist_more_button: Button = %PlaylistMoreButton
@onready var playlist_hero_panel: Panel = %PlaylistHeroPanel
@onready var playlist_hero_cover: Panel = %PlaylistHeroCover
@onready var playlist_hero_mark_label: Label = %PlaylistHeroMarkLabel
@onready var playlist_hero_title_label: Label = %PlaylistHeroTitleLabel
@onready var playlist_hero_count_label: Label = %PlaylistHeroCountLabel
@onready var play_all_button: Button = %PlayAllButton
@onready var playlist_add_button: Button = %PlaylistAddButton
@onready var playlist_edit_button: Button = %PlaylistEditButton
@onready var song_list: VBoxContainer = $Margin/PlaylistVBox/PlaylistScroll/SongList
@onready var song_bottom_space: Control = $Margin/PlaylistVBox/PlaylistScroll/SongList/SongBottomSpace

var song_rows: Array[MusicAppPlaylistSongRow] = []

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_playlist_controller = MusicAppPlaylistController.new(controller)
	bind()
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	playlist_back_button.pressed.connect(close_page)
	play_all_button.pressed.connect(_play_playlist_from_start)
func refresh() -> void:
	if _controller == null:
		return

	if _playlist_controller.get_playlists().is_empty():
		playlist_hero_mark_label.text = tr("music_app.playlist.favorites_mark")
		playlist_hero_title_label.text = tr("music_app.playlist.favorites_title")
		playlist_hero_count_label.text = _playlist_controller.format_total_track_count(0)
		_sync_song_rows(0)
		return

	var playlist: PlaylistData = _playlist_controller.get_selected_playlist()
	var tracks: Array[int] = _playlist_controller.get_selected_playlist_track_indices()

	_sync_song_rows(tracks.size())
	playlist_hero_title_label.text = _playlist_controller.get_playlist_display_title(playlist)
	playlist_hero_count_label.text = _playlist_controller.format_total_track_count(playlist.count)
	playlist_hero_mark_label.text = _playlist_controller.get_playlist_display_mark(playlist)

	for index in song_rows.size():
		var track_index: int = tracks[index]
		var track: TrackData = _playlist_controller.get_track(track_index)
		song_rows[index].configure(index, track)

func close_page() -> void:
	close_popup()

func _play_playlist_from_start() -> void:
	_playlist_controller.play_selected_playlist_from_start()

func _select_song_from_playlist(slot_index: int) -> void:
	_playlist_controller.play_selected_playlist_track(slot_index)

func _sync_song_rows(target_size: int) -> void:
	while song_rows.size() < target_size:
		var row := PLAYLIST_SONG_ROW_SCENE.instantiate() as MusicAppPlaylistSongRow
		song_list.add_child(row)
		song_list.move_child(row, song_bottom_space.get_index())
		row.play_requested.connect(_select_song_from_playlist)
		song_rows.append(row)

	while song_rows.size() > target_size:
		var row: MusicAppPlaylistSongRow = song_rows.pop_back()
		row.queue_free()
