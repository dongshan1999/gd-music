class_name MusicAppHomeModule
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const HomeFeatureCardType = preload("res://scripts/ui/music_app/modules/music_app_home_feature_card.gd")
const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppHomePlaylistRowType := preload("res://scripts/ui/music_app/modules/music_app_home_playlist_row.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const HOME_PLAYLIST_ROW_SCENE := preload("res://scenes/ui/music_app/home_playlist_row.tscn")
const FEATURE_ACTION_LOCAL_MUSIC := -1
const FEATURE_CARD_ICONS := ["🎧", "📈", "🕘", "💽"]
const FEATURE_CARD_KEYS := [
	"music_app.home.feature.recommended",
	"music_app.home.feature.charts",
	"music_app.home.feature.history",
	"music_app.home.feature.local_music"
]
const FEATURE_CARD_TARGETS := [0, 1, 0, FEATURE_ACTION_LOCAL_MUSIC]

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

	for card in feature_cards:
		card.pressed.connect(_on_feature_pressed)

	new_playlist_button.pressed.connect(_create_playlist_from_current)
	import_button.pressed.connect(_open_local_music)

func refresh() -> void:
	if _controller == null:
		return

	search_icon_label.text = "🔎"
	my_playlists_label.text = tr("music_app.home.my_playlists_count").format({"count": _controller._playlists.size()})
	favorite_playlists_label.text = tr("music_app.home.favorite_playlists_count").format({"count": 0})

	var feature_count := mini(feature_cards.size(), FEATURE_CARD_KEYS.size())
	for index in feature_count:
		feature_cards[index].configure(index, FEATURE_CARD_ICONS[index], tr(FEATURE_CARD_KEYS[index]))

	_sync_home_playlist_rows()
	for index in home_playlist_rows.size():
		var playlist: PlaylistDataType = _controller._playlists[index]
		home_playlist_rows[index].configure(
			index,
			_controller._get_playlist_display_mark(playlist),
			_controller._get_playlist_display_title(playlist),
			playlist.count,
			playlist.deletable
		)

func _open_playlist(index: int) -> void:
	if _controller._playlists.is_empty():
		return

	_controller._selected_playlist_index = clampi(index, 0, _controller._playlists.size() - 1)
	_controller._refresh_home_page()
	_controller._refresh_playlist_page()
	_controller._save_app_state()
	_show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLAYLIST)

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
	if target_playlist == FEATURE_ACTION_LOCAL_MUSIC:
		_open_local_music()
		return
	_open_playlist(target_playlist)

func _create_playlist_from_current() -> void:
	if not _controller._try_create_playlist_from_current():
		return

	_controller._refresh_home_page()
	_controller._refresh_playlist_page()
	_controller._save_app_state()

func _open_local_music() -> void:
	var popup = _show_popup(PopupRegistryType.PopupId.MUSIC_APP_LOCAL_MUSIC)
	if popup != null and popup.has_method("open_page"):
		popup.open_page()

func _delete_playlist(index: int) -> void:
	if index < 0 or index >= _controller._playlists.size():
		return

	var playlist: PlaylistDataType = _controller._playlists[index]
	if not playlist.deletable:
		return

	if index < _controller._selected_playlist_index:
		_controller._selected_playlist_index -= 1

	_controller._playlists.remove_at(index)
	_controller._selected_playlist_index = clampi(_controller._selected_playlist_index, 0, maxi(_controller._playlists.size() - 1, 0))
	_controller._refresh_home_page()
	_controller._refresh_playlist_page()
	_controller._save_app_state()

func _show_popup(popup_id: int):
	var manager = DX.popup
	if manager == null:
		return null

	var popup = manager.show(popup_id)
	if popup != null and popup.has_method("setup"):
		popup.setup(_controller)
	return popup
