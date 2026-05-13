class_name MusicAppPlaybackQueueController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

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

func get_queue_rows() -> Array[Dictionary]:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return []

	var queue_track_indices: Array[int] = get_playback_track_indices_ref()
	var tracks: Array[TrackData] = get_tracks_ref()
	var current_queue_index := get_playback_queue_index()
	var rows: Array[Dictionary] = []

	for queue_index in queue_track_indices.size():
		var track_index := int(queue_track_indices[queue_index])
		if track_index < 0 or track_index >= tracks.size():
			continue
		var track: TrackData = tracks[track_index]
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

func _get_track_display_title(track: TrackData) -> String:
	if not track.title.is_empty():
		return track.title
	if not track.file_path.is_empty():
		return track.file_path.get_file().get_basename()
	return tr("music_app.player.empty_title")

func _get_track_display_subtitle(track: TrackData) -> String:
	if not track.artist.is_empty() and not track.subtitle.is_empty() and track.artist != track.subtitle:
		return "%s - %s" % [track.artist, track.subtitle]
	if not track.artist.is_empty():
		return track.artist
	if not track.subtitle.is_empty():
		return track.subtitle
	return tr("music_app.track.local_file")

func _get_track_source(track: TrackData) -> String:
	if not track.source.is_empty():
		return track.source
	return tr("music_app.track.local_file")
