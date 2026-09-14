class_name MusicAppPlaybackController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const MusicAppIconsType := preload("res://scripts/constants/music_app_icons.gd")

## 返回当前播放列表中的曲目 ID 序列。
func get_playback_track_ids() -> Array[String]:
	var result: Array[String] = []
	for track_id in get_playback_track_ids_ref():
		result.append(track_id)
	return result

## 返回当前播放列表中的曲目数量。
func get_playback_track_count() -> int:
	return get_playback_track_ids().size()

## 返回当前播放列表的游标位置。
func get_playback_queue_index() -> int:
	return super.get_playback_queue_index()

## 设置当前播放列表的游标位置。
func set_playback_queue_index(value: int) -> void:
	super.set_playback_queue_index(value)

## 返回当前全局播放模式。
func get_playback_mode() -> int:
	return super.get_playback_mode()

## 设置当前全局播放模式。
func set_playback_mode(value: int, _persist_state: bool = true) -> void:
	var clamped_mode := clampi(
		value,
		MusicAppStateDataType.PlaybackMode.LOOP_ALL,
		MusicAppStateDataType.PlaybackMode.SHUFFLE
	)
	if get_playback_mode() == clamped_mode:
		return

	super.set_playback_mode(clamped_mode)

## 循环切换播放模式，并返回切换后的值。
func cycle_playback_mode() -> int:
	const PLAYBACK_MODE_COUNT := 3
	var next_mode := posmod(get_playback_mode() + 1, PLAYBACK_MODE_COUNT)
	set_playback_mode(next_mode)
	return next_mode

## 判断当前是否存在有效的播放列表。
func has_playback_queue() -> bool:
	return not get_playback_track_ids().is_empty()

## 按顺序替换播放列表，并设置当前播放项。
func set_playback_queue(track_ids: Array[String], start_queue_index: int = 0) -> bool:
	var resolved_track_ids := _sanitize_track_ids(track_ids)
	if resolved_track_ids.is_empty():
		clear_playback_queue()
		return false

	var clamped_queue_index := clampi(start_queue_index, 0, resolved_track_ids.size() - 1)
	var current_track_id := resolved_track_ids[clamped_queue_index]

	set_playback_track_ids(resolved_track_ids)
	set_playback_queue_index(clamped_queue_index)
	set_selected_track_id(current_track_id)
	return true

## 清空播放列表并复位游标。
func clear_playback_queue() -> void:
	set_playback_track_ids([])
	set_playback_queue_index(0)
	set_selected_track_id("")
	set_is_playing(false)
	request_audio_sync()

## 基于单首曲目构建播放列表。
func set_single_track_queue(track_id: String) -> bool:
	return set_playback_queue([track_id], 0)

## 从当前播放列表游标解析当前曲目 ID。
func get_current_playback_track_id() -> String:
	var playback_track_ids := get_playback_track_ids()
	if playback_track_ids.is_empty():
		return ""

	var queue_index := clampi(get_playback_queue_index(), 0, playback_track_ids.size() - 1)
	return playback_track_ids[queue_index]

## 返回当前播放列表对应的当前曲目对象。
func get_current_playback_track() -> TrackData:
	return get_track_by_id(get_current_playback_track_id())

## 查找某个曲目在当前播放列表中的槽位。
func find_queue_index_for_track(track_id: String) -> int:
	var playback_track_ids := get_playback_track_ids()
	for index in playback_track_ids.size():
		if playback_track_ids[index] == track_id:
			return index
	return -1

## 基于游标偏移切换到播放列表中的上一首或下一首。
func step_queue(offset: int, autoplay: bool = true) -> bool:
	var playback_track_ids := get_playback_track_ids()
	if playback_track_ids.is_empty():
		return false

	var next_queue_index := _resolve_step_target_index(offset)
	return play_queue_index(next_queue_index, autoplay)

## 根据当前播放模式，在曲目结束后自动推进到下一首。
func advance_after_finish() -> bool:
	var playback_track_ids := get_playback_track_ids()
	if playback_track_ids.is_empty():
		return false

	var current_queue_index := clampi(get_playback_queue_index(), 0, playback_track_ids.size() - 1)
	match get_playback_mode():
		MusicAppStateDataType.PlaybackMode.REPEAT_ONE:
			return play_queue_index(current_queue_index, true)
		MusicAppStateDataType.PlaybackMode.SHUFFLE:
			return play_queue_index(_pick_random_queue_index(true), true)
		_:
			return play_queue_index(posmod(current_queue_index + 1, playback_track_ids.size()), true)

## 播放播放列表中指定槽位的曲目。
func play_queue_index(queue_index: int, autoplay: bool = true) -> bool:
	var playback_track_ids := get_playback_track_ids()
	if playback_track_ids.is_empty():
		return false
	if queue_index < 0 or queue_index >= playback_track_ids.size():
		return false

	set_playback_queue_index(queue_index)
	set_selected_track_id(playback_track_ids[queue_index])
	set_elapsed_seconds(get_current_duration_preview_start())
	set_is_playing(autoplay)
	request_audio_sync()
	return true

## 从播放队列中移除指定槽位的曲目。
func remove_track_from_queue(queue_index: int) -> bool:
	var playback_track_ids := get_playback_track_ids()
	if queue_index < 0 or queue_index >= playback_track_ids.size():
		return false

	if playback_track_ids.size() == 1:
		clear_playback_queue()
		return true

	var current_queue_index := clampi(get_playback_queue_index(), 0, playback_track_ids.size() - 1)
	var is_removing_current := queue_index == current_queue_index
	var next_queue := get_playback_track_ids()
	next_queue.remove_at(queue_index)

	if next_queue.is_empty():
		clear_playback_queue()
		return true

	var next_queue_index := current_queue_index
	if queue_index < current_queue_index:
		next_queue_index -= 1
	elif is_removing_current:
		next_queue_index = mini(queue_index, next_queue.size() - 1)

	set_playback_track_ids(next_queue)
	set_playback_queue_index(next_queue_index)
	set_selected_track_id(next_queue[next_queue_index])
	if is_removing_current:
		set_elapsed_seconds(_get_preview_start_for_track_id(next_queue[next_queue_index]))
	request_audio_sync()
	return true

## 根据当前曲目获取默认起播进度。
func get_current_duration_preview_start() -> int:
	var track := get_current_playback_track()
	return track.preview_start if track != null else 0

## 将播放列表中不存在的曲目追加到末尾。
func append_tracks_to_queue(track_ids: Array[String]) -> int:
	var next_queue := get_playback_track_ids()
	var existing := {}
	for track_id in next_queue:
		existing[track_id] = true

	var appended_count := 0
	for track_id in _sanitize_track_ids(track_ids):
		if existing.has(track_id):
			continue
		existing[track_id] = true
		next_queue.append(track_id)
		appended_count += 1

	if appended_count > 0:
		set_playback_track_ids(next_queue)
	return appended_count

## 将单曲放到播放队列顶部并立即切到该曲目。
func play_track_at_queue_top(track_id: String, autoplay: bool = true) -> bool:
	var sanitized := _sanitize_track_ids([track_id])
	if sanitized.is_empty():
		return false

	var resolved_track_id := sanitized[0]
	var next_queue := get_playback_track_ids()
	for index in range(next_queue.size() - 1, -1, -1):
		if next_queue[index] == resolved_track_id:
			next_queue.remove_at(index)

	next_queue.push_front(resolved_track_id)
	set_playback_track_ids(next_queue)
	return play_queue_index(0, autoplay)

## 返回播放模式对应的文案 key。
func get_playback_mode_label_key() -> String:
	match get_playback_mode():
		MusicAppStateDataType.PlaybackMode.REPEAT_ONE:
			return "music_app.queue.mode.repeat_one"
		MusicAppStateDataType.PlaybackMode.SHUFFLE:
			return "music_app.queue.mode.shuffle"
		_:
			return "music_app.queue.mode.loop_all"

## 返回播放模式对应的图标。
func get_playback_mode_icon() -> Texture2D:
	match get_playback_mode():
		MusicAppStateDataType.PlaybackMode.REPEAT_ONE:
			return MusicAppIconsType.REPEAT_ONE
		MusicAppStateDataType.PlaybackMode.SHUFFLE:
			return MusicAppIconsType.SHUFFLE
		_:
			return MusicAppIconsType.LOOP_ALL

## 覆盖写入当前播放队列的曲目 ID 数组。
func set_playback_track_ids(track_ids: Array[String]) -> void:
	var copied_ids: Array[String] = []
	for track_id in track_ids:
		copied_ids.append(track_id)
	get_playback_state().track_ids = copied_ids

## 过滤非法曲目 ID，确保播放队列只包含有效曲目。
func _sanitize_track_ids(track_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for track_id in track_ids:
		var normalized_id := track_id.strip_edges()
		if normalized_id.is_empty() or get_track_by_id(normalized_id) == null:
			continue
		result.append(normalized_id)
	return result

func _resolve_step_target_index(offset: int) -> int:
	var playback_track_ids := get_playback_track_ids()
	if playback_track_ids.is_empty():
		return -1

	if get_playback_mode() == MusicAppStateDataType.PlaybackMode.SHUFFLE:
		return _pick_random_queue_index(true)
	return posmod(get_playback_queue_index() + offset, playback_track_ids.size())

func _pick_random_queue_index(exclude_current: bool) -> int:
	var queue_size := get_playback_track_count()
	if queue_size <= 0:
		return -1

	var current_queue_index := clampi(get_playback_queue_index(), 0, queue_size - 1)
	if queue_size == 1:
		return current_queue_index
	if not exclude_current:
		return randi() % queue_size
	return posmod(current_queue_index + 1 + (randi() % (queue_size - 1)), queue_size)

func _get_preview_start_for_track_id(track_id: String) -> int:
	var track := get_track_by_id(track_id)
	return track.preview_start if track != null else 0

## 返回曲目展示所需的歌手文案。
func _get_track_display_artist(track: TrackData) -> String:
	if not track.artist.is_empty():
		return track.artist
	if not track.subtitle.is_empty():
		return track.subtitle
	return "Local"
