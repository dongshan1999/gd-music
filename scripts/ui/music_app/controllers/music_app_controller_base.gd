class_name MusicAppControllerBase
extends RefCounted

const MusicAppShowcaseControllerType := preload("res://scripts/ui/music_app/music_app_showcase.gd")

var controller

func _init(owner = null) -> void:
	controller = owner

func get_showcase() -> MusicAppShowcaseControllerType:
	if controller != null:
		return controller
	return MusicAppShowcaseControllerType.instance

func get_tracks_ref() -> Array:
	var resolved_controller := get_showcase()
	return resolved_controller._tracks if resolved_controller != null else []

func get_playback_track_indices_ref() -> Array:
	var resolved_controller := get_showcase()
	return resolved_controller._playback_track_indices if resolved_controller != null else []

func get_playlists_ref() -> Array:
	var resolved_controller := get_showcase()
	return resolved_controller._playlists if resolved_controller != null else []

func get_selected_playlist_index() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._selected_playlist_index if resolved_controller != null else 0

func set_selected_playlist_index(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._selected_playlist_index = value

func get_selected_track_index() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._selected_track_index if resolved_controller != null else 0

func set_selected_track_index(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._selected_track_index = value

func get_playback_queue_index() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._playback_queue_index if resolved_controller != null else 0

func set_playback_queue_index(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._playback_queue_index = value

func get_elapsed_seconds() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._elapsed_seconds if resolved_controller != null else 0

func set_elapsed_seconds(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._elapsed_seconds = value

func is_playing() -> bool:
	var resolved_controller := get_showcase()
	return resolved_controller._is_playing if resolved_controller != null else false

func set_is_playing(value: bool) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._is_playing = value

func get_liked_tracks() -> Dictionary:
	var resolved_controller := get_showcase()
	return resolved_controller._liked_tracks if resolved_controller != null else {}

func set_liked_tracks(value: Dictionary) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._liked_tracks = value

func notify_state_changed() -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller.notify_state_changed()

func save_app_state() -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._save_app_state()

func request_audio_sync() -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null and resolved_controller.has_method("request_audio_sync"):
		resolved_controller.request_audio_sync()

func show_popup(popup_id: int):
	var resolved_controller := get_showcase()
	if resolved_controller == null:
		return null
	return resolved_controller.show_popup(popup_id)

func show_common_alert(title: String, message: String) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._show_common_alert(title, message)

func show_toast(message: String) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._show_toast(message)

func has_tracks() -> bool:
	return not get_tracks_ref().is_empty()

func get_current_track():
	var tracks := get_tracks_ref()
	var selected_track_index := get_selected_track_index()
	if selected_track_index < 0 or selected_track_index >= tracks.size():
		return null
	return tracks[selected_track_index]

func get_current_duration() -> int:
	var track = get_current_track()
	return track.duration if track != null else 0
