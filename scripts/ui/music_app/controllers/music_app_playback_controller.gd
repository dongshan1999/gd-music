class_name MusicAppPlaybackController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const TrackDataType := preload("res://scripts/save/music/track_data.gd")

## 返回当前播放列表中的曲目索引序列。
func get_playback_track_indices() -> Array[int]:
	var resolved_controller := get_showcase()
	if resolved_controller == null:
		return []

	var result: Array[int] = []
	for track_index in resolved_controller._playback_track_indices:
		result.append(track_index)
	return result

## 返回当前播放列表中的曲目数量。
func get_playback_track_count() -> int:
	return get_playback_track_indices().size()

## 返回当前播放列表的游标位置。
func get_playback_queue_index() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._playback_queue_index if resolved_controller != null else 0

## 设置当前播放列表的游标位置。
func set_playback_queue_index(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._playback_queue_index = value

## 判断当前是否存在有效的播放列表。
func has_playback_queue() -> bool:
	return not get_playback_track_indices().is_empty()

## 按顺序替换播放列表，并设置当前播放项。
func set_playback_queue(track_indices: Array[int], start_queue_index: int = 0) -> bool:
	var resolved_track_indices := _sanitize_track_indices(track_indices)
	if resolved_track_indices.is_empty():
		clear_playback_queue()
		return false

	var clamped_queue_index := clampi(start_queue_index, 0, resolved_track_indices.size() - 1)
	var current_track_index := resolved_track_indices[clamped_queue_index]

	set_playback_track_indices(resolved_track_indices)
	set_playback_queue_index(clamped_queue_index)
	set_selected_track_index(current_track_index)
	return true

## 清空播放列表并复位游标。
func clear_playback_queue() -> void:
	set_playback_track_indices([])
	set_playback_queue_index(0)
	set_is_playing(false)
	request_audio_sync()
	notify_state_changed()
	save_app_state()

## 基于单首曲目构建播放列表。
func set_single_track_queue(track_index: int) -> bool:
	return set_playback_queue([track_index], 0)

## 从当前播放列表游标解析当前曲目索引。
func get_current_playback_track_index() -> int:
	var playback_track_indices := get_playback_track_indices()
	if playback_track_indices.is_empty():
		return -1

	var queue_index := clampi(get_playback_queue_index(), 0, playback_track_indices.size() - 1)
	return playback_track_indices[queue_index]

## 返回当前播放列表对应的当前曲目对象。
func get_current_playback_track() -> TrackDataType:
	var resolved_controller := get_showcase()
	if resolved_controller == null:
		return null

	var track_index := get_current_playback_track_index()
	var tracks := resolved_controller._tracks
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]

## 查找某个曲目在当前播放列表中的槽位。
func find_queue_index_for_track(track_index: int) -> int:
	var playback_track_indices := get_playback_track_indices()
	for index in playback_track_indices.size():
		if playback_track_indices[index] == track_index:
			return index
	return -1

## 基于游标偏移切换到播放列表中的上一首或下一首。
func step_queue(offset: int, autoplay: bool = true) -> bool:
	var playback_track_indices := get_playback_track_indices()
	if playback_track_indices.is_empty():
		return false

	var next_queue_index := posmod(get_playback_queue_index() + offset, playback_track_indices.size())
	return play_queue_index(next_queue_index, autoplay)

## 播放播放列表中指定槽位的曲目。
func play_queue_index(queue_index: int, autoplay: bool = true) -> bool:
	var playback_track_indices := get_playback_track_indices()
	if playback_track_indices.is_empty():
		return false
	if queue_index < 0 or queue_index >= playback_track_indices.size():
		return false

	set_playback_queue_index(queue_index)
	set_selected_track_index(playback_track_indices[queue_index])
	set_elapsed_seconds(get_current_duration_preview_start())
	set_is_playing(autoplay)
	request_audio_sync()
	notify_state_changed()
	save_app_state()
	return true

## 根据曲目索引获取默认起播进度。
func get_current_duration_preview_start() -> int:
	var track := get_current_playback_track()
	return track.preview_start if track != null else 0

## 将播放列表中不存在的曲目追加到末尾。
func append_tracks_to_queue(track_indices: Array[int]) -> int:
	var next_queue := get_playback_track_indices()
	var existing := {}
	for track_index in next_queue:
		existing[track_index] = true

	var appended_count := 0
	for track_index in _sanitize_track_indices(track_indices):
		if existing.has(track_index):
			continue
		existing[track_index] = true
		next_queue.append(track_index)
		appended_count += 1

	if appended_count > 0:
		set_playback_track_indices(next_queue)
		save_app_state()
	return appended_count

func set_playback_track_indices(track_indices: Array[int]) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._playback_track_indices = track_indices.duplicate()

func _sanitize_track_indices(track_indices: Array[int]) -> Array[int]:
	var tracks := get_tracks_ref()
	var result: Array[int] = []
	for track_index in track_indices:
		if track_index < 0 or track_index >= tracks.size():
			continue
		result.append(track_index)
	return result
