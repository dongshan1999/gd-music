class_name MusicAppPlaybackStateData
extends "res://dx/runtime/scripts/serializer/json_object.gd"

const DEFAULT_SELECTED_TRACK_ID := ""
const DEFAULT_SELECTED_PLAYLIST_INDEX := 0
const DEFAULT_QUEUE_INDEX := 0
const DEFAULT_MODE := 0
const MIN_MODE := 0
const MAX_MODE := 2
const DEFAULT_ELAPSED_SECONDS := 0
const DEFAULT_IS_PLAYING := false

var selected_track_id: String = DEFAULT_SELECTED_TRACK_ID
var selected_playlist_index: int = DEFAULT_SELECTED_PLAYLIST_INDEX
var track_ids: Array[String] = []
var queue_index: int = DEFAULT_QUEUE_INDEX
var mode: int = DEFAULT_MODE
var elapsed_seconds: int = DEFAULT_ELAPSED_SECONDS
var is_playing: bool = DEFAULT_IS_PLAYING

func normalize(valid_track_ids: Dictionary = {}, current_duration: int = 0, playlist_count: int = 0) -> void:
	selected_track_id = selected_track_id.strip_edges()
	selected_playlist_index = _clamp_index(selected_playlist_index, playlist_count)
	track_ids = _normalize_track_ids(track_ids, valid_track_ids)
	queue_index = _clamp_index(queue_index, track_ids.size())
	mode = clampi(mode, MIN_MODE, MAX_MODE)
	elapsed_seconds = maxi(0, elapsed_seconds)

	if track_ids.is_empty():
		selected_track_id = DEFAULT_SELECTED_TRACK_ID
		queue_index = DEFAULT_QUEUE_INDEX
		elapsed_seconds = DEFAULT_ELAPSED_SECONDS
		is_playing = DEFAULT_IS_PLAYING
		return

	selected_track_id = track_ids[queue_index]
	if current_duration > 0:
		elapsed_seconds = clampi(elapsed_seconds, 0, current_duration)

func _normalize_track_ids(source: Array, valid_track_ids: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for item in source:
		var track_id := str(item).strip_edges()
		if track_id.is_empty():
			continue
		if not valid_track_ids.is_empty() and not valid_track_ids.has(track_id):
			continue
		result.append(track_id)
	return result

func _clamp_index(index: int, size: int) -> int:
	if size <= 0:
		return 0
	return clampi(index, 0, size - 1)
