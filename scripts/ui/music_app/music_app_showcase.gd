class_name MusicAppShowcaseController
extends Control
const MusicAppStateDataType := preload("res://scripts/save/music/music_app_state_data.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const MusicAppLayoutType := preload("res://scripts/ui/music_app/music_app_layout.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/popup/popup_registry.gd")
const PopupManagerType := preload("res://dx/runtime/scripts/popup/popup_manager.gd")
const PopupViewType := preload("res://dx/runtime/scripts/popup/popup_view.gd")
const CommonDialogPopupType := preload("res://scripts/popup/common_dialog_popup.gd")

const OUTER_MARGIN := 0.0

enum AppPage {
	HOME,
	PLAYLIST,
	PLAYER
}

@onready var preview_root: Control = %PreviewRoot
@onready var phone_shell: Panel = %PhoneShell
@onready var home_page: Control = %HomePage
@onready var playlist_page: Control = %PlaylistPage
@onready var player_page: Control = %PlayerPage
@onready var mini_player: Control = %MiniPlayer

var _current_page: int = AppPage.HOME
var _return_page: int = AppPage.HOME
var _playlist_back_target: int = AppPage.HOME
var _timer: Timer = Timer.new()

var _state: MusicAppStateDataType:
	get:
		return AppSave.data.music
	set(value):
		AppSave.data.music = value

var _selected_playlist_index: int:
	get:
		return _state.selected_playlist_index
	set(value):
		_state.selected_playlist_index = value

var _selected_track_index: int:
	get:
		return _state.selected_track_index
	set(value):
		_state.selected_track_index = value

var _elapsed_seconds: int:
	get:
		return _state.elapsed_seconds
	set(value):
		_state.elapsed_seconds = value

var _is_playing: bool:
	get:
		return _state.is_playing
	set(value):
		_state.is_playing = value

var _liked_tracks: Dictionary:
	get:
		return _state.liked_tracks
	set(value):
		_state.liked_tracks = value

var _tracks: Array[TrackDataType]:
	get:
		return _state.tracks
	set(value):
		_state.tracks = value

var _playlists: Array[PlaylistDataType]:
	get:
		return _state.playlists
	set(value):
		_state.playlists = value

func _ready() -> void:
	home_page.setup(self)
	playlist_page.setup(self)
	player_page.setup(self)
	mini_player.setup(self)
	add_child(_timer)
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_tick)
	_timer.start()
	_refresh_all_ui()
	_show_page(AppPage.HOME)
	_layout_preview()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_preview()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save_app_state()

func _refresh_all_ui() -> void:
	home_page.refresh()
	playlist_page.refresh()
	player_page.refresh()
	mini_player.refresh()

func _refresh_home_page() -> void:
	home_page.refresh()

func _refresh_playlist_page() -> void:
	playlist_page.refresh()

func _refresh_player_page() -> void:
	player_page.refresh()

func _refresh_mini_player() -> void:
	mini_player.refresh()
	mini_player.visible = _current_page != AppPage.PLAYER

func _show_page(page: int) -> void:
	_current_page = page
	MusicAppLayoutType.show_page(self, page, AppPage.PLAYER, AppPage.PLAYLIST, AppPage.HOME)

func _navigate_back() -> void:
	if _current_page == AppPage.PLAYER:
		player_page.navigate_back()
	elif _current_page == AppPage.PLAYLIST:
		playlist_page.close_page()

func _select_track(track_index: int, autoplay: bool) -> void:
	if _tracks.is_empty():
		return

	_selected_track_index = posmod(track_index, _tracks.size())
	_elapsed_seconds = _get_current_track().preview_start
	_is_playing = autoplay
	_refresh_all_ui()
	_save_app_state()

func _on_tick() -> void:
	player_page.on_tick()

func _has_tracks() -> bool:
	return not _tracks.is_empty()

func _get_current_track() -> TrackDataType:
	return _tracks[_selected_track_index]

func _get_current_duration() -> int:
	if _tracks.is_empty():
		return 0
	return _get_current_track().duration

func _get_selected_playlist() -> PlaylistDataType:
	return _playlists[_selected_playlist_index]

func _get_playlist_track_indices(index: int) -> Array[int]:
	if index < 0 or index >= _playlists.size():
		return []

	var result: Array[int] = []
	for item in _playlists[index].tracks:
		result.append(item)
	return result

func _is_current_track_liked() -> bool:
	if _tracks.is_empty():
		return false
	return bool(_liked_tracks.get(_track_key(_get_current_track()), false))

func _track_key(track: TrackDataType) -> String:
	return "%s - %s" % [track.title, track.artist]

func _next_playlist_title() -> String:
	var base_title := "新建歌单"
	var suffix := 1
	var title := base_title
	while _playlist_title_exists(title):
		suffix += 1
		title = "%s %d" % [base_title, suffix]
	return title

func _playlist_title_exists(title: String) -> bool:
	for playlist in _playlists:
		if playlist.title == title:
			return true
	return false

func _try_create_playlist_from_current() -> bool:
	if _tracks.is_empty():
		return false

	var title := _next_playlist_title()
	var track_ids: Array[int] = []
	var source_tracks: Array[int] = _get_playlist_track_indices(_selected_playlist_index)
	if source_tracks.is_empty():
		track_ids.append(_selected_track_index)
	else:
		var preview_count := mini(source_tracks.size(), 3)
		for index in preview_count:
			track_ids.append(source_tracks[index])

	var playlist := PlaylistDataType.new()
	playlist.title = title
	playlist.count = track_ids.size()
	playlist.mark = title.substr(0, 1)
	playlist.tracks = track_ids
	playlist.deletable = true
	_playlists.append(playlist)
	_selected_playlist_index = _playlists.size() - 1
	return true

func _page_home() -> int:
	return AppPage.HOME

func _page_playlist() -> int:
	return AppPage.PLAYLIST

func _page_player() -> int:
	return AppPage.PLAYER

func _set_return_page(page: int) -> void:
	_return_page = page

func _get_return_page() -> int:
	return _return_page

func _set_playlist_back_target(page: int) -> void:
	_playlist_back_target = page

func _get_playlist_back_target() -> int:
	return _playlist_back_target

func _layout_preview() -> void:
	MusicAppLayoutType.layout_preview(size, self, home_page, OUTER_MARGIN)

func _save_app_state() -> void:
	AppSave.save_data()

func _get_popup_manager() -> PopupManagerType:
	return get_node_or_null("/root/Popup") as PopupManagerType

func _show_common_alert(title: String, message: String) -> void:
	var popup_manager := _get_popup_manager()
	if popup_manager == null:
		push_error("Popup autoload is not available.")
		return

	var popup: PopupViewType = popup_manager.show(PopupRegistryType.PopupId.COMMON_DIALOG)
	if popup is CommonDialogPopupType:
		var dialog: CommonDialogPopupType = popup as CommonDialogPopupType
		dialog.show_alert(title, message)

func _show_no_tracks_popup() -> void:
	_show_common_alert("暂无歌曲", "请先导入歌曲后再使用这个功能。")

func _show_empty_playlist_popup() -> void:
	_show_common_alert("歌单为空", "这个歌单里还没有可播放的歌曲。")

func _show_playlist_deleted_popup(title: String) -> void:
	_show_common_alert("已删除", "歌单《%s》已删除。" % title)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if _current_page == AppPage.PLAYER:
		_navigate_back()
		get_viewport().set_input_as_handled()
	elif _current_page == AppPage.PLAYLIST:
		playlist_page.close_page()
		get_viewport().set_input_as_handled()
