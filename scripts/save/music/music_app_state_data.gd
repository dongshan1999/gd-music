class_name MusicAppStateData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

const TrackDataType := preload("res://scripts/save/music/track_data.gd")
const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")

const SAVE_VERSION := 1
const DEFAULT_SELECTED_PLAYLIST_INDEX := 0
const DEFAULT_SELECTED_TRACK_INDEX := 0
const DEFAULT_ELAPSED_SECONDS := 0
const DEFAULT_IS_PLAYING := false
const DEFAULT_LIKED_TRACKS := {}
const SYSTEM_FAVORITE_PLAYLIST_ID := "__music_app.favorite_playlist__"

var version: int = SAVE_VERSION
var tracks: Array[TrackDataType] = []
var playlists: Array[PlaylistDataType] = []
var selected_playlist_index: int = DEFAULT_SELECTED_PLAYLIST_INDEX
var selected_track_index: int = DEFAULT_SELECTED_TRACK_INDEX
var elapsed_seconds: int = DEFAULT_ELAPSED_SECONDS
var is_playing: bool = DEFAULT_IS_PLAYING
var liked_tracks: Dictionary = {}

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
	elapsed_seconds = DEFAULT_ELAPSED_SECONDS
	is_playing = DEFAULT_IS_PLAYING
	liked_tracks = DEFAULT_LIKED_TRACKS.duplicate(true)
	normalize()

func normalize() -> void:
	version = maxi(SAVE_VERSION, version)
	_normalize_tracks()
	_normalize_playlists()
	selected_playlist_index = _clamp_index(selected_playlist_index, playlists.size())
	selected_track_index = _clamp_index(selected_track_index, tracks.size())
	elapsed_seconds = maxi(0, elapsed_seconds)
	liked_tracks = _normalize_liked_tracks(liked_tracks)

	if tracks.is_empty():
		elapsed_seconds = 0
		is_playing = false
	else:
		elapsed_seconds = clampi(elapsed_seconds, 0, tracks[selected_track_index].duration)

func _normalize_tracks() -> void:
	var result: Array[TrackDataType] = []
	for track in tracks:
		if track == null:
			continue
		track.normalize()
		result.append(track)
	tracks = result

func _normalize_playlists() -> void:
	var result: Array[PlaylistDataType] = []
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

func _clamp_index(index: int, size: int) -> int:
	if size <= 0:
		return 0
	return clampi(index, 0, size - 1)

func _build_default_tracks() -> Array[TrackDataType]:
	return []

func _build_default_playlists() -> Array[PlaylistDataType]:
	return [
		_make_playlist(SYSTEM_FAVORITE_PLAYLIST_ID, 0, "", [], false)
	]

func _ensure_default_favorite_playlist(target_playlists: Array[PlaylistDataType]) -> void:
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
	source: String,
	accent: Color,
	secondary: Color,
	tertiary: Color
) -> TrackDataType:
	var track := TrackDataType.new()
	track.title = title
	track.artist = artist
	track.subtitle = subtitle
	track.duration = duration
	track.preview_start = preview_start
	track.mark = mark
	track.source = source
	track.accent = accent
	track.secondary = secondary
	track.tertiary = tertiary
	track.normalize()
	return track

func _make_playlist(
	title: String,
	count: int,
	mark: String,
	track_indices: Array[int],
	deletable: bool
) -> PlaylistDataType:
	var playlist := PlaylistDataType.new()
	playlist.title = title
	playlist.count = count
	playlist.mark = mark
	var copied_tracks: Array[int] = []
	for track_index in track_indices:
		copied_tracks.append(track_index)
	playlist.tracks = copied_tracks
	playlist.deletable = deletable
	return playlist
