class_name MusicAppPlaylistModule
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppPlaylistSongRowType := preload("res://scripts/ui/music_app/modules/music_app_playlist_song_row.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")
const PLAYLIST_SONG_ROW_SCENE := preload("res://scenes/ui/music_app/playlist_song_row.tscn")

var _controller: MusicAppShowcaseControllerType
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

var song_rows: Array[MusicAppPlaylistSongRowType] = []

func setup(controller: MusicAppShowcaseControllerType) -> void:
	_controller = controller
	bind()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	playlist_back_button.pressed.connect(close_page)
	play_all_button.pressed.connect(_play_playlist_from_start)
	playlist_add_button.pressed.connect(_create_playlist_from_current)

func refresh() -> void:
	if _controller == null:
		return


	if _controller._playlists.is_empty():
		playlist_hero_mark_label.text = tr("music_app.playlist.favorites_mark")
		playlist_hero_title_label.text = tr("music_app.playlist.favorites_title")
		playlist_hero_count_label.text = _controller._format_total_track_count(0)
		_sync_song_rows(0)
		return

	var playlist: PlaylistDataType = _controller._get_selected_playlist()
	var tracks: Array[int] = _controller._get_playlist_track_indices(_controller._selected_playlist_index)

	_sync_song_rows(tracks.size())
	playlist_hero_title_label.text = _controller._get_playlist_display_title(playlist)
	playlist_hero_count_label.text = _controller._format_total_track_count(playlist.count)
	playlist_hero_mark_label.text = _controller._get_playlist_display_mark(playlist)

	for index in song_rows.size():
		var track_index: int = tracks[index]
		var track: TrackDataType = _controller._tracks[track_index]
		song_rows[index].configure(index, track)

func open_selected_playlist() -> void:
	_show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYLIST)

func close_page() -> void:
	close_popup()

func _play_playlist_from_start() -> void:
	var tracks: Array[int] = _controller._get_playlist_track_indices(_controller._selected_playlist_index)
	if tracks.is_empty():
		return

	_controller._select_track(tracks[0], true)
	_show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)

func _select_song_from_playlist(slot_index: int) -> void:
	var tracks: Array[int] = _controller._get_playlist_track_indices(_controller._selected_playlist_index)
	if slot_index < 0 or slot_index >= tracks.size():
		return

	_controller._select_track(tracks[slot_index], true)
	_show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYER)

func _create_playlist_from_current() -> void:
	if not _controller._try_create_playlist_from_current():
		return

	_controller._refresh_home_page()
	_controller._refresh_playlist_page()
	_controller._save_app_state()

func _sync_song_rows(target_size: int) -> void:
	while song_rows.size() < target_size:
		var row := PLAYLIST_SONG_ROW_SCENE.instantiate() as MusicAppPlaylistSongRowType
		song_list.add_child(row)
		song_list.move_child(row, song_bottom_space.get_index())
		row.play_requested.connect(_select_song_from_playlist)
		song_rows.append(row)

	while song_rows.size() > target_size:
		var row: MusicAppPlaylistSongRowType = song_rows.pop_back()
		row.queue_free()

func _show_popup(popup_id: int):
	var manager = DX.popup
	if manager == null or not manager.has_method("show_or_reuse"):
		return null

	var popup = manager.show_or_reuse(popup_id)
	if popup != null and popup.has_method("setup"):
		popup.setup(_controller)
	if popup != null and popup.has_method("refresh"):
		popup.refresh()
	return popup
