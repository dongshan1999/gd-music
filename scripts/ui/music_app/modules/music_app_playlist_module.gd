class_name MusicAppPlaylistModule
extends Control
const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")

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
@onready var song_rows: Array[Panel] = [%SongRow0, %SongRow1, %SongRow2, %SongRow3, %SongRow4, %SongRow5, %SongRow6, %SongRow7]
@onready var song_indices: Array[Label] = [%SongIndex0, %SongIndex1, %SongIndex2, %SongIndex3, %SongIndex4, %SongIndex5, %SongIndex6, %SongIndex7]
@onready var song_titles: Array[Label] = [%SongTitle0, %SongTitle1, %SongTitle2, %SongTitle3, %SongTitle4, %SongTitle5, %SongTitle6, %SongTitle7]
@onready var song_subtitles: Array[Label] = [%SongSubtitle0, %SongSubtitle1, %SongSubtitle2, %SongSubtitle3, %SongSubtitle4, %SongSubtitle5, %SongSubtitle6, %SongSubtitle7]
@onready var song_vips: Array[Label] = [%SongVip0, %SongVip1, %SongVip2, %SongVip3, %SongVip4, %SongVip5, %SongVip6, %SongVip7]
@onready var song_more_buttons: Array[Button] = [%SongMore0, %SongMore1, %SongMore2, %SongMore3, %SongMore4, %SongMore5, %SongMore6, %SongMore7]
@onready var song_buttons: Array[Button] = [%SongButton0, %SongButton1, %SongButton2, %SongButton3, %SongButton4, %SongButton5, %SongButton6, %SongButton7]

func setup(controller: MusicAppShowcaseControllerType) -> void:
	_controller = controller
	bind()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	for index in song_buttons.size():
		song_buttons[index].pressed.connect(_select_song_from_playlist.bind(index))

	playlist_back_button.pressed.connect(close_page)
	play_all_button.pressed.connect(_play_playlist_from_start)
	playlist_add_button.pressed.connect(_create_playlist_from_current)

func refresh() -> void:
	if _controller == null:
		return

	if _controller._playlists.is_empty():
		for row in song_rows:
			row.visible = false
		return

	var playlist: PlaylistDataType = _controller._get_selected_playlist()
	var tracks: Array[int] = _controller._get_playlist_track_indices(_controller._selected_playlist_index)

	playlist_hero_title_label.text = playlist.title
	playlist_hero_count_label.text = "共 %d 首" % playlist.count
	playlist_hero_mark_label.text = playlist.mark

	for index in song_rows.size():
		var visible_row: bool = index < tracks.size()
		song_rows[index].visible = visible_row
		if not visible_row:
			continue

		var track_index: int = tracks[index]
		var track: TrackDataType = _controller._tracks[track_index]
		song_indices[index].text = str(index + 1)
		song_titles[index].text = track.title
		song_subtitles[index].text = track.subtitle
		song_vips[index].text = "[%s]" % track.source

func open_selected_playlist() -> void:
	if _controller._playlists.is_empty():
		return

	_controller._set_playlist_back_target(_controller._current_page if _controller._current_page != _controller._page_playlist() else _controller._page_home())
	_controller._set_return_page(_controller._page_playlist())
	_controller._refresh_playlist_page()
	_controller._show_page(_controller._page_playlist())

func close_page() -> void:
	if _controller._get_playlist_back_target() == _controller._page_player():
		_controller._show_page(_controller._page_player())
	else:
		_controller._show_page(_controller._page_home())

func _play_playlist_from_start() -> void:
	var tracks: Array[int] = _controller._get_playlist_track_indices(_controller._selected_playlist_index)
	if tracks.is_empty():
		return

	_controller._select_track(tracks[0], true)
	_controller._set_return_page(_controller._page_playlist())
	_controller._show_page(_controller._page_player())

func _select_song_from_playlist(slot_index: int) -> void:
	var tracks: Array[int] = _controller._get_playlist_track_indices(_controller._selected_playlist_index)
	if slot_index < 0 or slot_index >= tracks.size():
		return

	_controller._select_track(tracks[slot_index], true)
	_controller._set_return_page(_controller._page_playlist())
	_controller._show_page(_controller._page_player())

func _create_playlist_from_current() -> void:
	if not _controller._try_create_playlist_from_current():
		return

	_controller._refresh_home_page()
	_controller._refresh_playlist_page()
	_controller._save_app_state()
