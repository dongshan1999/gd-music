class_name MusicAppPlaybackQueueController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 返回当前是否存在可展示的播放队列。
func has_tracks() -> bool:
	var playback_controller = get_playback_controller()
	return playback_controller != null and playback_controller.has_playback_queue()

func get_queue_track_count() -> int:
	var playback_controller = get_playback_controller()
	return playback_controller.get_playback_track_count() if playback_controller != null else 0

func get_current_queue_index() -> int:
	var playback_controller = get_playback_controller()
	return playback_controller.get_playback_queue_index() if playback_controller != null else -1

func get_playback_mode_label_key() -> String:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return "music_app.queue.mode.loop_all"
	return playback_controller.get_playback_mode_label_key()

func get_playback_mode_icon() -> Texture2D:
	var playback_controller = get_playback_controller()
	return playback_controller.get_playback_mode_icon() if playback_controller != null else null

func cycle_playback_mode() -> int:
	var playback_controller = get_playback_controller()
	return playback_controller.cycle_playback_mode() if playback_controller != null else 0

func clear_queue() -> void:
	var playback_controller = get_playback_controller()
	if playback_controller != null:
		playback_controller.clear_playback_queue()

func play_queue_track(queue_index: int) -> bool:
	var playback_controller = get_playback_controller()
	return playback_controller.play_queue_index(queue_index, true) if playback_controller != null else false

func remove_queue_track(queue_index: int) -> bool:
	var playback_controller = get_playback_controller()
	return playback_controller.remove_track_from_queue(queue_index) if playback_controller != null else false

## 将当前播放队列转换成供界面直接渲染的行数据。
func get_queue_rows() -> Array[Dictionary]:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return []

	var queue_track_ids: Array[String] = get_playback_track_ids_ref()
	var current_queue_index := get_playback_queue_index()
	var rows: Array[Dictionary] = []

	for queue_index in queue_track_ids.size():
		var track: TrackData = get_track_by_id(queue_track_ids[queue_index])
		if track == null:
			continue
		rows.append({
			"queue_index": queue_index,
			"title": _get_track_display_title(track),
			"subtitle": _get_track_display_subtitle(track),
			"source": _get_track_source(track),
			"is_current": queue_index == current_queue_index,
		})
	return rows

## 生成播放队列行的标题文案。
func _get_track_display_title(track: TrackData) -> String:
	if not track.title.is_empty():
		return track.title
	if not track.file_path.is_empty():
		return track.file_path.get_file().get_basename()
	return tr("music_app.player.empty_title")

## 生成播放队列行的副标题文案。
func _get_track_display_subtitle(track: TrackData) -> String:
	if not track.artist.is_empty() and not track.subtitle.is_empty() and track.artist != track.subtitle:
		return "%s - %s" % [track.artist, track.subtitle]
	if not track.artist.is_empty():
		return track.artist
	if not track.subtitle.is_empty():
		return track.subtitle
	return tr("music_app.track.local_file")

## 生成播放队列行的来源标签文案。
func _get_track_source(track: TrackData) -> String:
	if not track.source.is_empty():
		return track.source
	return tr("music_app.track.local_file")
