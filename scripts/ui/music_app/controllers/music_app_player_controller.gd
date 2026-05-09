class_name MusicAppPlayerController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

## 判断播放器当前是否存在可播放队列。
func has_tracks() -> bool:
	var playback_controller = get_playback_controller()
	return playback_controller != null and playback_controller.has_playback_queue()

## 返回播放器当前曲目对象。
func get_current_track() -> TrackData:
	var playback_controller = get_playback_controller()
	return playback_controller.get_current_playback_track() if playback_controller != null else null

## 返回当前曲目时长。
func get_current_duration() -> int:
	var track := get_current_track()
	return track.duration if track != null else 0

## 返回当前已播放秒数。
func get_current_elapsed_seconds() -> int:
	return get_elapsed_seconds()

## 返回播放器展示用的歌手文案。
func get_track_display_artist(track: TrackData) -> String:
	if not track.artist.is_empty():
		return track.artist
	if not track.subtitle.is_empty():
		return track.subtitle
	return tr("music_app.track.local_file")

## 判断当前播放曲目是否已收藏。
func is_current_track_liked() -> bool:
	var track := get_current_track()
	if track == null:
		return false
	return bool(get_liked_tracks().get(_track_key(track), false))

## 切换播放器的播放或暂停状态。
func toggle_playback() -> void:
	var playback_state_controller = get_playback_state_controller()
	if playback_state_controller != null:
		playback_state_controller.toggle_playback()

## 切到播放队列中的上一首。
func play_previous_track() -> bool:
	var playback_controller = get_playback_controller()
	return playback_controller.step_queue(-1, true) if playback_controller != null else false

## 切到播放队列中的下一首。
func play_next_track() -> bool:
	var playback_controller = get_playback_controller()
	return playback_controller.step_queue(1, true) if playback_controller != null else false

## 切换当前播放曲目的收藏状态，并同步“我喜欢”歌单。
func toggle_like_current_track() -> bool:
	if not has_tracks():
		return false

	var track := get_current_track()
	if track == null:
		return false

	var liked_tracks: Dictionary = get_liked_tracks().duplicate(true)
	var key := _track_key(track)
	var next_state := not bool(liked_tracks.get(key, false))

	if next_state:
		liked_tracks[key] = true
	else:
		liked_tracks.erase(key)

	set_liked_tracks(liked_tracks)
	sync_favorite_playlist_from_likes()
	save_app_state()
	notify_state_changed()
	show_toast(
		tr("music_app.toast.favorite_added")
		if next_state
		else tr("music_app.toast.favorite_removed")
	)
	return next_state

## 展示当前播放队列弹窗。
func show_playback_queue() -> void:
	var playback_controller = get_playback_controller()
	if playback_controller != null:
		playback_controller.show_playback_queue_dialog()

## 生成曲目的唯一标识，用于收藏状态映射。
func _track_key(track: TrackData) -> String:
	return track_key(track)
