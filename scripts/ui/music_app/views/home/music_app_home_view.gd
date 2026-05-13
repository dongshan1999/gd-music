class_name MusicAppHomeView
extends "res://dx/runtime/scripts/managers/popup/popup_view.gd"

const MusicAppScriptPathsType := preload("res://scripts/constants/music_app_script_paths.gd")
const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")
const HomeFeatureCardType = preload(MusicAppScriptPathsType.MUSIC_APP_HOME_FEATURE_CARD_VIEW)
const HOME_PLAYLIST_ROW_SCENE := preload(MusicAppScriptPathsType.HOME_PLAYLIST_ROW)
const FEATURE_CARD_ICONS := [
	MusicAppIconsType.FIRE,
	MusicAppIconsType.TROPHY,
	MusicAppIconsType.CLOCK,
	MusicAppIconsType.FOLDER_MUSIC
]
const FEATURE_CARD_KEYS := [
	"music_app.home.feature.recommended",
	"music_app.home.feature.charts",
	"music_app.home.feature.history",
	"music_app.home.feature.local_music"
]

var _controller: MusicAppShowcaseController
var _home_controller: MusicAppHomeController
var _is_bound := false

@onready var search_bar: Panel = %SearchBar
@onready var search_icon_rect: TextureRect = %SearchIconRect
@onready var search_prompt_label: Label = %SearchPromptLabel
@onready var feature_grid: GridContainer = %FeatureGrid
@onready var home_menu_button: Button = %HomeMenuButton
@onready var my_playlists_label: Label = %MyPlaylistsLabel
@onready var favorite_playlists_label: Label = %FavoritePlaylistsLabel
@onready var home_tab_underline: Panel = %HomeTabUnderline
@onready var new_playlist_button: Button = %NewPlaylistButton
@onready var import_button: Button = %ImportButton
@onready var home_list: VBoxContainer = $Margin/HomeVBox/HomeScroll/HomeList
@onready var feature_cards: Array[MusicAppHomeFeatureCard] = [%FeatureCard0, %FeatureCard1, %FeatureCard2, %FeatureCard3]

var home_playlist_rows: Array[MusicAppHomePlaylistRow] = []

func setup(controller: MusicAppShowcaseController) -> void:
	_controller = controller
	_home_controller = MusicAppHomeController.new(controller)
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
	search_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	search_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _controller.state_changed.is_connected(refresh):
		_controller.state_changed.connect(refresh)

func refresh() -> void:
	if _controller == null:
		return

	MusicAppIconsType.apply_texture_icon(search_icon_rect, MusicAppIconsType.SEARCH)
	MusicAppIconsType.apply_icon_button(home_menu_button, MusicAppIconsType.MENU)
	MusicAppIconsType.apply_icon_button(new_playlist_button, MusicAppIconsType.PLUS)
	MusicAppIconsType.apply_icon_button(import_button, MusicAppIconsType.DOWNLOAD)
	var playlists = _home_controller.get_playlists()
	my_playlists_label.text = tr("music_app.home.my_playlists_count").format({"count": playlists.size()})
	var favorite_count := 0
	var favorite_index := _home_controller.find_favorite_playlist_index()
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
		var playlist: PlaylistData = playlists[index]
		home_playlist_rows[index].configure(
			index,
			_home_controller.get_playlist_display_mark(playlist),
			_home_controller.get_playlist_display_title(playlist),
			playlist.count,
			playlist.deletable
		)

func _open_playlist(index: int) -> void:
	_home_controller.open_playlist(index)

func _sync_home_playlist_rows() -> void:
	var target_size := _home_controller.get_playlists().size()

	while home_playlist_rows.size() < target_size:
		var row := HOME_PLAYLIST_ROW_SCENE.instantiate() as MusicAppHomePlaylistRow
		home_list.add_child(row)
		row.open_requested.connect(_open_playlist)
		row.delete_requested.connect(_delete_playlist)
		home_playlist_rows.append(row)

	while home_playlist_rows.size() > target_size:
		var row: MusicAppHomePlaylistRow = home_playlist_rows.pop_back()
		row.queue_free()

func _on_feature_pressed(index: int) -> void:
	_home_controller.open_feature_card(index)

func _create_playlist_from_current() -> void:
	_home_controller.create_playlist_from_current()

func _open_local_music() -> void:
	_home_controller.open_local_music()

func _open_plugin_browser() -> void:
	_home_controller.open_plugin_browser()

func _on_search_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_open_plugin_browser()

func _delete_playlist(index: int) -> void:
	_home_controller.delete_playlist(index)
