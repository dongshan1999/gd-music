class_name MusicAppControllerBase
extends RefCounted

var controller

## 初始化控制器，并记录所属的 showcase 实例。
func _init(owner = null) -> void:
	controller = owner

## 返回当前控制器关联的 showcase，未显式注入时回退到单例实例。
func get_showcase() -> MusicAppShowcaseController:
	if controller != null:
		return controller
	return MusicAppShowcaseController.instance

## 返回曲目数组引用，供子控制器直接读写全局状态。
func get_tracks_ref() -> Array:
	var resolved_controller := get_showcase()
	return resolved_controller._tracks if resolved_controller != null else []

## 返回播放队列索引数组引用。
func get_playback_track_indices_ref() -> Array:
	var resolved_controller := get_showcase()
	return resolved_controller._playback_track_indices if resolved_controller != null else []

## 返回歌单数组引用。
func get_playlists_ref() -> Array:
	var resolved_controller := get_showcase()
	return resolved_controller._playlists if resolved_controller != null else []

## 返回当前选中的歌单索引。
func get_selected_playlist_index() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._selected_playlist_index if resolved_controller != null else 0

## 设置当前选中的歌单索引。
func set_selected_playlist_index(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._selected_playlist_index = value

## 返回当前选中的曲目索引。
func get_selected_track_index() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._selected_track_index if resolved_controller != null else 0

## 设置当前选中的曲目索引。
func set_selected_track_index(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._selected_track_index = value

## 返回播放队列当前游标。
func get_playback_queue_index() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._playback_queue_index if resolved_controller != null else 0

## 设置播放队列当前游标。
func set_playback_queue_index(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._playback_queue_index = value

## 返回当前累计播放秒数。
func get_elapsed_seconds() -> int:
	var resolved_controller := get_showcase()
	return resolved_controller._elapsed_seconds if resolved_controller != null else 0

## 设置当前累计播放秒数。
func set_elapsed_seconds(value: int) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._elapsed_seconds = value

## 返回当前是否处于播放态。
func is_playing() -> bool:
	var resolved_controller := get_showcase()
	return resolved_controller._is_playing if resolved_controller != null else false

## 设置当前播放态标记。
func set_is_playing(value: bool) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._is_playing = value

## 返回已收藏曲目映射表。
func get_liked_tracks() -> Dictionary:
	var resolved_controller := get_showcase()
	return resolved_controller._liked_tracks if resolved_controller != null else {}

## 设置已收藏曲目映射表。
func set_liked_tracks(value: Dictionary) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._liked_tracks = value

## 通知界面层刷新当前状态。
func notify_state_changed() -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller.notify_state_changed()

## 触发 showcase 持久化当前音乐应用状态。
func save_app_state() -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._save_app_state()

## 请求 showcase 同步底层音频播放器状态。
func request_audio_sync() -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null and resolved_controller.has_method("request_audio_sync"):
		resolved_controller.request_audio_sync()

## 打开指定弹窗并返回弹窗实例。
func show_popup(popup_id: int):
	var resolved_controller := get_showcase()
	if resolved_controller == null:
		return null
	return resolved_controller.show_popup(popup_id)

## 弹出通用提示对话框。
func show_common_alert(title: String, message: String) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._show_common_alert(title, message)

## 弹出底部轻提示。
func show_toast(message: String) -> void:
	var resolved_controller := get_showcase()
	if resolved_controller != null:
		resolved_controller._show_toast(message)

## 判断当前是否存在任何曲目数据。
func has_tracks() -> bool:
	return not get_tracks_ref().is_empty()

## 返回当前选中曲目对象，越界时返回 null。
func get_current_track():
	var tracks := get_tracks_ref()
	var selected_track_index := get_selected_track_index()
	if selected_track_index < 0 or selected_track_index >= tracks.size():
		return null
	return tracks[selected_track_index]

## 返回当前选中曲目的时长，未选中时返回 0。
func get_current_duration() -> int:
	var track = get_current_track()
	return track.duration if track != null else 0
