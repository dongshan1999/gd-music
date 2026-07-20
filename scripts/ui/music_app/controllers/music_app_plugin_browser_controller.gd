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

## 将搜索结果条目导入为全局曲目，并返回对应曲目索引。
func ensure_plugin_track_from_search_result(_item: Dictionary, _plugin_id: String) -> int:
	return -1

## 将一组搜索结果按当前顺序导入为全局曲目索引列表。
func ensure_plugin_tracks_from_search_results(_items: Array[Dictionary], _plugin_id: String) -> Array[int]:
	return []

## 按搜索页语义播放单曲：空队列播放全部结果，非空队列把当前单曲放到队首播放。
func play_search_result(
	_items: Array[Dictionary],
	_selected_result_index: int,
	_plugin_id: String
) -> bool:
	push_warning("Plugin playback is disabled in the local-only save format.")
	return false

## 刷新外部 GDScript 插件目录并重新加载插件列表。
func refresh_music_plugins() -> bool:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		push_error("Music plugin controller is not available.")
		return false
	var ok: bool = plugin_controller.refresh_plugins()
	if not ok and not plugin_controller.last_error.is_empty():
		push_error(plugin_controller.last_error)
	return ok

## 控制器进入后预热外部插件目录。
func auto_refresh_music_plugins() -> void:
	var plugin_controller: MusicAppPluginController = get_plugin_controller()
	if plugin_controller == null:
		return
	plugin_controller.refresh_plugins()

## 解析指定插件曲目的可播放音频源。
func resolve_track_plugin_source(_track_id: String, _quality: String = "standard") -> Dictionary:
	return {}

## 解析指定插件曲目的歌词数据。
func resolve_track_plugin_lyric(_track_id: String) -> Dictionary:
	return {}
