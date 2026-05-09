class_name MusicAppShowcaseController
extends Control

signal state_changed

static var instance = null

const MusicAppStateDataType := preload("res://scripts/save/music/music_app_state_data.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const AppSaveManagerType := preload("res://dx/runtime/scripts/managers/save/save_manager.gd")
const MusicAppLibraryControllerType := preload("res://scripts/ui/music_app/controllers/music_app_library_controller.gd")
const MusicAppPluginControllerType := preload("res://scripts/ui/music_app/controllers/music_app_plugin_controller.gd")
const PopupRegistryType := preload("res://dx/runtime/scripts/managers/popup/popup_registry.gd")
const PopupManagerType := preload("res://dx/runtime/scripts/managers/popup/popup_manager.gd")
const PopupViewType := preload("res://dx/runtime/scripts/managers/popup/popup_view.gd")
const CommonDialogPopupType := preload("res://scripts/popup/common_dialog_popup.gd")
const CommonToastPopupType := preload("res://scripts/popup/common_toast_popup.gd")

const HOME_POPUP_ID := PopupRegistryType.PopupId.MUSIC_APP_HOME
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
	instance = self

	var popup_manager := _get_popup_manager()
	if popup_manager != null:
		popup_manager.set_normal_host(normal_popup_host)
		popup_manager.set_fullscreen_host(fullscreen_popup_host)

	mini_player.setup(self)
	MusicAppLibraryControllerType.new().sync_favorite_playlist_from_likes()

	add_child(_timer)
	_timer.wait_time = 1.0
	if not _timer.timeout.is_connected(_on_tick):
		_timer.timeout.connect(_on_tick)
	_timer.start()

	_show_home_popup()
	call_deferred("_auto_start_plugin_host")

func _exit_tree() -> void:
	var popup_manager := _get_popup_manager()
	if popup_manager != null:
		popup_manager.clear_normal_host(normal_popup_host)
		popup_manager.clear_fullscreen_host(fullscreen_popup_host)
	if instance == self:
		instance = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		notify_state_changed()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save_app_state()

func _auto_start_plugin_host() -> void:
	await MusicAppPluginControllerType.new().auto_start_music_plugin_host()

func _select_track(track_index: int, autoplay: bool) -> void:
	if _tracks.is_empty():
		return

	_selected_track_index = posmod(track_index, _tracks.size())
	_elapsed_seconds = _get_current_track().preview_start
	_is_playing = autoplay
	notify_state_changed()
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

	notify_state_changed()

func _has_tracks() -> bool:
	return not _tracks.is_empty()

func _get_current_track() -> TrackDataType:
	return _tracks[_selected_track_index]

func _get_current_duration() -> int:
	if _tracks.is_empty():
		return 0
	return _get_current_track().duration

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
		notify_state_changed()
		return

	_is_playing = not _is_playing
	notify_state_changed()
	_save_app_state()

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
	show_popup(HOME_POPUP_ID)

func show_popup(popup_id: int):
	var popup_manager := _get_popup_manager()
	if popup_manager == null:
		return null

	var popup = popup_manager.show(popup_id)
	if popup != null and popup.has_method("setup"):
		popup.setup(self)
	return popup

func _show_toast(message: String) -> void:
	var popup_manager := _get_popup_manager()
	if popup_manager == null:
		return

	var popup: PopupViewType = popup_manager.show(TOAST_POPUP_ID)
	if popup is CommonToastPopupType:
		var toast_popup := popup as CommonToastPopupType
		toast_popup.show_message(message, 104.0 if mini_player.visible else 28.0)

func notify_state_changed() -> void:
	state_changed.emit()

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
