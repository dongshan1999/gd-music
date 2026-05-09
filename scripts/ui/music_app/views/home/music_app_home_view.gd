class_name MusicAppHomeView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const HomeFeatureCardType = preload("res://scripts/ui/music_app/views/home/music_app_home_feature_card.gd")
const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppLibraryControllerType := preload("res://scripts/ui/music_app/controllers/music_app_library_controller.gd")
const MusicAppHomePlaylistRowType := preload("res://scripts/ui/music_app/views/home/music_app_home_playlist_row.gd")
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
var _library_controller: MusicAppLibraryControllerType = MusicAppLibraryControllerType.new()
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
	refresh()

func bind() -> void:
	if _is_bound:
		return
	_is_bound = true

	for card in feature_cards:
		card.pressed.connect(_on_feature_pressed)

	new_playlist_button.pressed.connect(_create_playlist_from_current)
	import_button.pressed.connect(_open_local_music)
	search_bar.gui_input.connect(_on_search_bar_gui_input)
	search_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	search_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func refresh() -> void:
	if _controller == null:
		return

	search_icon_label.text = "🔎"
	var playlists := _library_controller.get_playlists()
	my_playlists_label.text = tr("music_app.home.my_playlists_count").format({"count": playlists.size()})
	var favorite_count := 0
	var favorite_index := _library_controller.find_favorite_playlist_index()
	if favorite_index >= 0:
		favorite_count = playlists[favorite_index].count
	favorite_playlists_label.text = tr("music_app.home.favorite_playlists_count").format(
		{"count": favorite_count}
	)

	var feature_count := mini(feature_cards.size(), FEATURE_CARD_KEYS.size())
	for index in feature_count:
		feature_cards[index].configure(index, FEATURE_CARD_ICONS[index], tr(FEATURE_CARD_KEYS[index]))

	_sync_home_playlist_rows()
	for index in home_playlist_rows.size():
		var playlist: PlaylistDataType = playlists[index]
		home_playlist_rows[index].configure(
			index,
			_library_controller.get_playlist_display_mark(playlist),
			_library_controller.get_playlist_display_title(playlist),
			playlist.count,
			playlist.deletable
		)

func _open_playlist(index: int) -> void:
	_library_controller.open_playlist(index)

func _sync_home_playlist_rows() -> void:
	var target_size := _library_controller.get_playlists().size()

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
	_library_controller.create_playlist_from_current()

func _open_local_music() -> void:
	var popup = _library_controller.show_popup(PopupRegistryType.PopupId.MUSIC_APP_LOCAL_MUSIC)
	if popup != null and popup.has_method("open_page"):
		popup.open_page()

func _open_plugin_browser() -> void:
	_library_controller.show_popup(PopupRegistryType.PopupId.MUSIC_APP_PLUGIN_BROWSER)

func _on_search_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_open_plugin_browser()

func _delete_playlist(index: int) -> void:
	_library_controller.delete_playlist(index)
