class_name MusicAppPluginBrowserController
extends "res://scripts/ui/music_app/controllers/music_app_controller_base.gd"

const MAX_SEARCH_HISTORY := 10

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
	save_app_state()

## 删除单个搜索历史。
func remove_plugin_search_history(query: String) -> void:
	var normalized_query := query.strip_edges()
	if normalized_query.is_empty():
		return
	var next_history := get_plugin_search_history()
	next_history.erase(normalized_query)
	get_app_state().plugin_search_history = next_history
	save_app_state()

## 清空插件搜索历史。
func clear_plugin_search_history() -> void:
	if get_app_state().plugin_search_history.is_empty():
		return
	get_app_state().plugin_search_history = []
	save_app_state()

## 启动本地音乐插件宿主服务。
func start_music_plugin_host() -> Dictionary:
	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		return build_plugin_error("Music plugin controller is not available.")
	return await plugin_controller.start_local_host()

## 按配置尝试自动启动本地音乐插件宿主服务。
func auto_start_music_plugin_host() -> void:
	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		return
	await plugin_controller.auto_start_local_host()


## 调用指定插件执行音乐搜索。
func search_music_plugin(plugin_id: String, query: String, page: int = 1, media_type: String = "music") -> Dictionary:
	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		return build_plugin_error("Music plugin controller is not available.")
	return await plugin_controller.search(plugin_id, query, page, media_type)

## 解析指定插件曲目的可播放音频源。
func resolve_track_plugin_source(track_index: int, quality: String = "standard") -> Dictionary:
	var track := _get_track(track_index)
	if track == null:
		return build_plugin_error("Track index is out of range.")
	if track == null or not track.is_plugin_track():
		return build_plugin_error("Selected track is not a plugin track.")

	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		return build_plugin_error("Music plugin controller is not available.")

	var result: Dictionary = await plugin_controller.get_media_source(track, quality)
	if bool(result.get("ok", false)) and result.get("data", null) is Dictionary:
		track.apply_plugin_source(result.data)
		save_app_state()
	return result

## 解析指定插件曲目的歌词数据。
func resolve_track_plugin_lyric(track_index: int) -> Dictionary:
	var track := _get_track(track_index)
	if track == null:
		return build_plugin_error("Track index is out of range.")
	if track == null or not track.is_plugin_track():
		return build_plugin_error("Selected track is not a plugin track.")

	var plugin_controller = get_plugin_controller()
	if plugin_controller == null:
		return build_plugin_error("Music plugin controller is not available.")

	var result: Dictionary = await plugin_controller.get_lyric(track)
	if bool(result.get("ok", false)) and result.get("data", null) is Dictionary:
		track.apply_plugin_lyric(result.data)
		save_app_state()
	return result

## 构造统一格式的插件错误返回。
func build_plugin_error(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "error": message}
	for key in extra.keys():
		result[key] = extra[key]
	return result

## 根据全量曲目索引返回曲目对象。
func _get_track(track_index: int) -> TrackData:
	var tracks: Array[TrackData] = get_tracks_ref()
	if track_index < 0 or track_index >= tracks.size():
		return null
	return tracks[track_index]
