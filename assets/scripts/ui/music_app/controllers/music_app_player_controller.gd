class_name MusicAppPlayerController
extends "res://assets/scripts/ui/music_app/controllers/music_app_controller_base.gd"

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

## 将播放进度跳转到指定秒数。
func seek_to_elapsed_seconds(value: int, persist_state: bool = true) -> void:
	var playback_state_controller = get_playback_state_controller()
	if playback_state_controller != null:
		playback_state_controller.seek_to_elapsed_seconds(value, persist_state)

## 按比例跳转播放器进度。
func seek_to_progress_ratio(progress_ratio: float, persist_state: bool = true) -> void:
	var duration := get_current_duration()
	if duration <= 0:
		seek_to_elapsed_seconds(0, persist_state)
		return
	var target_seconds := roundi(clampf(progress_ratio, 0.0, 1.0) * float(duration))
	seek_to_elapsed_seconds(target_seconds, persist_state)

## 返回播放器展示用的歌手文案。
## 返回播放器展示用的标题文案，空标题回退到文件名。
func get_track_display_title(track: TrackData) -> String:
	if track == null:
		return ""
	if not track.title.is_empty():
		return track.title
	if not track.file_path.is_empty():
		return track.file_path.get_file().get_basename()
	return tr("music_app.player.empty_title")

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
	return is_track_liked(track)

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

## 返回当前播放模式对应的文案 key。
func get_playback_mode_label_key() -> String:
	var playback_controller = get_playback_controller()
	if playback_controller == null:
		return "music_app.queue.mode.loop_all"
	return playback_controller.get_playback_mode_label_key()

## 返回当前播放模式对应的图标。
func get_playback_mode_icon() -> Texture2D:
	var playback_controller = get_playback_controller()
	return playback_controller.get_playback_mode_icon() if playback_controller != null else null

## 切换播放器的全局播放模式。
func cycle_playback_mode() -> int:
	var playback_controller = get_playback_controller()
	return (
		playback_controller.cycle_playback_mode()
		if playback_controller != null
		else MusicAppStateDataType.PlaybackMode.LOOP_ALL
	)

## 切换当前播放曲目的收藏状态。
func toggle_like_current_track() -> bool:
	if not has_tracks():
		return false

	var track := get_current_track()
	if track == null:
		return false

	var next_state := toggle_track_liked(track)
	var home_popup = get_popup_router_controller().get_popup(DX_PopupRegistry.PopupId.MUSIC_APP_HOME)
	if home_popup != null and home_popup.has_method("refresh"):
		home_popup.refresh()
	show_toast(
		tr("music_app.toast.favorite_added")
		if next_state
		else tr("music_app.toast.favorite_removed")
	)
	return next_state

## 展示当前播放队列弹窗。
func show_playback_queue() -> void:
	show_popup(DX_PopupRegistry.PopupId.MUSIC_APP_PLAYBACK_QUEUE)

## 返回曲目的封面来源（插件给的地址，或本地音频里内嵌的封面缓存路径）。
func get_track_artwork_source(track: TrackData) -> String:
	var playback_state_controller = get_playback_state_controller()
	if playback_state_controller == null or track == null:
		return ""
	return playback_state_controller.get_track_artwork_source(track)

## 跨平台拉取远程二进制：Android 走 Java 原生通道，桌面走 HTTPRequest。
func fetch_remote_bytes(url: String) -> PackedByteArray:
	var playback_state_controller = get_playback_state_controller()
	if playback_state_controller == null:
		return PackedByteArray()
	return await playback_state_controller.fetch_remote_bytes(url)

