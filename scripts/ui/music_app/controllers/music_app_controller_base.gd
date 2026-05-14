class_name MusicAppControllerBase
extends RefCounted

const MusicAppShowcaseControllerScript := preload("res://scripts/ui/music_app/music_app_showcase.gd")
const MusicAppStateDataType := preload("res://scripts/save/music/music_app_state_data.gd")

static var _fallback_state = MusicAppStateDataType.new()

var controller

## 初始化控制器，并记录所属的 showcase 实例。
func _init(owner = null) -> void:
	controller = owner

## 返回当前控制器关联的 showcase，未显式注入时回退到单例实例。
func get_showcase():
	if controller != null:
		return controller
	return MusicAppShowcaseControllerScript.instance

## 返回全局存档管理器。
func get_save_manager() -> DX_SaveManager:
	return DX.save as DX_SaveManager

## 返回音乐应用存档状态，不存在时回退到内存态。
func get_app_state() -> MusicAppStateData:
	var save_manager := get_save_manager()
	if save_manager != null and save_manager.data != null:
		if save_manager.data.music == null:
			save_manager.data.music = MusicAppStateDataType.new()
		return save_manager.data.music
	return _fallback_state

## 返回全局播放列表控制器。
func get_playback_controller():
	var resolved_controller = get_showcase()
	return resolved_controller._playback_controller if resolved_controller != null else null

## 返回全局当前播放状态控制器。
func get_playback_state_controller():
	var resolved_controller = get_showcase()
	return resolved_controller._playback_state_controller if resolved_controller != null else null

## 返回全局歌单与收藏同步控制器。
func get_playlist_state_controller():
	var resolved_controller = get_showcase()
	return resolved_controller._playlist_state_controller if resolved_controller != null else null

## 返回全局弹窗路由控制器。
func get_popup_router_controller():
	var resolved_controller = get_showcase()
	return resolved_controller._popup_router_controller if resolved_controller != null else null

## 返回全局插件控制器。
func get_plugin_controller():
	var resolved_controller = get_showcase()
	return resolved_controller._plugin_controller if resolved_controller != null else null

## 返回曲目数组引用，供子控制器直接读写全局状态。
func get_tracks_ref() -> Array[TrackData]:
	return get_app_state().tracks

## 返回播放队列索引数组引用。
func get_playback_track_indices_ref() -> Array[int]:
	return get_app_state().playback_track_indices

## 返回歌单数组引用。
func get_playlists_ref() -> Array[PlaylistData]:
	return get_app_state().playlists

## 返回当前选中的歌单索引。
func get_selected_playlist_index() -> int:
	return get_app_state().selected_playlist_index

## 设置当前选中的歌单索引。
func set_selected_playlist_index(value: int) -> void:
	get_app_state().selected_playlist_index = value

## 返回当前选中的曲目索引。
func get_selected_track_index() -> int:
	return get_app_state().selected_track_index

## 设置当前选中的曲目索引。
func set_selected_track_index(value: int) -> void:
	get_app_state().selected_track_index = value

## 返回播放队列当前游标。
func get_playback_queue_index() -> int:
	return get_app_state().playback_queue_index

## 设置播放队列当前游标。
func set_playback_queue_index(value: int) -> void:
	get_app_state().playback_queue_index = value

## 返回当前全局播放模式。
func get_playback_mode() -> int:
	return get_app_state().playback_mode

## 设置当前全局播放模式。
func set_playback_mode(value: int) -> void:
	get_app_state().playback_mode = value

## 返回当前累计播放秒数。
func get_elapsed_seconds() -> int:
	return get_app_state().elapsed_seconds

## 设置当前累计播放秒数。
func set_elapsed_seconds(value: int) -> void:
	get_app_state().elapsed_seconds = value

## 返回当前是否处于播放态。
func is_playing() -> bool:
	return get_app_state().is_playing

## 设置当前播放态标记。
func set_is_playing(value: bool) -> void:
	get_app_state().is_playing = value

## 返回已收藏曲目映射表。
func get_liked_tracks() -> Dictionary:
	return get_app_state().liked_tracks

## 设置已收藏曲目映射表。
func set_liked_tracks(value: Dictionary) -> void:
	get_app_state().liked_tracks = value

## 触发 showcase 持久化当前音乐应用状态。
func save_app_state() -> void:
	var save_manager := get_save_manager()
	if save_manager != null:
		save_manager.save_data()

## 请求 showcase 同步底层音频播放器状态。
func request_audio_sync() -> void:
	var playback_state_controller = get_playback_state_controller()
	if playback_state_controller != null:
		playback_state_controller.request_audio_sync()

## 打开指定弹窗并返回弹窗实例。
func show_popup(popup_id: int):
	var popup_router_controller = get_popup_router_controller()
	if popup_router_controller == null:
		return null
	return popup_router_controller.show_popup(popup_id)

## 弹出通用提示对话框。
func show_common_alert(title: String, message: String) -> void:
	var popup_router_controller = get_popup_router_controller()
	if popup_router_controller != null:
		popup_router_controller.show_common_alert(title, message)

## 弹出底部轻提示。
func show_toast(message: String) -> void:
	var popup_router_controller = get_popup_router_controller()
	if popup_router_controller != null:
		popup_router_controller.show_toast(message)

## 根据收藏状态同步系统“我喜欢”歌单。
func sync_favorite_playlist_from_likes() -> void:
	var playlist_state_controller = get_playlist_state_controller()
	if playlist_state_controller != null:
		playlist_state_controller.sync_favorite_playlist_from_likes()

## 返回曲目的全局唯一标识。
func track_key(track: TrackData) -> String:
	var playlist_state_controller = get_playlist_state_controller()
	if playlist_state_controller != null:
		return playlist_state_controller.track_key(track)
	return ""

## 判断当前是否存在任何曲目数据。
func has_tracks() -> bool:
	return not get_tracks_ref().is_empty()

## 返回当前选中曲目对象，越界时返回 null。
func get_current_track():
	var tracks: Array[TrackData] = get_tracks_ref()
	var selected_track_index := get_selected_track_index()
	if selected_track_index < 0 or selected_track_index >= tracks.size():
		return null
	return tracks[selected_track_index]

## 返回当前选中曲目的时长，未选中时返回 0。
func get_current_duration() -> int:
	var track = get_current_track()
	return track.duration if track != null else 0
