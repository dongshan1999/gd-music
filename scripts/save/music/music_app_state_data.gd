class_name MusicAppStateData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

const SAVE_VERSION := 4
const DEFAULT_SELECTED_PLAYLIST_INDEX := 0
const DEFAULT_SELECTED_TRACK_INDEX := 0
const DEFAULT_PLAYBACK_QUEUE_INDEX := 0
const DEFAULT_PLAYBACK_MODE := PlaybackMode.LOOP_ALL
const DEFAULT_ELAPSED_SECONDS := 0
const DEFAULT_IS_PLAYING := false
const DEFAULT_LIKED_TRACKS := {}
const SYSTEM_FAVORITE_PLAYLIST_ID := "__music_app.favorite_playlist__"
const DEFAULT_VISUALIZER_SETTINGS := {
	"enabled": true,
	"mode": "mineradio",
	"quality": "medium",
	"particles": 1.0,
	"bloom": 1.0
}
const VISUALIZER_MODE_MINERADIO := "mineradio"
const VISUALIZER_MODE_CITY := "city"
const VISUALIZER_QUALITY_OFF := "off"
const VISUALIZER_QUALITY_LOW := "low"
const VISUALIZER_QUALITY_MEDIUM := "medium"
const VISUALIZER_QUALITY_HIGH := "high"

enum PlaybackMode {
	LOOP_ALL,
	REPEAT_ONE,
	SHUFFLE
}

var version: int = SAVE_VERSION
var tracks: Array[TrackData] = []
var playlists: Array[PlaylistData] = []
var selected_playlist_index: int = DEFAULT_SELECTED_PLAYLIST_INDEX
var selected_track_index: int = DEFAULT_SELECTED_TRACK_INDEX
var playback_track_indices: Array[int] = []
var playback_queue_index: int = DEFAULT_PLAYBACK_QUEUE_INDEX
var playback_mode: int = DEFAULT_PLAYBACK_MODE
var elapsed_seconds: int = DEFAULT_ELAPSED_SECONDS
var is_playing: bool = DEFAULT_IS_PLAYING
var liked_tracks: Dictionary = {}
var plugin_search_history: Array[String] = []
var visualizer_settings: Dictionary = {}

static func is_system_favorite_playlist(playlist) -> bool:
	if playlist == null:
		return false
	if playlist.title == SYSTEM_FAVORITE_PLAYLIST_ID:
		return true
	return not playlist.deletable and (
		playlist.title.is_empty()
		or playlist.title in _legacy_favorite_playlist_titles()
		or playlist.mark in _legacy_favorite_playlist_marks()
	)

static func _legacy_favorite_playlist_titles() -> Array[String]:
	return [
		SYSTEM_FAVORITE_PLAYLIST_ID,
		"\u6211\u559c\u6b22",
		"Liked"
	]

static func _legacy_favorite_playlist_marks() -> Array[String]:
	return [
		"",
		"\u6211",
		"L"
	]

func _init() -> void:
	version = SAVE_VERSION
	tracks = _build_default_tracks()
	playlists = _build_default_playlists()
	selected_playlist_index = DEFAULT_SELECTED_PLAYLIST_INDEX
	selected_track_index = DEFAULT_SELECTED_TRACK_INDEX
	playback_track_indices = []
	playback_queue_index = DEFAULT_PLAYBACK_QUEUE_INDEX
	playback_mode = DEFAULT_PLAYBACK_MODE
	elapsed_seconds = DEFAULT_ELAPSED_SECONDS
	is_playing = DEFAULT_IS_PLAYING
	liked_tracks = DEFAULT_LIKED_TRACKS.duplicate(true)
	plugin_search_history = []
	visualizer_settings = _build_default_visualizer_settings()
	normalize()

func normalize() -> void:
	version = maxi(SAVE_VERSION, version)
	_normalize_tracks()
	_normalize_playlists()
	selected_playlist_index = _clamp_index(selected_playlist_index, playlists.size())
	selected_track_index = _clamp_index(selected_track_index, tracks.size())
	playback_track_indices = _normalize_playback_track_indices(playback_track_indices)
	playback_queue_index = _clamp_index(playback_queue_index, playback_track_indices.size())
	playback_mode = clampi(playback_mode, PlaybackMode.LOOP_ALL, PlaybackMode.SHUFFLE)
	elapsed_seconds = maxi(0, elapsed_seconds)
	liked_tracks = _normalize_liked_tracks(liked_tracks)
	plugin_search_history = _normalize_string_array(plugin_search_history, 10)
	visualizer_settings = _normalize_visualizer_settings(visualizer_settings)

	if tracks.is_empty():
		elapsed_seconds = 0
		is_playing = false
	else:
		if not playback_track_indices.is_empty():
			selected_track_index = playback_track_indices[playback_queue_index]
		elapsed_seconds = clampi(elapsed_seconds, 0, tracks[selected_track_index].duration)

func _normalize_tracks() -> void:
	var result: Array[TrackData] = []
	for track in tracks:
		if track == null:
			continue
		track.normalize()
		result.append(track)
	tracks = result

func _normalize_playlists() -> void:
	var result: Array[PlaylistData] = []
	for playlist in playlists:
		if playlist == null:
			continue

		var cleaned_tracks: Array[int] = []
		for track_index in playlist.tracks:
			if track_index >= 0 and track_index < tracks.size():
				cleaned_tracks.append(track_index)

		playlist.tracks = cleaned_tracks
		if playlist.count <= 0:
			playlist.count = cleaned_tracks.size()
		if is_system_favorite_playlist(playlist):
			playlist.title = SYSTEM_FAVORITE_PLAYLIST_ID
			playlist.mark = ""
			playlist.deletable = false
		result.append(playlist)

	_ensure_default_favorite_playlist(result)
	playlists = result

func _normalize_liked_tracks(source_liked_tracks: Dictionary) -> Dictionary:
	var result := {}
	for key in source_liked_tracks:
		result[str(key)] = bool(source_liked_tracks[key])
	return result

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

func _normalize_visualizer_settings(source: Dictionary) -> Dictionary:
	var result := _build_default_visualizer_settings()
	for key in source:
		result[str(key)] = source[key]

	result["enabled"] = bool(result.get("enabled", DEFAULT_VISUALIZER_SETTINGS["enabled"]))
	var mode := str(result.get("mode", DEFAULT_VISUALIZER_SETTINGS["mode"])).strip_edges().to_lower()
	if not [
		VISUALIZER_MODE_MINERADIO,
		VISUALIZER_MODE_CITY
	].has(mode):
		mode = DEFAULT_VISUALIZER_SETTINGS["mode"]
	result["mode"] = mode
	var quality := str(result.get("quality", DEFAULT_VISUALIZER_SETTINGS["quality"])).strip_edges().to_lower()
	if not [
		VISUALIZER_QUALITY_OFF,
		VISUALIZER_QUALITY_LOW,
		VISUALIZER_QUALITY_MEDIUM,
		VISUALIZER_QUALITY_HIGH
	].has(quality):
		quality = DEFAULT_VISUALIZER_SETTINGS["quality"]
	result["quality"] = quality
	result["particles"] = clampf(float(result.get("particles", DEFAULT_VISUALIZER_SETTINGS["particles"])), 0.25, 1.5)
	result["bloom"] = clampf(float(result.get("bloom", DEFAULT_VISUALIZER_SETTINGS["bloom"])), 0.0, 1.5)
	return result

func _build_default_visualizer_settings() -> Dictionary:
	var result := DEFAULT_VISUALIZER_SETTINGS.duplicate(true)
	if OS.get_name() in ["Android", "iOS", "Web"]:
		result["quality"] = VISUALIZER_QUALITY_LOW
		result["particles"] = 0.65
		result["bloom"] = 0.75
	return result

func _normalize_playback_track_indices(source_track_indices: Array) -> Array[int]:
	var result: Array[int] = []
	for track_index in source_track_indices:
		if track_index < 0 or track_index >= tracks.size():
			continue
		result.append(track_index)
	return result

func _clamp_index(index: int, size: int) -> int:
	if size <= 0:
		return 0
	return clampi(index, 0, size - 1)

func _build_default_tracks() -> Array[TrackData]:
	return []

func _build_default_playlists() -> Array[PlaylistData]:
	return [
		_make_playlist(SYSTEM_FAVORITE_PLAYLIST_ID, 0, "", [], false)
	]

func _ensure_default_favorite_playlist(target_playlists: Array[PlaylistData]) -> void:
	for playlist in target_playlists:
		if not is_system_favorite_playlist(playlist):
			continue
		playlist.title = SYSTEM_FAVORITE_PLAYLIST_ID
		playlist.mark = ""
		playlist.deletable = false
		if playlist.count <= 0:
			playlist.count = playlist.tracks.size()
		return

	target_playlists.append(
		_make_playlist(SYSTEM_FAVORITE_PLAYLIST_ID, 0, "", [], false)
	)

func _make_track(
	title: String,
	artist: String,
	subtitle: String,
	duration: int,
	preview_start: int,
	mark: String,
	source: String
) -> TrackData:
	var track := TrackData.new()
	track.title = title
	track.artist = artist
	track.subtitle = subtitle
	track.duration = duration
	track.preview_start = preview_start
	track.mark = mark
	track.source = source
	track.normalize()
	return track

func _make_playlist(
	title: String,
	count: int,
	mark: String,
	track_indices: Array[int],
	deletable: bool
) -> PlaylistData:
	var playlist := PlaylistData.new()
	playlist.title = title
	playlist.count = count
	playlist.mark = mark
	var copied_tracks: Array[int] = []
	for track_index in track_indices:
		copied_tracks.append(track_index)
	playlist.tracks = copied_tracks
	playlist.deletable = deletable
	return playlist
