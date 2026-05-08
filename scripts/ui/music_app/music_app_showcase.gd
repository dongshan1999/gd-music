class_name MusicAppShowcaseController
extends Control

const MusicAppStateDataType := preload("res://scripts/save/music/music_app_state_data.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const AppSaveManagerType := preload("res://dx/runtime/scripts/managers/save/save_manager.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const PopupManagerType := preload("res://dx/runtime/scripts/managers/popup/popup_manager.gd")
const PopupViewType := preload("res://dx/runtime/scripts/managers/popup/popup_view.gd")
const CommonDialogPopupType := preload("res://scripts/popup/common_dialog_popup.gd")
const CommonToastPopupType := preload("res://scripts/popup/common_toast_popup.gd")
const WINDOWS_SCAN_ROOT := "windows://drives"
const AUDIO_EXTENSIONS := {
	"mp3": true,
	"wav": true,
	"ogg": true,
	"flac": true,
	"m4a": true,
	"aac": true
}

const HOME_POPUP_ID := PopupRegistryType.PopupId.MUSIC_APP_HOME
const PLAYLIST_POPUP_ID := PopupRegistryType.PopupId.MUSIC_APP_PLAYLIST
const PLAYER_POPUP_ID := PopupRegistryType.PopupId.MUSIC_APP_PLAYER
const LOCAL_MUSIC_POPUP_ID := PopupRegistryType.PopupId.MUSIC_APP_LOCAL_MUSIC
const LOCAL_SCAN_POPUP_ID := PopupRegistryType.PopupId.MUSIC_APP_LOCAL_SCAN
const TOAST_POPUP_ID := PopupRegistryType.PopupId.COMMON_TOAST

@onready var normal_popup_host: Control = %NormalPopupHost
@onready var mini_player: Control = %MiniPlayer
@onready var fullscreen_popup_host: Control = %FullscreenPopupHost

var _timer: Timer = Timer.new()
var _fallback_state := MusicAppStateDataType.new()

var _state: MusicAppStateDataType:
	get:
		var save_manager := DX.save as AppSaveManagerType
		return save_manager.data.music if save_manager != null else _fallback_state
	set(value):
		var save_manager := DX.save as AppSaveManagerType
		if save_manager != null:
			save_manager.data.music = value
		else:
			_fallback_state = value

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
	var popup_manager := _get_popup_manager()
	if popup_manager != null:
		popup_manager.set_normal_host(normal_popup_host)
		popup_manager.set_fullscreen_host(fullscreen_popup_host)
		if not popup_manager.popup_shown.is_connected(_on_popup_visibility_changed):
			popup_manager.popup_shown.connect(_on_popup_visibility_changed)
		if not popup_manager.popup_hidden.is_connected(_on_popup_visibility_changed):
			popup_manager.popup_hidden.connect(_on_popup_visibility_changed)

	mini_player.setup(self)
	_sync_favorite_playlist_from_likes()

	add_child(_timer)
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_tick)
	_timer.start()

	_show_home_popup()
	_refresh_all_ui()

func _exit_tree() -> void:
	var popup_manager := _get_popup_manager()
	if popup_manager != null:
		if popup_manager.popup_shown.is_connected(_on_popup_visibility_changed):
			popup_manager.popup_shown.disconnect(_on_popup_visibility_changed)
		if popup_manager.popup_hidden.is_connected(_on_popup_visibility_changed):
			popup_manager.popup_hidden.disconnect(_on_popup_visibility_changed)
		popup_manager.clear_normal_host(normal_popup_host)
		popup_manager.clear_fullscreen_host(fullscreen_popup_host)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_all_ui()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save_app_state()

func _refresh_all_ui() -> void:
	_refresh_home_page()
	_refresh_playlist_page()
	_refresh_player_page()
	_refresh_local_music_page()
	_refresh_local_scan_page()
	_refresh_mini_player()

func _refresh_home_page() -> void:
	_refresh_popup(HOME_POPUP_ID)

func _refresh_playlist_page() -> void:
	_refresh_popup(PLAYLIST_POPUP_ID)

func _refresh_player_page() -> void:
	_refresh_popup(PLAYER_POPUP_ID)

func _refresh_mini_player() -> void:
	mini_player.refresh()
	mini_player.visible = _get_popup(PLAYER_POPUP_ID) == null and _get_popup(LOCAL_SCAN_POPUP_ID) == null

func _refresh_local_music_page() -> void:
	_refresh_popup(LOCAL_MUSIC_POPUP_ID)

func _refresh_local_scan_page() -> void:
	_refresh_popup(LOCAL_SCAN_POPUP_ID)

func _select_track(track_index: int, autoplay: bool) -> void:
	if _tracks.is_empty():
		return

	_selected_track_index = posmod(track_index, _tracks.size())
	_elapsed_seconds = _get_current_track().preview_start
	_is_playing = autoplay
	_refresh_all_ui()
	_save_app_state()

func _on_tick() -> void:
	if not _has_tracks():
		_is_playing = false
		return

	if not _is_playing:
		return

	_elapsed_seconds += 1
	if _elapsed_seconds >= _get_current_duration():
		_select_track(_selected_track_index + 1, true)
		return

	_refresh_player_page()
	_refresh_mini_player()
	_refresh_playlist_page()

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

func _is_track_liked(track_index: int) -> bool:
	if track_index < 0 or track_index >= _tracks.size():
		return false
	return bool(_liked_tracks.get(_track_key(_tracks[track_index]), false))

func _track_key(track: TrackDataType) -> String:
	if not track.file_path.is_empty():
		return track.file_path
	return "%s - %s" % [track.title, track.artist]

func _get_local_track_indices() -> Array[int]:
	var result: Array[int] = []
	for index in _tracks.size():
		var track := _tracks[index]
		if track == null:
			continue
		if not track.file_path.is_empty() or track.source == "LOCAL":
			result.append(index)
	return result

func _is_system_favorite_playlist(playlist: PlaylistDataType) -> bool:
	return MusicAppStateDataType.is_system_favorite_playlist(playlist)

func _get_playlist_display_title(playlist: PlaylistDataType) -> String:
	if _is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_title")
	return playlist.title

func _get_playlist_display_mark(playlist: PlaylistDataType) -> String:
	if _is_system_favorite_playlist(playlist):
		return tr("music_app.playlist.favorites_mark")
	if not playlist.mark.is_empty():
		return playlist.mark
	var title := _get_playlist_display_title(playlist)
	return title.left(1) if not title.is_empty() else ""

func _format_song_count(count: int) -> String:
	return tr("music_app.common.song_count").format({"count": count})

func _format_total_track_count(count: int) -> String:
	return tr("music_app.playlist.total_tracks").format({"count": count})

func _get_track_display_artist(track: TrackDataType) -> String:
	if not track.artist.is_empty():
		return track.artist
	if not track.subtitle.is_empty():
		return track.subtitle
	return tr("music_app.track.local_file")

func _next_playlist_title() -> String:
	var base_title := tr("music_app.playlist.new_playlist")
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
	var title := _next_playlist_title()
	var playlist := PlaylistDataType.new()
	playlist.title = title
	playlist.count = 0
	playlist.mark = title.left(1)
	playlist.tracks = []
	playlist.deletable = true
	_playlists.append(playlist)
	_selected_playlist_index = _playlists.size() - 1
	return true

func _sync_favorite_playlist_from_likes() -> void:
	var favorite_playlist := _get_or_create_favorite_playlist()
	var liked_track_indices: Array[int] = []
	for index in _tracks.size():
		if _is_track_liked(index):
			liked_track_indices.append(index)

	favorite_playlist.title = MusicAppStateDataType.SYSTEM_FAVORITE_PLAYLIST_ID
	favorite_playlist.mark = ""
	favorite_playlist.deletable = false
	favorite_playlist.tracks = liked_track_indices
	favorite_playlist.count = liked_track_indices.size()

func _get_or_create_favorite_playlist() -> PlaylistDataType:
	var favorite_index := _find_favorite_playlist_index()
	if favorite_index >= 0:
		return _playlists[favorite_index]

	var favorite_playlist := PlaylistDataType.new()
	favorite_playlist.title = MusicAppStateDataType.SYSTEM_FAVORITE_PLAYLIST_ID
	favorite_playlist.mark = ""
	favorite_playlist.deletable = false
	favorite_playlist.count = 0
	favorite_playlist.tracks = []
	_playlists.insert(0, favorite_playlist)
	if _playlists.size() > 1:
		_selected_playlist_index += 1
	return favorite_playlist

func _find_favorite_playlist_index() -> int:
	for index in _playlists.size():
		if _is_system_favorite_playlist(_playlists[index]):
			return index
	return -1

func _save_app_state() -> void:
	var save_manager := DX.save as AppSaveManagerType
	if save_manager != null:
		save_manager.save_data()

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
	_show_common_alert(
		tr("music_app.alert.no_tracks_title"),
		tr("music_app.alert.no_tracks_message")
	)

func _show_empty_playlist_popup() -> void:
	_show_common_alert(
		tr("music_app.alert.empty_playlist_title"),
		tr("music_app.alert.empty_playlist_message")
	)

func _show_playlist_deleted_popup(title: String) -> void:
	_show_common_alert(
		tr("music_app.alert.deleted_title"),
		tr("music_app.alert.deleted_message").format({"title": title})
	)

func toggle_playback() -> void:
	if not _has_tracks():
		_is_playing = false
		_refresh_player_page()
		_refresh_mini_player()
		return

	_is_playing = not _is_playing
	_refresh_player_page()
	_refresh_mini_player()
	_refresh_playlist_page()
	_save_app_state()

func _refresh_popup(popup_id: int) -> void:
	var popup = _get_popup(popup_id)
	if popup == null or not popup.has_method("refresh"):
		return
	popup.refresh()

func _get_popup_manager() -> PopupManagerType:
	return DX.popup as PopupManagerType

func _get_popup(popup_id: int):
	var popup_manager := _get_popup_manager()
	if popup_manager == null or not popup_manager.has_method("get_popup"):
		return null
	return popup_manager.get_popup(popup_id)

func _get_current_popup():
	var popup_manager := _get_popup_manager()
	if popup_manager == null or not popup_manager.has_method("get_current_popup"):
		return null
	return popup_manager.get_current_popup()

func _show_home_popup() -> void:
	var popup_manager := _get_popup_manager()
	if popup_manager == null:
		return

	var home_popup = popup_manager.show(HOME_POPUP_ID)
	if home_popup != null and home_popup.has_method("setup"):
		home_popup.setup(self)

func _on_popup_visibility_changed(_popup_id = null, _popup = null) -> void:
	_refresh_mini_player()

func _show_toast(message: String) -> void:
	var popup_manager := _get_popup_manager()
	if popup_manager == null:
		return

	var popup: PopupViewType = popup_manager.show(TOAST_POPUP_ID)
	if popup is CommonToastPopupType:
		var toast_popup := popup as CommonToastPopupType
		toast_popup.show_message(message, 104.0 if mini_player.visible else 28.0)

func _get_scan_root_path() -> String:
	var os_name := OS.get_name()
	if os_name == "Android":
		for candidate in ["/storage/emulated/0", "/sdcard", "/storage/self/primary"]:
			if DirAccess.dir_exists_absolute(candidate):
				return candidate
		return "/"
	if os_name == "Windows":
		return WINDOWS_SCAN_ROOT

	var base_path := OS.get_environment("USERPROFILE")
	if base_path.is_empty():
		base_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if base_path.is_empty():
		base_path = ProjectSettings.globalize_path("res://")
	return _path_root(base_path)

func _get_scan_display_path(path: String) -> String:
	var normalized_path := _normalize_path(path)
	if _is_scan_virtual_root(normalized_path):
		return tr("music_app.scan.windows_root")
	return normalized_path

func _get_scan_parent_path(current_path: String, root_path: String) -> String:
	var normalized_current := _normalize_path(current_path)
	var normalized_root := _normalize_path(root_path)
	if normalized_current == normalized_root:
		return normalized_root
	if _is_scan_virtual_root(normalized_root) and _is_windows_drive_root(normalized_current):
		return normalized_root

	var parent := _normalize_path(normalized_current.get_base_dir())
	if parent.is_empty():
		return normalized_root
	if parent.ends_with(":"):
		parent += "/"
	if parent.length() < normalized_root.length():
		return normalized_root
	return parent

func _list_scan_directories(path: String) -> Array[Dictionary]:
	var normalized_path := _normalize_path(path)
	if _is_scan_virtual_root(normalized_path):
		return _list_windows_drive_entries()
	if not DirAccess.dir_exists_absolute(normalized_path):
		return []

	var result: Array[Dictionary] = []
	var directory_names := DirAccess.get_directories_at(normalized_path)
	directory_names.sort()
	for directory_name in directory_names:
		if directory_name in [".", ".."]:
			continue
		result.append(
			{
				"name": directory_name,
				"path": _normalize_path(normalized_path.path_join(directory_name))
			}
		)
	return result

func _list_windows_drive_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for index in letters.length():
		var drive_letter := letters.substr(index, 1)
		var drive_path := "%s:/" % drive_letter
		if not DirAccess.dir_exists_absolute(drive_path):
			continue
		result.append(
			{
				"name": "%s:" % drive_letter,
				"path": drive_path
			}
		)
	return result

func _scan_local_music_directories(paths: Array[String]) -> int:
	var existing_paths := {}
	for track in _tracks:
		if track == null or track.file_path.is_empty():
			continue
		existing_paths[_normalize_path(track.file_path)] = true

	var imported_tracks: Array[TrackDataType] = []
	var unique_targets := {}
	for raw_path in paths:
		var target_path := _normalize_path(str(raw_path))
		if target_path.is_empty() or unique_targets.has(target_path):
			continue
		unique_targets[target_path] = true
		_collect_audio_tracks(target_path, existing_paths, imported_tracks)

	for track in imported_tracks:
		_tracks.append(track)

	if not imported_tracks.is_empty():
		_refresh_all_ui()
		_save_app_state()

	return imported_tracks.size()

func _collect_audio_tracks(
	root_path: String,
	existing_paths: Dictionary,
	imported_tracks: Array[TrackDataType]
) -> void:
	var normalized_root := _normalize_path(root_path)
	if not DirAccess.dir_exists_absolute(normalized_root):
		return

	var directory := DirAccess.open(normalized_root)
	if directory == null:
		return

	directory.list_dir_begin()
	while true:
		var item_name := directory.get_next()
		if item_name.is_empty():
			break
		if item_name in [".", ".."]:
			continue

		var item_path := _normalize_path(normalized_root.path_join(item_name))
		if directory.current_is_dir():
			_collect_audio_tracks(item_path, existing_paths, imported_tracks)
			continue

		if not _is_audio_file(item_path) or existing_paths.has(item_path):
			continue

		existing_paths[item_path] = true
		imported_tracks.append(_make_local_track_from_path(item_path))
	directory.list_dir_end()

func _is_audio_file(path: String) -> bool:
	var extension := path.get_extension().to_lower()
	return AUDIO_EXTENSIONS.has(extension)

func _make_local_track_from_path(path: String) -> TrackDataType:
	var normalized_path := _normalize_path(path)
	var file_stem := normalized_path.get_file().get_basename()
	var title := file_stem
	var artist := ""
	var separator := " - "
	var separator_index := file_stem.find(separator)
	if separator_index >= 0:
		artist = file_stem.substr(0, separator_index).strip_edges()
		title = file_stem.substr(separator_index + separator.length()).strip_edges()
		if title.is_empty():
			title = file_stem

	var subtitle := normalized_path.get_base_dir().get_file()

	var track := TrackDataType.new()
	track.title = title
	track.artist = artist
	track.subtitle = subtitle
	track.duration = 180
	track.preview_start = 0
	track.mark = title.left(1) if not title.is_empty() else "L"
	track.source = "LOCAL"
	track.file_path = normalized_path
	track.normalize()
	return track

func _path_root(path: String) -> String:
	var normalized := _normalize_path(path)
	var drive_index := normalized.find(":/")
	if drive_index >= 0:
		return normalized.substr(0, drive_index + 2) + "/"
	if normalized.begins_with("/"):
		return "/"
	return normalized

func _normalize_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.ends_with("/") and normalized.length() > 1 and not normalized.ends_with(":/"):
		normalized = normalized.left(normalized.length() - 1)
	return normalized

func _is_scan_virtual_root(path: String) -> bool:
	return _normalize_path(path) == WINDOWS_SCAN_ROOT

func _is_windows_drive_root(path: String) -> bool:
	return path.length() == 3 and path.substr(1, 1) == ":" and path.ends_with("/")

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	var current_popup = _get_current_popup()
	if current_popup == null or current_popup == _get_popup(HOME_POPUP_ID):
		return

	var popup_manager := _get_popup_manager()
	if popup_manager != null:
		popup_manager.hide()
		get_viewport().set_input_as_handled()
