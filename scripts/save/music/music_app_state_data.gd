class_name MusicAppStateData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

const PlaybackStateDataScript := preload("res://scripts/save/music/music_app_playback_state_data.gd")

const SAVE_VERSION := "0.0.1"
const SYSTEM_FAVORITE_PLAYLIST_ID := "__music_app.favorite_playlist__"

enum PlaybackMode {
	LOOP_ALL,
	REPEAT_ONE,
	SHUFFLE
}

var version: String = SAVE_VERSION
var registered_version: String = ""
var registered_time: String = ""
var tracks: Array[TrackData] = []
var playlists: Array[PlaylistData] = []
var playback_state = PlaybackStateDataScript.new()
var plugin_search_history: Array[String] = []
var local_music_folders: Array[String] = []

static func is_system_favorite_playlist(playlist) -> bool:
	return playlist != null and playlist.title == SYSTEM_FAVORITE_PLAYLIST_ID

static func compare_versions(left: String, right: String) -> int:
	var left_parts := _parse_version_parts(left)
	var right_parts := _parse_version_parts(right)
	var max_size := maxi(left_parts.size(), right_parts.size())
	for index in max_size:
		var left_value := left_parts[index] if index < left_parts.size() else 0
		var right_value := right_parts[index] if index < right_parts.size() else 0
		if left_value < right_value:
			return -1
		if left_value > right_value:
			return 1
	return 0

static func _parse_version_parts(version_text: String) -> Array[int]:
	var result: Array[int] = []
	for part in version_text.strip_edges().split("."):
		result.append(int(part) if str(part).is_valid_int() else 0)
	return result

func _init() -> void:
	version = SAVE_VERSION
	registered_version = _get_current_app_version()
	registered_time = _get_current_time_string()
	tracks = _build_default_tracks()
	playlists = _build_default_playlists()
	playback_state = PlaybackStateDataScript.new()
	plugin_search_history = []
	local_music_folders = []
	normalize()

func normalize() -> void:
	version = SAVE_VERSION
	if registered_version.strip_edges().is_empty():
		registered_version = _get_current_app_version()
	if registered_time.strip_edges().is_empty():
		registered_time = _get_current_time_string()

	_normalize_tracks()
	var track_id_map := _build_track_id_map()
	_normalize_playlists(track_id_map)
	if playback_state == null:
		playback_state = PlaybackStateDataScript.new()
	playback_state.normalize(track_id_map, 0, playlists.size())
	var current_track := get_track_by_id(playback_state.selected_track_id)
	if current_track != null:
		playback_state.elapsed_seconds = clampi(playback_state.elapsed_seconds, 0, current_track.duration)
	plugin_search_history = _normalize_string_array(plugin_search_history, 10)
	local_music_folders = _normalize_path_array(local_music_folders)

func get_track_by_id(track_id: String) -> TrackData:
	var normalized_id := track_id.strip_edges()
	if normalized_id.is_empty():
		return null
	for track in tracks:
		if track != null and track.id == normalized_id:
			return track
	return null

func has_track_id(track_id: String) -> bool:
	return get_track_by_id(track_id) != null

func _normalize_tracks() -> void:
	var result: Array[TrackData] = []
	var seen_ids := {}
	for track in tracks:
		if track == null:
			continue
		track.normalize()
		if track.id.is_empty():
			track.id = TrackData.make_generated_id()
		if seen_ids.has(track.id):
			continue
		seen_ids[track.id] = true
		result.append(track)
	tracks = result

func _normalize_playlists(track_id_map: Dictionary) -> void:
	var result: Array[PlaylistData] = []
	var has_favorite_playlist := false
	for playlist in playlists:
		if playlist == null:
			continue

		var is_favorite_playlist := is_system_favorite_playlist(playlist)
		if is_favorite_playlist:
			if has_favorite_playlist:
				continue
			has_favorite_playlist = true

		var cleaned_tracks: Array[String] = []
		for track_id in playlist.tracks:
			var normalized_id := str(track_id).strip_edges()
			if normalized_id.is_empty() or not track_id_map.has(normalized_id):
				continue
			if is_favorite_playlist and cleaned_tracks.has(normalized_id):
				continue
			cleaned_tracks.append(normalized_id)

		playlist.tracks = cleaned_tracks
		playlist.count = cleaned_tracks.size()
		if is_favorite_playlist:
			playlist.title = SYSTEM_FAVORITE_PLAYLIST_ID
			playlist.mark = ""
			playlist.deletable = false
		result.append(playlist)

	_ensure_default_favorite_playlist(result)
	playlists = result

func _normalize_string_array(source: Array, max_count: int = -1) -> Array[String]:
	var result: Array[String] = []
	for item in source:
		var text := str(item).strip_edges()
		if text.is_empty() or result.has(text):
			continue
		result.append(text)
		if max_count > 0 and result.size() >= max_count:
			break
	return result

func _normalize_path_array(source: Array) -> Array[String]:
	var result: Array[String] = []
	for item in source:
		var path := str(item).strip_edges().replace("\\", "/")
		if path.ends_with("/") and path.length() > 1 and not path.ends_with(":/"):
			path = path.left(path.length() - 1)
		if path.is_empty() or result.has(path):
			continue
		result.append(path)
	return result

func _build_track_id_map() -> Dictionary:
	var result := {}
	for track in tracks:
		if track != null and not track.id.is_empty():
			result[track.id] = true
	return result

func _clamp_index(index: int, size: int) -> int:
	if size <= 0:
		return 0
	return clampi(index, 0, size - 1)

func _build_default_tracks() -> Array[TrackData]:
	return []

func _build_default_playlists() -> Array[PlaylistData]:
	return [
		_make_playlist(SYSTEM_FAVORITE_PLAYLIST_ID, "", [], false)
	]

func _ensure_default_favorite_playlist(target_playlists: Array[PlaylistData]) -> void:
	var favorite_index := -1
	var favorite_playlist: PlaylistData = null
	for index in target_playlists.size():
		if not is_system_favorite_playlist(target_playlists[index]):
			continue
		favorite_index = index
		favorite_playlist = target_playlists[index]
		break

	if favorite_playlist == null:
		favorite_playlist = _make_playlist(SYSTEM_FAVORITE_PLAYLIST_ID, "", [], false)
	else:
		favorite_playlist.title = SYSTEM_FAVORITE_PLAYLIST_ID
		favorite_playlist.mark = ""
		favorite_playlist.deletable = false
		favorite_playlist.count = favorite_playlist.tracks.size()
		if favorite_index > 0:
			target_playlists.remove_at(favorite_index)

	if favorite_index != 0:
		target_playlists.insert(0, favorite_playlist)

func _make_playlist(
	title: String,
	mark: String,
	track_ids: Array[String],
	deletable: bool
) -> PlaylistData:
	var playlist := PlaylistData.new()
	playlist.title = title
	playlist.mark = mark
	var copied_tracks: Array[String] = []
	for track_id in track_ids:
		copied_tracks.append(track_id)
	playlist.tracks = copied_tracks
	playlist.count = copied_tracks.size()
	playlist.deletable = deletable
	return playlist

func _get_current_app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

func _get_current_time_string() -> String:
	return Time.get_datetime_string_from_system()
