class_name MusicAppHomeModule
extends Control

const HomeFeatureCardType = preload("res://scripts/ui/music_app/modules/music_app_home_feature_card.gd")
const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppHomePlaylistRowType := preload("res://scripts/ui/music_app/modules/music_app_home_playlist_row.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const HOME_PLAYLIST_ROW_SCENE := preload("res://scenes/ui/music_app/home_playlist_row.tscn")
const FEATURE_CARD_ICONS := ["◉", "⌂", "◷", "▣"]
const FEATURE_CARD_TEXTS := ["推荐歌单", "榜单", "播放历史", "本地音乐"]
const FEATURE_CARD_TARGETS := [0, 1, 0, 2]

var _controller: MusicAppShowcaseControllerType
var _is_bound := false

@onready var search_bar: Panel = %SearchBar
@onready var search_icon_label: Label = $Margin/HomeVBox/SearchRow/SearchBar/Margin/SearchHBox/SearchIconLabel
@onready var search_prompt_label: Label = %SearchPromptLabel
@onready var feature_grid: GridContainer = %FeatureGrid
@onready var home_menu_button: Button = %HomeMenuButton
@onready var my_playlists_label: Label = %MyPlaylistsLabel
@onready var favorite_playlists_label: Label = %FavoritePlaylistsLabel
@onready var home_tab_underline: Panel = %HomeTabUnderline
@onready var new_playlist_button: Button = %NewPlaylistButton
@onready var import_button: Button = %ImportButton
@onready var home_list: VBoxContainer = $Margin/HomeVBox/HomeScroll/HomeList
@onready var feature_cards: Array[HomeFeatureCardType] = [%FeatureCard0, %FeatureCard1, %FeatureCard2, %FeatureCard3]
var home_playlist_rows: Array[MusicAppHomePlaylistRowType] = []

func setup(controller: MusicAppShowcaseControllerType) -> void:
	_controller = controller
	bind()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	var feature_count := mini(feature_cards.size(), FEATURE_CARD_TEXTS.size())
	for index in feature_count:
		feature_cards[index].configure(index, FEATURE_CARD_ICONS[index], FEATURE_CARD_TEXTS[index])
		feature_cards[index].pressed.connect(_on_feature_pressed)

	new_playlist_button.pressed.connect(_create_playlist_from_current)

func refresh() -> void:
	if _controller == null:
		return

	_sync_home_playlist_rows()
	my_playlists_label.text = "我的歌单 (%d)" % _controller._playlists.size()

	for index in home_playlist_rows.size():
		var playlist: PlaylistDataType = _controller._playlists[index]
		home_playlist_rows[index].configure(index, playlist)

func _open_playlist(index: int) -> void:
	if _controller._playlists.is_empty():
		return

	_controller._selected_playlist_index = clampi(index, 0, _controller._playlists.size() - 1)
	_controller._set_playlist_back_target(_controller._current_page if _controller._current_page != _controller._page_playlist() else _controller._page_home())
	_controller._set_return_page(_controller._page_playlist())
	_controller._refresh_home_page()
	_controller._refresh_playlist_page()
	_controller._save_app_state()
	_controller._show_page(_controller._page_playlist())

func _sync_home_playlist_rows() -> void:
	var target_size := _controller._playlists.size()

	while home_playlist_rows.size() < target_size:
		var row := HOME_PLAYLIST_ROW_SCENE.instantiate() as MusicAppHomePlaylistRowType
		home_list.add_child(row)
		row.open_requested.connect(_open_playlist)
		row.delete_requested.connect(_delete_playlist)
		home_playlist_rows.append(row)

	while home_playlist_rows.size() > target_size:
		var row: MusicAppHomePlaylistRowType = home_playlist_rows.pop_back()
		row.queue_free()

func _on_feature_pressed(index: int) -> void:
	if index < 0 or index >= FEATURE_CARD_TARGETS.size():
		return

	var target_playlist: int = FEATURE_CARD_TARGETS[index]
	_open_playlist(target_playlist)

func _create_playlist_from_current() -> void:
	if not _controller._try_create_playlist_from_current():
		return

	_controller._refresh_home_page()
	_controller._refresh_playlist_page()
	_controller._save_app_state()

func _delete_playlist(index: int) -> void:
	if index < 0 or index >= _controller._playlists.size():
		return

	var playlist: PlaylistDataType = _controller._playlists[index]
	if not playlist.deletable:
		return

	_controller._playlists.remove_at(index)
	_controller._selected_playlist_index = clampi(_controller._selected_playlist_index, 0, maxi(_controller._playlists.size() - 1, 0))
	if _controller._current_page == _controller._page_playlist() and _controller._playlists.is_empty():
		_controller._show_page(_controller._page_home())
	_controller._refresh_home_page()
	_controller._refresh_playlist_page()
	_controller._save_app_state()
