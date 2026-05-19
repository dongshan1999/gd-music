class_name MusicAppPluginBrowserController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const MAX_SEARCH_HISTORY := 10
var last_error := ""

## 返回插件搜索历史。
func get_plugin_search_history() -> Array[String]:
	var result: Array[String] = []
	for item in get_app_state().plugin_search_history:
		result.append(item)
	return result

## 将搜索关键字写入历史，自动去重并限制数量。
func push_plugin_search_history(query: String) -> void:
	var normalized_query := query.strip_edges()
	if normalized_query.is_empty():
		return

	var next_history := get_plugin_search_history()
	next_history.erase(normalized_query)
	next_history.push_front(normalized_query)
	if next_history.size() > MAX_SEARCH_HISTORY:
		next_history.resize(MAX_SEARCH_HISTORY)
	get_app_state().plugin_search_history = next_history

## 删除单个搜索历史。
func remove_plugin_search_history(query: String) -> void:
	var normalized_query := query.strip_edges()
	if normalized_query.is_empty():
		return
	var next_history := get_plugin_search_history()
	next_history.erase(normalized_query)
	get_app_state().plugin_search_history = next_history

## 清空插件搜索历史。
func clear_plugin_search_history() -> void:
	if get_app_state().plugin_search_history.is_empty():
		return
	get_app_state().plugin_search_history = []

## 刷新外部 GDScript 插件目录并重新加载插件列表。
func refresh_music_plugins() -> bool:
	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return false
	var ok := await plugin_controller.refresh_plugins()
	last_error = plugin_controller.last_error
	return ok

## 控制器进入后预热外部插件目录。
func auto_refresh_music_plugins() -> void:
	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		return
	await plugin_controller.refresh_plugins()

## 解析指定插件曲目的可播放音频源。
func resolve_track_plugin_source(track_index: int, quality: String = "standard") -> Dictionary:
	var track := _get_track(track_index)
	if track == null:
		last_error = "Track index is out of range."
		return {}
	if track == null or not track.is_plugin_track():
		last_error = "Selected track is not a plugin track."
		return {}

	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return {}

	var result: Dictionary = await plugin_controller.get_media_source(track, quality)
	last_error = plugin_controller.last_error
	if not result.is_empty():
		track.apply_plugin_source(result)
	return result

## 解析指定插件曲目的歌词数据。
func resolve_track_plugin_lyric(track_index: int) -> Dictionary:
	var track := _get_track(track_index)
	if track == null:
		last_error = "Track index is out of range."
		return {}
	if track == null or not track.is_plugin_track():
		last_error = "Selected track is not a plugin track."
		return {}

	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		last_error = "Music plugin controller is not available."
		return {}

	var result: Dictionary = await plugin_controller.get_lyric(track)
	last_error = plugin_controller.last_error
	if not result.is_empty():
		track.apply_plugin_lyric(result)
	return result

## 根据全量曲目索引返回曲目对象。
func _get_track(track_index: int) -> TrackData:
	var tracks: Array[TrackData] = get_tracks_ref()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]
